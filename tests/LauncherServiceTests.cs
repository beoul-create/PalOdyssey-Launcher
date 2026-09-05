using System;
using System.Collections.Generic;
using System.IO;
using System.Net.Http;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using PalLauncher.Models;
using PalLauncher.Services;
using Xunit;

namespace PalLauncher.Tests
{
    public class LauncherServiceTests
    {
        [Fact]
        public async Task HashService_ComputesCorrectSha256()
        {
            var hashService = new HashService();
            string tempFile = Path.GetTempFileName();

            try
            {
                byte[] data = Encoding.UTF8.GetBytes("Hello Palworld!");
                await File.WriteAllBytesAsync(tempFile, data);

                string hash = await hashService.ComputeSha256Async(tempFile);
                Assert.False(string.IsNullOrWhiteSpace(hash));
                Assert.Equal(64, hash.Length);
            }
            finally
            {
                if (File.Exists(tempFile)) File.Delete(tempFile);
            }
        }

        [Fact]
        public async Task HashService_VerifyFileWithCache_UsesFastPath()
        {
            var hashService = new HashService();
            string tempFile = Path.GetTempFileName();
            var cache = new LocalCache();

            try
            {
                byte[] data = Encoding.UTF8.GetBytes("Cached mod content test");
                await File.WriteAllBytesAsync(tempFile, data);

                string hash = await hashService.ComputeSha256Async(tempFile);
                var fi = new FileInfo(tempFile);

                // Populate cache
                cache.Entries["test_mod.pak"] = new CacheFileEntry
                {
                    RelativePath = "test_mod.pak",
                    ResolvedFullPath = tempFile,
                    LastWriteTimeUtc = fi.LastWriteTimeUtc,
                    FileSize = fi.Length,
                    Sha256 = hash
                };

                // Fast path verification
                var (isValid, verifiedHash) = await hashService.VerifyFileWithCacheAsync(
                    tempFile,
                    "test_mod.pak",
                    fi.Length,
                    hash,
                    cache);

                Assert.True(isValid);
                Assert.Equal(hash, verifiedHash);
            }
            finally
            {
                if (File.Exists(tempFile)) File.Delete(tempFile);
            }
        }

        [Fact]
        public async Task HashService_DetectsHashMismatch()
        {
            var hashService = new HashService();
            string tempFile = Path.GetTempFileName();
            var cache = new LocalCache();

            try
            {
                byte[] data = Encoding.UTF8.GetBytes("Mod version 1");
                await File.WriteAllBytesAsync(tempFile, data);

                var fi = new FileInfo(tempFile);
                string expectedDifferentHash = "0000000000000000000000000000000000000000000000000000000000000000";

                var (isValid, _) = await hashService.VerifyFileWithCacheAsync(
                    tempFile,
                    "test_mod.pak",
                    fi.Length,
                    expectedDifferentHash,
                    cache);

                Assert.False(isValid);
            }
            finally
            {
                if (File.Exists(tempFile)) File.Delete(tempFile);
            }
        }

        [Fact]
        public async Task HashService_DoesNotReuseCacheAcrossGameDirectories()
        {
            var hashService = new HashService();
            string firstFile = Path.GetTempFileName();
            string secondFile = Path.GetTempFileName();

            try
            {
                await File.WriteAllTextAsync(firstFile, "first-content");
                await File.WriteAllTextAsync(secondFile, "other-content");
                DateTime sharedTimestamp = DateTime.UtcNow.AddMinutes(-1);
                File.SetLastWriteTimeUtc(firstFile, sharedTimestamp);
                File.SetLastWriteTimeUtc(secondFile, sharedTimestamp);

                string firstHash = await hashService.ComputeSha256Async(firstFile);
                var firstInfo = new FileInfo(firstFile);
                var cache = new LocalCache();
                cache.Entries["same-relative-path.pak"] = new CacheFileEntry
                {
                    RelativePath = "same-relative-path.pak",
                    ResolvedFullPath = firstFile,
                    LastWriteTimeUtc = firstInfo.LastWriteTimeUtc,
                    FileSize = firstInfo.Length,
                    Sha256 = firstHash
                };

                var (isValid, computedHash) = await hashService.VerifyFileWithCacheAsync(
                    secondFile,
                    "same-relative-path.pak",
                    firstInfo.Length,
                    firstHash,
                    cache);

                Assert.False(isValid);
                Assert.NotEqual(firstHash, computedHash);
            }
            finally
            {
                File.Delete(firstFile);
                File.Delete(secondFile);
            }
        }

