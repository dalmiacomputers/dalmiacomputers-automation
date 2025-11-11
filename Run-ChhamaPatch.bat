@echo off
:: ============================================================
::  DALMIA COMPUTERS – CHHAMA ONE CLICK PATCH LAUNCHER
::  Automatically runs PowerShell patch script with permissions
::  Created: %DATE% %TIME%
:: ============================================================

:: Get the current folder
set "CURDIR=%~dp0"
cd /d "%CURDIR%"

echo.
echo ============================================================
echo   🚀  Launching Chhama One-Click Patch for Dalmia Computers
echo ============================================================
echo.
echo [INFO] Please wait... PowerShell is preparing environment.
echo.

:: Use PowerShell 7 if available, else fallback to Windows PowerShell
where pwsh >nul 2>nul
if %errorlevel%==0 (
    set "PSCMD=pwsh"
) else (
    set "PSCMD=powershell"
)

:: Run PowerShell script with ExecutionPolicy bypassed just for this run
%PSCMD% -NoProfile -ExecutionPolicy Bypass -File "%CURDIR%chhama_one_click_patch_fixed.ps1"

echo.
echo ============================================================
echo ✅  Patch run completed!  Check the generated log file:
echo      chhama_patch_*.log
echo ============================================================
echo.
pause
