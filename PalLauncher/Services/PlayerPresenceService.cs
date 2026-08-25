using System;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;
using PalLauncher.Models;
using PalLauncher.Services.Interfaces;

namespace PalLauncher.Services
{
    public class PlayerPresenceService : IPlayerPresenceService
    {
        private readonly HttpClient _httpClient;
        private readonly IConfigService _configService;
        private readonly ILogService _logService;

        public PlayerPresenceService(IConfigService configService, ILogService logService, HttpClient? httpClient = null)
        {
            _configService = configService;
            _logService = logService;
            _httpClient = httpClient ?? new HttpClient();
        }

        public async Task<bool> IsPlayerOnlineAsync(string steamId)
        {
            if (string.IsNullOrWhiteSpace(steamId)) return false;

            var config = _configService.Config;
            string password = config.ServerAdminPassword ?? "";
            int port = config.RestApiPort > 0 ? config.RestApiPort : 8212;

            try
            {
                var request = new HttpRequestMessage(HttpMethod.Get, $"http://127.0.0.1:{port}/v1/api/players");
                
                // Palworld REST API uses Basic Auth with username "admin"
                string credentials = Convert.ToBase64String(Encoding.ASCII.GetBytes($"admin:{password}"));
                request.Headers.Authorization = new AuthenticationHeaderValue("Basic", credentials);
                // Also add X-PalOdyssey-Key in case it's going through the launcher daemon proxy instead of direct
                request.Headers.Add("X-PalOdyssey-Key", config.RemoteAccessKey ?? LauncherConfig.DefaultRealmAccessKey);

                using var cts = new System.Threading.CancellationTokenSource(TimeSpan.FromSeconds(5));
                var response = await _httpClient.SendAsync(request, cts.Token);
                
                if (response.IsSuccessStatusCode)
                {
                    string json = await response.Content.ReadAsStringAsync();
                    
                    using var doc = JsonDocument.Parse(json);
                    if (doc.RootElement.TryGetProperty("players", out var playersArray) && playersArray.ValueKind == JsonValueKind.Array)
                    {
                        foreach (var player in playersArray.EnumerateArray())
                        {
                            string? onlineUserId = null;
                            string? onlineAccountId = null;
                            
                            if (player.TryGetProperty("userId", out var uProp)) onlineUserId = uProp.GetString();
                            if (player.TryGetProperty("accountId", out var aProp)) onlineAccountId = aProp.GetString();

                            bool matchUser = !string.IsNullOrWhiteSpace(onlineUserId) && 
                                (onlineUserId.Equals(steamId, StringComparison.OrdinalIgnoreCase) || 
                                 onlineUserId.Equals($"Steam_{steamId}", StringComparison.OrdinalIgnoreCase));
                                 
                            bool matchAccount = !string.IsNullOrWhiteSpace(onlineAccountId) && 
                                (onlineAccountId.Equals(steamId, StringComparison.OrdinalIgnoreCase) || 
                                 onlineAccountId.Equals($"Steam_{steamId}", StringComparison.OrdinalIgnoreCase));

                            if (matchUser || matchAccount)
                            {
                                return true;
                            }
                        }
                    }
                }
                else
                {
                    _logService.LogWarning($"Failed to query presence API. Status: {response.StatusCode}", "PlayerPresence");
                }
            }
            catch (Exception ex)
            {
                _logService.LogWarning($"Error querying player presence: {ex.Message}", "PlayerPresence");
            }

            return false;
        }
    }
}
