using System;
using System.Collections.Generic;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Net.WebSockets;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using PalLauncher.Models;
using PalLauncher.Services.Interfaces;

namespace PalLauncher.Services
{
    public class DiscordBotService : IDiscordBotService
    {
        private readonly ILogService _logService;
        private readonly HttpClient _httpClient;
        private ClientWebSocket? _webSocket;
        private CancellationTokenSource? _botCts;
        private Task? _gatewayTask;
        private int? _lastSequence;
        private string? _sessionId;
        private DateTime _lastHeartbeatSent = DateTime.UtcNow;
        private DateTime _lastHeartbeatAck = DateTime.UtcNow;
        private string _token = "";
        private string _prefix = "/";
        private string? _channelId;
        private string? _adminRoleId;
        private string? _applicationId;
        private Func<Task<bool>>? _onStartServer;
        private Func<Task<bool>>? _onStopServer;
        private Func<ServerLiveboardInfo>? _getLiveboard;

        private string? _liveboardMessageId;
        private Task? _liveboardTask;

        public bool IsRunning { get; private set; }
        public string BotUsername { get; private set; } = "PalOdyssey Bot";

        public DiscordBotService(ILogService logService)
        {
            _logService = logService;
            _httpClient = new HttpClient
            {
                BaseAddress = new Uri("https://discord.com/api/v10/")
            };
            _httpClient.DefaultRequestHeaders.UserAgent.ParseAdd("DiscordBot (PalOdyssey-Launcher, 2.0.0)");
        }

        public Task<bool> StartAsync(
            string token,
            string prefix,
            string? channelId,
            string? adminRoleId,
            Func<Task<bool>> onStartServer,
            Func<Task<bool>> onStopServer,
            Func<ServerLiveboardInfo> getLiveboard)
        {
            if (string.IsNullOrWhiteSpace(token))
            {
                _logService.LogWarning("Discord Bot token is empty. Bot will not start.", "DiscordBot");
                return Task.FromResult(false);
            }

            _token = token.Trim();
            _prefix = string.IsNullOrWhiteSpace(prefix) ? "/" : prefix.Trim();
            _channelId = string.IsNullOrWhiteSpace(channelId) ? "1541492780168380446" : channelId.Trim();
            _adminRoleId = string.IsNullOrWhiteSpace(adminRoleId) ? null : adminRoleId.Trim();
            _onStartServer = onStartServer;
            _onStopServer = onStopServer;
            _getLiveboard = getLiveboard;
            _applicationId = GetApplicationId();

            _httpClient.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bot", _token);

            _botCts?.Cancel();
            _botCts = new CancellationTokenSource();

            IsRunning = true;
            _gatewayTask = Task.Run(() => RunGatewayLoopAsync(_botCts.Token));
            _liveboardTask = Task.Run(() => RunLiveboardLoopAsync(_botCts.Token));

            _logService.LogInfo($"Discord Bot service initialized (Slash Commands: '/'). 24/7 Liveboard active on channel {_channelId}. Connecting to Discord Gateway...", "DiscordBot");
            return Task.FromResult(true);
        }

        public async Task StopAsync()
        {
            IsRunning = false;
            _botCts?.Cancel();

            if (_webSocket != null)
            {
                try
                {
                    if (_webSocket.State == WebSocketState.Open)
                    {
                        await _webSocket.CloseAsync(WebSocketCloseStatus.NormalClosure, "Bot Stopping", CancellationToken.None);
                    }
                }
                catch { }
                finally
                {
                    _webSocket.Dispose();
                    _webSocket = null;
                }
            }

            _logService.LogInfo("Discord Bot service stopped.", "DiscordBot");
        }

        private async Task RunGatewayLoopAsync(CancellationToken ct)
        {
            int consecutiveFailures = 0;
            var rng = new Random();

            while (!ct.IsCancellationRequested && IsRunning)
            {
                try
                {
                    _webSocket = new ClientWebSocket();
                    var gatewayUri = new Uri("wss://gateway.discord.gg/?v=10&encoding=json");

                    _logService.LogInfo("Connecting to Discord Gateway (24/7 autonomous watchdog)...", "DiscordBot");
                    await _webSocket.ConnectAsync(gatewayUri, ct);

                    consecutiveFailures = 0;
                    _lastHeartbeatAck = DateTime.UtcNow;
                    _lastHeartbeatSent = DateTime.UtcNow;

                    await HandleGatewaySessionAsync(_webSocket, ct);
                }
                catch (OperationCanceledException)
                {
                    break;
                }
                catch (Exception ex)
                {
                    if (IsRunning && !ct.IsCancellationRequested)
                    {
                        consecutiveFailures++;
                        int backoffSec = Math.Min(30, (int)Math.Pow(2, Math.Min(consecutiveFailures, 5)));
                        int jitterMs = rng.Next(200, 1500);
                        int totalDelay = (backoffSec * 1000) + jitterMs;

                        _logService.LogWarning($"Discord Gateway connection interrupted: {ex.Message}. Reconnecting in {backoffSec}s (retry #{consecutiveFailures})...", "DiscordBot");
                        try { await Task.Delay(totalDelay, ct); } catch { break; }
                    }
                }
                finally
                {
                    try
                    {
                        if (_webSocket != null)
                        {
                            if (_webSocket.State == WebSocketState.Open)
                            {
                                await _webSocket.CloseAsync(WebSocketCloseStatus.NormalClosure, "Reconnecting", CancellationToken.None);
                            }
                            _webSocket.Dispose();
                            _webSocket = null;
                        }
                    }
                    catch { }
                }
            }
        }

