using PalLauncher.Models;
using PalLauncher.Services;
using Xunit;

namespace PalLauncher.Tests
{
    public class LaunchServiceTests
    {
        private readonly LogService _logService = new();

        [Fact]
        public void BuildCommandLineArguments_WithDirectX11AndAllCores_BuildsCorrectFlags()
        {
            // Arrange
            var launchService = new LaunchService(_logService);
            var config = new LauncherConfig
            {
                LaunchMode = "Client",
                UseDirectX11 = true,
                UseAllCores = true,
                NoSplash = true,
                WindowedMode = false,
                UseHighPriority = false,
                CustomArguments = ""
            };

            // Act
            string args = launchService.BuildCommandLineArguments(config);

            // Assert
            Assert.Contains("-dx11", args);
            Assert.Contains("-USEALLAVAILABLECORES", args);
            Assert.Contains("-nosplash", args);
            Assert.DoesNotContain("-windowed", args);
            Assert.DoesNotContain("-high", args);
        }

        [Fact]
        public void BuildCommandLineArguments_WithAutoJoinServer_PrependsServerAddress()
        {
            // Arrange
            var launchService = new LaunchService(_logService);
            var config = new LauncherConfig
            {
                LaunchMode = "Client",
                AutoJoinServer = true,
                ServerIp = "192.168.1.100",
                ServerPort = 8211,
                UseDirectX11 = true,
                UseAllCores = false,
                NoSplash = false,
                CustomArguments = "-culture=en"
            };

            // Act
            string args = launchService.BuildCommandLineArguments(config);

            // Assert
            Assert.True(args.StartsWith("192.168.1.100:8211") || args.StartsWith("127.0.0.1:8211"));
            Assert.Contains("-dx11", args);
            Assert.Contains("-culture=en", args);
        }

        [Fact]
        public void BuildServerCommandLineArguments_BuildsCorrectDedicatedServerFlags()
        {
            // Arrange
            var launchService = new LaunchService(_logService);
            var config = new LauncherConfig
            {
                ServerPort = 8211,
                ServerIp = "palodyssey.duckdns.org"
            };

            // Act
            string args = launchService.BuildServerCommandLineArguments(config);

            // Assert
            Assert.Contains("-port=8211", args);
            Assert.Contains("-publicport=8211", args);
            Assert.Contains("-queryport=27016", args);
            Assert.Contains("-players=32", args);
            Assert.Contains("-log", args);
            Assert.Contains("-useperfthreads", args);
            Assert.Contains("-NoAsyncLoadingThread", args);
            Assert.Contains("-USEALLAVAILABLECORES", args);
            Assert.Contains("-malloc=system", args);
        }

        [Fact]
        public void InjectRawInputSettingsIntoIni_WithEmptyContent_CreatesCorrectSectionAndKeys()
        {
            string result = LaunchService.InjectRawInputSettingsIntoIni("");

            Assert.Contains("[/Script/Engine.InputSettings]", result);
            Assert.Contains("RawMouseInputEnabled=True", result);
            Assert.Contains("bEnableMouseSmoothing=False", result);
            Assert.Contains("bViewAccelerationEnabled=False", result);
            Assert.Contains("bDisableMouseAcceleration=True", result);
        }

        [Fact]
        public void InjectRawInputSettingsIntoIni_WithExistingOtherSections_PreservesSectionsAndInjects()
        {
            string existing = "[/Script/Engine.GameSession]\r\nMaxPlayers=32\r\n\r\n[Core.System]\r\nPaths=../../../Engine/Content";
            string result = LaunchService.InjectRawInputSettingsIntoIni(existing);

            Assert.Contains("[/Script/Engine.GameSession]", result);
            Assert.Contains("MaxPlayers=32", result);
            Assert.Contains("[Core.System]", result);
            Assert.Contains("[/Script/Engine.InputSettings]", result);
            Assert.Contains("RawMouseInputEnabled=True", result);
            Assert.Contains("bEnableMouseSmoothing=False", result);
        }

        [Fact]
        public void InjectRawInputSettingsIntoIni_WithExistingInputSettings_UpdatesFlagsIdempotently()
        {
            string existing = "[/Script/Engine.InputSettings]\r\nbEnableMouseSmoothing=True\r\nbViewAccelerationEnabled=True\r\nCustomKey=123";
            string result = LaunchService.InjectRawInputSettingsIntoIni(existing);

            Assert.Contains("[/Script/Engine.InputSettings]", result);
            Assert.Contains("RawMouseInputEnabled=True", result);
            Assert.Contains("bEnableMouseSmoothing=False", result);
            Assert.Contains("bViewAccelerationEnabled=False", result);
            Assert.Contains("bDisableMouseAcceleration=True", result);
            Assert.Contains("CustomKey=123", result);
            Assert.DoesNotContain("bEnableMouseSmoothing=True", result);
        }

        [Fact]
        public void ResolvePlayitExecutablePath_FindsToolExecutableIfExists()
        {
            var launchService = new LaunchService(_logService);

            string? path = launchService.ResolvePlayitExecutablePath();
            if (System.IO.File.Exists(@"C:\PalOddessey\tools\playit\playit.exe"))
            {
                Assert.NotNull(path);
                Assert.True(System.IO.File.Exists(path));
            }
        }
    }
}
