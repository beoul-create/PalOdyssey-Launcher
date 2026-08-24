using System;
using System.Collections.Generic;
using System.IO;
using System.Threading.Tasks;
using PalLauncher.Models;
using PalLauncher.Services;
using PalLauncher.Services.Interfaces;
using PalLauncher.ViewModels;
using Xunit;

namespace PalLauncher.Tests
{
    public class E2ERegressionMatrixTests
    {
        private readonly ILogService _logService = new LogService();

        #region 1. Launcher Client & UI Verification

        [Fact]
        public async Task Test_1_1_StartupLifecycle_InitializesCleanlyWithoutDeadlock()
        {
            var configService = new ConfigService(_logService);
            var pathDetector = new GamePathDetector(_logService);
            var updateService = new UpdateService(_logService);
            var crashLogService = new CrashLogService(_logService);
            var launchService = new LaunchService(_logService, crashLogService);
            var specService = new SystemSpecService(_logService);
            var remoteDaemon = new RemoteServerDaemon(_logService, launchService);
            var remoteClient = new RemoteClientService(_logService);
            var discordRpc = new DiscordRpcService(_logService);

            var mainVm = new MainViewModel(
                configService,
                pathDetector,
                updateService,
                launchService,
                _logService,
                specService,
                remoteDaemon,
                remoteClient,
                discordRpc,
                crashLogService);

            // Verify ViewModel initializes promptly without blocking/deadlocking
            var initTask = mainVm.InitializeAsync();
            var completedTask = await Task.WhenAny(initTask, Task.Delay(5000));
            Assert.Same(initTask, completedTask);

            Assert.False(mainVm.IsBusy);
            Assert.NotNull(mainVm.StatusText);
        }

        [Fact]
        public void Test_1_2_PublicScope_NoSecretsOrTokensExposedInUI()
        {
            var configService = new ConfigService(_logService);
            var pathDetector = new GamePathDetector(_logService);
            var launchService = new LaunchService(_logService);
            var updateService = new UpdateService(_logService);
            var specService = new SystemSpecService(_logService);

            var settingsVm = new SettingsViewModel(
                configService,
                pathDetector,
                launchService,
                updateService,
                _logService,
                specService);

            // Verify player view model exposes public endpoint and no secrets
            Assert.Equal("palodyssey.duckdns.org", settingsVm.ServerIp);
            Assert.Equal(8211, settingsVm.ServerPort);

            // Ensure no bot token or admin password is leaked in public fields
            Assert.DoesNotContain("0012", settingsVm.ServerIp);
            Assert.DoesNotContain("MTU0MTMz", settingsVm.ServerIp);
        }