        private async Task HandleGatewaySessionAsync(ClientWebSocket ws, CancellationToken ct)
        {
            var buffer = new byte[8192];
            int heartbeatIntervalMs = 41250;
            CancellationTokenSource? heartbeatCts = null;

            while (ws.State == WebSocketState.Open && !ct.IsCancellationRequested)
            {
                using var ms = new MemoryStream();
                WebSocketReceiveResult result;
                do
                {
                    result = await ws.ReceiveAsync(new ArraySegment<byte>(buffer), ct);
                    if (result.MessageType == WebSocketMessageType.Close)
                    {
                        await ws.CloseAsync(WebSocketCloseStatus.NormalClosure, "Closing", ct);
                        return;
                    }
                    ms.Write(buffer, 0, result.Count);
                } while (!result.EndOfMessage);

                ms.Seek(0, SeekOrigin.Begin);
                string json = Encoding.UTF8.GetString(ms.ToArray());

                using var doc = JsonDocument.Parse(json);
                var root = doc.RootElement;

                int op = root.GetProperty("op").GetInt32();
                if (root.TryGetProperty("s", out var sProp) && sProp.ValueKind == JsonValueKind.Number)
                {
                    _lastSequence = sProp.GetInt32();
                }

                switch (op)
                {
                    case 10: // Hello
                        heartbeatIntervalMs = root.GetProperty("d").GetProperty("heartbeat_interval").GetInt32();
                        heartbeatCts?.Cancel();
                        heartbeatCts = CancellationTokenSource.CreateLinkedTokenSource(ct);
                        _ = StartHeartbeatLoopAsync(ws, heartbeatIntervalMs, heartbeatCts.Token);
                        await SendIdentifyOrResumeAsync(ws, ct);
                        break;

                    case 11: // Heartbeat ACK
                        _lastHeartbeatAck = DateTime.UtcNow;
                        break;

                    case 0: // Dispatch
                        string eventType = root.GetProperty("t").GetString() ?? "";
                        if (eventType == "READY")
                        {
                            var readyData = root.GetProperty("d");
                            var userObj = readyData.GetProperty("user");
                            BotUsername = userObj.GetProperty("username").GetString() ?? "PalOdyssey Bot";
                            _sessionId = readyData.GetProperty("session_id").GetString();

                            if (readyData.TryGetProperty("application", out var appObj) &&
                                appObj.TryGetProperty("id", out var appIdProp))
                            {
                                _applicationId = appIdProp.GetString();
                                if (!string.IsNullOrWhiteSpace(_applicationId))
                                {
                                    _ = RegisterGlobalSlashCommandsAsync(_applicationId);
                                }
                            }

                            _logService.LogSuccess($"Discord Bot logged in successfully as @{BotUsername} (24/7 Ready)!", "DiscordBot");
                        }
                        else if (eventType == "RESUMED")
                        {
                            _logService.LogSuccess($"Discord Gateway session resumed seamlessly as @{BotUsername}!", "DiscordBot");
                        }
                        else if (eventType == "INTERACTION_CREATE")
                        {
                            var interactionData = root.GetProperty("d").Clone();
                            _ = HandleInteractionCreateAsync(interactionData);
                        }
                        else if (eventType == "MESSAGE_CREATE")
                        {
                            var msgData = root.GetProperty("d").Clone();
                            _ = HandleMessageCreateAsync(msgData);
                        }
                        break;

                    case 1: // Heartbeat requested immediately
                        await SendHeartbeatAsync(ws, ct);
                        break;

                    case 7: // Reconnect
                        _logService.LogInfo("Discord Gateway requested reconnect (OP 7). Re-establishing session...", "DiscordBot");
                        return;

                    case 9: // Invalid Session
                        bool resumable = root.TryGetProperty("d", out var dRes) && dRes.ValueKind == JsonValueKind.True;
                        if (!resumable)
                        {
                            _sessionId = null;
                            _lastSequence = null;
                        }
                        _logService.LogInfo($"Discord Gateway invalid session (resumable: {resumable}). Reconnecting...", "DiscordBot");
                        return;
                }
            }
        }

        private string GetApplicationId()
        {
            if (!string.IsNullOrWhiteSpace(_applicationId))
            {
                return _applicationId;
            }

            if (!string.IsNullOrWhiteSpace(_token))
            {
                try
                {
                    string firstPart = _token.Split('.')[0];
                    byte[] bytes = Convert.FromBase64String(firstPart.PadRight((firstPart.Length + 3) / 4 * 4, '='));
                    string decoded = Encoding.UTF8.GetString(bytes);
                    if (ulong.TryParse(decoded, out _))
                    {
                        _applicationId = decoded;
                        return decoded;
                    }
                }
                catch { }
            }

            return "1541335019899977768";
        }

