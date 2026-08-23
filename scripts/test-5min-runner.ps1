# test-5min-runner.ps1
# Continuous 5-minute integration and health validation test runner for PalLauncher

param (
    [int]$DurationSeconds = 300
)

$ErrorActionPreference = "Stop"
$env:DOTNET_ROOT = "C:\Users\jackt\.dotnet"
$env:PATH = "C:\Users\jackt\.dotnet;$env:PATH"

Write-Host "============================================================" -ForegroundColor Cyan
Write-Host " PalLauncher 5-Minute Continuous Validation & Error Check   " -ForegroundColor Yellow
Write-Host " Target Duration: $DurationSeconds seconds (~$([Math]::Round($DurationSeconds/60, 1)) minutes) " -ForegroundColor Cyan
Write-Host "============================================================" -ForegroundColor Cyan

$startTime = [System.Diagnostics.Stopwatch]::StartNew()
$totalErrors = 0
$iteration = 0
$errorLog = @()

function Log-TestStep($name, $passed, $details = "") {
    if ($passed) {
        Write-Host " [PASS] $name" -ForegroundColor Green
    } else {
        Write-Host " [FAIL] $name : $details" -ForegroundColor Red
        $script:totalErrors++
        $script:errorLog += "Iteration $($script:iteration) - ${name}: $details"
    }
}

# Test 1: Unit Test Suite Execution
Write-Host "`n[PHASE 1] Running .NET Unit Test Suite..." -ForegroundColor Cyan
try {
    $testOutput = & "C:\Users\jackt\.dotnet\dotnet.exe" test "c:\PalOddessey\PalLauncher.Tests\PalLauncher.Tests.csproj" --no-restore -v normal 2>&1
    if ($LASTEXITCODE -eq 0) {
        Log-TestStep "All 24 Unit Tests Passed" $true
    } else {
        Log-TestStep "Unit Tests" $false ($testOutput | Out-String)
    }
} catch {
    Log-TestStep "Unit Test Runner" $false $_.Exception.Message
}

# Phase 2: Manifest & URL Integrity Check
Write-Host "`n[PHASE 2] Validating Manifests & Repository URLs..." -ForegroundColor Cyan
$manifestFiles = @(
    "c:\PalOddessey\PalLauncher\SampleData\version.json",
    "c:\PalOddessey\Modpack\version.json",
    "c:\PalOddessey\publish\SampleData\version.json",
    "c:\PalOddessey\GitHub-Modpack-Release\version.json"
)

foreach ($mf in $manifestFiles) {
    if (Test-Path $mf) {
        try {
            $json = Get-Content $mf -Raw | ConvertFrom-Json
            $hasValidUrl = $json.baseDownloadUrl -like "*github.com/beoul-create/PalOdessey-Modpack*"
            Log-TestStep "Manifest JSON & BaseDownloadURL ($mf)" $hasValidUrl "URL: $($json.baseDownloadUrl)"
            
            # Validate mods structure
            if ($null -ne $json.mods -and $json.mods.Count -gt 0) {
                Log-TestStep "Manifest Mods Count ($($json.mods.Count) mods found)" $true
            } else {
                Log-TestStep "Manifest Mods Validation" $false "No mods array found in $mf"
            }
        } catch {
            Log-TestStep "Manifest Parsing ($mf)" $false $_.Exception.Message
        }
    } else {
        Log-TestStep "Manifest File Existence ($mf)" $false "File not found"
    }
}

# Phase 3: Continuous 5-minute Stress & Functional Loop
Write-Host "`n[PHASE 3] Starting 5-Minute Continuous Loop..." -ForegroundColor Cyan
$lastReportSec = 0

while ($startTime.Elapsed.TotalSeconds -lt $DurationSeconds) {
    $iteration++
    $currentSec = [int]$startTime.Elapsed.TotalSeconds
    $remainingSec = [int]($DurationSeconds - $currentSec)
    
    if ($currentSec - $lastReportSec -ge 30 -or $iteration -eq 1) {
        $lastReportSec = $currentSec
        Write-Host " ---> Progress: Elapsed: ${currentSec}s / ${DurationSeconds}s (Remaining: ${remainingSec}s, Iterations: $iteration, Errors: $totalErrors)" -ForegroundColor Yellow
    }

    # Sub-test A: Config Serialization roundtrip
    try {
        $tempConfig = [System.IO.Path]::GetTempFileName()
        $cfgJson = @{
            gamePath = "C:\Test\Palworld"
            serverIp = "127.0.0.1"
            serverPort = 8211
            remoteManifestUrl = "https://raw.githubusercontent.com/beoul-create/PalOdessey-Modpack/main/Modpack/version.json"
            autoUpdateBeforeLaunch = $true
        } | ConvertTo-Json
        
        Set-Content -Path $tempConfig -Value $cfgJson
        $readBack = Get-Content -Path $tempConfig -Raw | ConvertFrom-Json
        if ($readBack.remoteManifestUrl -ne "https://raw.githubusercontent.com/beoul-create/PalOdessey-Modpack/main/Modpack/version.json") {
            Log-TestStep "Config Serialization" $false "URL mismatch in serialization"
        }
        Remove-Item $tempConfig -Force -ErrorAction SilentlyContinue
    } catch {
        Log-TestStep "Config Serialization Loop" $false $_.Exception.Message
    }

    # Sub-test B: File hashing & Mod Integrity simulation
    try {
        $sampleFile = "c:\PalOddessey\PalLauncher\SampleData\version.json"
        $sha = Get-FileHash -Path $sampleFile -Algorithm SHA256
        if ([string]::IsNullOrWhiteSpace($sha.Hash)) {
            Log-TestStep "SHA256 Hash Computation" $false "Computed empty hash"
        }
    } catch {
        Log-TestStep "Hashing Loop" $false $_.Exception.Message
    }

    # Sub-test C: Periodic Fast Unit Test Validation every 60s
    if ($currentSec % 60 -lt 2 -and $currentSec -gt 5) {
        try {
            $testRun = & "C:\Users\jackt\.dotnet\dotnet.exe" test "c:\PalOddessey\PalLauncher.Tests\PalLauncher.Tests.csproj" --no-build --no-restore -v quiet 2>&1
            if ($LASTEXITCODE -ne 0) {
                Log-TestStep "Periodic Test Run (at ${currentSec}s)" $false ($testRun | Out-String)
            }
        } catch {
            Log-TestStep "Periodic Test Run" $false $_.Exception.Message
        }
    }

    Start-Sleep -Milliseconds 500
}

$startTime.Stop()
Write-Host "`n============================================================" -ForegroundColor Cyan
Write-Host "                TEST RUN COMPLETE                           " -ForegroundColor Yellow
Write-Host " Total Time Elapsed: $([Math]::Round($startTime.Elapsed.TotalSeconds, 2))s " -ForegroundColor Cyan
Write-Host " Total Iterations:   $iteration " -ForegroundColor Cyan
Write-Host " Total Errors:       $totalErrors " -ForegroundColor $(if ($totalErrors -eq 0) { "Green" } else { "Red" })
Write-Host "============================================================" -ForegroundColor Cyan

if ($totalErrors -gt 0) {
    Write-Host "`nError Summary:" -ForegroundColor Red
    $errorLog | ForEach-Object { Write-Host " - $_" -ForegroundColor Red }
    exit 1
} else {
    Write-Host "`nAll continuous 5-minute stability and integrity tests passed with 0 errors!" -ForegroundColor Green
    exit 0
}
