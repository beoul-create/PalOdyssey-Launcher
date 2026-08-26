using System;
using System.Diagnostics;
using System.Threading.Tasks;
using PalLauncher.Models;

namespace PalLauncher.Services.Interfaces
{
    public class GameProcessState
    {
        public bool IsRunning { get; set; }
        public int ProcessId { get; set; }
        public int ServerProcessId { get; set; }
        public bool IsServerRunning { get; set; }
        public bool IsClientRunning { get; set; }
        public DateTime? StartTime { get; set; }
        public string ExecutablePath { get; set; } = string.Empty;
        public string Arguments { get; set; } = string.Empty;
        public string Mode { get; set; } = "Unified";
    }

    public interface ILaunchService
    {
        GameProcessState CurrentState { get; }
        bool IsGameRunning { get; }
        bool IsServerRunning { get; }
        bool IsClientRunning { get; }
        event EventHandler<GameProcessState>? ProcessStateChanged;
        event EventHandler<int>? ProcessExited;

        Task<bool> LaunchGameAsync(LauncherConfig config, GamePathInfo pathInfo);
        Task<bool> StopGameAsync();
        Task<bool> StartServerOnlyAsync(LauncherConfig config, GamePathInfo pathInfo);
        Task<bool> StopServerOnlyAsync();
        Task<bool> RestartServerOnlyAsync(LauncherConfig config, GamePathInfo pathInfo);
        bool EnsureDirectRawInputConfig(LauncherConfig config, string? gameRootPath);
        string BuildCommandLineArguments(LauncherConfig config);
        string BuildServerCommandLineArguments(LauncherConfig config);
    }
}
