# =====================================================
# CHHAMA: Smart ZIP Creation for Manual or Auto Deploy
# =====================================================

Write-Host "`n==> Creating deploy ZIP package..."

try {
    $timestamp = Get-Date -Format "yyyyMMdd-HHmmss"
    $projectDir = (Get-Location).Path
    $downloads = [Environment]::GetFolderPath('UserProfile') + "\Downloads"
    $zipPath = "$downloads\site-deploy-$timestamp.zip"

    if (Test-Path $zipPath) { Remove-Item $zipPath -Force }

    Add-Type -AssemblyName System.IO.Compression.FileSystem
    [System.IO.Compression.ZipFile]::CreateFromDirectory($projectDir, $zipPath)

    Write-Host "`n✅ Deploy ZIP created successfully!"
    Write-Host "   Location: $zipPath"
    Write-Host "   You can upload this file manually via GoDaddy → File Manager → public_html → Upload → Extract.`n"

    # Ask user if they want to stop here for manual upload
    $choice = Read-Host "Do you want to stop here for manual upload (recommended)? (Y/n)"
    if ($choice -eq 'Y' -or $choice -eq 'y' -or $choice -eq '') {
        Write-Host "`nExiting after ZIP creation. Manual upload mode complete."
        return
    }

    # Continue with automated FTP (if configured)
    Write-Host "`nContinuing with automatic deploy..."
}
catch {
    Write-Host "`n❌ ZIP creation failed: $($_.Exception.Message)"
}
