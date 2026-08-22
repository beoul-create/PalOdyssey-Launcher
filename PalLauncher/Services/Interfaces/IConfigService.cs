using System.Threading.Tasks;
using PalLauncher.Models;

namespace PalLauncher.Services.Interfaces
{
    public interface IConfigService
    {
        LauncherConfig Config { get; }
        Task<LauncherConfig> LoadConfigAsync();
        Task SaveConfigAsync(LauncherConfig? config = null);
        string GetConfigFilePath();
    }
}
