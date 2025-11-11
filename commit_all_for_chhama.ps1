# commit_all_for_chhama.ps1 (fixed: uses single-quoted here-strings for GitHub templates)
# Place this in your project root and run:
# pwsh -NoProfile -ExecutionPolicy Bypass -File .\commit_all_for_chhama.ps1

$root = (Get-Location).Path
Write-Host "Working in: $root"

# --- create folders ---
New-Item -Path ".github\workflows" -ItemType Directory -Force | Out-Null
New-Item -Path "scripts" -ItemType Directory -Force | Out-Null

# --- write deploy-ftp.yml (single-quoted here-string to preserve ${{ }}) ---
@'
name: FTP Deploy + Verify (CHHAMA)

on:
  push:
    branches: [ main ]
  workflow_dispatch:
  schedule:
    - cron: "0 2 * * *"

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: FTP Deploy (SamKirkland)
        uses: SamKirkland/FTP-Deploy-Action@4.2.0
        with:
          server: ${{ secrets.FTP_HOST }}
          username: ${{ secrets.FTP_USER }}
          password: ${{ secrets.FTP_PASSWORD }}
          protocol: ftp
          port: 21
          local-dir: ./
          server-dir: ${{ secrets.FTP_REMOTE_ROOT }}
          git-ftp-args: --insecure

      - name: Wait 5s
        run: sleep 5

      - name: HTTP verify
        run: |
          URL="https://${{ secrets.SITE_DOMAIN }}/"
          echo "Checking $URL"
          status=$(curl -s -o /dev/null -w "%{http_code}" "$URL")
          echo "HTTP STATUS: $status"
          if [[ "$status" -ge 200 && "$status" -lt 400 ]]; then
            echo "Site OK"
          else
            echo "Site check failed with $status"
            exit 1
          fi
'@ | Out-File -Encoding UTF8 ".github\workflows\deploy-ftp.yml" -Force

# --- write deploy-ssh.yml (single-quoted here-string) ---
@'
name: SSH Deploy + Server WebDoctor

on:
  push:
    branches: [ main ]
  workflow_dispatch:
  schedule:
    - cron: "0 */6 * * *"

jobs:
  build-and-deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Archive repo
        run: tar -czf site_package.tar.gz --exclude .git --exclude node_modules .

      - name: Upload package to server (SCP)
        uses: appleboy/scp-action@master
        with:
          host: ${{ secrets.SSH_HOST }}
          username: ${{ secrets.SSH_USER }}
          key: ${{ secrets.SSH_PRIVATE_KEY }}
          port: ${{ secrets.SSH_PORT }}
          source: "site_package.tar.gz"
          target: "/home/${{ secrets.SSH_USER }}/chhama_deploy_tmp/"

      - name: Run remote deploy
        uses: appleboy/ssh-action@master
        with:
          host: ${{ secrets.SSH_HOST }}
          username: ${{ secrets.SSH_USER }}
          key: ${{ secrets.SSH_PRIVATE_KEY }}
          port: ${{ secrets.SSH_PORT }}
          script: |
            set -e
            cd /home/${{ secrets.SSH_USER }}/chhama_deploy_tmp/
            tar -xzf site_package.tar.gz -C /home/${{ secrets.SSH_USER }}/chhama_deploy_tmp/
            bash /home/${{ secrets.SSH_USER }}/chhama_deploy_tmp/scripts/server_deploy.sh
'@ | Out-File -Encoding UTF8 ".github\workflows\deploy-ssh.yml" -Force

# --- write server_deploy.sh ---
@'
#!/usr/bin/env bash
set -euo pipefail
TIMESTAMP=$(date '+%Y%m%d_%H%M%S')
DEPLOY_TMP="$HOME/chhama_deploy_tmp_$TIMESTAMP"
LIVE_ROOT="/home/$USER/public_html"
BACKUP_DIR="$HOME/chhama_backups_$TIMESTAMP"

echo "Deploy tmp: $DEPLOY_TMP"
mkdir -p "$DEPLOY_TMP"
mkdir -p "$BACKUP_DIR"
echo "Backing up current live site to $BACKUP_DIR"
rsync -a --delete "$LIVE_ROOT/" "$BACKUP_DIR/"

echo "Moving new files into place..."
rsync -a --delete "$DEPLOY_TMP/" "$LIVE_ROOT/"

if [ -x "$LIVE_ROOT/scripts/webdoctor-server.sh" ]; then
  echo "Running server-side webdoctor..."
  bash "$LIVE_ROOT/scripts/webdoctor-server.sh" || echo "webdoctor exited non-zero"
fi

echo "Deploy done at $TIMESTAMP"
'@ | Out-File -Encoding UTF8 "scripts\server_deploy.sh" -Force

# set permissions for unix if later transferred
try { icacls "scripts\server_deploy.sh" /grant Everyone:RX > $null 2>&1 } catch {}

