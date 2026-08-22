@echo off
setlocal
set "USER_DOTNET=%USERPROFILE%\.dotnet"
if exist "%USER_DOTNET%" (
    set "DOTNET_ROOT=%USER_DOTNET%"
    set "PATH=%USER_DOTNET%;%PATH%"
)

echo ==========================================
echo   PalOdyssey Custom Launcher - Dev Runner
echo ==========================================

taskkill /F /IM PalLauncher.exe >nul 2>&1

echo Building and launching PalLauncher (Debug mode)...
dotnet run --project "%~dp0PalLauncher\PalLauncher.csproj"
