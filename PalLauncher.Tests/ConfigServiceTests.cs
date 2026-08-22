using System;
using System.IO;
using System.Threading.Tasks;
using PalLauncher.Models;
using PalLauncher.Services;
using Xunit;

namespace PalLauncher.Tests
{
    public class ConfigServiceTests
    {
        private readonly LogService _logService = new();

        [Fact]
        public async Task ConfigService_SaveAndLoad_PreservesCustomSettings()
        {
            // Arrange
            string tempConfigFile = Path.Combine(Path.GetTempPath(), $"pallauncher_test_{Guid.NewGuid():N}.json");
            try
            {
                var configService = new ConfigService(_logService, tempConfigFile);
                var customConfig = new LauncherConfig
                {
                    GamePath = @"C:\Games\CustomPalworld",
                    ServerIp = "10.0.0.55",
                    ServerPort = 9999,
                    AutoJoinServer = true,
                    UseDirectX11 = false,
                    UseAllCores = true,
                    UseHighPriority = true,
                    CustomArguments = "-culture=ja -NoEAC"
                };

                // Act
                await configService.SaveConfigAsync(customConfig);
                var loadedConfig = await configService.LoadConfigAsync();

                // Assert
                Assert.Equal(@"C:\Games\CustomPalworld", loadedConfig.GamePath);
                Assert.Equal("10.0.0.55", loadedConfig.ServerIp);
                Assert.Equal(9999, loadedConfig.ServerPort);
                Assert.True(loadedConfig.AutoJoinServer);
                Assert.False(loadedConfig.UseDirectX11);
                Assert.True(loadedConfig.UseAllCores);
                Assert.True(loadedConfig.UseHighPriority);
                Assert.Equal("-culture=ja -NoEAC", loadedConfig.CustomArguments);
            }
            finally
            {
                if (File.Exists(tempConfigFile)) File.Delete(tempConfigFile);
            }
        }
    }
}
