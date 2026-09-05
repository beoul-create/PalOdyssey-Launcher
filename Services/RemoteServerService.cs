using System;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;

namespace PalLauncher.Services
{
    public class RemoteServerService : IDisposable
    {
        private readonly HttpClient _http;
        private readonly bool _ownsClient;
        private static readonly JsonSerializerOptions JsonOptions = new() { PropertyNameCaseInsensitive = true };

        public RemoteServerService(HttpClient? httpClient = null)
        {
            _ownsClient = httpClient == null;
            _http = httpClient ?? new HttpClient
            {
                Timeout = TimeSpan.FromSeconds(5)
            };
        }

        public async Task<bool> StartRemoteServerAsync(string serverApiUrl, string adminKey, CancellationToken cancellationToken = default)
        {
            try
            {
                using var request = new HttpRequestMessage(HttpMethod.Post, $"{serverApiUrl.TrimEnd('/')}/api/server/start");
                request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", adminKey);
                using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
                return response.IsSuccessStatusCode;
            }
            catch { return false; }
        }

        public async Task<bool> StopRemoteServerAsync(string serverApiUrl, string adminKey, CancellationToken cancellationToken = default)
        {
            try
            {
                using var request = new HttpRequestMessage(HttpMethod.Post, $"{serverApiUrl.TrimEnd('/')}/api/server/stop");
                request.Headers.Authorization = new AuthenticationHeaderValue("Bearer", adminKey);
                using var response = await _http.SendAsync(request, HttpCompletionOption.ResponseHeadersRead, cancellationToken);
                return response.IsSuccessStatusCode;
            }
            catch { return false; }
        }

        public async Task<ServerStatusResponse?> GetRemoteStatusAsync(string serverApiUrl, CancellationToken cancellationToken = default)
        {
            try
            {
                using var response = await _http.GetAsync(
                    $"{serverApiUrl.TrimEnd('/')}/api/server/status",
                    HttpCompletionOption.ResponseHeadersRead,
                    cancellationToken);
                if (!response.IsSuccessStatusCode) return null;
                await using var stream = await response.Content.ReadAsStreamAsync(cancellationToken);
                return await JsonSerializer.DeserializeAsync<ServerStatusResponse>(stream, JsonOptions, cancellationToken);
            }
            catch { return null; }
        }

        public void Dispose()
        {
            if (_ownsClient) _http.Dispose();
            GC.SuppressFinalize(this);
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
