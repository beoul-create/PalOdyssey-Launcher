using System;
using System.Threading;
using System.Threading.Tasks;

namespace PalLauncher.Services.Interfaces
{
    public interface ISteamAuthService
    {
        Task<SteamProfileInfo> InitiateSteamLoginAsync(int localPort = 8766, TimeSpan? timeout = null, CancellationToken ct = default);
    }
}
