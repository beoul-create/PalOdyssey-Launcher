@echo off
setlocal
cd /d "%~dp0"
set "PATH=%APPDATA%\npm;C:\Program Files\nodejs;%PATH%"

call pm2 status
echo.
echo Press any key to stream live bot logs (Ctrl+C to exit)...
pause >nul
call pm2 logs palodyssey-bot
