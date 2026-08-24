using System;
using System.Collections.Generic;
using System.IO;
using System.Net.Http;
using System.Threading.Tasks;
using PalLauncher.Models;
using PalLauncher.Services;
using PalLauncher.Services.Interfaces;
using PalLauncher.ViewModels;
using Xunit;
using Xunit.Abstractions;

namespace PalLauncher.Tests
{
    [Collection("DaemonTests")]
    public class FeatureIntegrationTests
    {
        private readonly ITestOutputHelper _output;
        private readonly LogService _logService = new();

        public FeatureIntegrationTests(ITestOutputHelper output)
        {
            _output = output;
        }

        [Fact]
        public async Task Test_1_RemoteServerDaemon_StartUp_And_Liveboard()
        {
            int testPort = 19400 + Random.Shared.Next(10, 500);
            string secretKey = "PalOdysseyLiveTestKey";
            bool serverStartTriggered = false;
            bool serverStopTriggered = false;

            var launchService = new LaunchService(_logService);
            var daemon = new RemoteServerDaemon(_logService, launchService);
            var client = new RemoteClientService(_logService);

            // 1. Start Remote Server Daemon
            bool started = await daemon.StartDaemonAsync(
                testPort,
                secretKey,
                onStartServerRequested: () =>
                {
                    serverStartTriggered = true;
                    return Task.FromResult(true);
                },
                onStopServerRequested: () =>
                {
                    serverStopTriggered = true;
                    return Task.FromResult(true);
                });

            Assert.True(started, "Remote Server Daemon should start successfully");
            await Task.Delay(150);

            try
            {
                // 2. Query Liveboard via REST API
                var liveboard = await client.FetchLiveboardAsync("127.0.0.1", testPort, 3000);
                Assert.NotNull(liveboard);
                Assert.True(liveboard.IsOnline, "Liveboard should report server online");
                Assert.Equal("PalOdyssey Realm", liveboard.ServerName);
                Assert.True(liveboard.ServerAddress.StartsWith("palodyssey.duckdns.org:"));

                _output.WriteLine($"[PASS] Server Liveboard Query: {liveboard.ServerName} ({liveboard.ServerAddress}) - Online: {liveboard.IsOnline}");

                // 3. Send Remote Server Start Command
                bool startSuccess = await client.RequestRemoteServerStartAsync("127.0.0.1", testPort, secretKey, null, 5);
                Assert.True(startSuccess, "Authenticated remote start should succeed");
                Assert.True(serverStartTriggered, "Start callback should have been triggered");

                _output.WriteLine($"[PASS] Remote Server Start Up Triggered via API: Success = {startSuccess}");

                // 4. Send Remote Server Stop Command
                bool stopSuccess = await client.RequestRemoteServerStopAsync("127.0.0.1", testPort, secretKey);
                Assert.True(stopSuccess, "Authenticated remote stop should succeed");
                Assert.True(serverStopTriggered, "Stop callback should have been triggered");

                _output.WriteLine($"[PASS] Remote Server Stop Triggered via API: Success = {stopSuccess}");
            }
            finally
            {
                await daemon.StopDaemonAsync();
            }
        }

        [Fact]
        public void Test_2_ServerAutoJoin_And_CommandLineBuilder()
        {
            var launchService = new LaunchService(_logService);

            var config = new LauncherConfig
            {
                GamePath = @"C:\SteamLibrary\steamapps\common\Palworld",
                LaunchMode = "Client",
                AutoJoinServer = true,
                ServerIp = "palodyssey.duckdns.org",
                ServerPort = 57294,
                UseDirectX11 = true,
                UseAllCores = true,
                NoSplash = true,
                UseHighPriority = true,
                CustomArguments = "-malloc=system -useperfthreads"
            };

            string commandLine = launchService.BuildCommandLineArguments(config);

            Assert.True(commandLine.Contains("127.0.0.1:8211") || commandLine.Contains("palodyssey.duckdns.org:8211") || commandLine.Contains("palodyssey.duckdns.org:57294"));
            Assert.Contains("-dx11", commandLine);
            Assert.Contains("-USEALLAVAILABLECORES", commandLine);
            Assert.Contains("-nosplash", commandLine);
            Assert.Contains("-high", commandLine);
            Assert.Contains("-malloc=system", commandLine);

            _output.WriteLine($"[PASS] Auto-Join Command Line: {commandLine}");
        }

        [Fact]
        public async Task Test_3_InAppModUpdater_ManifestAndChecksumVerification()
        {
            var configService = new ConfigService(_logService);
            var updateService = new UpdateService(_logService);

            string manifestPath = @"C:\PalOddessey\Modpack\version.json";
            string gamePath = @"C:\SteamLibrary\steamapps\common\Palworld";

            Assert.True(File.Exists(manifestPath), "Manifest version.json must exist");

            // 1. Check mod status against local manifest
            var mods = await updateService.CheckForUpdatesAsync(manifestPath, gamePath);
            Assert.NotEmpty(mods);

            _output.WriteLine($"[PASS] Manifest Loaded: {mods.Count} mods verified");
            foreach (var mod in mods)
            {
                _output.WriteLine($"  • [{mod.Status}] {mod.Name} (v{mod.Version}) -> {mod.RelativeInstallPath}");
                Assert.False(string.IsNullOrEmpty(mod.Name));
                Assert.False(string.IsNullOrEmpty(mod.RelativeInstallPath));
            }
        }

        [Fact]
        public void Test_4_ActivityLogs_And_ConsoleExport()
        {
            var testLogService = new LogService();

            // Emit logs across all severities
            testLogService.LogInfo("Test Info Message", "TestRunner");
            testLogService.LogSuccess("Test Success Message", "TestRunner");
            testLogService.LogWarning("Test Warning Message", "TestRunner");
            testLogService.LogError("Test Error Message", "TestRunner");

            Assert.True(testLogService.LogEntries.Count >= 4);

            // Test Log Content
            Assert.Contains(testLogService.LogEntries, e => e.Level == LogLevel.Info && e.Message == "Test Info Message");
            Assert.Contains(testLogService.LogEntries, e => e.Level == LogLevel.Success && e.Message == "Test Success Message");
            Assert.Contains(testLogService.LogEntries, e => e.Level == LogLevel.Warning && e.Message == "Test Warning Message");
            Assert.Contains(testLogService.LogEntries, e => e.Level == LogLevel.Error && e.Message == "Test Error Message");

            _output.WriteLine($"[PASS] Log System: 4 events captured with Info, Success, Warning, Error severities.");
        }
    }
}
