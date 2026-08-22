using System.Threading.Tasks;
using PalLauncher.Models;
using PalLauncher.Services;
using PalLauncher.Services.Interfaces;
using Xunit;

namespace PalLauncher.Tests
{
    public class SystemSpecServiceTests
    {
        private readonly LogService _logService = new();

        [Fact]
        public async Task SystemSpecService_DetectSpecs_ReturnsValidHardwareProfile()
        {
            var service = new SystemSpecService(_logService);

            var profile = await service.DetectSystemSpecsAsync();

            Assert.NotNull(profile);
            Assert.False(string.IsNullOrWhiteSpace(profile.CpuName));
            Assert.True(profile.LogicalCores >= 1);
            Assert.True(profile.TotalRamGb > 0);
            Assert.False(string.IsNullOrWhiteSpace(profile.GpuName));
            Assert.False(string.IsNullOrWhiteSpace(profile.PerformanceTier));
            Assert.False(string.IsNullOrWhiteSpace(profile.SummaryText));
        }

        [Fact]
        public void SystemSpecService_ApplyOptimalFlags_ConfiguresHighEndRigCorrectly()
        {
            var service = new SystemSpecService(_logService);
            var profile = new SystemHardwareProfile
            {
                CpuName = "AMD Ryzen 5 5500",
                PhysicalCores = 6,
                LogicalCores = 12,
                TotalRamGb = 32.0,
                GpuName = "NVIDIA GeForce RTX 4060",
                GpuVramGb = 8.0,
                RecommendAllCores = true,
                RecommendDirectX11 = true,
                RecommendHighPriority = true,
                RecommendNoSplash = true,
                RecommendWindowedMode = false,
                RecommendedCustomArguments = "-malloc=system"
            };

            var config = new LauncherConfig();
            service.ApplyOptimalFlags(config, profile);

            Assert.True(config.UseAllCores);
            Assert.True(config.UseDirectX11);
            Assert.True(config.UseHighPriority);
            Assert.True(config.NoSplash);
            Assert.False(config.WindowedMode);
            Assert.Equal("-malloc=system", config.CustomArguments);
        }
    }
}
