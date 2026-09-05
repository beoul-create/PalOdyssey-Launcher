using System;
using System.Buffers;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;
using PalLauncher.Models;

namespace PalLauncher.Services
{
    public class DownloadProgressReport
    {
        public long BytesDownloaded { get; set; }
        public long TotalBytesToDownload { get; set; }
        public double Percentage { get; set; }
        public double SpeedMbPerSec { get; set; }
        public string CurrentFileName { get; set; } = string.Empty;
        public int CurrentFileIndex { get; set; }
        public int TotalFileCount { get; set; }
        public string FormattedProgressText => $"{CurrentFileIndex}/{TotalFileCount} - {CurrentFileName} ({Percentage:F1}%)";
        public string FormattedSpeedText => $"{SpeedMbPerSec:F2} MB/s";
    }

    public class DownloadManager : IDisposable
    {
        private readonly HttpClient _httpClient;
        private readonly HashService _hashService;
        private bool _disposed;

        public DownloadManager(HashService? hashService = null)
        {
            _hashService = hashService ?? new HashService();
            var handler = new SocketsHttpHandler
            {
                PooledConnectionLifetime = TimeSpan.FromMinutes(2),
                MaxConnectionsPerServer = 10,
                EnableMultipleHttp2Connections = true
            };
            _httpClient = new HttpClient(handler)
            {
                Timeout = TimeSpan.FromMinutes(10)
            };
            _httpClient.DefaultRequestHeaders.UserAgent.ParseAdd("PalOdyssey-Launcher/2.0");
        }

