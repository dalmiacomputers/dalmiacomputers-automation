<#
chhama_master_runner.ps1
Fixed master runner: finds chhama*.ps1, backups, auto-fixes $var:$var2 patterns, writes fixed file and runs it,
capturing stdout/stderr to timestamped logs. Robust for single/multiple matches.
#>

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Info($m){ Write-Host "[INFO] $m" -ForegroundColor Cyan }
function Warn($m){ Write-Host "[WARN] $m" -ForegroundColor Yellow }
function Err($m){ Write-Host "[ERROR] $m" -ForegroundColor Red }

$TS = (Get-Date).ToString("yyyyMMdd-HHmmss")
$pwdPath = (Get-Location).ProviderPath

Info "Starting CHHAMA Master Runner - $TS"
Info "Folder: $pwdPath"

# find candidate scripts (force array)
$psCandidates = @(Get-ChildItem -Path . -Filter "chhama*.ps1" -File | Where-Object { $_.Name -ne 'chhama_master_runner.ps1' } | Sort-Object Name)
if ($psCandidates.Count -eq 0) {
    Err "No 'chhama*.ps1' file found here. Put your script in this folder and re-run."
    exit 2
}

# choose the first candidate (you can edit the index if you want specific file)
$chosen = $psCandidates[0]
Info ("Using script: {0}" -f $chosen.Name)
$origFile = $chosen.FullName

# backup original
$backupName = "{0}.backup.{1}.ps1" -f $chosen.BaseName, $TS
$backupPath = Join-Path $pwdPath $backupName
Copy-Item -Path $origFile -Destination $backupPath -Force
Info ("Backed up original to: {0}" -f $backupName)

# read content
$content = Get-Content -Raw -Path $origFile -Encoding UTF8

# AUTO-FIX: Replace only patterns of form $var:$var2 -> ${var}:${var2}
# Use a regex that matches $<ident>:$<ident>
$fixed = [regex]::Replace($content, '\$([A-Za-z_][A-Za-z0-9_]*)\:\$([A-Za-z_][A-Za-z0-9_]*)', '${$1}:${$2}')

if ($fixed -ne $content) {
    Info "Applied auto-fix for variable-colon-variable patterns."
} else {
    Info "No risky var:var patterns found."
}

# write fixed script
$fixedName = "chhama_one_click_patch_fixed.ps1"
$fixedPath = Join-Path $pwdPath $fixedName
Set-Content -Path $fixedPath -Value $fixed -Encoding UTF8 -Force
Info ("Wrote fixed script: {0}" -f $fixedName)

# prepare run log names
$runLog = "chhama_runlog_$TS.txt"
$runErr = "chhama_runerr_$TS.txt"

# pick PowerShell executable (pwsh preferred)
$pwsh = (Get-Command pwsh.exe -ErrorAction SilentlyContinue).Path
if ($pwsh) {
    $psExe = $pwsh
    Info ("Using PowerShell 7 (pwsh): {0}" -f $psExe)
} else {
    $psExe = (Get-Command powershell.exe -ErrorAction SilentlyContinue).Path
    if (-not $psExe) { Err "No PowerShell found."; exit 3 }
    Info ("Using Windows PowerShell: {0}" -f $psExe)
}

# start the child process and capture streams
$argList = @("-NoProfile","-ExecutionPolicy","Bypass","-File",$fixedPath)
Info "Starting child PowerShell process..."
$startInfo = New-Object System.Diagnostics.ProcessStartInfo
$startInfo.FileName = $psExe
$startInfo.Arguments = ($argList -join ' ')
$startInfo.RedirectStandardOutput = $true
$startInfo.RedirectStandardError  = $true
$startInfo.UseShellExecute = $false
$startInfo.CreateNoWindow = $false

$proc = New-Object System.Diagnostics.Process
$proc.StartInfo = $startInfo
$proc.Start() | Out-Null

$stdOut = $proc.StandardOutput
$stdErr = $proc.StandardError

$outWriter = [System.IO.StreamWriter]::new((Join-Path $pwdPath $runLog), $false, [System.Text.Encoding]::UTF8)
$errWriter = [System.IO.StreamWriter]::new((Join-Path $pwdPath $runErr), $false, [System.Text.Encoding]::UTF8)

try {
    while (-not $proc.HasExited) {
        while (-not $stdOut.EndOfStream) {
            $line = $stdOut.ReadLine()
            if ($line -ne $null) { Write-Host $line; $outWriter.WriteLine($line); $outWriter.Flush() }
        }
        while (-not $stdErr.EndOfStream) {
            $line2 = $stdErr.ReadLine()
            if ($line2 -ne $null) { Write-Host $line2 -ForegroundColor Red; $errWriter.WriteLine($line2); $errWriter.Flush() }
        }
        Start-Sleep -Milliseconds 150
    }
    # drain remaining
    while (-not $stdOut.EndOfStream) { $l = $stdOut.ReadLine(); Write-Host $l; $outWriter.WriteLine($l) }
    while (-not $stdErr.EndOfStream) { $l = $stdErr.ReadLine(); Write-Host $l -ForegroundColor Red; $errWriter.WriteLine($l) }

    Info ("Child exited with code {0}" -f $proc.ExitCode)
} finally {
    $outWriter.Close(); $errWriter.Close()
    if ($proc -and -not $proc.HasExited) { $proc.Kill() }
}

Info "Run complete."
Write-Host "  stdout log: $runLog"
Write-Host "  stderr log: $runErr"
Write-Host "  backup: $backupName"
Write-Host "  fixed: $fixedName"
Write-Host ""
Write-Host "Press Enter to close..."
[void][System.Console]::ReadLine()
