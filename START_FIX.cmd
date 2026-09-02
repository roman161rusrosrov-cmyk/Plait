@echo off
setlocal
cd /d "%~dp0"

echo ================================================
echo  DLSSNR FIXER - Cyberpunk 2077
echo ================================================
echo.
echo Close Cyberpunk 2077 before continuing.
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Repair-DLSSNR.ps1"
set "ERR=%ERRORLEVEL%"

echo.
if not "%ERR%"=="0" (
    echo [ERROR] Fixer returned error code %ERR%.
) else (
    echo [OK] Fixer finished.
)

pause
exit /b %ERR%
