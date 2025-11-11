<#
Run-ChhamaPatch-Auto.ps1
Single launcher: try SFTP (WinSCP) when available, otherwise fallback to FTP (.NET).
Place this file in your project folder (next to patch_files). Run in PowerShell (Admin).

Features:
 - Prompts for server, username, password, mode (test/live), local patch folder (default patch_files)
 - If WinSCP .NET is found: uses SFTP (secure). If not found: uses FTP via .NET FtpWebRequest
 - Auto-creates patch_files folder if missing
 - Test mode uploads into a timestamped test folder (safe)
 - Live mode attempts to create a backup folder (best-effort)
 - Full logging to chhama_patch_auto_YYYYMMDD_HHMMSS.log
 - Avoids reserved PowerShell variables
#>

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$defaultLocal = Join-Path $scriptDir "patch_files"
$defaultWinScpDll = "C:\Program Files (x86)\WinSCP\WinSCPnet.dll"
$logFile = Join-Path $scriptDir ("chhama_patch_auto_{0}.log" -f (Get-Date -Format "yyyyMMdd_HHmmss"))

function Write-Log { param($m) $t=(Get-Date).ToString("yyyy-MM-dd HH:mm:ss"); Add-Content -Path $logFile -Value "$t`t$m"; Write-Host $m }

# Prompt (no reserved names)
$Server = Read-Host "Server host or IP (example: ftp.dalmiacomputers.in or 107.180.113.63)"
$User = Read-Host "Username (example: amitdalmia@dalmiacomputers.in)"
$Password = Read-Host "Password (won't be stored in file)"
$LocalPath = Read-Host "Local patch folder (press Enter for default: $defaultLocal)"
if ([string]::IsNullOrWhiteSpace($LocalPath)) { $LocalPath = $defaultLocal }
$Mode = Read-Host "Mode (test/live). Default: test"
if ($Mode -ne "live") { $Mode = "test" }
$WinScpDllPath = Read-Host "Path to WinSCPnet.dll (press Enter for default: $defaultWinScpDll)"
if ([string]::IsNullOrWhiteSpace($WinScpDllPath)) { $WinScpDllPath = $defaultWinScpDll }

Write-Log "Launcher start. Server=$Server, User=$User, Mode=$Mode, LocalPath=$LocalPath, WinSCP DLL=$WinScpDllPath"

# Ensure local folder exists (create if missing)
if (-not (Test-Path $LocalPath)) {
    Try {
        New-Item -ItemType Directory -Path $LocalPath -Force | Out-Null
        Write-Log "Created missing local patch folder: $LocalPath"
    } catch {
        Write-Log "ERROR: Could not create local folder $LocalPath : $($_.Exception.Message)"
        throw "Local patch folder missing and could not be created."
    }
} else {
    Write-Log "Local patch folder exists: $LocalPath"
}

# Helper: recursive upload using WinSCP session
function Invoke-SftpUpload {
    param($session, $localRoot, $remoteRoot)
    $transferOptions = New-Object WinSCP.TransferOptions
    $transferOptions.TransferMode = [WinSCP.TransferMode]::Binary

    function UploadDirRec {
        param($localDir, $remoteDir)
        try { $session.CreateDirectory($remoteDir) } catch {}
        $items = Get-ChildItem -Path $localDir -Force
        foreach ($it in $items) {
            if ($it.PSIsContainer) {
                $subRemote = ($remoteDir.TrimEnd("/") + "/" + $it.Name)
                UploadDirRec -localDir $it.FullName -remoteDir $subRemote
            } else {
                $localFile = $it.FullName
                $remoteFile = $remoteDir.TrimEnd("/") + "/" + $it.Name
                Write-Log "SFTP: Uploading $localFile -> $remoteFile"
                $result = $session.PutFiles($localFile, $remoteFile, $false, $transferOptions)
                if ($result.IsSuccess) { Write-Log "SFTP: Uploaded $localFile" }
                else { foreach ($f in $result.Failures) { Write-Log "SFTP ERROR: $($f.FileName) : $($f.Message)" } }
            }
        }
    }

    UploadDirRec -localDir $localRoot -remoteDir $remoteRoot
}

