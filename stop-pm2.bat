@echo off
setlocal
cd /d "%~dp0"
set "PATH=%APPDATA%\npm;C:\Program Files\nodejs;%PATH%"

echo Stopping PalOdyssey PM2 Daemon...
call pm2 stop palodyssey-bot
call pm2 delete palodyssey-bot
call pm2 save
echo Bot stopped and unregistered from PM2.
pause
