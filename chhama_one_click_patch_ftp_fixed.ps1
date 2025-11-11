<#
chhama_one_click_patch_ftp_fixed.ps1
FTP-based patch (host variable fixed)
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function LogLine([string]$m){
    $ts = (Get-Date).ToString("u")
    $line = "[$ts] $m"
    Write-Host $line
    Add-Content -Path ".\chhama_one_click_patch_ftp.log" -Value $line
}

# Collect info
$ftpHost = $env:CHHAMA_FTP_HOST
if ([string]::IsNullOrWhiteSpace($ftpHost)) { $ftpHost = Read-Host "FTP host or IP" }
$ftpUser = $env:CHHAMA_FTP_USER
if ([string]::IsNullOrWhiteSpace($ftpUser)) { $ftpUser = Read-Host "FTP username" }
$ftpPass = $env:CHHAMA_FTP_PASS
if ([string]::IsNullOrWhiteSpace($ftpPass)) {
    $secure = Read-Host "FTP password (hidden)" -AsSecureString
    $ftpPass = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure))
}
$remoteRoot = $env:CHHAMA_REMOTE_ROOT
if ([string]::IsNullOrWhiteSpace($remoteRoot)) { $remoteRoot = Read-Host "Remote site path (default /public_html)"; if (-not $remoteRoot) { $remoteRoot = "/public_html" } }
$domain = $env:CHHAMA_DOMAIN
if ([string]::IsNullOrWhiteSpace($domain)) { $domain = Read-Host "Public domain for verification"; if (-not $domain) { $domain = $ftpHost } }

LogLine "Starting FTP patch run. Host: $ftpHost RemoteRoot: $remoteRoot Domain: $domain"

function Ensure-LocalDir($p){ if (-not (Test-Path $p)) { New-Item -Path $p -ItemType Directory -Force | Out-Null } }
function New-FtpReq($method,$uri,$u,$p){
    $r=[System.Net.FtpWebRequest]::Create($uri)
    $r.Method=$method; $r.Credentials=New-Object System.Net.NetworkCredential($u,$p)
    $r.UseBinary=$true; $r.UsePassive=$true; $r.KeepAlive=$false; return $r
}

function Ftp-ListDir($ftpHost,$path,$u,$p){
    $uri="ftp://{0}{1}" -f $ftpHost,$path
    $req=New-FtpReq ([System.Net.WebRequestMethods+Ftp]::ListDirectory) $uri $u $p
    $resp=$req.GetResponse(); $sr=New-Object IO.StreamReader($resp.GetResponseStream())
    $items=@(); while(-not $sr.EndOfStream){$items+=$sr.ReadLine()};$sr.Close();$resp.Close();return $items
}

function Ftp-DownloadFile($ftpHost,$remote,$local,$u,$p){
    Ensure-LocalDir (Split-Path $local -Parent)
    try{
        $uri="ftp://{0}{1}" -f $ftpHost,$remote
        $r=New-FtpReq ([System.Net.WebRequestMethods+Ftp]::DownloadFile) $uri $u $p
        $resp=$r.GetResponse();$s=$resp.GetResponseStream();$fs=[IO.File]::OpenWrite($local)
        $b=New-Object byte[] 8192;while(($n=$s.Read($b,0,$b.Length)) -gt 0){$fs.Write($b,0,$n)}
        $fs.Close();$s.Close();$resp.Close();LogLine "Downloaded $remote -> $local";return $true
    }catch{return $false}
}

function Ftp-DownloadRec($ftpHost,$rpath,$lpath,$u,$p){
    Ensure-LocalDir $lpath
    try{$it=Ftp-ListDir $ftpHost $rpath $u $p}catch{LogLine "List failed $rpath";return}
    foreach($n in $it){if(-not $n){continue}
        $rchild="$($rpath.TrimEnd('/'))/$n";$lchild=Join-Path $lpath $n
        $ok=Ftp-DownloadFile $ftpHost $rchild $lchild $u $p
        if(-not $ok){Ftp-DownloadRec $ftpHost $rchild $lchild $u $p}
    }
}

