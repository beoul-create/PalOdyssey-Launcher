using System.Threading.Tasks;
using PalLauncher.Models;

namespace PalLauncher.Services.Interfaces
{
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
    }

    public interface ISystemSpecService
    {
        SystemHardwareProfile CurrentProfile { get; }
        Task<SystemHardwareProfile> DetectSystemSpecsAsync();
        void ApplyOptimalFlags(LauncherConfig config, SystemHardwareProfile? profile = null);
    }
}
