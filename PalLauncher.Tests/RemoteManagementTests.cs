using System;
using System.Threading.Tasks;
using PalLauncher.Models;
using PalLauncher.Services;
using PalLauncher.Services.Interfaces;
using Xunit;

namespace PalLauncher.Tests
{
    [Collection("DaemonTests")]
    public class RemoteManagementTests
    {
        private readonly LogService _logService = new();

        [Fact]
        public async Task RemoteDaemon_And_Client_StatusAndWakeCycle_Succeeds()
        {
            var launchService = new LaunchService(_logService);
            var daemon = new RemoteServerDaemon(_logService, launchService);
            var client = new RemoteClientService(_logService);

            int testPort = 18212; // Use distinct port for unit testing
            string testKey = "TestSecretKey123";
            bool serverStartTriggered = false;

            try
            {
                // 1. Start daemon
                bool started = await daemon.StartDaemonAsync(
                    testPort,
                    testKey,
                    onStartServerRequested: () =>
                    {
                        serverStartTriggered = true;
                        return Task.FromResult(true);
                    },
                    onStopServerRequested: () => Task.FromResult(true));

                Assert.True(started);
                Assert.True(daemon.IsRunning);

                // 2. Query status from client
                var status = await client.QueryServerStatusAsync("127.0.0.1", testPort, 3000);
                Assert.True(status.IsOnline);
                Assert.Equal(8211, status.ServerPort);
                Assert.Equal("PalOdyssey Realm", status.ServerName);

                // 3. Test Invalid Key Rejected
                bool invalidWake = await client.RequestRemoteServerStartAsync("127.0.0.1", testPort, "WrongKey", timeoutSeconds: 2);
                Assert.False(invalidWake);
                Assert.False(serverStartTriggered);

                // 4. Test Valid Key Triggers Server Start
                bool validWake = await client.RequestRemoteServerStartAsync("127.0.0.1", testPort, testKey, timeoutSeconds: 2);
                Assert.True(validWake);
                Assert.True(serverStartTriggered);
            }
            finally
            {
                await daemon.StopDaemonAsync();
            }
        }

        [Fact]
        public async Task RemoteDaemon_HandlesWorldBossSpawnAndCaptureEvents_Successfully()
        {
            var launchService = new LaunchService(_logService);
            var daemon = new RemoteServerDaemon(_logService, launchService);

            int testPort = 18218;
            string testKey = "TestBossKey123";

            string? spawnedPal = null;
            string? spawnLocation = null;
            string? capturedPal = null;
            string? capturer = null;

            daemon.OnWorldBossSpawn = (pal, loc, aura, x, y) =>
            {
                spawnedPal = pal;
                spawnLocation = loc;
                return Task.CompletedTask;
            };

            daemon.OnWorldBossCaptured = (pal, by) =>
            {
                capturedPal = pal;
                capturer = by;
                return Task.CompletedTask;
            };

            try
            {
                bool started = await daemon.StartDaemonAsync(
                    testPort,
                    testKey,
                    onStartServerRequested: () => Task.FromResult(true),
                    onStopServerRequested: () => Task.FromResult(true));

                Assert.True(started);

                using var httpClient = new System.Net.Http.HttpClient { BaseAddress = new Uri($"http://127.0.0.1:{testPort}/") };

                // 1. Post Spawn Event
                var spawnPayload = new System.Net.Http.StringContent(
                    "{\"event\":\"spawn\",\"palName\":\"Orserk_Terra\",\"location\":\"Desolate Dunes\",\"aura\":\"Corrupted\",\"x\":-120000,\"y\":-180000}",
                    System.Text.Encoding.UTF8, "application/json");

                var spawnResp = await httpClient.PostAsync("api/world-boss", spawnPayload);
                Assert.Equal(System.Net.HttpStatusCode.OK, spawnResp.StatusCode);

                // Give async task time to invoke callback
                await Task.Delay(100);
                Assert.Equal("Orserk_Terra", spawnedPal);
                Assert.Equal("Desolate Dunes", spawnLocation);

                // 2. Post Capture Event
                var capPayload = new System.Net.Http.StringContent(
                    "{\"event\":\"captured\",\"palName\":\"Orserk_Terra\",\"capturedBy\":\"PioneerHero\"}",
                    System.Text.Encoding.UTF8, "application/json");

                var capResp = await httpClient.PostAsync("api/world-boss", capPayload);
                Assert.Equal(System.Net.HttpStatusCode.OK, capResp.StatusCode);

                await Task.Delay(100);
                Assert.Equal("Orserk_Terra", capturedPal);
                Assert.Equal("PioneerHero", capturer);
            }
            finally
            {
                await daemon.StopDaemonAsync();
            }
        }
    }
}
