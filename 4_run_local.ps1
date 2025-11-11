# 4_run_local.ps1
if (Test-Path package.json) {
  Write-Host "Detected Node project. Installing..."
  npm ci
  if (Get-Content package.json | Select-String "start") { npm run start } else { Write-Host "No start script." }
} elseif (Test-Path requirements.txt) {
  Write-Host "Detected Python project. Preparing venv..."
  python -m venv .venv
  .\.venv\Scripts\Activate.ps1
  pip install -r requirements.txt
  if (Test-Path app.py) { python app.py }
} elseif (Test-Path docker-compose.yml) {
  Write-Host "Detected docker-compose. Starting..."
  docker-compose up -d --build
} else { Write-Host "No recognizable project files in repo root." }
