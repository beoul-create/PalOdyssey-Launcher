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
echo   PalOdyssey Launcher - Package Release
echo ==========================================

taskkill /F /IM PalLauncher.exe >nul 2>&1

echo 1. Building Release Executable...
"%DOTNET_CMD%" publish "PalLauncher\PalLauncher.csproj" -c Release -r win-x64 --self-contained false -o "publish"

if %errorlevel% neq 0 (
    echo [ERROR] Build failed!
    pause
    exit /b %errorlevel%
)

echo 2. Packaging Release ZIP (PalOdyssey-Launcher-v2.0.0.zip)...
powershell -Command "Compress-Archive -Path 'publish\PalLauncher.exe', 'publish\System.Management.dll', 'publish\PalLauncher.dll', 'publish\PalLauncher.runtimeconfig.json', 'publish\PalLauncher.deps.json', 'README.md' -DestinationPath 'PalOdyssey-Launcher-v2.0.0.zip' -Force"

echo.
echo ==========================================
echo [SUCCESS] Release package created at:
echo PalOdyssey-Launcher-v2.0.0.zip
echo ==========================================
echo.
pause
