<#
Robust chhama_one_click_patch_fixed.ps1
Safe: uses single-quoted here-string when written so $vars inside function definitions are preserved.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Log([string]$m){
    $ts = (Get-Date).ToString("u")
    $line = "[$ts] $m"
    Write-Host $line
    Add-Content -Path ".\chhama_one_click_patch_run.log" -Value $line
}

function EnsureDir([string]$p){ if (-not (Test-Path $p)) { New-Item -Path $p -ItemType Directory -Force | Out-Null } }

# Prompt for credentials
$ftpHostLocal = Read-Host "FTP Host (e.g. ftp.dalmiacomputers.in)"
$ftpUserLocal = Read-Host "FTP Username"
$ftpPassSecure = Read-Host "FTP Password (hidden)" -AsSecureString
$ftpPassLocal = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($ftpPassSecure))

$remoteRootLocal = Read-Host "Remote site path (default: /public_html). Enter / for root"
if ([string]::IsNullOrWhiteSpace($remoteRootLocal)) { $remoteRootLocal = "/public_html" }
$domainLocal = Read-Host "Public domain for verification (e.g. dalmiacomputers.in)"
if ([string]::IsNullOrWhiteSpace($domainLocal)) { $domainLocal = $ftpHostLocal }

$ts = (Get-Date).ToString("yyyyMMddTHHmmssZ")
$backupDir = Join-Path (Get-Location) ("backup_$ts")
$patchDir  = Join-Path (Get-Location) ("patch_$ts")
EnsureDir $backupDir
EnsureDir $patchDir

Log ("BackupDir={0} PatchDir={1}" -f $backupDir, $patchDir)

# Plain FTP recursive download (positional args)
function FtpDownloadRecursive([string]$ftpHostP,[string]$ftpUserP,[string]$ftpPassP,[string]$remotePathP,[string]$localPathP){
    EnsureDir $localPathP
    Log ("Starting FTP download: {0}{1} -> {2}" -f $ftpHostP, $remotePathP, $localPathP)
    $wc = New-Object System.Net.WebClient
    $wc.Credentials = New-Object System.Net.NetworkCredential($ftpUserP,$ftpPassP)
    try {
        $uriBase = "ftp://{0}{1}" -f $ftpHostP, $remotePathP.TrimEnd('/')
        $req = [System.Net.FtpWebRequest]::Create($uriBase)
        $req.Method = [System.Net.WebRequestMethods+Ftp]::ListDirectory
        $req.Credentials = $wc.Credentials
        $resp = $req.GetResponse()
        $sr = New-Object System.IO.StreamReader($resp.GetResponseStream())
        $entries = @()
        while (-not $sr.EndOfStream) { $entries += $sr.ReadLine() }
        $sr.Close(); $resp.Close()
        foreach ($e in $entries) {
            if ([string]::IsNullOrWhiteSpace($e)) { continue }
            $remoteFile = "{0}/{1}" -f $remotePathP.TrimEnd('/'), $e
            $localFile = Join-Path $localPathP $e
            try {
                $fileUri = "ftp://{0}{1}" -f $ftpHostP, $remoteFile
                $wc.DownloadFile($fileUri, $localFile)
                Log ("Downloaded {0}" -f $remoteFile)
            } catch {
                EnsureDir $localFile
                FtpDownloadRecursive $ftpHostP $ftpUserP $ftpPassP $remoteFile $localFile
            }
        }
    } catch {
        Log ("FTP download failed: {0}" -f $_.Exception.Message)
        throw $_
    } finally {
        $wc.Dispose()
    }
}

# Plain FTP upload
function FtpUploadFile([string]$ftpHostP,[string]$ftpUserP,[string]$ftpPassP,[string]$localFileP,[string]$remoteFileP){
    $uri = "ftp://{0}{1}" -f $ftpHostP, $remoteFileP
    $req = [System.Net.FtpWebRequest]::Create($uri)
    $req.Method = [System.Net.WebRequestMethods+Ftp]::UploadFile
    $req.Credentials = New-Object System.Net.NetworkCredential($ftpUserP,$ftpPassP)
    $bytes = [System.IO.File]::ReadAllBytes($localFileP)
    $req.ContentLength = $bytes.Length
    $stream = $req.GetRequestStream()
    $stream.Write($bytes,0,$bytes.Length)
    $stream.Close()
    $resp = $req.GetResponse()
    $resp.Close()
    Log ("Uploaded {0} -> {1}" -f $localFileP, $remoteFileP)
}