        /// <summary>
        /// Downloads missing or outdated files with progress reporting, temporary file staging, and atomic rename.
        /// </summary>
        public async Task DownloadFilesAsync(
            List<ModFileItem> filesToDownload,
            string gameRootPath,
            LocalCache cache,
            string cachePath,
            IProgress<DownloadProgressReport>? progress = null,
            CancellationToken cancellationToken = default)
        {
            if (filesToDownload == null || filesToDownload.Count == 0)
                return;

            long totalBytesAllFiles = 0;
            foreach (var f in filesToDownload)
                totalBytesAllFiles += f.FileSize;

            long globalBytesDownloaded = 0;
            var stopwatch = Stopwatch.StartNew();
            long lastReportBytes = 0;
            double lastReportTime = 0;
            double currentSpeedMb = 0;
            var progressLock = new object();

            await Parallel.ForEachAsync(
                filesToDownload.Select((item, index) => (Item: item, Index: index)),
                new ParallelOptions
                {
                    MaxDegreeOfParallelism = 4,
                    CancellationToken = cancellationToken
                },
                async (entry, token) =>
            {
                var modItem = entry.Item;
                string destinationPath = modItem.GetResolvedPath(gameRootPath);
                string destinationDir = Path.GetDirectoryName(destinationPath)!;

                if (!Directory.Exists(destinationDir))
                {
                    Directory.CreateDirectory(destinationDir);
                }

                string tempPath = destinationPath + ".tmp";

                // Ensure clean temp file
                if (File.Exists(tempPath))
                {
                    try { File.Delete(tempPath); } catch { }
                }

                string effectiveUrl = !string.IsNullOrWhiteSpace(modItem.DownloadUrl) 
                    ? modItem.DownloadUrl 
                    : $"https://raw.githubusercontent.com/beoul-create/PalOdessey-Modpack/main/{Uri.EscapeDataString(modItem.RelativePath.TrimStart('/', '\\').Replace('\\', '/')).Replace("%2F", "/")}";

                try
                {
                    string cacheBusterUrl = effectiveUrl + (effectiveUrl.Contains('?') ? "&" : "?") + $"t={DateTimeOffset.UtcNow.ToUnixTimeSeconds()}";
                    using var request = new HttpRequestMessage(HttpMethod.Get, cacheBusterUrl);
                    request.Headers.CacheControl = new System.Net.Http.Headers.CacheControlHeaderValue
                    {
                        NoCache = true,
                        NoStore = true
                    };

                    using var response = await _httpClient.SendAsync(
                        request,
                        HttpCompletionOption.ResponseHeadersRead,
                        token);

                    if (!response.IsSuccessStatusCode)
                    {
                        throw new HttpRequestException($"Failed to download '{modItem.RelativePath}' (HTTP {(int)response.StatusCode} {response.ReasonPhrase}). Target URL: {effectiveUrl}", null, response.StatusCode);
                    }


                    long? serverContentLength = response.Content.Headers.ContentLength;
                    long expectedTotalBytes = serverContentLength ?? (modItem.FileSize > 0 ? modItem.FileSize : 0);

                    await using var streamToReadFrom = await response.Content.ReadAsStreamAsync(token);
                    await using (var fileStream = new FileStream(tempPath, new FileStreamOptions
                    {
                        Mode = FileMode.Create,
                        Access = FileAccess.Write,
                        Share = FileShare.None,
                        BufferSize = 256 * 1024,
                        Options = FileOptions.Asynchronous | FileOptions.SequentialScan,
                        PreallocationSize = Math.Max(0, expectedTotalBytes)
                    }))
                    {
                        byte[] buffer = ArrayPool<byte>.Shared.Rent(256 * 1024);
                        long fileBytesDownloaded = 0;

                        try
                        {
                            int bytesRead;
                            while ((bytesRead = await streamToReadFrom.ReadAsync(buffer.AsMemory(), token)) > 0)
                            {
                                await fileStream.WriteAsync(buffer.AsMemory(0, bytesRead), token);
                                fileBytesDownloaded += bytesRead;
                                long downloaded = Interlocked.Add(ref globalBytesDownloaded, bytesRead);

                                lock (progressLock)
                                {
                                    double elapsedSeconds = stopwatch.Elapsed.TotalSeconds;
                                    if (elapsedSeconds - lastReportTime >= 0.2 || downloaded >= totalBytesAllFiles)
                                    {
                                        double timeDelta = elapsedSeconds - lastReportTime;
                                        long byteDelta = downloaded - lastReportBytes;
                                        if (timeDelta > 0)
                                        {
                                            currentSpeedMb = (byteDelta / (1024.0 * 1024.0)) / timeDelta;
                                        }
                                        lastReportTime = elapsedSeconds;
                                        lastReportBytes = downloaded;

                                        double overallPercentage = totalBytesAllFiles > 0
                                            ? (double)downloaded / totalBytesAllFiles * 100.0
                                            : 100.0;

                                        progress?.Report(new DownloadProgressReport
                                        {
                                            BytesDownloaded = downloaded,
                                            TotalBytesToDownload = totalBytesAllFiles,
                                            Percentage = Math.Min(100.0, overallPercentage),
                                            SpeedMbPerSec = Math.Max(0.0, currentSpeedMb),
                                            CurrentFileName = Path.GetFileName(destinationPath),
                                            CurrentFileIndex = entry.Index + 1,
                                            TotalFileCount = filesToDownload.Count
                                        });
                                    }
                                }
                            }
                        }
                        finally
                        {
                            ArrayPool<byte>.Shared.Return(buffer);
                        }

                        if (serverContentLength.HasValue && serverContentLength.Value > 0 && fileBytesDownloaded != serverContentLength.Value)
                        {
                            throw new EndOfStreamException($"Download for '{modItem.RelativePath}' ended at {fileBytesDownloaded} of {serverContentLength.Value} bytes.");
                        }
                    }

                    // Verify downloaded hash
                    string downloadedHash = await _hashService.ComputeSha256Async(tempPath, token);
                    if (!string.IsNullOrWhiteSpace(modItem.Sha256) &&
                        !string.Equals(downloadedHash, modItem.Sha256, StringComparison.OrdinalIgnoreCase))
                    {
                        if (_hashService.IsTextFile(tempPath))
                        {
                            try
                            {
                                string textContent = await File.ReadAllTextAsync(tempPath, token);
                                string normalized = textContent.Replace("\r\n", "\n").Replace("\r", "\n");
                                byte[] normBytes = System.Text.Encoding.UTF8.GetBytes(normalized);
                                string normHash = Convert.ToHexString(System.Security.Cryptography.SHA256.HashData(normBytes)).ToLowerInvariant();
                                if (string.Equals(normHash, modItem.Sha256, StringComparison.OrdinalIgnoreCase))
                                {
                                    downloadedHash = modItem.Sha256;
                                }
                            }
                            catch { }
                        }

                        if (!string.Equals(downloadedHash, modItem.Sha256, StringComparison.OrdinalIgnoreCase))
                        {
                            if (File.Exists(tempPath)) File.Delete(tempPath);
                            throw new InvalidDataException($"Checksum validation failed for '{modItem.RelativePath}'. Expected: {modItem.Sha256}, Actual: {downloadedHash}");
                        }
                    }

                    // Atomic Replace / Move
                    try
                    {
                        File.Move(tempPath, destinationPath, overwrite: true);
                    }
                    catch (UnauthorizedAccessException uEx)
                    {
                        throw new IOException($"Access denied writing '{destinationPath}'. Ensure the file is not write-protected and your antivirus is not blocking it.", uEx);
                    }
                    catch (IOException ioEx)
                    {
                        throw new IOException($"Could not overwrite '{destinationPath}'. Ensure the game is closed and no other application is locking the file.", ioEx);
                    }

                    // Update cache
                    var finalFileInfo = new FileInfo(destinationPath);
                    lock (cache.Entries)
                    {
                        cache.Entries[modItem.RelativePath] = new CacheFileEntry
                        {
                            RelativePath = modItem.RelativePath,
                            ResolvedFullPath = destinationPath,
                            LastWriteTimeUtc = finalFileInfo.LastWriteTimeUtc,
                            FileSize = finalFileInfo.Length,
                            Sha256 = downloadedHash
                        };
                    }
                }
                catch
                {
                    if (File.Exists(tempPath))
                    {
                        try { File.Delete(tempPath); } catch { }
                    }
                    throw;
                }
            });

            // One atomic cache write replaces a full JSON serialization per file.
            cache.Save(cachePath);
        }

