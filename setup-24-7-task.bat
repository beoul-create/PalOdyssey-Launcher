@echo off
setlocal
cd /d "%~dp0"
echo ==================================================================
echo   PalOdyssey 24/7 Autonomous Discord Bot - 1-Click Installer
echo ==================================================================
echo.
powershell.exe -ExecutionPolicy Bypass -NoProfile -File "%~dp0Install-PalOdyssey-Task.ps1"
echo.
pause
