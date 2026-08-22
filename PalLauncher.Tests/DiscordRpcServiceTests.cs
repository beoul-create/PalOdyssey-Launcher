using System.Threading.Tasks;
using PalLauncher.Services;
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
            await service.InitializeAsync("1200155050516521020");

            // Update presence should safely no-op when not connected
            await service.UpdatePresenceAsync("Using PalOddyssey Launcher", "Preparing Expedition", isPlaying: false);
            await service.UpdatePresenceAsync("Playing ⚡ PalOddyssey Expedition ⚔️", "In Realm (15 Mods Active)", isPlaying: true);

            // Clear presence
            await service.ClearPresenceAsync();

            Assert.NotNull(service);
        }
    }
}
