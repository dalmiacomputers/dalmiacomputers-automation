# finalize_chhama_automation.ps1
# Finalizes GitHub automation for Dalmia (patches LIVE_ROOT, creates repo, sets secrets, triggers workflow).
# Run from project root. Requires git and gh installed & gh authenticated.
# Does not print secrets; prompts interactively for sensitive values.

Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"

Write-Host "== Dalmia Automation Finalizer ==" -ForegroundColor Cyan
$root = (Get-Location).Path
Write-Host "Working directory: $root"

# 1) Patch LIVE_ROOT in server_deploy.sh
$serverScript = Join-Path $root "scripts\server_deploy.sh"
if (-not (Test-Path $serverScript)) {
    Write-Host "ERROR: scripts/server_deploy.sh not found. Exiting." -ForegroundColor Red
    exit 1
}
# Backup
Copy-Item $serverScript ($serverScript + ".bak") -Force
# Replace the LIVE_ROOT line with confirmed absolute path
(Get-Content $serverScript -Raw) -replace 'LIVE_ROOT="/home/\$USER/public_html"', 'LIVE_ROOT="/home/e5khdkcsrpke/public_html"' | Set-Content $serverScript
Write-Host "Patched scripts/server_deploy.sh -> LIVE_ROOT=/home/e5khdkcsrpke/public_html (backup saved)." -ForegroundColor Green

# 2) Ensure workflows exist (they should, script created earlier)
$workflowDir = Join-Path $root ".github\workflows"
if (-not (Test-Path $workflowDir)) {
    Write-Host "Creating .github/workflows and writing default workflows." -ForegroundColor Yellow
    New-Item -ItemType Directory -Path $workflowDir -Force | Out-Null
    # If needed, you could write files here — but commit_all already created them earlier.
}

# 3) Ensure git repo & commit
if (-not (Test-Path (Join-Path $root ".git"))) {
    Write-Host "Initializing git repository..."
    git init | Out-Null
} else {
    Write-Host "Git repository already present."
}

git add -A
# commit only if changes
try {
    git commit -m "chhama: finalize automation (patch LIVE_ROOT & add GH workflows/secrets)" 2>$null
    Write-Host "Committed changes." -ForegroundColor Green
} catch {
    Write-Host "No new changes to commit (or commit failed due to no changes)." -ForegroundColor Yellow
}

# 4) Ensure remote origin exists; if not, create repo on GH using gh and push
$remoteUrl = ""
try { $remoteUrl = git remote get-url origin 2>$null } catch {}
if ([string]::IsNullOrWhiteSpace($remoteUrl)) {
    Write-Host "No remote 'origin' found. Creating GitHub repo 'dalmiacomputers-automation' and pushing..." -ForegroundColor Cyan
    # Create repo on GitHub under authenticated account
    $repoName = "dalmiacomputers-automation"
    try {
        gh repo create $repoName --public --source=. --remote=origin --push --confirm | Out-Null
        Write-Host "Created GitHub repo and pushed to origin/$((git rev-parse --abbrev-ref HEAD))." -ForegroundColor Green
    } catch {
        Write-Host "gh repo create failed: $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "You can create the repo manually in GitHub and then run:" -ForegroundColor Yellow
        Write-Host "  git remote add origin https://github.com/<your-username>/$repoName.git"
        Write-Host "  git branch -M main"
        Write-Host "  git push -u origin main"
        exit 1
    }
} else {
    Write-Host "Remote origin exists: $remoteUrl" -ForegroundColor Green
}

# 5) Prompt for secrets (do NOT echo) and set GitHub Actions Secrets
Write-Host "`nNow I will set GitHub Actions secrets for this repo. I will prompt for values — they will NOT be printed." -ForegroundColor Cyan

# Helper to set a secret via gh
function Set-GhSecret($name, $value) {
    if ([string]::IsNullOrWhiteSpace($value)) { return }
    # gh secret set accepts stdin body; use echo and pipe
    $tempFile = [IO.Path]::GetTempFileName()
    Set-Content -Path $tempFile -Value $value -Encoding UTF8
    gh secret set $name --body-file $tempFile | Out-Null
    Remove-Item $tempFile -Force
    Write-Host "Set secret: $name"
}

