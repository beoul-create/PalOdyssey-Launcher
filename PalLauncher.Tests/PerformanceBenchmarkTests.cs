using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Threading.Tasks;
using PalLauncher.Models;
using PalLauncher.Services;
using PalLauncher.Services.Interfaces;
using Xunit;
using Xunit.Abstractions;

namespace PalLauncher.Tests
{
    public class PerformanceBenchmarkTests
    {
        private readonly ITestOutputHelper _output;
        private readonly LogService _logService = new();

        public PerformanceBenchmarkTests(ITestOutputHelper output)
        {
            _output = output;
        }

        [Theory]
        [InlineData(4, 8.0, 3.0, "GTX 1050 Ti", "Balanced / Efficiency Rig (APU/Mobile)", "efficiency_max")]
        [InlineData(6, 16.0, 6.0, "RTX 3060", "High Performance Gaming Rig", "balanced")]
        [InlineData(16, 32.0, 16.0, "RTX 4080", "Ultra / Enthusiast Rig", "ultra_optimal")]
        public async Task StressTest_HardwareTiersAndGraphicalPresets(
            int cores,
            double ramGb,
            double vramGb,
            string gpuName,
            string expectedTier,
            string expectedPreset)
        {
            var specService = new SystemSpecService(_logService);
            var mockProfile = new SystemHardwareProfile
            {
                LogicalCores = cores,
                PhysicalCores = Math.Max(2, cores / 2),
                TotalRamGb = ramGb,
                GpuName = gpuName,
                GpuVramGb = vramGb,
                CpuName = $"Benchmark Simulated {cores}-Core Processor"
            };

            // 1. Compute Flags
            specService.ComputeOptimalFlags(mockProfile);

            Assert.Equal(expectedTier, mockProfile.PerformanceTier);
            Assert.Equal(expectedPreset, mockProfile.RecommendedPresetName);

            // 2. CPU Multithread Stress Benchmark
            var sw = Stopwatch.StartNew();
            int threadCount = mockProfile.LogicalCores;
            var tasks = new Task[threadCount];
            for (int t = 0; t < threadCount; t++)
            {
                tasks[t] = Task.Run(() =>
                {
                    double acc = 1.0;
                    for (int i = 0; i < 200_000; i++)
                    {
                        acc = Math.Sqrt(acc * 1.00001) + Math.Sin(i);
                    }
                });
            }
            await Task.WhenAll(tasks);
            sw.Stop();

            // 3. Memory Allocation & GC Stress
            long beforeMem = GC.GetTotalMemory(true);
            var bufferList = new List<byte[]>();
            int allocChunks = (int)(ramGb >= 16.0 ? 50 : 20);
            for (int i = 0; i < allocChunks; i++)
            {
                bufferList.Add(new byte[1024 * 512]); // 512 KB per chunk
            }
            long peakMem = GC.GetTotalMemory(false);
            bufferList.Clear();
            GC.Collect();
            long postGcMem = GC.GetTotalMemory(true);

            // 4. Modpack Lua Config Generation
            string luaJson = specService.GenerateOptimizedModpackConfig(mockProfile);
            Assert.False(string.IsNullOrWhiteSpace(luaJson));
            Assert.Contains(expectedPreset, luaJson);

            _output.WriteLine($"--- BENCHMARK REPORT [{expectedTier}] ---");
            _output.WriteLine($"Hardware: {cores}T / {ramGb:F0}GB RAM / {gpuName} ({vramGb:F0}GB VRAM)");
            _output.WriteLine($"Preset: {expectedPreset} | Estimated FPS: {mockProfile.EstimatedAvgFps}");
            _output.WriteLine($"CPU Compute Time ({threadCount} threads): {sw.ElapsedMilliseconds} ms");
            _output.WriteLine($"Memory Headroom: Peak +{(peakMem - beforeMem) / 1024} KB, Post-GC Delta {(postGcMem - beforeMem) / 1024} KB");
            _output.WriteLine($"Applied Arguments: {mockProfile.RecommendedCustomArguments}");
            _output.WriteLine($"---------------------------------------------------");
        }

        [Fact]
        public async Task StressTest_AutoCalibrateLiveSystemAndVerifyOutputIntegrity()
        {
            var specService = new SystemSpecService(_logService);
            var progressReports = new List<CalibrationProgressInfo>();
            var progress = new Progress<CalibrationProgressInfo>(report =>
            {
                progressReports.Add(report);
            });

            var profile = await specService.AutoCalibrateAsync(progress, @"C:\SteamLibrary\steamapps\common\Palworld");

            Assert.NotNull(profile);
            Assert.True(profile.CalibrationResults.Count >= 4, "Must complete all 4 calibration stages");
            Assert.True(profile.LogicalCores > 0);
            Assert.True(profile.TotalRamGb > 0);

            _output.WriteLine($"LIVE SYSTEM CALIBRATED:");
            _output.WriteLine($"Tier: {profile.PerformanceTier}");
            _output.WriteLine($"Target: {profile.EstimatedAvgFps}");
            _output.WriteLine($"Preset: {profile.RecommendedPresetName}");
            _output.WriteLine($"Arguments: {profile.RecommendedCustomArguments}");

            foreach (var result in profile.CalibrationResults)
            {
                _output.WriteLine($"  ✓ [{result.TestName}]: {result.Metrics} -> {result.OptimizationApplied}");
                Assert.True(result.Passed);
            }
        }
    }
}
