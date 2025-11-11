<#
chhama_one_click_patch_ftp.ps1
One-click FTP patch for CHHAMA (plain FTP, port 21)
- Reads env vars CHHAMA_FTP_HOST, CHHAMA_FTP_USER, CHHAMA_FTP_PASS, CHHAMA_REMOTE_ROOT, CHHAMA_DOMAIN if present
- Otherwise prompts interactively
- Backup (recursive), zip, create patch, upload patch, verify HTTP
Save to: chhama_one_click_patch_ftp.ps1
Run: pwsh -NoProfile -ExecutionPolicy Bypass -File .\chhama_one_click_patch_ftp.ps1
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function LogLine([string]$m){
    $ts = (Get-Date).ToString("u")
    $line = "[$ts] $m"
    Write-Host $line
    Add-Content -Path ".\chhama_one_click_patch_ftp.log" -Value $line
}

# Read env or prompt; avoid using $Host variable name
$ftpHostVar = $env:CHHAMA_FTP_HOST
if ([string]::IsNullOrWhiteSpace($ftpHostVar)) { $ftpHostVar = Read-Host "FTP host or IP (example: 107.180.113.63 or ftp.dalmiacomputers.in)" }

$ftpUserVar = $env:CHHAMA_FTP_USER
if ([string]::IsNullOrWhiteSpace($ftpUserVar)) { $ftpUserVar = Read-Host "FTP username (cPanel user or FTP user)" }

$ftpPassVar = $env:CHHAMA_FTP_PASS
if ([string]::IsNullOrWhiteSpace($ftpPassVar)) {
    $secure = Read-Host "FTP password (hidden)" -AsSecureString
    $ftpPassVar = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure))
}

$remoteRootVar = $env:CHHAMA_REMOTE_ROOT
if ([string]::IsNullOrWhiteSpace($remoteRootVar)) {
    $remoteRootVar = Read-Host "Remote site path (default /public_html). Enter / for root"
    if ([string]::IsNullOrWhiteSpace($remoteRootVar)) { $remoteRootVar = "/public_html" }
}
$domainVar = $env:CHHAMA_DOMAIN
if ([string]::IsNullOrWhiteSpace($domainVar)) {
    $domainVar = Read-Host "Public domain for verification (e.g. dalmiacomputers.in)"
    if ([string]::IsNullOrWhiteSpace($domainVar)) { $domainVar = $ftpHostVar }
}

LogLine "Starting FTP patch run. Host: $ftpHostVar  RemoteRoot: $remoteRootVar  Domain: $domainVar"

# Helpers
function Ensure-LocalDir([string]$p){ if (-not (Test-Path $p)) { New-Item -Path $p -ItemType Directory -Force | Out-Null } }

function New-FtpRequest([string]$method, [string]$uri, [string]$user, [string]$pass){
    $req = [System.Net.FtpWebRequest]::Create($uri)
    $req.Method = $method
    $req.Credentials = New-Object System.Net.NetworkCredential($user,$pass)
    $req.UseBinary = $true
    $req.UsePassive = $true
    $req.KeepAlive = $false
    return $req
}

# Recursive FTP list/download (tries to differentiate files vs dirs by trying to download; fallback)
function Ftp-ListDirectory([string]$host,[string]$path,[string]$user,[string]$pass){
    $uri = "ftp://{0}{1}" -f $host, $path
    $req = New-FtpRequest ([System.Net.WebRequestMethods+Ftp]::ListDirectory) $uri $user $pass
    try {
        $resp = $req.GetResponse()
        $sr = New-Object System.IO.StreamReader($resp.GetResponseStream())
        $items = @()
        while (-not $sr.EndOfStream) { $items += $sr.ReadLine() }
        $sr.Close(); $resp.Close()
        return $items
    } catch {
        throw $_
    }
}

function Ftp-DownloadFile([string]$host,[string]$remoteFile,[string]$localFile,[string]$user,[string]$pass){
    Ensure-LocalDir ((Split-Path $localFile -Parent))
    $uri = "ftp://{0}{1}" -f $host, $remoteFile
    $req = New-FtpRequest ([System.Net.WebRequestMethods+Ftp]::DownloadFile) $uri $user $pass
    try {
        $resp = $req.GetResponse()
        $stream = $resp.GetResponseStream()
        $fs = [System.IO.File]::OpenWrite($localFile)
        $buffer = New-Object byte[] 8192
        while (($read = $stream.Read($buffer,0,$buffer.Length)) -gt 0) { $fs.Write($buffer,0,$read) }
        $fs.Close(); $stream.Close(); $resp.Close()
        LogLine ("Downloaded: {0} -> {1}" -f $remoteFile, $localFile)
        return $true
    } catch {
        # LogLine ("Download failed for {0}: {1}" -f $remoteFile, $_.Exception.Message)
        return $false
    }
}