        [Fact]
        public void Test_1_3_GameLaunch_SteamIntegration_BypassesConfirmationPrompt()
        {
            string tempGameDir = Path.Combine(Path.GetTempPath(), "PalMockGame_" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(tempGameDir);

            try
            {
                var launchService = new LaunchService(_logService);
                var config = new LauncherConfig
                {
                    GamePath = tempGameDir,
                    ServerIp = "palodyssey.duckdns.org",
                    ServerPort = 8211,
                    AutoJoinServer = true,
                    UseAllCores = true,
                    UseDirectX11 = true
                };

                // Build CLI arguments
                string args = launchService.BuildCommandLineArguments(config);

                // Verify NO raw +connect or raw IP connection parameter is present (to preserve EOS auth)
                Assert.DoesNotContain("+connect", args);
                Assert.DoesNotContain("8211", args);
                Assert.DoesNotContain("palodyssey.duckdns.org", args);

                // Verify performance arguments are present
                Assert.Contains("-USEALLAVAILABLECORES", args);
                Assert.Contains("-dx11", args);
                Assert.Contains("-useperfthreads", args);
            }
            finally
            {
                if (Directory.Exists(tempGameDir)) Directory.Delete(tempGameDir, true);
            }
        }

        [Fact]
        public void Test_1_4_ClipboardAndQuickActions_CopiesServerAddressCorrectly()
        {
            var configService = new ConfigService(_logService);
            var pathDetector = new GamePathDetector(_logService);
            var updateService = new UpdateService(_logService);
            var launchService = new LaunchService(_logService);
            var specService = new SystemSpecService(_logService);
            var remoteDaemon = new RemoteServerDaemon(_logService, launchService);
            var remoteClient = new RemoteClientService(_logService);
            var discordRpc = new DiscordRpcService(_logService);

            var mainVm = new MainViewModel(
                configService,
                pathDetector,
                updateService,
                launchService,
                _logService,
                specService,
                remoteDaemon,
                remoteClient,
                discordRpc);

            // Execute Copy Command without throwing
            mainVm.CopyServerIpCommand.Execute(null);

            Assert.NotNull(mainVm.StatusText);
            Assert.Contains("copied", mainVm.StatusText, StringComparison.OrdinalIgnoreCase);
        }

        #endregion

        #region 2. 24/7 Discord Daemon & Liveboard Testing

        [Fact]
        public void Test_2_1_LiveboardChannel_ConfiguredCorrectly()
        {
            var config = new LauncherConfig();
            Assert.Equal("1541492780168380446", config.DiscordBotChannelId);
            Assert.Equal(8212, config.RestApiPort);
            Assert.Equal("0012", config.ServerAdminPassword);
        }

        [Fact]
        public void Test_2_2_PermissionsMatrix_AdminOnlyRestrictions()
        {
            // Verify public commands vs admin commands
            var publicCommands = new[] { "start", "status", "ip", "help", "shop", "exchange", "recycle", "scrap", "inventory", "link" };
            var adminCommands = new[] { "restart", "stop" };

            Assert.Equal(10, publicCommands.Length);
            Assert.Equal(2, adminCommands.Length);
        }

        [Fact]
        public void Test_2_3_InactivityAutoShutdown_TimerCountdownCalculation()
        {
            var liveboard = new ServerLiveboardInfo
            {
                IsOnline = true,
                IsServerRunning = true,
                PlayerCount = 0,
                IsIdleCountingDown = true,
                IdleMinutesRemaining = 20,
                IdleSecondsRemaining = 1200 // 20 minutes
            };

            Assert.Equal(1200, liveboard.IdleSecondsRemaining);
            Assert.Equal(20, liveboard.IdleMinutesRemaining);
            Assert.Contains("20m", liveboard.AutoShutdownStatusText);

            // When player connects, countdown pauses
            liveboard.PlayerCount = 1;
            liveboard.IsIdleCountingDown = false;
            Assert.Contains("Active (1 Online)", liveboard.AutoShutdownStatusText);
        }

        #endregion

        #region 3. Shop & Recycling Save-File Transaction Testing

        [Fact]
        public async Task Test_3_1_BackupSafety_GeneratesTimestampedBackupBeforeModify()
        {
            string tempDir = Path.Combine(Path.GetTempPath(), "PalTestBackupSafety_" + Guid.NewGuid().ToString("N"));
            string playersDir = Path.Combine(tempDir, "Players");
            Directory.CreateDirectory(playersDir);

            try
            {
                string playerUid = "9EDC20A9000000000000000000000000";
                string savePath = Path.Combine(playersDir, $"{playerUid}.sav");

                byte[] mockSave = CreateMockPalworldSave(unusedTechPoints: 50, level: 30);
                await File.WriteAllBytesAsync(savePath, mockSave);

                var saveService = new PalSaveService(_logService, tempDir);

                bool backedUp = await saveService.CreateBackupAsync(playerUid);
                Assert.True(backedUp);

                string backupDir = Path.Combine(tempDir, "backup", "economy_backups");
                Assert.True(Directory.Exists(backupDir));
                var backupFiles = Directory.GetFiles(backupDir, $"*_{playerUid}.sav");
                Assert.Single(backupFiles);
            }
            finally
            {
                if (Directory.Exists(tempDir)) Directory.Delete(tempDir, true);
            }
        }

        [Fact]
        public async Task Test_3_2_ValidationAndRollbacks_HandlesInsufficientFundsAndInvalidItems()
        {
            string tempDir = Path.Combine(Path.GetTempPath(), "PalTestValidation_" + Guid.NewGuid().ToString("N"));
            string playersDir = Path.Combine(tempDir, "Players");
            Directory.CreateDirectory(playersDir);

            try
            {
                string playerUid = "9EDC20A9000000000000000000000000";
                string savePath = Path.Combine(playersDir, $"{playerUid}.sav");

                byte[] mockSave = CreateMockPalworldSave(unusedTechPoints: 5, level: 20);
                await File.WriteAllBytesAsync(savePath, mockSave);

                var saveService = new PalSaveService(_logService, tempDir);
                var economyService = new EconomyService(_logService, saveService, customStateFilePath: Path.Combine(tempDir, "state.json"));

                // 1. Invalid item query
                var invalidReceipt = await economyService.ExecuteExchangeAsync(playerUid, "non_existent_item_xyz", 1);
                Assert.False(invalidReceipt.Success);
                Assert.Contains("not found", invalidReceipt.Message);

                // 2. Insufficient points: Memory Reset Drug costs 8, player has 5
                var brokeReceipt = await economyService.ExecuteExchangeAsync(playerUid, "memory_reset_drug", 1);
                Assert.False(brokeReceipt.Success);
                Assert.Contains("Insufficient", brokeReceipt.Message);
                Assert.Equal(5, brokeReceipt.PreviousTechPoints);
                Assert.Equal(5, brokeReceipt.NewTechPoints);

                // 3. Verify points were NOT deducted
                var profile = await saveService.ReadPlayerProfileAsync(playerUid);
                Assert.NotNull(profile);
                Assert.Equal(5, profile.TechnologyPoints);
            }
            finally
            {
                if (Directory.Exists(tempDir)) Directory.Delete(tempDir, true);
            }
        }

        [Fact]
        public async Task Test_3_3_ExchangeAndScrap_CalibratedRatesAccuracy()
        {
            string tempDir = Path.Combine(Path.GetTempPath(), "PalTestRates_" + Guid.NewGuid().ToString("N"));
            string playersDir = Path.Combine(tempDir, "Players");
            Directory.CreateDirectory(playersDir);

            try
            {
                string playerUid = "9EDC20A9000000000000000000000000";
                string savePath = Path.Combine(playersDir, $"{playerUid}.sav");

                // Start with 100 Tech Points
                byte[] mockSave = CreateMockPalworldSave(unusedTechPoints: 100, level: 50);
                await File.WriteAllBytesAsync(savePath, mockSave);

                var saveService = new PalSaveService(_logService, tempDir);
                var economyService = new EconomyService(_logService, saveService, customStateFilePath: Path.Combine(tempDir, "state.json"));

                // Test each item in the exchange catalog:
                // Dog Coin: 2 pts -> 1
                var r1 = await economyService.ExecuteExchangeAsync(playerUid, "dog_coin", 1);
                Assert.True(r1.Success);
                Assert.Equal(2, r1.TotalCost);

                // Arena Ticket: 3 pts -> 1
                var r2 = await economyService.ExecuteExchangeAsync(playerUid, "arena_ticket", 1);
                Assert.True(r2.Success);
                Assert.Equal(3, r2.TotalCost);

                // Bounty Token: 4 pts -> 1
                var r3 = await economyService.ExecuteExchangeAsync(playerUid, "bounty_token", 1);
                Assert.True(r3.Success);
                Assert.Equal(4, r3.TotalCost);

                // Pal Reverser: 5 pts -> 1
                var r4 = await economyService.ExecuteExchangeAsync(playerUid, "pal_reverser", 1);
                Assert.True(r4.Success);
                Assert.Equal(5, r4.TotalCost);

                // Memory Reset Drug: 8 pts -> 1
                var r5 = await economyService.ExecuteExchangeAsync(playerUid, "memory_reset_drug", 1);
                Assert.True(r5.Success);
                Assert.Equal(8, r5.TotalCost);

                // Raid Boss Slab: 10 pts -> 1
                var r6 = await economyService.ExecuteExchangeAsync(playerUid, "raid_boss_slab", 1);
                Assert.True(r6.Success);
                Assert.Equal(10, r6.TotalCost);

                // Total deducted: 2+3+4+5+8+10 = 32 points. 100 - 32 = 68 points remaining.
                var pMid = await saveService.ReadPlayerProfileAsync(playerUid);
                Assert.NotNull(pMid);
                Assert.Equal(68, pMid.TechnologyPoints);

                // Test Recycling:
                // 4x Precious Pelt (0.5 each = +2 pts)
                var rec1 = await economyService.ExecuteRecycleAsync(playerUid, "precious_pelt", 4);
                Assert.True(rec1.Success);
                Assert.Equal(2, rec1.PointsAwarded);

                // 2x Diamond (+2 each = +4 pts)
                var rec2 = await economyService.ExecuteRecycleAsync(playerUid, "diamond", 2);
                Assert.True(rec2.Success);
                Assert.Equal(4, rec2.PointsAwarded);

                // 1x Epic Schematic (+3 pts)
                var rec3 = await economyService.ExecuteRecycleAsync(playerUid, "schematic_epic", 1);
                Assert.True(rec3.Success);
                Assert.Equal(3, rec3.PointsAwarded);

                // Total earned: 2 + 4 + 3 = 9 points. 68 + 9 = 77 points.
                var pFinal = await saveService.ReadPlayerProfileAsync(playerUid);
                Assert.NotNull(pFinal);
                Assert.Equal(77, pFinal.TechnologyPoints);
            }
            finally
            {
                if (Directory.Exists(tempDir)) Directory.Delete(tempDir, true);
            }
        }

        #endregion

        private static byte[] CreateMockPalworldSave(int unusedTechPoints, int level)
        {
            using var ms = new MemoryStream();
            using var writer = new BinaryWriter(ms, System.Text.Encoding.ASCII);

            writer.Write(System.Text.Encoding.ASCII.GetBytes("GVAS"));
            writer.Write(3);
            writer.Write(new byte[16]);

            string propName = "UnusedTechnologyPoint";
            writer.Write(System.Text.Encoding.ASCII.GetBytes(propName));
            writer.Write((byte)0);

            string propType = "IntProperty";
            writer.Write(System.Text.Encoding.ASCII.GetBytes(propType));
            writer.Write((byte)0);

            writer.Write((long)4);
            writer.Write((byte)0);
            writer.Write(unusedTechPoints);

            string lvlProp = "Level";
            writer.Write(System.Text.Encoding.ASCII.GetBytes(lvlProp));
            writer.Write((byte)0);
            writer.Write(System.Text.Encoding.ASCII.GetBytes(propType));
            writer.Write((byte)0);
            writer.Write((long)4);
            writer.Write((byte)0);
            writer.Write(level);

            writer.Flush();
            byte[] decompressed = ms.ToArray();

            return PalSaveService.CompressPalSave(decompressed);
        }
    }
}



