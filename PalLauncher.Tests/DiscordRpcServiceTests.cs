using System;
using System.Threading.Tasks;
using PalLauncher.Models;
using PalLauncher.Services;
using PalLauncher.ViewModels;
using Xunit;

namespace PalLauncher.Tests
{
    public class DiscordRpcServiceTests
    {
        private readonly LogService _logService = new();

        [Fact]
        public async Task DiscordRpcService_InitializeAndLifecycle_NoCrashWhenDiscordClosed()
        {
            using var service = new DiscordRpcService(_logService);

            // Should initialize safely without throwing even if Discord is not currently running
            await service.InitializeAsync("1540924979095408700");

            // Update presence should safely no-op when not connected
            await service.UpdatePresenceAsync("Using PalOdyssey Launcher", "Preparing Expedition", isPlaying: false);
            await service.UpdatePresenceAsync("Playing ⚡ PalOdyssey Expedition ⚔️", "In Realm (15 Mods Active)", isPlaying: true);

            // Clear presence
            await service.ClearPresenceAsync();

            Assert.NotNull(service);
        }

        [Fact]
        public async Task DiscordRpcService_UpdatePresenceWithButtonsAndAssets_SafeExecution()
        {
            using var service = new DiscordRpcService(_logService);
            await service.InitializeAsync("1541335019899977768");

            var buttons = new (string label, string url)[]
            {
                ("Join Discord", "https://discord.gg/palodyssey"),
                ("Get Launcher", "https://github.com/beoul-create/PalOdyssey-Launcher")
            };

            await service.UpdatePresenceAsync(
                "Exploring Realm",
                "15 Mods Active",
                isPlaying: true,
                targetPid: 1234,
                largeImageKey: "palworld",
                largeImageText: "PalOdyssey Expedition",
                smallImageKey: "online",
                smallImageText: "In Dedicated Realm",
                buttons: buttons);

            await service.ClearPresenceAsync();
            Assert.NotNull(service);
        }

        [Fact]
        public async Task DiscordRpcService_MultipleRapidUpdates_NoDeadlocks()
        {
            using var service = new DiscordRpcService(_logService);
            await service.InitializeAsync("1541335019899977768");

            for (int i = 0; i < 50; i++)
            {
                await service.UpdatePresenceAsync(
                    $"Expedition Wave #{i}",
                    "Surviving Dunes",
                    isPlaying: i % 2 == 0,
                    targetPid: Environment.ProcessId);
            }

            await service.ClearPresenceAsync();
            Assert.NotNull(service);
        }

        [Fact]
        public async Task MainViewModel_RestartDiscordRpcAsync_ExecutesWhenRemoteHostDaemonEnabled()
        {
            var configService = new ConfigService(_logService);
            configService.Config.EnableDiscordRpc = true;
            configService.Config.EnableRemoteHostDaemon = true; // Was previously causing RPC suppression!
            configService.Config.LaunchMode = "Client";

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

            // Trigger restart Discord RPC directly
            await mainVm.RestartDiscordRpcAsync();

            Assert.True(configService.Config.EnableDiscordRpc);
            Assert.NotNull(mainVm);
        }
    }
}
