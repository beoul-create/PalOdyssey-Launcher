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
echo   PalOdyssey Launcher - Test Suite Runner
echo ==========================================

"%DOTNET_CMD%" test "PalLauncher.Tests\PalLauncher.Tests.csproj"

echo.
pause
