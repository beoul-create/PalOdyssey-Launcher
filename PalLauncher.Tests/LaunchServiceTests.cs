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
            Assert.StartsWith("192.168.1.100:8211", args);
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
                ServerIp = "beoul.duckdns.org"
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
    }
}
