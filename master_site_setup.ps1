# master_site_setup.ps1
# Final all-in-one setup: copy site, create automation files, init git, optional GH push, run diagnostics, create admin placeholder, write report.
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# CONFIG - update these only if your source is in another path
$sourcePath = "C:\Users\Dalmia Computers\Downloads\royal_dalmia_master"
$targetRepo = "C:\dalmiacomputers-automation"
$githubUser = "dalmiacomputers"
$repoName = "dalmiacomputers-automation"
$reportFile = Join-Path $targetRepo "royal_repo_setup_report.txt"

# small helper
function Log([string]$line) {
  $t = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
  $out = "$t`t$line"
  $out | Out-File -FilePath $reportFile -Append -Encoding UTF8
  Write-Host $line
}

# start fresh report
if (Test-Path $reportFile) { Remove-Item $reportFile -Force }
Log "START: master_site_setup"
Log "Source: $sourcePath"
Log "Target repo folder: $targetRepo"

if (-not (Test-Path $sourcePath)) {
  Log "ERROR: Source path not found. Please ensure your project exists at $sourcePath"
  throw "Source not found: $sourcePath"
}

# create target folder
if (-not (Test-Path $targetRepo)) {
  New-Item -Path $targetRepo -ItemType Directory -Force | Out-Null
  Log "Created target folder."
} else {
  Log "Target folder exists; will mirror into it."
}

# copy site into target (robocopy mirror)
Log "Copying site files (robocopy) - this may take a few seconds..."
robocopy $sourcePath $targetRepo /MIR /FFT /Z /R:2 /W:2 | Out-Null
Log "Copy complete."

# ensure public_html exists
$publicHtml = Join-Path $targetRepo "public_html"
if (-not (Test-Path $publicHtml)) {
  # If the source already had public_html inside, robocopy should have created it; otherwise, if source itself IS public_html, move it
  if (Test-Path (Join-Path $targetRepo "index.html")) {
    # source root seems to be public_html files; create public_html and move
    New-Item -Path $publicHtml -ItemType Directory -Force | Out-Null
    Get-ChildItem $targetRepo -File | Where-Object { $_.Name -ne (Split-Path $MyInvocation.MyCommand.Path -Leaf) } | Move-Item -Destination $publicHtml -Force -ErrorAction SilentlyContinue
    Log "Normalized site files into public_html directory."
  } else {
    Log "WARNING: public_html not found under target after copy. Please check your source layout."
  }
} else {
  Log "public_html found."
}

# create .github/workflows folder
$wfDir = Join-Path $targetRepo ".github\workflows"
if (-not (Test-Path $wfDir)) { New-Item -Path $wfDir -ItemType Directory -Force | Out-Null; Log "Created workflows directory." } else { Log "Workflows directory exists." }

# write deploy.yml (single-quoted here-string so PowerShell won't expand ${{ }} tokens)
$deployYml = @'
name: Deploy site (FTP/SSH)

on:
  push:
    branches: [ 'main' ]

