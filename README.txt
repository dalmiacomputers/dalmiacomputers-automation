
Project Chhama — Windows 11 Master ZIP
--------------------------------------

This package is configured with the following values (placeholders used where specified):

- GitHub repo: dalmiaacomputers/Chhama
- GitHub PAT: __GITHUB_PAT__  (placeholder — replace or use set_secrets.ps1)
- GoDaddy FTP host: ftp.dalmiacomputers.in
- Domain: dalmiacomputers.in
- Deploy directory: /public_html

How to use:
1. Unzip the package to a folder (e.g., C:\Users\<you>\Downloads\Chhama_Master).
2. Open PowerShell as Administrator.
3. OPTIONAL: Run 'set_secrets.ps1' to securely store your secrets (encrypts them to a file readable only by this Windows user).
     .\set_secrets.ps1
   This will prompt for:
     - GitHub PAT (optional)
     - FTP username
     - FTP password
     - SSH private key path (optional)
   The secrets are stored encrypted in 'secrets.encrypted' using Windows Data Protection API (DPAPI) tied to your user account.
4. Run scripts in numeric order as Administrator:
     1_install.ps1
     2_setup_ssh_git.ps1
     3_diagnose.ps1
     4_run_local.ps1
     5_deploy.ps1

Notes:
- This package intentionally uses placeholders for sensitive values. Do NOT upload the package with real credentials to public places.
- The deploy script will prefer reading credentials from 'secrets.encrypted' if present; otherwise it will prompt interactively.
- Inspect scripts before running if you want to audit them.



ADDITIONAL FILES:
- run_all.ps1 : Launcher that runs steps in order with prompts.
- create_shortcut.ps1 : Creates a desktop shortcut to run the launcher (Run as Admin).

Usage:
1. Extract package.
2. Run create_shortcut.ps1 as Administrator once to create desktop launcher, or run run_all.ps1 directly as Administrator.
3. Follow on-screen prompts.
deploy-test 11/13/2025 12:48:22
