# Deploy-Modpack.ps1
# Synchronizes the assembled base modpack to both Palworld client and dedicated server installations

param (
    [string]$TargetGamePath = "",
    [string]$TargetServerPath = ""
)

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "  PalOdyssey Unified Modpack Deployer     " -ForegroundColor Yellow
Write-Host "==========================================" -ForegroundColor Cyan

# 1. Detect client game path if not provided
if ([string]::IsNullOrWhiteSpace($TargetGamePath)) {
    $regKey = "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Steam App 1623730"
    if (Test-Path $regKey) {
        $TargetGamePath = (Get-ItemProperty -Path $regKey -Name "InstallLocation" -ErrorAction SilentlyContinue).InstallLocation
    }
}

if ([string]::IsNullOrWhiteSpace($TargetGamePath) -or !(Test-Path $TargetGamePath)) {
    $TargetGamePath = "C:\SteamLibrary\steamapps\common\Palworld"
}

# 2. Detect dedicated server path if not provided
if ([string]::IsNullOrWhiteSpace($TargetServerPath)) {
    $siblingServer = Join-Path (Split-Path $TargetGamePath) "PalServer"
    if (Test-Path $siblingServer) {
        $TargetServerPath = $siblingServer
    } else {
        $TargetServerPath = "C:\SteamLibrary\steamapps\common\PalServer"
    }
}

$srcModpack = "$PSScriptRoot\Modpack\Pal"

function Deploy-ToTarget($targetRoot, $label) {
    if (!(Test-Path $targetRoot)) {
        Write-Host "[$label] Skipping (Path not found: $targetRoot)" -ForegroundColor Yellow
        return
    }

    Write-Host "[$label] Deploying to: $targetRoot" -ForegroundColor Green
    $destPal = Join-Path $targetRoot "Pal"
    
    # Copy Pal/ tree
    Copy-Item "$srcModpack\*" -Destination $destPal -Recurse -Force

    # Ensure ue4ss\Mods structure is mirrored and complete
    $win64Mods = Join-Path $destPal "Binaries\Win64\Mods"
    $ue4ssMods = Join-Path $destPal "Binaries\Win64\ue4ss\Mods"
    
    if (Test-Path $win64Mods) {
        if (!(Test-Path $ue4ssMods)) {
            New-Item -ItemType Directory -Path $ue4ssMods -Force | Out-Null
        }
        Copy-Item "$win64Mods\*" -Destination $ue4ssMods -Recurse -Force
        Copy-Item "$destPal\Binaries\Win64\UE4SS-settings.ini" -Destination (Join-Path $destPal "Binaries\Win64\ue4ss\UE4SS-settings.ini") -Force -ErrorAction SilentlyContinue
    }

    Write-Host "[$label] Success! Updated dwmapi.dll, ue4ss\Mods, and pak files." -ForegroundColor Cyan
}

# Deploy to Client
Deploy-ToTarget $TargetGamePath "Palworld Client"

# Deploy to Dedicated Server
Deploy-ToTarget $TargetServerPath "Palworld Dedicated Server"

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Deployment complete across all targets!   " -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Cyan
