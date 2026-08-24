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
        private Func<string, Task>? _onWebhookServerBooting;
        private int _port = 8215;
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
            Func<Task<bool>> onStopServerRequested,
            Func<string, Task>? onWebhookServerBooting = null)
        {
            if (_isRunning) return Task.FromResult(true);

            _port = port > 0 ? port : 8215;
            _accessKey = string.IsNullOrWhiteSpace(accessKey) ? "PalOdyssey2026Secure" : accessKey;
            _onStartServerRequested = onStartServerRequested;
            _onStopServerRequested = onStopServerRequested;
            _onWebhookServerBooting = onWebhookServerBooting;

            try
            {
                bool started = false;

                // Attempt 1: Wildcard listener
                try
                {
                    var listener = new HttpListener();
                    listener.Prefixes.Add($"http://*:{_port}/");
                    listener.Start();
                    _httpListener = listener;
                    started = true;
                }
                catch { }

                // Attempt 2: Plus wildcard listener
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

                // Attempt 3: Loopback / localhost fallback
                if (!started)
                {
                    try
                    {
                        var listener = new HttpListener();
                        listener.Prefixes.Add($"http://localhost:{_port}/");
                        listener.Prefixes.Add($"http://127.0.0.1:{_port}/");
                        listener.Start();
                        _httpListener = listener;
                        started = true;
                    }
                    catch (Exception ex)
                    {
                        _logService.LogError($"Failed to start HTTP Webhook listener on port {_port}", "RemoteDaemon", ex);
                        return Task.FromResult(false);
                    }
                }

                _cts = new CancellationTokenSource();
                _isRunning = true;

                _listenerTask = Task.Run(() => HandleIncomingRequestsAsync(_cts.Token));
                _idleMonitorTask = Task.Run(() => IdleAutoShutdownLoopAsync(_cts.Token));

                _logService.LogSuccess($"Remote Webhook & Host Daemon listening on port {_port} (24/7 armed).", "RemoteDaemon");
                return Task.FromResult(true);
            }
            catch (Exception ex)
            {
                _logService.LogError("Failed to initialize Remote Daemon.", "RemoteDaemon", ex);
                return Task.FromResult(false);
            }
        }

        public Task StopDaemonAsync()
        {
            _isRunning = false;
            _cts?.Cancel();

            try
            {
                _httpListener?.Stop();
                _httpListener?.Close();
            }
            catch { }
            finally
            {
                _httpListener = null;
            }

            _logService.LogInfo("Remote Webhook & Host Daemon stopped.", "RemoteDaemon");
            return Task.CompletedTask;
        }

        private async Task HandleIncomingRequestsAsync(CancellationToken ct)
        {
            while (!ct.IsCancellationRequested && _httpListener != null && _httpListener.IsListening)
            {
                try
                {
                    var context = await _httpListener.GetContextAsync();
                    _ = ProcessRequestAsync(context);
                }
                catch (HttpListenerException) { break; }
                catch (ObjectDisposedException) { break; }
                catch (Exception ex)
                {
                    if (!ct.IsCancellationRequested)
                    {
                        _logService.LogWarning($"RemoteDaemon request handler exception: {ex.Message}", "RemoteDaemon");
                    }
                }
            }
        }

        private async Task ProcessRequestAsync(HttpListenerContext context)
        {
            var req = context.Request;
            var resp = context.Response;

            // CORS headers for browser / external webhooks
            resp.AddHeader("Access-Control-Allow-Origin", "*");
            resp.AddHeader("Access-Control-Allow-Headers", "Content-Type, X-PalOdyssey-Key, Authorization");
            resp.AddHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");

            if (req.HttpMethod.Equals("OPTIONS", StringComparison.OrdinalIgnoreCase))
            {
                resp.StatusCode = (int)HttpStatusCode.OK;
                resp.Close();
                return;
            }

            string path = req.Url?.AbsolutePath.TrimEnd('/') ?? "";
            _logService.LogInfo($"HTTP Webhook received: {req.HttpMethod} {path}", "RemoteDaemon");

            try
            {
                if (path.Equals("/webhook/start-server", StringComparison.OrdinalIgnoreCase) ||
                    path.Equals("/api/start", StringComparison.OrdinalIgnoreCase))
                {
                    await HandleStartServerWebhookAsync(req, resp);
                }
                else if (path.Equals("/api/stop", StringComparison.OrdinalIgnoreCase) ||
                         path.Equals("/webhook/stop-server", StringComparison.OrdinalIgnoreCase))
                {
                    await HandleStopServerWebhookAsync(req, resp);
                }
                else if (path.Equals("/api/status", StringComparison.OrdinalIgnoreCase))
                {
                    HandleStatusRequest(resp);
                }
                else if (path.Equals("/api/liveboard", StringComparison.OrdinalIgnoreCase))
                {
                    HandleLiveboardRequest(resp);
                }
                else if (path.Equals("/api/health", StringComparison.OrdinalIgnoreCase) || string.IsNullOrEmpty(path))
                {
                    await SendJsonResponseAsync(resp, HttpStatusCode.OK, new
                    {
                        status = "healthy",
                        service = "PalOdyssey Bot & Host Daemon",
                        port = _port,
                        serverRunning = _launchService.IsServerRunning
                    });
                }
                else
                {
                    await SendJsonResponseAsync(resp, HttpStatusCode.NotFound, new { error = "Endpoint not found" });
                }
            }
            catch (Exception ex)
            {
                _logService.LogError($"Exception processing {path}", "RemoteDaemon", ex);
                try
                {
                    await SendJsonResponseAsync(resp, HttpStatusCode.InternalServerError, new { error = ex.Message });
                }
                catch { }
            }
        }

        private bool IsAuthorized(HttpListenerRequest req, string? bodyKey = null)
        {
            string? headerKey = req.Headers["X-PalOdyssey-Key"] ?? req.Headers["Authorization"]?.Replace("Bearer ", "").Trim();
            if (!string.IsNullOrWhiteSpace(headerKey))
            {
                return headerKey == _accessKey;
            }
            if (!string.IsNullOrWhiteSpace(bodyKey))
            {
                return bodyKey == _accessKey;
            }
            return false;
        }

        private async Task HandleStartServerWebhookAsync(HttpListenerRequest req, HttpListenerResponse resp)
        {
            string bodyText = "";
            string? keyFromBody = null;
            string source = "Launcher Webhook";

            if (req.HasEntityBody)
            {
                using var reader = new StreamReader(req.InputStream, req.ContentEncoding);
                bodyText = await reader.ReadToEndAsync();
                try
                {
                    using var doc = JsonDocument.Parse(bodyText);
                    if (doc.RootElement.TryGetProperty("accessKey", out var k)) keyFromBody = k.GetString();
                    if (doc.RootElement.TryGetProperty("key", out var k2)) keyFromBody = k2.GetString();
                    if (doc.RootElement.TryGetProperty("source", out var s)) source = s.GetString() ?? "Launcher Webhook";
                }
                catch { }
            }

            if (!IsAuthorized(req, keyFromBody))
            {
                _logService.LogWarning("Unauthorized webhook start request received.", "RemoteDaemon");
                await SendJsonResponseAsync(resp, HttpStatusCode.Unauthorized, new { error = "Invalid or missing access key." });
                return;
            }

            // 1. Check if server process is already running and spawn/invoke if requested
            _logService.LogInfo($"Processing server start trigger from {source}. Spawning PalServer...", "RemoteDaemon");
            bool started = false;
            if (_onStartServerRequested != null)
            {
                started = await _onStartServerRequested.Invoke();
            }
            else
            {
                started = true;
            }

            // 2. Post a status message to Discord letting everyone know the server is booting
            if (_onWebhookServerBooting != null)
            {
                _ = Task.Run(async () =>
                {
                    try { await _onWebhookServerBooting.Invoke(source); }
                    catch (Exception ex) { _logService.LogWarning($"Failed to post Discord boot notification: {ex.Message}", "RemoteDaemon"); }
                });
            }

            await SendJsonResponseAsync(resp, HttpStatusCode.OK, new
            {
                success = true,
                status = "booting",
                message = "Palworld Dedicated Server boot sequence initiated successfully.",
                serverPort = 8211
            });
        }

        private async Task HandleStopServerWebhookAsync(HttpListenerRequest req, HttpListenerResponse resp)
        {
            string bodyText = "";
            string? keyFromBody = null;

            if (req.HasEntityBody)
            {
                using var reader = new StreamReader(req.InputStream, req.ContentEncoding);
                bodyText = await reader.ReadToEndAsync();
                try
                {
                    using var doc = JsonDocument.Parse(bodyText);
                    if (doc.RootElement.TryGetProperty("accessKey", out var k)) keyFromBody = k.GetString();
                    if (doc.RootElement.TryGetProperty("key", out var k2)) keyFromBody = k2.GetString();
                }
                catch { }
            }

            if (!IsAuthorized(req, keyFromBody))
            {
                await SendJsonResponseAsync(resp, HttpStatusCode.Unauthorized, new { error = "Invalid access key." });
                return;
            }

            _logService.LogInfo("Processing remote stop request...", "RemoteDaemon");
            bool stopped = false;
            if (_onStopServerRequested != null)
            {
                stopped = await _onStopServerRequested.Invoke();
            }

            await SendJsonResponseAsync(resp, HttpStatusCode.OK, new
            {
                success = stopped,
                message = stopped ? "Palworld Dedicated Server shutdown successfully." : "Failed to stop server."
            });
        }

        private void HandleStatusRequest(HttpListenerResponse resp)
        {
            var liveboard = GetCurrentLiveboard();
            var status = new RemoteServerStatus
            {
                IsOnline = true,
                IsServerRunning = liveboard.IsServerRunning,
                ProcessId = _launchService.CurrentState.ProcessId,
                ServerPort = 8211,
                UptimeSeconds = liveboard.UptimeSeconds,
                ServerName = "PalOdyssey Realm",
                Version = liveboard.Version,
                Message = liveboard.IsServerRunning ? "Server is active" : "Server is sleeping (standby)"
            };

            _ = SendJsonResponseAsync(resp, HttpStatusCode.OK, status);
        }

        private void HandleLiveboardRequest(HttpListenerResponse resp)
        {
            var liveboard = GetCurrentLiveboard();
            _ = SendJsonResponseAsync(resp, HttpStatusCode.OK, liveboard);
        }

        private string _serverVersion = "v1.0.3";
        private string _serverTitle = "PalOdyssey Realm";
        private int _serverFps = 60;

        public ServerLiveboardInfo GetCurrentLiveboard()
        {
            bool isServerActive = _launchService.IsServerRunning || LaunchService.GetActiveServerProcesses().Count > 0;

            lock (_lock)
            {
                if (!isServerActive)
                {
                    _serverStartedTime = null;
                    return new ServerLiveboardInfo
                    {
                        IsOnline = true,
                        IsServerRunning = false,
                        ServerAddress = "palodyssey.duckdns.org:8211",
                        ServerName = _serverTitle,
                        PlayerCount = 0,
                        MaxPlayers = 32,
                        UptimeSeconds = 0,
                        Version = _serverVersion,
                        IsIdleCountingDown = false,
                        IdleShutdownEnabled = _idleShutdownEnabled,
                        IdleMinutesRemaining = _idleShutdownMinutes,
                        IdleSecondsRemaining = _idleShutdownMinutes * 60,
                        ServerFps = 0
                    };
                }

                _serverStartedTime ??= DateTime.Now;
                double uptime = (DateTime.Now - _serverStartedTime.Value).TotalSeconds;

                var idleDuration = DateTime.Now - _lastActivePlayerTime;
                int totalRemainingSec = Math.Max(0, (_idleShutdownMinutes * 60) - (int)idleDuration.TotalSeconds);

                return new ServerLiveboardInfo
                {
                    IsOnline = true,
                    IsServerRunning = true,
                    ServerAddress = "palodyssey.duckdns.org:8211",
                    ServerName = _serverTitle,
                    PlayerCount = _activePlayers.Count,
                    MaxPlayers = 32,
                    UptimeSeconds = Math.Max(1, uptime),
                    Version = _serverVersion,
                    Players = new List<PlayerInfo>(_activePlayers),
                    IsIdleCountingDown = _activePlayers.Count == 0 && _idleShutdownEnabled,
                    IdleShutdownEnabled = _idleShutdownEnabled,
                    IdleMinutesRemaining = (int)Math.Ceiling(totalRemainingSec / 60.0),
                    IdleSecondsRemaining = totalRemainingSec,
                    ServerFps = _serverFps
                };
            }
        }

        private async Task IdleAutoShutdownLoopAsync(CancellationToken ct)
        {
            while (!ct.IsCancellationRequested)
            {
                try
                {
                    await Task.Delay(10000, ct); // Check every 10s for responsive countdown
                    bool isRunning = _launchService.IsServerRunning || LaunchService.GetActiveServerProcesses().Count > 0;

                    if (isRunning)
                    {
                        if (!_wasServerRunning)
                        {
                            _wasServerRunning = true;
                            _serverStartedTime = DateTime.Now;
                            _lastActivePlayerTime = DateTime.Now;
                            _shutdownTriggered = false;
                            _logService.LogSuccess("Server process detected by Watchdog. Connecting to REST API...", "AutoShutdown");
                        }

                        await QueryPalServerTelemetryAsync();

                        lock (_lock)
                        {
                            if (_activePlayers.Count > 0)
                            {
                                _lastActivePlayerTime = DateTime.Now;
                                _shutdownTriggered = false;
                            }
                            else if (_idleShutdownEnabled && !_shutdownTriggered)
                            {
                                var idleDuration = DateTime.Now - _lastActivePlayerTime;
                                var totalUptime = DateTime.Now - (_serverStartedTime ?? DateTime.Now);
                                int totalRemainingSec = (_idleShutdownMinutes * 60) - (int)idleDuration.TotalSeconds;

                                // Grace period: 2.5 minutes after server boot before executing shutdown
                                if (totalUptime.TotalMinutes >= 2.5 && totalRemainingSec <= 0)
                                {
                                    _shutdownTriggered = true;
                                    _logService.LogWarning($"[IDLE WATCHDOG] Dedicated server has been empty for {_idleShutdownMinutes} minutes. Executing graceful save and shutdown...", "AutoShutdown");

                                    _ = Task.Run(async () =>
                                    {
                                        try
                                        {
                                            // 1. Issue graceful world save via REST API
                                            try
                                            {
                                                await _palServerClient.PostAsync("http://127.0.0.1:8212/v1/api/save", null);
                                                _logService.LogSuccess("World save completed prior to shutdown.", "AutoShutdown");
                                            }
                                            catch { }

                                            // 2. Issue graceful shutdown command via REST API
                                            try
                                            {
                                                var content = new StringContent("{\"waittime\": 5, \"message\": \"PalOdyssey Server shutting down due to inactivity.\"}", Encoding.UTF8, "application/json");
                                                await _palServerClient.PostAsync("http://127.0.0.1:8212/v1/api/shutdown", content);
                                            }
                                            catch { }

                                            await Task.Delay(4000);

                                            // 3. Ensure server process is fully stopped
                                            if (_onStopServerRequested != null)
                                            {
                                                await _onStopServerRequested.Invoke();
                                            }
                                        }
                                        catch (Exception ex)
                                        {
                                            _logService.LogError("Exception during idle auto-shutdown sequence", "AutoShutdown", ex);
                                        }
                                    });
                                }
                            }
                        }
                    }
                    else
                    {
                        _wasServerRunning = false;
                        _shutdownTriggered = false;
                    }
                }
                catch (OperationCanceledException) { break; }
                catch (Exception ex)
                {
                    _logService.LogWarning($"Idle watchdog error: {ex.Message}", "AutoShutdown");
                }
            }
        }

        private async Task QueryPalServerTelemetryAsync()
        {
            try
            {
                // 1. Query Active Players
                var playersResp = await _palServerClient.GetAsync("http://127.0.0.1:8212/v1/api/players");
                if (playersResp.IsSuccessStatusCode)
                {
                    string json = await playersResp.Content.ReadAsStringAsync();
                    using var doc = JsonDocument.Parse(json);
                    if (doc.RootElement.TryGetProperty("players", out var playersArray) && playersArray.ValueKind == JsonValueKind.Array)
                    {
                        var list = new List<PlayerInfo>();
                        foreach (var item in playersArray.EnumerateArray())
                        {
                            string name = item.TryGetProperty("name", out var n) ? n.GetString() ?? "Pioneer" : "Pioneer";
                            int ping = item.TryGetProperty("ping", out var p) ? (p.ValueKind == JsonValueKind.Number ? p.GetInt32() : 25) : 25;
                            string loc = item.TryGetProperty("location", out var l) ? l.GetString() ?? "Palpagos Islands" : "Palpagos Islands";
                            int level = item.TryGetProperty("level", out var lvl) ? (lvl.ValueKind == JsonValueKind.Number ? lvl.GetInt32() : 1) : 1;
                            string steamId = item.TryGetProperty("userId", out var uid) ? uid.GetString() ?? "" : "";
                            list.Add(new PlayerInfo { Name = name, PingMs = ping, Location = loc, Level = level, SteamId = steamId });
                        }

                        lock (_lock)
                        {
                            _activePlayers.Clear();
                            _activePlayers.AddRange(list);
                        }
                    }
                }

                // 2. Query Server Metrics (FPS)
                try
                {
                    var metricsResp = await _palServerClient.GetAsync("http://127.0.0.1:8212/v1/api/metrics");
                    if (metricsResp.IsSuccessStatusCode)
                    {
                        string mJson = await metricsResp.Content.ReadAsStringAsync();
                        using var mDoc = JsonDocument.Parse(mJson);
                        if (mDoc.RootElement.TryGetProperty("serverfps", out var fpsProp) && fpsProp.ValueKind == JsonValueKind.Number)
                        {
                            lock (_lock) { _serverFps = fpsProp.GetInt32(); }
                        }
                    }
                }
                catch { }

                // 3. Query Server Info
                try
                {
                    var infoResp = await _palServerClient.GetAsync("http://127.0.0.1:8212/v1/api/info");
                    if (infoResp.IsSuccessStatusCode)
                    {
                        string iJson = await infoResp.Content.ReadAsStringAsync();
                        using var iDoc = JsonDocument.Parse(iJson);
                        if (iDoc.RootElement.TryGetProperty("version", out var vProp))
                        {
                            lock (_lock) { _serverVersion = vProp.GetString() ?? "v1.0.3"; }
                        }
                        if (iDoc.RootElement.TryGetProperty("servername", out var sProp))
                        {
                            lock (_lock) { _serverTitle = sProp.GetString() ?? "PalOdyssey Realm"; }
                        }
                    }
                }
                catch { }
            }
            catch
            {
                // PalServer REST API offline or starting up
            }
        }

        private static async Task SendJsonResponseAsync(HttpListenerResponse resp, HttpStatusCode statusCode, object data)
        {
            resp.StatusCode = (int)statusCode;
            resp.ContentType = "application/json; charset=utf-8";

            string json = JsonSerializer.Serialize(data, new JsonSerializerOptions
            {
                PropertyNamingPolicy = JsonNamingPolicy.CamelCase,
                WriteIndented = true
            });

            byte[] buffer = Encoding.UTF8.GetBytes(json);
            resp.ContentLength64 = buffer.Length;
            await resp.OutputStream.WriteAsync(buffer, 0, buffer.Length);
            resp.OutputStream.Close();
        }

        public void Dispose()
        {
            StopDaemonAsync().GetAwaiter().GetResult();
        }
    }
}
