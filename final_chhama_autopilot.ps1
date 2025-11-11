Set-Location "C:\Users\Dalmia Computers\Downloads\chhama_windows_master"
Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force

@'
<#
final_chhama_autopilot.ps1  (FIXED: avoid $host collision)
Master automation for Project CHHAMA (Windows 11)
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# Config
$FallbackIP = '107.180.113.63'
$DefaultFtpHost = 'ftp.dalmiacomputers.in'
$LogFile = Join-Path (Get-Location) 'automation.log'
$SecretsFile = Join-Path (Get-Location) 'secrets.encrypted'

function Log($msg) {
    $line = "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $msg"
    $line | Tee-Object -FilePath $LogFile -Append
    Write-Host $msg
}

function Read-Or-Create-Secrets {
    if (Test-Path $SecretsFile) {
        try {
            $s = Get-Content $SecretsFile -Raw | ConvertFrom-Json
            return $s
        } catch {
            Log "Warning: could not read secrets.encrypted: $($_.Exception.Message)"
        }
    }
    Log "No valid secrets file found. Asking for FTP details..."
    $ftpHost = Read-Host "FTP host (example: ftp.dalmiacomputers.in or IP) [default: $DefaultFtpHost]"
    if ([string]::IsNullOrWhiteSpace($ftpHost)) { $ftpHost = $DefaultFtpHost }
    $ftpUser = Read-Host "FTP username (example: amitdalmia@dalmiacomputers.in)"
    $ftpPassSecure = Read-Host -AsSecureString "FTP password (hidden)"
    $deployDir = Read-Host "Remote deploy dir (example: /public_html) [default: /public_html]"
    if ([string]::IsNullOrWhiteSpace($deployDir)) { $deployDir = '/public_html' }

    $obj = @{
        ftp_host = $ftpHost
        ftp_user = $ftpUser
        ftp_pass = ($ftpPassSecure | ConvertFrom-SecureString)
        deploy_dir = $deployDir
    }
    $obj | ConvertTo-Json | Out-File -FilePath $SecretsFile -Encoding UTF8
    Log "Saved encrypted secrets to $SecretsFile (user-scoped). Keep it private."
    return $obj
}

# Renamed parameters to avoid collision with built-in $host
function Ensure-HostsEntry($hostnameToAdd, $ipAddress) {
    $hostsPath = "$env:windir\System32\drivers\etc\hosts"
    try {
        $exists = Select-String -Path $hostsPath -Pattern [regex]::Escape($hostnameToAdd) -SimpleMatch -Quiet
    } catch {
        $exists = $false
    }
    if (-not $exists) {
        try {
            Copy-Item $hostsPath "$hostsPath.bak_$(Get-Date -Format yyyyMMdd_HHmmss)" -Force
            $line = "$ipAddress`t$hostnameToAdd"
            Add-Content -Path $hostsPath -Value $line
            Log "Appended hosts entry: $line"
            ipconfig /flushdns | Out-Null
        } catch {
            Log "Could not add hosts entry (requires admin): $($_.Exception.Message)"
        }
    } else {
        Log "Hosts entry for $hostnameToAdd already present."
    }
}

function Create-DeployZip {
    Log "Creating deploy ZIP in Downloads..."
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $projectDir = (Get-Location).Path
    $downloads = [Environment]::GetFolderPath('UserProfile') + "\Downloads"
    $zipPath = Join-Path $downloads "site-deploy-$timestamp.zip"
    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [IO.Compression.ZipFile]::CreateFromDirectory($projectDir, $zipPath)
    Log "Created ZIP: $zipPath"
    return $zipPath
}

function Run-Diagnostics {
    Log "Running diagnostics..."
    $ts = (Get-Date).ToString("yyyyMMdd-HHmmss")
    $diagDir = Join-Path (Get-Location) 'diagnostics'
    if (-not (Test-Path $diagDir)) { New-Item -ItemType Directory -Path $diagDir | Out-Null }

    function Safe([ScriptBlock]$b) { try { & $b 2>&1 | Out-String } catch { "ERROR: $($_.Exception.Message)" } }

    $report = [ordered]@{
        timestamp = $ts
        git = Safe { git --version }
        ssh = Safe { ssh -T git@github.com }
        node = Safe { node -v }
        npm = Safe { npm -v }
        python = Safe { python --version }
        pip = Safe { pip --version }
        dns_dalmiacomputers = Safe { nslookup dalmiacomputers.in }
        curl = Safe { curl -UseBasicParsing -Uri 'https://dalmiacomputers.in' -Method Head }
    }
    function PortOpen($p) { try { $c = New-Object Net.Sockets.TcpClient; $c.Connect('127.0.0.1',$p); $c.Close(); return 'open' } catch { return 'closed' } }
    $report.ports = @{ '80' = PortOpen 80; '443' = PortOpen 443; '3000' = PortOpen 3000 }

    $out = Join-Path $diagDir ("report-$ts.json")
    $report | ConvertTo-Json -Depth 6 | Out-File -FilePath $out -Encoding UTF8
    Log "Diagnostics saved: $out"
    return $out
}

