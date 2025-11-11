@echo off
title CHHAMA One-Click FTP Patch (DEBUG)
color 0B
echo ============================================================
echo     Dalmia Computers – CHHAMA One-Click FTP Patch (DEBUG)
echo ============================================================
echo.

:: find pwsh
for /f "tokens=*" %%I in ('where pwsh 2^>nul') do set "PWSH_PATH=%%I"
if not defined PWSH_PATH (
    echo [ERROR] PowerShell 7 (pwsh) not found in PATH.
    echo Please install PowerShell 7 (https://aka.ms/powershell) and try again.
    pause
    exit /b 1
)

echo [INFO] PowerShell 7 found at: %PWSH_PATH%
cd /d "%~dp0"
echo [INFO] Working directory: %CD%
echo.

:: --- OPTIONAL: you can set these variables here (or leave commented to be prompted) ---
:: set "CHHAMA_FTP_HOST=107.180.113.63"
:: set "CHHAMA_FTP_USER=your_cpanel_username"
:: set "CHHAMA_FTP_PASS=your_cpanel_password"
:: set "CHHAMA_REMOTE_ROOT=/public_html"
:: set "CHHAMA_DOMAIN=dalmiacomputers.in"

echo [INFO] Starting PowerShell script and logging output to chhama_run_output.log
echo.

:: Run PowerShell and redirect stdout+stderr to log file, keep console open afterwards
"%PWSH_PATH%" -NoProfile -ExecutionPolicy Bypass -File ".\chhama_one_click_patch_ftp_fixed.ps1" > ".\chhama_run_output.log" 2>&1

echo.
echo [DONE] PowerShell finished. Output (and errors) were saved to:
echo    %CD%\chhama_run_output.log
echo.
echo To view the last 120 lines now, press any key...
pause >nul
type ".\chhama_run_output.log" | more
echo.
echo If the script needed you to enter credentials but exited immediately, please:
echo  1) Open PowerShell (pwsh) manually:
echo       Start -> type pwsh -> Enter
echo  2) Run the script interactively so you can respond to prompts:
echo       cd "%~dp0"
echo       pwsh -NoProfile -ExecutionPolicy Bypass -File .\chhama_one_click_patch_ftp_fixed.ps1
echo.
pause
exit /b
