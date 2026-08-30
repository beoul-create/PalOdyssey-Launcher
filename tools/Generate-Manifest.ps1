# Parameters: adjust $ModpackStagingPath and $BaseDownloadUrl to your hosting endpoint
param(
    [string]$ModpackStagingPath = "",
    [string]$BaseDownloadUrl = "https://raw.githubusercontent.com/beoul-create/PalOdessey-Modpack/main",
    [string]$OutputPath = ""
)

$ErrorActionPreference = "Stop"

if ([string]::IsNullOrWhiteSpace($ModpackStagingPath)) {
    if (Test-Path "$PSScriptRoot\..\PalOdyssey-ModpackStaging") {
        $ModpackStagingPath = (Resolve-Path "$PSScriptRoot\..\PalOdyssey-ModpackStaging").Path
    } elseif (Test-Path "c:\PalOdyssey-ModpackStaging") {
        $ModpackStagingPath = "c:\PalOdyssey-ModpackStaging"
    } else {
        $ModpackStagingPath = "$PSScriptRoot\..\PalOdyssey-ModpackStaging"
    }
}

if ([string]::IsNullOrWhiteSpace($OutputPath)) {
    $OutputPath = Join-Path $ModpackStagingPath "manifest.json"
}

if (-not (Test-Path $ModpackStagingPath)) {
    Write-Error "Modpack staging path does not exist: $ModpackStagingPath"
    exit 1
}

Write-Host "Scanning modpack files in: $ModpackStagingPath" -ForegroundColor Cyan

# Gather all files except manifest.json itself or any hidden/temp files
$files = Get-ChildItem -Path $ModpackStagingPath -Recurse -File | Where-Object {
    $_.Name -ne "manifest.json" -and $_.Extension -ne ".tmp"
}

$manifestEntries = @()

foreach ($file in $files) {
    # Compute relative path from the staging root
    $relativePath = $file.FullName.Substring($ModpackStagingPath.Length).TrimStart('\', '/')
    $normalizedRelativePath = $relativePath.Replace('\', '/')

    # Compute SHA-256 Hash
    $hash = (Get-FileHash -Path $file.FullName -Algorithm SHA256).Hash.ToLowerInvariant()
    $fileSize = $file.Length

    # Build Download URL (Encodes spaces and special characters)
    $encodedRelativePath = [System.Uri]::EscapeUriString($normalizedRelativePath)
    # Content-address the URL so GitHub/CDN caches cannot serve bytes from a
    # previous commit for a newly published manifest hash.
    $downloadUrl = "$BaseDownloadUrl/$encodedRelativePath`?sha=$hash"

    Write-Host "  -> Processed: $normalizedRelativePath ($fileSize bytes) [$($hash.Substring(0, 8))...]" -ForegroundColor Gray

    $manifestEntries += [PSCustomObject]@{
        RelativePath = $normalizedRelativePath
        Hash         = $hash
        Size         = $fileSize
        DownloadUrl  = $downloadUrl
    }
}

# Construct Final Manifest Schema
$manifestObj = [PSCustomObject]@{
    Version     = (Get-Date -Format "yyyy.MM.dd.HHmmss")
    GeneratedAt = (Get-Date).ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
    TotalFiles  = $manifestEntries.Count
    Files       = $manifestEntries
}

# Serialize to JSON with formatting
$jsonOutput = $manifestObj | ConvertTo-Json -Depth 5

# Ensure output directory exists
$outputDir = Split-Path -Path $OutputPath -Parent
if (-not [string]::IsNullOrWhiteSpace($outputDir) -and -not (Test-Path $outputDir)) {
    New-Item -ItemType Directory -Force -Path $outputDir | Out-Null
}

# Write UTF8 without BOM
[System.IO.File]::WriteAllText($OutputPath, $jsonOutput, [System.Text.Encoding]::UTF8)

# Also update root manifest.json if exists
$rootManifestPath = Join-Path "$PSScriptRoot\.." "manifest.json"
if (Test-Path (Split-Path -Path $rootManifestPath -Parent)) {
    [System.IO.File]::WriteAllText($rootManifestPath, $jsonOutput, [System.Text.Encoding]::UTF8)
}

Write-Host "`nManifest generated successfully at: $OutputPath" -ForegroundColor Green
Write-Host "Total Files Indexed: $($manifestEntries.Count)" -ForegroundColor Green
