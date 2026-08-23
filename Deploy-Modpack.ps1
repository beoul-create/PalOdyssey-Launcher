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

function Deploy-ToTarget($targetRoot, $label, [bool]$isDedicatedServer = $false) {
    if (!(Test-Path $targetRoot)) {
        Write-Host "[$label] Skipping (Path not found: $targetRoot)" -ForegroundColor Yellow
        return
    }

    Write-Host "[$label] Deploying to: $targetRoot" -ForegroundColor Green
    $destPal = Join-Path $targetRoot "Pal"
    
    # 1. Copy Pal/ tree
    Copy-Item "$srcModpack\*" -Destination $destPal -Recurse -Force

    # 2. Ensure ue4ss\Mods and Binaries\Win64\Mods structures exist
    $win64Mods = Join-Path $destPal "Binaries\Win64\Mods"
    $ue4ssMods = Join-Path $destPal "Binaries\Win64\ue4ss\Mods"
    
    if (Test-Path $win64Mods) {
        if (!(Test-Path $ue4ssMods)) {
            New-Item -ItemType Directory -Path $ue4ssMods -Force | Out-Null
        }
        Copy-Item "$win64Mods\*" -Destination $ue4ssMods -Recurse -Force
        Copy-Item "$destPal\Binaries\Win64\UE4SS-settings.ini" -Destination (Join-Path $destPal "Binaries\Win64\ue4ss\UE4SS-settings.ini") -Force -ErrorAction SilentlyContinue
    }

    # 3. Configure Server vs Client specific settings
    if ($isDedicatedServer) {
        # Place .server marker for WeaponProficiency side detection
        $wpDir = Join-Path $ue4ssMods "WeaponProficiency"
        if (Test-Path $wpDir) {
            Set-Content -Path (Join-Path $wpDir ".server") -Value "server" -Force
        }

        # Write server-tailored mods.txt (enable server gameplay/performance mods, disable client-only HUD)
        $serverModsTxt = @"
KismetDebuggerMod : 0
EventViewerMod : 0
CheatManagerEnablerMod : 0
ActorDumperMod : 0
ConsoleCommandsMod : 0
ConsoleEnablerMod : 0
SplitScreenMod : 0
LineTraceMod : 0
BPML_GenericFunctions : 1
BPModLoaderMod : 1
jsbLuaProfilerMod : 0

PalSchema : 1
RamTrimMod : 1
PalworldTuner : 1
ExpeditionXP : 1
DarnMenu : 0
DarnToasts : 0
LevelLock : 1
WeaponProficiency : 1
PalOdysseyOptimizer : 1
StuckPalRescuer : 1
RemoveModWarning : 0
QuickDeposit : 0
PalClearVision : 0

; Built-in keybinds (disabled on dedicated server)
Keybinds : 0
"@
        Set-Content -Path (Join-Path $ue4ssMods "mods.txt") -Value $serverModsTxt -Force
        if (Test-Path $win64Mods) {
            Set-Content -Path (Join-Path $win64Mods "mods.txt") -Value $serverModsTxt -Force
        }
        Write-Host "[$label] Configured Dedicated Server: ServerDurability RPC, LevelLock, ExpeditionXP, Optimizer & Memory Trimming active." -ForegroundColor Cyan
    } else {
        # Client side: ensure UI mods are active
        $clientModsTxt = @"
KismetDebuggerMod : 0
EventViewerMod : 0
CheatManagerEnablerMod : 0
ActorDumperMod : 0
ConsoleCommandsMod : 0
ConsoleEnablerMod : 0
SplitScreenMod : 0
LineTraceMod : 0
BPML_GenericFunctions : 1
BPModLoaderMod : 1
jsbLuaProfilerMod : 0

PalSchema : 1
RamTrimMod : 1
PalworldTuner : 1
ExpeditionXP : 1
DarnMenu : 1
DarnToasts : 1
LevelLock : 1
WeaponProficiency : 1
PalOdysseyOptimizer : 1
StuckPalRescuer : 1
RemoveModWarning : 1
QuickDeposit : 1
PalClearVision : 1
PalboxSearchPlus : 1
CleanHUD : 1
ShiningLuckies : 1

; Built-in keybinds, do not move up!
Keybinds : 1
"@
        Set-Content -Path (Join-Path $ue4ssMods "mods.txt") -Value $clientModsTxt -Force
        if (Test-Path $win64Mods) {
            Set-Content -Path (Join-Path $win64Mods "mods.txt") -Value $clientModsTxt -Force
        }
        # Remove .server marker if accidentally placed on client
        $wpServerMarker = Join-Path $ue4ssMods "WeaponProficiency\.server"
        if (Test-Path $wpServerMarker) {
            Remove-Item $wpServerMarker -Force -ErrorAction SilentlyContinue
        }
        Write-Host "[$label] Configured Game Client: Full UI Suite, Keybinds, and In-Game Mod Options active." -ForegroundColor Cyan
    }

    Write-Host "[$label] Success! Updated binaries, UE4SS mods, and content paks." -ForegroundColor Green
}

# Deploy to Client
Deploy-ToTarget $TargetGamePath "Palworld Client" -isDedicatedServer $false

# Deploy to Dedicated Server
Deploy-ToTarget $TargetServerPath "Palworld Dedicated Server" -isDedicatedServer $true

Write-Host "==========================================" -ForegroundColor Cyan
Write-Host "Deployment complete across all targets!   " -ForegroundColor Green
Write-Host "==========================================" -ForegroundColor Cyan