        [Fact]
        public void LauncherConfig_DefaultServerArguments_AvoidLegacyThreadOverrides()
        {
            Assert.Equal("-port=8211", new LauncherConfig().ServerLaunchArguments);
        }

        [Fact]
        public void ManifestModel_ResolvesCorrectTargetPaths()
        {
            string fakeGameRoot = @"C:\Games\Palworld";

            // Full relative path format generated by Generate-Manifest.ps1 / generate_manifest.py
            var generatorItem = new ModFileItem
            {
                RelativePath = "Pal/Content/Paks/~mods/PalworldAuras_P.pak",
                Hash = "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855",
                Size = 14582912
            };
            string fullPath = generatorItem.GetResolvedPath(fakeGameRoot);
            Assert.Equal(Path.Combine(fakeGameRoot, "Pal", "Content", "Paks", "~mods", "PalworldAuras_P.pak"), fullPath);
            Assert.Equal("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", generatorItem.Sha256);
            Assert.Equal(14582912, generatorItem.FileSize);

            // Sub-relative path format
            var pakItem = new ModFileItem
            {
                RelativePath = "PalOdyssey_Weapons.pak",
                TargetCategory = ModTargetCategory.PakMod
            };
            string pakPath = pakItem.GetResolvedPath(fakeGameRoot);
            Assert.Equal(Path.Combine(fakeGameRoot, "Pal", "Content", "Paks", "~mods", "PalOdyssey_Weapons.pak"), pakPath);

            var ue4ssItem = new ModFileItem
            {
                RelativePath = "Pal/Binaries/Win64/ue4ss/Mods/WorldBossAuraSystem/main.lua",
                Hash = "4e07408562bedb8b60ce05c1decfe3ad16b72230967de01f640b7e4729b49fce",
                Size = 4912
            };
            string ue4ssPath = ue4ssItem.GetResolvedPath(fakeGameRoot);
            Assert.Equal(Path.Combine(fakeGameRoot, "Pal", "Binaries", "Win64", "ue4ss", "Mods", "WorldBossAuraSystem", "main.lua"), ue4ssPath);
        }

        [Fact]
        public void ManifestModel_DeserializesGeneratedManifestJson()
        {
            string sampleJson = @"
{
  ""Version"": ""2026.08.28.172400"",
  ""GeneratedAt"": ""2026-08-28T22:24:00Z"",
  ""TotalFiles"": 3,
  ""Files"": [
    {
      ""RelativePath"": ""Pal/Content/Paks/~mods/PalworldAuras_P.pak"",
      ""Hash"": ""e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855"",
      ""Size"": 14582912,
      ""DownloadUrl"": ""https://raw.githubusercontent.com/your-repo/palworld-modpack/main/files/Pal/Content/Paks/~mods/PalworldAuras_P.pak""
    },
    {
      ""RelativePath"": ""Pal/Content/Paks/~mods/ForceOfPalpagos.pak"",
      ""Hash"": ""ca978112ca1bbdcafac231b39a23dc4da786eff8147c4e72b9807785afee48bb"",
      ""Size"": 8421054,
      ""DownloadUrl"": ""https://raw.githubusercontent.com/your-repo/palworld-modpack/main/files/Pal/Content/Paks/~mods/ForceOfPalpagos.pak""
    },
    {
      ""RelativePath"": ""Pal/Binaries/Win64/ue4ss/Mods/WorldBossAuraSystem/main.lua"",
      ""Hash"": ""4e07408562bedb8b60ce05c1decfe3ad16b72230967de01f640b7e4729b49fce"",
      ""Size"": 4912,
      ""DownloadUrl"": ""https://raw.githubusercontent.com/your-repo/palworld-modpack/main/files/Pal/Binaries/Win64/ue4ss/Mods/WorldBossAuraSystem/main.lua""
    }
  ]
}";
            var options = new JsonSerializerOptions { PropertyNameCaseInsensitive = true };
            var manifest = JsonSerializer.Deserialize<ManifestModel>(sampleJson, options);

            Assert.NotNull(manifest);
            Assert.Equal("2026.08.28.172400", manifest.ManifestVersion);
            Assert.Equal(3, manifest.Files.Count);

            var first = manifest.Files[0];
            Assert.Equal("Pal/Content/Paks/~mods/PalworldAuras_P.pak", first.RelativePath);
            Assert.Equal("e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855", first.Sha256);
            Assert.Equal(14582912, first.FileSize);
        }

