# Set .NET SDK environment paths
$userDotnet = "$env:USERPROFILE\.dotnet"
if (Test-Path $userDotnet) {
    $env:DOTNET_ROOT = $userDotnet
    $env:PATH = "$userDotnet;$env:PATH"
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
dotnet run --project "$PSScriptRoot\PalLauncher\PalLauncher.csproj"