function Ftp-MakeDir($ftpHost,$rdir,$u,$p){
    $parts=$rdir.Trim('/').Split('/')|?{$_}
    $acc="";foreach($pt in $parts){$acc+="/$pt";$uri="ftp://{0}{1}" -f $ftpHost,$acc
        $req=New-FtpReq ([System.Net.WebRequestMethods+Ftp]::MakeDirectory) $uri $u $p
        try{$req.GetResponse().Close()}catch{}}
}

function Ftp-UploadFile($ftpHost,$local,$remote,$u,$p){
    Ftp-MakeDir $ftpHost (Split-Path $remote -Parent) $u $p
    $uri="ftp://{0}{1}" -f $ftpHost,$remote
    $req=New-FtpReq ([System.Net.WebRequestMethods+Ftp]::UploadFile) $uri $u $p
    $bytes=[IO.File]::ReadAllBytes($local);$req.ContentLength=$bytes.Length
    $rs=$req.GetRequestStream();$rs.Write($bytes,0,$bytes.Length);$rs.Close();$req.GetResponse().Close()
    LogLine "Uploaded $local -> $remote"
}

$ts=(Get-Date).ToString("yyyyMMddTHHmmssZ")
$backup="backup_$ts";$patch="patch_$ts"
Ensure-LocalDir $backup;Ensure-LocalDir $patch

try{LogLine "Backing up site...";Ftp-DownloadRec $ftpHost $remoteRoot $backup $ftpUser $ftpPass}catch{LogLine "Backup error: $($_.Exception.Message)"}
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::CreateFromDirectory($backup,"$backup.zip")
LogLine "Backup zipped."

# Patch creation
Ensure-LocalDir (Join-Path $patch "css");Ensure-LocalDir (Join-Path $patch "assets");Ensure-LocalDir (Join-Path $patch "pages/products")
Set-Content (Join-Path $patch "css/style.css") ':root{--primary:#0a4d8c}body{font-family:Arial,Helvetica,sans-serif;margin:0;padding:0}'
Set-Content (Join-Path $patch "robots.txt") ("User-agent: *`nDisallow:`nSitemap: https://{0}/sitemap.xml" -f $domain)
$smap='<?xml version="1.0"?><urlset xmlns="http://www.sitemaps.org/schemas/sitemap/0.9"><url><loc>https://' + $domain + '</loc></url></urlset>'
Set-Content (Join-Path $patch "sitemap.xml") $smap
Set-Content (Join-Path $patch "pages/products/index.html") '<!doctype html><html><body><h1>Products placeholder</h1></body></html>'
$svg="<svg xmlns='http://www.w3.org/2000/svg' viewBox='0 0 300 100'><rect width='100%' height='100%' fill='#0a4d8c'/><text x='50%' y='55%' font-size='20' fill='#fff' text-anchor='middle'>Dalmia</text></svg>"
Set-Content (Join-Path $patch "assets/dc-logo.svg") $svg
LogLine "Patch files created."

# Upload
try{
    foreach($folder in @("css","assets","pages")){
        Get-ChildItem -Path (Join-Path $patch $folder) -File -Recurse | ForEach-Object {
            $rel=$_.FullName.Substring((Join-Path $patch $folder).Length).TrimStart('\','/')
            $remote=($remoteRoot.TrimEnd('/') + "/$folder/" + $rel) -replace '\\','/'
            Ftp-UploadFile $ftpHost $_.FullName $remote $ftpUser $ftpPass
        }
    }
    foreach($f in @("robots.txt","sitemap.xml")){
        $loc=Join-Path $patch $f
        if(Test-Path $loc){$remote=$remoteRoot.TrimEnd('/') + "/$f";Ftp-UploadFile $ftpHost $loc $remote $ftpUser $ftpPass}
    }
    LogLine "Upload stage finished."
}catch{LogLine "Upload error: $($_.Exception.Message)"}

# Verify site
try{
    $url="https://$domain"
    LogLine "Verifying $url ..."
    $r=Invoke-WebRequest -Uri $url -UseBasicParsing -TimeoutSec 15 -ErrorAction Stop
    LogLine "HTTP verify success: Status $($r.StatusCode)"
}catch{
    LogLine "Verify failed: $($_.Exception.Message)"
}

LogLine "One-click FTP patch finished."
