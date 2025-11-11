# 2_setup_ssh_git.ps1 (fixed)
# Generates an ed25519 SSH key WITHOUT passphrase and prints the public key.
param([string]$Email)

if (-not $Email) {
  $Email = Read-Host "Enter your email for the SSH key comment (e.g. you@example.com)"
}

$sshPath = Join-Path $env:USERPROFILE ".ssh"
if (-not (Test-Path $sshPath)) { New-Item -ItemType Directory -Path $sshPath | Out-Null }

# Use a stable filename
$keyFile = Join-Path $sshPath 'chhama_ed25519'

# If another similar key exists, back it up (safe)
if (Test-Path $keyFile) {
  Write-Host "Key already exists at $keyFile — backing up the existing key to ${keyFile}.bak"
  Copy-Item -Path $keyFile -Destination "${keyFile}.bak" -Force -ErrorAction SilentlyContinue
  Copy-Item -Path "${keyFile}.pub" -Destination "${keyFile}.pub.bak" -Force -ErrorAction SilentlyContinue
}

# Generate an ed25519 key with empty passphrase (automated)
ssh-keygen -t ed25519 -C $Email -f $keyFile -N "" -q

# wait a moment for file system
Start-Sleep -Milliseconds 300

# Start ssh-agent and add key
if (Get-Service -Name ssh-agent -ErrorAction SilentlyContinue) {
    Start-Service ssh-agent -ErrorAction SilentlyContinue
}
ssh-add $keyFile 2>$null | Out-Null

# Print public key content (if present)
$pubPath = $keyFile + '.pub'
if (Test-Path $pubPath) {
    Write-Host "`n=== Public key (copy this into GitHub -> Settings -> SSH and GPG keys) ===`n"
    Get-Content $pubPath -Raw
} else {
    Write-Host "Public key not found at $pubPath. Please check permissions."
}

Write-Host "`nDone."