        private async Task RegisterGlobalSlashCommandsAsync(string? applicationId = null)
        {
            try
            {
                string appId = !string.IsNullOrWhiteSpace(applicationId) ? applicationId : GetApplicationId();

                var commands = new object[]
                {
                    // Public Commands (Available to @everyone)
                    new
                    {
                        name = "start",
                        description = "Start and boot up the PalOdyssey Dedicated Server",
                        type = 1
                    },
                    new
                    {
                        name = "status",
                        description = "Check real-time server status, players, and uptime",
                        type = 1
                    },
                    new
                    {
                        name = "ip",
                        description = "Get the server connection IP and instructions",
                        type = 1
                    },
                    new
                    {
                        name = "help",
                        description = "List all available PalOdyssey server commands",
                        type = 1
                    },

                    // Admin-Only Commands (Restricted to Administrators)
                    new
                    {
                        name = "restart",
                        description = "Gracefully reboot the PalOdyssey Dedicated Server (Admin Only)",
                        type = 1,
                        default_member_permissions = "8"
                    },
                    new
                    {
                        name = "stop",
                        description = "Gracefully shut down the PalOdyssey dedicated server (Admin Only)",
                        type = 1,
                        default_member_permissions = "8"
                    }
                };

                string json = JsonSerializer.Serialize(commands);

                // 1. Register global slash commands (available across all servers and DMs)
                var globalContent = new StringContent(json, Encoding.UTF8, "application/json");
                var globalResp = await _httpClient.PutAsync($"applications/{appId}/commands", globalContent);
                if (globalResp.IsSuccessStatusCode)
                {
                    _logService.LogSuccess("Discord native Slash Commands (/start, /status, /ip, /restart, /stop, /help) registered globally!", "DiscordBot");
                }
                else
                {
                    string err = await globalResp.Content.ReadAsStringAsync();
                    _logService.LogWarning($"Global slash command registration returned {globalResp.StatusCode}: {err}", "DiscordBot");
                }

                // 2. Clear any lingering guild-specific commands from joined guilds to prevent duplicate entries in Discord's slash command picker
                var guildsResp = await _httpClient.GetAsync("users/@me/guilds");
                if (guildsResp.IsSuccessStatusCode)
                {
                    string guildsJson = await guildsResp.Content.ReadAsStringAsync();
                    using var doc = JsonDocument.Parse(guildsJson);
                    var emptyContent = new StringContent("[]", Encoding.UTF8, "application/json");

                    foreach (var guild in doc.RootElement.EnumerateArray())
                    {
                        string guildId = guild.GetProperty("id").GetString() ?? "";
                        string guildName = guild.TryGetProperty("name", out var n) ? n.GetString() ?? guildId : guildId;

                        if (!string.IsNullOrWhiteSpace(guildId))
                        {
                            var clearResp = await _httpClient.PutAsync($"applications/{appId}/guilds/{guildId}/commands", emptyContent);
                            if (clearResp.IsSuccessStatusCode)
                            {
                                _logService.LogInfo($"Cleared redundant guild-level commands for '{guildName}' ({guildId}) to prevent duplicates.", "DiscordBot");
                            }
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                _logService.LogWarning($"Failed to register slash commands: {ex.Message}", "DiscordBot");
            }
        }

        private async Task StartHeartbeatLoopAsync(ClientWebSocket ws, int intervalMs, CancellationToken ct)
        {
            try
            {
                var rng = new Random();
                int jitter = rng.Next(0, Math.Min(intervalMs, 5000));
                await Task.Delay(jitter, ct);

                while (!ct.IsCancellationRequested && ws.State == WebSocketState.Open)
                {
                    // Watchdog: detect zombie websocket if Heartbeat ACK was missed for > 2.5 intervals
                    if (_lastHeartbeatSent > _lastHeartbeatAck &&
                        (DateTime.UtcNow - _lastHeartbeatSent).TotalMilliseconds > (intervalMs * 2.5))
                    {
                        _logService.LogWarning("Discord Heartbeat ACK timed out (zombie connection detected). Forcing gateway reconnection...", "DiscordBot");
                        try { ws.Abort(); } catch { }
                        break;
                    }

                    await SendHeartbeatAsync(ws, ct);
                    await Task.Delay(intervalMs, ct);
                }
            }
            catch { }
        }

        private async Task SendHeartbeatAsync(ClientWebSocket ws, CancellationToken ct)
        {
            try
            {
                _lastHeartbeatSent = DateTime.UtcNow;
                string payload = JsonSerializer.Serialize(new
                {
                    op = 1,
                    d = _lastSequence
                });
                byte[] bytes = Encoding.UTF8.GetBytes(payload);
                await ws.SendAsync(new ArraySegment<byte>(bytes), WebSocketMessageType.Text, true, ct);
            }
            catch { }
        }

        private async Task SendIdentifyOrResumeAsync(ClientWebSocket ws, CancellationToken ct)
        {
            try
            {
                // If we have an existing session and sequence number, attempt to Resume first
                if (!string.IsNullOrWhiteSpace(_sessionId) && _lastSequence.HasValue)
                {
                    _logService.LogInfo($"Attempting to resume Discord session '{_sessionId}' at sequence {_lastSequence.Value}...", "DiscordBot");
                    var resumePayload = new
                    {
                        op = 6,
                        d = new
                        {
                            token = _token,
                            session_id = _sessionId,
                            seq = _lastSequence.Value
                        }
                    };

                    string resumeJson = JsonSerializer.Serialize(resumePayload);
                    byte[] resumeBytes = Encoding.UTF8.GetBytes(resumeJson);
                    await ws.SendAsync(new ArraySegment<byte>(resumeBytes), WebSocketMessageType.Text, true, ct);
                    return;
                }

                // Otherwise, send standard Identify payload
                int intents = 1 | 512 | 4096 | 32768;

                var identifyPayload = new
                {
                    op = 2,
                    d = new
                    {
                        token = _token,
                        intents = intents,
                        properties = new Dictionary<string, string>
                        {
                            { "os", "windows" },
                            { "browser", "PalOdyssey-Launcher" },
                            { "device", "PalOdyssey-Launcher" }
                        }
                    }
                };

                string json = JsonSerializer.Serialize(identifyPayload);
                byte[] bytes = Encoding.UTF8.GetBytes(json);
                await ws.SendAsync(new ArraySegment<byte>(bytes), WebSocketMessageType.Text, true, ct);
            }
            catch (Exception ex)
            {
                _logService.LogWarning($"Failed to send identify/resume payload: {ex.Message}", "DiscordBot");
            }
        }

        private async Task HandleInteractionCreateAsync(JsonElement interaction)
        {
            string interactionToken = "";
            try
            {
                string interactionId = interaction.GetProperty("id").GetString() ?? "";
                interactionToken = interaction.GetProperty("token").GetString() ?? "";
                string channelId = interaction.TryGetProperty("channel_id", out var ch) ? ch.GetString() ?? "" : "";

                if (interaction.TryGetProperty("application_id", out var appIdProp))
                {
                    string? appId = appIdProp.GetString();
                    if (!string.IsNullOrWhiteSpace(appId))
                    {
                        _applicationId = appId;
                    }
                }
                
                string authorName = "Pioneer";
                if (interaction.TryGetProperty("member", out var member) &&
                    member.TryGetProperty("user", out var mUser) &&
                    mUser.TryGetProperty("username", out var muName))
                {
                    authorName = muName.GetString() ?? "Pioneer";
                }
                else if (interaction.TryGetProperty("user", out var user) &&
                         user.TryGetProperty("username", out var uName))
                {
                    authorName = uName.GetString() ?? "Pioneer";
                }

                if (!interaction.TryGetProperty("data", out var data)) return;
                string command = data.GetProperty("name").GetString()?.ToLowerInvariant() ?? "";

                _logService.LogInfo($"Received Discord slash interaction '/{command}' from '{authorName}' in channel '{channelId}' (ID: {interactionId})", "DiscordBot");

                // Immediately ACK the interaction with a deferred response (type 5) to prevent the 3-second timeout
                await DeferInteractionAsync(interactionId, interactionToken);

                switch (command)
                {
                    case "start":
                    case "boot":
                        await ExecuteStartInteractionAsync(interactionToken, channelId, authorName);
                        break;

                    case "status":
                    case "server":
                        await ExecuteStatusInteractionAsync(interactionToken);
                        break;

                    case "ip":
                    case "connect":
                        await ExecuteIpInteractionAsync(interactionToken);
                        break;

                    case "restart":
                    case "reboot":
                        if (!IsAdminUser(interaction))
                        {
                            _logService.LogWarning($"User '{authorName}' attempted admin command '/{command}' without administrator permissions.", "DiscordBot");
                            await EditDeferredResponseEmbedAsync(interactionToken,
                                title: "⛔ Administrative Permission Required",
                                description: "❌ You do not have permission to execute this administrative command.",
                                color: 0xFF3366);
                            return;
                        }
                        await ExecuteRestartInteractionAsync(interactionToken, channelId, authorName);
                        break;

                    case "stop":
                    case "shutdown":
                        if (!IsAdminUser(interaction))
                        {
                            _logService.LogWarning($"User '{authorName}' attempted admin command '/{command}' without administrator permissions.", "DiscordBot");
                            await EditDeferredResponseEmbedAsync(interactionToken,
                                title: "⛔ Administrative Permission Required",
                                description: "❌ You do not have permission to execute this administrative command.",
                                color: 0xFF3366);
                            return;
                        }
                        await ExecuteStopInteractionAsync(interactionToken, authorName);
                        break;

                    case "help":
                        await ExecuteHelpInteractionAsync(interactionToken);
                        break;

                    default:
                        await EditDeferredResponseEmbedAsync(interactionToken,
                            title: "❓ Unknown Command",
                            description: $"The command `/{command}` is not recognized. Use `/help` to see available commands.",
                            color: 0x8899AA);
                        break;
                }
            }
            catch (Exception ex)
            {
                _logService.LogWarning($"Error handling Discord slash interaction: {ex.Message}", "DiscordBot");
                // Attempt to send an error response so Discord doesn't show "The application did not respond"
                if (!string.IsNullOrWhiteSpace(interactionToken))
                {
                    try
                    {
                        await EditDeferredResponseEmbedAsync(interactionToken,
                            title: "⚠️ Something went wrong",
                            description: "An internal error occurred while processing this command. Please try again.",
                            color: 0xFF4466);
                    }
                    catch { }
                }
            }
        }

        private bool IsAdminUser(JsonElement interaction)
        {
            // 1. Check member.permissions bitmask in guild context (ADMINISTRATOR is bit 3 = 8)
            if (interaction.TryGetProperty("member", out var member))
            {
                if (member.TryGetProperty("permissions", out var permsProp))
                {
                    string? permStr = permsProp.GetString();
                    if (ulong.TryParse(permStr, out ulong permBits))
                    {
                        const ulong administratorBit = 1UL << 3; // 8 = ADMINISTRATOR
                        if ((permBits & administratorBit) != 0)
                        {
                            return true;
                        }
                    }
                }

                // 2. Check admin role if configured
                if (!string.IsNullOrWhiteSpace(_adminRoleId) && member.TryGetProperty("roles", out var rolesProp))
                {
                    foreach (var r in rolesProp.EnumerateArray())
                    {
                        if (r.GetString() == _adminRoleId)
                        {
                            return true;
                        }
                    }
                }
            }

            // In direct DMs with bot, allow if user ID matches admin role ID (or configured admin)
            if (interaction.TryGetProperty("user", out var user))
            {
                string? uid = user.TryGetProperty("id", out var uidProp) ? uidProp.GetString() : null;
                if (!string.IsNullOrWhiteSpace(_adminRoleId) && uid == _adminRoleId)
                {
                    return true;
                }
            }

            return false;
        }

        private bool IsAdminMessageAuthor(JsonElement msg)
        {
            if (msg.TryGetProperty("member", out var member))
            {
                if (member.TryGetProperty("permissions", out var permsProp))
                {
                    string? permStr = permsProp.GetString();
                    if (ulong.TryParse(permStr, out ulong permBits))
                    {
                        const ulong administratorBit = 1UL << 3; // 8 = ADMINISTRATOR
                        if ((permBits & administratorBit) != 0)
                        {
                            return true;
                        }
                    }
                }

                if (!string.IsNullOrWhiteSpace(_adminRoleId) && member.TryGetProperty("roles", out var rolesProp))
                {
                    foreach (var r in rolesProp.EnumerateArray())
                    {
                        if (r.GetString() == _adminRoleId)
                        {
                            return true;
                        }
                    }
                }
            }

            if (msg.TryGetProperty("author", out var author))
            {
                string? uid = author.TryGetProperty("id", out var uidProp) ? uidProp.GetString() : null;
                if (!string.IsNullOrWhiteSpace(_adminRoleId) && uid == _adminRoleId)
                {
                    return true;
                }
            }

            return false;
        }

        private async Task HandleMessageCreateAsync(JsonElement msg)
        {
            try
            {
                if (msg.TryGetProperty("author", out var author) &&
                    author.TryGetProperty("bot", out var isBot) && isBot.GetBoolean())
                {
                    return;
                }

                string content = msg.TryGetProperty("content", out var cProp) ? cProp.GetString() ?? "" : "";
                string channelId = msg.TryGetProperty("channel_id", out var chProp) ? chProp.GetString() ?? "" : "";
                string authorName = author.TryGetProperty("username", out var uProp) ? uProp.GetString() ?? "Pioneer" : "Pioneer";

                if (string.IsNullOrWhiteSpace(content)) return;

                string trimmed = content.Trim();
                string command = "";

                if (trimmed.StartsWith("/", StringComparison.OrdinalIgnoreCase))
                {
                    command = trimmed[1..].Trim().ToLowerInvariant();
                }
                else if (trimmed.StartsWith("!", StringComparison.OrdinalIgnoreCase))
                {
                    command = trimmed[1..].Trim().ToLowerInvariant();
                }
                else if (trimmed.StartsWith(_prefix, StringComparison.OrdinalIgnoreCase))
                {
                    command = trimmed[_prefix.Length..].Trim().ToLowerInvariant();
                }

                if (string.IsNullOrWhiteSpace(command)) return;

                _logService.LogInfo($"Received Discord command '{content}' from '{authorName}' in channel {channelId}", "DiscordBot");

                string[] parts = command.Split(' ', StringSplitOptions.RemoveEmptyEntries);
                string mainCmd = parts[0];

                switch (mainCmd)
                {
                    case "start":
                    case "boot":
                    case "start-server":
                    case "wake":
                        await ExecuteStartCommandAsync(channelId, authorName);
                        break;

                    case "status":
                    case "server":
                    case "info":
                    case "live":
                        await ExecuteStatusCommandAsync(channelId);
                        break;

                    case "ip":
                    case "connect":
                    case "address":
                        await ExecuteIpCommandAsync(channelId);
                        break;

                    case "restart":
                    case "reboot":
                        if (!IsAdminMessageAuthor(msg))
                        {
                            _logService.LogWarning($"User '{authorName}' attempted admin message command '{mainCmd}' without administrator permissions.", "DiscordBot");
                            await SendEmbedMessageAsync(channelId,
                                title: "⛔ Administrative Permission Required",
                                description: "❌ You do not have permission to execute this administrative command.",
                                color: 0xFF3366);
                            return;
                        }
                        await ExecuteRestartCommandAsync(channelId, authorName);
                        break;

                    case "stop":
                    case "shutdown":
                        if (!IsAdminMessageAuthor(msg))
                        {
                            _logService.LogWarning($"User '{authorName}' attempted admin message command '{mainCmd}' without administrator permissions.", "DiscordBot");
                            await SendEmbedMessageAsync(channelId,
                                title: "⛔ Administrative Permission Required",
                                description: "❌ You do not have permission to execute this administrative command.",
                                color: 0xFF3366);
                            return;
                        }
                        await ExecuteStopCommandAsync(channelId, authorName);
                        break;

                    case "help":
                    case "commands":
                        await ExecuteHelpCommandAsync(channelId);
                        break;
                }
            }
            catch (Exception ex)
            {
                _logService.LogWarning($"Error processing Discord message command: {ex.Message}", "DiscordBot");
            }
        }

        private async Task ExecuteStartInteractionAsync(string interactionToken, string channelId, string authorName)
        {
            ServerLiveboardInfo liveboard;
            try { liveboard = _getLiveboard?.Invoke() ?? new ServerLiveboardInfo(); }
            catch { liveboard = new ServerLiveboardInfo(); }

            if (liveboard.IsOnline || liveboard.IsServerRunning)
            {
                await EditDeferredResponseEmbedAsync(interactionToken,
                    title: "⚡ PalOdyssey Realm is ALREADY Online!",
                    description: $"The server is already running and accepting connections.\n\n🎮 **Server Address**: `palodyssey.duckdns.org:8211`\n👥 **Pioneers**: `{liveboard.PlayerCount} / {liveboard.MaxPlayers}`\n⏱️ **Uptime**: `{liveboard.UptimeFormatted}`",
                    color: 0x00E5FF);
                return;
            }

            await EditDeferredResponseEmbedAsync(interactionToken,
                title: "🚀 Starting PalOdyssey Dedicated Server...",
                description: $"Requested by **{authorName}** via `/start`.\n\nAllocating CPU cores and preparing dedicated world state...",
                color: 0xFFAA00);

            _logService.LogInfo($"Discord user '{authorName}' triggered /start command.", "DiscordBot");

            bool started = false;
            if (_onStartServer != null)
            {
                started = await _onStartServer.Invoke();
            }

            if (!string.IsNullOrWhiteSpace(channelId))
            {
                for (int i = 0; i < 15; i++)
                {
                    await Task.Delay(2000);
                    var current = _getLiveboard?.Invoke();
                    if (current != null && (current.IsOnline || current.IsServerRunning))
                    {
                        await SendEmbedMessageAsync(channelId,
                            title: "🟢 PalOdyssey Realm is ONLINE!",
                            description: "The dedicated server is fully loaded and ready for exploration!\n\n" +
                                         "🔗 **Connection Address**: `palodyssey.duckdns.org:8211`\n" +
                                         "👥 **Max Pioneers**: `32`\n" +
                                         "✨ **1-Click Launch**: Open your PalOdyssey Launcher and click **LAUNCH GAME** to auto-connect with active mods!",
                            color: 0x00FF88);
                        return;
                    }
                }
            }
        }

        private async Task ExecuteStatusInteractionAsync(string interactionToken)
        {
            ServerLiveboardInfo liveboard;
            try { liveboard = _getLiveboard?.Invoke() ?? new ServerLiveboardInfo(); }
            catch { liveboard = new ServerLiveboardInfo(); }

            if (liveboard.IsOnline || liveboard.IsServerRunning)
            {
                await EditDeferredResponseEmbedAsync(interactionToken,
                    title: "🟢 PalOdyssey Realm — Online",
                    description: $"Server is currently active and healthy.\n\n" +
                                 $"📍 **Direct Address**: `palodyssey.duckdns.org:8211`\n" +
                                 $"👥 **Pioneers in Realm**: `{liveboard.PlayerCount} / {liveboard.MaxPlayers}`\n" +
                                 $"⏱️ **Current Uptime**: `{liveboard.UptimeFormatted}`\n" +
                                 $"💤 **Idle Auto-Shutdown**: Enabled (15m standby)",
                    color: 0x00FF88);
            }
            else
            {
                await EditDeferredResponseEmbedAsync(interactionToken,
                    title: "⚪ PalOdyssey Realm — Standby / Sleeping",
                    description: "The server is currently powered down in power-saving standby mode.\n\n" +
                                 $"👉 Type `/start` to boot it up instantly!",
                    color: 0x8899AA);
            }
        }

        private async Task ExecuteIpInteractionAsync(string interactionToken)
        {
            await EditDeferredResponseEmbedAsync(interactionToken,
                title: "🌐 PalOdyssey Server Connection Info",
                description: "### 🎮 Join Address:\n" +
                             "```\npalodyssey.duckdns.org:8211\n```\n\n" +
                             "**How to connect:**\n" +
                             "1. **Launcher (Recommended)**: Open **PalLauncher.exe** and click **LAUNCH GAME**.\n" +
                             "2. **Manual in Palworld**: Multiplayer -> Join Multiplayer Game -> Enter `palodyssey.duckdns.org:8211`.",
                color: 0x00E5FF);
        }

        private async Task ExecuteStopInteractionAsync(string interactionToken, string authorName)
        {
            _logService.LogInfo($"Discord user '{authorName}' requested server shutdown via /stop.", "DiscordBot");

            await EditDeferredResponseEmbedAsync(interactionToken,
                title: "🛑 Stopping PalOdyssey Dedicated Server...",
                description: $"Dedicated server shutdown requested by **{authorName}** via `/stop`.\n\nSaving world state and shutting down processes...",
                color: 0xFF4466);

            if (_onStopServer != null)
            {
                await _onStopServer.Invoke();
            }
        }

        private async Task ExecuteRestartInteractionAsync(string interactionToken, string channelId, string authorName)
        {
            _logService.LogInfo($"Discord user '{authorName}' requested server reboot via /restart or /reboot.", "DiscordBot");

            await EditDeferredResponseEmbedAsync(interactionToken,
                title: "🔄 Rebooting PalOdyssey Server...",
                description: $"Reboot requested by **{authorName}**.\n\nGracefully stopping world state, clearing memory caches, and rebooting engine...",
                color: 0x00E5FF);

            _ = Task.Run(async () =>
            {
                try
                {
                    if (_onStopServer != null)
                    {
                        await _onStopServer.Invoke();
                    }

                    await Task.Delay(3000);

                    if (_onStartServer != null)
                    {
                        await _onStartServer.Invoke();
                    }

                    if (!string.IsNullOrWhiteSpace(channelId))
                    {
                        for (int i = 0; i < 20; i++)
                        {
                            await Task.Delay(2000);
                            var current = _getLiveboard?.Invoke();
                            if (current != null && (current.IsOnline || current.IsServerRunning))
                            {
                                await SendEmbedMessageAsync(channelId,
                                    title: "🟢 PalOdyssey Server Reboot Complete!",
                                    description: "Dedicated server is fully back online and ready for pioneers!\n\n" +
                                                 "🔗 **Address**: `palodyssey.duckdns.org:8211`\n" +
                                                 "✨ 1-Click Launch from PalOdyssey Launcher to join!",
                                    color: 0x00FF88);
                                return;
                            }
                        }
                    }
                }
                catch (Exception ex)
                {
                    _logService.LogError("Error during server reboot", "DiscordBot", ex);
                }
            });
        }

        private async Task ExecuteHelpInteractionAsync(string interactionToken)
        {
            await EditDeferredResponseEmbedAsync(interactionToken,
                title: "📜 PalOdyssey Commands Guide",
                description: "**🌍 Public Commands (@everyone)**\n" +
                             "• `/start` — Powers up the dedicated server (24/7 auto-wake).\n" +
                             "• `/status` — Real-time server status, player count, and uptime.\n" +
                             "• `/ip` — Server endpoint address and connection guide.\n" +
                             "• `/help` — Lists all available bot commands.\n\n" +
                             "**🛡️ Administrator Commands (Admin Only)**\n" +
                             "• `/restart` — Gracefully reboots the dedicated server.\n" +
                             "• `/stop` — Safely shuts down the dedicated server.",
                color: 0x9966FF);
        }

        private async Task ExecuteStartCommandAsync(string channelId, string authorName)
        {
            var liveboard = _getLiveboard?.Invoke() ?? new ServerLiveboardInfo();

            if (liveboard.IsOnline || liveboard.IsServerRunning)
            {
                await SendEmbedMessageAsync(channelId,
                    title: "⚡ PalOdyssey Realm is ALREADY Online!",
                    description: $"The server is already running and accepting connections.\n\n🎮 **Server Address**: `palodyssey.duckdns.org:8211`\n👥 **Pioneers**: `{liveboard.PlayerCount} / {liveboard.MaxPlayers}`\n⏱️ **Uptime**: `{liveboard.UptimeFormatted}`",
                    color: 0x00E5FF);
                return;
            }

            await SendEmbedMessageAsync(channelId,
                title: "🚀 Starting PalOdyssey Dedicated Server...",
                description: $"Requested by **{authorName}**.\n\nAllocating CPU cores and preparing dedicated world state...",
                color: 0xFFAA00);

            _logService.LogInfo($"Discord user '{authorName}' triggered server start command.", "DiscordBot");

            bool started = false;
            if (_onStartServer != null)
            {
                started = await _onStartServer.Invoke();
            }

            if (!started)
            {
                await SendEmbedMessageAsync(channelId,
                    title: "⚠️ Server Start Requested",
                    description: "Server start sequence initiated on host PC. Please allow up to 15–30 seconds for Unreal Engine to finish loading.",
                    color: 0xFFAA00);
                return;
            }

            for (int i = 0; i < 15; i++)
            {
                await Task.Delay(2000);
                var current = _getLiveboard?.Invoke();
                if (current != null && (current.IsOnline || current.IsServerRunning))
                {
                    await SendEmbedMessageAsync(channelId,
                        title: "🟢 PalOdyssey Realm is ONLINE!",
                        description: "The dedicated server is fully loaded and ready for exploration!\n\n" +
                                     "🔗 **Connection Address**: `palodyssey.duckdns.org:8211`\n" +
                                     "👥 **Max Pioneers**: `32`\n" +
                                     "✨ **1-Click Launch**: Open your PalOdyssey Launcher and click **LAUNCH GAME** to auto-connect with active mods!",
                        color: 0x00FF88);
                    return;
                }
            }

            await SendEmbedMessageAsync(channelId,
                title: "🟢 Server Boot Complete",
                description: "Palworld server process initialized!\n\n🎮 **Join Address**: `palodyssey.duckdns.org:8211`",
                color: 0x00FF88);
        }

        private async Task ExecuteStatusCommandAsync(string channelId)
        {
            var liveboard = _getLiveboard?.Invoke() ?? new ServerLiveboardInfo();

            if (liveboard.IsOnline || liveboard.IsServerRunning)
            {
                await SendEmbedMessageAsync(channelId,
                    title: "🟢 PalOdyssey Realm — Online",
                    description: $"Server is currently active and healthy.\n\n" +
                                 $"📍 **Direct Address**: `palodyssey.duckdns.org:8211`\n" +
                                 $"👥 **Pioneers in Realm**: `{liveboard.PlayerCount} / {liveboard.MaxPlayers}`\n" +
                                 $"⏱️ **Current Uptime**: `{liveboard.UptimeFormatted}`\n" +
                                 $"💤 **Idle Auto-Shutdown**: Enabled (15m standby)",
                    color: 0x00FF88);
            }
            else
            {
                await SendEmbedMessageAsync(channelId,
                    title: "⚪ PalOdyssey Realm — Standby / Sleeping",
                    description: "The server is currently powered down in power-saving standby mode.\n\n" +
                                 $"👉 Type `/start` to boot it up instantly!",
                    color: 0x8899AA);
            }
        }

        private async Task ExecuteIpCommandAsync(string channelId)
        {
            await SendEmbedMessageAsync(channelId,
                title: "🌐 PalOdyssey Server Connection Info",
                description: "### 🎮 Join Address:\n" +
                             "```\npalodyssey.duckdns.org:8211\n```\n\n" +
                             "**How to connect:**\n" +
                             "1. **Launcher (Recommended)**: Open **PalLauncher.exe** and click **LAUNCH GAME**.\n" +
                             "2. **Manual in Palworld**: Multiplayer -> Join Multiplayer Game -> Enter `palodyssey.duckdns.org:8211`.",
                color: 0x00E5FF);
        }

        private async Task ExecuteStopCommandAsync(string channelId, string authorName)
        {
            _logService.LogInfo($"Discord user '{authorName}' requested server shutdown.", "DiscordBot");

            bool stopped = false;
            if (_onStopServer != null)
            {
                stopped = await _onStopServer.Invoke();
            }

            await SendEmbedMessageAsync(channelId,
                title: "🛑 PalOdyssey Server Stopped",
                description: $"Dedicated server has been stopped by **{authorName}**.\n\nType `/start` when you want to play again.",
                color: 0xFF4466);
        }

        private async Task ExecuteRestartCommandAsync(string channelId, string authorName)
        {
            _logService.LogInfo($"Discord user '{authorName}' requested server reboot via text command.", "DiscordBot");

            await SendEmbedMessageAsync(channelId,
                title: "🔄 Rebooting PalOdyssey Server...",
                description: $"Reboot requested by **{authorName}**.\n\nGracefully restarting server...",
                color: 0x00E5FF);

            _ = Task.Run(async () =>
            {
                try
                {
                    if (_onStopServer != null)
                    {
                        await _onStopServer.Invoke();
                    }

                    await Task.Delay(3000);

                    if (_onStartServer != null)
                    {
                        await _onStartServer.Invoke();
                    }

                    if (!string.IsNullOrWhiteSpace(channelId))
                    {
                        for (int i = 0; i < 20; i++)
                        {
                            await Task.Delay(2000);
                            var current = _getLiveboard?.Invoke();
                            if (current != null && (current.IsOnline || current.IsServerRunning))
                            {
                                await SendEmbedMessageAsync(channelId,
                                    title: "🟢 PalOdyssey Server Reboot Complete!",
                                    description: "Dedicated server is fully back online and ready for pioneers!\n\n" +
                                                 "🔗 **Address**: `palodyssey.duckdns.org:8211`\n" +
                                                 "✨ 1-Click Launch from PalOdyssey Launcher to join!",
                                    color: 0x00FF88);
                                return;
                            }
                        }
                    }
                }
                catch (Exception ex)
                {
                    _logService.LogError("Error during server reboot", "DiscordBot", ex);
                }
            });
        }

        private async Task ExecuteHelpCommandAsync(string channelId)
        {
            await SendEmbedMessageAsync(channelId,
                title: "📜 PalOdyssey Commands Guide",
                description: "**🌍 Public Commands (@everyone)**\n" +
                             "• `!start` or `/start` — Powers up the dedicated server (24/7 auto-wake).\n" +
                             "• `!status` or `/status` — Real-time server status, player count, and uptime.\n" +
                             "• `!ip` or `/ip` — Server endpoint address and connection guide.\n" +
                             "• `!help` or `/help` — Lists all available bot commands.\n\n" +
                             "**🛡️ Administrator Commands (Admin Only)**\n" +
                             "• `!restart` or `/restart` — Gracefully reboots the dedicated server.\n" +
                             "• `!stop` or `/stop` — Safely shuts down the dedicated server.",
                color: 0x9966FF);
        }

        private async Task DeferInteractionAsync(string interactionId, string interactionToken)
        {
            try
            {
                var payload = new
                {
                    type = 5 // DEFERRED_CHANNEL_MESSAGE_WITH_SOURCE
                };

                string json = JsonSerializer.Serialize(payload);
                var content = new StringContent(json, Encoding.UTF8, "application/json");

                // Interaction callbacks MUST NOT include the Bot Authorization header (Discord rejects it with 401 Unauthorized)
                using var request = new HttpRequestMessage(HttpMethod.Post, $"https://discord.com/api/v10/interactions/{interactionId}/{interactionToken}/callback")
                {
                    Content = content
                };

                using var callbackClient = new HttpClient();
                callbackClient.DefaultRequestHeaders.UserAgent.ParseAdd("DiscordBot (PalOdyssey-Launcher, 2.0.0)");

                var resp = await callbackClient.SendAsync(request);
                if (!resp.IsSuccessStatusCode)
                {
                    string err = await resp.Content.ReadAsStringAsync();
                    _logService.LogWarning($"Interaction defer callback returned {resp.StatusCode}: {err}", "DiscordBot");
                }
                else
                {
                    _logService.LogInfo($"Successfully deferred slash interaction ({interactionId})", "DiscordBot");
                }
            }
            catch (Exception ex)
            {
                _logService.LogWarning($"Failed to defer Discord interaction: {ex.Message}", "DiscordBot");
            }
        }

        private async Task EditDeferredResponseEmbedAsync(string interactionToken, string title, string description, int color)
        {
            try
            {
                string appId = GetApplicationId();

                var payload = new
                {
                    embeds = new[]
                    {
                        new
                        {
                            title = title,
                            description = description,
                            color = color,
                            footer = new
                            {
                                text = "PalOdyssey Autonomous Host • Automated Server Manager"
                            },
                            timestamp = DateTime.UtcNow.ToString("o")
                        }
                    }
                };

                string json = JsonSerializer.Serialize(payload);
                var content = new StringContent(json, Encoding.UTF8, "application/json");

                using var request = new HttpRequestMessage(HttpMethod.Patch, $"https://discord.com/api/v10/webhooks/{appId}/{interactionToken}/messages/@original")
                {
                    Content = content
                };

                using var webhookClient = new HttpClient();
                webhookClient.DefaultRequestHeaders.UserAgent.ParseAdd("DiscordBot (PalOdyssey-Launcher, 2.0.0)");

                var resp = await webhookClient.SendAsync(request);
                if (!resp.IsSuccessStatusCode)
                {
                    string err = await resp.Content.ReadAsStringAsync();
                    _logService.LogWarning($"Edit deferred response returned {resp.StatusCode}: {err}", "DiscordBot");
                }
                else
                {
                    _logService.LogSuccess($"Successfully edited deferred interaction response.", "DiscordBot");
                }
            }
            catch (Exception ex)
            {
                _logService.LogWarning($"Failed to edit deferred interaction response: {ex.Message}", "DiscordBot");
            }
        }

        private async Task RespondInteractionEmbedAsync(string interactionId, string interactionToken, string title, string description, int color)
        {
            try
            {
                var payload = new
                {
                    type = 4, // CHANNEL_MESSAGE_WITH_SOURCE
                    data = new
                    {
                        embeds = new[]
                        {
                            new
                            {
                                title = title,
                                description = description,
                                color = color,
                                footer = new
                                {
                                    text = "PalOdyssey Autonomous Host • Automated Server Manager"
                                },
                                timestamp = DateTime.UtcNow.ToString("o")
                            }
                        }
                    }
                };

                string json = JsonSerializer.Serialize(payload);
                var content = new StringContent(json, Encoding.UTF8, "application/json");

                // Interaction callbacks MUST NOT include the Bot Authorization header (Discord rejects it with 401 Unauthorized)
                using var request = new HttpRequestMessage(HttpMethod.Post, $"https://discord.com/api/v10/interactions/{interactionId}/{interactionToken}/callback")
                {
                    Content = content
                };

                using var callbackClient = new HttpClient();
                callbackClient.DefaultRequestHeaders.UserAgent.ParseAdd("DiscordBot (PalOdyssey-Launcher, 2.0.0)");

                var resp = await callbackClient.SendAsync(request);
                if (!resp.IsSuccessStatusCode)
                {
                    string err = await resp.Content.ReadAsStringAsync();
                    _logService.LogWarning($"Interaction callback returned {resp.StatusCode}: {err}", "DiscordBot");
                }
                else
                {
                    _logService.LogSuccess($"Successfully responded to slash interaction ({interactionId})", "DiscordBot");
                }
            }
            catch (Exception ex)
            {
                _logService.LogWarning($"Failed to respond to Discord interaction: {ex.Message}", "DiscordBot");
            }
        }

        private async Task SendEmbedMessageAsync(string channelId, string title, string description, int color)
        {
            try
            {
                var payload = new
                {
                    embeds = new[]
                    {
                        new
                        {
                            title = title,
                            description = description,
                            color = color,
                            footer = new
                            {
                                text = "PalOdyssey Autonomous Host • Automated Server Manager"
                            },
                            timestamp = DateTime.UtcNow.ToString("o")
                        }
                    }
                };

                string json = JsonSerializer.Serialize(payload);
                var content = new StringContent(json, Encoding.UTF8, "application/json");

                var resp = await _httpClient.PostAsync($"channels/{channelId}/messages", content);
                if (!resp.IsSuccessStatusCode)
                {
                    string err = await resp.Content.ReadAsStringAsync();
                    _logService.LogWarning($"Failed to send Discord message: {resp.StatusCode} - {err}", "DiscordBot");
                }
            }
            catch (Exception ex)
            {
                _logService.LogWarning($"Failed to send Discord embed: {ex.Message}", "DiscordBot");
            }
        }

        public async Task BroadcastServerBootingAsync(string triggeredBy = "Remote Webhook")
        {
            if (string.IsNullOrWhiteSpace(_channelId) || string.IsNullOrWhiteSpace(_token)) return;

            try
            {
                _logService.LogInfo($"Broadcasting server boot notification to Discord channel {_channelId} (Triggered by: {triggeredBy})...", "DiscordBot");
                await SendEmbedMessageAsync(_channelId,
                    title: "🚀 PalOdyssey Dedicated Server is BOOTING UP!",
                    description: $"Server launch triggered via **{triggeredBy}**.\n\n" +
                                 "⚡ **Status**: Allocating CPU cores, loading world save, and spinning up network sockets on port `8211`...\n\n" +
                                 "⏱️ Ready in ~15–30 seconds. A notification will post as soon as the realm is joinable!",
                    color: 0xFFAA00);

                // Spawn background watchdog to announce when online
                _ = Task.Run(async () =>
                {
                    for (int i = 0; i < 30; i++)
                    {
                        await Task.Delay(2000);
                        var current = _getLiveboard?.Invoke();
                        if (current != null && (current.IsOnline || current.IsServerRunning))
                        {
                            await BroadcastServerOnlineAsync();
                            return;
                        }
                    }
                });
            }
            catch (Exception ex)
            {
                _logService.LogWarning($"Failed to broadcast server booting to Discord: {ex.Message}", "DiscordBot");
            }
        }

        public async Task BroadcastServerOnlineAsync()
        {
            if (string.IsNullOrWhiteSpace(_channelId) || string.IsNullOrWhiteSpace(_token)) return;

            try
            {
                await SendEmbedMessageAsync(_channelId,
                    title: "🟢 PalOdyssey Realm is ONLINE!",
                    description: "The dedicated server is fully loaded and ready for exploration!\n\n" +
                                 "🔗 **Connection Address**: `palodyssey.duckdns.org:8211`\n" +
                                 "👥 **Max Pioneers**: `32`\n" +
                                 "✨ **1-Click Launch**: Open your PalOdyssey Launcher and click **LAUNCH GAME** to auto-connect with active mods!",
                    color: 0x00FF88);
            }
            catch (Exception ex)
            {
                _logService.LogWarning($"Failed to broadcast server online to Discord: {ex.Message}", "DiscordBot");
            }
        }

        private void LoadLiveboardMessageId()
        {
            try
            {
                string statePath = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    "PalLauncher",
                    "liveboard_state.json");

                if (File.Exists(statePath))
                {
                    string json = File.ReadAllText(statePath);
                    using var doc = JsonDocument.Parse(json);
                    if (doc.RootElement.TryGetProperty("messageId", out var idProp))
                    {
                        _liveboardMessageId = idProp.GetString();
                    }
                }
            }
            catch { }
        }

        private void SaveLiveboardMessageId(string messageId)
        {
            try
            {
                _liveboardMessageId = messageId;
                string dir = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    "PalLauncher");

                if (!Directory.Exists(dir)) Directory.CreateDirectory(dir);
                string statePath = Path.Combine(dir, "liveboard_state.json");
                File.WriteAllText(statePath, JsonSerializer.Serialize(new { messageId }));
            }
            catch { }
        }

        private async Task RunLiveboardLoopAsync(CancellationToken ct)
        {
            string targetChannel = !string.IsNullOrWhiteSpace(_channelId) ? _channelId : "1541492780168380446";
            LoadLiveboardMessageId();

            // Brief initial delay to allow gateway connection
            try { await Task.Delay(3000, ct); } catch { return; }

            while (!ct.IsCancellationRequested && IsRunning)
            {
                try
                {
                    await UpdateLiveboardEmbedAsync(targetChannel);
                }
                catch (OperationCanceledException) { break; }
                catch (Exception ex)
                {
                    _logService.LogWarning($"Liveboard update loop exception: {ex.Message}", "DiscordBot");
                }

                try
                {
                    await Task.Delay(30000, ct); // Auto-refresh every 30s
                }
                catch (OperationCanceledException) { break; }
            }
        }

        public async Task UpdateLiveboardEmbedAsync(string channelId)
        {
            if (string.IsNullOrWhiteSpace(_token) || string.IsNullOrWhiteSpace(channelId)) return;

            ServerLiveboardInfo liveboard;
            try { liveboard = _getLiveboard?.Invoke() ?? new ServerLiveboardInfo(); }
            catch { liveboard = new ServerLiveboardInfo(); }

            long unixSeconds = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
            bool isOnline = liveboard.IsOnline || liveboard.IsServerRunning;

            string statusBadge = isOnline ? "🟢 **ONLINE**" : "🔴 **OFFLINE (Standby)**";
            int embedColor = isOnline ? 0x00FF88 : 0x8899AA;

            var sb = new StringBuilder();
            sb.AppendLine("### 🗺️ PalOdyssey Realm Status");
            sb.AppendLine($"• **Status**: {statusBadge}");
            sb.AppendLine($"• **Address**: `palodyssey.duckdns.org:8211`");
            sb.AppendLine($"• **Uptime**: `{(isOnline ? liveboard.UptimeFormatted : "Standby (00m 00s)")}`");
            sb.AppendLine($"• **Version**: `{liveboard.Version}` *(32 Max Pioneers)*");
            sb.AppendLine();

            // Player list with Level formatting
            sb.AppendLine($"### 👥 Pioneers Online ({liveboard.PlayerCount} / {liveboard.MaxPlayers})");
            if (liveboard.Players != null && liveboard.Players.Count > 0)
            {
                foreach (var p in liveboard.Players)
                {
                    sb.AppendLine($"• **{p.Name}** (Lv. {p.Level}) — `{p.PingBadge}`");
                }
            }
            else
            {
                sb.AppendLine("*No players currently online.*");
            }
            sb.AppendLine();

            // Inactivity Watchdog Section
            sb.AppendLine("### ⏳ Inactivity Auto-Shutdown");
            if (!isOnline)
            {
                sb.AppendLine("💤 **Standby Mode**: Server is sleeping to conserve host resources. Type `/start` or launch game to wake.");
            }
            else if (liveboard.PlayerCount > 0)
            {
                sb.AppendLine($"🟢 **Active Realm**: Auto-shutdown paused while {liveboard.PlayerCount} pioneer(s) are exploring.");
            }
            else if (liveboard.IdleShutdownEnabled)
            {
                int remMin = Math.Max(0, liveboard.IdleSecondsRemaining / 60);
                int remSec = Math.Max(0, liveboard.IdleSecondsRemaining % 60);
                sb.AppendLine($"⏳ **Countdown Active**: Server will save & shut down in **{remMin}m {remSec:D2}s** if no players join.");
            }
            else
            {
                sb.AppendLine("🛡️ **24/7 Always On**: Auto-shutdown disabled.");
            }
            sb.AppendLine();

            // Connection Guide
            sb.AppendLine("### 🎮 Join Expedition");
            sb.AppendLine("1. Open **PalOdyssey Launcher** and click **LAUNCH GAME** (copies server address automatically).");
            sb.AppendLine("2. In-Game: **Join Multiplayer Game** ➔ Paste `palodyssey.duckdns.org:8211` ➔ Connect.");
            sb.AppendLine();
            sb.AppendLine($"🔄 *Last Synchronized:* <t:{unixSeconds}:R>");

            var payload = new
            {
                embeds = new[]
                {
                    new
                    {
                        title = "📡 PalOdyssey Realm — 24/7 Liveboard",
                        description = sb.ToString(),
                        color = embedColor,
                        footer = new
                        {
                            text = "PalOdyssey Autonomous Host • Auto-refreshes every 30s"
                        },
                        timestamp = DateTime.UtcNow.ToString("o")
                    }
                }
            };

            string json = JsonSerializer.Serialize(payload);
            var content = new StringContent(json, Encoding.UTF8, "application/json");

            bool messageUpdated = false;

            // 1. If we have an existing Liveboard message ID, attempt to edit it in place
            if (!string.IsNullOrWhiteSpace(_liveboardMessageId))
            {
                try
                {
                    using var editReq = new HttpRequestMessage(HttpMethod.Patch, $"channels/{channelId}/messages/{_liveboardMessageId}")
                    {
                        Content = content
                    };

                    var editResp = await _httpClient.SendAsync(editReq);
                    if (editResp.IsSuccessStatusCode)
                    {
                        messageUpdated = true;
                    }
                    else if (editResp.StatusCode == HttpStatusCode.NotFound)
                    {
                        _logService.LogInfo("Previous Liveboard message not found on Discord. Creating a fresh Liveboard embed...", "DiscordBot");
                        _liveboardMessageId = null;
                    }
                }
                catch { }
            }

            // 2. If message ID was null or edit returned 404, send a new message and save its ID
            if (!messageUpdated)
            {
                try
                {
                    var postResp = await _httpClient.PostAsync($"channels/{channelId}/messages", content);
                    if (postResp.IsSuccessStatusCode)
                    {
                        string postJson = await postResp.Content.ReadAsStringAsync();
                        using var doc = JsonDocument.Parse(postJson);
                        if (doc.RootElement.TryGetProperty("id", out var idProp))
                        {
                            string newMsgId = idProp.GetString() ?? "";
                            if (!string.IsNullOrWhiteSpace(newMsgId))
                            {
                                SaveLiveboardMessageId(newMsgId);
                                _logService.LogSuccess($"24/7 Liveboard embed created in channel {channelId} (Message ID: {newMsgId})", "DiscordBot");
                            }
                        }
                    }
                    else
                    {
                        string err = await postResp.Content.ReadAsStringAsync();
                        _logService.LogWarning($"Failed to create Liveboard message: {postResp.StatusCode} - {err}", "DiscordBot");
                    }
                }
                catch (Exception ex)
                {
                    _logService.LogWarning($"Exception posting Liveboard message: {ex.Message}", "DiscordBot");
                }
            }
        }

        public void Dispose()
        {
            _botCts?.Cancel();
            _botCts?.Dispose();
            _webSocket?.Dispose();
            _httpClient?.Dispose();
        }
    }
}

