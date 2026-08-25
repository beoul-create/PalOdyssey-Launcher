@echo off
setlocal
cd /d "%~dp0\.."

set "DOTNET_CMD=dotnet"
set "USER_DOTNET=%USERPROFILE%\.dotnet"
if exist "%USER_DOTNET%\dotnet.exe" (
    set "DOTNET_ROOT=%USER_DOTNET%"
    set "PATH=%USER_DOTNET%;%PATH%"
    set "DOTNET_CMD=%USER_DOTNET%\dotnet.exe"
)

echo ==========================================
echo   PalOdyssey Custom Launcher - Dev Runner
echo ==========================================

taskkill /F /IM PalLauncher.exe >nul 2>&1

echo Building and launching PalLauncher (Debug mode)...
"%DOTNET_CMD%" run --project "PalLauncher\PalLauncher.csproj"
