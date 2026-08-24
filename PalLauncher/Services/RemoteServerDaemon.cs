using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Net.Sockets;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using PalLauncher.Models;
using PalLauncher.Services.Interfaces;

namespace PalLauncher.Services
{
    public class RemoteServerDaemon : IRemoteServerDaemon
    {
        private readonly ILogService _logService;
        private readonly ILaunchService _launchService;
        private HttpListener? _httpListener;
        private UdpClient? _udpWakeListener;
        private Task? _udpWakeTask;
        private CancellationTokenSource? _cts;
        private Task? _listenerTask;
        private Task? _idleMonitorTask;
        private string _accessKey = "PalOdyssey2026Secure";
        private Func<Task<bool>>? _onStartServerRequested;
        private Func<Task<bool>>? _onStopServerRequested;
        private int _port = 8215;
        private int _gamePort = 8211;
        private bool _isRunning;

        // Auto-Shutdown State
        private bool _idleShutdownEnabled = true;
        private int _idleShutdownMinutes = 15;
        private DateTime? _serverStartedTime;
        private DateTime _lastActivePlayerTime = DateTime.Now;
        private bool _wasServerRunning = false;
        private bool _shutdownTriggered = false;
        private readonly List<PlayerInfo> _activePlayers = new();
        private readonly object _lock = new();

        public bool IsRunning => _isRunning;
        public int Port => _port;

        private static readonly HttpClient _palServerClient = CreatePalServerHttpClient();

        private static HttpClient CreatePalServerHttpClient()
        {
            var client = new HttpClient { Timeout = TimeSpan.FromSeconds(2) };
            var authBytes = Encoding.UTF8.GetBytes("admin:0012");
            client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Basic", Convert.ToBase64String(authBytes));
            return client;
        }

        public RemoteServerDaemon(ILogService logService, ILaunchService launchService)
        {
            _logService = logService;
            _launchService = launchService;
        }

        public void ConfigureIdleAutoShutdown(bool enabled, int minutes)
        {
            lock (_lock)
            {
                _idleShutdownEnabled = enabled;
                _idleShutdownMinutes = Math.Max(1, minutes);
                _logService.LogInfo($"Inactivity Auto-Shutdown configured: Enabled={enabled}, Timeout={_idleShutdownMinutes}m", "AutoShutdown");
            }
        }

        public Task<bool> StartDaemonAsync(
            int port,
            string accessKey,
            Func<Task<bool>> onStartServerRequested,
            Func<Task<bool>> onStopServerRequested)
        {
            if (_isRunning) return Task.FromResult(true);

            _port = port > 0 ? port : 8215;
            _accessKey = string.IsNullOrWhiteSpace(accessKey) ? "PalOdyssey2026Secure" : accessKey;
            _onStartServerRequested = onStartServerRequested;
            _onStopServerRequested = onStopServerRequested;

            try
            {
                // Attempt 1: Try Wildcard Listener (accepts external WAN/LAN connections when URL reserved or elevated)
                bool started = false;
                try
                {
                    var listener = new HttpListener();
                    listener.Prefixes.Add($"http://*:{_port}/");
                    listener.Start();
                    _httpListener = listener;
                    started = true;
                }
                catch { }

                // Attempt 2: Try Plus Wildcard Listener
                if (!started)
                {
                    try
                    {
                        var listener = new HttpListener();
                        listener.Prefixes.Add($"http://+:{_port}/");
                        listener.Start();
                        _httpListener = listener;
                        started = true;
                    }
                    catch { }
                }

                // Attempt 3: Standard Loopback Listener (always succeeds without elevation)
                if (!started)
                {
                    var listener = new HttpListener();
                    listener.Prefixes.Add($"http://localhost:{_port}/");
                    listener.Prefixes.Add($"http://127.0.0.1:{_port}/");
                    listener.Start();
                    _httpListener = listener;
                    started = true;
                }

                _cts = new CancellationTokenSource();
                _isRunning = true;
                _lastActivePlayerTime = DateTime.Now;
                _wasServerRunning = _launchService.IsServerRunning;
                _shutdownTriggered = false;

                _logService.LogSuccess($"Remote Host Daemon listening on port {_port} with Inactivity Auto-Shutdown ({_idleShutdownMinutes}m).", "RemoteDaemon");
                
                // Arm UDP Wake-on-Demand on game port 8211 so single-port-forward wake works immediately
                if (!_wasServerRunning)
                {
                    StartUdpWakeListener(_gamePort);
                }

                _listenerTask = Task.Run(() => AcceptRequestsLoopAsync(_cts.Token));
                _idleMonitorTask = Task.Run(() => IdleMonitorLoopAsync(_cts.Token));
                return Task.FromResult(true);
            }
            catch (Exception ex)
            {
                _isRunning = false;
                _logService.LogError($"Failed to start Remote Host Daemon on port {_port}.", "RemoteDaemon", ex);
                return Task.FromResult(false);
            }
        }

