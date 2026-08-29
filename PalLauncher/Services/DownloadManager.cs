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

                if (string.IsNullOrWhiteSpace(modItem.DownloadUrl))
                {
                    throw new InvalidOperationException($"No download URL provided for '{modItem.RelativePath}'.");
                }

                try
                {
                    using var request = new HttpRequestMessage(HttpMethod.Get, modItem.DownloadUrl);
                    request.Headers.CacheControl = new System.Net.Http.Headers.CacheControlHeaderValue
                    {
                        NoCache = true,
                        NoStore = true
                    };

                    using var response = await _httpClient.SendAsync(
                        request,
                        HttpCompletionOption.ResponseHeadersRead,
                        token);

                    response.EnsureSuccessStatusCode();

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
