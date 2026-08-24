# PalOdyssey 24/7 Autonomous Host & Discord Bot Task Scheduler Installer
$ErrorActionPreference = "Stop"

$taskName = "PalOdyssey-24x7-Daemon"
$projectRoot = $PSScriptRoot
$dotnetCmd = "dotnet"
$userDotnet = "$env:USERPROFILE\.dotnet"
if (Test-Path "$userDotnet\dotnet.exe") {
    $env:DOTNET_ROOT = $userDotnet
    $env:PATH = "$userDotnet;$env:PATH"
    $dotnetCmd = "$userDotnet\dotnet.exe"
}

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host "  PalOdyssey 24/7 Daemon - Windows Task Scheduler Setup      " -ForegroundColor Yellow
Write-Host "============================================================" -ForegroundColor Cyan

# Publish/build standalone executable if needed
$exePath = "$projectRoot\PalLauncher.exe"
$builtExe = "$projectRoot\PalLauncher\bin\Debug\net8.0-windows\PalLauncher.exe"

if (Test-Path $builtExe) {
    $exePath = $builtExe
}

Write-Host "Target Executable: $exePath" -ForegroundColor Gray
Write-Host "Arguments: --daemon" -ForegroundColor Gray

# Unregister existing task if present
try {
    $existing = Get-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    if ($existing) {
        Write-Host "Removing existing scheduled task '$taskName'..." -ForegroundColor DarkGray
        Unregister-ScheduledTask -TaskName $taskName -Confirm:$false
    }
} catch { }

# Create Task Action & Trigger
$action = New-ScheduledTaskAction -Execute $exePath -Argument "--daemon" -WorkingDirectory $projectRoot
$trigger = New-ScheduledTaskTrigger -AtLogOn
$principal = New-ScheduledTaskPrincipal -UserId "$env:USERDOMAIN\$env:USERNAME" -LogonType Interactive -RunLevel Highest
$settings = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1) -ExecutionTimeLimit (New-TimeSpan -Days 0)

Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Description "PalOdyssey 24/7 Autonomous Discord Bot and Server Host Daemon" | Out-Null

Write-Host "✓ Successfully registered '$taskName' in Windows Task Scheduler!" -ForegroundColor Green
Write-Host "The bot and server host daemon will automatically launch at Windows logon and run 24/7 in the background." -ForegroundColor White