        private void StartUdpWakeListener(int gamePort)
        {
            StopUdpWakeListener();
            if (_launchService.IsServerRunning) return;

            _gamePort = gamePort > 0 ? gamePort : 8211;
            var localEp = new IPEndPoint(IPAddress.Any, _gamePort);

            // Robust binding with socket reuse & retry
            UdpClient? client = null;
            for (int attempt = 1; attempt <= 5; attempt++)
            {
                try
                {
                    client = new UdpClient();
                    client.Client.SetSocketOption(SocketOptionLevel.Socket, SocketOptionName.ReuseAddress, true);
                    client.Client.Bind(localEp);
                    client.EnableBroadcast = true;
                    break;
                }
                catch (Exception ex)
                {
                    client?.Close();
                    client = null;
                    if (attempt == 5)
                    {
                        _logService.LogWarning($"Could not bind UDP Wake listener on port {_gamePort}: {ex.Message}", "RemoteDaemon");
                        return;
                    }
                    Thread.Sleep(300);
                }
            }

            if (client == null) return;

            _udpWakeListener = client;
            _udpWakeTask = Task.Run(async () =>
            {
                while (_udpWakeListener != null && !_launchService.IsServerRunning)
                {
                    try
                    {
                        var result = await _udpWakeListener.ReceiveAsync();
                        if (result.Buffer != null && result.Buffer.Length > 0)
                        {
                            string msg = Encoding.UTF8.GetString(result.Buffer);
                            if (msg.StartsWith("PALODYSSEY_WAKE:", StringComparison.OrdinalIgnoreCase))
                            {
                                string key = msg["PALODYSSEY_WAKE:".Length..].Trim();
                                if (!string.Equals(key, _accessKey, StringComparison.Ordinal))
                                {
                                    _logService.LogWarning($"Rejected unauthorized UDP wake packet from {result.RemoteEndPoint}.", "RemoteDaemon");
                                    continue;
                                }
                            }

                            _logService.LogSuccess($"[Port 8211 Wake] Received authorized UDP wake signal on port {_gamePort} from {result.RemoteEndPoint}! Booting Palworld Dedicated Server...", "RemoteDaemon");
                            StopUdpWakeListener();
                            if (_onStartServerRequested != null)
                            {
                                _ = Task.Run(async () =>
                                {
                                    try
                                    {
                                        await _onStartServerRequested();
                                    }
                                    catch (Exception ex)
                                    {
                                        _logService.LogError("Error executing start server callback", "RemoteDaemon", ex);
                                    }
                                });
                            }
                            break;
                        }
                    }
                    catch (ObjectDisposedException) { break; }
                    catch (SocketException) { break; }
                    catch (Exception ex)
                    {
                        _logService.LogWarning($"UDP wake listener exception: {ex.Message}", "RemoteDaemon");
                        break;
                    }
                }
            });
            _logService.LogInfo($"UDP Wake-on-Demand armed on port {_gamePort}. Incoming connection on port {_gamePort} will auto-start server.", "RemoteDaemon");
        }

        private void StopUdpWakeListener()
        {
            try
            {
                _udpWakeListener?.Close();
                _udpWakeListener?.Dispose();
            }
            catch { }
            _udpWakeListener = null;
        }