# --- write webdoctor-server.sh ---
@'
#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
echo "Running server webdoctor at $ROOT"

if command -v php >/dev/null 2>&1; then
  if [ -f "$ROOT/tools/regenerate_sitemap.php" ]; then
    php "$ROOT/tools/regenerate_sitemap.php" || true
  fi
fi

if [ -d "$ROOT/cache" ]; then
  rm -rf "$ROOT/cache/*" || true
fi

if [ -f "$ROOT/final_chhama_run.ps1" ]; then
  if command -v pwsh >/dev/null 2>&1; then
    pwsh -NoProfile -NonInteractive -File "$ROOT/final_chhama_run.ps1" || true
  fi
fi

echo "Server-side WebDoctor completed."
'@ | Out-File -Encoding UTF8 "scripts\webdoctor-server.sh" -Force

try { icacls "scripts\webdoctor-server.sh" /grant Everyone:RX > $null 2>&1 } catch {}

# --- write deploy-exclude.txt and README ---
@'
# Files/dirs to exclude from deployment (example)
.git
node_modules
*.pem
*.key
'@ | Out-File -Encoding UTF8 "deploy-exclude.txt" -Force

@'
# README-deploy.md

1) Add GitHub repo - either create new or use existing remote.
2) Add Secrets (see below) in repository Settings -> Secrets & variables -> Actions.
3) Choose FTP-only or SSH workflow by enabling secrets and pushing to main.

Secrets to add for FTP option:
- FTP_HOST: 107.180.113.63
- FTP_USER: your ftp user (e.g. e5khdkcsrpke)
- FTP_PASSWORD: your ftp password
- FTP_REMOTE_ROOT: /public_html
- SITE_DOMAIN: dalmiacomputers.in

Secrets to add for SSH option:
- SSH_PRIVATE_KEY: (the private key contents)
- SSH_HOST: 107.180.113.63
- SSH_PORT: 22
- SSH_USER: your ssh user (cPanel user)
- REMOTE_ROOT: /public_html
- SITE_DOMAIN: dalmiacomputers.in

To set secrets with GitHub CLI (example):
gh secret set FTP_PASSWORD --body "<value>"
'@ | Out-File -Encoding UTF8 "README-deploy.md" -Force

# --- git init / add / commit / push ---
if (-not (Test-Path ".git")) {
    git init
    Write-Host "Initialized new git repo."
}

git add -A
# commit may fail if nothing changed; handle gracefully
try {
    git commit -m "chhama: add github actions deploy + server scripts (auto-commit)" 2>$null
} catch {
    Write-Host "Nothing new to commit or commit failed (maybe already up-to-date)."
}

# attempt to push if remote exists
$remote = ""
try { $remote = git remote get-url origin 2>$null } catch {}
if ($remote -and $remote.Trim() -ne "") {
    Write-Host "Pushing to origin main (ensure you have write access)..."
    try {
        git branch -M main 2>$null
        git push origin main
    } catch {
        Write-Host "Push failed; please ensure you have correct remote and permissions. Remote URL: $remote"
    }
} else {
    Write-Host "No remote 'origin' configured. Create a repo on GitHub and add remote, or run 'gh repo create' then push."
    Write-Host "If you want, run this to create one (replace repo name):"
    Write-Host "  gh repo create dalmiacomputers --public --source=. --remote=origin --push"
}

Write-Host ""
Write-Host "Files created and committed. Next steps (required):"
Write-Host " 1) Add repository Secrets in Settings → Secrets & variables → Actions."
Write-Host " 2) If using SSH option, create an SSH keypair locally, add the public key to cPanel (SSH Access), and add the private key to GitHub Secret 'SSH_PRIVATE_KEY'."
Write-Host " 3) Manually run 'gh secret set' commands (examples printed below)."

Write-Host ""
Write-Host "Example gh commands to set secrets (copy-paste and replace values):"
Write-Host "gh secret set FTP_HOST --body '107.180.113.63'"
Write-Host "gh secret set FTP_USER --body 'e5khdkcsrpke'"
Write-Host "gh secret set FTP_PASSWORD --body '<your-ftp-password>'"
Write-Host "gh secret set FTP_REMOTE_ROOT --body '/public_html'"
Write-Host "gh secret set SITE_DOMAIN --body 'dalmiacomputers.in'"
Write-Host "gh secret set SSH_PRIVATE_KEY --body '<contents-of-private-key-file>'"
Write-Host "gh secret set SSH_HOST --body '107.180.113.63'"
Write-Host "gh secret set SSH_PORT --body '22'"
Write-Host "gh secret set SSH_USER --body '<ssh-username>'"

Write-Host ""
Write-Host "If you want me to also create a GitHub Issue template, Slack integration, or finalize the server paths (e.g., replace /home/\$USER/public_html with exact path), tell me and I'll produce the patch."
