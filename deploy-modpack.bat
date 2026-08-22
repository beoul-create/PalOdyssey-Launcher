@echo off
setlocal

echo ==========================================
echo   PalOdyssey Base Modpack Deployer
echo ==========================================

powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Deploy-Modpack.ps1" %*

pause
