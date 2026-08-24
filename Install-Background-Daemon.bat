@echo off
setlocal
echo ======================================================================
echo   PalOdyssey - Register Background Host Daemon on Windows Startup
echo ======================================================================
echo.
set "LAUNCHER_EXE=%~dp0PalLauncher.exe"
set "STARTUP_FOLDER=%APPDATA%\Microsoft\Windows\Start Menu\Programs\Startup"
set "VBS_SCRIPT=%TEMP%\CreatePalDaemonShortcut.vbs"

if not exist "%LAUNCHER_EXE%" (
    echo [ERROR] PalLauncher.exe not found in %~dp0
    pause
    exit /b 1
)

echo Creating Windows Startup shortcut with --daemon flag...
echo Set oWS = WScript.CreateObject("WScript.Shell") > "%VBS_SCRIPT%"
echo sLinkFile = "%STARTUP_FOLDER%\PalOdyssey-HostDaemon.lnk" >> "%VBS_SCRIPT%"
echo Set oLink = oWS.CreateShortcut(sLinkFile) >> "%VBS_SCRIPT%"
echo oLink.TargetPath = "%LAUNCHER_EXE%" >> "%VBS_SCRIPT%"
echo oLink.Arguments = "--daemon" >> "%VBS_SCRIPT%"
echo oLink.WorkingDirectory = "%~dp0" >> "%VBS_SCRIPT%"
echo oLink.Description = "PalOdyssey Headless Remote Server Wake Daemon" >> "%VBS_SCRIPT%"
echo oLink.WindowStyle = 7 >> "%VBS_SCRIPT%"
echo oLink.Save >> "%VBS_SCRIPT%"

cscript //nologo "%VBS_SCRIPT%"
del "%VBS_SCRIPT%"

echo.
echo [SUCCESS] PalOdyssey Background Host Daemon registered!
echo The daemon will automatically run silently on Windows Startup and listen on port 8211.
echo.
pause
