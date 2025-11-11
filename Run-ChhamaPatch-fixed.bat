@echo off
REM Run-ChhamaPatch-fixed.bat
REM Place this in the same folder as chhama_one_click_patch_fixed.ps1

SETLOCAL
set "SCRIPT=%~dp0chhama_one_click_patch_fixed.ps1"
cd /d "%~dp0"

echo.
echo ============================================================
echo   Launching Chhama One-Click Patch (fixed) - Please wait
echo ============================================================
echo.

:: Prefer pwsh (PowerShell 7), else use Windows PowerShell
where pwsh >nul 2>nul
if %errorlevel%==0 (
    set "PSCMD=pwsh"
) else (
    set "PSCMD=powershell"
)

if not exist "%SCRIPT%" (
    echo ERROR: Script not found: "%SCRIPT%"
    echo Put chhama_one_click_patch_fixed.ps1 in the same folder as this .bat
    pause
    exit /b 2
)

:: Launch PowerShell in a new window and keep it open using -NoExit, so it does not close
start "" "%PSCMD%" -NoProfile -ExecutionPolicy Bypass -NoExit -File "%SCRIPT%"

echo.
echo Launched PowerShell. A new window will open and remain until you close it.
echo Check the log file chhama_patch_*.log inside this folder when finished.
echo.
pause
ENDLOCAL
