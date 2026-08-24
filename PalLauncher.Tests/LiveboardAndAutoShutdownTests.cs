using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using PalLauncher.Models;
using PalLauncher.Services;
using PalLauncher.Services.Interfaces;
using Xunit;

namespace PalLauncher.Tests
{
    [Collection("DaemonTests")]
    public class LiveboardAndAutoShutdownTests
    {
        private readonly LogService _logService = new();

        [Fact]
        public async Task Liveboard_SerializationAndQuery_ReturnsAccurateData()
        {
            var launchService = new LaunchService(_logService);
            var daemon = new RemoteServerDaemon(_logService, launchService);
            var client = new RemoteClientService(_logService);

            int testPort = 19280 + Random.Shared.Next(10, 500);
            string testKey = "TestSecretKeyLiveboard";

            try
            {
                daemon.ConfigureIdleAutoShutdown(true, 10);
                bool started = await daemon.StartDaemonAsync(
                    testPort,
                    testKey,
                    () => Task.FromResult(true),
                    () => Task.FromResult(true));

                Assert.True(started);
                await Task.Delay(150);

                // Fetch Liveboard via HTTP API
                var liveboard = await client.FetchLiveboardAsync("127.0.0.1", testPort, 5000);

                Assert.NotNull(liveboard);
                Assert.True(liveboard.IsOnline);
                Assert.Equal("PalOdyssey Realm", liveboard.ServerName);
                Assert.True(liveboard.ServerAddress.StartsWith("palodyssey.duckdns.org:"));
                Assert.Equal(32, liveboard.MaxPlayers);
                Assert.True(liveboard.IdleShutdownEnabled);
            }
            finally
            {
                await daemon.StopDaemonAsync();
            }
        }

        [Fact]
        public void ServerLiveboardInfo_FormattedProperties_FormatCorrectly()
        {
            var liveboard = new ServerLiveboardInfo
            {
                IsOnline = true,
                IsServerRunning = true,
                UptimeSeconds = 3665, // 1 hour, 1 min, 5 sec
                PlayerCount = 2,
                MaxPlayers = 32,
                Players = new List<PlayerInfo>
                {
                    new PlayerInfo { Name = "Jack", Level = 50, PingMs = 15 },
                    new PlayerInfo { Name = "Beoul", Level = 35, PingMs = 40 }
                }
            };

            Assert.Equal("01h 01m 05s", liveboard.UptimeFormatted);
            Assert.Equal("2 / 32 Players Online", liveboard.PlayerCountSummary);
            Assert.True(liveboard.HasActivePlayers);
            Assert.False(liveboard.HasNoPlayers);
            Assert.Equal("Lv. 50", liveboard.Players[0].LevelBadge);
            Assert.Equal("15ms", liveboard.Players[0].PingBadge);
        }

        [Fact]
        public void AutoShutdown_ConfigureIdleAutoShutdown_UpdatesProperties()
        {
            var launchService = new LaunchService(_logService);
            var daemon = new RemoteServerDaemon(_logService, launchService);

            daemon.ConfigureIdleAutoShutdown(true, 5);
            var liveboard = daemon.GetCurrentLiveboard();

            Assert.True(liveboard.IdleShutdownEnabled);
            Assert.Equal(5, liveboard.IdleMinutesRemaining);

            daemon.ConfigureIdleAutoShutdown(false, 30);
            liveboard = daemon.GetCurrentLiveboard();

            Assert.False(liveboard.IdleShutdownEnabled);
            Assert.Equal(30, liveboard.IdleMinutesRemaining);
        }

        [Fact]
        public void LaunchService_ProcessDetection_SafelyQueriesActiveProcesses()
        {
            var serverProcs = LaunchService.GetActiveServerProcesses();
            var clientProcs = LaunchService.GetActiveClientProcesses();

            Assert.NotNull(serverProcs);
            Assert.NotNull(clientProcs);
        }

        [Fact]
        public void GamePathDetector_DedicatedServerPaths_ValidatesProperly()
        {
            var detector = new GamePathDetector(_logService);
            string serverPath = @"C:\SteamLibrary\steamapps\common\PalServer";

            if (System.IO.Directory.Exists(serverPath))
            {
                var info = detector.ValidatePath(serverPath);
                Assert.True(info.IsValid);
                Assert.False(string.IsNullOrEmpty(info.ServerExecutablePath));
            }
        }
    }
}
