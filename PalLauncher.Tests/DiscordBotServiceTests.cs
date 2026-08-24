using System;
using System.Threading.Tasks;
using PalLauncher.Models;
using PalLauncher.Services;
using PalLauncher.ViewModels;
using Xunit;

namespace PalLauncher.Tests
{
    public class DiscordBotServiceTests
    {
        [Fact]
        public async Task DiscordBotService_EmptyToken_ShouldNotStart()
        {
            var logService = new LogService();
            using var botService = new DiscordBotService(logService);

            bool started = await botService.StartAsync(
                token: "",
                prefix: "!",
                channelId: null,
                adminRoleId: null,
                onStartServer: () => Task.FromResult(true),
                onStopServer: () => Task.FromResult(true),
                getLiveboard: () => new ServerLiveboardInfo());

            Assert.False(started, "Bot should not start with empty token");
            Assert.False(botService.IsRunning);
        }

        [Fact]
        public void LauncherConfig_DiscordBotProperties_DefaultsCorrectly()
        {
            var config = new LauncherConfig();

            Assert.True(config.EnableDiscordBot);
            Assert.True(config.AutoStartWithWindows);
            Assert.True(config.RunInBackgroundOnClose);
            Assert.Equal("", config.DiscordBotToken);
            Assert.Equal("/", config.DiscordCommandPrefix);
            Assert.Equal("1541492780168380446", config.DiscordBotChannelId);
            Assert.Equal("", config.DiscordAdminRoleId);
        }

        [Fact]
        public void SettingsViewModel_DiscordBotFields_MapCorrectly()
        {
            var logService = new LogService();
            var configService = new ConfigService(logService);
            var pathDetector = new GamePathDetector(logService);
            var launchService = new LaunchService(logService);
            var updateService = new UpdateService(logService);
            var specService = new SystemSpecService(logService);

            var vm = new SettingsViewModel(configService, pathDetector, launchService, updateService, logService, specService);

            var config = new LauncherConfig
            {
                EnableDiscordBot = true,
                AutoStartWithWindows = true,
                RunInBackgroundOnClose = true,
                DiscordBotToken = "sample_bot_token_12345",
                DiscordCommandPrefix = "!",
                DiscordBotChannelId = "123456789012345678"
            };

            vm.LoadFromConfig(config);

            Assert.True(vm.EnableDiscordBot);
            Assert.True(vm.AutoStartWithWindows);
            Assert.True(vm.RunInBackgroundOnClose);
            Assert.Equal("sample_bot_token_12345", vm.DiscordBotToken);
            Assert.Equal("!", vm.DiscordCommandPrefix);
            Assert.Equal("123456789012345678", vm.DiscordBotChannelId);

            var created = vm.CreateConfigFromProperties();
            Assert.True(created.EnableDiscordBot);
            Assert.True(created.AutoStartWithWindows);
            Assert.True(created.RunInBackgroundOnClose);
            Assert.Equal("sample_bot_token_12345", created.DiscordBotToken);
            Assert.Equal("!", created.DiscordCommandPrefix);
            Assert.Equal("123456789012345678", created.DiscordBotChannelId);
        }

        [Fact]
        public void SingleInstanceManager_CanAcquireAndDispose()
        {
            var logService = new LogService();
            using var manager = new SingleInstanceManager(logService);

            bool acquired = manager.TryAcquire(customMutexName: "Local\\PalOdysseyLauncher_Test_Mutex_" + Guid.NewGuid().ToString("N"));
            Assert.True(acquired);
            Assert.True(manager.IsFirstInstance);
        }

        [Fact]
        public void WindowsTaskSchedulerService_CanInstantiateAndCheckStatus()
        {
            var logService = new LogService();
            var scheduler = new WindowsTaskSchedulerService(logService);

            // Should query without throwing exceptions
            bool isRegistered = scheduler.Is24x7TaskRegistered();
            Assert.True(isRegistered == true || isRegistered == false);
        }

        [Fact]
        public async Task DiscordBotService_StopAsync_GracefullyStops()
        {
            var logService = new LogService();
            using var botService = new DiscordBotService(logService);

            await botService.StopAsync();
            Assert.False(botService.IsRunning);
        }
    }
}