# Attempt SFTP with WinSCP if DLL present
if (Test-Path $WinScpDllPath) {
    Try {
        Add-Type -Path $WinScpDllPath
        Write-Log "WinSCP .NET loaded from $WinScpDllPath"
        $sessionOptions = New-Object WinSCP.SessionOptions -Property @{
            Protocol = [WinSCP.Protocol]::Sftp
            HostName = $Server
            UserName = $User
            Password = $Password
            PortNumber = 22
            GiveUpSecurityAndAcceptAnySshHostKey = $true
        }
        $session = New-Object WinSCP.Session
        $session.Open($sessionOptions)
        Write-Log "Connected via SFTP to $Server"

        # Detect remote webroot candidates
        $candidates = @("/public_html","/www","/httpdocs","/htdocs","/site/wwwroot","/public","/html","/home","/")
        $remoteRoot = $null
        foreach ($p in $candidates) {
            try {
                $listing = $session.ListDirectory($p) 2>$null
                if ($null -ne $listing) { $remoteRoot = $p; Write-Log "Remote candidate detected: $p"; break }
            } catch { Write-Log "SFTP: Not accessible: $p" }
        }
        if (-not $remoteRoot) {
            Write-Log "SFTP: No standard root found. Picking first directory under / (best-effort)."
            $rootList = $session.ListDirectory("/")
            $firstDir = $rootList.Files | Where-Object { $_.IsDirectory -and -not ($_.Name.StartsWith(".")) } | Select-Object -First 1
            if ($firstDir) { $remoteRoot = "/" + $firstDir.Name.TrimStart("/"); Write-Log "SFTP: Using $remoteRoot" } else { $remoteRoot="/" ; Write-Log "SFTP: Falling back to /" }
        }

        if ($Mode -eq "test") {
            $ts = Get-Date -Format "yyyyMMdd_HHmmss"
            $remoteTarget = ($remoteRoot.TrimEnd("/")) + "/chhama_patch_test_$ts"
            try { $session.CreateDirectory($remoteTarget); Write-Log "SFTP: Created test folder $remoteTarget" } catch { Write-Log "SFTP: Could not create test folder (server may restrict)" }
        } else {
            $remoteTarget = $remoteRoot
            $backup = ($remoteRoot.TrimEnd("/")) + "/backup_$(Get-Date -Format yyyyMMdd_HHmmss)"
            try { $session.CreateDirectory($backup); Write-Log "SFTP: Created backup folder $backup (empty)" } catch { Write-Log "SFTP: Could not create backup folder" }
        }

        Invoke-SftpUpload -session $session -localRoot (Resolve-Path $LocalPath).Path -remoteRoot $remoteTarget

        # basic verification
        $verify = @("index.php","index.html","chhama-check.php")
        $foundVerify = $false
        foreach ($v in $verify) {
            try { if ($session.FileExists($remoteTarget.TrimEnd('/') + "/" + $v)) { Write-Log "SFTP: Verification file present: $v"; $foundVerify=$true; break } } catch {}
        }
        if (-not $foundVerify) { Write-Log "SFTP: No verification file found (manual check recommended)." } else { Write-Log "SFTP: Post-upload verification OK." }

        $session.Dispose()
        Write-Log "SFTP session closed. Done."
        Write-Host "`n✅ Completed SFTP upload. See log: $logFile"
        exit 0
    } catch {
        Write-Log "SFTP ERROR: $($_.Exception.GetType().FullName) - $($_.Exception.Message)"
        if ($session) { try { $session.Dispose() } catch {} }
        Write-Log "Falling back to FTP (.NET) due to SFTP error."
    }
} else {
    Write-Log "WinSCP .NET not found at $WinScpDllPath - skipping SFTP and using FTP fallback."
}

# ---------- FTP fallback using .NET FtpWebRequest ----------
Write-Log "Starting FTP fallback (.NET). Attempting plain FTP (port 21)."

# Convert password to plain string if secure string passed (we use string here)
$plainPass = [string]$Password

# Remote webroot candidates
$commonRoots = @("/public_html","/www","/httpdocs","/htdocs","/site/wwwroot","/public","/html","/")

function RemotePathExists_FTP {
    param($remotePath)
    try {
        $uri = "ftp://$Server$remotePath"
        $req = [System.Net.FtpWebRequest]::Create($uri)
        $req.Method = [System.Net.WebRequestMethods+Ftp]::ListDirectory
        $req.Credentials = New-Object System.Net.NetworkCredential($User, $plainPass)
        $req.UsePassive = $true
        $req.UseBinary = $true
        $resp = $req.GetResponse()
        $resp.Close()
        return $true
    } catch {
        return $false
    }
}

$RemoteRoot = $null
foreach ($r in $commonRoots) {
    if (RemotePathExists_FTP $r) { $RemoteRoot = $r; Write-Log "FTP: detected remote root $r"; break }
    else { Write-Log "FTP: not found or inaccessible $r" }
}

if (-not $RemoteRoot) {
    Write-Log "FTP: Trying root listing and picking first directory (best-effort)."
    try {
        $uri = "ftp://$Server/"
        $req = [System.Net.FtpWebRequest]::Create($uri)
        $req.Method = [System.Net.WebRequestMethods+Ftp]::ListDirectoryDetails
        $req.Credentials = New-Object System.Net.NetworkCredential($User, $plainPass)
        $req.UsePassive = $true
        $req.UseBinary = $true
        $resp = $req.GetResponse()
        $sr = New-Object System.IO.StreamReader($resp.GetResponseStream())
        $lines = $sr.ReadToEnd().Trim() -split "`n" | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
        $resp.Close()
        if ($lines.Count -gt 0) {
            $first = $lines[0] -split "\s+" | Select-Object -Last 1
            $candidate = "/$first"
            if (RemotePathExists_FTP $candidate) { $RemoteRoot = $candidate; Write-Log "FTP: using first directory $candidate" }
        }
    } catch {
        Write-Log "FTP: root listing failed: $($_.Exception.Message)"
    }
}