function Ftp-DownloadRecursive([string]$host,[string]$remotePath,[string]$localPath,[string]$user,[string]$pass){
    Ensure-LocalDir $localPath
    try {
        $items = Ftp-ListDirectory $host $remotePath $user $pass
    } catch {
        LogLine ("List directory failed on {0}: {1}" -f $remotePath, $_.Exception.Message)
        return
    }
    foreach ($it in $items) {
        if ([string]::IsNullOrWhiteSpace($it)) { continue }
        $remoteChild = ($remotePath.TrimEnd('/') + '/' + $it)
        $localChild  = Join-Path $localPath $it
        # Try to download — if download fails assume directory and recurse
        $ok = Ftp-DownloadFile $host $remoteChild $localChild $user $pass
        if (-not $ok) {
            # treat as directory
            Ftp-DownloadRecursive $host $remoteChild $localChild $user $pass
        }
    }
}

function Ftp-EnsureRemoteDir([string]$host,[string]$remoteDir,[string]$user,[string]$pass){
    # create directory recursively by splitting parts and calling MKD
    $parts = $remoteDir.Trim('/').Split('/') | Where-Object { $_ -ne "" }
    $acc = ""
    foreach ($p in $parts) {
        $acc = $acc + "/" + $p
        $uri = "ftp://{0}{1}" -f $host, $acc
        $req = New-FtpRequest ([System.Net.WebRequestMethods+Ftp]::MakeDirectory) $uri $user $pass
        try {
            $resp = $req.GetResponse()
            $resp.Close()
            LogLine ("Created remote dir: {0}" -f $acc)
        } catch {
            # ignore if exists; other errors logged
            $msg = $_.Exception.Message
            if ($msg -notmatch "550") { LogLine ("MKD error for {0}: {1}" -f $acc, $msg) }
        }
    }
}

function Ftp-UploadFile([string]$host,[string]$localFile,[string]$remoteFile,[string]$user,[string]$pass){
    $uri = "ftp://{0}{1}" -f $host, $remoteFile
    # ensure remote directory exists
    $remoteDir = (Split-Path $remoteFile -Parent)
    if ($remoteDir -and ($remoteDir -ne "")) { Ftp-EnsureRemoteDir $host $remoteDir $user $pass }
    $req = New-FtpRequest ([System.Net.WebRequestMethods+Ftp]::UploadFile) $uri $user $pass
    try {
        $bytes = [System.IO.File]::ReadAllBytes($localFile)
        $req.ContentLength = $bytes.Length
        $rs = $req.GetRequestStream()
        $rs.Write($bytes,0,$bytes.Length)
        $rs.Close()
        $resp = $req.GetResponse()
        $resp.Close()
        LogLine ("Uploaded {0} -> {1}" -f $localFile, $remoteFile)
    } catch {
        LogLine ("Upload failed: {0} -> {1}   {2}" -f $localFile, $remoteFile, $_.Exception.Message)
        throw $_
    }
}

# start operations
$ts = (Get-Date).ToString("yyyyMMddTHHmmssZ")
$backupDir = Join-Path (Get-Location) ("backup_$ts")
$patchDir  = Join-Path (Get-Location) ("patch_$ts")
Ensure-LocalDir $backupDir; Ensure-LocalDir $patchDir

LogLine ("BackupDir={0} PatchDir={1}" -f $backupDir, $patchDir)

# 1) Download remote tree into backup
try {
    LogLine "Starting FTP recursive download (this may take a few minutes)..."
    Ftp-DownloadRecursive $ftpHostVar $remoteRootVar $backupDir $ftpUserVar $ftpPassVar
    LogLine "Download stage finished (see backup folder)."
} catch {
    LogLine ("Download stage failed: {0}" -f $_.Exception.Message)
}

# 2) Zip backup
try {
    $zipFile = "$backupDir.zip"
    if (Test-Path $zipFile) { Remove-Item $zipFile -Force }
    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::CreateFromDirectory($backupDir, $zipFile)
    LogLine ("Backup zipped to {0}" -f $zipFile)
} catch {
    LogLine ("Zipping backup failed: {0}" -f $_.Exception.Message)
}

