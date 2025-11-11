<#
 notify_and_sync.ps1
 - Sends email summary using SMTP
 - Posts a short JSON to a webhook URL (WhatsApp/Slack/Discord/Twilio)
 - Commits automation.log and diagnostics/*.json to a git repo and pushes (uses GITHUB_PAT)
#>

param(
    [string]$LogFile = ".\automation.log",
    [string]$DiagnosticsDir = ".\diagnostics",
    [string]$RepoLocalPath = ".\logs-repo",      # local git folder to push logs (create or clone)
    [string]$CommitMessage = "Auto: upload automation log and diagnostics"
)

function Load-Secrets {
    $secretsFile = Join-Path (Get-Location) 'secrets.encrypted'
    if (-not (Test-Path $secretsFile)) { throw "secrets.encrypted not found; run create_local_secrets.ps1 first." }
    $raw = Get-Content $secretsFile -Raw | ConvertFrom-Json
    return $raw
}

function Send-Email($smtpHost, $smtpPort, $smtpUser, $smtpPassPlain, $to, $subject, $body) {
    try {
        $msg = New-Object System.Net.Mail.MailMessage
        $msg.From = $smtpUser
        $msg.To.Add($to)
        $msg.Subject = $subject
        $msg.Body = $body
        $msg.IsBodyHtml = $false

        $client = New-Object System.Net.Mail.SmtpClient($smtpHost, [int]$smtpPort)
        $client.EnableSsl = $true
        $client.Credentials = New-Object System.Net.NetworkCredential($smtpUser, $smtpPassPlain)
        $client.Send($msg)
        return $true
    } catch {
        Write-Host "Email failed: $($_.Exception.Message)"
        return $false
    }
}

function Post-Webhook($url, $payload) {
    try {
        $json = $payload | ConvertTo-Json -Depth 6
        Invoke-RestMethod -Uri $url -Method Post -ContentType 'application/json' -Body $json -ErrorAction Stop
        return $true
    } catch {
        Write-Host "Webhook post failed: $($_.Exception.Message)"
        return $false
    }
}

function Push-LogsToGit($repoPath, $githubUser, $githubPat, $files) {
    try {
        if (-not (Test-Path $repoPath)) {
            Write-Host "Local repo path $repoPath not found — cloning into it..."
            git clone https://github.com/$githubUser/logs.git $repoPath
        }
        Push-Location $repoPath
        # copy files into repo
        foreach ($f in $files) {
            $dest = Join-Path $repoPath (Split-Path $f -Leaf)
            Copy-Item -Path $f -Destination $dest -Force
        }
        git add -A
        git commit -m "$CommitMessage" 2>$null
        # set temporary remote with token
        $remoteUrl = "https://$githubUser:$githubPat@github.com/$githubUser/logs.git"
        git remote remove autoup 2>$null
        git remote add autoup $remoteUrl
        git push autoup HEAD:main --set-upstream
        git remote remove autoup
        Pop-Location
        return $true
    } catch {
        Write-Host "Git push failed: $($_.Exception.Message)"
        return $false
    }
}

# ---- main ----
$secrets = Load-Secrets

# SMTP config in secrets: smtp_host, smtp_port, smtp_user, smtp_pass (ConvertFrom-SecureString stored)
$smtpHost = $secrets.smtp_host
$smtpPort = if ($secrets.smtp_port) { $secrets.smtp_port } else { 587 }
$smtpUser = $secrets.smtp_user
$smtpPassPlain = $null
if ($secrets.smtp_pass) {
    $secure = ConvertTo-SecureString $secrets.smtp_pass
    $b = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
    $smtpPassPlain = [Runtime.InteropServices.Marshal]::PtrToStringAuto($b)
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b) | Out-Null
}

# webhook_url and notification_recipient in secrets
$webhook = $secrets.webhook_url
$notify_to = $secrets.notify_email

# GitHub push info
$githubUser = $secrets.github_user
$githubPat = $null
if ($secrets.github_pat) {
    $secureg = ConvertTo-SecureString $secrets.github_pat
    $b2 = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureg)
    $githubPat = [Runtime.InteropServices.Marshal]::PtrToStringAuto($b2)
    [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($b2) | Out-Null
}

# Prepare summary
$logTail = ""
if (Test-Path $LogFile) {
    $logTail = (Get-Content $LogFile -Tail 40) -join "`n"
}
$diagFiles = @(Get-ChildItem -Path $DiagnosticsDir -Filter "report-*.json" -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 3).FullName
$summary = @{
    time = (Get-Date).ToString("yyyy-MM-dd HH:mm:ss")
    host = $env:COMPUTERNAME
    log_tail = $logTail
    last_diagnostics = $diagFiles
}

# Send email (if configured)
if ($smtpHost -and $smtpUser -and $smtpPassPlain -ne $null -and $notify_to) {
    $sub = "CHHAMA: Deploy & Diagnostics summary - $((Get-Date).ToString('yyyy-MM-dd'))"
    $body = "Summary:`n`n" + ($summary | ConvertTo-Json -Depth 3)
    Send-Email -smtpHost $smtpHost -smtpPort $smtpPort -smtpUser $smtpUser -smtpPassPlain $smtpPassPlain -to $notify_to -subject $sub -body $body | Out-Null
}

# Post webhook (if configured)
if ($webhook) {
    Post-Webhook -url $webhook -payload $summary | Out-Null
}

# Push logs to git (if github user + pat present)
if ($githubUser -and $githubPat) {
    $filesToPush = @()
    if (Test-Path $LogFile) { $filesToPush += (Resolve-Path $LogFile).Path }
    if ($diagFiles) { $filesToPush += $diagFiles }
    Push-LogsToGit -repoPath $RepoLocalPath -githubUser $githubUser -githubPat $githubPat -files $filesToPush | Out-Null
}

Write-Host "notify_and_sync completed."