        /// <summary>
        /// Cleans up orphan .pak files inside Pal/Content/Paks/~mods that are not listed in the remote manifest.
        /// </summary>
        public int CleanupOrphanPakFiles(string gameRootPath, HashSet<string> validPakFileNames)
        {
            int deletedCount = 0;
            string modsDir = Path.Combine(gameRootPath, "Pal", "Content", "Paks", "~mods");
            if (!Directory.Exists(modsDir))
                return 0;

            try
            {
                var existingFiles = Directory.GetFiles(modsDir, "*.pak", SearchOption.TopDirectoryOnly);
                foreach (var file in existingFiles)
                {
                    string fileName = Path.GetFileName(file);
                    if (!validPakFileNames.Contains(fileName))
                    {
                        try
                        {
                            File.Delete(file);
                            deletedCount++;
                        }
                        catch (Exception)
                        {
                            // Best-effort cleanup
                        }
                    }
                }
            }
            catch (Exception)
            {
                // Ignore directory enumeration failures
            }

            return deletedCount;
        }

        /// <summary>
        /// Removes the retired WorldBoss music bridge from existing installations.
        /// The manifest no longer ships these files, but ordinary manifest sync does
        /// not delete non-pak files that were installed by an earlier release.
        /// </summary>
        public int CleanupRetiredMusicFiles(string gameRootPath)
        {
            string[] legacyRoots =
            {
                Path.Combine("Pal", "Binaries", "Win64", "Mods", "WorldBossAuraSystem"),
                Path.Combine("Pal", "Binaries", "Win64", "ue4ss", "Mods", "WorldBossAuraSystem")
            };
            string[] legacyAudioFiles =
            {
                "base_the_first_town.mp3",
                "boss_luminous_sword.mp3",
                "boss_theme_opm.mp3",
                "dungeon_weird_place.mp3",
                "night_theme.mp3",
                "PalBossJukebox.deps.json",
                "PalBossJukebox.dll",
                "PalBossJukebox.exe",
                "PalBossJukebox.runtimeconfig.json",
                "region_aincrad.mp3",
                "region_desert.mp3",
                "region_snow.mp3",
                "region_volcano.mp3",
                "rust_headshot.wav",
                "title_perfect_time.mp3",
                "victory_fanfare.mp3"
            };

            int deletedCount = 0;
            foreach (string legacyRoot in legacyRoots)
            {
                string musicModule = Path.Combine(gameRootPath, legacyRoot, "Scripts", "boss_music.lua");
                deletedCount += TryDeleteRetiredFile(musicModule);

                string audioDirectory = Path.Combine(gameRootPath, legacyRoot, "audio");
                foreach (string fileName in legacyAudioFiles)
                {
                    deletedCount += TryDeleteRetiredFile(Path.Combine(audioDirectory, fileName));
                }

                try
                {
                    if (Directory.Exists(audioDirectory) &&
                        !Directory.EnumerateFileSystemEntries(audioDirectory).Any())
                    {
                        Directory.Delete(audioDirectory);
                    }
                }
                catch
                {
                    // Preserve unknown or locked files in the retired directory.
                }
            }

            string[] adaptiveRoots =
            {
                Path.Combine("Pal", "Binaries", "Win64", "Mods", "AdaptiveBGM"),
                Path.Combine("Pal", "Binaries", "Win64", "ue4ss", "Mods", "AdaptiveBGM")
            };
            foreach (string root in adaptiveRoots)
            {
                deletedCount += TryDeleteRetiredFile(Path.Combine(gameRootPath, root, "dlls", "main.dll"));
                deletedCount += TryDeleteRetiredFile(Path.Combine(gameRootPath, root, "enabled.txt"));

                string musicDirectory = Path.Combine(gameRootPath, root, "music");
                foreach (string fileName in legacyAudioFiles)
                {
                    deletedCount += TryDeleteRetiredFile(Path.Combine(musicDirectory, fileName));
                }

                try
                {
                    if (Directory.Exists(musicDirectory) &&
                        !Directory.EnumerateFileSystemEntries(musicDirectory).Any())
                    {
                        Directory.Delete(musicDirectory);
                    }
                    string dllDir = Path.Combine(gameRootPath, root, "dlls");
                    if (Directory.Exists(dllDir) &&
                        !Directory.EnumerateFileSystemEntries(dllDir).Any())
                    {
                        Directory.Delete(dllDir);
                    }
                }
                catch
                {
                    // Preserve unknown or locked files in the retired directory.
                }
            }

            return deletedCount;
        }

        private static int TryDeleteRetiredFile(string path)
        {
            try
            {
                if (!File.Exists(path))
                    return 0;

                File.Delete(path);
                return 1;
            }
            catch
            {
                return 0;
            }
        }

        public void Dispose()
        {
            if (!_disposed)
            {
                _httpClient.Dispose();
                _disposed = true;
            }
            GC.SuppressFinalize(this);
        }
    }
}