function Run-LocalIfAny {
    Log "Checking for local project files..."
    if (Test-Path .\package.json) {
        Log "Node project found; running npm ci & build (if present)."
        npm ci
        if ((Get-Content package.json -Raw) -match '"build"') { npm run build --if-present }
    } elseif (Test-Path .\requirements.txt) {
        Log "Python project found; setting up virtualenv & dependencies."
        python -m venv .venv
        .\.venv\Scripts\Activate.ps1
        pip install -r requirements.txt
    } elseif (Test-Path .\docker-compose.yml) {
        Log "Docker Compose found; attempting docker-compose up -d --build"
        docker-compose up -d --build
    } else {
        Log "No project artifacts found; skipping local run."
    }
}

function Upload-FTP($ftpHost, $ftpUser, $ftpPassPlain, $deployDir, $zipPath) {
    $maxRetries = 3
    for ($i=1; $i -le $maxRetries; $i++) {
        try {
            Log "FTP upload attempt $i -> $ftpHost$deployDir/site-deploy.zip"
            $uri = "ftp://$ftpHost/$($deployDir.TrimStart('/').TrimEnd('/'))/site-deploy.zip"
            $req = [System.Net.FtpWebRequest]::Create($uri)
            $req.Method = [System.Net.WebRequestMethods+Ftp]::UploadFile
            $req.Credentials = New-Object System.Net.NetworkCredential($ftpUser, $ftpPassPlain)
            $req.UseBinary = $true; $req.UsePassive = $true; $req.EnableSsl = $false
            $bytes = [System.IO.File]::ReadAllBytes($zipPath)
            $req.ContentLength = $bytes.Length
            $stream = $req.GetRequestStream()
            $stream.Write($bytes, 0, $bytes.Length)
            $stream.Close()
            $resp = $req.GetResponse()
            $resp.Close()
            Log "FTP upload successful on attempt $i."
            return $true
        } catch {
            Log "FTP attempt $i failed: $($_.Exception.Message)"
            Start-Sleep -Seconds (5 * $i)
        }
    }
    return $false
}

# ===== MAIN FLOW =====
Log "========== CHHAMA AUTOPILOT START =========="

# 1. Ensure hosts entry (attempt but ignore failure if not elevated)
Ensure-HostsEntry $DefaultFtpHost $FallbackIP

# 2. Read or create secrets
$secrets = Read-Or-Create-Secrets
$ftpHost = $secrets.ftp_host
$ftpUser = $secrets.ftp_user
$ftpPassSecure = ConvertTo-SecureString $secrets.ftp_pass
$ftpPassPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($ftpPassSecure))
$deployDir = $secrets.deploy_dir

# 3. Run diagnostics
try { $diag = Run-Diagnostics } catch { Log "Diagnostics failed: $($_.Exception.Message)" }

# 4. Local run/build if any
try { Run-LocalIfAny } catch { Log "Local run failed: $($_.Exception.Message)" }

# 5. Create ZIP in Downloads
try { $zip = Create-DeployZip } catch { Log "ZIP creation failed: $($_.Exception.Message)"; exit 1 }

# 6. Try uploading to hostname first
$uploaded = $false
try {
    $resolved = $null
    try { $resolved = (Resolve-DnsName $ftpHost -ErrorAction Stop).IPAddress[0] } catch { $resolved = $null }
    if (-not $resolved) {
        Log "Hostname $ftpHost did not resolve; will try fallback IP $FallbackIP"
        $tryHost = $FallbackIP
    } else {
        $tryHost = $ftpHost
    }

    $uploaded = Upload-FTP -ftpHost $tryHost -ftpUser $ftpUser -ftpPassPlain $ftpPassPlain -deployDir $deployDir -zipPath $zip
    if (-not $uploaded -and $tryHost -ne $FallbackIP) {
        Log "Retrying with fallback IP $FallbackIP"
        $uploaded = Upload-FTP -ftpHost $FallbackIP -ftpUser $ftpUser -ftpPassPlain $ftpPassPlain -deployDir $deployDir -zipPath $zip
    }
} catch {
    Log "Upload flow error: $($_.Exception.Message)"
}

if ($uploaded) {
    Log "Deploy succeeded. Please extract site-deploy.zip in cPanel -> $deployDir."
} else {
    Log "Deploy failed after retries. Please check credentials and network; manual upload recommended."
}

Log "========== CHHAMA AUTOPILOT END =========="
'@ | Out-File -FilePath .\final_chhama_autopilot.ps1 -Encoding UTF8 -Force

# Execute the fixed script
powershell -ExecutionPolicy Bypass -File .\final_chhama_autopilot.ps1
