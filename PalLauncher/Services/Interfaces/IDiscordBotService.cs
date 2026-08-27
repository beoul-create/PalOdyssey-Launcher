using System;
using System.Threading.Tasks;
using PalLauncher.Models;

namespace PalLauncher.Services.Interfaces
{
    public interface IDiscordBotService : IDisposable
    {
        bool IsRunning { get; }
        string BotUsername { get; }
        Task<bool> StartAsync(
            string token,
            string prefix,
            string? channelId,
            string? adminRoleId,
            Func<Task<bool>> onStartServer,
            Func<Task<bool>> onStopServer,
            Func<ServerLiveboardInfo> getLiveboard);
        Task StopAsync();
        Task BroadcastServerBootingAsync(string triggeredBy = "Remote Webhook");
        Task BroadcastServerOnlineAsync();
        Task BroadcastWorldBossSpawnAsync(string palName, string location, string aura, double x, double y);
        Task BroadcastWorldBossCapturedAsync(string palName, string capturedBy);
        Task BroadcastWorldBossKilledAsync(string palName, string killedBy, string schematicName);
        Task SetupChangelogRoleMessageAsync(string channelId = "1534308427080273990");
        Task BroadcastChangelogAsync(string title, string description, string channelId = "1542544366176968714", bool pingRole = true);
        Task PublishLatestUpdateChangelogAsync(string channelId = "1542544366176968714", bool pingRole = true);
    }
}