        [Fact]
        public void DownloadManager_CleansOrphanPakFiles()
        {
            string testDir = Path.Combine(Path.GetTempPath(), "PalTestGame_" + Guid.NewGuid());
            string modsDir = Path.Combine(testDir, "Pal", "Content", "Paks", "~mods");
            Directory.CreateDirectory(modsDir);

            try
            {
                string validPak = Path.Combine(modsDir, "ValidMod.pak");
                string orphanPak = Path.Combine(modsDir, "OldOrphanMod.pak");

                File.WriteAllText(validPak, "valid");
                File.WriteAllText(orphanPak, "orphan");

                var validSet = new HashSet<string>(StringComparer.OrdinalIgnoreCase) { "ValidMod.pak" };

                using var downloadMgr = new DownloadManager();
                int deleted = downloadMgr.CleanupOrphanPakFiles(testDir, validSet);

                Assert.Equal(1, deleted);
                Assert.True(File.Exists(validPak));
                Assert.False(File.Exists(orphanPak));
            }
            finally
            {
                if (Directory.Exists(testDir))
                {
                    Directory.Delete(testDir, true);
                }
            }
        }

        [Fact]
        public void LauncherConfig_SavesAndLoadsCorrectly()
        {
            string tempConfigPath = Path.Combine(Path.GetTempPath(), "launcher_config_test_" + Guid.NewGuid() + ".json");

            try
            {
                var config = new LauncherConfig
                {
                    GamePath = @"D:\Games\Steam\steamapps\common\Palworld",
                    ServerInstallPath = @"D:\Games\Steam\steamapps\common\PalServer",
                    ServerLaunchArguments = "-useperfthreads -NoAsyncLoadingThread -port=8211",
                    AutoStartServerWithClient = true,
                    RemoteManifestUrl = "https://raw.githubusercontent.com/beoul-create/PalOdessey-Modpack/main/manifest.json",
                    ServerIp = "192.168.1.100",
                    ServerPort = 7777,
                    SoundEnabled = false,
                    DiscordRpcEnabled = true,
                    LaunchViaSteamProtocol = true
                };

                config.Save(tempConfigPath);
                Assert.True(File.Exists(tempConfigPath));

                var loaded = LauncherConfig.Load(tempConfigPath);
                Assert.Equal(config.GamePath, loaded.GamePath);
                Assert.Equal(config.ServerInstallPath, loaded.ServerInstallPath);
                Assert.Equal(config.ServerLaunchArguments, loaded.ServerLaunchArguments);
                Assert.True(loaded.AutoStartServerWithClient);
                Assert.Equal(config.RemoteManifestUrl, loaded.RemoteManifestUrl);
                Assert.Equal(config.ServerIp, loaded.ServerIp);
                Assert.Equal(config.ServerPort, loaded.ServerPort);
                Assert.False(loaded.SoundEnabled);
                Assert.True(loaded.DiscordRpcEnabled);
                Assert.True(loaded.LaunchViaSteamProtocol);
            }
            finally
            {
                if (File.Exists(tempConfigPath)) File.Delete(tempConfigPath);
            }
        }

        [Fact]
        public void ManifestService_DefaultFallback_IsValid()
        {
            var manifest = ManifestService.GetDefaultFallbackManifest();
            Assert.NotNull(manifest);
            Assert.NotEmpty(manifest.ServerName);
            Assert.NotEmpty(manifest.Files);
            Assert.NotEmpty(manifest.News);
        }

        [Fact]
        public void GameProcessService_Validation_HandlesInvalidPathsGracefully()
        {
            var service = new GameProcessService();
            Assert.False(service.IsValidGameDirectory(null));
            Assert.False(service.IsValidGameDirectory(""));
            Assert.False(service.IsValidGameDirectory(@"C:\NonExistentDirectory_12345"));

            Assert.False(service.IsValidServerDirectory(null));
            Assert.False(service.IsValidServerDirectory(""));
            Assert.False(service.IsValidServerDirectory(@"C:\NonExistentServer_12345"));
        }

        [Fact]
        public void GameProcessService_DetectServerPath_WithValidExplicitPath()
        {
            var service = new GameProcessService();
            string tempDir = Path.Combine(Path.GetTempPath(), "palserver_test_" + Guid.NewGuid());
            Directory.CreateDirectory(tempDir);

            try
            {
                string fakeExe = Path.Combine(tempDir, "PalServer.exe");
                File.WriteAllText(fakeExe, "fake binary");

                string? detected = service.DetectServerPath(tempDir);
                Assert.Equal(tempDir, detected);
                Assert.True(service.IsValidServerDirectory(tempDir));
            }
            finally
            {
                if (Directory.Exists(tempDir)) Directory.Delete(tempDir, true);
            }
        }

