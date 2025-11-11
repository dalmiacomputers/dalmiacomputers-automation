<#
chhama_full_diagnostic_and_test.ps1
Full automated diagnostics for FTP/SFTP/cPanel + create a tiny test file and verify.
Place in: C:\Users\Dalmia Computers\Downloads\chhama_windows_master
Run as Admin:
  pwsh -NoProfile -ExecutionPolicy Bypass -File .\chhama_full_diagnostic_and_test.ps1

Security: Password is requested interactively and not saved to disk.
#>

# --- settings & helpers ---
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$log = Join-Path $scriptDir ("chhama_full_diag_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))
function Write-Log { param($m) $t=(Get-Date).ToString("yyyy-MM-dd HH:mm:ss"); Add-Content -Path $log -Value "$t`t$m"; Write-Host $m }

Write-Log "=== CHHAMA FULL DIAGNOSTIC START ==="

# Prompt for minimal info
$ServerOrIP = Read-Host "Enter Server host or IP (e.g. 107.180.113.63 or ftp.dalmiacomputers.in)"
$Username = Read-Host "Enter FTP/SFTP username (e.g. amitdalmia@dalmiacomputers.in)"
$Password = Read-Host "Enter password (won't be stored)" -AsSecureString
# convert to plain for APIs (kept in-memory)
$PlainPass = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password))

# Basic DNS + port checks
Write-Log "STEP: DNS + Port checks for $ServerOrIP"
try {
    $dns = Resolve-DnsName $ServerOrIP -ErrorAction SilentlyContinue
    if ($dns) {
        $ips = ($dns | Select-Object -ExpandProperty IPAddress) -join ", "
        Write-Log "DNS: Resolved -> $ips"
    } else {
        Write-Log "DNS: No DNS record found / may be IP address provided"
    }
} catch {
    Write-Log "DNS lookup error: $($_.Exception.Message)"
}

# Test ports
$ports = @(21,22,80,443)
foreach ($p in $ports) {
    try {
        $t = Test-NetConnection -ComputerName $ServerOrIP -Port $p -InformationLevel "Quiet"
        if ($t) { Write-Log ("PORT {0}: Open/Reachable" -f $p) } else { Write-Log ("PORT {0}: Not reachable" -f $p) }
    } catch {
        Write-Log ("PORT {0}: Test-NetConnection error: {1}" -f $p, $_.Exception.Message)
    }
}

# Create small local test file
$timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
$localTestDir = Join-Path $scriptDir "diag_temp"
if (-not (Test-Path $localTestDir)) { New-Item -ItemType Directory -Path $localTestDir | Out-Null }
$localTestFile = Join-Path $localTestDir ("chhama_diag_test_{0}.txt" -f $timestamp)
"CHHAMA diag test file created at $(Get-Date) for server $ServerOrIP" | Out-File -FilePath $localTestFile -Encoding UTF8
Write-Log "Created local test file: $localTestFile"

# candidate roots to try
$candidates = @("/public_html","/www","/httpdocs","/htdocs","/site/wwwroot","/public","/html","/")

# Attempt SFTP via WinSCP if available
$winScpDefault = "C:\Program Files (x86)\WinSCP\WinSCPnet.dll"
$useSftp = $false
if (Test-Path $winScpDefault) {
    try {
        Add-Type -Path $winScpDefault
        Write-Log "WinSCP .NET found: $winScpDefault -> Attempting SFTP connect"
        $sessionOptions = New-Object WinSCP.SessionOptions -Property @{
            Protocol = [WinSCP.Protocol]::Sftp
            HostName = $ServerOrIP
            UserName = $Username
            Password = $PlainPass
            PortNumber = 22
            GiveUpSecurityAndAcceptAnySshHostKey = $true
        }
        $session = New-Object WinSCP.Session
        $session.Open($sessionOptions)
        Write-Log "SFTP: Connected via WinSCP"
        # detect root
        $sroot = $null
        foreach ($p in $candidates) {
            try {
                $entry = $session.ListDirectory($p) 2>$null
                if ($entry) { $sroot = $p; Write-Log ("SFTP: candidate root -> {0}" -f $p); break }
            } catch { Write-Log ("SFTP: not available: {0}" -f $p) }
        }
        if (-not $sroot) { Write-Log "SFTP: no standard root found; picking /"; $sroot = "/" }
        # create test folder and upload file
        $remoteTestFolder = $sroot.TrimEnd("/") + "/chhama_diag_test_$timestamp"
        try { $session.CreateDirectory($remoteTestFolder); Write-Log ("SFTP: Created remote test folder {0}" -f $remoteTestFolder) } catch { Write-Log ("SFTP: Create folder warning: {0}" -f $_.Exception.Message) }
        $remoteTestFile = $remoteTestFolder + "/" + (Split-Path $localTestFile -Leaf)
        $tx = New-Object WinSCP.TransferOptions
        $tx.TransferMode = [WinSCP.TransferMode]::Binary
        $res = $session.PutFiles($localTestFile, $remoteTestFile, $false, $tx)
        if ($res.IsSuccess) { Write-Log ("SFTP: Uploaded test file to {0}" -f $remoteTestFile); $useSftp = $true } else { foreach ($f in $res.Failures) { Write-Log ("SFTP upload failure: {0}" -f $f.Message) } }
        $session.Dispose()
    } catch {
        Write-Log ("SFTP error: {0}. Will fallback to FTP." -f $_.Exception.Message)
        if ($session) { try { $session.Dispose() } catch {} }
    }
} else {
    Write-Log "WinSCP .NET DLL not found; skipping SFTP attempt ($winScpDefault)."
}

