using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
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
                    string cacheBusterUrl = url + (url.Contains('?') ? "&" : "?") + $"t={DateTimeOffset.UtcNow.ToUnixTimeSeconds()}";
                    using var request = new HttpRequestMessage(HttpMethod.Get, cacheBusterUrl);
                    request.Headers.CacheControl = new System.Net.Http.Headers.CacheControlHeaderValue
                    {
                        NoCache = true,
                        NoStore = true,
                        MustRevalidate = true
                    };

                    using var response = await _httpClient.SendAsync(request, HttpCompletionOption.ResponseContentRead, cancellationToken);
                    if (response.IsSuccessStatusCode)
                    {
                        string json = await response.Content.ReadAsStringAsync(cancellationToken);
                        var manifest = JsonSerializer.Deserialize<ManifestModel>(json, JsonOptions);
                        if (manifest != null && manifest.Files.Count > 0)
                            return manifest;
                    }
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

            var verificationResults = new bool[manifest.Files.Count];
            int completedCount = 0;

            // Two readers saturate typical SSDs without turning integrity checks into
            // random-I/O contention on hard drives or starving the WPF UI thread.
            await Parallel.ForEachAsync(
                Enumerable.Range(0, manifest.Files.Count),
                new ParallelOptions
                {
                    MaxDegreeOfParallelism = 2,
                    CancellationToken = cancellationToken
                },
                async (i, token) =>
            {
                var item = manifest.Files[i];
                string resolvedPath = item.GetResolvedPath(gameRootPath);

                if (item.TargetCategory == ModTargetCategory.PakMod)
                {
                    lock (result.ValidPakFileNames)
                    {
                        result.ValidPakFileNames.Add(Path.GetFileName(resolvedPath));
                    }
                }

                var (isValid, _) = await _hashService.VerifyFileWithCacheAsync(
                    resolvedPath,
                    item.RelativePath,
                    item.FileSize,
                    item.Sha256,
                    cache,
                    token);

                verificationResults[i] = isValid;
                int completed = Interlocked.Increment(ref completedCount);
                statusProgress?.Report($"Verifying ({completed}/{manifest.Files.Count}): {Path.GetFileName(resolvedPath)}");
            });

            // Merge sequentially to retain manifest order and avoid locks in the hot path.
            for (int i = 0; i < manifest.Files.Count; i++)
            {
                var item = manifest.Files[i];
                if (!verificationResults[i])
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
                        LinkUrl = "https://discord.gg/8YCVeQgUVq"
                    },
                    new()
                    {
                        Title = "Weekend Breeding & EXP Event",
                        Date = "Upcoming",
                        Summary = "Enjoy 2.0x Egg Incubation speed and 1.5x Capture XP rate through Sunday midnight.",
                        LinkUrl = "https://discord.gg/8YCVeQgUVq"
                    }
                },
                Files = new List<ModFileItem>
                {
                    new()
                    {
                        RelativePath = "Pal/Binaries/Win64/dwmapi.dll",
                        TargetCategory = ModTargetCategory.Root,
                        FileSize = 61952,
                        Sha256 = "6c6e7151c206628445eb69c3dfee702b31bc51208df13a5cc15c2118c413cde1",
                        DownloadUrl = "https://raw.githubusercontent.com/beoul-create/PalOdessey-Modpack/main/Pal/Binaries/Win64/dwmapi.dll",
                        Description = "Core UE4SS injection hook"
                    }
                }
            };
        }
    }
}
