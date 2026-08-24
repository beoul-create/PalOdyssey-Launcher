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
            Assert.Equal(8211, config.ServerPort);
            Assert.Equal("1540924979095408700", config.DiscordApplicationId);

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
                    Assert.Equal("PalOdyssey Realm", liveboard.ServerName);
                    Assert.Equal("palodyssey.duckdns.org:8211", liveboard.ServerAddress);
                }
            }
            finally
            {
                await daemon.StopDaemonAsync();
            }
        }
    }
}
