<#
Launcher for SFTP uploader (WinSCP). Interactive prompt collects credentials and calls main script.
#>

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$mainScript = Join-Path $scriptDir "chhama_sftp_autonormalize_and_patch.ps1"
$defaultLocal = Join-Path $scriptDir "patch_files"
$defaultDll = "C:\Program Files (x86)\WinSCP\WinSCPnet.dll"

if (-not (Test-Path $mainScript)) {
    Write-Host "ERROR: Main script not found: $mainScript" -ForegroundColor Red
    exit 1
}

$Host = Read-Host "SFTP host (example: ftp.dalmiacomputers.in or IP)"
$User = Read-Host "SFTP username (example: amitdalmia@dalmiacomputers.in)"
$Password = Read-Host "SFTP password (won't be stored)"
$LocalPath = Read-Host "Local patch folder (press Enter for default: $defaultLocal)"
if ([string]::IsNullOrWhiteSpace($LocalPath)) { $LocalPath = $defaultLocal }

$Mode = Read-Host "Mode (test/live). Default: test"
if ($Mode -ne "live") { $Mode = "test" }

$WinScpDllPath = Read-Host "WinSCP .NET DLL path (press Enter for default: $defaultDll)"
if ([string]::IsNullOrWhiteSpace($WinScpDllPath)) { $WinScpDllPath = $defaultDll }

$logFile = Join-Path $scriptDir "chhama_sftp_launcher_$(Get-Date -Format yyyyMMdd_HHmmss).log"
Write-Host "`nStarting SFTP launcher. Log -> $logFile`n"

# Run the main script (pass password as plain string)
& pwsh -NoProfile -ExecutionPolicy Bypass -File $mainScript `
    -Host $Host -User $User -Password $Password -LocalPath $LocalPath -Mode $Mode -Log $logFile -WinScpDllPath $WinScpDllPath

if ($LASTEXITCODE -ne 0) {
    Write-Host "`nScript returned non-zero exit code: $LASTEXITCODE" -ForegroundColor Yellow
} else {
    Write-Host "`n✅ SFTP script finished successfully. Check log: $logFile"
}

Write-Host ""
Write-Host "Recommended next steps:"
Write-Host " 1) Inspect log file for any failed uploads."
Write-Host " 2) If test mode: open your hosting file manager or SFTP client to inspect created test folder."
Write-Host " 3) If all good, run again with Mode=live to deploy to the detected webroot."
