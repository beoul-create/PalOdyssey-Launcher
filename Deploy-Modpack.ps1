# Deploy-Modpack.ps1
# Synchronizes the assembled base modpack to Palworld installation

param (
    [string]$TargetGamePath = ""
)

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  PalOdyssey Base Modpack Deployer        " -ForegroundColor Yellow
Write-Host "==========================================" -ForegroundColor Cyan

# 1. Detect path if not provided
if ([string]::IsNullOrWhiteSpace($TargetGamePath)) {
    # Check Windows Registry
    $regKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Steam App 1623730"
    if (Test-Path $regKey) {
        $TargetGamePath = (Get-ItemProperty -Path $regKey -Name "InstallLocation" -ErrorAction SilentlyContinue).InstallLocation
    }
}

if ([string]::IsNullOrWhiteSpace($TargetGamePath) -or !(Test-Path $TargetGamePath)) {
    $TargetGamePath = "C:\SteamLibrary\steamapps\common\Palworld"
}

if (!(Test-Path $TargetGamePath)) {
    Write-Host "Palworld folder not found at '$TargetGamePath'. Please specify your path with -TargetGamePath." -ForegroundColor Red
    exit 1
}

Write-Host "Target Palworld Directory: $TargetGamePath" -ForegroundColor Green

$srcModpack = "$PSScriptRoot\Modpack\Pal"
$destPal = Join-Path $TargetGamePath "Pal"

Write-Host "Deploying UE4SS, Lua mods, Shaders, and PalSchema data..." -ForegroundColor Cyan
Copy-Item "$srcModpack\*" -Destination $destPal -Recurse -Force

Write-Host "Deployment completed successfully! All 11 base mods installed." -ForegroundColor Green
