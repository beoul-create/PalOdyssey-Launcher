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

                IPAddress targetIp;
                if (IPAddress.TryParse(context.DnsEndPoint.Host, out var parsedIp))
                {
                    targetIp = parsedIp;
                }
                else if (context.DnsEndPoint.Host.Equals("localhost", StringComparison.OrdinalIgnoreCase))
                {
                    targetIp = IPAddress.Loopback;
                }
                else
                {
                    var addresses = await Dns.GetHostAddressesAsync(context.DnsEndPoint.Host, cancellationToken);
                    targetIp = Array.Find(addresses, a => a.AddressFamily == System.Net.Sockets.AddressFamily.InterNetwork)
                               ?? addresses[0];
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
            string cleanHost = string.IsNullOrWhiteSpace(host) ? "palodyssey.duckdns.org" : host.Trim();
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

        private static async Task<bool> ProbeUdpAsync(string host, int port, int timeoutMs = 1200)
        {
            try
            {
                using var udp = new System.Net.Sockets.UdpClient();
                udp.Client.ReceiveTimeout = timeoutMs;
                udp.Client.SendTimeout = timeoutMs;

                byte[] request = new byte[] {
                    0xFF, 0xFF, 0xFF, 0xFF, 0x54, 0x53, 0x6F, 0x75,
                    0x72, 0x63, 0x65, 0x20, 0x45, 0x6E, 0x67, 0x69,
                    0x6E, 0x65, 0x20, 0x51, 0x75, 0x65, 0x72, 0x79, 0x00
                };

                await udp.SendAsync(request, request.Length, host, port);
                var receiveTask = udp.ReceiveAsync();
                var timeoutTask = Task.Delay(timeoutMs);
                if (await Task.WhenAny(receiveTask, timeoutTask) == receiveTask)
                {
                    var result = await receiveTask;
                    return result.Buffer != null && result.Buffer.Length > 0;
                }
            }
            catch { }
            return false;
        }

        private static async Task<bool> ProbeTcpAsync(string host, int port, int timeoutMs = 1200)
        {
            try
            {
                using var tcp = new System.Net.Sockets.TcpClient();
                using var cts = new CancellationTokenSource(timeoutMs);
                await tcp.ConnectAsync(host, port, cts.Token);
                return tcp.Connected;
            }
            catch { }
            return false;
        }

        public async Task<RemoteServerStatus> QueryServerStatusAsync(string host, int managementPort, int timeoutMs = 2500)
        {
            int port = managementPort > 0 ? managementPort : 8215;
            string cleanHost = string.IsNullOrWhiteSpace(host) ? "palodyssey.duckdns.org" : host.Trim();
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

            bool socketActive = await ProbeUdpAsync(cleanHost, 27016, 1000)
                             || await ProbeTcpAsync(cleanHost, port, 1000)
                             || await ProbeTcpAsync(cleanHost, 8215, 1000)
                             || await ProbeTcpAsync(cleanHost, 8211, 1000)
                             || await ProbeTcpAsync(cleanHost, 25575, 1000);

            if (socketActive)
            {
                return new RemoteServerStatus
                {
                    IsOnline = true,
                    IsServerRunning = true,
                    ServerPort = 8211,
                    ServerName = "PalOdyssey Realm",
                    Message = "Remote Server Online"
                };
            }

            return new RemoteServerStatus
            {
                IsOnline = false,
                IsServerRunning = false,
                ServerPort = 8211,
                Message = "Host Daemon Unreachable / Server Sleeping"
            };
        }

        private static DateTime? _remoteOnlineSince;

        private static double GetLocalServerUptimeSeconds()
        {
            try
            {
                var procs = System.Diagnostics.Process.GetProcessesByName("PalServer");
                if (procs.Length == 0) procs = System.Diagnostics.Process.GetProcessesByName("PalServer-Win64-Shipping-Cmd");
                if (procs.Length == 0) procs = System.Diagnostics.Process.GetProcessesByName("PalServer-Win64-Shipping");
                if (procs.Length > 0 && procs[0] != null && !procs[0].HasExited)
                {
                    var uptime = (DateTime.Now - procs[0].StartTime).TotalSeconds;
                    if (uptime > 0) return uptime;
                }
            }
            catch { }
            return 0;
        }

        public async Task<ServerLiveboardInfo> FetchLiveboardAsync(string host, int managementPort, int timeoutMs = 2500)
        {
            string cleanHost = string.IsNullOrWhiteSpace(host) ? "palodyssey.duckdns.org" : host.Trim();
            int port = managementPort > 0 ? managementPort : 8215;
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
                        if (liveboard.UptimeSeconds <= 0)
                        {
                            liveboard.UptimeSeconds = GetLocalServerUptimeSeconds();
                        }
                        return liveboard;
                    }
                }
            }
            catch (Exception)
            {
                // Unreachable or offline
            }

            if (IsLocalServerRunning())
            {
                double localUptime = GetLocalServerUptimeSeconds();
                return new ServerLiveboardInfo
                {
                    IsOnline = true,
                    IsServerRunning = true,
                    ServerAddress = "palodyssey.duckdns.org:8211",
                    ServerName = "PalOdyssey Realm",
                    UptimeSeconds = localUptime,
                    PlayerCount = 0,
                    MaxPlayers = 32
                };
            }

            bool socketActive = await ProbeUdpAsync(cleanHost, 27016, 1000)
                             || await ProbeTcpAsync(cleanHost, port, 1000)
                             || await ProbeTcpAsync(cleanHost, 8215, 1000)
                             || await ProbeTcpAsync(cleanHost, 8211, 1000)
                             || await ProbeTcpAsync(cleanHost, 25575, 1000);

            if (socketActive)
            {
                _remoteOnlineSince ??= DateTime.Now;
                double remoteUptime = (DateTime.Now - _remoteOnlineSince.Value).TotalSeconds;
                return new ServerLiveboardInfo
                {
                    IsOnline = true,
                    IsServerRunning = true,
                    ServerAddress = "palodyssey.duckdns.org:8211",
                    ServerName = "PalOdyssey Realm",
                    UptimeSeconds = Math.Max(1, remoteUptime),
                    PlayerCount = 0,
                    MaxPlayers = 32
                };
            }

            _remoteOnlineSince = null;
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
            int timeoutSeconds = 25)
        {
            int port = managementPort > 0 ? managementPort : 8215;
            string cleanHost = string.IsNullOrWhiteSpace(host) ? "palodyssey.duckdns.org" : host.Trim();

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
            int port = managementPort > 0 ? managementPort : 8215;

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
