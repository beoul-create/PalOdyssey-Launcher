using System;
using System.Threading.Tasks;

namespace PalLauncher.Services.Interfaces
{
    public interface IDiscordRpcService : IDisposable
    {
        bool IsConnected { get; }
        Task InitializeAsync(string? applicationId = null);
        Task UpdatePresenceAsync(string details, string state, bool isPlaying = false);
        Task ClearPresenceAsync();
    }
}
