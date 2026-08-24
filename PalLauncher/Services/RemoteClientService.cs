using System;
using System.Net.Http;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using PalLauncher.Models;
using PalLauncher.Services.Interfaces;

namespace PalLauncher.Services
{
    public class RemoteClientService : IRemoteClientService
    {
        private readonly ILogService _logService;
        private static readonly HttpClient _httpClient = new HttpClient
        {
            Timeout = TimeSpan.FromSeconds(6)
        };

        public RemoteClientService(ILogService logService)
        {
            _logService = logService;
        }

        private static string ResolveBaseUrl(string host, int managementPort)
        {
            int port = managementPort > 0 ? managementPort : LauncherConfig.OfficialManagementPort;
            string cleanHost = string.IsNullOrWhiteSpace(host) ? LauncherConfig.OfficialServerHost : host.Trim();

            if (cleanHost.StartsWith("http://", StringComparison.OrdinalIgnoreCase) ||
                cleanHost.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
            {
                return cleanHost.TrimEnd('/');
            }

            return $"http://{cleanHost}:{port}";
        }

        public async Task<RemoteServerStatus> QueryServerStatusAsync(string host, int managementPort, int timeoutMs = 2500)
        {
            string baseUrl = ResolveBaseUrl(host, managementPort);
            using var cts = new CancellationTokenSource(timeoutMs);

            try
            {
                var response = await _httpClient.GetAsync($"{baseUrl}/api/status", cts.Token);
                if (response.IsSuccessStatusCode)
                {
                    string json = await response.Content.ReadAsStringAsync(cts.Token);
                    var status = JsonSerializer.Deserialize<RemoteServerStatus>(json, new JsonSerializerOptions
                    {
                        PropertyNameCaseInsensitive = true
                    });

                    if (status != null)
                    {
                        status.IsOnline = true;
                        return status;
                    }
                }
            }
            catch
            {
                // Host daemon is currently offline or unreachable
            }

            // Check if local dedicated server process is running
            if (IsLocalServerRunning())
            {
                return new RemoteServerStatus
                {
                    IsOnline = true,
                    IsServerRunning = true,
                    ServerPort = 8211,
                    ServerName = "PalOdyssey Realm",
                    Message = "Local Dedicated Server Active"
                };
            }

            return new RemoteServerStatus
            {
                IsOnline = false,
                IsServerRunning = false,
                ServerPort = 8211,
                ServerName = "PalOdyssey Realm",
                Message = "Server Offline (Standby)"
            };
        }

        public async Task<ServerLiveboardInfo> FetchLiveboardAsync(string host, int managementPort, int timeoutMs = 2500)
        {
            string baseUrl = ResolveBaseUrl(host, managementPort);
            using var cts = new CancellationTokenSource(timeoutMs);

            try
            {
                var response = await _httpClient.GetAsync($"{baseUrl}/api/liveboard", cts.Token);
                if (response.IsSuccessStatusCode)
                {
                    string json = await response.Content.ReadAsStringAsync(cts.Token);
                    var liveboard = JsonSerializer.Deserialize<ServerLiveboardInfo>(json, new JsonSerializerOptions
                    {
                        PropertyNameCaseInsensitive = true
                    });

                    if (liveboard != null)
                    {
                        return liveboard;
                    }
                }
            }
            catch
            {
                // Host daemon offline
            }

            // Local fallback
            if (IsLocalServerRunning())
            {
                return new ServerLiveboardInfo
                {
                    IsOnline = true,
                    IsServerRunning = true,
                    ServerAddress = "127.0.0.1:8211",
                    ServerName = "PalOdyssey Realm",
                    PlayerCount = 0,
                    MaxPlayers = 32,
                    UptimeSeconds = 1,
                    Version = "1.5.4"
                };
            }

            return new ServerLiveboardInfo
            {
                IsOnline = false,
                IsServerRunning = false,
                ServerAddress = "palodyssey.duckdns.org:8211",
                PlayerCount = 0,
                MaxPlayers = 32
            };
        }

        public async Task<bool> RequestRemoteServerStartAsync(
            string host,
            int managementPort,
            string accessKey,
            IProgress<string>? progress = null,
            int timeoutSeconds = 30)
        {
            string baseUrl = ResolveBaseUrl(host, managementPort);
            string displayHost = string.IsNullOrWhiteSpace(host) ? "PalOdyssey Realm" : host;

            progress?.Report($"Triggering start webhook on {displayHost}...");
            _logService.LogInfo($"Sending HTTPS/HTTP start webhook to {baseUrl}/webhook/start-server...", "RemoteClient");

            try
            {
                using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(8));
                using var request = new HttpRequestMessage(HttpMethod.Post, $"{baseUrl}/webhook/start-server")
                {
                    Content = new StringContent(
                        JsonSerializer.Serialize(new
                        {
                            accessKey = accessKey,
                            source = "PalOdyssey Launcher Client"
                        }),
                        Encoding.UTF8,
                        "application/json")
                };

                request.Headers.Add("X-PalOdyssey-Key", accessKey);

                var response = await _httpClient.SendAsync(request, cts.Token);
                if (!response.IsSuccessStatusCode)
                {
                    // Fallback to /api/start
                    using var req2 = new HttpRequestMessage(HttpMethod.Post, $"{baseUrl}/api/start");
                    req2.Headers.Add("X-PalOdyssey-Key", accessKey);
                    response = await _httpClient.SendAsync(req2, cts.Token);
                }

                if (!response.IsSuccessStatusCode)
                {
                    string error = await response.Content.ReadAsStringAsync();
                    progress?.Report($"Server start webhook rejected ({response.StatusCode})");
                    _logService.LogWarning($"Server start webhook rejected: {response.StatusCode} - {error}", "RemoteClient");
                    return false;
                }

                string respJson = await response.Content.ReadAsStringAsync();
                _logService.LogSuccess($"Server start webhook accepted: {respJson}", "RemoteClient");
                progress?.Report("Start webhook confirmed! Booting dedicated server...");

                // Poll status until server is running
                var startTime = DateTime.Now;
                while ((DateTime.Now - startTime).TotalSeconds < timeoutSeconds)
                {
                    await Task.Delay(2000);
                    var status = await QueryServerStatusAsync(host, managementPort, 2000);

                    if (status.IsOnline && status.IsServerRunning)
                    {
                        progress?.Report($"Palworld Server is online (PID: {status.ProcessId}) on port {status.ServerPort}!");
                        _logService.LogSuccess($"Remote Palworld Server is confirmed ONLINE on port {status.ServerPort}!", "RemoteClient");
                        return true;
                    }
                    else
                    {
                        int elapsed = (int)(DateTime.Now - startTime).TotalSeconds;
                        progress?.Report($"Starting Palworld dedicated server... ({elapsed}s)");
                    }
                }

                progress?.Report("Server start triggered, proceeding with launch.");
                return true;
            }
            catch (Exception ex)
            {
                progress?.Report($"Failed to trigger server webhook: {ex.Message}");
                _logService.LogError("Webhook start communication error.", "RemoteClient", ex);
                return false;
            }
        }

        public async Task<bool> RequestRemoteServerStopAsync(string host, int managementPort, string accessKey)
        {
            string baseUrl = ResolveBaseUrl(host, managementPort);

            try
            {
                using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(5));
                using var request = new HttpRequestMessage(HttpMethod.Post, $"{baseUrl}/api/stop");
                request.Headers.Add("X-PalOdyssey-Key", accessKey);

                var response = await _httpClient.SendAsync(request, cts.Token);
                return response.IsSuccessStatusCode;
            }
            catch (Exception ex)
            {
                _logService.LogWarning("Remote stop request exception.", "RemoteClient", ex.Message);
                return false;
            }
        }

        private static bool IsLocalServerRunning()
        {
            try
            {
                return System.Diagnostics.Process.GetProcessesByName("PalServer").Length > 0
                    || System.Diagnostics.Process.GetProcessesByName("PalServer-Win64-Shipping-Cmd").Length > 0
                    || System.Diagnostics.Process.GetProcessesByName("PalServer-Win64-Shipping").Length > 0;
            }
            catch { return false; }
        }
    }
}
