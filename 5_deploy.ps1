# 5_deploy.ps1
# Simple interactive deploy helper (FTP)
$cfg = @{}
if (Test-Path .\chhama.config.json) { $cfg = Get-Content .\chhama.config.json | ConvertFrom-Json }
$ftp = $cfg.ftp.host
if (-not $ftp) { $ftp = Read-Host "FTP host (e.g. ftp.dalmiacomputers.in)" }
$user = Read-Host "FTP user"
$pass = Read-Host -AsSecureString "FTP password"
$bpass = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($pass))
# Prepare zip
$zip = "$env:TEMP\site-deploy.zip"
if (Test-Path $zip) { Remove-Item $zip -Force }
Add-Type -AssemblyName System.IO.Compression.FileSystem
[IO.Compression.ZipFile]::CreateFromDirectory((Get-Location).Path, $zip)
Write-Host "Created $zip"
# Upload using WinSCP if present
$winscp = "C:\Program Files (x86)\WinSCP\WinSCP.com"
if (-not (Test-Path $winscp)) { $winscp = "C:\Program Files\WinSCP\WinSCP.com" }
if (Test-Path $winscp) {
  $script = "open ftp://$user:`"" + $bpass + "`"@${ftp} -passive=1`nput -delete `"$zip`" /public_html/site-deploy.zip`nclose`nexit"
  $tmp = "$env:TEMP\winscp-script.txt"
  $script | Out-File -FilePath $tmp -Encoding ASCII
  & $winscp /script=$tmp
  Write-Host "Uploaded to $ftp"
} else {
  Write-Host "WinSCP not found. Use FTP client or upload via cPanel."
}
