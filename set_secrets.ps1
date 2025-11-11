# set_secrets.ps1
# Prompts for FTP/GitHub secrets and saves them encrypted to 'secrets.encrypted' using DPAPI (user-scoped).

# Prompt for FTP host; allow using chhama.config.json default when left blank.
$ftp = Read-Host "FTP host (press Enter to use chhama.config.json value)"
if ([string]::IsNullOrWhiteSpace($ftp) -and (Test-Path .\chhama.config.json)) {
    try {
        $cfg = Get-Content .\chhama.config.json -Raw | ConvertFrom-Json
        if ($null -ne $cfg.ftp -and $cfg.ftp.host) { $ftp = $cfg.ftp.host }
    } catch { Write-Host "Could not read chhama.config.json; continuing to prompt." }
}

# Prompt for FTP user & password
$ftp_user = Read-Host "FTP username"
$ftp_pass = Read-Host -AsSecureString "FTP password"

# Optional: GitHub PAT (leave blank to skip)
$gh = Read-Host "Do you want to save a GitHub PAT? (Y/n)"
$gh_pat_enc = $null
if ($gh -ne 'n' -and $gh -ne 'N') {
    $pat = Read-Host -AsSecureString "Enter GitHub PAT (scopes: repo, admin:public_key) (leave blank to skip)"
    if ($pat.Length -gt 0) { $gh_pat_enc = $pat | ConvertFrom-SecureString }
}

# Convert secure string to encrypted string using DPAPI (tied to your Windows user)
$enc_pass = $ftp_pass | ConvertFrom-SecureString

$secretObj = @{
    ftp_host = $ftp
    ftp_user = $ftp_user
    ftp_pass = $enc_pass
    github_pat = $gh_pat_enc
}

$secretObj | ConvertTo-Json | Out-File -Encoding UTF8 secrets.encrypted

Write-Host "Saved encrypted secrets to: secrets.encrypted"
Write-Host "This file is encrypted with Windows DPAPI and readable only by this Windows user."
