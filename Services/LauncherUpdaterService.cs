using System;
using System.Diagnostics;
using System.IO;
using System.Net.Http;
using System.Reflection;
using System.Security.Cryptography;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using PalLauncher.Models;

namespace PalLauncher.Services
{
    public class LauncherUpdaterService
    {
        private readonly HttpClient _httpClient;
        private readonly HashService _hashService;

        public static readonly Version CurrentVersion = new(2, 0, 1);
        public const string GitHubReleasesApiUrl = "https://api.github.com/repos/beoul-create/PalOdyssey-Launcher/releases/latest";

        public LauncherUpdaterService(HashService? hashService = null)
        {
            _hashService = hashService ?? new HashService();
            _httpClient = new HttpClient
            {
                Timeout = TimeSpan.FromSeconds(30)
            };
            _httpClient.DefaultRequestHeaders.UserAgent.ParseAdd("PalOdyssey-Launcher-Updater/2.0");
        }

        public async Task<(bool hasUpdate, LauncherReleaseInfo? releaseInfo)> CheckForLauncherUpdateAsync(
            ManifestModel? manifest,
            CancellationToken cancellationToken = default)
        {
            // 1. Check Manifest for Launcher metadata
            if (manifest?.Launcher != null && !string.IsNullOrWhiteSpace(manifest.Launcher.Version))
            {
                if (TryParseVersion(manifest.Launcher.Version, out var remoteVer) && remoteVer > CurrentVersion)
                {
                    return (true, manifest.Launcher);
                }
            }

            // 2. Fallback: Query GitHub Releases API directly
            try
            {
                using var request = new HttpRequestMessage(HttpMethod.Get, GitHubReleasesApiUrl);
                using var response = await _httpClient.SendAsync(request, cancellationToken);
                if (response.IsSuccessStatusCode)
                {
                    string json = await response.Content.ReadAsStringAsync(cancellationToken);
                    using var doc = JsonDocument.Parse(json);
                    var root = doc.RootElement;
                    if (root.TryGetProperty("tag_name", out var tagProp))
                    {
                        string tag = tagProp.GetString() ?? "";
                        if (TryParseVersion(tag, out var ghVer) && ghVer > CurrentVersion)
                        {
                            string downloadUrl = "";
                            if (root.TryGetProperty("assets", out var assets) && assets.ValueKind == JsonValueKind.Array)
                            {
                                foreach (var asset in assets.EnumerateArray())
                                {
                                    if (asset.TryGetProperty("name", out var nameProp) && 
                                        nameProp.GetString()?.Equals("PalLauncher.exe", StringComparison.OrdinalIgnoreCase) == true)
                                    {
                                        downloadUrl = asset.GetProperty("browser_download_url").GetString() ?? "";
                                        break;
                                    }
                                }
                            }

                            if (string.IsNullOrWhiteSpace(downloadUrl))
                            {
                                downloadUrl = $"https://github.com/beoul-create/PalOdyssey-Launcher/releases/download/{tag}/PalLauncher.exe";
                            }

                            string body = root.TryGetProperty("body", out var bodyProp) ? bodyProp.GetString() ?? "" : "";

                            return (true, new LauncherReleaseInfo
                            {
                                Version = tag.TrimStart('v', 'V'),
                                DownloadUrl = downloadUrl,
                                ReleaseNotes = body
                            });
                        }
                    }
                }
            }
            catch
            {
                // Non-fatal if GitHub is unreachable
            }

            return (false, null);
        }

