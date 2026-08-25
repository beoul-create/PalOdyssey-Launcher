# PalOdyssey Launcher Developer Runner
$ErrorActionPreference = "Stop"

$projectRoot = Resolve-Path (Join-Path $PSScriptRoot "..")
$dotnetCmd = "dotnet"
$userDotnet = "$env:USERPROFILE\.dotnet"
if (Test-Path "$userDotnet\dotnet.exe") {
    $env:DOTNET_ROOT = $userDotnet
    $env:PATH = "$userDotnet;$env:PATH"
    $dotnetCmd = "$userDotnet\dotnet.exe"
}

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  PalOdyssey Custom Launcher - Dev Runner " -ForegroundColor Yellow
Write-Host "==========================================" -ForegroundColor Cyan

# Terminate any running instances
Get-Process -Name "PalLauncher" -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue

Write-Host "Building and launching PalLauncher (Debug mode)..." -ForegroundColor Green
& $dotnetCmd run --project "$projectRoot\PalLauncher\PalLauncher.csproj"