# 3) Create patch files
Ensure-LocalDir (Join-Path $patchDir "css")
Ensure-LocalDir (Join-Path $patchDir "assets")
Ensure-LocalDir (Join-Path $patchDir "pages\products")
$css = ':root{--primary:#0a4d8c}body{font-family:Arial,Helvetica,sans-serif;margin:0;padding:0}.container{max-width:1200px;margin:0 auto;padding:0 16px}'
Set-Content -Path (Join-Path $patchDir "css\style.css") -Value $css -Encoding UTF8
Set-Content -Path (Join-Path $patchDir "robots.txt") -Value ("User-agent: *`nDisallow:`nSitemap: https://{0}/sitemap.xml" -f $domainVar)
$smap = '<?xml version="1.0" encoding="UTF-8"?><urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"><url><loc>https://' + $domainVar + '</loc></url></urlset>'
Set-Content -Path (Join-Path $patchDir "sitemap.xml") -Value $smap -Encoding UTF8
$svg = "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 300 100'><rect width='100%' height='100%' fill='#0a4d8c'/><text x='50%' y='55%' font-family='Verdana' font-size='20' fill='#fff' text-anchor='middle'>Dalmia</text></svg>"
Set-Content -Path (Join-Path $patchDir "assets\dc-logo.svg") -Value $svg -Encoding UTF8
$page = '<!doctype html><html lang="en"><head><meta charset="utf-8"><title>Products</title><link rel="stylesheet" href="/css/style.css"></head><body><h1>Products (placeholder)</h1></body></html>'
Set-Content -Path (Join-Path $patchDir "pages\products\index.html") -Value $page -Encoding UTF8
LogLine "Patch files created."

# 4) Upload patch: css, assets, pages, top-level
try {
    # upload css
    Get-ChildItem -Path (Join-Path $patchDir "css") -File -Recurse | ForEach-Object {
        $rel = $_.FullName.Substring((Join-Path $patchDir "css").Length).TrimStart('\','/')
        $remote = ($remoteRootVar.TrimEnd('/') + "/css/" + $rel) -replace '\\','/'
        Ftp-UploadFile $ftpHostVar $_.FullName $remote $ftpUserVar $ftpPassVar
    }
    # assets
    Get-ChildItem -Path (Join-Path $patchDir "assets") -File -Recurse | ForEach-Object {
        $rel = $_.FullName.Substring((Join-Path $patchDir "assets").Length).TrimStart('\','/')
        $remote = ($remoteRootVar.TrimEnd('/') + "/assets/" + $rel) -replace '\\','/'
        Ftp-UploadFile $ftpHostVar $_.FullName $remote $ftpUserVar $ftpPassVar
    }
    # pages
    Get-ChildItem -Path (Join-Path $patchDir "pages") -File -Recurse | ForEach-Object {
        $rel = $_.FullName.Substring((Join-Path $patchDir "pages").Length).TrimStart('\','/')
        $remote = ($remoteRootVar.TrimEnd('/') + "/pages/" + $rel) -replace '\\','/'
        Ftp-UploadFile $ftpHostVar $_.FullName $remote $ftpUserVar $ftpPassVar
    }
    foreach ($f in @("robots.txt","sitemap.xml")) {
        $local = Join-Path $patchDir $f
        if (Test-Path $local) {
            $remote = ($remoteRootVar.TrimEnd('/') + "/" + $f)
            Ftp-UploadFile $ftpHostVar $local $remote $ftpUserVar $ftpPassVar
        }
    }
    LogLine "Upload stage finished."
} catch {
    LogLine ("Upload stage error: {0}" -f $_.Exception.Message)
}

# 5) Verify HTTP
try {
    $u = "https://$domainVar"
    LogLine ("Verifying $u ...")
    $r = Invoke-WebRequest -Uri $u -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
    LogLine ("HTTP verify success: Status {0}" -f $r.StatusCode)
} catch {
    LogLine ("HTTPS verify failed: {0}. Trying HTTP..." -f $_.Exception.Message)
    try {
        $r2 = Invoke-WebRequest -Uri ("http://{0}" -f $domainVar) -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
        LogLine ("HTTP verify success: Status {0}" -f $r2.StatusCode)
    } catch {
        LogLine ("HTTP verify failed: {0}" -f $_.Exception.Message)
    }
}

LogLine "One-click FTP patch finished. Check backup zip, patch folder and log file."
