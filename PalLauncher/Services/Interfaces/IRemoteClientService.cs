using System;
using System.Threading.Tasks;
using PalLauncher.Models;

namespace PalLauncher.Services.Interfaces
{
    public interface IRemoteClientService
    {
        Task<RemoteServerStatus> QueryServerStatusAsync(string host, int managementPort, int timeoutMs = 2500);
        Task<ServerLiveboardInfo> FetchLiveboardAsync(string host, int managementPort, int timeoutMs = 2500);
        Task<bool> RequestRemoteServerStartAsync(string host, int managementPort, string accessKey, IProgress<string>? progress = null, int timeoutSeconds = 25);
        Task<bool> RequestRemoteServerStopAsync(string host, int managementPort, string accessKey);
    }
}
