using System;
using System.IO;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using PalLauncher.Models;
using PalLauncher.Services;
using PalLauncher.Services.Interfaces;
using Xunit;

namespace PalLauncher.Tests
{
    [Collection("DaemonTests")]
    public class ComprehensiveDiagnosticTests
    {
        private readonly LogService _logService = new();

        [Fact]
        public void Diagnostic_ValidateModpackStructureAndIntegrity()
        {
            string root = @"C:\PalOddessey\Modpack\Pal";
            Assert.True(Directory.Exists(root), "Modpack/Pal root directory must exist");

            string ue4ssMods = Path.Combine(root, @"Binaries\Win64\ue4ss\Mods");
            Assert.True(Directory.Exists(ue4ssMods), "UE4SS Mods directory must exist");

            string modsTxt = Path.Combine(ue4ssMods, "mods.txt");
            Assert.True(File.Exists(modsTxt), "mods.txt must exist");

            string modsContent = File.ReadAllText(modsTxt);
            Assert.Contains("StuckPalRescuer : 1", modsContent);
            Assert.Contains("QuickDeposit : 1", modsContent);
            Assert.Contains("PalClearVision : 1", modsContent);
            Assert.Contains("DarnMenu : 1", modsContent);
            Assert.Contains("WeaponProficiency : 1", modsContent);
            Assert.Contains("PalOdysseyOptimizer : 1", modsContent);

            // Validate Shared DarnMenu Schemas
            string sharedDir = Path.Combine(ue4ssMods, "shared");
            Assert.True(Directory.Exists(sharedDir), "shared directory must exist");
            Assert.True(File.Exists(Path.Combine(sharedDir, "DarnMenu_schema_index.lua")), "DarnMenu_schema_index.lua must exist");
            Assert.True(File.Exists(Path.Combine(sharedDir, "DarnMenu_schema_StuckPalRescuer.lua")), "StuckPalRescuer schema must exist");
            Assert.True(File.Exists(Path.Combine(sharedDir, "DarnMenu_schema_PalClearVision.lua")), "PalClearVision schema must exist");
            Assert.True(File.Exists(Path.Combine(sharedDir, "DarnMenu_schema_QuickDeposit.lua")), "QuickDeposit schema must exist");
            Assert.True(File.Exists(Path.Combine(sharedDir, "DarnMenu_schema_PalworldTuner.lua")), "PalworldTuner schema must exist");
            Assert.True(File.Exists(Path.Combine(sharedDir, "DarnMenu_schema_WeaponProficiency.lua")), "WeaponProficiency schema must exist");
            Assert.True(File.Exists(Path.Combine(sharedDir, "DarnMenu_schema_PalOdysseyOptimizer.lua")), "PalOdysseyOptimizer schema must exist");
        }

        [Fact]
        public async Task Diagnostic_ContinuousMultiMinuteServiceStressAndHealthCheck()
        {
            var configService = new ConfigService(_logService);
            var pathDetector = new GamePathDetector(_logService);
            var launchService = new LaunchService(_logService);
            var updateService = new UpdateService(_logService);
            var specService = new SystemSpecService(_logService);
            var rpcService = new DiscordRpcService(_logService);

            // 1. Validate Config Lifecycle
            var config = configService.Config;
            Assert.NotNull(config);
            Assert.Equal("palodyssey.duckdns.org", config.ServerIp);
            Assert.True(config.ServerPort == 57294 || config.ServerPort == 8211);
            Assert.True(config.DiscordApplicationId == "1541335019899977768" || config.DiscordApplicationId == "1540924979095408700");

            // 2. Multi-iteration Stress loop simulating continuous operations
            int iterations = 100;
            for (int i = 0; i < iterations; i++)
            {
                // Simulated Discord Presence updates
                await rpcService.UpdatePresenceAsync($"Iteration {i}", "Stress Testing", isPlaying: i % 2 == 0);

                // Path detection query
                var pathInfo = pathDetector.DetectPalworldInstallation();
                Assert.NotNull(pathInfo);

                // Hardware spec calculation
                var profile = await specService.DetectSystemSpecsAsync();
                Assert.NotNull(profile);
                Assert.False(string.IsNullOrEmpty(profile.PerformanceTier));

                // Launch arguments computation
                string args = launchService.BuildCommandLineArguments(config);
                Assert.NotNull(args);

                // Config read/write cycling
                await configService.SaveConfigAsync();
            }

            await rpcService.ClearPresenceAsync();
        }

