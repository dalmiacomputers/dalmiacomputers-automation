# create_shortcut.ps1
# Creates a small .bat file on Desktop which launches run_all.ps1 as elevated PowerShell.
# This avoids complex shortcut quoting issues. Run this script from the CHHAMA folder.

$scriptPath = (Get-Location).Path + "\run_all.ps1"
$desktop = [Environment]::GetFolderPath("Desktop")
$batPath = Join-Path $desktop "CHHAMA Launcher.bat"

# Build a single-line command that starts a new elevated PowerShell and runs run_all.ps1
# We carefully concatenate so quotes are correct.
$argLine = '-NoProfile -ExecutionPolicy Bypass -File "' + $scriptPath + '"'
$startCmd = 'Start-Process powershell -ArgumentList ''' + $argLine + ''' -Verb RunAs'
$batContent = 'powershell -NoProfile -ExecutionPolicy Bypass -Command "' + $startCmd + '"'

# Save to desktop
Set-Content -Path $batPath -Value $batContent -Encoding ASCII -Force
Write-Host "Created launcher (bat) on Desktop:" $batPath
Write-Host "Double-click 'CHHAMA Launcher.bat' and allow UAC (Run as administrator)."
