@echo off
setlocal
cd /d "%~dp0"
echo =======================================================
echo   Starting PalOdyssey Bot & Host Daemon via PM2 (24/7)
echo =======================================================
echo.
if not exist "logs" mkdir logs

:: Ensure Node, npm global binaries, and dotnet are in PATH
set "PATH=%APPDATA%\npm;C:\Program Files\nodejs;%PATH%"

set "USER_DOTNET=%USERPROFILE%\.dotnet"
if exist "%USER_DOTNET%\dotnet.exe" (
    set "DOTNET_ROOT=%USER_DOTNET%"
    set "PATH=%USER_DOTNET%;%PATH%"
)

:: Check if PM2 is installed
call pm2 -v >nul 2>&1
if %errorlevel% neq 0 (
    echo [INFO] PM2 not found. Installing globally via npm...
    call npm install -g pm2
)

echo Building PalLauncher in Daemon mode...
call dotnet build "PalLauncher\PalLauncher.csproj"

echo Starting PM2 Daemon...
call pm2 start ecosystem.config.js
call pm2 save

echo.
echo =======================================================
echo   PalOdyssey Bot is now running 24/7 in background!
echo   To view logs:    pm2 logs palodyssey-bot
echo   To check status: pm2 status
echo   To stop:         stop-bot-pm2.bat
echo =======================================================
echo.
pause
