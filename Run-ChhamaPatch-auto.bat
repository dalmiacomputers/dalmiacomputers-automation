@'
@echo off
REM Run-ChhamaPatch-auto.bat
REM Auto-detects the chhama*.ps1 file and opens PowerShell to run it (keeps window open).

SETLOCAL
cd /d "%~dp0"

echo ============================================================
echo   Auto-launcher: CHHAMA One-Click Patch
echo ============================================================

REM find the first PS1 starting with chhama
set "SCRIPT="
for /f "delims=" %%F in ('dir /b /a:-d "chhama*.ps1" 2^>nul') do (
  set "SCRIPT=%%F"
  goto :found
)
:found

if "%SCRIPT%"=="" (
  echo ERROR: No chhama*.ps1 found in this folder.
  echo Put the PowerShell script (chhama*.ps1) in this folder and try again.
  pause
  exit /b 2
)

echo Found script: "%SCRIPT%"

REM choose pwsh if available
where pwsh >nul 2>nul
if %errorlevel%==0 (
  set "PSCMD=pwsh"
) else (
  set "PSCMD=powershell"
)

REM Launch in new PowerShell window and keep it open
start "" "%PSCMD%" -NoProfile -ExecutionPolicy Bypass -NoExit -File "%~dp0%SCRIPT%"

echo Launched PowerShell. A new window will open and remain until you close it.
echo Script: %SCRIPT%
pause
ENDLOCAL
'@ | Out-File -FilePath .\Run-ChhamaPatch-auto.bat -Encoding ASCII

Write-Host "Created Run-ChhamaPatch-auto.bat — double-click it to run."