jobs:
  diagnostics:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Run diagnostics (simple)
        run: |
          echo "Collecting diagnostics..."
          ls -la public_html || true
          echo "--- top lines of index.html ---"
          head -n 60 public_html/index.html || true
          echo "--- assets ---"
          ls -la public_html/assets || true

      - name: Upload diagnostics as artifact
        uses: actions/upload-artifact@v4
        with:
          name: diagnostics
          path: |
            public_html/index.html
            public_html/assets/**

  deploy_ftp:
    if: ${{ secrets.FTP_HOST && secrets.FTP_USERNAME && secrets.FTP_PASSWORD }}
    runs-on: ubuntu-latest
    needs: diagnostics
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Deploy to FTP (SamKirkland action)
        uses: SamKirkland/FTP-Deploy-Action@4.3.0
        with:
          server: ${{ secrets.FTP_HOST }}
          username: ${{ secrets.FTP_USERNAME }}
          password: ${{ secrets.FTP_PASSWORD }}
          local-dir: public_html
          server-dir: ${{ secrets.FTP_REMOTE_DIR }}
          protocol: ftp

  deploy_ssh:
    if: ${{ secrets.SSH_HOST && secrets.SSH_USER && secrets.SSH_KEY }}
    runs-on: ubuntu-latest
    needs: diagnostics
    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Setup SSH key
        run: |
          mkdir -p ~/.ssh
          echo "${{ secrets.SSH_KEY }}" > ~/.ssh/deploy_key
          chmod 600 ~/.ssh/deploy_key

      - name: Rsync over SSH
        run: |
          rsync -avz --delete -e "ssh -i ~/.ssh/deploy_key -o StrictHostKeyChecking=no" public_html/ ${{ secrets.SSH_USER }}@${{ secrets.SSH_HOST }}:${{ secrets.SSH_REMOTE_DIR }}
'@
$deployPath = Join-Path $wfDir "deploy.yml"
Set-Content -Path $deployPath -Value $deployYml -Encoding UTF8
Log "Wrote GitHub Actions workflow to $deployPath"

# create local deploy helper (deploy.ps1) using single-quoted here-string
$deployPs = @'
param(
  [string]$EnvFile = "$PSScriptRoot\ftp_credentials_example.env"
)
if (Test-Path $EnvFile) {
  Get-Content $EnvFile | ForEach-Object {
    if ($_ -match "^\s*([^#=]+)=(.*)") { $k=$matches[1].Trim(); $v=$matches[2].Trim(); $env:$k = $v }
  }
}
$host = $env:FTP_HOST
$user = $env:FTP_USERNAME
$pass = $env:FTP_PASSWORD
$remote = $env:FTP_REMOTE_DIR
$local = Join-Path $PSScriptRoot "public_html"

if (-not (Test-Path $local)) { Write-Error "Local public_html not found: $local"; exit 1 }
if (-not (Get-Command winscp.com -ErrorAction SilentlyContinue)) {
  Write-Error "WinSCP not found in PATH. Install WinSCP and ensure winscp.com is usable."; exit 1
}

$script = "open ftp://$user:$pass@$host`noption transfer binary`ncd $remote`nlcd $local`nput -r *`nclose`nexit`n"
$scriptFile = [System.IO.Path]::GetTempFileName()
Set-Content -Path $scriptFile -Value $script -Encoding ASCII
Write-Host "Running WinSCP..."
winscp.com /script=$scriptFile | Tee-Object -Variable out
if ($LASTEXITCODE -eq 0) { Write-Host "Deploy complete." } else { Write-Host "Deploy finished with code $LASTEXITCODE" }
Remove-Item $scriptFile -Force
'@
Set-Content -Path (Join-Path $targetRepo "deploy.ps1") -Value $deployPs -Encoding UTF8
Log "Wrote local deploy helper: deploy.ps1"

# diagnostics.ps1
$diag = @'
$root = Join-Path $PSScriptRoot 'public_html'
$report = Join-Path $PSScriptRoot 'diagnostics_local_report.txt'
Remove-Item $report -ErrorAction SilentlyContinue
function L($m){ "$((Get-Date).ToString('s'))`t$m" | Out-File -FilePath $report -Append -Encoding UTF8 }
L "Diagnostics start"
if (-not (Test-Path $root)) { L "ERROR: public_html missing"; exit 1 }
L "Listing public_html"
Get-ChildItem $root -Recurse -Force | Sort-Object FullName | ForEach-Object { L $_.FullName }
L "Top of index.html"
Get-Content (Join-Path $root 'index.html') -TotalCount 80 | ForEach-Object { L $_.Replace("`t","    ") }
L "Assets folder"
Get-ChildItem (Join-Path $root 'assets') | ForEach-Object { L ("{0} - {1} bytes" -f $_.Name,$_.Length) }
L "Diagnostics end"
Write-Host "Diagnostics written to $report"
'@
Set-Content -Path (Join-Path $targetRepo "diagnostics.ps1") -Value $diag -Encoding UTF8
Log "Wrote diagnostics script."

# ftp_credentials_example.env
$envTxt = @'
FTP_HOST=ftp.yourdomain.com
FTP_USERNAME=yourftpuser
FTP_PASSWORD=yourftppassword
FTP_REMOTE_DIR=/public_html/
'@
Set-Content -Path (Join-Path $targetRepo "ftp_credentials_example.env") -Value $envTxt -Encoding UTF8
Log "Wrote ftp_credentials_example.env (edit with your credentials or use GitHub Secrets)"

# README-DEPLOY.md
$readme = @'
Quick deploy:

1) Put FTP creds into ftp_credentials_example.env (or use GitHub Secrets).
2) For local deploy: install WinSCP and run: powershell -File .\deploy.ps1
3) For CI deploy: push to GitHub and set repository Actions secrets:
   FTP_HOST, FTP_USERNAME, FTP_PASSWORD, FTP_REMOTE_DIR
'@
Set-Content -Path (Join-Path $targetRepo "README-DEPLOY.md") -Value $readme -Encoding UTF8
Log "Wrote README-DEPLOY.md"

# ADMIN placeholder (simple admin/README and placeholder creds file)
$adminDir = Join-Path $targetRepo "admin"
if (-not (Test-Path $adminDir)) { New-Item -Path $adminDir -ItemType Directory -Force | Out-Null; Log "Created admin folder." }
$adminReadme = @'
ADMIN PLACEHOLDER
=================

This folder is a placeholder for admin tools (login, site management, content edits).

Files to create here later:
- admin/index.html  -> Admin dashboard (protected)
- admin/.htpasswd   -> Basic auth file (if you host with .htaccess support)
- admin/users.json  -> Admin user list (do NOT store plain passwords)

Default placeholder credentials (change immediately when deploying):
- username: admin
- password: ChangeMe123!

Next steps for admin setup:
1) Implement authentication (HTTP Basic, JWT, or your CMS).
2) Move sensitive config (FTP creds, API keys) into GitHub Secrets or server env.
3) Use diagnostics.ps1 to verify site health after deploy.
'@
Set-Content -Path (Join-Path $adminDir "README-ADMIN.txt") -Value $adminReadme -Encoding UTF8
Log "Wrote admin placeholder README"

# Initialize git if not already
Push-Location $targetRepo
if (-not (Test-Path ".git")) {
  git init | Out-Null
  git add --all
  git commit -m "Initial site + automation bootstrap" | Out-Null
  Log "Initialized git and created initial commit."
} else {
  Log "Git repo already initialized."
}

# Attempt GH create + push if gh exists and user likely logged in
$gh = Get-Command gh -ErrorAction SilentlyContinue
if ($gh) {
  try {
    Write-Host "Attempting to create remote repo via gh CLI..."
    gh repo create "$githubUser/$repoName" --public --source $targetRepo --remote origin --push --description "Royal Dalmia site + automation" | Out-Null
    Log "GitHub repo created and pushed via gh CLI: https://github.com/$githubUser/$repoName"
  } catch {
    Log "gh CLI present but creation failed: $($_.ToString())"
    Log "Please run manual push commands (printed below)."
    Write-Host ""
    Write-Host "MANUAL commands to run from inside $targetRepo :"
    Write-Host "git remote add origin https://github.com/$githubUser/$repoName.git"
    Write-Host "git branch -M main"
    Write-Host "git push -u origin main"
  }
} else {
  Log "gh CLI not detected. To publish, run these commands from $targetRepo:"
  Write-Host ""
  Write-Host "cd `"$targetRepo`""
  Write-Host "git remote add origin https://github.com/$githubUser/$repoName.git"
  Write-Host "git branch -M main"
  Write-Host "git push -u origin main"
  Log "Manual push instructions printed to console."
}

Pop-Location

# Run diagnostics script to produce diagnostics_local_report.txt
try {
  Write-Host "Running local diagnostics..."
  powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $targetRepo "diagnostics.ps1")
  $diagReport = Join-Path $targetRepo "diagnostics_local_report.txt"
  if (Test-Path $diagReport) {
    Log "Diagnostics produced: $diagReport"
  } else {
    Log "Diagnostics script did not produce expected report."
  }
} catch {
  Log "Failed to run diagnostics: $($_.ToString())"
}

Log "FINISH: master_site_setup"
Log "Final report saved at: $reportFile"
Write-Host ""
Write-Host "Setup complete. Open the report file:"
Write-Host $reportFile
