using System;
using System.Collections.Generic;
using System.IO;
using System.Net.Http;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using PalLauncher.Models;

namespace PalLauncher.Services
{
    public class SyncDeltaResult
    {
        public List<ModFileItem> FilesToDownload { get; set; } = new();
        public List<ModFileItem> UpToDateFiles { get; set; } = new();
        public HashSet<string> ValidPakFileNames { get; set; } = new(StringComparer.OrdinalIgnoreCase);
        public long TotalBytesToDownload { get; set; }
        public int TotalFilesCount { get; set; }
    }

    public class ManifestService
    {
        private readonly HttpClient _httpClient;
        private readonly HashService _hashService;

        private static readonly JsonSerializerOptions JsonOptions = new()
        {
            PropertyNameCaseInsensitive = true,
            AllowTrailingCommas = true
        };

        public ManifestService(HashService? hashService = null)
        {
            _hashService = hashService ?? new HashService();
            _httpClient = new HttpClient
            {
                Timeout = TimeSpan.FromSeconds(15)
            };
            _httpClient.DefaultRequestHeaders.UserAgent.ParseAdd("PalOdyssey-Launcher/2.0");
        }

        /// <summary>
        /// Fetches the manifest from a remote URL, with optional local fallback file.
        /// </summary>
        public async Task<ManifestModel> FetchManifestAsync(string url, string? localFallbackPath = null, CancellationToken cancellationToken = default)
        {
            try
            {
                if (!string.IsNullOrWhiteSpace(url) && (url.StartsWith("http://", StringComparison.OrdinalIgnoreCase) || url.StartsWith("https://", StringComparison.OrdinalIgnoreCase)))
                {
                    string json = await _httpClient.GetStringAsync(url, cancellationToken);
                    var manifest = JsonSerializer.Deserialize<ManifestModel>(json, JsonOptions);
                    if (manifest != null)
                        return manifest;
                }
            }
            catch (Exception)
            {
                // Fall back to local file if remote cannot be fetched
            }

            // Check local fallback
            if (!string.IsNullOrWhiteSpace(localFallbackPath) && File.Exists(localFallbackPath))
            {
                string localJson = await File.ReadAllTextAsync(localFallbackPath, cancellationToken);
                var manifest = JsonSerializer.Deserialize<ManifestModel>(localJson, JsonOptions);
                if (manifest != null)
                    return manifest;
            }

            // Default fallback manifest
            return GetDefaultFallbackManifest();
        }

        /// <summary>
        /// Computes sync delta by comparing manifest files against local game directory.
        /// </summary>
        public async Task<SyncDeltaResult> CalculateDeltaAsync(
            ManifestModel manifest,
            string gameRootPath,
            LocalCache cache,
            IProgress<string>? statusProgress = null,
            CancellationToken cancellationToken = default)
        {
            var result = new SyncDeltaResult
            {
                TotalFilesCount = manifest.Files.Count
            };

            for (int i = 0; i < manifest.Files.Count; i++)
            {
                cancellationToken.ThrowIfCancellationRequested();

                var item = manifest.Files[i];
                string resolvedPath = item.GetResolvedPath(gameRootPath);

                if (item.TargetCategory == ModTargetCategory.PakMod)
                {
                    result.ValidPakFileNames.Add(Path.GetFileName(resolvedPath));
                }

                statusProgress?.Report($"Verifying ({i + 1}/{manifest.Files.Count}): {Path.GetFileName(resolvedPath)}");

                var (isValid, _) = await _hashService.VerifyFileWithCacheAsync(
                    resolvedPath,
                    item.RelativePath,
                    item.FileSize,
                    item.Sha256,
                    cache,
                    cancellationToken);

                if (!isValid)
                {
                    result.FilesToDownload.Add(item);
                    result.TotalBytesToDownload += item.FileSize;
                }
                else
                {
                    result.UpToDateFiles.Add(item);
                }
            }

            return result;
        }

        public static ManifestModel GetDefaultFallbackManifest()
        {
            return new ManifestModel
            {
                ServerName = "PalOdyssey Modded Sanctuary",
                ServerAddress = "palodyssey.duckdns.org",
                ServerPort = 8211,
                GameVersion = "v0.3.5",
                ManifestVersion = "2.0.0",
                News = new List<ServerNewsItem>
                {
                    new()
                    {
                        Title = "PalOdyssey 2.0 Update Live!",
                        Date = "Today",
                        Summary = "Enhanced dedicated server synchronization, new raid bosses, and balanced pal breeding parameters are now active.",
                        LinkUrl = "https://palodyssey.gg/news/2.0"
                    },
                    new()
                    {
                        Title = "Weekend Breeding & EXP Event",
                        Date = "Upcoming",
                        Summary = "Enjoy 2.0x Egg Incubation speed and 1.5x Capture XP rate through Sunday midnight.",
                        LinkUrl = "https://palodyssey.gg/events"
                    }
                },
                Files = new List<ModFileItem>
                {
                    new()
                    {
                        RelativePath = "PalOdyssey_Core.pak",
                        TargetCategory = ModTargetCategory.PakMod,
                        FileSize = 1048576,
                        Sha256 = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
                        DownloadUrl = "https://palodyssey.gg/mods/PalOdyssey_Core.pak",
                        Description = "Core PalOdyssey game modifications and custom textures"
                    },
                    new()
                    {
                        RelativePath = "PalOdyssey_UI.pak",
                        TargetCategory = ModTargetCategory.PakMod,
                        FileSize = 524288,
                        Sha256 = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
                        DownloadUrl = "https://palodyssey.gg/mods/PalOdyssey_UI.pak",
                        Description = "Custom server HUD indicators and map markers"
                    }
                }
            };
        }
    }
}
