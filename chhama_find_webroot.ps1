<#
chhama_find_webroot.ps1
Scans your FTP account recursively (top 2 levels) to locate your website root (public_html or similar).
#>

$server = Read-Host "FTP host or IP (e.g. 107.180.113.63)"
$user = Read-Host "FTP username (e.g. amitdalmia@dalmiacomputers.in)"
$pass = Read-Host "FTP password (won't be stored)"
Write-Host "`nScanning FTP structure for public_html or similar folders...`n"

$creds = New-Object System.Net.NetworkCredential($user, $pass)

function List-FTP($path) {
    try {
        $uri = "ftp://${server}${path}"
        $req = [System.Net.FtpWebRequest]::Create($uri)
        $req.Method = [System.Net.WebRequestMethods+Ftp]::ListDirectory
        $req.Credentials = $creds
        $req.UsePassive = $true
        $req.UseBinary = $true
        $resp = $req.GetResponse()
        $sr = New-Object System.IO.StreamReader($resp.GetResponseStream())
        $data = $sr.ReadToEnd().Split("`n") | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne "" }
        $resp.Close()
        return $data
    } catch {
        return @()
    }
}

$roots = @("/", "/home", "/var/www", "/domains", "/htdocs", "/public_html")
$found = @()

foreach ($r in $roots) {
    $items = List-FTP $r
    if ($items.Count -gt 0) {
        Write-Host ("Contents of {0}:" -f $r)
        $items | ForEach-Object { Write-Host ("  {0}" -f $_) }
        if ($items -match "public_html" -or $items -match "htdocs") {
            $found += $r
        }
    }
}

if ($found.Count -gt 0) {
    Write-Host "`n✅ Potential webroot found inside:" -ForegroundColor Green
    $found | ForEach-Object { Write-Host ("  {0}" -f $_) -ForegroundColor Cyan }
} else {
    Write-Host "`n⚠️ Could not find public_html directly. Check subfolders manually or share above listing." -ForegroundColor Yellow
}
