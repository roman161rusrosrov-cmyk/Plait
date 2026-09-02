@echo off
setlocal
cd /d "%~dp0"
title PLAIT DLSS5 AUTO - Cyberpunk 2077
set "PS=powershell.exe"
where pwsh.exe >nul 2>nul && set "PS=pwsh.exe"
"%PS%" -NoProfile -ExecutionPolicy Bypass -File "%~dp0AUTO_DLSS5.ps1"
if errorlevel 1 (
  echo.
  echo [ERROR] DLSS5 auto preparation failed.
  pause
  exit /b 1
)
exit /b 0
