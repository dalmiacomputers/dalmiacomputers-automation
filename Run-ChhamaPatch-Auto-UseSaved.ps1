<#
Run-ChhamaPatch-Auto-UseSaved.ps1
Auto launcher — reads saved creds if present at %USERPROFILE%\.chhama\chhama_creds.xml
Otherwise prompts interactively.
#>

$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Definition
$defaultLocal = Join-Path $scriptDir "patch_files"
$defaultWinScpDll = "C:\Program Files (x86)\WinSCP\WinSCPnet.dll"
$credFile = Join-Path $env:USERPROFILE ".chhama\chhama_creds.xml"

function Write-Log { param($m) $t=(Get-Date).ToString("yyyy-MM-dd HH:mm:ss"); Add-Content -Path (Join-Path $scriptDir "chhama_patch_auto_use_saved.log") -Value "$t`t$m"; Write-Host $m }

# Load saved credentials if present
if (Test-Path $credFile) {
    try {
        $SavedCred = Import-Clixml -Path $credFile
        Write-Log "Loaded saved credentials from $credFile"
        $Server = Read-Host "Server host or IP (press Enter to use previous server when run earlier)" 
        if ([string]::IsNullOrWhiteSpace($Server)) {
            # If the script previously stored server info locally, we could load it; fallback to prompt
            $Server = Read-Host "Enter Server host or IP (example: 107.180.113.63)"
        }
        $User = $SavedCred.UserName
        $Password = $SavedCred.GetNetworkCredential().Password
    } catch {
        Write-Log "Failed to load saved credentials: $($_.Exception.Message). Falling back to interactive input."
        $Server = Read-Host "Server host or IP (example: 107.180.113.63)"
        $User = Read-Host "Username"
        $Password = Read-Host "Password (won't be stored)"
    }
} else {
    # interactive fallback
    $Server = Read-Host "Server host or IP (example: 107.180.113.63)"
    $User = Read-Host "Username (example: amitdalmia@dalmiacomputers.in)"
    $Password = Read-Host "Password (won't be stored)"
}

$LocalPath = Read-Host "Local patch folder (press Enter for default: $defaultLocal)"
if ([string]::IsNullOrWhiteSpace($LocalPath)) { $LocalPath = $defaultLocal }
$Mode = Read-Host "Mode (test/live). Default: test"
if ($Mode -ne "live") { $Mode = "test" }
$WinScpDllPath = Read-Host "Path to WinSCPnet.dll (press Enter for default: $defaultWinScpDll)"
if ([string]::IsNullOrWhiteSpace($WinScpDllPath)) { $WinScpDllPath = $defaultWinScpDll }

Write-Log "Launcher start. Server=$Server, User=$User, Mode=$Mode"

# (Then reuse the same logic from the earlier Auto launcher to try SFTP->FTP.)
# For brevity, call your existing Run-ChhamaPatch-Auto.ps1 with parameters:
$existingLauncher = Join-Path $scriptDir "Run-ChhamaPatch-Auto.ps1"
if (Test-Path $existingLauncher) {
    & pwsh -NoProfile -ExecutionPolicy Bypass -File $existingLauncher -Server $Server -User $User -Password $Password -LocalPath $LocalPath -Mode $Mode -WinScpDllPath $WinScpDllPath
} else {
    Write-Log "Existing Run-ChhamaPatch-Auto.ps1 not found. Either copy it or run the main sftp/ftp script directly."
}
