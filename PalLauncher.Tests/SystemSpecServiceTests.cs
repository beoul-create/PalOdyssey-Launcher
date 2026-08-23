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

        [Fact]
        public async Task SystemSpecService_AutoCalibrateAsync_ExecutesAllBenchmarkStages()
        {
            var service = new SystemSpecService(_logService);
            int lastReportedPercent = 0;
            var progress = new System.Progress<CalibrationProgressInfo>(p =>
            {
                lastReportedPercent = p.Percent;
            });

            var profile = await service.AutoCalibrateAsync(progress);

            Assert.NotNull(profile);
            Assert.NotEmpty(profile.CalibrationResults);
            Assert.True(profile.CalibrationResults.Count >= 4);
            Assert.All(profile.CalibrationResults, res => Assert.True(res.Passed));
            Assert.False(string.IsNullOrWhiteSpace(profile.EstimatedAvgFps));
        }

        [Theory]
        [InlineData("NVIDIA GeForce RTX 4080", 32.0, 16.0, 8, 16, "Ultra / Enthusiast Rig", false, "-malloc=system -useperfthreads -NoAsyncLoadingThread")]
        [InlineData("NVIDIA GeForce RTX 3060", 16.0, 6.0, 6, 12, "High Performance Gaming Rig", true, "-malloc=system -useperfthreads")]
        [InlineData("Intel Iris Xe Graphics", 8.0, 1.0, 4, 8, "Balanced / Efficiency Rig (APU/Mobile)", true, "-lowmemory")]
        public void SystemSpecService_ComputeOptimalFlags_AccommodatesDifferentSpecs(
            string gpuName, double ramGb, double vramGb, int pCores, int lCores,
            string expectedTier, bool expectedDx11, string expectedArgs)
        {
            var service = new SystemSpecService(_logService);
            var profile = new SystemHardwareProfile
            {
                GpuName = gpuName,
                TotalRamGb = ramGb,
                GpuVramGb = vramGb,
                PhysicalCores = pCores,
                LogicalCores = lCores
            };

            service.ComputeOptimalFlags(profile);

            Assert.Equal(expectedTier, profile.PerformanceTier);
            Assert.Equal(expectedDx11, profile.RecommendDirectX11);
            Assert.Equal(expectedArgs, profile.RecommendedCustomArguments);
        }

        [Fact]
        public void SystemSpecService_GenerateOptimizedModpackConfig_ProducesValidJsonWithCorrectTierSettings()
        {
            var service = new SystemSpecService(_logService);
            var profile = new SystemHardwareProfile
            {
                PerformanceTier = "Ultra / Enthusiast Rig",
                RecommendedPresetName = "ultra_optimal",
                RecommendedTaskGraphTasks = 120,
                RecommendedSigScannerThreads = 12,
                RecommendedMaxBandwidth = 2097152,
                RecommendedGcIntervalSeconds = 90,
                RecommendedTrimIntervalMinutes = 3,
                RecommendDirectX11 = false,
                TotalRamGb = 32.0,
                LogicalCores = 12
            };

            string json = service.GenerateOptimizedModpackConfig(profile);

            Assert.Contains("\"preset\": \"ultra_optimal\"", json);
            Assert.Contains("\"maxBandwidth\": 2097152", json);
            Assert.Contains("\"taskGraphTasksPerTick\": 120", json);
            Assert.Contains("\"asyncCompute\": true", json);
            Assert.Contains("\"highPollingRateSupport\": true", json);
            Assert.Contains("\"disableSmoothing\": true", json);
            Assert.Contains("\"disableAcceleration\": true", json);
        }
    }
}

