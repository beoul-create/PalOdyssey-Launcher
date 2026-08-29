using System;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text.Json;
using System.Threading.Tasks;

namespace PalLauncher.Services
{
    public class RemoteServerService
    {
        private readonly HttpClient _http;

        public RemoteServerService(HttpClient? httpClient = null)
        {
            _http = httpClient ?? new HttpClient();
        }

        public async Task<bool> StartRemoteServerAsync(string serverApiUrl, string adminKey)
        {
            try
            {
                using var request = new HttpRequestMessage(HttpMethod.Post, $"{serverApiUrl.TrimEnd('/')}/api/server/start");
                request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", adminKey);
                var response = await _http.SendAsync(request);
                return response.IsSuccessStatusCode;
            }
            catch { return false; }
        }

        public async Task<bool> StopRemoteServerAsync(string serverApiUrl, string adminKey)
        {
            try
            {
                using var request = new HttpRequestMessage(HttpMethod.Post, $"{serverApiUrl.TrimEnd('/')}/api/server/stop");
                request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", adminKey);
                var response = await _http.SendAsync(request);
                return response.IsSuccessStatusCode;
            }
            catch { return false; }
        }

        public async Task<ServerStatusResponse?> GetRemoteStatusAsync(string serverApiUrl)
        {
            try
            {
                var response = await _http.GetAsync($"{serverApiUrl.TrimEnd('/')}/api/server/status");
                if (!response.IsSuccessStatusCode) return null;
                string json = await response.Content.ReadAsStringAsync();
                return JsonSerializer.Deserialize<ServerStatusResponse>(json, new JsonSerializerOptions { PropertyNameCaseInsensitive = true });
            }
            catch { return null; }
        }
    }

    public class ServerStatusResponse
    {
        public bool Success { get; set; }
        public bool IsProcessRunning { get; set; }
        public bool ServerOnline { get; set; }
        public int PlayerCount { get; set; }
        public int MaxPlayers { get; set; }
    }
}