        public ServerLiveboardInfo GetCurrentLiveboard()
        {
            bool isServerRunning = _launchService.IsServerRunning;
            var state = _launchService.CurrentState;
            
            double uptime = 0;
            if (isServerRunning)
            {
                if (!_serverStartedTime.HasValue)
                {
                    _serverStartedTime = state.StartTime ?? DateTime.Now;
                }
                uptime = (DateTime.Now - _serverStartedTime.Value).TotalSeconds;
            }
            else
            {
                _serverStartedTime = null;
            }

            int idleRemaining = _idleShutdownMinutes;
            bool isIdleCountingDown = false;

            lock (_lock)
            {
                int currentPlayers = _activePlayers.Count;
                if (isServerRunning && currentPlayers == 0 && _idleShutdownEnabled)
                {
                    isIdleCountingDown = true;
                    var idleDuration = DateTime.Now - _lastActivePlayerTime;
                    int minutesPassed = (int)idleDuration.TotalMinutes;
                    idleRemaining = Math.Max(0, _idleShutdownMinutes - minutesPassed);
                }
                else if (currentPlayers > 0)
                {
                    _lastActivePlayerTime = DateTime.Now;
                    _shutdownTriggered = false;
                }

                return new ServerLiveboardInfo
                {
                    IsOnline = true,
                    IsServerRunning = isServerRunning,
                    ServerName = "PalOdyssey Realm",
                    ServerAddress = "palodyssey.duckdns.org:8211",
                    Version = "1.5.4",
                    UptimeSeconds = uptime,
                    PlayerCount = currentPlayers,
                    MaxPlayers = 32,
                    Players = new List<PlayerInfo>(_activePlayers),
                    IsIdleCountingDown = isIdleCountingDown,
                    IdleMinutesRemaining = idleRemaining,
                    IdleShutdownEnabled = _idleShutdownEnabled
                };
            }
        }

        private async Task IdleMonitorLoopAsync(CancellationToken ct)
        {
            while (!ct.IsCancellationRequested)
            {
                try
                {
                    await Task.Delay(1500, ct); // Responsive 1.5s lifecycle check

                    bool isServerRunning = _launchService.IsServerRunning;

                    // Detect Server Start Transition
                    if (!_wasServerRunning && isServerRunning)
                    {
                        _wasServerRunning = true;
                        _serverStartedTime = DateTime.Now;
                        _lastActivePlayerTime = DateTime.Now;
                        _shutdownTriggered = false;
                        StopUdpWakeListener();
                        _logService.LogInfo("Dedicated server active detected. Inactivity timer initialized.", "AutoShutdown");
                    }
                    // Detect Server Stop Transition
                    else if (_wasServerRunning && !isServerRunning)
                    {
                        double uptimeSeconds = _serverStartedTime.HasValue ? (DateTime.Now - _serverStartedTime.Value).TotalSeconds : 999;
                        if (uptimeSeconds >= 45)
                        {
                            _wasServerRunning = false;
                            _serverStartedTime = null;
                            _lastActivePlayerTime = DateTime.Now;
                            _shutdownTriggered = false;
                            lock (_lock) { _activePlayers.Clear(); }
                            StartUdpWakeListener(_gamePort);
                        }
                        continue;
                    }

                    if (!isServerRunning)
                    {
                        _lastActivePlayerTime = DateTime.Now;
                        continue;
                    }

                    // Server is active - query live players from Palworld REST API
                    await RefreshConnectedPlayersAsync();

                    lock (_lock)
                    {
                        if (_activePlayers.Count > 0)
                        {
                            _lastActivePlayerTime = DateTime.Now;
                            _shutdownTriggered = false;
                        }
                        else if (_idleShutdownEnabled && !_shutdownTriggered)
                        {
                            // Startup grace period: Allow at least 2 minutes for server world initialization & client connections
                            double uptimeSeconds = _serverStartedTime.HasValue ? (DateTime.Now - _serverStartedTime.Value).TotalSeconds : 0;
                            if (uptimeSeconds < 90)
                            {
                                _lastActivePlayerTime = DateTime.Now;
                                continue;
                            }

                            var idleDuration = DateTime.Now - _lastActivePlayerTime;
                            if (idleDuration.TotalMinutes >= _idleShutdownMinutes)
                            {
                                _shutdownTriggered = true;
                                _logService.LogWarning($"Auto-Shutdown triggered: 0 players online for {_idleShutdownMinutes} minutes. Gracefully stopping dedicated server.", "AutoShutdown");
                                
                                _ = Task.Run(async () =>
                                {
                                    try
                                    {
                                        if (_onStopServerRequested != null)
                                        {
                                            await _onStopServerRequested();
                                        }
                                    }
                                    catch (Exception ex)
                                    {
                                        _logService.LogError("Exception executing auto-shutdown stop callback.", "AutoShutdown", ex);
                                    }
                                });
                            }
                        }
                    }
                }
                catch (OperationCanceledException) { break; }
                catch (Exception ex)
                {
                    if (!ct.IsCancellationRequested)
                    {
                        _logService.LogWarning("IdleMonitor loop notice.", "AutoShutdown", ex.Message);
                    }
                }
            }
        }

