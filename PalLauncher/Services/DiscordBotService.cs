using System;
using System.Collections.Generic;
using System.IO;
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
        private string _token = "";
        private string _prefix = "/";
        private string? _channelId;
        private string? _adminRoleId;
        private string? _applicationId;
        private Func<Task<bool>>? _onStartServer;
        private Func<Task<bool>>? _onStopServer;
        private Func<ServerLiveboardInfo>? _getLiveboard;

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
            _channelId = string.IsNullOrWhiteSpace(channelId) ? null : channelId.Trim();
            _adminRoleId = string.IsNullOrWhiteSpace(adminRoleId) ? null : adminRoleId.Trim();
            _onStartServer = onStartServer;
            _onStopServer = onStopServer;
            _getLiveboard = getLiveboard;

            _httpClient.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Bot", _token);

            _botCts?.Cancel();
            _botCts = new CancellationTokenSource();

            IsRunning = true;
            _gatewayTask = Task.Run(() => RunGatewayLoopAsync(_botCts.Token));

            _logService.LogInfo($"Discord Bot service initialized (Slash Commands: '/'). Connecting to Discord Gateway...", "DiscordBot");
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
            while (!ct.IsCancellationRequested && IsRunning)
            {
                try
                {
                    _webSocket = new ClientWebSocket();
                    var gatewayUri = new Uri("wss://gateway.discord.gg/?v=10&encoding=json");

                    _logService.LogInfo("Connecting to Discord Gateway...", "DiscordBot");
                    await _webSocket.ConnectAsync(gatewayUri, ct);

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
                        _logService.LogWarning($"Discord Gateway connection lost: {ex.Message}. Reconnecting in 5s...", "DiscordBot");
                        try { await Task.Delay(5000, ct); } catch { break; }
                    }
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
                        await SendIdentifyAsync(ws, ct);
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

                            _logService.LogSuccess($"Discord Bot logged in successfully as @{BotUsername}!", "DiscordBot");
                        }
                        else if (eventType == "INTERACTION_CREATE")
                        {
                            var interactionData = root.GetProperty("d");
                            _ = HandleInteractionCreateAsync(interactionData);
                        }
                        else if (eventType == "MESSAGE_CREATE")
                        {
                            var msgData = root.GetProperty("d");
                            _ = HandleMessageCreateAsync(msgData);
                        }
                        break;

                    case 1: // Heartbeat requested immediately
                        await SendHeartbeatAsync(ws, ct);
                        break;

                    case 7: // Reconnect
                    case 9: // Invalid Session
                        _logService.LogInfo($"Discord Gateway requested session restart (OP {op}).", "DiscordBot");
                        return;
                }
            }
        }

        private async Task RegisterGlobalSlashCommandsAsync(string applicationId)
        {
            try
            {
                var commands = new[]
                {
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
                        name = "stop",
                        description = "Gracefully shut down the PalOdyssey dedicated server",
                        type = 1
                    },
                    new
                    {
                        name = "help",
                        description = "List all available PalOdyssey server commands",
                        type = 1
                    }
                };

                string json = JsonSerializer.Serialize(commands);
                var content = new StringContent(json, Encoding.UTF8, "application/json");
                var resp = await _httpClient.PutAsync($"applications/{applicationId}/commands", content);

                if (resp.IsSuccessStatusCode)
                {
                    _logService.LogSuccess("Discord native Slash Commands (/start, /status, /ip, /stop, /help) registered successfully!", "DiscordBot");
                }
                else
                {
                    string err = await resp.Content.ReadAsStringAsync();
                    _logService.LogWarning($"Slash command registration returned {resp.StatusCode}: {err}", "DiscordBot");
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

        private async Task SendIdentifyAsync(ClientWebSocket ws, CancellationToken ct)
        {
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

        private async Task HandleInteractionCreateAsync(JsonElement interaction)
        {
            try
            {
                string interactionId = interaction.GetProperty("id").GetString() ?? "";
                string interactionToken = interaction.GetProperty("token").GetString() ?? "";
                string channelId = interaction.TryGetProperty("channel_id", out var ch) ? ch.GetString() ?? "" : "";
                
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

                switch (command)
                {
                    case "start":
                    case "boot":
                        await ExecuteStartInteractionAsync(interactionId, interactionToken, channelId, authorName);
                        break;

                    case "status":
                    case "server":
                        await ExecuteStatusInteractionAsync(interactionId, interactionToken);
                        break;

                    case "ip":
                    case "connect":
                        await ExecuteIpInteractionAsync(interactionId, interactionToken);
                        break;

                    case "stop":
                    case "shutdown":
                        await ExecuteStopInteractionAsync(interactionId, interactionToken, authorName);
                        break;

                    case "help":
                        await ExecuteHelpInteractionAsync(interactionId, interactionToken);
                        break;
                }
            }
            catch (Exception ex)
            {
                _logService.LogWarning($"Error handling Discord slash interaction: {ex.Message}", "DiscordBot");
            }
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

                if (!string.IsNullOrWhiteSpace(_channelId) && !string.Equals(channelId, _channelId, StringComparison.OrdinalIgnoreCase))
                {
                    return;
                }

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

                    case "stop":
                    case "shutdown":
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

        private async Task ExecuteStartInteractionAsync(string interactionId, string interactionToken, string channelId, string authorName)
        {
            var liveboard = _getLiveboard?.Invoke() ?? new ServerLiveboardInfo();

            if (liveboard.IsOnline || liveboard.IsServerRunning)
            {
                await RespondInteractionEmbedAsync(interactionId, interactionToken,
                    title: "⚡ PalOdyssey Realm is ALREADY Online!",
                    description: $"The server is already running and accepting connections.\n\n🎮 **Server Address**: `palodyssey.duckdns.org:8211`\n👥 **Pioneers**: `{liveboard.PlayerCount} / {liveboard.MaxPlayers}`\n⏱️ **Uptime**: `{liveboard.UptimeFormatted}`",
                    color: 0x00E5FF);
                return;
            }

            await RespondInteractionEmbedAsync(interactionId, interactionToken,
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

        private async Task ExecuteStatusInteractionAsync(string interactionId, string interactionToken)
        {
            var liveboard = _getLiveboard?.Invoke() ?? new ServerLiveboardInfo();

            if (liveboard.IsOnline || liveboard.IsServerRunning)
            {
                await RespondInteractionEmbedAsync(interactionId, interactionToken,
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
                await RespondInteractionEmbedAsync(interactionId, interactionToken,
                    title: "⚪ PalOdyssey Realm — Standby / Sleeping",
                    description: "The server is currently powered down in power-saving standby mode.\n\n" +
                                 $"👉 Type `/start` to boot it up instantly!",
                    color: 0x8899AA);
            }
        }

        private async Task ExecuteIpInteractionAsync(string interactionId, string interactionToken)
        {
            await RespondInteractionEmbedAsync(interactionId, interactionToken,
                title: "🌐 PalOdyssey Server Connection Info",
                description: "### 🎮 Join Address:\n" +
                             "```\npalodyssey.duckdns.org:8211\n```\n\n" +
                             "**How to connect:**\n" +
                             "1. **Launcher (Recommended)**: Open **PalLauncher.exe** and click **LAUNCH GAME**.\n" +
                             "2. **Manual in Palworld**: Multiplayer -> Join Multiplayer Game -> Enter `palodyssey.duckdns.org:8211`.",
                color: 0x00E5FF);
        }

        private async Task ExecuteStopInteractionAsync(string interactionId, string interactionToken, string authorName)
        {
            _logService.LogInfo($"Discord user '{authorName}' requested server shutdown via /stop.", "DiscordBot");

            bool stopped = false;
            if (_onStopServer != null)
            {
                stopped = await _onStopServer.Invoke();
            }

            await RespondInteractionEmbedAsync(interactionId, interactionToken,
                title: "🛑 PalOdyssey Server Stopped",
                description: $"Dedicated server has been stopped by **{authorName}**.\n\nType `/start` when you want to play again.",
                color: 0xFF4466);
        }

        private async Task ExecuteHelpInteractionAsync(string interactionId, string interactionToken)
        {
            await RespondInteractionEmbedAsync(interactionId, interactionToken,
                title: "📜 PalOdyssey Slash Commands",
                description: "• `/start` — Powers up the dedicated server.\n" +
                             "• `/status` — Displays live server uptime and player count.\n" +
                             "• `/ip` — Shows server IP and quick connection instructions.\n" +
                             "• `/stop` — Powers down the server.\n" +
                             "• `/help` — Shows this slash command guide.",
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

        private async Task ExecuteHelpCommandAsync(string channelId)
        {
            await SendEmbedMessageAsync(channelId,
                title: "📜 PalOdyssey Slash Commands",
                description: "• `/start` — Powers up the dedicated server.\n" +
                             "• `/status` — Displays live server uptime and player count.\n" +
                             "• `/ip` — Shows server IP and quick connection instructions.\n" +
                             "• `/stop` — Powers down the server.\n" +
                             "• `/help` — Shows this commands guide.",
                color: 0x9966FF);
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

                var resp = await _httpClient.PostAsync($"interactions/{interactionId}/{interactionToken}/callback", content);
                if (!resp.IsSuccessStatusCode)
                {
                    string err = await resp.Content.ReadAsStringAsync();
                    _logService.LogWarning($"Interaction callback returned {resp.StatusCode}: {err}", "DiscordBot");
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

        public void Dispose()
        {
            _botCts?.Cancel();
            _botCts?.Dispose();
            _webSocket?.Dispose();
            _httpClient?.Dispose();
        }
    }
}
