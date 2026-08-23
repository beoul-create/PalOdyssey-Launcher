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
    public class HardwareTierSpec
    {
        public string TierName { get; set; } = string.Empty;
        public string Era { get; set; } = string.Empty;
        public string CpuName { get; set; } = string.Empty;
        public int LogicalCores { get; set; }
        public int PhysicalCores { get; set; }
        public double TotalRamGb { get; set; }
        public string GpuName { get; set; } = string.Empty;
        public double GpuVramGb { get; set; }
        public string StorageType { get; set; } = string.Empty;
        public int SimulatedComputeIterations { get; set; }
    }

    [Collection("DaemonTests")]
    public class MultiGenerationHardwareBenchmarkTests
    {
        private readonly ITestOutputHelper _output;
        private readonly LogService _logService = new();

        public MultiGenerationHardwareBenchmarkTests(ITestOutputHelper output)
        {
            _output = output;
        }

        public static IEnumerable<object[]> GetHardwareGenerations()
        {
            yield return new object[]
            {
                new HardwareTierSpec
                {
                    TierName = "Tier 1: Legacy / Budget (~2015-2018)",
                    Era = "DDR3/DDR4, 4-Core CPU, GTX 1050 (Low VRAM)",
                    CpuName = "Intel Core i5-6400 @ 2.70GHz",
                    LogicalCores = 4,
                    PhysicalCores = 4,
                    TotalRamGb = 8.0,
                    GpuName = "NVIDIA GeForce GTX 1050",
                    GpuVramGb = 2.0,
                    StorageType = "SATA HDD / 2.5\" SSD",
                    SimulatedComputeIterations = 150_000
                }
            };

            yield return new object[]
            {
                new HardwareTierSpec
                {
                    TierName = "Tier 2: Handheld / Mobile APU (~2022-2024)",
                    Era = "Steam Deck / ROG Ally / LPDDR5 Unified APU",
                    CpuName = "AMD Custom APU 0405 (Zen 2 / 8 Threads)",
                    LogicalCores = 8,
                    PhysicalCores = 4,
                    TotalRamGb = 16.0,
                    GpuName = "AMD Radeon Graphics (RDNA 2 APU)",
                    GpuVramGb = 4.0,
                    StorageType = "PCIe Gen3 NVMe",
                    SimulatedComputeIterations = 200_000
                }
            };

            yield return new object[]
            {
                new HardwareTierSpec
                {
                    TierName = "Tier 3: Mainstream Mid-Range (~2019-2021)",
                    Era = "DDR4, 6-Core / 12-Thread, GTX 1660 / RTX 2060",
                    CpuName = "AMD Ryzen 5 3600 (6 Cores / 12 Threads)",
                    LogicalCores = 12,
                    PhysicalCores = 6,
                    TotalRamGb = 16.0,
                    GpuName = "NVIDIA GeForce RTX 2060",
                    GpuVramGb = 6.0,
                    StorageType = "PCIe Gen3 NVMe",
                    SimulatedComputeIterations = 300_000
                }
            };

            yield return new object[]
            {
                new HardwareTierSpec
                {
                    TierName = "Tier 4: Modern High-Performance (~2022-2024)",
                    Era = "DDR4/DDR5, 8-Core / 16-Thread, RTX 3070 / RTX 4060",
                    CpuName = "AMD Ryzen 7 5700X (8 Cores / 16 Threads)",
                    LogicalCores = 16,
                    PhysicalCores = 8,
                    TotalRamGb = 32.0,
                    GpuName = "NVIDIA GeForce RTX 4060",
                    GpuVramGb = 8.0,
                    StorageType = "PCIe Gen4 NVMe",
                    SimulatedComputeIterations = 450_000
                }
            };

            yield return new object[]
            {
                new HardwareTierSpec
                {
                    TierName = "Tier 5: Next-Gen Enthusiast (~2024-2026)",
                    Era = "DDR5 6000MHz, 16+ Cores, RTX 4080 / RTX 4090",
                    CpuName = "AMD Ryzen 7 7800X3D (8C/16T 3D V-Cache)",
                    LogicalCores = 16,
                    PhysicalCores = 8,
                    TotalRamGb = 64.0,
                    GpuName = "NVIDIA GeForce RTX 4090",
                    GpuVramGb = 24.0,
                    StorageType = "PCIe Gen5 NVMe (10,000 MB/s)",
                    SimulatedComputeIterations = 600_000
                }
            };
        }

        [Theory]
        [MemberData(nameof(GetHardwareGenerations))]
        public async Task Benchmark_HardwareGeneration_EvaluateSpeedAndOptimizations(HardwareTierSpec spec)
        {
            var specService = new SystemSpecService(_logService);
            var launchService = new LaunchService(_logService);

            var profile = new SystemHardwareProfile
            {
                CpuName = spec.CpuName,
                LogicalCores = spec.LogicalCores,
                PhysicalCores = spec.PhysicalCores,
                TotalRamGb = spec.TotalRamGb,
                GpuName = spec.GpuName,
                GpuVramGb = spec.GpuVramGb
            };

            // 1. Compute Flags
            specService.ComputeOptimalFlags(profile);

            // 2. Multithreaded CPU Dispatch Benchmark
            var cpuSw = Stopwatch.StartNew();
            int threads = spec.LogicalCores;
            var tasks = new Task[threads];
            for (int t = 0; t < threads; t++)
            {
                tasks[t] = Task.Run(() =>
                {
                    double acc = 1.0;
                    for (int i = 0; i < spec.SimulatedComputeIterations; i++)
                    {
                        acc = Math.Sqrt(acc * 1.00002) + Math.Cos(i);
                    }
                });
            }
            await Task.WhenAll(tasks);
            cpuSw.Stop();

            // 3. Memory Allocation Headroom & Garbage Collection Simulation
            var memSw = Stopwatch.StartNew();
            int allocChunks = (int)(spec.TotalRamGb >= 32.0 ? 80 : (spec.TotalRamGb >= 16.0 ? 40 : 15));
            var buffers = new List<byte[]>();
            for (int i = 0; i < allocChunks; i++)
            {
                buffers.Add(new byte[512 * 1024]); // 512KB chunks
            }
            long allocatedBytes = allocChunks * 512 * 1024;
            buffers.Clear();
            GC.Collect(1, GCCollectionMode.Optimized);
            memSw.Stop();

            // 4. Generate Modpack Lua Optimization Json
            string modpackConfig = specService.GenerateOptimizedModpackConfig(profile);

            // 5. Build Final Launch Command
            var config = new LauncherConfig
            {
                GamePath = @"C:\SteamLibrary\steamapps\common\Palworld",
                LaunchMode = "Client",
                AutoJoinServer = true,
                ServerIp = "palodyssey.duckdns.org",
                ServerPort = 57294,
                UseDirectX11 = profile.RecommendDirectX11,
                UseAllCores = profile.RecommendAllCores,
                NoSplash = profile.RecommendNoSplash,
                UseHighPriority = profile.RecommendHighPriority,
                CustomArguments = profile.RecommendedCustomArguments
            };
            string finalArgs = launchService.BuildCommandLineArguments(config);

            _output.WriteLine("==========================================================================");
            _output.WriteLine($"  ⚡ {spec.TierName.ToUpper()}");
            _output.WriteLine($"  Era/Class: {spec.Era}");
            _output.WriteLine("--------------------------------------------------------------------------");
            _output.WriteLine($"  💻 Hardware: {spec.CpuName} ({spec.PhysicalCores}C/{spec.LogicalCores}T) | {spec.TotalRamGb:F0}GB RAM | {spec.GpuName} ({spec.GpuVramGb:F0}GB VRAM)");
            _output.WriteLine($"  ⚙️ Calibrated Tier: {profile.PerformanceTier}");
            _output.WriteLine($"  🎯 Estimated Target: {profile.EstimatedAvgFps}");
            _output.WriteLine($"  ⏱️ Multithreaded Dispatch Time: {cpuSw.ElapsedMilliseconds} ms ({threads} threads)");
            _output.WriteLine($"  ⏱️ Heap Allocation/GC Time: {memSw.Elapsed.TotalMilliseconds:F2} ms ({allocatedBytes / 1024 / 1024} MB simulated)");
            _output.WriteLine($"  🔧 UE4SS SigScanner Threads: {profile.RecommendedSigScannerThreads} | TaskGraph Tasks: {profile.RecommendedTaskGraphTasks}");
            _output.WriteLine($"  🧹 RAM Trim Interval: {profile.RecommendedTrimIntervalMinutes}m | GC Interval: {profile.RecommendedGcIntervalSeconds}s");
            _output.WriteLine($"  🚀 Applied Launch Command Line: {finalArgs}");
            _output.WriteLine("==========================================================================\n");

            Assert.False(string.IsNullOrWhiteSpace(profile.PerformanceTier));
            Assert.False(string.IsNullOrWhiteSpace(finalArgs));
        }
    }
}