# Create patch files
function CreatePatch([string]$outDir){
    EnsureDir $outDir
    EnsureDir (Join-Path $outDir "css")
    $css = ':root{--primary:#0a4d8c}body{font-family:Arial,Helvetica,sans-serif;margin:0;padding:0}.container{max-width:1200px;margin:0 auto;padding:0 16px}'
    Set-Content -Path (Join-Path $outDir "css\style.css") -Value $css -Encoding UTF8
    Set-Content -Path (Join-Path $outDir "robots.txt") -Value ("User-agent: *`nDisallow:`nSitemap: https://{0}/sitemap.xml" -f $domainLocal)
    $smap = '<?xml version="1.0" encoding="UTF-8"?><urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"><url><loc>https://' + $domainLocal + '</loc></url></urlset>'
    Set-Content -Path (Join-Path $outDir "sitemap.xml") -Value $smap -Encoding UTF8
    EnsureDir (Join-Path $outDir "assets")
    $svg = "<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 300 100'><rect width='100%' height='100%' fill='#0a4d8c'/><text x='50%' y='55%' font-family='Verdana' font-size='20' fill='#fff' text-anchor='middle'>Dalmia</text></svg>"
    Set-Content -Path (Join-Path $outDir "assets\dc-logo.svg") -Value $svg -Encoding UTF8
    EnsureDir (Join-Path $outDir "pages\products")
    $page = '<!doctype html><html lang="en"><head><meta charset="utf-8"><title>Products</title><link rel="stylesheet" href="/css/style.css"></head><body><h1>Products (placeholder)</h1></body></html>'
    Set-Content -Path (Join-Path $outDir "pages\products\index.html") -Value $page -Encoding UTF8
    Log ("Patch files created in {0}" -f $outDir)
}

# Run download
try {
    FtpDownloadRecursive $ftpHostLocal $ftpUserLocal $ftpPassLocal $remoteRootLocal $backupDir
} catch {
    Log ("Download stage failed: {0}" -f $_.Exception.Message)
}

# Zip backup
$zipPath = "$backupDir.zip"
if (Test-Path $zipPath) { Remove-Item $zipPath -Force }
Add-Type -AssemblyName System.IO.Compression.FileSystem
[System.IO.Compression.ZipFile]::CreateFromDirectory($backupDir, $zipPath)
Log ("Backup zipped to {0}" -f $zipPath)

# Create patch and upload
CreatePatch $patchDir

Get-ChildItem -Path (Join-Path $patchDir "css") -File -Recurse | ForEach-Object {
    $rel = $_.FullName.Substring((Join-Path $patchDir "css").Length).TrimStart('\','/')
    $remote = ("{0}/css/{1}" -f $remoteRootLocal.TrimEnd('/'), $rel) -replace '\\','/'
    FtpUploadFile $ftpHostLocal $ftpUserLocal $ftpPassLocal $_.FullName $remote
}
Get-ChildItem -Path (Join-Path $patchDir "assets") -File -Recurse | ForEach-Object {
    $rel = $_.FullName.Substring((Join-Path $patchDir "assets").Length).TrimStart('\','/')
    $remote = ("{0}/assets/{1}" -f $remoteRootLocal.TrimEnd('/'), $rel) -replace '\\','/'
    FtpUploadFile $ftpHostLocal $ftpUserLocal $ftpPassLocal $_.FullName $remote
}
Get-ChildItem -Path (Join-Path $patchDir "pages") -File -Recurse | ForEach-Object {
    $rel = $_.FullName.Substring((Join-Path $patchDir "pages").Length).TrimStart('\','/')
    $remote = ("{0}/pages/{1}" -f $remoteRootLocal.TrimEnd('/'), $rel) -replace '\\','/'
    FtpUploadFile $ftpHostLocal $ftpUserLocal $ftpPassLocal $_.FullName $remote
}
foreach ($f in @("robots.txt","sitemap.xml")) {
    $local = Join-Path $patchDir $f
    if (Test-Path $local) {
        FtpUploadFile $ftpHostLocal $ftpUserLocal $ftpPassLocal $local ("{0}/{1}" -f $remoteRootLocal.TrimEnd('/'), $f)
    }
}

# Verify HTTP
try {
    $u = "https://{0}" -f $domainLocal
    Log ("Verifying {0} ..." -f $u)
    $r = Invoke-WebRequest -Uri $u -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
    Log ("HTTP {0} bytes {1}" -f $r.StatusCode, $r.RawContentLength)
} catch {
    Log ("HTTPS verify failed: {0}. Trying HTTP..." -f $_.Exception.Message)
    try {
        $r2 = Invoke-WebRequest -Uri ("http://{0}" -f $domainLocal) -UseBasicParsing -TimeoutSec 10 -ErrorAction Stop
        Log ("HTTP {0} bytes {1}" -f $r2.StatusCode, $r2.RawContentLength)
    } catch {
        Log ("HTTP verify failed: {0}" -f $_.Exception.Message)
    }
}

Log "All done. Check logs and backup zip."
