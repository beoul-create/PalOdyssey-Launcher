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
        private DateTime _lastTelemetryQueryTime = DateTime.MinValue;

        // World Boss Aura System callbacks (set by MainViewModel after StartDaemonAsync)
        public Func<string, string, string, double, double, Task>? OnWorldBossSpawn { get; set; }
        public Func<string, string, Task>? OnWorldBossCaptured { get; set; }
        public Func<string, string, string, Task>? OnWorldBossKilled { get; set; }

        public bool IsRunning => _isRunning;
        public int Port => _port;

        private readonly HttpClient _palServerClient = new HttpClient { Timeout = TimeSpan.FromSeconds(5) };
        private readonly IConfigService _configService;

        public RemoteServerDaemon(ILogService logService, ILaunchService launchService, IConfigService? configService = null)
        {
            _logService = logService;
            _launchService = launchService;
            _configService = configService ?? new ConfigService(logService);
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
                else if (path.Equals("/api/link-account", StringComparison.OrdinalIgnoreCase) ||
                         path.Equals("/webhook/link-account", StringComparison.OrdinalIgnoreCase))
                {
                    await HandleLinkAccountAsync(req, resp);
                }
                else if (path.Equals("/api/world-boss", StringComparison.OrdinalIgnoreCase))
                {
                    await HandleWorldBossEventAsync(req, resp);
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

        private async Task HandleLinkAccountAsync(HttpListenerRequest req, HttpListenerResponse resp)
        {
            try
            {
                using var reader = new StreamReader(req.InputStream, req.ContentEncoding);
                string json = await reader.ReadToEndAsync();
                var linkReq = JsonSerializer.Deserialize<AccountLinkRequest>(json);

                if (linkReq != null && !string.IsNullOrWhiteSpace(linkReq.DiscordId) && !string.IsNullOrWhiteSpace(linkReq.SteamId))
                {
                    string dir = Path.Combine(
                        Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                        "PalLauncher");
                    if (!Directory.Exists(dir)) Directory.CreateDirectory(dir);

                    string linksFile = Path.Combine(dir, "account-links.json");
                    Dictionary<string, AccountLinkInfo> links = new();

                    if (File.Exists(linksFile))
                    {
                        try
                        {
                            string existing = await File.ReadAllTextAsync(linksFile);
                            links = JsonSerializer.Deserialize<Dictionary<string, AccountLinkInfo>>(existing) ?? new();
                        }
                        catch { }
                    }

                    var info = new AccountLinkInfo
                    {
                        DiscordId = linkReq.DiscordId,
                        DiscordUsername = linkReq.DiscordName,
                        DiscordGlobalName = linkReq.DiscordName,
                        SteamId64 = linkReq.SteamId,
                        SteamPersonaName = linkReq.SteamName,
                        PlayerUid = !string.IsNullOrWhiteSpace(linkReq.PlayerUid) ? linkReq.PlayerUid : linkReq.SteamId,
                        LinkedAt = DateTime.UtcNow,
                        IsLinked = true
                    };

                    links[linkReq.DiscordId] = info;

                    string updatedJson = JsonSerializer.Serialize(links, new JsonSerializerOptions { WriteIndented = true });
                    await File.WriteAllTextAsync(linksFile, updatedJson);

                    _logService.LogSuccess($"[ACCOUNT STORE] Persisted account link: Discord @{linkReq.DiscordName} ({linkReq.DiscordId}) ⇄ Steam {linkReq.SteamName} ({linkReq.SteamId})", "RemoteDaemon");

                    await SendJsonResponseAsync(resp, HttpStatusCode.OK, new
                    {
                        success = true,
                        message = "Account link stored successfully",
                        link = info
                    });
                    return;
                }

                await SendJsonResponseAsync(resp, HttpStatusCode.BadRequest, new { error = "Invalid account link payload" });
            }
            catch (Exception ex)
            {
                _logService.LogError("Failed to process account link request", "RemoteDaemon", ex);
                await SendJsonResponseAsync(resp, HttpStatusCode.InternalServerError, new { error = ex.Message });
            }
        }

        private async Task HandleWorldBossEventAsync(HttpListenerRequest req, HttpListenerResponse resp)
        {
            try
            {
                using var reader = new StreamReader(req.InputStream, req.ContentEncoding);
                string json = await reader.ReadToEndAsync();

                using var doc = JsonDocument.Parse(json);
                var root = doc.RootElement;

                string eventType = root.TryGetProperty("event", out var evProp) ? evProp.GetString() ?? "" : "";

                if (eventType.Equals("spawn", StringComparison.OrdinalIgnoreCase))
                {
                    string palName = root.TryGetProperty("palName", out var p) ? p.GetString() ?? "Unknown" : "Unknown";
                    string location = root.TryGetProperty("location", out var l) ? l.GetString() ?? "Unknown" : "Unknown";
                    string aura = root.TryGetProperty("aura", out var a) ? a.GetString() ?? "Fiery" : "Fiery";
                    double x = root.TryGetProperty("x", out var xp) ? xp.GetDouble() : 0;
                    double y = root.TryGetProperty("y", out var yp) ? yp.GetDouble() : 0;

                    _logService.LogInfo($"[WORLD BOSS] Spawn event: {palName} ({aura} Aura) at {location} (X:{x:F0}, Y:{y:F0})", "RemoteDaemon");

                    if (OnWorldBossSpawn != null)
                    {
                        _ = Task.Run(async () =>
                        {
                            try { await OnWorldBossSpawn.Invoke(palName, location, aura, x, y); }
                            catch (Exception ex) { _logService.LogWarning($"World Boss spawn broadcast error: {ex.Message}", "RemoteDaemon"); }
                        });
                    }

                    await SendJsonResponseAsync(resp, HttpStatusCode.OK, new { success = true, message = $"World Boss spawn event received: {palName}" });
                }
                else if (eventType.Equals("captured", StringComparison.OrdinalIgnoreCase))
                {
                    string palName = root.TryGetProperty("palName", out var p) ? p.GetString() ?? "Unknown" : "Unknown";
                    string capturedBy = root.TryGetProperty("capturedBy", out var c) ? c.GetString() ?? "Unknown Pioneer" : "Unknown Pioneer";

                    _logService.LogInfo($"[WORLD BOSS] Capture event: {palName} captured by {capturedBy}", "RemoteDaemon");

                    if (OnWorldBossCaptured != null)
                    {
                        _ = Task.Run(async () =>
                        {
                            try { await OnWorldBossCaptured.Invoke(palName, capturedBy); }
                            catch (Exception ex) { _logService.LogWarning($"World Boss capture broadcast error: {ex.Message}", "RemoteDaemon"); }
                        });
                    }

                    await SendJsonResponseAsync(resp, HttpStatusCode.OK, new { success = true, message = $"World Boss capture event received: {palName} by {capturedBy}" });
                }
                else if (eventType.Equals("killed", StringComparison.OrdinalIgnoreCase) || eventType.Equals("slain", StringComparison.OrdinalIgnoreCase))
                {
                    string palName = root.TryGetProperty("palName", out var p) ? p.GetString() ?? "Unknown" : "Unknown";
                    string killedBy = root.TryGetProperty("killedBy", out var k) ? k.GetString() ?? "Pioneers" : "Pioneers";
                    string droppedSchematic = root.TryGetProperty("schematic", out var s) ? s.GetString() ?? "Legendary Schematic" : "Legendary Schematic";

                    _logService.LogInfo($"[WORLD BOSS] Defeated event: {palName} slain by {killedBy}, dropped {droppedSchematic}", "RemoteDaemon");

                    if (OnWorldBossKilled != null)
                    {
                        _ = Task.Run(async () =>
                        {
                            try { await OnWorldBossKilled.Invoke(palName, killedBy, droppedSchematic); }
                            catch (Exception ex) { _logService.LogWarning($"World Boss defeated broadcast error: {ex.Message}", "RemoteDaemon"); }
                        });
                    }

                    await SendJsonResponseAsync(resp, HttpStatusCode.OK, new { success = true, message = $"World Boss killed event received: {palName} by {killedBy}" });
                }
                else
                {
                    await SendJsonResponseAsync(resp, HttpStatusCode.BadRequest, new { error = $"Unknown world boss event type: {eventType}" });
                }
            }
            catch (Exception ex)
            {
                _logService.LogError("Failed to process world boss event", "RemoteDaemon", ex);
                await SendJsonResponseAsync(resp, HttpStatusCode.InternalServerError, new { error = ex.Message });
            }
        }

        private string _serverVersion = "v1.0.3";
        private string _serverTitle = "PalOdyssey Realm";
        private int _serverFps = 60;

        public ServerLiveboardInfo GetCurrentLiveboard()
        {
            bool isServerActive = _launchService.IsServerRunning || LaunchService.GetActiveServerProcesses().Count > 0;

            if (isServerActive && (DateTime.Now - _lastTelemetryQueryTime).TotalSeconds >= 4)
            {
                _lastTelemetryQueryTime = DateTime.Now;
                _ = Task.Run(async () =>
                {
                    try { await QueryPalServerTelemetryAsync(); } catch { }
                });
            }

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
                                            var config = _configService?.Config;
                                            if (config == null) return;
                                            
                                            string password = config.ServerAdminPassword ?? "";
                                            int port = config.RestApiPort > 0 ? config.RestApiPort : 8212;
                                            string credentials = Convert.ToBase64String(Encoding.ASCII.GetBytes($"admin:{password}"));
                                            var authHeader = new AuthenticationHeaderValue("Basic", credentials);

                                            try
                                            {
                                                var saveReq = new HttpRequestMessage(HttpMethod.Post, $"http://127.0.0.1:{port}/v1/api/save");
                                                saveReq.Headers.Authorization = authHeader;
                                                await _palServerClient.SendAsync(saveReq);
                                                _logService.LogSuccess("World save completed prior to shutdown.", "AutoShutdown");
                                            }
                                            catch { }

                                            // 2. Issue graceful shutdown command via REST API
                                            try
                                            {
                                                var shutdownReq = new HttpRequestMessage(HttpMethod.Post, $"http://127.0.0.1:{port}/v1/api/shutdown");
                                                shutdownReq.Headers.Authorization = authHeader;
                                                shutdownReq.Content = new StringContent("{\"waittime\": 5, \"message\": \"PalOdyssey Server shutting down due to inactivity.\"}", Encoding.UTF8, "application/json");
                                                await _palServerClient.SendAsync(shutdownReq);
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

        private static int GetNumberSafe(JsonElement element, int fallback = 0)
        {
            if (element.ValueKind == JsonValueKind.Number)
            {
                if (element.TryGetInt32(out int iVal)) return iVal;
                if (element.TryGetInt64(out long lVal)) return (int)lVal;
                if (element.TryGetDouble(out double dVal)) return (int)Math.Round(dVal);
            }
            else if (element.ValueKind == JsonValueKind.String && element.GetString() is string s)
            {
                if (int.TryParse(s, out int sVal)) return sVal;
                if (double.TryParse(s, System.Globalization.NumberStyles.Any, System.Globalization.CultureInfo.InvariantCulture, out double sdVal)) return (int)Math.Round(sdVal);
            }
            return fallback;
        }

        private static string ResolveBiomeLocation(double x, double y)
        {
            if (x == 0 && y == 0) return "Palpagos Islands";
            // Windswept Hills / Plateau of Beginnings / Grassy Behemoth
            if (x >= -450000 && x <= -200000 && y >= 100000 && y <= 350000) return "Windswept Hills";
            // Mount Obsidian / Volcano
            if (x <= -450000 && y >= -550000 && y <= 200000) return "Mount Obsidian";
            // Astral Mountains / Snow Mountain
            if (x >= -250000 && x <= 50000 && y <= -100000) return "Astral Mountains";
            // Dessicated Desert / Dunes
            if (x >= 150000 && y <= 150000) return "Dessicated Desert";
            // Bamboo Groves
            if (x >= -350000 && x <= -100000 && y >= -100000 && y <= 150000) return "Bamboo Groves";
            // Sea Breeze Archipelago / South Islands
            if (y >= 300000) return "Sea Breeze Archipelago";

            return "Palpagos Islands";
        }

        private async Task QueryPalServerTelemetryAsync()
        {
            try
            {
                var config = _configService?.Config;
                if (config == null)
                {
                    _logService.LogWarning("Telemetry skipped: ConfigService or Config is null.", "Telemetry");
                    return;
                }
                
                string password = config.ServerAdminPassword ?? "";
                int port = config.RestApiPort > 0 ? config.RestApiPort : 8212;
                string credentials = Convert.ToBase64String(Encoding.ASCII.GetBytes($"admin:{password}"));
                var authHeader = new AuthenticationHeaderValue("Basic", credentials);

                // 1. Query Active Players
                var playersReq = new HttpRequestMessage(HttpMethod.Get, $"http://127.0.0.1:{port}/v1/api/players");
                playersReq.Headers.Authorization = authHeader;
                var playersResp = await _palServerClient.SendAsync(playersReq);
                if (playersResp.IsSuccessStatusCode)
                {
                    string json = await playersResp.Content.ReadAsStringAsync();
                    using var doc = JsonDocument.Parse(json);
                    if (doc.RootElement.TryGetProperty("players", out var playersArray) && playersArray.ValueKind == JsonValueKind.Array)
                    {
                        var list = new List<PlayerInfo>();
                        foreach (var item in playersArray.EnumerateArray())
                        {
                            try
                            {
                                string name = "Pioneer";
                                if (item.TryGetProperty("name", out var n) && !string.IsNullOrWhiteSpace(n.GetString()))
                                {
                                    name = n.GetString()!;
                                }
                                else if (item.TryGetProperty("accountName", out var an) && !string.IsNullOrWhiteSpace(an.GetString()))
                                {
                                    name = an.GetString()!;
                                }

                                int ping = 25;
                                if (item.TryGetProperty("ping", out var p))
                                {
                                    ping = GetNumberSafe(p, 25);
                                }

                                int level = 1;
                                if (item.TryGetProperty("level", out var lvl))
                                {
                                    level = Math.Max(1, GetNumberSafe(lvl, 1));
                                }

                                string steamId = "";
                                if (item.TryGetProperty("userId", out var uid) && !string.IsNullOrWhiteSpace(uid.GetString()))
                                {
                                    steamId = uid.GetString()!;
                                }
                                else if (item.TryGetProperty("accountId", out var aid) && !string.IsNullOrWhiteSpace(aid.GetString()))
                                {
                                    steamId = aid.GetString()!;
                                }
                                else if (item.TryGetProperty("accountName", out var anProp) && !string.IsNullOrWhiteSpace(anProp.GetString()))
                                {
                                    steamId = anProp.GetString()!;
                                }

                                string loc = "Palpagos Islands";
                                if (item.TryGetProperty("location", out var l) && !string.IsNullOrWhiteSpace(l.GetString()))
                                {
                                    loc = l.GetString()!;
                                }
                                else if (item.TryGetProperty("location_x", out var lx) && item.TryGetProperty("location_y", out var ly))
                                {
                                    double vx = 0, vy = 0;
                                    if (lx.ValueKind == JsonValueKind.Number && lx.TryGetDouble(out var dx)) vx = dx;
                                    if (ly.ValueKind == JsonValueKind.Number && ly.TryGetDouble(out var dy)) vy = dy;
                                    loc = ResolveBiomeLocation(vx, vy);
                                }

                                list.Add(new PlayerInfo { Name = name, PingMs = ping, Location = loc, Level = level, SteamId = steamId });
                            }
                            catch (Exception itemEx)
                            {
                                _logService.LogWarning($"Error parsing player item: {itemEx.Message}", "Telemetry");
                            }
                        }

                        lock (_lock)
                        {
                            _activePlayers.Clear();
                            _activePlayers.AddRange(list);
                        }
                    }
                }
                else
                {
                    // API returned a non-success status — clear stale player data
                    _logService.LogWarning($"Palworld REST API returned {(int)playersResp.StatusCode} ({playersResp.ReasonPhrase}) on /v1/api/players. Password or port mismatch? (port={port})", "Telemetry");
                    lock (_lock) { _activePlayers.Clear(); }
                }

                // 2. Query Server Metrics (FPS)
                try
                {
                    var metricsReq = new HttpRequestMessage(HttpMethod.Get, $"http://127.0.0.1:{port}/v1/api/metrics");
                    metricsReq.Headers.Authorization = authHeader;
                    var metricsResp = await _palServerClient.SendAsync(metricsReq);
                    if (metricsResp.IsSuccessStatusCode)
                    {
                        string mJson = await metricsResp.Content.ReadAsStringAsync();
                        using var mDoc = JsonDocument.Parse(mJson);
                        if (mDoc.RootElement.TryGetProperty("serverfps", out var fpsProp))
                        {
                            int fps = GetNumberSafe(fpsProp, 60);
                            lock (_lock) { _serverFps = fps; }
                        }
                    }
                }
                catch { }

                // 3. Query Server Info
                try
                {
                    var infoReq = new HttpRequestMessage(HttpMethod.Get, $"http://127.0.0.1:{port}/v1/api/info");
                    infoReq.Headers.Authorization = authHeader;
                    var infoResp = await _palServerClient.SendAsync(infoReq);
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
            catch (TaskCanceledException)
            {
                // HTTP timeout — PalServer REST API likely still starting up; clear stale data
                lock (_lock) { _activePlayers.Clear(); }
            }
            catch (HttpRequestException ex)
            {
                // Connection refused / network error — PalServer REST API offline
                _logService.LogWarning($"Telemetry connection failed (REST API may be starting): {ex.Message}", "Telemetry");
                lock (_lock) { _activePlayers.Clear(); }
            }
            catch (Exception ex)
            {
                // Unexpected error — log it instead of swallowing
                _logService.LogWarning($"Telemetry query error: {ex.Message}", "Telemetry");
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
