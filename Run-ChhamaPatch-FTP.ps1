<#
Launcher for CHHAMA FTP patch (fixed variable name conflict)
#>

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$mainScript = Join-Path $scriptDir "chhama_ftp_autonormalize_and_patch.ps1"
$defaultLocal = "C:\Users\Dalmia Computers\Downloads\chhama_windows_master\patch_files"

if (-not (Test-Path $mainScript)) {
    Write-Host "ERROR: Main script not found: $mainScript" -ForegroundColor Red
    exit 1
}

$FtpHost = Read-Host "FTP host or IP (example: 107.180.113.63)"
$FtpUser = Read-Host "FTP username"
$FtpPassword = Read-Host "FTP password (won't be stored)" -AsSecureString
$LocalPath = Read-Host "Local patch folder (press Enter for default: $defaultLocal)"
if ([string]::IsNullOrWhiteSpace($LocalPath)) { $LocalPath = $defaultLocal }

$Mode = Read-Host "Mode (test/live). Default: test"
if ($Mode -ne "live") { $Mode = "test" }

$logFile = Join-Path $scriptDir "chhama_patch_launcher_$(Get-Date -Format yyyyMMdd_HHmmss).log"
Write-Host "`nStarting launcher. Log -> $logFile`n"

& pwsh -NoProfile -ExecutionPolicy Bypass -File $mainScript `
    -FtpHost $FtpHost -User $FtpUser -Password $FtpPassword -LocalPath $LocalPath -Mode $Mode -Log $logFile

if ($LASTEXITCODE -ne 0) {
    Write-Host "Script returned non-zero exit code: $LASTEXITCODE" -ForegroundColor Yellow
} else {
    Write-Host "✅ Script finished successfully. Check log: $logFile"
}

Write-Host ""
Write-Host "Next steps:"
Write-Host " 1) If test mode: check ftp://$FtpHost for the test folder."
Write-Host " 2) If live mode: visit https://dalmiacomputers.in/"
Write-Host " 3) Check $logFile for upload summary."
