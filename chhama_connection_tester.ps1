<# 
chhama_connection_tester.ps1 – fixed (no $Host conflict)
-----------------------------------------------
Run with:
  pwsh -NoProfile -ExecutionPolicy Bypass -File .\chhama_connection_tester.ps1
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$ts = (Get-Date).ToString("yyyyMMdd-HHmmss")
$logPath = Join-Path (Get-Location) ("chhama_conn_test_$ts.log")

function LogLine([string]$text) {
    $line = ("[{0:u}] {1}" -f (Get-Date), $text)
    $line | Tee-Object -FilePath $logPath -Append
}

# --- Collect credentials -------------------------------------------------------
$ftpHost = $env:CHHAMA_FTP_HOST
if ([string]::IsNullOrWhiteSpace($ftpHost)) {
    $ftpHost = Read-Host "FTP host or IP (e.g. 107.180.113.63)"
}
$user = $env:CHHAMA_FTP_USER
if ([string]::IsNullOrWhiteSpace($user)) {
    $user = Read-Host "FTP username"
}
$pwdPlain = $env:CHHAMA_FTP_PASS
if ([string]::IsNullOrWhiteSpace($pwdPlain)) {
    $pwdSecure = Read-Host "FTP password (hidden)" -AsSecureString
    $pwdPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($pwdSecure)
    )
}

LogLine "=== CHHAMA connection tester starting ==="
LogLine ("Host: " + $ftpHost + "  User: " + $user)
LogLine ("Log: " + (Resolve-Path $logPath).Path)

# --- DNS -----------------------------------------------------------------------
try {
    LogLine "Resolving host..."
    $dns = Resolve-DnsName $ftpHost -ErrorAction Stop | Where-Object { $_.Type -in @('A','AAAA') }
    if ($dns) { foreach ($d in $dns) { LogLine ("DNS -> " + $d.Name + " -> " + $d.IPAddress) } }
    else { LogLine "No A/AAAA records found." }
} catch { LogLine ("DNS resolve failed: " + $_.Exception.Message) }

# --- Ping ----------------------------------------------------------------------
try {
    LogLine "Ping test..."
    $p = Test-Connection -ComputerName $ftpHost -Count 2 -ErrorAction SilentlyContinue
    if ($p) { foreach ($r in $p) { LogLine ("Ping reply from " + $r.Address + " time=" + $r.ResponseTime + "ms") } }
    else { LogLine "Ping failed or blocked (can be normal)." }
} catch { LogLine ("Ping error: " + $_.Exception.Message) }

# --- Port checks ---------------------------------------------------------------
$ports = @(21, 990, 22)
foreach ($port in $ports) {
    $label = switch ($port) { 21 { "FTP" } 990 { "FTPS-Implicit" } 22 { "SFTP" } default { "Unknown" } }
    try {
        $r = Test-NetConnection -ComputerName $ftpHost -Port $port -InformationLevel Detailed -WarningAction SilentlyContinue
        $succ = $r.TcpTestSucceeded
        $remote = if ($r.RemoteAddress) { $r.RemoteAddress } else { "<none>" }
        LogLine ("Port " + $port + " (" + $label + ") -> TcpTestSucceeded=" + $succ + "  RemoteAddress=" + $remote)
    } catch { LogLine ("Port " + $port + " (" + $label + ") check error: " + $_.Exception.Message) }
}

# --- Plain FTP -----------------------------------------------------------------
LogLine "Attempting plain FTP LIST ..."
try {
    $uri = "ftp://$ftpHost/"
    $req = [System.Net.FtpWebRequest]::Create($uri)
    $req.Method = [System.Net.WebRequestMethods+Ftp]::ListDirectory
    $req.Credentials = New-Object System.Net.NetworkCredential($user, $pwdPlain)
    $req.UsePassive = $true
    $req.KeepAlive = $false
    $resp = $req.GetResponse()
    $reader = New-Object System.IO.StreamReader($resp.GetResponseStream())
    $entries = @()
    while (-not $reader.EndOfStream) { $entries += $reader.ReadLine() }
    $reader.Close(); $resp.Close()
    if ($entries.Count -gt 0) {
        $sample = ($entries | Select-Object -First 5) -join ", "
        LogLine ("Plain FTP LIST succeeded. Sample entries: " + $sample)
    } else { LogLine "Plain FTP LIST succeeded but empty directory." }
} catch { LogLine ("Plain FTP failed: " + $_.Exception.Message) }

# --- FTPS Explicit -------------------------------------------------------------
LogLine "Attempting FTPS Explicit (EnableSsl on port 21) ..."
try {
    $uri = "ftp://$ftpHost/"
    $req = [System.Net.FtpWebRequest]::Create($uri)
    $req.Method = [System.Net.WebRequestMethods+Ftp]::ListDirectory
    $req.Credentials = New-Object System.Net.NetworkCredential($user, $pwdPlain)
    $req.EnableSsl = $true
    $req.UsePassive = $true
    $req.KeepAlive = $false
    $resp = $req.GetResponse()
    $resp.Close()
    LogLine "FTPS Explicit succeeded."
} catch { LogLine ("FTPS Explicit failed: " + $_.Exception.Message) }

# --- FTPS Implicit -------------------------------------------------------------
LogLine "Attempting FTPS Implicit (port 990) ..."
try {
    $uri = "ftp://$ftpHost:990/"
    $req = [System.Net.FtpWebRequest]::Create($uri)
    $req.Method = [System.Net.WebRequestMethods+Ftp]::ListDirectory
    $req.Credentials = New-Object System.Net.NetworkCredential($user, $pwdPlain)
    $req.EnableSsl = $true
    $req.UsePassive = $true
    $req.KeepAlive = $false
    $resp = $req.GetResponse()
    $resp.Close()
    LogLine "FTPS Implicit succeeded."
} catch { LogLine ("FTPS Implicit failed: " + $_.Exception.Message) }

# --- SFTP via Posh-SSH ---------------------------------------------------------
LogLine "Attempting SFTP (port 22) via Posh-SSH ..."
if (-not (Get-Module -ListAvailable -Name Posh-SSH)) {
    LogLine "Posh-SSH not installed. Install-Module -Name Posh-SSH -Scope CurrentUser -Force"
} else {
    try {
        Import-Module Posh-SSH -ErrorAction Stop
        $cred = New-Object System.Management.Automation.PSCredential($user,(ConvertTo-SecureString $pwdPlain -AsPlainText -Force))
        $sess = New-SSHSession -ComputerName $ftpHost -Credential $cred -AcceptKey -ErrorAction Stop
        LogLine ("SFTP connected (SessionId=" + $sess.SessionId + ")")
        Remove-SSHSession -SessionId $sess.SessionId
    } catch { LogLine ("SFTP failed: " + $_.Exception.Message) }
}

LogLine "=== Diagnostics finished ==="
LogLine ("Log file path: " + (Resolve-Path $logPath).Path)
Write-Host ""
Write-Host "Diagnostics complete. View the last 60 lines with:"
Write-Host "Get-ChildItem -Filter 'chhama_conn_test_*.log' | Sort-Object LastWriteTime -Descending | Select-Object -First 1 | ForEach-Object { Get-Content -Path \$_.FullName -Tail 60 }"
