using System;
using System.Collections.Generic;
using System.Threading;
using System.Threading.Tasks;
using PalLauncher.Models;

namespace PalLauncher.Services.Interfaces
{
    public interface IUpdateService
    {
        ModManifest? CurrentManifest { get; }
        bool IsCheckingUpdates { get; }
        bool IsUpdating { get; }

        Task<ModManifest?> FetchManifestAsync(string manifestUrl, CancellationToken cancellationToken = default);
        Task<List<ModInfo>> CheckForUpdatesAsync(string manifestUrl, string gameRootPath, CancellationToken cancellationToken = default);
        Task<bool> VerifyModFileAsync(ModInfo mod, string gameRootPath);
        Task<bool> DownloadAndInstallModAsync(ModInfo mod, string gameRootPath, IProgress<UpdateProgressInfo>? progress = null, CancellationToken cancellationToken = default);
        Task<int> DownloadAndInstallAllUpdatesAsync(IEnumerable<ModInfo> mods, string gameRootPath, IProgress<UpdateProgressInfo>? progress = null, CancellationToken cancellationToken = default);
        string ComputeFileSha256(string filePath);
    }
}
