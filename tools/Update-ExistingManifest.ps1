param(
    [string]$ManifestPath = "$PSScriptRoot\..\manifest.json",
    [string]$ContentRoot = "$PSScriptRoot\.."
)

$ErrorActionPreference = "Stop"
$manifestPathResolved = (Resolve-Path -LiteralPath $ManifestPath).Path
$contentRootResolved = (Resolve-Path -LiteralPath $ContentRoot).Path
$manifest = Get-Content -Raw -LiteralPath $manifestPathResolved | ConvertFrom-Json

foreach ($entry in $manifest.Files) {
    $relative = $entry.RelativePath.Replace('/', [IO.Path]::DirectorySeparatorChar)
    $fullPath = Join-Path $contentRootResolved $relative
    if (-not (Test-Path -LiteralPath $fullPath -PathType Leaf)) {
        throw "Tracked manifest file is missing: $($entry.RelativePath)"
    }
    $file = Get-Item -LiteralPath $fullPath
    $entry.Hash = (Get-FileHash -LiteralPath $fullPath -Algorithm SHA256).Hash.ToLowerInvariant()
    $entry.Size = $file.Length
}

$now = Get-Date
$manifest.Version = $now.ToUniversalTime().ToString("yyyy.MM.dd.HHmmss")
$manifest.GeneratedAt = $now.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
$manifest.TotalFiles = $manifest.Files.Count

$json = $manifest | ConvertTo-Json -Depth 10
$tempPath = $manifestPathResolved + ".tmp"
[IO.File]::WriteAllText($tempPath, $json, [Text.UTF8Encoding]::new($false))
Move-Item -LiteralPath $tempPath -Destination $manifestPathResolved -Force

foreach ($mirror in @("Pal\manifest.json", "publish\Release\manifest.json")) {
    $mirrorPath = Join-Path $contentRootResolved $mirror
    if (Test-Path -LiteralPath (Split-Path -Parent $mirrorPath)) {
        Copy-Item -LiteralPath $manifestPathResolved -Destination $mirrorPath -Force
    }
}

Write-Host "Updated $($manifest.TotalFiles) tracked hashes; version $($manifest.Version)."
