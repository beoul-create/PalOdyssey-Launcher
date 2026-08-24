using System.Threading.Tasks;

namespace PalLauncher.Services.Interfaces
{
    public interface IPlayerPresenceService
    {
        Task<bool> IsPlayerOnlineAsync(string steamId);
    }
}
