@echo off
setlocal
cd /d "%~dp0"

set "DOTNET_CMD=dotnet"
set "USER_DOTNET=%USERPROFILE%\.dotnet"
if exist "%USER_DOTNET%\dotnet.exe" (
    set "DOTNET_ROOT=%USER_DOTNET%"
    set "PATH=%USER_DOTNET%;%PATH%"
    set "DOTNET_CMD=%USER_DOTNET%\dotnet.exe"
)

echo ===============================================================
echo   PalOdyssey Standalone Host & Bot Runner (External Console)
echo ===============================================================
echo.
echo Launching 24/7 Autonomous Bot & Host in a detached external terminal...
echo (You can close your IDE/editor completely without stopping the bot!)
echo.

start "PalOdyssey 24/7 Autonomous Host & Discord Bot" cmd.exe /k "cd /d "%~dp0" && title PalOdyssey 24/7 Bot Host && echo Starting PalOdyssey 24/7 Host Daemon... && "%DOTNET_CMD%" run --project "%~dp0PalLauncher\PalLauncher.csproj" -- --daemon"
