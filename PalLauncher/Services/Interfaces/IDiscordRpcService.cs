using System;
using System.Threading.Tasks;

namespace PalLauncher.Services.Interfaces
{
    public interface IDiscordRpcService : IDisposable
    {
        bool IsConnected { get; }
        Task InitializeAsync(string? applicationId = null);
        Task UpdatePresenceAsync(
            string details,
            string state,
            bool isPlaying = false,
            int? targetPid = null,
            string? largeImageKey = null,
            string? largeImageText = null,
            string? smallImageKey = null,
            string? smallImageText = null,
            (string label, string url)[]? buttons = null);
        Task ClearPresenceAsync();
    }
}
