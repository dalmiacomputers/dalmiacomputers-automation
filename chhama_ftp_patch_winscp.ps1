# chhama_ftp_patch_winscp.ps1
# Requires WinSCP (winscpnet.dll). Recommended: put winscpnet.dll next to this script or install WinSCP and update path.

# ---------- CONFIG ----------
$ftpHost = "107.180.113.63"
$ftpUser = "e5khdkcsrpke"
$remotePath = "/public_html"               # remote folder where website lives
$localPatchFolder = "C:\path\to\chhama_patch"  # change to your local patch folder (files to upload)
$backupLocalFolder = "C:\path\to\chhama_backups"
$logFile = "$PSScriptRoot\chhama_ftp_patch_log.txt"
# ---------------------------

# Prompt for password securely
$ftpPass = Read-Host "Enter FTP password (hidden)" -AsSecureString
$plainPass = [Runtime.InteropServices.Marshal]::PtrToStringAuto(
    [Runtime.InteropServices.Marshal]::SecureStringToBSTR($ftpPass)
)

# Load WinSCP .NET assembly - change path if needed
$winScpDll = "C:\Program Files (x86)\WinSCP\WinSCPnet.dll"
if (-not (Test-Path $winScpDll)) {
    $winScpDll = Join-Path $PSScriptRoot "WinSCPnet.dll"
}
if (-not (Test-Path $winScpDll)) {
    Write-Error "Cannot find WinSCPnet.dll. Install WinSCP or place WinSCPnet.dll next to this script."
    exit 1
}
Add-Type -Path $winScpDll

# Create session options
$sessionOptions = New-Object WinSCP.SessionOptions -Property @{
    Protocol = [WinSCP.Protocol]::Ftp         # change to Sftp if server supports SFTP
    HostName = $ftpHost
    UserName = $ftpUser
    Password = $plainPass
    FtpMode = [WinSCP.FtpMode]::Passive      # Passive is usually better behind NAT/firewall
    GiveUpSecurityAndAcceptAnySslHostKey = $true
}

$session = New-Object WinSCP.Session
$session.SessionLogPath = $logFile

try {
    $session.Open($sessionOptions)

    # Ensure local backup folder exists
    if (-not (Test-Path $backupLocalFolder)) { New-Item -ItemType Directory -Path $backupLocalFolder | Out-Null }

    # 1) LIST remote directory (diagnostic)
    Write-Output "Listing remote $remotePath ..."
    $remoteFiles = $session.ListDirectory($remotePath)
    $remoteFiles.Files | ForEach-Object {
        Write-Output ("{0}`t{1}`t{2}" -f $_.Name, $_.Length, $_.LastWriteTime)
    }

    # 2) DOWNLOAD remote site as backup (only files, not recursion heavy)
    $timestamp = (Get-Date).ToString("yyyyMMdd_HHmmss")
    $backupDest = Join-Path $backupLocalFolder "remote_backup_$timestamp"
    New-Item -ItemType Directory -Path $backupDest | Out-Null
    Write-Output "Backing up remote $remotePath -> $backupDest"
    $transferOptions = New-Object WinSCP.TransferOptions
    $transferOptions.TransferMode = [WinSCP.TransferMode]::Binary
    $transferResult = $session.GetFiles($remotePath + "/*", $backupDest, $False, $transferOptions)
    if ($transferResult.IsSuccess) {
        Write-Output "Backup completed: $($transferResult.Transfers.Count) files."
    } else {
        Write-Warning "Backup had some failures. Check log: $logFile"
    }

    # 3) UPLOAD patch files (recursive)
    if (-not (Test-Path $localPatchFolder)) { throw "Local patch folder not found: $localPatchFolder" }
    Write-Output "Uploading patch from $localPatchFolder -> $remotePath"
    $uploadResult = $session.PutFiles((Join-Path $localPatchFolder "*"), $remotePath, $True, $transferOptions)
    $uploadResult.Check()   # throws on error
    Write-Output "Upload success: $($uploadResult.Transfers.Count) items uploaded."

    # 4) Verify sizes/timestamps for a few key files (example)
    $verifyList = @("index.php","wp-config.php") # adjust to your project
    foreach ($f in $verifyList) {
        $remoteFile = $session.ListDirectory($remotePath).Files | Where-Object { $_.Name -eq $f }
        if ($null -ne $remoteFile) {
            Write-Output "Remote $f -> size: $($remoteFile.Length), mod: $($remoteFile.LastWriteTime)"
        } else {
            Write-Warning "Remote file $f not found after upload."
        }
    }

    # 5) OPTIONAL: Trigger remote extraction via HTTP if you uploaded a zip and have extract endpoint
    # Example: if you uploaded extract.php to remote, call it:
    # $extractUrl = "http://yourdomain.com/extract.php?token=XYZ"
    # Invoke-WebRequest -Uri $extractUrl -UseBasicParsing

    Write-Output "Done. Inspect WinSCP log: $logFile"
}
catch {
    Write-Error "Error: $_"
}
finally {
    $session.Dispose()
}