if (-not $RemoteRoot) {
    Write-Log "FTP: Could not detect remote webroot. Aborting FTP fallback."
    Write-Host "`n❌ Could not detect remote webroot for FTP. Check credentials, DNS or enable SFTP and try again. See log: $logFile"
    exit 1
}

if ($Mode -eq "test") {
    $ts = Get-Date -Format "yyyyMMdd_HHmmss"
    $remoteTarget = $RemoteRoot.TrimEnd('/') + "/chhama_patch_test_$ts"
    Write-Log "FTP test mode target: $remoteTarget"
    try {
        $uri = "ftp://$Server$remoteTarget"
        $req = [System.Net.FtpWebRequest]::Create($uri)
        $req.Method = [System.Net.WebRequestMethods+Ftp]::MakeDirectory
        $req.Credentials = New-Object System.Net.NetworkCredential($User, $plainPass)
        $req.UsePassive = $true
        $req.UseBinary = $true
        $resp = $req.GetResponse()
        $resp.Close()
        Write-Log "FTP: created remote test folder $remoteTarget"
    } catch { Write-Log "FTP: could not create test folder (server may restrict MKD)" }
} else {
    $remoteTarget = $RemoteRoot
    $backup = $RemoteRoot.TrimEnd('/') + "/backup_$(Get-Date -Format yyyyMMdd_HHmmss)"
    try {
        $uri = "ftp://$Server$backup"
        $req = [System.Net.FtpWebRequest]::Create($uri)
        $req.Method = [System.Net.WebRequestMethods+Ftp]::MakeDirectory
        $req.Credentials = New-Object System.Net.NetworkCredential($User, $plainPass)
        $req.UsePassive = $true
        $req.UseBinary = $true
        $resp = $req.GetResponse()
        $resp.Close()
        Write-Log "FTP: created backup folder $backup"
    } catch { Write-Log "FTP: could not create backup folder (server may restrict)" }
}

# Upload helper
function UploadFile_FTP {
    param($localFile, $remoteFile)
    try {
        $uri = "ftp://$Server$remoteFile"
        $req = [System.Net.FtpWebRequest]::Create($uri)
        $req.Method = [System.Net.WebRequestMethods+Ftp]::UploadFile
        $req.Credentials = New-Object System.Net.NetworkCredential($User, $plainPass)
        $req.UseBinary = $true
        $req.UsePassive = $true
        $bytes = [System.IO.File]::ReadAllBytes($localFile)
        $req.ContentLength = $bytes.Length
        $stream = $req.GetRequestStream()
        $stream.Write($bytes,0,$bytes.Length)
        $stream.Close()
        $resp = $req.GetResponse()
        $resp.Close()
        Write-Log "FTP: Uploaded $localFile -> $remoteFile"
    } catch {
        Write-Log "FTP ERROR uploading $localFile -> $remoteFile : $($_.Exception.Message)"
    }
}

# Recursive upload
$localRootFull = (Resolve-Path $LocalPath).Path
$files = Get-ChildItem -Path $localRootFull -Recurse -File
Write-Log "FTP: Found $($files.Count) files to upload from $localRootFull"
foreach ($f in $files) {
    $relative = $f.FullName.Substring($localRootFull.Length).TrimStart('\','/')
    $relativeUnix = $relative -replace '\\','/'
    $remote = $remoteTarget.TrimEnd('/') + "/" + $relativeUnix
    # ensure remote dir (best-effort)
    $remoteDir = [System.IO.Path]::GetDirectoryName($remote).Replace('\','/')
    try {
        $uri = "ftp://$Server$remoteDir"
        $mkr = [System.Net.FtpWebRequest]::Create($uri)
        $mkr.Method = [System.Net.WebRequestMethods+Ftp]::MakeDirectory
        $mkr.Credentials = New-Object System.Net.NetworkCredential($User, $plainPass)
        $mkr.UsePassive=$true; $mkr.UseBinary=$true
        $mkr.GetResponse() | Out-Null
    } catch {}
    if ($Mode -eq "test") { Write-Log "FTP(TEST) Would upload: $($f.FullName) -> $remote" } else { UploadFile_FTP $f.FullName $remote }
}

Write-Log "FTP: Upload step finished. Remote target: $remoteTarget"
Write-Host "`nDone. Check log: $logFile"
exit 0
