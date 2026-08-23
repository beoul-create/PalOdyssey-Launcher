using System;
using System.Collections.Generic;
using System.Threading.Tasks;
using PalLauncher.Models;

namespace PalLauncher.Services.Interfaces
{
    public class CalibrationTestResult
    {
        public string TestName { get; set; } = string.Empty;
        public bool Passed { get; set; } = true;
        public string Metrics { get; set; } = string.Empty;
        public string OptimizationApplied { get; set; } = string.Empty;
    }

    public class CalibrationProgressInfo
    {
        public int Percent { get; set; }
        public string Stage { get; set; } = string.Empty;
        public string Details { get; set; } = string.Empty;
    }

    public class SystemHardwareProfile
    {
        public string CpuName { get; set; } = "Standard CPU";
        public int LogicalCores { get; set; } = Environment.ProcessorCount;
        public int PhysicalCores { get; set; } = Math.Max(1, Environment.ProcessorCount / 2);
        public double TotalRamGb { get; set; } = 16.0;
        public string GpuName { get; set; } = "Dedicated GPU";
        public double GpuVramGb { get; set; } = 6.0;
        public string PerformanceTier { get; set; } = "High Performance Rig";
        
        public string SummaryText => $"{CpuName} • {TotalRamGb:F0}GB RAM • {GpuName}";

        // Recommended Optimal Flag Settings
        public bool RecommendDirectX11 { get; set; } = true;
        public bool RecommendAllCores { get; set; } = true;
        public bool RecommendHighPriority { get; set; } = false;
        public bool RecommendNoSplash { get; set; } = true;
        public bool RecommendWindowedMode { get; set; } = false;
        public string RecommendedCustomArguments { get; set; } = "-malloc=system";
        public string RecommendationSummary { get; set; } = "Optimal multithreading and memory flags configured.";

        // Modpack & Engine Tuned Parameters
        public string RecommendedPresetName { get; set; } = "balanced";
        public int RecommendedTaskGraphTasks { get; set; } = 100;
        public int RecommendedSigScannerThreads { get; set; } = 8;
        public int RecommendedMaxBandwidth { get; set; } = 1048576;
        public int RecommendedGcIntervalSeconds { get; set; } = 60;
        public int RecommendedTrimIntervalMinutes { get; set; } = 5;
        public string EstimatedAvgFps { get; set; } = "60-80 FPS";

        public List<CalibrationTestResult> CalibrationResults { get; set; } = new();
    }

    public interface ISystemSpecService
    {
        SystemHardwareProfile CurrentProfile { get; }
        Task<SystemHardwareProfile> DetectSystemSpecsAsync();
        Task<SystemHardwareProfile> AutoCalibrateAsync(IProgress<CalibrationProgressInfo>? progress = null, string? gameInstallPath = null);
        void ApplyOptimalFlags(LauncherConfig config, SystemHardwareProfile? profile = null);
        string GenerateOptimizedModpackConfig(SystemHardwareProfile profile);
        void ApplyModpackCalibration(string? gameInstallPath, SystemHardwareProfile profile);
    }
}

