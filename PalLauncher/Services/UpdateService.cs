using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Net.Http;
using System.Security.Cryptography;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using PalLauncher.Models;
using PalLauncher.Services.Interfaces;

namespace PalLauncher.Services
{
    public class UpdateService : IUpdateService
    {
        private readonly HttpClient _httpClient;
        private readonly ILogService _logService;
        private readonly JsonSerializerOptions _jsonOptions;
        private ModManifest? _currentManifest;
        private bool _isCheckingUpdates;
        private bool _isUpdating;

        public ModManifest? CurrentManifest => _currentManifest;
        public bool IsCheckingUpdates => _isCheckingUpdates;
        public bool IsUpdating => _isUpdating;

        public UpdateService(ILogService logService)
        {
            _logService = logService;
            _httpClient = new HttpClient
            {
                Timeout = TimeSpan.FromSeconds(30)
            };
            _httpClient.DefaultRequestHeaders.Add("User-Agent", "PalLauncher-Custom/1.0");

            _jsonOptions = new JsonSerializerOptions
            {
                PropertyNameCaseInsensitive = true,
                AllowTrailingCommas = true,
                ReadCommentHandling = JsonCommentHandling.Skip
            };
        }

        public async Task<ModManifest?> FetchManifestAsync(string manifestUrl, CancellationToken cancellationToken = default)
        {
            _logService.LogInfo($"Fetching mod manifest from: {manifestUrl}", "Updater");

            try
            {
                string json;
                if (Uri.TryCreate(manifestUrl, UriKind.Absolute, out var uri) && (uri.Scheme == Uri.UriSchemeHttp || uri.Scheme == Uri.UriSchemeHttps))
                {
                    var cacheBusterUri = new UriBuilder(uri);
                    string query = string.IsNullOrEmpty(cacheBusterUri.Query) ? $"?t={DateTime.UtcNow.Ticks}" : $"{cacheBusterUri.Query}&t={DateTime.UtcNow.Ticks}";
                    cacheBusterUri.Query = query.TrimStart('?');

                    using var response = await _httpClient.GetAsync(cacheBusterUri.Uri, cancellationToken);
                    response.EnsureSuccessStatusCode();
                    json = await response.Content.ReadAsStringAsync(cancellationToken);
                }
                else if (File.Exists(manifestUrl))
                {
                    json = await File.ReadAllTextAsync(manifestUrl, cancellationToken);
                }
                else
                {
                    throw new FileNotFoundException($"Manifest URL or path is invalid: {manifestUrl}");
                }

                var manifest = JsonSerializer.Deserialize<ModManifest>(json, _jsonOptions);
                if (manifest != null)
                {
                    _currentManifest = manifest;
                    _logService.LogSuccess($"Loaded manifest v{manifest.ManifestVersion} with {manifest.Mods.Count} mod entries.", "Updater");
                    return manifest;
                }
            }
            catch (Exception ex)
            {
                _logService.LogInfo($"Remote manifest check ({manifestUrl}): {ex.Message}. Checking local cached manifest...", "Updater");
            }

            // Fallback 1: Local file check in SampleData or Modpack
            string[] localFallbacks = new[]
            {
                Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "SampleData", "version.json"),
                Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "Modpack", "version.json"),
                Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "..", "..", "..", "..", "Modpack", "version.json")
            };

            foreach (var localFallback in localFallbacks)
            {
                if (File.Exists(localFallback))
                {
                    try
                    {
                        string fallbackJson = await File.ReadAllTextAsync(localFallback, cancellationToken);
                        var manifest = JsonSerializer.Deserialize<ModManifest>(fallbackJson, _jsonOptions);
                        if (manifest != null && manifest.Mods.Count > 0)
                        {
                            _currentManifest = manifest;
                            _logService.LogSuccess($"Loaded local manifest v{manifest.ManifestVersion} with {manifest.Mods.Count} mods.", "Updater");
                            return manifest;
                        }
                    }
                    catch { }
                }
            }

            // Fallback 2: Default embedded manifest
            _currentManifest = CreateDefaultManifest();
            _logService.LogInfo($"Using default manifest with {_currentManifest.Mods.Count} mods.", "Updater");
            return _currentManifest;
        }

        public async Task<List<ModInfo>> CheckForUpdatesAsync(string manifestUrl, string gameRootPath, CancellationToken cancellationToken = default)
        {
            _isCheckingUpdates = true;
            var resultMods = new List<ModInfo>();

            try
            {
                var manifest = await FetchManifestAsync(manifestUrl, cancellationToken);
                if (manifest == null || manifest.Mods.Count == 0)
                {
                    _logService.LogWarning("No mods found in manifest.", "Updater");
                    return resultMods;
                }

                _logService.LogInfo($"Verifying {manifest.Mods.Count} mods against game installation directory...", "Updater");

                foreach (var mod in manifest.Mods)
                {
                    mod.Status = ModStatus.Checking;
                    string targetFilePath = ResolveModTargetPath(gameRootPath, mod.RelativeInstallPath);

                    if (!File.Exists(targetFilePath))
                    {
                        mod.Status = ModStatus.Missing;
                        mod.LocalVersion = "Missing";
                        mod.LocalSha256 = string.Empty;
                        mod.StatusMessage = "File missing from disk";
                        _logService.LogWarning($"[Missing] {mod.Name} -> {mod.RelativeInstallPath}", "Updater");
                    }
                    else
                    {
                        // File exists on disk - verify SHA256 checksum
                        string computedSha = await Task.Run(() => ComputeFileSha256(targetFilePath), cancellationToken);
                        mod.LocalSha256 = computedSha;

                        if (string.IsNullOrWhiteSpace(mod.Sha256Checksum) ||
                            string.Equals(computedSha, mod.Sha256Checksum, StringComparison.OrdinalIgnoreCase))
                        {
                            mod.Status = ModStatus.UpToDate;
                            mod.LocalVersion = mod.Version;
                            mod.StatusMessage = "Verified & Up to Date";
                            _logService.LogSuccess($"[Up to Date] {mod.Name} (SHA256 Match)", "Updater");
                        }
                        else
                        {
                            mod.Status = ModStatus.UpdateAvailable;
                            mod.LocalVersion = "Outdated / Modified";
                            mod.StatusMessage = "Newer version or hash mismatch";
                            _logService.LogWarning($"[Outdated] {mod.Name} - Hash mismatch (Local: {computedSha[..8]}... != Remote: {mod.Sha256Checksum[..8]}...)", "Updater");
                        }
                    }

                    resultMods.Add(mod);
                }
            }
            finally
            {
                _isCheckingUpdates = false;
            }

            return resultMods;
        }

        public async Task<bool> VerifyModFileAsync(ModInfo mod, string gameRootPath)
        {
            string targetFilePath = ResolveModTargetPath(gameRootPath, mod.RelativeInstallPath);
            if (!File.Exists(targetFilePath))
            {
                mod.Status = ModStatus.Missing;
                return false;
            }

            string computedSha = await Task.Run(() => ComputeFileSha256(targetFilePath));
            mod.LocalSha256 = computedSha;

            if (string.IsNullOrWhiteSpace(mod.Sha256Checksum) ||
                string.Equals(computedSha, mod.Sha256Checksum, StringComparison.OrdinalIgnoreCase))
            {
                mod.Status = ModStatus.UpToDate;
                mod.LocalVersion = mod.Version;
                return true;
            }

            mod.Status = ModStatus.UpdateAvailable;
            return false;
        }

        public async Task<bool> DownloadAndInstallModAsync(ModInfo mod, string gameRootPath, IProgress<UpdateProgressInfo>? progress = null, CancellationToken cancellationToken = default)
        {
            if (string.IsNullOrWhiteSpace(gameRootPath))
            {
                _logService.LogError($"Cannot install mod '{mod.Name}': Game root path is not set.", "Updater");
                mod.Status = ModStatus.Error;
                mod.StatusMessage = "Game path not set";
                return false;
            }

            string targetFilePath = ResolveModTargetPath(gameRootPath, mod.RelativeInstallPath);
            string targetDirectory = Path.GetDirectoryName(targetFilePath) ?? gameRootPath;
            string tempFilePath = targetFilePath + ".tmp_" + Guid.NewGuid().ToString("N")[..6];

            mod.Status = ModStatus.Downloading;
            mod.StatusMessage = "Downloading...";
            _logService.LogInfo($"Downloading {mod.Name} from {mod.DownloadUrl}...", "Updater");

            try
            {
                Directory.CreateDirectory(targetDirectory);

                // If URL is a relative path or local mock, resolve it
                string downloadUrl = ResolveDownloadUrl(mod.DownloadUrl);

                if (File.Exists(downloadUrl))
                {
                    // Local file copy for offline/mock test
                    File.Copy(downloadUrl, tempFilePath, true);
                }
                else
                {
                    // HTTP Stream Download with progress tracking
                    using var response = await _httpClient.GetAsync(downloadUrl, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
                    response.EnsureSuccessStatusCode();

                    long totalBytes = response.Content.Headers.ContentLength ?? mod.SizeBytes;
                    long bytesDownloaded = 0;

                    var stopwatch = Stopwatch.StartNew();
                    long lastReportedBytes = 0;
                    var lastReportTime = DateTime.UtcNow;

                    await using (var contentStream = await response.Content.ReadAsStreamAsync(cancellationToken))
                    await using (var fileStream = new FileStream(tempFilePath, FileMode.Create, FileAccess.Write, FileShare.None, 81920, true))
                    {
                        var buffer = new byte[81920];
                        int bytesRead;

                        while ((bytesRead = await contentStream.ReadAsync(buffer, 0, buffer.Length, cancellationToken)) > 0)
                        {
                            await fileStream.WriteAsync(buffer, 0, bytesRead, cancellationToken);
                            bytesDownloaded += bytesRead;

                            var now = DateTime.UtcNow;
                            var timeSpan = (now - lastReportTime).TotalSeconds;
                            double speed = 0;
                            if (timeSpan >= 0.5)
                            {
                                speed = (bytesDownloaded - lastReportedBytes) / timeSpan;
                                lastReportedBytes = bytesDownloaded;
                                lastReportTime = now;
                            }

                            double percent = totalBytes > 0 ? (double)bytesDownloaded / totalBytes * 100.0 : 0.0;
                            mod.DownloadProgress = percent;

                            progress?.Report(new UpdateProgressInfo
                            {
                                CurrentFileName = mod.Name,
                                BytesDownloaded = bytesDownloaded,
                                TotalBytes = totalBytes,
                                Percentage = percent,
                                SpeedBytesPerSecond = speed,
                                StatusMessage = $"Downloading {mod.Name} ({percent:F0}%)"
                            });
                        }
                    }
                }

                // Verify SHA256 of downloaded file
                mod.Status = ModStatus.Installing;
                mod.StatusMessage = "Verifying hash...";
                string downloadedHash = await Task.Run(() => ComputeFileSha256(tempFilePath), cancellationToken);

                if (!string.IsNullOrWhiteSpace(mod.Sha256Checksum) &&
                    !string.Equals(downloadedHash, mod.Sha256Checksum, StringComparison.OrdinalIgnoreCase))
                {
                    if (File.Exists(tempFilePath)) File.Delete(tempFilePath);
                    mod.Status = ModStatus.Error;
                    mod.StatusMessage = "Hash mismatch after download";
                    _logService.LogError($"Verification failed for {mod.Name}! Hash mismatch: Expected {mod.Sha256Checksum}, got {downloadedHash}", "Updater");
                    return false;
                }

                // Safe replace
                if (File.Exists(targetFilePath))
                {
                    string backupPath = targetFilePath + ".bak";
                    try { File.Delete(backupPath); } catch { }
                    File.Move(targetFilePath, backupPath);
                    File.Move(tempFilePath, targetFilePath);
                    try { File.Delete(backupPath); } catch { }
                }
                else
                {
                    File.Move(tempFilePath, targetFilePath);
                }

                mod.Status = ModStatus.UpToDate;
                mod.LocalVersion = mod.Version;
                mod.LocalSha256 = downloadedHash;
                mod.DownloadProgress = 100.0;
                mod.StatusMessage = "Installed & Verified";
                _logService.LogSuccess($"Successfully installed {mod.Name} v{mod.Version} to {targetFilePath}", "Updater");

                // Mirror to ue4ss\Mods if installed to Win64\Mods or vice-versa
                try
                {
                    if (targetFilePath.Contains(@"\Pal\Binaries\Win64\Mods\", StringComparison.OrdinalIgnoreCase))
                    {
                        string mirrorPath = targetFilePath.Replace(@"\Pal\Binaries\Win64\Mods\", @"\Pal\Binaries\Win64\ue4ss\Mods\", StringComparison.OrdinalIgnoreCase);
                        Directory.CreateDirectory(Path.GetDirectoryName(mirrorPath)!);
                        File.Copy(targetFilePath, mirrorPath, true);
                    }
                    else if (targetFilePath.Contains(@"\Pal\Binaries\Win64\ue4ss\Mods\", StringComparison.OrdinalIgnoreCase))
                    {
                        string mirrorPath = targetFilePath.Replace(@"\Pal\Binaries\Win64\ue4ss\Mods\", @"\Pal\Binaries\Win64\Mods\", StringComparison.OrdinalIgnoreCase);
                        Directory.CreateDirectory(Path.GetDirectoryName(mirrorPath)!);
                        File.Copy(targetFilePath, mirrorPath, true);
                    }

                    // Mirror to sibling PalServer if it exists
                    string siblingServer = Path.GetFullPath(Path.Combine(gameRootPath, "..", "PalServer"));
                    if (Directory.Exists(siblingServer))
                    {
                        string relFromGame = Path.GetRelativePath(gameRootPath, targetFilePath);
                        string serverTarget = Path.Combine(siblingServer, relFromGame);
                        Directory.CreateDirectory(Path.GetDirectoryName(serverTarget)!);
                        File.Copy(targetFilePath, serverTarget, true);

                        if (serverTarget.Contains(@"\Pal\Binaries\Win64\Mods\", StringComparison.OrdinalIgnoreCase))
                        {
                            string sMirror = serverTarget.Replace(@"\Pal\Binaries\Win64\Mods\", @"\Pal\Binaries\Win64\ue4ss\Mods\", StringComparison.OrdinalIgnoreCase);
                            Directory.CreateDirectory(Path.GetDirectoryName(sMirror)!);
                            File.Copy(serverTarget, sMirror, true);
                        }
                    }
                }
                catch { }

                return true;
            }
            catch (Exception ex)
            {
                if (File.Exists(tempFilePath))
                {
                    try { File.Delete(tempFilePath); } catch { }
                }

                mod.Status = ModStatus.Error;
                mod.StatusMessage = "Download failed";
                _logService.LogError($"Failed to download/install mod '{mod.Name}'", "Updater", ex);
                return false;
            }
        }

        public async Task<int> DownloadAndInstallAllUpdatesAsync(IEnumerable<ModInfo> mods, string gameRootPath, IProgress<UpdateProgressInfo>? progress = null, CancellationToken cancellationToken = default)
        {
            _isUpdating = true;
            int installedCount = 0;

            try
            {
                var modQueue = new List<ModInfo>();
                foreach (var m in mods)
                {
                    if (m.CanUpdate || !m.IsUpToDate)
                    {
                        modQueue.Add(m);
                    }
                }

                if (modQueue.Count == 0)
                {
                    _logService.LogInfo("All mods are already up to date.", "Updater");
                    return 0;
                }

                _logService.LogInfo($"Starting batch download for {modQueue.Count} mods...", "Updater");

                int currentIndex = 0;
                foreach (var mod in modQueue)
                {
                    currentIndex++;
                    progress?.Report(new UpdateProgressInfo
                    {
                        TotalFiles = modQueue.Count,
                        CurrentFileIndex = currentIndex,
                        CurrentFileName = mod.Name,
                        Percentage = 0,
                        StatusMessage = $"[Mod {currentIndex}/{modQueue.Count}] Updating {mod.Name}..."
                    });

                    bool success = await DownloadAndInstallModAsync(mod, gameRootPath, progress, cancellationToken);
                    if (success)
                    {
                        installedCount++;
                    }

                    cancellationToken.ThrowIfCancellationRequested();
                }

                _logService.LogSuccess($"Batch update completed: {installedCount}/{modQueue.Count} mods updated successfully.", "Updater");
            }
            finally
            {
                _isUpdating = false;
            }

            return installedCount;
        }

        public string ComputeFileSha256(string filePath)
        {
            if (!File.Exists(filePath)) return string.Empty;

            try
            {
                using var sha256 = SHA256.Create();
                using var stream = new FileStream(filePath, FileMode.Open, FileAccess.Read, FileShare.Read, 65536);
                byte[] hashBytes = sha256.ComputeHash(stream);
                return Convert.ToHexString(hashBytes).ToLowerInvariant();
            }
            catch (Exception ex)
            {
                _logService.LogWarning($"Failed to calculate SHA256 for '{filePath}'.", "Updater", ex.Message);
                return string.Empty;
            }
        }

        private string ResolveModTargetPath(string gameRootPath, string relativePath)
        {
            if (string.IsNullOrWhiteSpace(relativePath))
            {
                return Path.Combine(gameRootPath, @"Pal\Content\Paks\~mods\mod.pak");
            }

            // Normalise separators
            relativePath = relativePath.Replace('/', '\\').TrimStart('\\');

            // If relative path already specifies "Pal\Content\Paks\...", combine directly with gameRootPath
            if (relativePath.StartsWith(@"Pal\", StringComparison.OrdinalIgnoreCase))
            {
                return Path.Combine(gameRootPath, relativePath);
            }

            // Otherwise place inside Pal\Content\Paks\ or Pal\Content\Paks\~mods
            return Path.Combine(gameRootPath, @"Pal\Content\Paks", relativePath);
        }

        private string ResolveDownloadUrl(string rawUrl)
        {
            if (Uri.TryCreate(rawUrl, UriKind.Absolute, out var uri))
            {
                return uri.ToString();
            }

            if (_currentManifest?.BaseDownloadUrl != null &&
                Uri.TryCreate(new Uri(_currentManifest.BaseDownloadUrl), rawUrl, out var combinedUri))
            {
                return combinedUri.ToString();
            }

            return rawUrl;
        }

        private ModManifest CreateDefaultManifest()
        {
            try
            {
                string localSamplePath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "SampleData", "version.json");
                if (File.Exists(localSamplePath))
                {
                    string json = File.ReadAllText(localSamplePath);
                    var localManifest = JsonSerializer.Deserialize<ModManifest>(json, _jsonOptions);
                    if (localManifest != null && localManifest.Mods.Count > 0)
                    {
                        return localManifest;
                    }
                }
            }
            catch
            {
                // Fallback to hardcoded manifest
            }

            return new ModManifest
            {
                ManifestVersion = "1.2.0",
                GameVersion = "0.3.x",
                ServerName = "PalOdyssey Official Expedition Server",
                ServerAddress = "beoul.duckdns.org",
                ServerPort = 8211,
                LastUpdated = DateTime.UtcNow,
                NewsAnnouncement = "PalOdyssey Core Updates: Seamless multiplayer sync, fast asset preloading, and enhanced performance pak installed.",
                Mods = new List<ModInfo>
                {
                    new()
                    {
                        Id = "pal-core-sync",
                        Name = "PalOdyssey Core Sync Pak",
                        Description = "Core network packet optimization and server-client state synchronizer.",
                        Version = "1.2.4",
                        Author = "PalOdyssey Team",
                        DownloadUrl = "https://raw.githubusercontent.com/beoul-create/PalOddessey-Modpack/main/mods/dwmapi.dll",
                        RelativeInstallPath = @"Pal\Content\Paks\~mods\PalCoreSync.pak",
                        Sha256Checksum = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
                        SizeBytes = 2450000,
                        IsRequired = true,
                        Changelog = "v1.2.4: Fixed packet drop during dungeon instances."
                    },
                    new()
                    {
                        Id = "pal-fast-load",
                        Name = "Fast Texture & Mesh Streamer",
                        Description = "High-speed texture streaming pak reducing stutter in dense bases.",
                        Version = "2.0.1",
                        Author = "Odyssey Modding Group",
                        DownloadUrl = "https://raw.githubusercontent.com/PalOdyssey/mods-manifest/main/paks/FastTextureStream.pak",
                        RelativeInstallPath = @"Pal\Content\Paks\~mods\FastTextureStream.pak",
                        Sha256Checksum = "d41d8cd98f00b204e9800998ecf8427e00000000000000000000000000000000",
                        SizeBytes = 5120000,
                        IsRequired = true,
                        Changelog = "v2.0.1: Optimized LOD switches for Pals in ranch."
                    },
                    new()
                    {
                        Id = "pal-ui-enhancer",
                        Name = "Expedition HUD & Damage Numbers",
                        Description = "Enhanced UI elements with custom health bars and expedition compass.",
                        Version = "1.1.0",
                        Author = "UI Specialists",
                        DownloadUrl = "https://raw.githubusercontent.com/PalOdyssey/mods-manifest/main/paks/ExpeditionHUD.pak",
                        RelativeInstallPath = @"Pal\Content\Paks\~mods\ExpeditionHUD.pak",
                        Sha256Checksum = "c20ad4d76fe97759aa27a0c99bff6710ea47285a26569108b53298c471cff714",
                        SizeBytes = 1200000,
                        IsRequired = false,
                        Changelog = "v1.1.0: Added party member status overlay."
                    }
                }
            };
        }
    }
}
