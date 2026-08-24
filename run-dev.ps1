# Set .NET SDK environment paths
$dotnetCmd = "dotnet"
$userDotnet = "$env:USERPROFILE\.dotnet"
if (Test-Path "$userDotnet\dotnet.exe") {
    $env:DOTNET_ROOT = $userDotnet
    $env:PATH = "$userDotnet;$env:PATH"
    $dotnetCmd = "$userDotnet\dotnet.exe"
}

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  PalOdyssey Custom Launcher - Dev Runner  " -ForegroundColor Yellow
Write-Host "==========================================" -ForegroundColor Cyan

# Close any existing instance to avoid file locks
Get-Process -Name "PalLauncher" -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Host "Closing existing PalLauncher instance (PID: $($_.Id))..." -ForegroundColor DarkGray
    try { $_.Kill() } catch { }
}

Write-Host "Building and launching PalLauncher (Debug mode)..." -ForegroundColor Green
& $dotnetCmd run --project "$PSScriptRoot\PalLauncher\PalLauncher.csproj"