        public async Task DownloadAndApplyUpdateAsync(
            LauncherReleaseInfo releaseInfo,
            IProgress<DownloadProgressReport>? progressReporter = null,
            CancellationToken cancellationToken = default)
        {
            if (string.IsNullOrWhiteSpace(releaseInfo.DownloadUrl))
                throw new ArgumentException("Download URL cannot be empty.", nameof(releaseInfo));

            string baseDir = AppDomain.CurrentDomain.BaseDirectory;
            string currentExePath = Environment.ProcessPath ?? Path.Combine(baseDir, "PalLauncher.exe");
            string updateTempPath = Path.Combine(baseDir, "PalLauncher.update");
            string updaterScriptPath = Path.Combine(baseDir, "apply_launcher_update.cmd");

            // 1. Download updated binary
            using (var response = await _httpClient.GetAsync(releaseInfo.DownloadUrl, HttpCompletionOption.ResponseHeadersRead, cancellationToken))
            {
                response.EnsureSuccessStatusCode();
                long totalBytes = response.Content.Headers.ContentLength ?? -1L;

                using var contentStream = await response.Content.ReadAsStreamAsync(cancellationToken);
                using var fileStream = new FileStream(updateTempPath, FileMode.Create, FileAccess.Write, FileShare.None);

                var buffer = new byte[81920];
                long totalRead = 0;
                int read;
                var stopwatch = Stopwatch.StartNew();

                while ((read = await contentStream.ReadAsync(buffer, 0, buffer.Length, cancellationToken)) > 0)
                {
                    await fileStream.WriteAsync(buffer, 0, read, cancellationToken);
                    totalRead += read;

                    if (totalBytes > 0 && progressReporter != null)
                    {
                        double percentage = (double)totalRead / totalBytes * 100.0;
                        double speedMb = (totalRead / 1048576.0) / Math.Max(0.001, stopwatch.Elapsed.TotalSeconds);
                        progressReporter.Report(new DownloadProgressReport
                        {
                            Percentage = percentage,
                            BytesDownloaded = totalRead,
                            TotalBytesToDownload = totalBytes,
                            SpeedMbPerSec = speedMb,
                            CurrentFileName = "PalLauncher.exe",
                            CurrentFileIndex = 1,
                            TotalFileCount = 1
                        });
                    }
                }
            }

            // 2. Verify Hash if provided
            if (!string.IsNullOrWhiteSpace(releaseInfo.Sha256))
            {
                string downloadedHash = await _hashService.ComputeSha256Async(updateTempPath, cancellationToken);
                if (!downloadedHash.Equals(releaseInfo.Sha256, StringComparison.OrdinalIgnoreCase))
                {
                    if (File.Exists(updateTempPath)) File.Delete(updateTempPath);
                    throw new InvalidOperationException("Downloaded launcher update failed SHA-256 integrity verification.");
                }
            }

            // 3. Generate Detached Batch Updater Script
            string batchScript = $@"@echo off
setlocal enabledelayedexpansion
title Updating PalOdyssey Launcher...
timeout /t 1 /nobreak > nul

set TARGET=""{currentExePath}""
set UPDATE=""{updateTempPath}""

:retry
if exist !UPDATE! (
    copy /y !UPDATE! !TARGET! > nul
    if errorlevel 1 (
        timeout /t 1 /nobreak > nul
        goto retry
    )
    del !UPDATE! > nul
)

start """" !TARGET!
del ""%~f0"" > nul
exit
";

            await File.WriteAllTextAsync(updaterScriptPath, batchScript, cancellationToken);

            // 4. Launch Detached Updater and Terminate Current Process
            var psi = new ProcessStartInfo
            {
                FileName = updaterScriptPath,
                UseShellExecute = true,
                CreateNoWindow = true,
                WindowStyle = ProcessWindowStyle.Hidden
            };

            Process.Start(psi);

            // 5. Exit application cleanly
            Application.Current?.Dispatcher?.Invoke(() =>
            {
                Application.Current.Shutdown();
            });

            Environment.Exit(0);
        }

        private static bool TryParseVersion(string input, out Version version)
        {
            input = input.Trim().TrimStart('v', 'V');
            // Support 2 or 3 segment version numbers (e.g. 2.0 or 2.0.2)
            string[] parts = input.Split('.');
            if (parts.Length == 1) input += ".0.0";
            else if (parts.Length == 2) input += ".0";
            return Version.TryParse(input, out version!);
        }
    }
}