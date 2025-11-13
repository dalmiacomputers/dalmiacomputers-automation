# BEGIN FIXED SCRIPT
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

# CONFIG
$localSrc = "C:\Users\Dalmia Computers\Downloads\royal_dalmia_master"
$repoDir  = "C:\dalmiacomputers-automation"
$repoName = "dalmiacomputers-automation"
$githubUser = "dalmiacomputers"
$fullRepoUrl = "https://github.com/$githubUser/$repoName.git"
$now = Get-Date -Format "yyyyMMdd_HHmmss"

function WriteLog($m) {
  $t = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
  Write-Host "$t `t $m"
}

WriteLog "START: setup_and_push"

# Create repo folder
if (-not (Test-Path $repoDir)) {
  New-Item -Path $repoDir -ItemType Directory -Force | Out-Null
  WriteLog "Created folder: $repoDir"
} else {
  WriteLog "Folder exists: $repoDir"
}

# Check source exists
if (-not (Test-Path $localSrc)) {
  Write-Host "ERROR: Source project folder not found: $localSrc"
  Write-Host "Please put your site in that path or edit the script to the correct path."
  exit 1
}

# Copy site into repo folder (mirror)
WriteLog "Copying site files (this may take a few seconds)..."
robocopy $localSrc $repoDir /MIR | Out-Null
WriteLog "Copy complete."

# Create .github/workflows dir
$wfDir = Join-Path $repoDir ".github\workflows"
if (-not (Test-Path $wfDir)) { New-Item -Path $wfDir -ItemType Directory -Force | Out-Null; WriteLog "Created workflows dir." }

# Create deploy.yml using single-quoted here-string to avoid expansion
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
WriteLog "Wrote workflow: $deployPath"

# Create deploy.ps1 (local helper using WinSCP) — single-quoted literal
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

Set-Content -Path (Join-Path $repoDir "deploy.ps1") -Value $deployPs -Encoding UTF8
WriteLog "Wrote local deploy helper: deploy.ps1"

# Create diagnostics.ps1 — single-quoted literal
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

Set-Content -Path (Join-Path $repoDir "diagnostics.ps1") -Value $diag -Encoding UTF8
WriteLog "Wrote diagnostics script."

# Create ftp_credentials_example.env
$envContent = @'
FTP_HOST=ftp.yourdomain.com
FTP_USERNAME=yourftpuser
FTP_PASSWORD=yourftppassword
FTP_REMOTE_DIR=/public_html/
'@
Set-Content -Path (Join-Path $repoDir "ftp_credentials_example.env") -Value $envContent -Encoding UTF8
WriteLog "Wrote ftp_credentials_example.env"

# Create README-DEPLOY.md
$readme = @'
Quick deploy instructions:

1. Put your production FTP credentials into ftp_credentials_example.env (or use GitHub Secrets).
2. If you want CI deploys, push this repo to GitHub and set Actions secrets:
   - FTP_HOST, FTP_USERNAME, FTP_PASSWORD, FTP_REMOTE_DIR
3. For local deploy, install WinSCP and then run: .\deploy.ps1
4. To run diagnostics locally: powershell -File .\diagnostics.ps1
'@
Set-Content -Path (Join-Path $repoDir "README-DEPLOY.md") -Value $readme -Encoding UTF8
WriteLog "Wrote README-DEPLOY.md"

# Initialize git repo and commit
Push-Location $repoDir
if (-not (Test-Path ".git")) {
  git init | Out-Null
  git add .
  git commit -m "Initial site + deploy automation" | Out-Null
  WriteLog "Initialized local git repo and committed."
} else {
  WriteLog "Git repo already initialized."
}

# If gh CLI exists and user is logged in, create remote and push
$gh = (Get-Command gh -ErrorAction SilentlyContinue)
if ($gh) {
  try {
    WriteLog "Detected gh CLI. Attempting to create remote repo on GitHub..."
    gh repo create $githubUser/$repoName --public --source $repoDir --remote origin --push --description "Royal Dalmia site + deploy automation" | Out-Null
    WriteLog "Repo created and pushed to GitHub via gh."
    WriteLog "Repo URL: $fullRepoUrl"
  } catch {
    WriteLog "gh CLI present but failed to auto-create. Error: $($_.ToString())"
    WriteLog "Please run the manual remote commands below."
    WriteHost ""
    WriteHost "Manual commands to run (replace password/token if needed):"
    WriteHost ""
    WriteHost "git remote add origin $fullRepoUrl"
    WriteHost "git branch -M main"
    WriteHost "git push -u origin main"
  }
} else {
  WriteLog "gh CLI not found. To publish this repo to GitHub, run these commands in $repoDir:"
  WriteHost ""
  WriteHost "cd `"$repoDir`""
  WriteHost "git remote add origin $fullRepoUrl"
  WriteHost "git branch -M main"
  WriteHost "git push -u origin main"
  WriteHost ""
  WriteLog "Manual push instructions printed above."
}

Pop-Location

WriteLog "DONE: setup_and_push"
# END FIXED SCRIPT
