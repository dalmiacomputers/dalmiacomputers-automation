# run_all.ps1
Set-StrictMode -Version Latest
$ErrorActionPreference = "Stop"
function Run-Step($script) {
  $p = Join-Path (Get-Location) $script
  if (-not (Test-Path $p)) { Write-Host "Missing $script. Skipping."; return }
  Write-Host "`n===== Running $script ====="
  Write-Host "Press Enter to run, or type s then Enter to skip."
  $i = Read-Host
  if ($i -eq "s") { Write-Host "Skipped $script"; return }
  try { PowerShell -ExecutionPolicy Bypass -File $p; Write-Host "$script done." } catch { Write-Host ("Error running {0}: {1}" -f $script, $($_.Exception.Message)) }
}
# optional secrets setup
if (Test-Path .\set_secrets.ps1) {
  Write-Host "Run set_secrets.ps1 now? (Y/n)"
  $r = Read-Host
  if ($r -ne "n") { PowerShell -ExecutionPolicy Bypass -File .\set_secrets.ps1 }
}
$steps = @("1_install.ps1","2_setup_ssh_git.ps1","3_diagnose.ps1","4_run_local.ps1")
foreach ($s in $steps) { Run-Step $s }
Write-Host "`nFinal Step: Deploy (5_deploy.ps1). Run now? (Y/n)"
$ans = Read-Host
if ($ans -ne "n") { Run-Step "5_deploy.ps1" } else { Write-Host "Deployment skipped." }