        [Fact]
        public async Task ServerQueryService_QueryServerAsync_ReturnsValidStatus()
        {
            using var queryService = new ServerQueryService();
            var status = await queryService.QueryServerAsync("127.0.0.1", 8211);

            Assert.NotNull(status);
            Assert.NotNull(status.StatusText);
            Assert.NotNull(status.ColorHex);
            Assert.NotNull(status.PingText);
            Assert.NotNull(status.PlayersText);
        }

        [Fact]
        public void LauncherConfig_AtomicSaveAndLoad_PreservesAllFields()
        {
            string tempFile = Path.Combine(Path.GetTempPath(), "test_config_" + Guid.NewGuid() + ".json");
            try
            {
                var config = new LauncherConfig
                {
                    GamePath = @"C:\TestGames\Palworld",
                    ServerInstallPath = @"C:\TestServer\PalServer",
                    ServerLaunchArguments = "-port=8211 -NoAsyncLoadingThread",
                    SoundEnabled = false,
                    DiscordRpcEnabled = true,
                    AutoStartServerWithClient = true,
                    RemoteServerApiUrl = "http://192.168.1.100:3001",
                    RemoteAdminKey = "CustomKey123"
                };

                config.Save(tempFile);
                Assert.True(File.Exists(tempFile));

                var loaded = LauncherConfig.Load(tempFile);
                Assert.Equal(config.GamePath, loaded.GamePath);
                Assert.Equal(config.ServerInstallPath, loaded.ServerInstallPath);
                Assert.Equal(config.ServerLaunchArguments, loaded.ServerLaunchArguments);
                Assert.Equal(config.SoundEnabled, loaded.SoundEnabled);
                Assert.Equal(config.DiscordRpcEnabled, loaded.DiscordRpcEnabled);
                Assert.Equal(config.AutoStartServerWithClient, loaded.AutoStartServerWithClient);
                Assert.Equal("http://192.168.1.100:3001", loaded.RemoteServerApiUrl);
                Assert.Equal("CustomKey123", loaded.RemoteAdminKey);
            }
            finally
            {
                if (File.Exists(tempFile)) File.Delete(tempFile);
            }
        }

        [Fact]
        public async Task RemoteServerService_GetRemoteStatusAsync_ParsesJsonStatus()
        {
            var handler = new MockHttpMessageHandler(req =>
            {
                Assert.Equal(HttpMethod.Get, req.Method);
                Assert.EndsWith("/api/server/status", req.RequestUri!.AbsolutePath);
                return new HttpResponseMessage(System.Net.HttpStatusCode.OK)
                {
                    Content = new StringContent("{\"success\":true,\"isProcessRunning\":true,\"serverOnline\":true,\"playerCount\":5,\"maxPlayers\":32}")
                };
            });

            var service = new RemoteServerService(new HttpClient(handler));
            var status = await service.GetRemoteStatusAsync("http://127.0.0.1:3001");

            Assert.NotNull(status);
            Assert.True(status.Success);
            Assert.True(status.IsProcessRunning);
            Assert.True(status.ServerOnline);
            Assert.Equal(5, status.PlayerCount);
            Assert.Equal(32, status.MaxPlayers);
        }

        [Fact]
        public void DownloadManager_CleanupRetiredMusicFiles_DeletesOnlyKnownLegacyFiles()
        {
            string tempDir = Path.Combine(Path.GetTempPath(), "pal-music-cleanup-" + Guid.NewGuid());
            string legacyRoot = Path.Combine(tempDir, "Pal", "Binaries", "Win64", "ue4ss", "Mods", "WorldBossAuraSystem");
            string audioDir = Path.Combine(legacyRoot, "audio");
            string scriptsDir = Path.Combine(legacyRoot, "Scripts");

            try
            {
                Directory.CreateDirectory(audioDir);
                Directory.CreateDirectory(scriptsDir);
                string retiredTrack = Path.Combine(audioDir, "night_theme.mp3");
                string retainedTrack = Path.Combine(audioDir, "user_track.mp3");
                string retiredModule = Path.Combine(scriptsDir, "boss_music.lua");
                File.WriteAllText(retiredTrack, "legacy");
                File.WriteAllText(retainedTrack, "user-owned");
                File.WriteAllText(retiredModule, "legacy");

                using var manager = new DownloadManager();
                int deleted = manager.CleanupRetiredMusicFiles(tempDir);

                Assert.Equal(2, deleted);
                Assert.False(File.Exists(retiredTrack));
                Assert.False(File.Exists(retiredModule));
                Assert.True(File.Exists(retainedTrack));
            }
            finally
            {
                if (Directory.Exists(tempDir)) Directory.Delete(tempDir, true);
            }
        }

