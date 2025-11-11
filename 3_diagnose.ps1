# 3_diagnose.ps1 (fixed)
# Runs diagnostics and writes diagnostics/report-<timestamp>.json with JSON-safe data types.

$ErrorActionPreference = "Continue"
$ts = (Get-Date).ToString("yyyyMMdd-HHmmss")
$diagDir = Join-Path (Get-Location) "diagnostics"
if (-not (Test-Path $diagDir)) { New-Item -ItemType Directory -Path $diagDir | Out-Null }

# Helper to safely run commands and return string output
function Safe-Run([ScriptBlock]$sb) {
    try {
        $o = & $sb 2>&1
        if ($null -eq $o) { return "" }
        return ($o -join "`n")
    } catch {
        return ("ERROR: " + ($_.Exception.Message))
    }
}

# Collect info as strings and string-keyed dictionaries
$report = [ordered]@{}
$report["timestamp"] = $ts
$report["git_version"] = Safe-Run { git --version }
$report["git_remotes"] = Safe-Run { git remote -v }
$report["ssh_test"] = Safe-Run { ssh -T -o StrictHostKeyChecking=no git@github.com }
$report["node_version"] = Safe-Run { node -v }
$report["npm_version"] = Safe-Run { npm -v }
$report["python_version"] = Safe-Run { python -V 2>&1 }
$report["pip_version"] = Safe-Run { pip --version 2>$null }

# Ports (strings for keys)
$ports = @{ "80" = (Safe-Run { if ((New-Object Net.Sockets.TcpClient).ConnectAsync('127.0.0.1',80).IsCompleted) { 'open' } else { 'closed' } } ) }
# fallback port checks
function Check-PortOpen($p) { try { $sock = New-Object Net.Sockets.TcpClient; $sock.Connect('127.0.0.1',$p); $sock.Close(); return 'open' } catch { return 'closed' } }
$ports["80"] = Check-PortOpen 80
$ports["443"] = Check-PortOpen 443
$ports["3000"] = Check-PortOpen 3000
$report["ports"] = $ports

# DNS and site
$report["dns_lookup"] = Safe-Run { nslookup dalmiacomputers.in 2>&1 }
$report["site_head"] = Safe-Run { curl -UseBasicParsing -Uri 'https://dalmiacomputers.in' -Method Head -ErrorAction Stop; "HTTP_OK" }

# Save as JSON
$outPath = Join-Path $diagDir ("report-" + $ts + ".json")
$report | ConvertTo-Json -Depth 6 | Out-File -FilePath $outPath -Encoding UTF8

Write-Host "Diagnostics complete. Saved: $outPath"
Write-Host "Summary: Git:$($report.git_version.Split()[0])  Node:$($report.node_version)  Python:$($report.python_version)"
