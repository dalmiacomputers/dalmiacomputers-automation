<#
chhama_sftp_autonormalize_and_patch.ps1
Secure uploader using WinSCP .NET assembly (SFTP).
Usage (called by launcher):
  pwsh -NoProfile -ExecutionPolicy Bypass -File .\chhama_sftp_autonormalize_and_patch.ps1 `
      -Host "ftp.dalmiacomputers.in" -User "amitdalmia@dalmiacomputers.in" `
      -Password "NEWPASSWORD" -LocalPath ".\patch_files" -Mode "test" -Log ".\sftp_patch_log.txt"

This script requires WinSCPnet.dll (installed with WinSCP). It will:
 - connect via SFTP (port 22)
 - detect remote webroot (common candidates)
 - create test folder if Mode=test
 - upload files recursively with PutFiles
 - log actions to the provided log file
#>

param(
    [Parameter(Mandatory=$true)][string]$Host,
    [Parameter(Mandatory=$true)][string]$User,
    [Parameter(Mandatory=$true)][string]$Password,
    [Parameter(Mandatory=$true)][string]$LocalPath,
    [ValidateSet("test","live")][string]$Mode = "test",
    [string]$Log = ".\chhama_sftp_patch_log.txt",
    [string]$WinScpDllPath = "C:\Program Files (x86)\WinSCP\WinSCPnet.dll"
)

function Write-Log { param($m) $t=(Get-Date).ToString("yyyy-MM-dd HH:mm:ss"); Add-Content -Path $Log -Value "$t`t$m"; Write-Host $m }

if (-not (Test-Path $WinScpDllPath)) {
    Write-Log "ERROR: WinSCP .NET DLL not found at $WinScpDllPath"
    throw "WinSCP .NET assembly missing. Install WinSCP and set -WinScpDllPath correctly."
}

Add-Type -Path $WinScpDllPath

Write-Log "Starting CHHAMA SFTP auto-normalize. Host=$Host, User=$User, Mode=$Mode, LocalPath=$LocalPath"

if (-not (Test-Path $LocalPath)) {
    Write-Log "ERROR: LocalPath '$LocalPath' not found."
    throw "LocalPath not found."
}

# Session options
$sessionOptions = New-Object WinSCP.SessionOptions -Property @{
    Protocol = [WinSCP.Protocol]::Sftp
    HostName = $Host
    UserName = $User
    Password = $Password
    PortNumber = 22
    GiveUpSecurityAndAcceptAnySshHostKey = $true
}

$session = New-Object WinSCP.Session
try {
    $session.Open($sessionOptions)
    Write-Log "Connected via SFTP to $Host"

    # Candidate webroots to check (try absolute paths and common cPanel style)
    $candidates = @("/public_html","/www","/httpdocs","/htdocs","/site/wwwroot","/public","/html","/home","/")
    $found = $null
    foreach ($p in $candidates) {
        try {
            $entry = $session.ListDirectory($p) 2>$null
            if ($null -ne $entry) {
                Write-Log "Detected remote candidate webroot: $p"
                $found = $p
                break
            }
        } catch {
            Write-Log "Not found or inaccessible: $p"
        }
    }

    if (-not $found) {
        Write-Log "No standard webroot detected; listing root and picking first directory (best-effort)."
        try {
            $rootList = $session.ListDirectory("/")
            $first = $rootList.Files | Where-Object { -not $_.Name.StartsWith(".") -and $_.IsDirectory } | Select-Object -First 1
            if ($null -ne $first) {
                $found = "/" + $first.Name.TrimStart("/")
                Write-Log "Using first directory found: $found"
            } else {
                $found = "/"
                Write-Log "Falling back to root: /"
            }
        } catch {
            Write-Log "Failed to list root '/': $($_.Exception.Message)"
            throw "Cannot detect remote webroot."
        }
    }

    if ($Mode -eq "test") {
        $timestamp = Get-Date -Format "yyyyMMdd_HHmmss"
        $remoteTarget = ($found.TrimEnd('/')) + "/chhama_patch_test_$timestamp"
        Write-Log "Test mode -> target: $remoteTarget"
        try { $session.CreateDirectory($remoteTarget); Write-Log "Created remote test folder $remoteTarget" } catch { Write-Log "CreateDirectory warning: $($_.Exception.Message)" }
    } else {
        $remoteTarget = $found
        # create backup folder
        $backupPath = ($found.TrimEnd('/')) + "/backup_$(Get-Date -Format yyyyMMdd_HHmmss)"
        try { $session.CreateDirectory($backupPath); Write-Log "Created backup folder $backupPath (empty)" } catch { Write-Log "Could not create backup folder: $($_.Exception.Message)" }
    }

    # Upload recursively using PutFiles with transfer options
    $transferOptions = New-Object WinSCP.TransferOptions
    $transferOptions.TransferMode = [WinSCP.TransferMode]::Binary

    # Build local->remote mappings: we will upload the entire LocalPath contents into remoteTarget preserving subfolders
    $localFull = (Resolve-Path $LocalPath).Path
    Write-Log "Preparing upload from local: $localFull"

    # Use mask to send everything; PutFiles supports wildcard with -remove:false
    # But to preserve folder structure we use UploadDirectory function below.
    function Upload-DirectoryRecursively {
        param($localDir, $remoteDir)
        # ensure remoteDir exists
        try { $session.CreateDirectory($remoteDir) } catch {}
        $items = Get-ChildItem -Path $localDir -Force
        foreach ($it in $items) {
            if ($it.PSIsContainer) {
                $subRemote = ($remoteDir.TrimEnd("/") + "/" + $it.Name)
                Upload-DirectoryRecursively -localDir $it.FullName -remoteDir $subRemote
            } else {
                $localFile = $it.FullName
                $remoteFile = $remoteDir.TrimEnd("/") + "/" + $it.Name
                Write-Log "Uploading: $localFile -> $remoteFile"
                $transferResult = $session.PutFiles($localFile, $remoteFile, $False, $transferOptions)
                if ($transferResult.IsSuccess) {
                    Write-Log "Uploaded: $localFile"
                } else {
                    foreach ($er in $transferResult.Failures) { Write-Log "ERROR upload $localFile : $($er.Message)" }
                }
            }
        }
    }

    # If LocalPath contains files instead of subfolder, upload into remoteTarget directly
    Upload-DirectoryRecursively -localDir $localFull -remoteDir $remoteTarget

    Write-Log "Upload finished. Remote target: $remoteTarget"

    # Post-upload basic verification (look for index.*)
    $verifyCandidates = @("index.php","index.html","chhama-check.php")
    $foundVerify = $false
    foreach ($v in $verifyCandidates) {
        try {
            $remoteCheck = $remoteTarget.TrimEnd('/') + "/" + $v
            $exists = $session.FileExists($remoteCheck)
            if ($exists) { Write-Log "Verification file present: $remoteCheck"; $foundVerify = $true; break }
        } catch {}
    }
    if (-not $foundVerify) { Write-Log "No verification file found in remote target (manual check recommended)." } else { Write-Log "Post-upload verification ok." }

} catch {
    Write-Log "ERROR: $($_.Exception.GetType().FullName) - $($_.Exception.Message)"
    throw
} finally {
    if ($session -ne $null) {
        $session.Dispose()
        Write-Log "Session closed."
    }
}
