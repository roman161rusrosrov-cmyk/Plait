@echo off
chcp 65001 >nul
cd /d "%~dp0"

echo ================================================
echo  DLSSNR FIXER - Cyberpunk 2077
echo ================================================
echo.

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0Repair-DLSSNR.ps1"

if errorlevel 1 (
    echo.
    echo [ERROR] Скрипт завершился с ошибкой.
    pause
)
