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

# Mirror to \Pal\Binaries\Win64\ue4ss\Mods for UE4SS builds requiring the subfolder path
$win64Mods = Join-Path $destPal "Binaries\Win64\Mods"
$ue4ssMods = Join-Path $destPal "Binaries\Win64\ue4ss\Mods"
if (Test-Path $win64Mods) {
    if (!(Test-Path $ue4ssMods)) {
        New-Item -ItemType Directory -Path $ue4ssMods -Force | Out-Null
    }
    Copy-Item "$win64Mods\*" -Destination $ue4ssMods -Recurse -Force
    Copy-Item "$destPal\Binaries\Win64\UE4SS-settings.ini" -Destination (Join-Path $destPal "Binaries\Win64\ue4ss\UE4SS-settings.ini") -Force -ErrorAction SilentlyContinue
}

Write-Host "Deployment completed successfully! All base mods installed to both Win64\Mods and Win64\ue4ss\Mods." -ForegroundColor Green