        [Fact]
        public async Task Diagnostic_RemoteDaemonAndClientLiveboardStressTest()
        {
            int testPort = 18235 + Random.Shared.Next(10, 500);
            var launchService = new LaunchService(_logService);
            var daemon = new RemoteServerDaemon(_logService, launchService);
            var client = new RemoteClientService(_logService);

            bool started = await daemon.StartDaemonAsync(testPort, "StressTestKey2026", () => Task.FromResult(true), () => Task.FromResult(true));
            Assert.True(started);
            await Task.Delay(150);

            try
            {
                // Run 25 consecutive rapid liveboard requests
                for (int i = 0; i < 25; i++)
                {
                    var liveboard = await client.FetchLiveboardAsync("127.0.0.1", testPort, 3000);
                    Assert.NotNull(liveboard);
                    Assert.True(liveboard.IsOnline);
                    Assert.True(liveboard.ServerName.StartsWith("Pal"));
                    Assert.True(liveboard.ServerAddress.StartsWith("palodyssey.duckdns.org:"));
                }
            }
            finally
            {
                await daemon.StopDaemonAsync();
            }
        }

        [Fact]
        public async Task PalSaveService_ApplyServerStabilityAndNetworkOptimizations_TunesIniFiles()
        {
            string tempDir = Path.Combine(Path.GetTempPath(), "PalServerTest_" + Guid.NewGuid());
            string configDir = Path.Combine(tempDir, "Pal", "Saved", "Config", "WindowsServer");
            Directory.CreateDirectory(configDir);

            try
            {
                string settingsIni = Path.Combine(configDir, "PalWorldSettings.ini");
                await File.WriteAllTextAsync(settingsIni, "[/Script/Pal.PalGameWorldSettings]\nOptionSettings=(AutoSaveSpan=30.000000,BaseCampMaxNumInGuild=4)");

                var saveService = new PalSaveService(_logService);
                bool applied = await saveService.ApplyServerStabilityAndNetworkOptimizationsAsync(tempDir);

                Assert.True(applied);

                string updatedSettings = await File.ReadAllTextAsync(settingsIni);
                Assert.Contains("AutoSaveSpan=300.000000", updatedSettings);

                string engineIni = Path.Combine(configDir, "Engine.ini");
                Assert.True(File.Exists(engineIni));
                string engineContent = await File.ReadAllTextAsync(engineIni);
                Assert.Contains("ConnectionTimeout=30.0", engineContent);
                Assert.Contains("MaxClientRate=100000", engineContent);
            }
            finally
            {
                if (Directory.Exists(tempDir))
                {
                    try { Directory.Delete(tempDir, recursive: true); } catch { }
                }
            }
        }

        [Fact]
        public async Task PalSaveService_PruneExcessBackups_CleansOldBackups()
        {
            string tempDir = Path.Combine(Path.GetTempPath(), "PalBackupTest_" + Guid.NewGuid());
            string worldBackupDir = Path.Combine(tempDir, "backup", "world");
            Directory.CreateDirectory(worldBackupDir);

            try
            {
                // Create 10 dummy backup folders
                for (int i = 0; i < 10; i++)
                {
                    string subDir = Path.Combine(worldBackupDir, $"snap_{i:D2}");
                    Directory.CreateDirectory(subDir);
                    await File.WriteAllTextAsync(Path.Combine(subDir, "world.sav"), "dummy save data");
                    Directory.SetCreationTimeUtc(subDir, DateTime.UtcNow.AddMinutes(i - 20));
                }

                var saveService = new PalSaveService(_logService, tempDir);
                int pruned = await saveService.PruneExcessBackupsAsync(maxBackupsToKeep: 4);

                Assert.Equal(6, pruned);
                var remaining = Directory.GetDirectories(worldBackupDir);
                Assert.Equal(4, remaining.Length);
            }
            finally
            {
                if (Directory.Exists(tempDir))
                {
                    try { Directory.Delete(tempDir, recursive: true); } catch { }
                }
            }
        }
        [Fact]
        public async Task Diagnostic_InspectDecompressedPlayerSaveFileProperties()
        {
            var saveService = new PalSaveService(_logService);
            string playerSave = @"C:\SteamLibrary\steamapps\common\PalServer\Pal\Saved\SaveGames\0\CAF1FFD4723E4AA79BEC247C36B01C64\Players\9EDC20A9000000000000000000000000.sav";
            if (File.Exists(playerSave))
            {
                var profile = await saveService.ReadPlayerProfileAsync("9EDC20A9000000000000000000000000");
                Assert.NotNull(profile);
                Assert.True(profile.Level > 0, $"Expected Level > 0 but was {profile.Level}");
                Assert.True(profile.TechnologyPoints > 0, $"Expected TechnologyPoints > 0 but was {profile.TechnologyPoints}");
            }
        }
    }
}