        private async Task RefreshConnectedPlayersAsync()
        {
            // Query local Palworld server API with HTTP Basic Auth
            try
            {
                var response = await _palServerClient.GetAsync("http://127.0.0.1:8212/v1/api/players");
                if (response.IsSuccessStatusCode)
                {
                    string json = await response.Content.ReadAsStringAsync();
                    using var doc = JsonDocument.Parse(json);
                    var playersList = new List<PlayerInfo>();

                    if (doc.RootElement.TryGetProperty("players", out var playersArr))
                    {
                        foreach (var elem in playersArr.EnumerateArray())
                        {
                            string name = "Pal Trainer";
                            if (elem.TryGetProperty("name", out var n) && !string.IsNullOrWhiteSpace(n.GetString())) name = n.GetString()!;
                            else if (elem.TryGetProperty("playerName", out var pn) && !string.IsNullOrWhiteSpace(pn.GetString())) name = pn.GetString()!;
                            else if (elem.TryGetProperty("accountName", out var an) && !string.IsNullOrWhiteSpace(an.GetString())) name = an.GetString()!;
                            else if (elem.TryGetProperty("playerId", out var pid) && !string.IsNullOrWhiteSpace(pid.GetString())) name = pid.GetString()!;

                            int level = 1;
                            if (elem.TryGetProperty("level", out var l))
                            {
                                if (l.ValueKind == JsonValueKind.Number) level = l.GetInt32();
                                else if (int.TryParse(l.GetString(), out int parsedLvl)) level = parsedLvl;
                            }

                            int ping = 20;
                            if (elem.TryGetProperty("ping", out var p))
                            {
                                if (p.ValueKind == JsonValueKind.Number) ping = p.GetInt32();
                                else if (int.TryParse(p.GetString(), out int parsedPing)) ping = parsedPing;
                            }

                            string location = "Palpagos Islands";
                            if (elem.TryGetProperty("location", out var loc) && !string.IsNullOrWhiteSpace(loc.GetString()))
                            {
                                location = loc.GetString()!;
                            }
                            else if (elem.TryGetProperty("location_x", out var lx) && elem.TryGetProperty("location_y", out var ly))
                            {
                                location = $"X: {lx.ToString()}, Y: {ly.ToString()}";
                            }

                            playersList.Add(new PlayerInfo
                            {
                                Name = name,
                                Level = level,
                                PingMs = ping,
                                Location = location
                            });
                        }
                    }

                    lock (_lock)
                    {
                        _activePlayers.Clear();
                        _activePlayers.AddRange(playersList);
                    }
                }
            }
            catch
            {
                // If local REST API is not responding or no players are currently in socket
            }
        }

        private async Task AcceptRequestsLoopAsync(CancellationToken ct)
        {
            while (!ct.IsCancellationRequested && _httpListener != null && _httpListener.IsListening)
            {
                try
                {
                    var context = await _httpListener.GetContextAsync();
                    _ = Task.Run(() => ProcessHttpRequestAsync(context), ct);
                }
                catch (HttpListenerException) { break; }
                catch (ObjectDisposedException) { break; }
                catch (Exception ex)
                {
                    if (!ct.IsCancellationRequested)
                    {
                        _logService.LogWarning("RemoteDaemon request loop notice.", "RemoteDaemon", ex.Message);
                    }
                }
            }
        }

