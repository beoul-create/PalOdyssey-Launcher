using System;
using System.Collections.Generic;
using System.Net;
using System.Net.Http;
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
        private static readonly HttpClient _httpClient = new(new SocketsHttpHandler
        {
            ConnectTimeout = TimeSpan.FromSeconds(2),
            PooledConnectionLifetime = TimeSpan.FromMinutes(1),
            ConnectCallback = async (context, cancellationToken) =>
            {
                var socket = new System.Net.Sockets.Socket(System.Net.Sockets.AddressFamily.InterNetwork, System.Net.Sockets.SocketType.Stream, System.Net.Sockets.ProtocolType.Tcp)
                {
                    NoDelay = true
                };

                IPAddress targetIp = IPAddress.Loopback;
                if (!IPAddress.TryParse(context.DnsEndPoint.Host, out targetIp!))
                {
                    if (context.DnsEndPoint.Host.Equals("localhost", StringComparison.OrdinalIgnoreCase))
                    {
                        targetIp = IPAddress.Loopback;
                    }
                    else
                    {
                        var addresses = await Dns.GetHostAddressesAsync(context.DnsEndPoint.Host, cancellationToken);
                        targetIp = Array.Find(addresses, a => a.AddressFamily == System.Net.Sockets.AddressFamily.InterNetwork)
                                   ?? addresses[0];
                    }
                }

                try
                {
                    await socket.ConnectAsync(targetIp, context.DnsEndPoint.Port, cancellationToken);
                    return new System.Net.Sockets.NetworkStream(socket, ownsSocket: true);
                }
                catch
                {
                    socket.Dispose();
                    throw;
                }
            }
        })
        {
            Timeout = TimeSpan.FromSeconds(5)
        };

        public RemoteClientService(ILogService logService)
        {
            _logService = logService;
        }

        private static async Task<HttpResponseMessage?> SendWithLoopbackFallbackAsync(
            string host,
            int port,
            string path,
            CancellationToken ct,
            HttpMethod? method = null,
            Action<HttpRequestMessage>? configure = null)
        {
            method ??= HttpMethod.Get;
            string cleanHost = string.IsNullOrWhiteSpace(host) ? "beoul.duckdns.org" : host.Trim();
            var hostsToTry = new List<string>();

            if (cleanHost == "127.0.0.1" || cleanHost.Equals("localhost", StringComparison.OrdinalIgnoreCase))
            {
                hostsToTry.Add("localhost");
                hostsToTry.Add("127.0.0.1");
            }
            else
            {
                hostsToTry.Add(cleanHost);
            }

            while (!ct.IsCancellationRequested)
            {
                foreach (var h in hostsToTry)
                {
                    try
                    {
                        string url = $"http://{h}:{port}{path}";
                        var req = new HttpRequestMessage(method, url);
                        req.Headers.ConnectionClose = true;
                        configure?.Invoke(req);
                        var resp = await _httpClient.SendAsync(req, ct);
                        if (resp != null && (resp.IsSuccessStatusCode || resp.StatusCode == HttpStatusCode.Forbidden))
                        {
                            return resp;
                        }
                        req.Dispose();
                    }
                    catch (OperationCanceledException)
                    {
                        return null;
                    }
                    catch { }
                }

                try
                {
                    await Task.Delay(100, ct);
                }
                catch (OperationCanceledException)
                {
                    return null;
                }
            }

            return null;
        }

        public async Task<RemoteServerStatus> QueryServerStatusAsync(string host, int managementPort, int timeoutMs = 2500)
        {
            int port = managementPort > 0 ? managementPort : 8212;
            using var cts = new CancellationTokenSource(timeoutMs);

            try
            {
                var response = await SendWithLoopbackFallbackAsync(host, port, "/api/status", cts.Token);
                if (response != null && response.IsSuccessStatusCode)
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
            catch (Exception)
            {
                // Host daemon is unreachable or port is sleeping
            }

            return new RemoteServerStatus
            {
                IsOnline = false,
                IsServerRunning = false,
                ServerPort = 8211,
                Message = "Host Daemon Unreachable / Server Sleeping"
            };
        }

        public async Task<ServerLiveboardInfo> FetchLiveboardAsync(string host, int managementPort, int timeoutMs = 2500)
        {
            int port = managementPort > 0 ? managementPort : 8212;
            string cleanHost = string.IsNullOrWhiteSpace(host) ? "beoul.duckdns.org" : host.Trim();
            using var cts = new CancellationTokenSource(timeoutMs);

            try
            {
                var response = await SendWithLoopbackFallbackAsync(host, port, "/api/liveboard", cts.Token);
                if (response != null && response.IsSuccessStatusCode)
                {
                    string json = await response.Content.ReadAsStringAsync(cts.Token);
                    var liveboard = JsonSerializer.Deserialize<ServerLiveboardInfo>(json, new JsonSerializerOptions
                    {
                        PropertyNameCaseInsensitive = true
                    });

                    if (liveboard != null)
                    {
                        liveboard.IsOnline = true;
                        return liveboard;
                    }
                }
            }
            catch (Exception)
            {
                // Unreachable or offline
            }

            return new ServerLiveboardInfo
            {
                IsOnline = false,
                IsServerRunning = false,
                ServerAddress = $"{cleanHost}:8211",
                PlayerCount = 0,
                MaxPlayers = 32
            };
        }

        public async Task<bool> RequestRemoteServerStartAsync(
            string host,
            int managementPort,
            string accessKey,
            IProgress<string>? progress = null,
            int timeoutSeconds = 25)
        {
            int port = managementPort > 0 ? managementPort : 8212;
            string cleanHost = string.IsNullOrWhiteSpace(host) ? "beoul.duckdns.org" : host.Trim();

            progress?.Report($"Connecting to host at {cleanHost}:{port}...");
            _logService.LogInfo($"Sending remote wake request to host {cleanHost}:{port}...", "RemoteClient");

            try
            {
                using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(5));
                var response = await SendWithLoopbackFallbackAsync(
                    host,
                    port,
                    "/api/start",
                    cts.Token,
                    HttpMethod.Post,
                    req => req.Headers.Add("X-PalOdyssey-Key", accessKey));

                if (response == null || !response.IsSuccessStatusCode)
                {
                    string error = response != null ? await response.Content.ReadAsStringAsync() : "No response";
                    progress?.Report($"Remote wake rejected: {response?.StatusCode}");
                    _logService.LogWarning($"Remote wake rejected by host ({response?.StatusCode}): {error}", "RemoteClient");
                    return false;
                }

                progress?.Report("Wake signal accepted! Waiting for Palworld server initialization...");
                _logService.LogSuccess("Wake signal accepted by host. Polling server startup heartbeat...", "RemoteClient");

                // Poll status until server reports active
                var startTime = DateTime.Now;
                while ((DateTime.Now - startTime).TotalSeconds < timeoutSeconds)
                {
                    await Task.Delay(1500);
                    var status = await QueryServerStatusAsync(cleanHost, port, 2000);

                    if (status.IsOnline && status.IsServerRunning)
                    {
                        progress?.Report($"Palworld Server is online (PID: {status.ProcessId}) on port {status.ServerPort}!");
                        _logService.LogSuccess($"Remote Palworld Server is confirmed ONLINE on port {status.ServerPort} (PID: {status.ProcessId})!", "RemoteClient");
                        return true;
                    }
                    else
                    {
                        int elapsed = (int)(DateTime.Now - startTime).TotalSeconds;
                        progress?.Report($"Starting Palworld server on host... ({elapsed}s)");
                    }
                }

                progress?.Report("Server wake initiated, proceeding with launch.");
                return true;
            }
            catch (Exception ex)
            {
                progress?.Report($"Failed to communicate with remote host: {ex.Message}");
                _logService.LogError("Remote wake communication exception.", "RemoteClient", ex);
                return false;
            }
        }

        public async Task<bool> RequestRemoteServerStopAsync(string host, int managementPort, string accessKey)
        {
            int port = managementPort > 0 ? managementPort : 8212;

            try
            {
                using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(5));
                var response = await SendWithLoopbackFallbackAsync(
                    host,
                    port,
                    "/api/stop",
                    cts.Token,
                    HttpMethod.Post,
                    req => req.Headers.Add("X-PalOdyssey-Key", accessKey));

                return response != null && response.IsSuccessStatusCode;
            }
            catch (Exception ex)
            {
                _logService.LogWarning("Remote stop request exception.", "RemoteClient", ex.Message);
                return false;
            }
        }
    }
}
