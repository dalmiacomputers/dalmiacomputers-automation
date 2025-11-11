<#
CHHAMA FTP auto-normalize + patch uploader
This version accepts -Password as either a SecureString or plain string (launcher-friendly).
#>

param(
    [Parameter(Mandatory=$true)][string]$FtpHost,
    [Parameter(Mandatory=$true)][string]$User,
    [Parameter(Mandatory=$true)][AllowNull()][object]$Password,
    [Parameter(Mandatory=$true)][string]$LocalPath,
    [ValidateSet("test","live")][string]$Mode = "test",
    [string]$Log = ".\chhama_patch_log.txt"
)

function Write-Log {
    param($msg)
    $timestamp = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    Add-Content -Path $Log -Value "$timestamp`t$msg"
    Write-Host $msg
}

# Normalize password: accept SecureString or plain string
if ($null -eq $Password) {
    Write-Log "ERROR: Password parameter is empty."
    throw "Password is required."
}

if ($Password -is [System.Security.SecureString]) {
    $plainPass = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
        [Runtime.InteropServices.Marshal]::SecureStringToBSTR($Password)
    )
} elseif ($Password -is [string]) {
    # Got plain string from launcher; convert to secure in-memory (but we need plain for .NET FTP client)
    $plainPass = $Password
} else {
    # Unexpected type - attempt ToString()
    $plainPass = [string]$Password
}

Write-Log "Starting CHHAMA FTP auto-normalize. Host=$FtpHost, User=$User, Mode=$Mode, LocalPath=$LocalPath"

if (-not (Test-Path $LocalPath)) {
    Write-Log "ERROR: LocalPath '$LocalPath' not found."
    throw "LocalPath not found."
}

$commonRoots = @("/public_html","/www","/httpdocs","/htdocs","/site/wwwroot","/public","/html","/")

function RemotePathExists {
    param($remotePath)
    try {
        $uri = "ftp://$FtpHost$remotePath"
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

$found = $null
foreach ($p in $commonRoots) {
    if (RemotePathExists $p) {
        Write-Log "Detected accessible remote path: $p"
        $found = $p
        break
    } else {
        Write-Log "Not found or inaccessible: $p"
    }
}

if (-not $found) {
    Write-Log "No standard root detected; attempting root listing..."
    try {
        $uri = "ftp://$FtpHost/"
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
            if (RemotePathExists $candidate) {
                $found = $candidate
                Write-Log "Using first directory found: $found"
            }
        }
    } catch {
        Write-Log "Failed to list root '/'. Error: $($_.Exception.Message)"
    }
}

if (-not $found) {
    Write-Log "ERROR: Could not detect a writable remote webroot. Aborting."
    throw "No writable remote webroot detected."
}

if ($Mode -eq "test") {
    $timestamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
    $remoteTarget = "$found/chhama_patch_test_$timestamp"
    Write-Log "Test mode active -> remote target: $remoteTarget"
    # attempt to create test dir (best-effort)
    try {
        $uri = "ftp://$FtpHost$remoteTarget"
        $req = [System.Net.FtpWebRequest]::Create($uri)
        $req.Method = [System.Net.WebRequestMethods+Ftp]::MakeDirectory
        $req.Credentials = New-Object System.Net.NetworkCredential($User, $plainPass)
        $req.UseBinary = $true
        $req.UsePassive = $true
        $resp = $req.GetResponse()
        $resp.Close()
        Write-Log "Created remote test folder $remoteTarget"
    } catch {
        Write-Log "Could not create test folder (server may restrict MKD). Continuing."
    }
} else {
    $remoteTarget = $found
    Write-Log "Live mode -> remote target: $remoteTarget"
    # attempt to create backup folder (best-effort)
    $backupName = "backup_$(Get-Date -Format yyyyMMdd_HHmmss)"
    $backupPath = "$found/$backupName"
    try {
        $uri = "ftp://$FtpHost$backupPath"
        $req = [System.Net.FtpWebRequest]::Create($uri)
        $req.Method = [System.Net.WebRequestMethods+Ftp]::MakeDirectory
        $req.Credentials = New-Object System.Net.NetworkCredential($User, $plainPass)
        $req.UseBinary = $true
        $req.UsePassive = $true
        $resp = $req.GetResponse()
        $resp.Close()
        Write-Log "Created backup folder $backupPath (empty)."
    } catch {
        Write-Log "Could not create backup folder $backupPath (server may restrict)."
    }
}

function Ensure-RemoteDirectory {
    param($remoteDir)
    try {
        $uri = "ftp://$FtpHost$remoteDir"
        $req = [System.Net.FtpWebRequest]::Create($uri)
        $req.Method = [System.Net.WebRequestMethods+Ftp]::MakeDirectory
        $req.Credentials = New-Object System.Net.NetworkCredential($User, $plainPass)
        $req.UseBinary = $true
        $req.UsePassive = $true
        $resp = $req.GetResponse()
        $resp.Close()
    } catch {
        # ignore errors (directory may already exist)
    }
}

function Upload-File {
    param($localFile, $remoteFile)
    try {
        $uri = "ftp://$FtpHost$remoteFile"
        $req = [System.Net.FtpWebRequest]::Create($uri)
        $req.Method = [System.Net.WebRequestMethods+Ftp]::UploadFile
        $req.Credentials = New-Object System.Net.NetworkCredential($User, $plainPass)
        $req.UseBinary = $true
        $req.UsePassive = $true
        $bytes = [System.IO.File]::ReadAllBytes($localFile)
        $req.ContentLength = $bytes.Length
        $reqStream = $req.GetRequestStream()
        $reqStream.Write($bytes, 0, $bytes.Length)
        $reqStream.Close()
        $resp = $req.GetResponse()
        $resp.Close()
        Write-Log "Uploaded: $localFile -> $remoteFile"
        return $true
    } catch {
        Write-Log "ERROR uploading $localFile -> $remoteFile : $($_.Exception.Message)"
        return $false
    }
}

$localFull = Resolve-Path $LocalPath
$files = Get-ChildItem -Path $localFull -Recurse -File
Write-Log "Preparing to upload $($files.Count) files from $localFull"

foreach ($f in $files) {
    $relative = $f.FullName.Substring($localFull.Path.Length).TrimStart('\','/')
    $relativeUnix = $relative -replace '\\','/'
    $remotePath = $remoteTarget.TrimEnd('/') + "/" + $relativeUnix
    $remoteDir = ([System.IO.Path]::GetDirectoryName($remotePath)).Replace('\','/')
    Ensure-RemoteDirectory $remoteDir
    if ($Mode -eq "test") {
        Write-Log "(TEST) Would upload $($f.FullName) -> $remotePath"
    } else {
        Upload-File $f.FullName $remotePath
    }
}

Write-Log "Upload step finished. Remote target: $remoteTarget"

# Basic post-upload verification
$verifyCandidates = @("/index.php","/index.html","/chhama-check.php")
$foundVerify = $false
foreach ($cand in $verifyCandidates) {
    $candRemote = $remoteTarget.TrimEnd('/') + $cand
    if (RemotePathExists $candRemote) {
        Write-Log "Verification file detected at $candRemote"
        $foundVerify = $true
        break
    }
}

if (-not $foundVerify) {
    Write-Log "Warning: No standard verification file found in target. You may need to check site manually."
} else {
    Write-Log "Post-upload verification suggests files present."
}

Write-Log "CHHAMA FTP auto-normalize script completed."
