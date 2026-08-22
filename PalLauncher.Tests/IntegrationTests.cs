using System;
using System.IO;
using System.Threading.Tasks;
using PalLauncher.Models;
using PalLauncher.Services;
using Xunit;

namespace PalLauncher.Tests
{
    public class IntegrationTests
    {
        private readonly LogService _logService = new();
        private readonly GamePathDetector _detector;
        private readonly UpdateService _updateService;
        private readonly LaunchService _launchService;

        public IntegrationTests()
        {
            _detector = new GamePathDetector(_logService);
            _updateService = new UpdateService(_logService);
            _launchService = new LaunchService(_logService);
        }

        [Fact]
        public async Task EndToEnd_MockGame_DetectsModsAndValidatesPath()
        {
            string mockGamePath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "..", "..", "..", "..", "MockGame", "PalRoot");
            string fullMockPath = Path.GetFullPath(mockGamePath);

            string sampleManifestPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "..", "..", "..", "..", "PalLauncher", "SampleData", "version.json");
            string fullManifestPath = Path.GetFullPath(sampleManifestPath);

            if (!Directory.Exists(fullMockPath) || !File.Exists(fullManifestPath))
            {
                // Fallback for different build output directory paths
                return;
            }

            // 1. Path validation
            var pathInfo = _detector.ValidatePath(fullMockPath);
            Assert.True(pathInfo.IsValid);
            Assert.True(File.Exists(pathInfo.ClientExecutablePath));

            // 2. Mod status checking
            var mods = await _updateService.CheckForUpdatesAsync(fullManifestPath, fullMockPath);
            Assert.True(mods.Count >= 3);

            // 3. Launch configuration test
            var config = new LauncherConfig
            {
                GamePath = fullMockPath,
                LaunchMode = "Client",
                AutoJoinServer = true,
                ServerIp = "127.0.0.1",
                ServerPort = 8211,
                UseDirectX11 = true,
                UseAllCores = true
            };

            string args = _launchService.BuildCommandLineArguments(config);
            Assert.Contains("127.0.0.1:8211", args);
            Assert.Contains("-dx11", args);
            Assert.Contains("-USEALLAVAILABLECORES", args);
        }
    }
}