        [Fact]
        public async Task RemoteServerService_StartRemoteServerAsync_SendsBearerToken()
        {
            string? capturedAuth = null;
            var handler = new MockHttpMessageHandler(req =>
            {
                Assert.Equal(HttpMethod.Post, req.Method);
                Assert.EndsWith("/api/server/start", req.RequestUri!.AbsolutePath);
                capturedAuth = req.Headers.Authorization?.ToString();
                return new HttpResponseMessage(System.Net.HttpStatusCode.OK)
                {
                    Content = new StringContent("{\"success\":true,\"message\":\"Server started.\",\"pid\":1234}")
                };
            });

            var service = new RemoteServerService(new HttpClient(handler));
            bool started = await service.StartRemoteServerAsync("http://127.0.0.1:3001", "MySecretKey");

            Assert.True(started);
            Assert.Equal("Bearer MySecretKey", capturedAuth);
        }

        [Fact]
        public async Task RemoteServerService_StopRemoteServerAsync_SendsBearerToken()
        {
            string? capturedAuth = null;
            var handler = new MockHttpMessageHandler(req =>
            {
                Assert.Equal(HttpMethod.Post, req.Method);
                Assert.EndsWith("/api/server/stop", req.RequestUri!.AbsolutePath);
                capturedAuth = req.Headers.Authorization?.ToString();
                return new HttpResponseMessage(System.Net.HttpStatusCode.OK)
                {
                    Content = new StringContent("{\"success\":true,\"message\":\"Server terminated.\"}")
                };
            });

            var service = new RemoteServerService(new HttpClient(handler));
            bool stopped = await service.StopRemoteServerAsync("http://127.0.0.1:3001", "MySecretKey");

            Assert.True(stopped);
            Assert.Equal("Bearer MySecretKey", capturedAuth);
        }

        [Fact]
        public async Task RemoteServerService_HandlesNetworkErrorsGracefully()
        {
            var handler = new MockHttpMessageHandler(_ => throw new HttpRequestException("Connection refused"));

            var service = new RemoteServerService(new HttpClient(handler));
            var status = await service.GetRemoteStatusAsync("http://unreachable-host:3001");
            Assert.Null(status);

            bool started = await service.StartRemoteServerAsync("http://unreachable-host:3001", "Key");
            Assert.False(started);

            bool stopped = await service.StopRemoteServerAsync("http://unreachable-host:3001", "Key");
            Assert.False(stopped);
        }

        [Fact]
        public void LocalCache_AtomicSaveAndLoad_PreservesEntries()
        {
            string tempFile = Path.Combine(Path.GetTempPath(), "test_cache_" + Guid.NewGuid() + ".json");
            try
            {
                var cache = new LocalCache();
                cache.Entries["Pal/Content/Paks/~mods/test.pak"] = new CacheFileEntry
                {
                    RelativePath = "Pal/Content/Paks/~mods/test.pak",
                    ResolvedFullPath = @"C:\Games\Pal\Content\Paks\~mods\test.pak",
                    FileSize = 1048576,
                    Sha256 = "E3B0C44298FC1C149AFBF4C8996FB92427AE41E4649B934CA495991B7852B855",
                    LastWriteTimeUtc = DateTime.UtcNow
                };

                cache.Save(tempFile);
                Assert.True(File.Exists(tempFile));

                var loaded = LocalCache.Load(tempFile);
                Assert.Single(loaded.Entries);
                Assert.True(loaded.Entries.ContainsKey("Pal/Content/Paks/~mods/test.pak"));
                Assert.Equal(1048576, loaded.Entries["Pal/Content/Paks/~mods/test.pak"].FileSize);
            }
            finally
            {
                if (File.Exists(tempFile)) File.Delete(tempFile);
            }
        }

        private class MockHttpMessageHandler : HttpMessageHandler
        {
            private readonly Func<HttpRequestMessage, HttpResponseMessage> _handler;

            public MockHttpMessageHandler(Func<HttpRequestMessage, HttpResponseMessage> handler)
            {
                _handler = handler;
            }

            protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, System.Threading.CancellationToken cancellationToken)
            {
                return Task.FromResult(_handler(request));
            }
        }
    }
}