        private async Task ProcessHttpRequestAsync(HttpListenerContext context)
        {
            var req = context.Request;
            var resp = context.Response;

            try
            {
                string path = req.Url?.AbsolutePath ?? "/";
                string method = req.HttpMethod.ToUpperInvariant();
                string key = req.Headers["X-PalOdyssey-Key"] ?? req.QueryString["key"] ?? "";

                // CORS headers
                resp.AddHeader("Access-Control-Allow-Origin", "*");
                resp.AddHeader("Access-Control-Allow-Headers", "X-PalOdyssey-Key, Content-Type");

                if (method == "OPTIONS")
                {
                    resp.StatusCode = 200;
                    resp.Close();
                    return;
                }

                if (path.Equals("/api/liveboard", StringComparison.OrdinalIgnoreCase))
                {
                    var liveboard = GetCurrentLiveboard();
                    await SendJsonResponseAsync(resp, 200, liveboard);
                }
                else if (path.Equals("/api/status", StringComparison.OrdinalIgnoreCase) || path.Equals("/", StringComparison.OrdinalIgnoreCase))
                {
                    var liveboard = GetCurrentLiveboard();
                    var status = new RemoteServerStatus
                    {
                        IsOnline = true,
                        IsServerRunning = liveboard.IsServerRunning,
                        ProcessId = _launchService.CurrentState.ProcessId,
                        ServerPort = 8211,
                        ServerName = "PalOdyssey Realm",
                        Version = "1.5.4",
                        UptimeSeconds = liveboard.UptimeSeconds,
                        Message = liveboard.IsServerRunning ? $"Dedicated Server Active ({liveboard.PlayerCount} Players)" : "Dedicated Server Sleeping (Wake on Demand Available)"
                    };

                    await SendJsonResponseAsync(resp, 200, status);
                }
                else if (path.Equals("/api/start", StringComparison.OrdinalIgnoreCase) && method == "POST")
                {
                    if (!string.Equals(key, _accessKey, StringComparison.Ordinal))
                    {
                        await SendJsonResponseAsync(resp, 403, new { error = "Invalid Realm Access Key" });
                        return;
                    }

                    _logService.LogInfo("Received remote server wake/start command from authorized client.", "RemoteDaemon");
                    _lastActivePlayerTime = DateTime.Now;
                    bool triggered = false;
                    if (_onStartServerRequested != null)
                    {
                        triggered = await _onStartServerRequested();
                    }

                    await SendJsonResponseAsync(resp, 200, new { success = triggered, status = "Server Starting" });
                }
                else if (path.Equals("/api/stop", StringComparison.OrdinalIgnoreCase) && method == "POST")
                {
                    if (!string.Equals(key, _accessKey, StringComparison.Ordinal))
                    {
                        await SendJsonResponseAsync(resp, 403, new { error = "Invalid Realm Access Key" });
                        return;
                    }

                    _logService.LogInfo("Received remote server stop command from authorized client.", "RemoteDaemon");
                    bool triggered = false;
                    if (_onStopServerRequested != null)
                    {
                        triggered = await _onStopServerRequested();
                    }

                    await SendJsonResponseAsync(resp, 200, new { success = triggered, status = "Server Stopping" });
                }
                else
                {
                    await SendJsonResponseAsync(resp, 404, new { error = "Unknown Endpoint" });
                }
            }
            catch (Exception ex)
            {
                _logService.LogWarning("Exception processing RemoteDaemon HTTP request.", "RemoteDaemon", ex.Message);
            }
            finally
            {
                try { resp.Close(); } catch { }
            }
        }

        private static async Task SendJsonResponseAsync(HttpListenerResponse resp, int statusCode, object payload)
        {
            resp.StatusCode = statusCode;
            resp.ContentType = "application/json; charset=utf-8";
            resp.KeepAlive = false;

            string json = JsonSerializer.Serialize(payload, new JsonSerializerOptions { WriteIndented = true });
            byte[] bytes = Encoding.UTF8.GetBytes(json);
            resp.ContentLength64 = bytes.Length;

            await resp.OutputStream.WriteAsync(bytes, 0, bytes.Length);
            await resp.OutputStream.FlushAsync();
        }

        public async Task StopDaemonAsync()
        {
            if (!_isRunning) return;

            _isRunning = false;
            try
            {
                StopUdpWakeListener();
                _cts?.Cancel();
                _httpListener?.Stop();
                _httpListener?.Close();
                _httpListener = null;

                if (_listenerTask != null)
                {
                    await Task.WhenAny(_listenerTask, Task.Delay(1000));
                }

                _logService.LogInfo("Remote Host Daemon stopped.", "RemoteDaemon");
            }
            catch { }
        }

        public void Dispose()
        {
            _ = StopDaemonAsync();
        }
    }
}
