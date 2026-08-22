using System;
using System.IO;
using System.Management;
using System.Runtime.InteropServices;
using System.Threading.Tasks;
using PalLauncher.Models;
using PalLauncher.Services.Interfaces;

namespace PalLauncher.Services
{
    public class SystemSpecService : ISystemSpecService
    {
        private readonly ILogService _logService;
        private SystemHardwareProfile _currentProfile = new();

        public SystemHardwareProfile CurrentProfile => _currentProfile;

        [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
        private class MEMORYSTATUSEX
        {
            public uint dwLength;
            public uint dwMemoryLoad;
            public ulong ullTotalPhys;
            public ulong ullAvailPhys;
            public ulong ullTotalPageFile;
            public ulong ullAvailPageFile;
            public ulong ullTotalVirtual;
            public ulong ullAvailVirtual;
            public ulong ullAvailExtendedVirtual;

            public MEMORYSTATUSEX()
            {
                dwLength = (uint)Marshal.SizeOf(typeof(MEMORYSTATUSEX));
            }
        }

        [DllImport("kernel32.dll", CharSet = CharSet.Auto, SetLastError = true)]
        [return: MarshalAs(UnmanagedType.Bool)]
        private static extern bool GlobalMemoryStatusEx([In, Out] MEMORYSTATUSEX lpBuffer);

        public SystemSpecService(ILogService logService)
        {
            _logService = logService;
        }

        public async Task<SystemHardwareProfile> DetectSystemSpecsAsync()
        {
            return await Task.Run(() =>
            {
                var profile = new SystemHardwareProfile();

                try
                {
                    // 1. Detect CPU
                    using (var searcher = new ManagementObjectSearcher("SELECT Name, NumberOfCores, NumberOfLogicalProcessors FROM Win32_Processor"))
                    {
                        foreach (ManagementObject obj in searcher.Get())
                        {
                            profile.CpuName = (obj["Name"]?.ToString() ?? "Standard CPU").Trim();
                            if (int.TryParse(obj["NumberOfCores"]?.ToString(), out int cores) && cores > 0)
                            {
                                profile.PhysicalCores = cores;
                            }
                            if (int.TryParse(obj["NumberOfLogicalProcessors"]?.ToString(), out int threads) && threads > 0)
                            {
                                profile.LogicalCores = threads;
                            }
                            break;
                        }
                    }
                }
                catch (Exception ex)
                {
                    _logService.LogWarning("WMI CPU detection fallback triggered.", "HardwareDetector", ex.Message);
                    profile.CpuName = Environment.GetEnvironmentVariable("PROCESSOR_IDENTIFIER") ?? "x86_64 CPU";
                    profile.LogicalCores = Environment.ProcessorCount;
                    profile.PhysicalCores = Math.Max(1, Environment.ProcessorCount / 2);
                }

                try
                {
                    // 2. Detect RAM via Win32 API for 100% precision
                    var memStatus = new MEMORYSTATUSEX();
                    if (GlobalMemoryStatusEx(memStatus))
                    {
                        profile.TotalRamGb = Math.Round((double)memStatus.ullTotalPhys / (1024 * 1024 * 1024), 1);
                    }
                    else
                    {
                        profile.TotalRamGb = 16.0;
                    }
                }
                catch
                {
                    profile.TotalRamGb = 16.0;
                }

                try
                {
                    // 3. Detect GPU
                    using (var searcher = new ManagementObjectSearcher("SELECT Name, AdapterRAM FROM Win32_VideoController"))
                    {
                        foreach (ManagementObject obj in searcher.Get())
                        {
                            string name = obj["Name"]?.ToString() ?? "";
                            if (!string.IsNullOrWhiteSpace(name) && !name.Contains("Basic", StringComparison.OrdinalIgnoreCase))
                            {
                                profile.GpuName = name.Trim();
                                if (ulong.TryParse(obj["AdapterRAM"]?.ToString(), out ulong vramBytes) && vramBytes > 0)
                                {
                                    profile.GpuVramGb = Math.Round((double)vramBytes / (1024 * 1024 * 1024), 1);
                                }
                                break;
                            }
                        }
                    }
                }
                catch (Exception ex)
                {
                    _logService.LogWarning("WMI GPU detection fallback triggered.", "HardwareDetector", ex.Message);
                    profile.GpuName = "Direct3D 11/12 Compatible GPU";
                    profile.GpuVramGb = 4.0;
                }

                // 4. Calculate Optimal Startup Flags based on detected specifications
                ComputeOptimalFlags(profile);

                _currentProfile = profile;
                _logService.LogInfo($"Detected Hardware: {profile.SummaryText} [Tier: {profile.PerformanceTier}]", "HardwareDetector");
                return profile;
            });
        }

        private void ComputeOptimalFlags(SystemHardwareProfile profile)
        {
            // Multithreading
            profile.RecommendAllCores = profile.LogicalCores >= 4;

            // DirectX 11 for max mod stability and frame consistency
            profile.RecommendDirectX11 = true;

            // High Priority if 6 or more physical cores available
            profile.RecommendHighPriority = profile.PhysicalCores >= 6;

            // Skip splash video
            profile.RecommendNoSplash = true;
            profile.RecommendWindowedMode = false;

            // Memory allocator optimization (-malloc=system avoids UE5 memory heap fragmentation on >= 16GB RAM)
            if (profile.TotalRamGb >= 16.0)
            {
                profile.RecommendedCustomArguments = "-malloc=system";
                profile.PerformanceTier = "Ultra High Performance Rig";
                profile.RecommendationSummary = $"Tuned for {profile.PhysicalCores}C/{profile.LogicalCores}T CPU & {profile.TotalRamGb:F0}GB RAM with System Low-Fragmentation Heap & All-Cores Multithreading.";
            }
            else if (profile.TotalRamGb >= 8.0)
            {
                profile.RecommendedCustomArguments = "";
                profile.PerformanceTier = "High Performance Gaming Rig";
                profile.RecommendationSummary = $"Tuned for {profile.LogicalCores} threads & {profile.TotalRamGb:F0}GB RAM with multithreading optimization.";
            }
            else
            {
                profile.RecommendedCustomArguments = "-lowmemory";
                profile.PerformanceTier = "Balanced Efficiency Rig";
                profile.RecommendationSummary = "Configured for optimal memory efficiency.";
            }
        }

        public void ApplyOptimalFlags(LauncherConfig config, SystemHardwareProfile? profile = null)
        {
            var target = profile ?? _currentProfile;
            config.UseAllCores = target.RecommendAllCores;
            config.UseDirectX11 = target.RecommendDirectX11;
            config.NoSplash = target.RecommendNoSplash;
            config.UseHighPriority = target.RecommendHighPriority;
            config.WindowedMode = target.RecommendWindowedMode;

            if (!string.IsNullOrWhiteSpace(target.RecommendedCustomArguments))
            {
                config.CustomArguments = target.RecommendedCustomArguments;
            }

            _logService.LogSuccess($"Applied automated startup flags: -USEALLAVAILABLECORES={config.UseAllCores}, -dx11={config.UseDirectX11}, -high={config.UseHighPriority}, args='{config.CustomArguments}'", "Optimizer");
        }
    }
}
