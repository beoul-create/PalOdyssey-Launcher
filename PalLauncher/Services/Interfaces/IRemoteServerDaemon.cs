using System;
using System.Threading.Tasks;
using PalLauncher.Models;

namespace PalLauncher.Services.Interfaces
{
    public class RemoteServerStatus
    {
        public bool IsOnline { get; set; }
        public bool IsServerRunning { get; set; }
        public int ProcessId { get; set; }
        public int ServerPort { get; set; } = 8211;
        public double UptimeSeconds { get; set; }
        public string ServerName { get; set; } = "PalOdyssey Realm";
        public string Version { get; set; } = "1.5.4";
        public string Message { get; set; } = "Ready";
    }

    public interface IRemoteServerDaemon : IDisposable
    {
        bool IsRunning { get; }
        int Port { get; }
        Task<bool> StartDaemonAsync(
            int port,
            string accessKey,
            Func<Task<bool>> onStartServerRequested,
            Func<Task<bool>> onStopServerRequested,
            Func<string, Task>? onWebhookServerBooting = null);
        Task StopDaemonAsync();
        ServerLiveboardInfo GetCurrentLiveboard();
        void ConfigureIdleAutoShutdown(bool enabled, int minutes);
        Func<string, string, string, double, double, Task>? OnWorldBossSpawn { get; set; }
        Func<string, string, Task>? OnWorldBossCaptured { get; set; }
    }
}