# Read FTP password securely
$ftpHost = Read-Host "FTP host (press Enter to accept 107.180.113.63)" 
if ([string]::IsNullOrWhiteSpace($ftpHost)) { $ftpHost = "107.180.113.63" }
$ftpUser = Read-Host "FTP user (press Enter to accept e5khdkcsrpke)"
if ([string]::IsNullOrWhiteSpace($ftpUser)) { $ftpUser = "e5khdkcsrpke" }
Write-Host "Enter FTP password (input hidden):"
$ftpPassSecure = Read-Host -AsSecureString
$ftpPass = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($ftpPassSecure))

# Site domain (defaults)
$siteDomain = Read-Host "Site domain (press Enter to accept dalmiacomputers.in)"
if ([string]::IsNullOrWhiteSpace($siteDomain)) { $siteDomain = "dalmiacomputers.in" }

# Set FTP secrets
Set-GhSecret -name "FTP_HOST" -value $ftpHost
Set-GhSecret -name "FTP_USER" -value $ftpUser
Set-GhSecret -name "FTP_PASSWORD" -value $ftpPass
Set-GhSecret -name "FTP_REMOTE_ROOT" -value "/public_html"
Set-GhSecret -name "SITE_DOMAIN" -value $siteDomain

# Optional: SSH secrets (ask user if they want)
$useSsh = Read-Host "Do you want to set SSH deploy secret now? (y/N)"
if ($useSsh -match '^(y|Y)') {
    $sshHost = Read-Host "SSH host (press Enter to accept 107.180.113.63)"
    if ([string]::IsNullOrWhiteSpace($sshHost)) { $sshHost = "107.180.113.63" }
    $sshPort = Read-Host "SSH port (press Enter to accept 22)"
    if ([string]::IsNullOrWhiteSpace($sshPort)) { $sshPort = "22" }
    $sshUser = Read-Host "SSH user (press Enter to accept e5khdkcsrpke)"
    if ([string]::IsNullOrWhiteSpace($sshUser)) { $sshUser = "e5khdkcsrpke" }
    $sshKeyPath = Read-Host "Path to SSH private key file (leave blank to skip)"
    if (-not [string]::IsNullOrWhiteSpace($sshKeyPath) -and (Test-Path $sshKeyPath)) {
        $sshKeyContent = Get-Content -Raw -Path $sshKeyPath
        Set-GhSecret -name "SSH_PRIVATE_KEY" -value $sshKeyContent
        Set-GhSecret -name "SSH_HOST" -value $sshHost
        Set-GhSecret -name "SSH_PORT" -value $sshPort
        Set-GhSecret -name "SSH_USER" -value $sshUser
        Set-GhSecret -name "REMOTE_ROOT" -value "/home/$sshUser/public_html"
    } else {
        Write-Host "Skipping SSH private key secret (no path provided or file missing)." -ForegroundColor Yellow
    }
}

# 6) Trigger the FTP workflow
Write-Host "`nTriggering the FTP workflow 'FTP Deploy + Verify (CHHAMA)'..." -ForegroundColor Cyan
try {
    gh workflow run "FTP Deploy + Verify (CHHAMA)" | Out-Null
    Write-Host "Workflow dispatch requested. Check GitHub Actions page for run details." -ForegroundColor Green
} catch {
    Write-Host "Could not trigger workflow (gh error): $($_.Exception.Message)" -ForegroundColor Yellow
}

Write-Host "`nAll done. Important next steps:" -ForegroundColor Cyan
Write-Host " - Visit your repo on GitHub, open Actions, and inspect the workflow run logs." -ForegroundColor White
Write-Host " - After confirming a successful deploy, rotate your FTP password in GoDaddy and update the GitHub secret 'FTP_PASSWORD'." -ForegroundColor Yellow
Write-Host " - If you want full SSH automation later, add the deploy public key to cPanel -> SSH Access." -ForegroundColor White

exit 0
