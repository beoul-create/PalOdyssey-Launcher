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
    }
}