# If SFTP succeeded, do an HTTP check (if domain provided)
if ($useSftp) {
    try {
        if ($ServerOrIP -match "\.") {
            $testUrl = "http://$ServerOrIP/" + ($remoteTestFolder.TrimStart("/")) + "/" + (Split-Path $localTestFile -Leaf)
            Write-Log ("Attempting HTTP GET to {0}" -f $testUrl)
            try {
                $r = Invoke-WebRequest -Uri $testUrl -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
                Write-Log ("HTTP check succeeded: StatusCode {0}" -f $r.StatusCode)
            } catch { Write-Log ("HTTP check failed: {0}" -f $_.Exception.Message) }
        } else { Write-Log "Server appears to be IP; skipping HTTP check for SFTP-uploaded file." }
    } catch { Write-Log ("HTTP verify exception: {0}" -f $_.Exception.Message) }
}

# If SFTP not used or failed, try FTP (.NET)
if (-not $useSftp) {
    Write-Log "STEP: Trying FTP (.NET) with provided credentials"
    $ftpUser = $Username
    $ftpPass = $PlainPass
    $detectedRoot = $null
    foreach ($p in $candidates) {
        try {
            $uri = "ftp://$ServerOrIP$p"
            $req = [System.Net.FtpWebRequest]::Create($uri)
            $req.Method = [System.Net.WebRequestMethods+Ftp]::ListDirectory
            $req.Credentials = New-Object System.Net.NetworkCredential($ftpUser, $ftpPass)
            $req.UsePassive=$true; $req.UseBinary=$true
            $resp = $req.GetResponse()
            $resp.Close()
            Write-Log ("FTP: root accessible -> {0}" -f $p)
            $detectedRoot = $p
            break
        } catch {
            Write-Log ("FTP: not accessible -> {0} ({1})" -f $p, $_.Exception.Message)
        }
    }
    if (-not $detectedRoot) {
        Write-Log "FTP: No standard root found; will try root '/'"
        try {
            $uri = "ftp://$ServerOrIP/"
            $req = [System.Net.FtpWebRequest]::Create($uri)
            $req.Method = [System.Net.WebRequestMethods+Ftp]::ListDirectoryDetails
            $req.Credentials = New-Object System.Net.NetworkCredential($ftpUser, $ftpPass)
            $req.UsePassive=$true; $req.UseBinary=$true
            $resp = $req.GetResponse()
            $sr = New-Object System.IO.StreamReader($resp.GetResponseStream())
            $body = $sr.ReadToEnd()
            $resp.Close()
            Write-Log "FTP root listing succeeded. Choosing '/' as root"
            $detectedRoot = "/"
        } catch {
            Write-Log ("FTP: root listing failed: {0}" -f $_.Exception.Message)
        }
    }

    if ($detectedRoot) {
        # create remote test folder
        $remoteTestFolder = $detectedRoot.TrimEnd("/") + "/chhama_diag_test_$timestamp"
        try {
            $mkUri = "ftp://$ServerOrIP$remoteTestFolder"
            $mkReq = [System.Net.FtpWebRequest]::Create($mkUri)
            $mkReq.Method = [System.Net.WebRequestMethods+Ftp]::MakeDirectory
            $mkReq.Credentials = New-Object System.Net.NetworkCredential($ftpUser, $ftpPass)
            $mkReq.UsePassive=$true; $mkReq.UseBinary=$true
            $mkResp = $mkReq.GetResponse(); $mkResp.Close()
            Write-Log ("FTP: Created remote test folder {0}" -f $remoteTestFolder)
        } catch { Write-Log ("FTP: Could not create test folder (may be restricted): {0}" -f $_.Exception.Message) }
        # upload test file
        try {
            $remoteTestFile = $remoteTestFolder + "/" + (Split-Path $localTestFile -Leaf)
            $upUri = "ftp://$ServerOrIP$remoteTestFile"
            $upReq = [System.Net.FtpWebRequest]::Create($upUri)
            $upReq.Method = [System.Net.WebRequestMethods+Ftp]::UploadFile
            $upReq.Credentials = New-Object System.Net.NetworkCredential($ftpUser, $ftpPass)
            $upReq.UsePassive=$true; $upReq.UseBinary=$true
            $bytes = [System.IO.File]::ReadAllBytes($localTestFile)
            $upReq.ContentLength = $bytes.Length
            $stream = $upReq.GetRequestStream(); $stream.Write($bytes,0,$bytes.Length); $stream.Close()
            $upResp = $upReq.GetResponse(); $upResp.Close()
            Write-Log ("FTP: Uploaded test file to {0}" -f $remoteTestFile)
            # attempt HTTP check if domain provided
            if ($ServerOrIP -match "\.") {
                $testUrl = "http://$ServerOrIP" + ($remoteTestFile)
                Write-Log ("Attempting HTTP GET to {0}" -f $testUrl)
                try {
                    $r = Invoke-WebRequest -Uri $testUrl -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
                    Write-Log ("HTTP check succeeded: StatusCode {0}" -f $r.StatusCode)
                } catch { Write-Log ("HTTP check failed: {0}" -f $_.Exception.Message) }
            } else { Write-Log "Server appears to be IP; skipping HTTP check for FTP-uploaded file." }
        } catch { Write-Log ("FTP upload failed: {0}" -f $_.Exception.Message) }
    } else {
        Write-Log "FTP: Could not detect any accessible root. Please verify credentials, server address, or enable FTP/SFTP on host."
    }
}

# final summary
Write-Log "=== DIAGNOSTIC COMPLETE ==="
Write-Log ("Log saved at: {0}" -f $log)
Write-Host "`nDIAGNOSTIC COMPLETE. Log: $log"
Write-Host "Please paste the last 30 lines of this log here or upload the log file for me to read and give the exact resolution."
