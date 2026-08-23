using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Net.Http.Headers;
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
        private CancellationTokenSource? _cts;
        private Task? _listenerTask;
        private Task? _idleMonitorTask;
        private string _accessKey = "PalOdyssey2026Secure";
        private Func<Task<bool>>? _onStartServerRequested;
        private Func<Task<bool>>? _onStopServerRequested;
        private int _port = 8212;
        private bool _isRunning;

        // Auto-Shutdown State
        private bool _idleShutdownEnabled = true;
        private int _idleShutdownMinutes = 15;
        private DateTime? _serverStartedTime;
        private DateTime _lastActivePlayerTime = DateTime.Now;
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
            _idleShutdownEnabled = enabled;
            _idleShutdownMinutes = Math.Max(1, minutes);
        }

        public Task<bool> StartDaemonAsync(
            int port,
            string accessKey,
            Func<Task<bool>> onStartServerRequested,
            Func<Task<bool>> onStopServerRequested)
        {
            if (_isRunning) return Task.FromResult(true);

            _port = port > 0 ? port : 8212;
            _accessKey = string.IsNullOrWhiteSpace(accessKey) ? "PalOdyssey2026Secure" : accessKey;
            _onStartServerRequested = onStartServerRequested;
            _onStopServerRequested = onStopServerRequested;

            try
            {
                _httpListener = new HttpListener();
                _httpListener.Prefixes.Add($"http://localhost:{_port}/");
                _httpListener.Prefixes.Add($"http://127.0.0.1:{_port}/");
                
                try
                {
                    _httpListener.Start();
                }
                catch
                {
                    _httpListener.Close();
                    _httpListener = new HttpListener();
                    _httpListener.Prefixes.Add($"http://*:{_port}/");
                    _httpListener.Start();
                }

                _cts = new CancellationTokenSource();
                _isRunning = true;
                _lastActivePlayerTime = DateTime.Now;

                _logService.LogSuccess($"Remote Host Daemon listening on port {_port} with Inactivity Auto-Shutdown ({_idleShutdownMinutes}m).", "RemoteDaemon");
                
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

        public ServerLiveboardInfo GetCurrentLiveboard()
        {
            bool isServerRunning = _launchService.IsServerRunning || _launchService.IsGameRunning;
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
                if (isServerRunning && currentPlayers == 0)
                {
                    isIdleCountingDown = true;
                    var idleDuration = DateTime.Now - _lastActivePlayerTime;
                    int minutesPassed = (int)idleDuration.TotalMinutes;
                    idleRemaining = Math.Max(0, _idleShutdownMinutes - minutesPassed);
                }
                else if (currentPlayers > 0)
                {
                    _lastActivePlayerTime = DateTime.Now;
                }

                return new ServerLiveboardInfo
                {
                    IsOnline = true,
                    IsServerRunning = isServerRunning,
                    ServerName = "PalOdyssey Realm",
                    ServerAddress = "palodyssey.duckdns.org:57294",
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
                    await Task.Delay(15000, ct); // Check every 15s

                    bool isServerRunning = _launchService.IsServerRunning || _launchService.IsGameRunning;
                    if (!isServerRunning)
                    {
                        _lastActivePlayerTime = DateTime.Now;
                        continue;
                    }

                    // Query live players from Palworld server
                    await RefreshConnectedPlayersAsync();

                    lock (_lock)
                    {
                        if (_activePlayers.Count > 0)
                        {
                            _lastActivePlayerTime = DateTime.Now;
                        }
                        else if (_idleShutdownEnabled)
                        {
                            var idleDuration = DateTime.Now - _lastActivePlayerTime;
                            if (idleDuration.TotalMinutes >= _idleShutdownMinutes)
                            {
                                _logService.LogWarning($"Auto-Shutdown triggered: 0 players online for {_idleShutdownMinutes} minutes. Gracefully sleeping server.", "AutoShutdown");
                                _ = Task.Run(async () =>
                                {
                                    if (_onStopServerRequested != null)
                                    {
                                        await _onStopServerRequested();
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
                            string name = elem.TryGetProperty("name", out var n) ? n.GetString() ?? "Pal Trainer" : "Pal Trainer";
                            int level = elem.TryGetProperty("level", out var l) ? l.GetInt32() : 1;
                            int ping = elem.TryGetProperty("ping", out var p) ? p.GetInt32() : 20;
                            string location = elem.TryGetProperty("location", out var loc) ? loc.GetString() ?? "Palpagos" : "Palpagos Islands";

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
