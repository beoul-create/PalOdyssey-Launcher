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
                            string? onlinePlayerId = null;
                            string? onlineUserId = null;
                            string? onlineAccountId = null;
                            string? onlineName = null;
                            
                            if (player.TryGetProperty("playerId", out var pProp)) onlinePlayerId = pProp.GetString();
                            if (player.TryGetProperty("userId", out var uProp)) onlineUserId = uProp.GetString();
                            if (player.TryGetProperty("accountId", out var aProp)) onlineAccountId = aProp.GetString();
                            if (player.TryGetProperty("name", out var nProp)) onlineName = nProp.GetString();

                            string cleanQuery = steamId.Trim();
                            string cleanNoPrefix = cleanQuery.StartsWith("steam_", StringComparison.OrdinalIgnoreCase) 
                                ? cleanQuery.Substring(6) 
                                : cleanQuery;

                            bool matchPlayerId = !string.IsNullOrWhiteSpace(onlinePlayerId) &&
                                (onlinePlayerId.Equals(cleanQuery, StringComparison.OrdinalIgnoreCase) ||
                                 onlinePlayerId.Replace("-", "").Equals(cleanQuery.Replace("-", ""), StringComparison.OrdinalIgnoreCase));

                            bool matchUser = !string.IsNullOrWhiteSpace(onlineUserId) && 
                                (onlineUserId.Equals(cleanQuery, StringComparison.OrdinalIgnoreCase) || 
                                 onlineUserId.Equals($"steam_{cleanNoPrefix}", StringComparison.OrdinalIgnoreCase) ||
                                 onlineUserId.Equals(cleanNoPrefix, StringComparison.OrdinalIgnoreCase));
                                 
                            bool matchAccount = !string.IsNullOrWhiteSpace(onlineAccountId) && 
                                (onlineAccountId.Equals(cleanQuery, StringComparison.OrdinalIgnoreCase) || 
                                 onlineAccountId.Equals($"steam_{cleanNoPrefix}", StringComparison.OrdinalIgnoreCase) ||
                                 onlineAccountId.Equals(cleanNoPrefix, StringComparison.OrdinalIgnoreCase));

                            bool matchName = !string.IsNullOrWhiteSpace(onlineName) &&
                                onlineName.Equals(cleanQuery, StringComparison.OrdinalIgnoreCase);

                            if (matchPlayerId || matchUser || matchAccount || matchName)
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
