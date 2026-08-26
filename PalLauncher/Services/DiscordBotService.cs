using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
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
        private readonly IEconomyService _economyService;
        private readonly IPlayerPresenceService? _presenceService;
        private readonly HttpClient _interactionClient;

        public bool IsRunning { get; private set; }
        public string BotUsername { get; private set; } = "PalOdyssey Bot";

        public DiscordBotService(ILogService logService, IEconomyService? economyService = null, IPlayerPresenceService? presenceService = null)
        {
            _logService = logService;
            _economyService = economyService ?? new EconomyService(_logService, new PalSaveService(_logService));
            _presenceService = presenceService;
            _httpClient = new HttpClient
            {
                BaseAddress = new Uri("https://discord.com/api/v10/"),
                Timeout = TimeSpan.FromSeconds(15)
            };
            _httpClient.DefaultRequestHeaders.UserAgent.ParseAdd("DiscordBot (PalOdyssey-Launcher, 2.0.0)");

            _interactionClient = new HttpClient
            {
                BaseAddress = new Uri("https://discord.com/api/v10/"),
                Timeout = TimeSpan.FromSeconds(10)
            };
            _interactionClient.DefaultRequestHeaders.UserAgent.ParseAdd("DiscordBot (PalOdyssey-Launcher, 2.0.0)");
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
            _ = RegisterGlobalSlashCommandsAsync(_applicationId);
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
                    // Public Server Commands
                    new
                    {
                        name = "deposit",
                        description = "Deposit personal Tech Points into your Guild Bank",
                        type = 1,
                        options = new object[]
                        {
                            new
                            {
                                name = "amount",
                                description = "Quantity of Technology Points to deposit",
                                type = 4, // INTEGER
                                required = true
                            },
                            new
                            {
                                name = "steam_id",
                                description = "Player UID or Steam ID (optional if linked)",
                                type = 3, // STRING
                                required = false
                            }
                        }
                    },
                    new
                    {
                        name = "guild-bank",
                        description = "View your Guild's Tech Bank balance, infrastructure caps, and contributors",
                        type = 1,
                        options = new object[]
                        {
                            new
                            {
                                name = "steam_id",
                                description = "Player UID or Steam ID (optional if linked)",
                                type = 3, // STRING
                                required = false
                            }
                        }
                    },
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
                        name = "server-info",
                        description = "Comprehensive PalOdyssey server summary, telemetry, and connection details",
                        type = 1
                    },
                    new
                    {
                        name = "info",
                        description = "View complete PalOdyssey server information and live telemetry",
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
                        name = "shop",
                        description = "Browse the Technology Point Exchange Store and Recycling valuations",
                        type = 1
                    },
                    new
                    {
                        name = "exchange",
                        description = "Exchange unspent Technology Points for rare currencies, items, or summoning slabs",
                        type = 1,
                        options = new object[]
                        {
                            new
                            {
                                name = "item",
                                description = "Item to buy (e.g. dog_coin, arena_ticket, bounty_token, pal_reverser, reset_drug, raid_boss_slab)",
                                type = 3, // STRING
                                required = true
                            },
                            new
                            {
                                name = "amount",
                                description = "Quantity to purchase (default: 1)",
                                type = 4, // INTEGER
                                required = false
                            },
                            new
                            {
                                name = "steam_id",
                                description = "Player UID or Steam ID (optional if linked)",
                                type = 3, // STRING
                                required = false
                            }
                        }
                    },
                    new
                    {
                        name = "recycle",
                        description = "Recycle vendor loot, keys, gems, or blueprints into Technology Points",
                        type = 1,
                        options = new object[]
                        {
                            new
                            {
                                name = "item",
                                description = "Item to scrap (e.g. ruby, diamond, precious_pelt, gold_key, ancient_parts, schematic)",
                                type = 3, // STRING
                                required = true
                            },
                            new
                            {
                                name = "amount",
                                description = "Quantity to recycle (default: 1)",
                                type = 4, // INTEGER
                                required = false
                            },
                            new
                            {
                                name = "steam_id",
                                description = "Player UID or Steam ID (optional if linked)",
                                type = 3, // STRING
                                required = false
                            }
                        }
                    },
                    new
                    {
                        name = "scrap",
                        description = "Alias for /recycle - Scrap loot and blueprints into Technology Points",
                        type = 1,
                        options = new object[]
                        {
                            new
                            {
                                name = "item",
                                description = "Item to scrap (e.g. ruby, diamond, precious_pelt, gold_key, ancient_parts, schematic)",
                                type = 3, // STRING
                                required = true
                            },
                            new
                            {
                                name = "amount",
                                description = "Quantity to scrap (default: 1)",
                                type = 4, // INTEGER
                                required = false
                            },
                            new
                            {
                                name = "steam_id",
                                description = "Player UID or Steam ID (optional if linked)",
                                type = 3, // STRING
                                required = false
                            }
                        }
                    },
                    new
                    {
                        name = "inventory",
                        description = "View your Pioneer Character's Tech Points and Virtual Vault delivery depot",
                        type = 1,
                        options = new object[]
                        {
                            new
                            {
                                name = "steam_id",
                                description = "Player UID or Steam ID (optional if linked)",
                                type = 3, // STRING
                                required = false
                            }
                        }
                    },
                    new
                    {
                        name = "link",
                        description = "Link your Discord user account to your Palworld Player UID or Steam ID",
                        type = 1,
                        options = new object[]
                        {
                            new
                            {
                                name = "steam_id",
                                description = "Your Palworld Player UID or Steam ID",
                                type = 3, // STRING
                                required = true
                            }
                        }
                    },
                    new
                    {
                        name = "gacha",
                        description = "Open Mystery Boxes or Ancient Relic Boxes for rare loot, lotus fruits, and legendary schematics",
                        type = 1,
                        options = new object[]
                        {
                            new
                            {
                                name = "pulls",
                                description = "Number of pulls (1 or 10)",
                                type = 4, // INTEGER
                                required = false,
                                choices = new object[]
                                {
                                    new { name = "1 Pull", value = 1 },
                                    new { name = "10 Pulls (Discount + Pity Guarantee)", value = 10 }
                                }
                            },
                            new
                            {
                                name = "tier",
                                description = "Gacha Tier: Standard (3 Tech Pts) or Ancient (2 Ancient Pts for Sacred Lotus/Cores)",
                                type = 3, // STRING
                                required = false,
                                choices = new object[]
                                {
                                    new { name = "🪙 Standard Mystery Box (3 Tech Points)", value = "standard" },
                                    new { name = "🔮 Ancient Relic Box (2 Ancient Points)", value = "ancient" }
                                }
                            },
                            new
                            {
                                name = "steam_id",
                                description = "Player UID or Steam ID (optional if linked)",
                                type = 3, // STRING
                                required = false
                            }
                        }
                    },
                    new
                    {
                        name = "transmute",
                        description = "Transmute Ancient Technology Points into Standard Technology Points (1 Ancient = 2 Normal)",
                        type = 1,
                        options = new object[]
                        {
                            new
                            {
                                name = "ancient_points",
                                description = "Amount of Ancient Technology Points to convert (1 Ancient = 2 Normal Tech Points)",
                                type = 4, // INTEGER
                                required = true
                            },
                            new
                            {
                                name = "steam_id",
                                description = "Player UID or Steam ID (optional if linked)",
                                type = 3, // STRING
                                required = false
                            }
                        }
                    },
                    new
                    {
                        name = "convert",
                        description = "Alias for /transmute - Convert Ancient Technology Points into Standard Tech Points",
                        type = 1,
                        options = new object[]
                        {
                            new
                            {
                                name = "ancient_points",
                                description = "Amount of Ancient Technology Points to convert",
                                type = 4, // INTEGER
                                required = true
                            },
                            new
                            {
                                name = "steam_id",
                                description = "Player UID or Steam ID (optional if linked)",
                                type = 3, // STRING
                                required = false
                            }
                        }
                    },
                    new
                    {
                        name = "perk",
                        description = "Upgrade Guild & Server Perks using Ancient Technology Points",
                        type = 1,
                        options = new object[]
                        {
                            new
                            {
                                name = "upgrade",
                                description = "Perk to upgrade: Work Speed (5 Ancient Pts = +1%) or EXP Boost (20 Ancient Pts = +5%)",
                                type = 3, // STRING
                                required = true,
                                choices = new object[]
                                {
                                    new { name = "⚡ Base Pal Work & Movement Speed (5 Ancient Pts = +1%)", value = "work_speed" },
                                    new { name = "🌟 Global Server EXP Boost (20 Ancient Pts = +5%)", value = "exp_boost" }
                                }
                            },
                            new
                            {
                                name = "steam_id",
                                description = "Player UID or Steam ID (optional if linked)",
                                type = 3, // STRING
                                required = false
                            }
                        }
                    },
                    new
                    {
                        name = "perks",
                        description = "View active Guild & Server Perks, total Base Pal speed boosts, and EXP modifiers",
                        type = 1
                    },
                    new
                    {
                        name = "withdraw",
                        description = "Withdraw and claim items from your Virtual Vault into your live Palworld character",
                        type = 1,
                        options = new object[]
                        {
                            new
                            {
                                name = "item",
                                description = "Item name to withdraw (or 'all' for everything)",
                                type = 3, // STRING
                                required = false
                            },
                            new
                            {
                                name = "amount",
                                description = "Quantity to withdraw (default: all available)",
                                type = 4, // INTEGER
                                required = false
                            },
                            new
                            {
                                name = "steam_id",
                                description = "Player UID or Steam ID (optional if linked)",
                                type = 3, // STRING
                                required = false
                            }
                        }
                    },
                    new
                    {
                        name = "claim",
                        description = "Alias for /withdraw - Claim stored items into your live Palworld character",
                        type = 1,
                        options = new object[]
                        {
                            new
                            {
                                name = "item",
                                description = "Item name to claim (or 'all' for everything)",
                                type = 3, // STRING
                                required = false
                            },
                            new
                            {
                                name = "amount",
                                description = "Quantity to claim (default: all available)",
                                type = 4, // INTEGER
                                required = false
                            },
                            new
                            {
                                name = "steam_id",
                                description = "Player UID or Steam ID (optional if linked)",
                                type = 3, // STRING
                                required = false
                            }
                        }
                    },
                    new
                    {
                        name = "help",
                        description = "List all available PalOdyssey server and economy commands",
                        type = 1
                    },

                    // Admin-Only Commands (Restricted to Administrators)
                    new
                    {
                        name = "setpoints",
                        description = "Directly set a player's Technology or Boss Points balance (Admin Only)",
                        type = 1,
                        default_member_permissions = "8",
                        options = new object[]
                        {
                            new
                            {
                                name = "user",
                                description = "Discord @user, SteamID64, or Player UID",
                                type = 3,
                                required = true
                            },
                            new
                            {
                                name = "points",
                                description = "Exact point balance to set (e.g. 50)",
                                type = 4,
                                required = true
                            },
                            new
                            {
                                name = "currency",
                                description = "Currency type: tech_points (Standard) or boss_points (Ancient)",
                                type = 3,
                                required = false,
                                choices = new object[]
                                {
                                    new { name = "Technology Points (Standard)", value = "tech_points" },
                                    new { name = "Ancient Boss Points (Boss)", value = "boss_points" }
                                }
                            }
                        }
                    },
                    new
                    {
                        name = "grantpoints",
                        description = "Grant or deduct Technology or Boss Points for a player (Admin Only)",
                        type = 1,
                        default_member_permissions = "8",
                        options = new object[]
                        {
                            new
                            {
                                name = "user",
                                description = "Discord @user, SteamID64, or Player UID",
                                type = 3,
                                required = true
                            },
                            new
                            {
                                name = "points",
                                description = "Number of points to grant (e.g. 10 or -5)",
                                type = 4,
                                required = true
                            },
                            new
                            {
                                name = "currency",
                                description = "Currency type: tech_points (Standard) or boss_points (Ancient)",
                                type = 3,
                                required = false,
                                choices = new object[]
                                {
                                    new { name = "Technology Points (Standard)", value = "tech_points" },
                                    new { name = "Ancient Boss Points (Boss)", value = "boss_points" }
                                }
                            }
                        }
                    },
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
                    _logService.LogSuccess("Discord native Slash Commands (/start, /status, /ip, /shop, /exchange, /recycle, /gacha, /inventory, /link, /restart, /stop, /help) registered globally!", "DiscordBot");
                }
                else
                {
                    string err = await globalResp.Content.ReadAsStringAsync();
                    _logService.LogWarning($"Global slash command registration returned {globalResp.StatusCode}: {err}", "DiscordBot");
                }

                // 2. Also register commands directly to all joined Discord Servers (Guilds) for INSTANT availability (bypasses Discord's 1-hour global propagation delay!)
                var guildsResp = await _httpClient.GetAsync("users/@me/guilds");
                if (guildsResp.IsSuccessStatusCode)
                {
                    string guildsJson = await guildsResp.Content.ReadAsStringAsync();
                    using var doc = JsonDocument.Parse(guildsJson);
                    var guildContent = new StringContent(json, Encoding.UTF8, "application/json");

                    foreach (var guild in doc.RootElement.EnumerateArray())
                    {
                        string guildId = guild.GetProperty("id").GetString() ?? "";
                        string guildName = guild.TryGetProperty("name", out var n) ? n.GetString() ?? guildId : guildId;

                        if (!string.IsNullOrWhiteSpace(guildId))
                        {
                            var gResp = await _httpClient.PutAsync($"applications/{appId}/guilds/{guildId}/commands", guildContent);
                            if (gResp.IsSuccessStatusCode)
                            {
                                _logService.LogSuccess($"[INSTANT SYNC] Synchronized {commands.Length} slash commands directly to Discord server '{guildName}' ({guildId})!", "DiscordBot");
                            }
                            else
                            {
                                string gErr = await gResp.Content.ReadAsStringAsync();
                                _logService.LogWarning($"Guild slash command registration for '{guildName}' ({guildId}) returned {gResp.StatusCode}: {gErr}", "DiscordBot");
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
                
                string authorId = "";
                string authorName = "Pioneer";
                if (interaction.TryGetProperty("member", out var member) &&
                    member.TryGetProperty("user", out var mUser))
                {
                    authorId = mUser.TryGetProperty("id", out var mid) ? mid.GetString() ?? "" : "";
                    authorName = mUser.TryGetProperty("username", out var muName) ? muName.GetString() ?? "Pioneer" : "Pioneer";
                }
                else if (interaction.TryGetProperty("user", out var user))
                {
                    authorId = user.TryGetProperty("id", out var uid) ? uid.GetString() ?? "" : "";
                    authorName = user.TryGetProperty("username", out var uName) ? uName.GetString() ?? "Pioneer" : "Pioneer";
                }

                if (!interaction.TryGetProperty("data", out var data)) return;
                string command = data.GetProperty("name").GetString()?.ToLowerInvariant() ?? "";

                // 1. Instant commands: Answer in a single HTTP packet (<50ms) without defer latency
                switch (command)
                {
                    case "shop":
                    case "store":
                        await ExecuteShopDirectInteractionAsync(interactionId, interactionToken, authorId);
                        return;

                    case "help":
                        await ExecuteHelpDirectInteractionAsync(interactionId, interactionToken);
                        return;

                    case "ip":
                    case "connect":
                        await ExecuteIpDirectInteractionAsync(interactionId, interactionToken);
                        return;

                    case "status":
                    case "server":
                    case "server-info":
                    case "serverinfo":
                    case "info":
                        await ExecuteStatusDirectInteractionAsync(interactionId, interactionToken);
                        return;
                }

                // 2. Heavy/Async commands: Immediately ACK with deferred response (type 5)
                bool isEphemeral = command switch
                {
                    "recycle" => true,
                    "scrap" => true,
                    "deposit" => true,
                    "guild-bank" => true,
                    _ => false
                };

                await DeferInteractionAsync(interactionId, interactionToken, isEphemeral);

                switch (command)
                {
                    case "start":
                    case "boot":
                        await ExecuteStartInteractionAsync(interactionToken, channelId, authorName);
                        break;

                    case "deposit":
                        await ExecuteDepositInteractionAsync(interactionToken, data, authorId, authorName);
                        break;

                    case "guild-bank":
                        await ExecuteGuildBankInteractionAsync(interactionToken, data, authorId, authorName);
                        break;

                    case "exchange":
                    case "buy":
                        await ExecuteExchangeInteractionAsync(interactionToken, data, authorId, authorName);
                        break;

                    case "recycle":
                    case "scrap":
                        await ExecuteRecycleInteractionAsync(interactionToken, data, authorId, authorName);
                        break;

                    case "inventory":
                    case "vault":
                        await ExecuteInventoryInteractionAsync(interactionToken, data, authorId, authorName);
                        break;

                    case "withdraw":
                    case "claim":
                        await ExecuteWithdrawInteractionAsync(interactionToken, data, authorId, authorName);
                        break;

                    case "link":
                        await ExecuteLinkInteractionAsync(interactionToken, data, authorId, authorName);
                        break;

                    case "gacha":
                    case "mysterybox":
                    case "relic":
                        await ExecuteGachaInteractionAsync(interactionToken, data, authorId, authorName);
                        break;

                    case "transmute":
                    case "convert":
                        await ExecuteTransmuteInteractionAsync(interactionToken, data, authorId, authorName);
                        break;

                    case "perk":
                    case "perks":
                        await ExecutePerkInteractionAsync(interactionToken, data, authorId, authorName);
                        break;

                    case "setpoints":
                        if (!IsAdminUser(interaction))
                        {
                            _logService.LogWarning($"User '{authorName}' attempted admin command '/{command}' without administrator permissions.", "DiscordBot");
                            await EditDeferredResponseEmbedAsync(interactionToken,
                                title: "⛔ Administrative Permission Required",
                                description: "❌ You do not have permission to execute this administrative command.",
                                color: 0xFF3366);
                            return;
                        }
                        await ExecuteSetPointsInteractionAsync(interactionToken, data, authorName);
                        break;

                    case "grantpoints":
                    case "addpoints":
                        if (!IsAdminUser(interaction))
                        {
                            _logService.LogWarning($"User '{authorName}' attempted admin command '/{command}' without administrator permissions.", "DiscordBot");
                            await EditDeferredResponseEmbedAsync(interactionToken,
                                title: "⛔ Administrative Permission Required",
                                description: "❌ You do not have permission to execute this administrative command.",
                                color: 0xFF3366);
                            return;
                        }
                        await ExecuteGrantPointsInteractionAsync(interactionToken, data, authorName);
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

                    case "shop":
                    case "store":
                        await ExecuteShopCommandAsync(channelId);
                        break;

                    case "setpoints":
                        if (!IsAdminMessageAuthor(msg))
                        {
                            _logService.LogWarning($"User '{authorName}' attempted admin message command '{mainCmd}' without administrator permissions.", "DiscordBot");
                            await SendEmbedMessageAsync(channelId,
                                title: "⛔ Administrative Permission Required",
                                description: "❌ You do not have permission to execute this administrative command.",
                                color: 0xFF3366);
                            return;
                        }
                        await ExecuteSetPointsCommandAsync(channelId, trimmed, authorName);
                        break;

                    case "grantpoints":
                    case "addpoints":
                        if (!IsAdminMessageAuthor(msg))
                        {
                            _logService.LogWarning($"User '{authorName}' attempted admin message command '{mainCmd}' without administrator permissions.", "DiscordBot");
                            await SendEmbedMessageAsync(channelId,
                                title: "⛔ Administrative Permission Required",
                                description: "❌ You do not have permission to execute this administrative command.",
                                color: 0xFF3366);
                            return;
                        }
                        await ExecuteGrantPointsCommandAsync(channelId, trimmed, authorName);
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

            bool isOnline = liveboard.IsOnline || liveboard.IsServerRunning;
            int color = isOnline ? 0x00FF88 : 0x8899AA;
            string title = isOnline ? "📡 PalOdyssey Realm — Server Info & Telemetry" : "💤 PalOdyssey Realm — Standby (Power-Saving)";

            await EditDeferredResponseEmbedAsync(interactionToken,
                title: title,
                description: liveboard.BuildDiscordSummaryMarkdown(),
                color: color);
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
            bool isOnline = liveboard.IsOnline || liveboard.IsServerRunning;
            int color = isOnline ? 0x00FF88 : 0x8899AA;
            string title = isOnline ? "📡 PalOdyssey Realm — Server Info & Telemetry" : "💤 PalOdyssey Realm — Standby (Power-Saving)";

            await SendEmbedMessageAsync(channelId,
                title: title,
                description: liveboard.BuildDiscordSummaryMarkdown(),
                color: color);
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
                description: "**🌍 Public Server Commands**\n" +
                             "• `/start` — Powers up the dedicated server (24/7 auto-wake).\n" +
                             "• `/status` — Real-time server status, player count, and uptime.\n" +
                             "• `/ip` — Server endpoint address and connection guide.\n" +
                             "• `/help` — Lists all available bot commands.\n\n" +
                             "**🏛️ Technology Point Economy & Exchange**\n" +
                             "• `/shop` — Browse the Technology Point Exchange Store & Recycling rates.\n" +
                             "• `/exchange item:<name> amount:<qty>` — Trade unspent Tech Points for Dog Coins, Arena Tickets, Slabs, and Elixirs.\n" +
                             "• `/recycle item:<name> amount:<qty>` — Scrap vendor junk, gems, keys, and schematics into Tech Points.\n" +
                             "• `/gacha pulls:<1|10>` — Open Relic Mystery Boxes for random loot (3 pts / 1 pull, 25 pts / 10-pull w/ pity).\n" +
                             "• `/inventory` — View character Tech Points balance and Virtual Vault.\n" +
                             "• `/link steam_id:<id>` — Link your Discord account to your Palworld character save.\n\n" +
                             "**🛡️ Administrator Commands (Admin Only)**\n" +
                             "• `/restart` — Gracefully reboots the dedicated server.\n" +
                             "• `/stop` — Safely shuts down the dedicated server.",
                color: 0x9966FF);
        }

        private string BuildShopCatalogDescription(PlayerEconomyProfile? profile = null)
        {
            var catalog = _economyService.GetShopCatalog();
            var perks = _economyService.GetGuildPerks();

            var sb = new StringBuilder();
            if (profile != null)
            {
                string pName = !string.IsNullOrWhiteSpace(profile.PlayerName) ? profile.PlayerName : "Pioneer";
                sb.AppendLine($"### 👤 Pioneer: `{pName}`");
                sb.AppendLine($"• **🪙 Technology Points**: `{profile.TechnologyPoints} pts`");
                sb.AppendLine($"• **🔮 Ancient Boss Points**: `{profile.BossTechnologyPoints} pts`\n");
            }

            sb.AppendLine("Trade unspent **Standard & Ancient Technology Points** for sacred lotus fruits, skill chests, currencies, passives, and guild upgrades!\n");

            sb.AppendLine("### 🔮 Ancient Relics & Sacred Lotus Fruits (`/exchange`)");
            foreach (var item in catalog.Where(i => i.Category.Equals("Ancient", StringComparison.OrdinalIgnoreCase)))
            {
                sb.AppendLine($"{item.Emoji} **{item.Name}** (`{item.Id}`) — `🔮 {item.AncientPointCost} Ancient pts`\n  ↳ *{item.Description}*");
            }
            sb.AppendLine();

            sb.AppendLine("### 🪙 Standard Technology Items (`/exchange`)");
            foreach (var item in catalog.Where(i => !i.Category.Equals("Ancient", StringComparison.OrdinalIgnoreCase)))
            {
                sb.AppendLine($"{item.Emoji} **{item.Name}** (`{item.Id}`) — `🪙 {item.TechPointCost} Tech pts`");
            }
            sb.AppendLine();

            sb.AppendLine("### ⚗️ Ancient Transmutation & Conversion (`/transmute`)");
            sb.AppendLine("• 🔮 **1 Ancient Technology Point** ➔ `🪙 +2 Standard Technology Points`\n");

            sb.AppendLine("### 🏰 Guild & Server Perks (`/perk` | `/perks`)");
            sb.AppendLine($"• ⚡ **Base Pal Work & Movement Speed**: `5 Ancient Pts` = `+1% Speed` (Active: **+{perks.TotalWorkSpeedPercent}%**)");
            sb.AppendLine($"• 🌟 **Global Server EXP Boost**: `20 Ancient Pts` = `+5% EXP` (Active: **+{perks.TotalExpBoostPercent}%**)\n");

            sb.AppendLine("### 🎰 Mystery & Ancient Gacha Tiers (`/gacha`)");
            sb.AppendLine("• 🪙 **Standard Mystery Box**: `3 Tech Pts` (1 pull) | `25 Tech Pts` (10 pulls)");
            sb.AppendLine("• 🔮 **Ancient Relic Box**: `2 Ancient Pts` (1 pull) | `18 Ancient Pts` (10 pulls)\n");

            sb.AppendLine("### ♻️ Trash-to-Tech Recycling Rates (`/recycle`)");
            sb.AppendLine("• 🥋 **Precious Pelts / Feathers / Claws**: `+1 pt per 2 items`");
            sb.AppendLine("• 🫀 **Precious Entrails / Dragon Stone**: `+1 pt each`");
            sb.AppendLine("• 💎 **Ruby / Sapphire / Emerald / Diamond**: `+1 to +2 pts each`");
            sb.AppendLine("• 🗝️ **Bronze / Silver / Gold Keys**: `+1 per 3 Bronze, +1 Silver, +2 Gold`");
            sb.AppendLine("• ⚙️ **Ancient Civ Parts**: `+1 pt per 5` | 🧩 **Raid Slabs**: `+1 pt each`\n");

            sb.AppendLine("💡 *Commands:* `/exchange` | `/transmute` | `/perk` | `/gacha` | `/withdraw` | `/inventory`");
            return sb.ToString();
        }

        private async Task ExecuteShopCommandAsync(string channelId)
        {
            await SendEmbedMessageAsync(channelId,
                title: "🏛️ PalOdyssey Technology Exchange & Recycling",
                description: BuildShopCatalogDescription(),
                color: 0x00E5FF);
        }

        private async Task ExecuteHelpDirectInteractionAsync(string interactionId, string interactionToken)
        {
            await RespondInteractionEmbedAsync(interactionId, interactionToken,
                title: "📜 PalOdyssey Commands Guide",
                description: "**🌍 Public Server Commands**\n" +
                             "• `/start` — Powers up the dedicated server (24/7 auto-wake).\n" +
                             "• `/status` — Real-time server status, player count, and uptime.\n" +
                             "• `/ip` — Server endpoint address and connection guide.\n" +
                             "• `/help` — Lists all available bot commands.\n\n" +
                             "**🏛️ Technology Point Economy & Exchange**\n" +
                             "• `/shop` — Browse the Technology Point Exchange Store & Recycling rates.\n" +
                             "• `/exchange item:<name> amount:<qty>` — Trade unspent Tech Points for Dog Coins, Arena Tickets, Slabs, and Elixirs.\n" +
                             "• `/recycle item:<name> amount:<qty>` — Scrap vendor junk, gems, keys, and schematics into Tech Points.\n" +
                             "• `/gacha pulls:<1|10>` — Open Relic Mystery Boxes for random loot (3 pts / 1 pull, 25 pts / 10-pull w/ pity).\n" +
                             "• `/inventory` — View character Tech Points balance and Virtual Vault.\n" +
                             "• `/link steam_id:<id>` — Link your Discord account to your Palworld character save.\n\n" +
                             "**🛡️ Administrator Commands (Admin Only)**\n" +
                             "• `/restart` — Gracefully reboots the dedicated server.\n" +
                             "• `/stop` — Safely shuts down the dedicated server.",
                color: 0x9966FF,
                ephemeral: true);
        }

        private async Task ExecuteShopDirectInteractionAsync(string interactionId, string interactionToken, string authorId)
        {
            PlayerEconomyProfile? profile = null;
            if (!string.IsNullOrWhiteSpace(authorId))
            {
                string linkedUid = _economyService.GetLinkedPlayerUid(authorId);
                if (!string.IsNullOrWhiteSpace(linkedUid))
                {
                    try
                    {
                        profile = await _economyService.GetPlayerProfileAsync(linkedUid, forceLiveRefresh: true);
                    }
                    catch { }
                }
            }

            await RespondInteractionEmbedAsync(interactionId, interactionToken,
                title: "🏛️ PalOdyssey Technology Exchange & Recycling",
                description: BuildShopCatalogDescription(profile),
                color: 0x00E5FF,
                ephemeral: true);
        }

        private async Task ExecuteShopInteractionAsync(string interactionToken, string authorId)
        {
            PlayerEconomyProfile? profile = null;
            if (!string.IsNullOrWhiteSpace(authorId))
            {
                string linkedUid = _economyService.GetLinkedPlayerUid(authorId);
                if (!string.IsNullOrWhiteSpace(linkedUid))
                {
                    try
                    {
                        profile = await _economyService.GetPlayerProfileAsync(linkedUid, forceLiveRefresh: true);
                    }
                    catch { }
                }
            }

            await EditDeferredResponseEmbedAsync(interactionToken,
                title: "🏛️ PalOdyssey Technology Exchange & Recycling",
                description: BuildShopCatalogDescription(profile),
                color: 0x00E5FF);
        }

        private async Task ExecuteIpDirectInteractionAsync(string interactionId, string interactionToken)
        {
            await RespondInteractionEmbedAsync(interactionId, interactionToken,
                title: "🌐 PalOdyssey Server Connection Info",
                description: "### 🎮 Join Address:\n" +
                             "```\npalodyssey.duckdns.org:8211\n```\n\n" +
                             "**How to connect:**\n" +
                             "1. **Launcher (Recommended)**: Open **PalLauncher.exe** and click **LAUNCH GAME**.\n" +
                             "2. **Manual in Palworld**: Multiplayer -> Join Multiplayer Game -> Enter `palodyssey.duckdns.org:8211`.",
                color: 0x00E5FF,
                ephemeral: false);
        }

        private async Task ExecuteStatusDirectInteractionAsync(string interactionId, string interactionToken)
        {
            ServerLiveboardInfo liveboard;
            try { liveboard = _getLiveboard?.Invoke() ?? new ServerLiveboardInfo(); }
            catch { liveboard = new ServerLiveboardInfo(); }

            bool isOnline = liveboard.IsOnline || liveboard.IsServerRunning;
            int color = isOnline ? 0x00FF88 : 0x8899AA;
            string title = isOnline ? "📡 PalOdyssey Realm — Server Info & Telemetry" : "💤 PalOdyssey Realm — Standby (Power-Saving)";

            await RespondInteractionEmbedAsync(interactionId, interactionToken,
                title: title,
                description: liveboard.BuildDiscordSummaryMarkdown(),
                color: color,
                ephemeral: false);
        }



        private async Task ExecuteDepositInteractionAsync(string interactionToken, JsonElement data, string authorId, string authorName)
        {
            int amount = Math.Max(1, GetIntOption(data, "amount", 1));
            string? steamIdOption = GetStringOption(data, "steam_id");

            string targetUid = !string.IsNullOrWhiteSpace(steamIdOption)
                ? steamIdOption.Trim()
                : _economyService.GetLinkedPlayerUid(authorId);

            if (_presenceService != null && !await _presenceService.IsPlayerOnlineAsync(targetUid))
            {
                await EditDeferredResponseEmbedAsync(interactionToken,
                    title: "⚠️ Offline",
                    description: "You must be logged into the Palworld server to use this command.",
                    color: 0xFF4466);
                return;
            }

            if (string.IsNullOrWhiteSpace(targetUid))
            {
                await EditDeferredResponseEmbedAsync(interactionToken,
                    title: "⚠️ Unlinked Account",
                    description: "You have not linked a Palworld Steam ID. Please provide `steam_id` or link your account in the Launcher.",
                    color: 0xFFCC00);
                return;
            }

            var saveService = new PalSaveService(_logService);
            var licenseService = new GuildLicenseService(_logService, saveService);
            
            targetUid = saveService.ResolvePlayerUid(targetUid);
            
            var profile = await saveService.ReadPlayerProfileAsync(targetUid);
            if (profile == null || profile.TechnologyPoints < amount)
            {
                await EditDeferredResponseEmbedAsync(interactionToken,
                    title: "❌ Deposit Failed",
                    description: $"Insufficient personal Technology Points. You need {amount}, but have {profile?.TechnologyPoints ?? 0}.",
                    color: 0xFF3366);
                return;
            }

            string? guildId = await licenseService.ResolveGuildIdAsync(targetUid);
            if (string.IsNullOrWhiteSpace(guildId))
            {
                await EditDeferredResponseEmbedAsync(interactionToken,
                    title: "❌ Guild Not Found",
                    description: "Could not locate your Guild in Level.sav. Ensure you are in a guild and the server has saved.",
                    color: 0xFF3366);
                return;
            }

            bool updated = await saveService.UpdateTechnologyPointsAsync(targetUid, -amount);
            if (updated)
            {
                await licenseService.DepositToBankAsync(guildId, targetUid, amount);
                var guildState = await licenseService.GetGuildStateAsync(guildId);

                await EditDeferredResponseEmbedAsync(interactionToken,
                    title: "🏦 Guild Bank Deposit Successful",
                    description: $"You deposited **{amount} Tech Points** into the Guild Bank!\n\n**New Guild Bank Balance**: `🪙 {guildState?.GuildBankBalance} Tech Points`",
                    color: 0x4CAF50);
            }
            else
            {
                await EditDeferredResponseEmbedAsync(interactionToken,
                    title: "❌ Deposit Failed",
                    description: "Failed to deduct points from your personal wallet.",
                    color: 0xFF3366);
            }
        }

        private async Task ExecuteGuildBankInteractionAsync(string interactionToken, JsonElement data, string authorId, string authorName)
        {
            string? steamIdOption = GetStringOption(data, "steam_id");
            string targetUid = !string.IsNullOrWhiteSpace(steamIdOption)
                ? steamIdOption.Trim()
                : _economyService.GetLinkedPlayerUid(authorId);

            if (string.IsNullOrWhiteSpace(targetUid))
            {
                await EditDeferredResponseEmbedAsync(interactionToken,
                    title: "⚠️ Unlinked Account",
                    description: "You have not linked a Palworld Steam ID. Please provide `steam_id` or link your account in the Launcher.",
                    color: 0xFFCC00);
                return;
            }

            var saveService = new PalSaveService(_logService);
            var licenseService = new GuildLicenseService(_logService, saveService);
            targetUid = saveService.ResolvePlayerUid(targetUid);
            
            string? guildId = await licenseService.ResolveGuildIdAsync(targetUid);
            if (string.IsNullOrWhiteSpace(guildId))
            {
                await EditDeferredResponseEmbedAsync(interactionToken,
                    title: "❌ Guild Not Found",
                    description: "Could not locate your Guild in Level.sav. Ensure you are in a guild and the server has saved.",
                    color: 0xFF3366);
                return;
            }

            var state = await licenseService.GetGuildStateAsync(guildId) ?? new GuildLicenseState();

            var sb = new StringBuilder();
            sb.AppendLine($"### 🏦 Pooled Balance: `🪙 {state.GuildBankBalance} Tech Points`\n");
            
            sb.AppendLine($"**Infrastructure Caps:**");
            sb.AppendLine($"⛺ **Bases:** {state.MaxBases} / 10");
            sb.AppendLine($"🥚 **Breeding Pens:** {state.MaxBreedingPens}");
            sb.AppendLine($"🐑 **Ranches:** {state.MaxRanches}\n");

            sb.AppendLine($"**🏆 Top Contributors:**");
            if (state.Contributions.Count == 0)
            {
                sb.AppendLine("*No contributions yet.*");
            }
            else
            {
                var sorted = state.Contributions.OrderByDescending(x => x.Value).Take(10);
                int rank = 1;
                foreach (var c in sorted)
                {
                    sb.AppendLine($"`#{rank}` **{c.Key}**: `🪙 {c.Value}`");
                    rank++;
                }
            }

            await EditDeferredResponseEmbedAsync(interactionToken,
                title: $"🏦 {(state.GuildName == "Unknown" ? "Guild" : state.GuildName)} - Tech Bank",
                description: sb.ToString(),
                color: 0xFFD700);
        }

        private async Task ExecuteExchangeInteractionAsync(string interactionToken, JsonElement data, string authorId, string authorName)
        {
            string itemQuery = GetStringOption(data, "item") ?? "";
            int amount = Math.Max(1, GetIntOption(data, "amount", 1));
            string? steamIdOption = GetStringOption(data, "steam_id");

            string targetUid = !string.IsNullOrWhiteSpace(steamIdOption)
                ? steamIdOption.Trim()
                : _economyService.GetLinkedPlayerUid(authorId);

            if (_presenceService != null && !await _presenceService.IsPlayerOnlineAsync(targetUid))
            {
                await EditDeferredResponseEmbedAsync(interactionToken,
                    title: "⚠️ Offline",
                    description: "You must be logged into the Palworld server to use this command.",
                    color: 0xFF4466);
                return;
            }

            var receipt = await _economyService.ExecuteExchangeAsync(targetUid, itemQuery, amount, isOnlineSession: true);

            if (receipt.Success)
            {
                var sb = new StringBuilder();
                sb.AppendLine($"### ✅ Transaction Approved (Receipt `#{receipt.TransactionId}`)");
                sb.AppendLine($"• **Pioneer Target**: `{targetUid}`");
                sb.AppendLine($"• **Purchased Item**: **{receipt.Quantity}x {receipt.ItemName}**");
                if (receipt.IsAncientCurrency)
                {
                    sb.AppendLine($"• **Cost Deducted**: `🔮 -{receipt.TotalCost} Ancient Technology Points`");
                    sb.AppendLine($"• **Previous Balance**: `{receipt.PreviousAncientPoints} Ancient Points`");
                    sb.AppendLine($"• **New Balance**: `{receipt.NewAncientPoints} Ancient Points`\n");
                }
                else
                {
                    sb.AppendLine($"• **Cost Deducted**: `🪙 -{receipt.TotalCost} Technology Points`");
                    sb.AppendLine($"• **Previous Balance**: `{receipt.PreviousTechPoints} Tech Points`");
                    sb.AppendLine($"• **New Balance**: `{receipt.NewTechPoints} Tech Points`\n");
                }
                sb.AppendLine($"📦 **Delivery Depot**: Items are credited to your Pioneer Virtual Vault.");
                sb.AppendLine($"👉 Type `/inventory` to inspect your items and balance | `/withdraw` to claim.");

                await EditDeferredResponseEmbedAsync(interactionToken,
                    title: "🛍️ Exchange Purchase Successful",
                    description: sb.ToString(),
                    color: receipt.IsAncientCurrency ? 0x9966FF : 0x00FF88);

                // Broadcast Guild Base Expansion
                if (itemQuery.Equals("guild_base_slot", StringComparison.OrdinalIgnoreCase))
                {
                    await SendEmbedMessageAsync("1541492780168380446",
                        title: "⛺ Guild Expansion Announced",
                        description: $"🎉 **{targetUid}** just expanded their Guild's Base Camp allowance (+1 Slot) via the Technology Exchange!",
                        color: 0x00FF88);
                }
            }
            else
            {
                await EditDeferredResponseEmbedAsync(interactionToken,
                    title: "❌ Exchange Transaction Failed",
                    description: receipt.Message,
                    color: 0xFF4466);
            }
        }

        private async Task ExecuteRecycleInteractionAsync(string interactionToken, JsonElement data, string authorId, string authorName)
        {
            string itemQuery = GetStringOption(data, "item") ?? "";
            int amount = Math.Max(1, GetIntOption(data, "amount", 1));
            string? steamIdOption = GetStringOption(data, "steam_id");

            string targetUid = !string.IsNullOrWhiteSpace(steamIdOption)
                ? steamIdOption.Trim()
                : _economyService.GetLinkedPlayerUid(authorId);

            if (_presenceService != null && !await _presenceService.IsPlayerOnlineAsync(targetUid))
            {
                await EditDeferredResponseEmbedAsync(interactionToken,
                    title: "⚠️ Offline",
                    description: "You must be logged into the Palworld server to use this command.",
                    color: 0xFF4466);
                return;
            }

            var receipt = await _economyService.ExecuteRecycleAsync(targetUid, itemQuery, amount, isOnlineSession: true);

            if (receipt.Success)
            {
                var sb = new StringBuilder();
                sb.AppendLine($"### ♻️ Recycling Completed (Receipt `#{receipt.TransactionId}`)");
                sb.AppendLine($"• **Pioneer Target**: `{targetUid}`");
                sb.AppendLine($"• **Items Scrapped**: **{receipt.Quantity}x {receipt.ItemName}**");
                sb.AppendLine($"• **Tech Points Awarded**: `🪙 +{receipt.PointsAwarded} Technology Points`");
                sb.AppendLine($"• **Previous Balance**: `{receipt.PreviousTechPoints} Tech Points`");
                sb.AppendLine($"• **New Balance**: `{receipt.NewTechPoints} Tech Points`\n");
                sb.AppendLine($"✨ Your Technology Points have been credited directly to your character save!");

                await EditDeferredResponseEmbedAsync(interactionToken,
                    title: "♻️ Trash-to-Tech Recycling Complete",
                    description: sb.ToString(),
                    color: 0x00E5FF);
            }
            else
            {
                await EditDeferredResponseEmbedAsync(interactionToken,
                    title: "⚠️ Recycling Failed",
                    description: receipt.Message,
                    color: 0xFFAA00);
            }
        }

        private async Task ExecuteInventoryInteractionAsync(string interactionToken, JsonElement data, string authorId, string authorName)
        {
            string? steamIdOption = GetStringOption(data, "steam_id");
            string targetUid = !string.IsNullOrWhiteSpace(steamIdOption)
                ? steamIdOption.Trim()
                : _economyService.GetLinkedPlayerUid(authorId);

            var profile = await _economyService.GetPlayerProfileAsync(targetUid, forceLiveRefresh: true);
            if (profile == null)
            {
                await EditDeferredResponseEmbedAsync(interactionToken,
                    title: "🎒 Pioneer Profile & Inventory",
                    description: $"Could not find player save for `{targetUid}`. Run `/link steam_id:<your_id>` or verify server save files.",
                    color: 0xFF4466);
                return;
            }

            var perks = _economyService.GetGuildPerks();

            string displayDiscord;
            if (!string.IsNullOrWhiteSpace(profile.DiscordId))
            {
                displayDiscord = $"<@{profile.DiscordId}> (`{profile.DiscordId}`)";
            }
            else if (string.IsNullOrWhiteSpace(steamIdOption))
            {
                displayDiscord = $"<@{authorId}> (`{authorId}`)";
            }
            else
            {
                displayDiscord = "*Not Linked*";
            }

            string displaySteam;
            if (!string.IsNullOrWhiteSpace(profile.SteamId))
            {
                displaySteam = $"`{profile.SteamId}`";
            }
            else if (!string.IsNullOrWhiteSpace(steamIdOption) && (steamIdOption.StartsWith("7656") || steamIdOption.StartsWith("steam_")))
            {
                displaySteam = $"`{steamIdOption.Replace("steam_", "")}`";
            }
            else
            {
                displaySteam = "*Not Linked*";
            }

            string inGameName = !string.IsNullOrWhiteSpace(profile.PlayerName) ? profile.PlayerName : "Unknown";
            string discordName = !string.IsNullOrWhiteSpace(profile.DiscordUsername)
                ? profile.DiscordUsername
                : (string.IsNullOrWhiteSpace(steamIdOption) ? authorName : string.Empty);

            string userHeader = !string.IsNullOrWhiteSpace(discordName) && !inGameName.Equals(discordName, StringComparison.OrdinalIgnoreCase)
                ? $"{inGameName} (@{discordName})"
                : inGameName;

            var sb = new StringBuilder();
            sb.AppendLine($"### 👤 User: `{userHeader}`");
            sb.AppendLine($"• **Player UID**: `{profile.PlayerUid}`");
            sb.AppendLine($"• **Steam ID**: {displaySteam}");
            sb.AppendLine($"• **Discord ID**: {displayDiscord}");
            sb.AppendLine($"• **Character Level**: `Lv. {profile.Level}`");
            sb.AppendLine($"• **🪙 Technology Points**: `{profile.TechnologyPoints} pts`");
            sb.AppendLine($"• **🔮 Ancient Boss Points**: `{profile.BossTechnologyPoints} pts`\n");

            sb.AppendLine("### 🏰 Active Server Perks");
            sb.AppendLine($"• ⚡ **Base Pal Speed & Work**: `+{perks.TotalWorkSpeedPercent}%`");
            sb.AppendLine($"• 🌟 **Server EXP Boost**: `+{perks.TotalExpBoostPercent}%`\n");

            sb.AppendLine("### 📦 Virtual Vault & Delivery Depot");
            if (profile.InventoryItems != null && profile.InventoryItems.Count > 0)
            {
                foreach (var kvp in profile.InventoryItems)
                {
                    sb.AppendLine($"• **{kvp.Key}**: `x{kvp.Value}`");
                }
            }
            else
            {
                sb.AppendLine("*Your Virtual Vault is currently empty. Use `/exchange` or `/gacha` to trade points for items!*");
            }
            sb.AppendLine();
            sb.AppendLine("💡 *Commands:* `/shop` | `/exchange` | `/transmute` | `/perk` | `/gacha` | `/withdraw`");

            await EditDeferredResponseEmbedAsync(interactionToken,
                title: "🎒 User Profile & Vault",
                description: sb.ToString(),
                color: 0x9966FF);
        }

        private async Task ExecuteLinkInteractionAsync(string interactionToken, JsonElement data, string authorId, string authorName)
        {
            string steamId = GetStringOption(data, "steam_id") ?? "";
            if (string.IsNullOrWhiteSpace(steamId))
            {
                await EditDeferredResponseEmbedAsync(interactionToken,
                    title: "⚠️ Link Failed",
                    description: "Please specify your Palworld Player UID or Steam ID: `/link steam_id:<your_id>`",
                    color: 0xFFAA00);
                return;
            }

            _economyService.LinkDiscordUser(authorId, steamId.Trim());

            await EditDeferredResponseEmbedAsync(interactionToken,
                title: "🔗 Character Save Linked",
                description: $"Successfully linked your Discord account (**@{authorName}**) to Palworld Player UID / Steam ID:\n`{steamId.Trim()}`\n\nYou can now run `/exchange`, `/transmute`, `/perk`, `/gacha`, `/withdraw`, and `/inventory` without specifying your ID!",
                color: 0x00FF88);
        }

        private async Task ExecuteWithdrawInteractionAsync(string interactionToken, JsonElement data, string authorId, string authorName)
        {
            string? itemQuery = GetStringOption(data, "item");
            int amount = GetIntOption(data, "amount", 0);
            string? steamIdOption = GetStringOption(data, "steam_id");

            string targetUid = !string.IsNullOrWhiteSpace(steamIdOption)
                ? steamIdOption.Trim()
                : _economyService.GetLinkedPlayerUid(authorId);

            if (_presenceService != null && !await _presenceService.IsPlayerOnlineAsync(targetUid))
            {
                await EditDeferredResponseEmbedAsync(interactionToken,
                    title: "⚠️ Offline",
                    description: "You must be logged into the Palworld server to claim items into your in-game character.",
                    color: 0xFF4466);
                return;
            }

            var receipt = await _economyService.ExecuteWithdrawAsync(targetUid, itemQuery, amount, isOnlineSession: true);

            if (receipt.Success)
            {
                var sb = new StringBuilder();
                sb.AppendLine($"### 📦 Items Claimed to In-Game Character\n");
                foreach (var item in receipt.WithdrawnItems)
                {
                    sb.AppendLine($"• **{item.Key}**: `x{item.Value}`");
                }
                sb.AppendLine();

                if (receipt.RemainingVaultItems.Count > 0)
                {
                    sb.AppendLine($"**Remaining in Virtual Vault** ({receipt.RemainingVaultItems.Count} item types):");
                    foreach (var item in receipt.RemainingVaultItems)
                    {
                        sb.AppendLine($"• {item.Key}: `x{item.Value}`");
                    }
                }
                else
                {
                    sb.AppendLine("✨ *Your Virtual Vault is now empty — all items claimed!*");
                }

                sb.AppendLine("\n💡 *Items are dispatched directly to your live character inventory!*");

                await EditDeferredResponseEmbedAsync(interactionToken,
                    title: "🎁 Virtual Vault Withdrawal Successful",
                    description: sb.ToString(),
                    color: 0x00FF88);
            }
            else
            {
                await EditDeferredResponseEmbedAsync(interactionToken,
                    title: "⚠️ Virtual Vault Notice",
                    description: receipt.Message,
                    color: 0xFFAA00);
            }
        }

        private async Task ExecuteGachaInteractionAsync(string interactionToken, JsonElement data, string authorId, string authorName)
        {
            int pulls = GetIntOption(data, "pulls", 1);
            if (pulls != 1 && pulls != 10) pulls = 1;
            string tierOption = GetStringOption(data, "tier") ?? "standard";
            string currency = tierOption.Equals("ancient", StringComparison.OrdinalIgnoreCase) ? "ancient_points" : "tech_points";
            string? steamIdOption = GetStringOption(data, "steam_id");

            string targetUid = !string.IsNullOrWhiteSpace(steamIdOption)
                ? steamIdOption.Trim()
                : _economyService.GetLinkedPlayerUid(authorId);

            if (_presenceService != null && !await _presenceService.IsPlayerOnlineAsync(targetUid))
            {
                await EditDeferredResponseEmbedAsync(interactionToken,
                    title: "⚠️ Offline",
                    description: "You must be logged into the Palworld server to use this command.",
                    color: 0xFF4466);
                return;
            }

            var receipt = await _economyService.ExecuteGachaAsync(targetUid, pulls, currency, isOnlineSession: true);

            if (receipt.Success)
            {
                bool isAncient = receipt.CurrencyUsed == "ancient_points";
                string boxName = isAncient ? "Ancient Relic Box" : "Mystery Box";
                string currencyLabel = isAncient ? "Ancient Points" : "Tech Points";
                string currencyEmoji = isAncient ? "🔮" : "🪙";

                var sb = new StringBuilder();
                sb.AppendLine($"### 🎰 {boxName} — {pulls}-Pull (Receipt `#{receipt.TransactionId}`)\n");
                sb.AppendLine($"**Pioneer**: `{targetUid}` | **Cost**: `{currencyEmoji} {receipt.TotalCost} {currencyLabel}`");
                if (isAncient)
                {
                    sb.AppendLine($"**Ancient Balance**: `{receipt.PreviousAncientPoints}` → `{receipt.NewAncientPoints} pts`\n");
                }
                else
                {
                    sb.AppendLine($"**Tech Balance**: `{receipt.PreviousTechPoints}` → `{receipt.NewTechPoints} pts`\n");
                }

                sb.AppendLine("### 📦 Drop Results");
                int dropNum = 1;
                foreach (var drop in receipt.Drops)
                {
                    string prefix = drop.Rarity == GachaRarity.Legendary ? "**★** " : "";
                    string qty = drop.Quantity > 1 ? $" (x{drop.Quantity})" : "";
                    sb.AppendLine($"`#{dropNum++}` {drop.Emoji} {prefix}**{drop.Name}**{qty} — {drop.RarityLabel}");
                }

                if (receipt.PityTriggered)
                {
                    sb.AppendLine("\n🔔 *Pity Mechanic activated — guaranteed Rare+ on final pull!*");
                }

                if (receipt.HasLegendary)
                {
                    sb.AppendLine("\n# 🌟 JACKPOT! LEGENDARY PULL!");
                }

                sb.AppendLine($"\n💡 *Use `/inventory` to view items | `/withdraw` to claim into character!*");

                int embedColor = receipt.HasLegendary ? 0xFFD700 : (isAncient ? 0x9966FF : 0x00E5FF);
                await EditDeferredResponseEmbedAsync(interactionToken,
                    title: receipt.HasLegendary ? $"🌟 LEGENDARY JACKPOT! — {boxName}" : $"🎰 {boxName} Results",
                    description: sb.ToString(),
                    color: embedColor);

                if (receipt.HasLegendary)
                {
                    var legendaryDrops = receipt.Drops.Where(d => d.Rarity == GachaRarity.Legendary).ToList();
                    string legendaryNames = string.Join(", ", legendaryDrops.Select(d => $"{d.Emoji} **{d.Name}**"));

                    await SendEmbedMessageAsync("1541492780168380446",
                        title: "🌟 JACKPOT ALERT — Legendary Drop!",
                        description: $"🎰 **@{authorName}** just pulled a **LEGENDARY** item from the {boxName}!\n\n" +
                                     $"**Legendary Loot**: {legendaryNames}\n\n" +
                                     $"Try your luck with `/gacha tier:standard` or `/gacha tier:ancient`!",
                        color: 0xFFD700);

                    _logService.LogSuccess($"[JACKPOT BROADCAST] @{authorName} pulled LEGENDARY: {string.Join(", ", legendaryDrops.Select(d => d.Name))}", "DiscordBot");
                }
            }
            else
            {
                await EditDeferredResponseEmbedAsync(interactionToken,
                    title: "❌ Gacha Transaction Failed",
                    description: receipt.Message,
                    color: 0xFF4466);
            }
        }

        private async Task ExecuteTransmuteInteractionAsync(string interactionToken, JsonElement data, string authorId, string authorName)
        {
            int ancientPoints = Math.Max(1, GetIntOption(data, "ancient_points", 1));
            string? steamIdOption = GetStringOption(data, "steam_id");

            string targetUid = !string.IsNullOrWhiteSpace(steamIdOption)
                ? steamIdOption.Trim()
                : _economyService.GetLinkedPlayerUid(authorId);

            if (_presenceService != null && !await _presenceService.IsPlayerOnlineAsync(targetUid))
            {
                await EditDeferredResponseEmbedAsync(interactionToken,
                    title: "⚠️ Offline",
                    description: "You must be logged into the Palworld server to use this command.",
                    color: 0xFF4466);
                return;
            }

            var receipt = await _economyService.ExecuteTransmuteAsync(targetUid, ancientPoints, isOnlineSession: true);

            if (receipt.Success)
            {
                var sb = new StringBuilder();
                sb.AppendLine($"### ⚗️ Transmutation Completed (Receipt `#{receipt.TransactionId}`)");
                sb.AppendLine($"• **Pioneer Target**: `{targetUid}`");
                sb.AppendLine($"• **Ancient Points Converted**: `🔮 -{receipt.AncientPointsSpent} Ancient Points`");
                sb.AppendLine($"• **Standard Tech Points Gained**: `🪙 +{receipt.TechPointsGained} Tech Points` (1:2 Conversion)");
                sb.AppendLine($"• **Ancient Balance**: `{receipt.PreviousAncientPoints}` → `{receipt.RemainingAncientPoints} pts`");
                sb.AppendLine($"• **Tech Points Balance**: `{receipt.PreviousTechPoints}` → `{receipt.NewTechPoints} pts`\n");
                sb.AppendLine("✨ *Points have been synced to your live player character in-game!*");

                await EditDeferredResponseEmbedAsync(interactionToken,
                    title: "⚗️ Ancient Point Transmutation Successful",
                    description: sb.ToString(),
                    color: 0x9966FF);
            }
            else
            {
                await EditDeferredResponseEmbedAsync(interactionToken,
                    title: "⚠️ Transmutation Failed",
                    description: receipt.Message,
                    color: 0xFFAA00);
            }
        }

        private async Task ExecutePerkInteractionAsync(string interactionToken, JsonElement data, string authorId, string authorName)
        {
            string? perkOption = GetStringOption(data, "upgrade");
            string? steamIdOption = GetStringOption(data, "steam_id");

            if (string.IsNullOrWhiteSpace(perkOption))
            {
                // Just display current perk status
                var perks = _economyService.GetGuildPerks();
                var sb = new StringBuilder();
                sb.AppendLine("### 🏰 Active Guild & Server Perks\n");
                sb.AppendLine($"• ⚡ **Base Pal Work & Movement Speed**: **Tier {perks.WorkSpeedLevel}** (`+{perks.TotalWorkSpeedPercent}% Speed Boost`)");
                sb.AppendLine($"  ↳ *Upgrade Cost: `🔮 5 Ancient Tech Points` (Adds +1% Work & Movement Speed)*\n");
                sb.AppendLine($"• 🌟 **Global Server EXP Boost**: **Tier {perks.ExpBoostLevel}** (`+{perks.TotalExpBoostPercent}% EXP Boost`)");
                sb.AppendLine($"  ↳ *Upgrade Cost: `🔮 20 Ancient Tech Points` (Adds +5% Server EXP)*\n");
                sb.AppendLine("💡 *Run `/perk upgrade:work_speed` or `/perk upgrade:exp_boost` to contribute!*");

                await EditDeferredResponseEmbedAsync(interactionToken,
                    title: "🏰 PalOdyssey Guild & Server Perks",
                    description: sb.ToString(),
                    color: 0xFFD700);
                return;
            }

            string targetUid = !string.IsNullOrWhiteSpace(steamIdOption)
                ? steamIdOption.Trim()
                : _economyService.GetLinkedPlayerUid(authorId);

            if (_presenceService != null && !await _presenceService.IsPlayerOnlineAsync(targetUid))
            {
                await EditDeferredResponseEmbedAsync(interactionToken,
                    title: "⚠️ Offline",
                    description: "You must be logged into the Palworld server to use this command.",
                    color: 0xFF4466);
                return;
            }

            var receipt = await _economyService.ExecuteUpgradePerkAsync(targetUid, perkOption, isOnlineSession: true);

            if (receipt.Success)
            {
                var sb = new StringBuilder();
                sb.AppendLine($"### 🏰 Server Perk Upgraded! (Receipt `#{receipt.TransactionId}`)");
                sb.AppendLine($"• **Pioneer Contributor**: `{targetUid}`");
                sb.AppendLine($"• **Perk Upgraded**: **{receipt.PerkName}** (Tier {receipt.NewPerkLevel})");
                sb.AppendLine($"• **Ancient Cost**: `🔮 -{receipt.AncientCost} Ancient Points`");
                sb.AppendLine($"• **New Active Buff**: `{receipt.PerkBonusDescription}`");
                sb.AppendLine($"• **Remaining Ancient Balance**: `{receipt.RemainingAncientPoints} pts`\n");
                sb.AppendLine("🎉 *Thank you for contributing your Ancient Technology Points to power up the realm!*");

                await EditDeferredResponseEmbedAsync(interactionToken,
                    title: "🌟 Guild & Server Perk Upgraded",
                    description: sb.ToString(),
                    color: 0xFFD700);

                // Broadcast to liveboard channel
                await SendEmbedMessageAsync("1541492780168380446",
                    title: "🌟 Server Perk Upgraded!",
                    description: $"🎉 **@{authorName}** upgraded **{receipt.PerkName}** to **Tier {receipt.NewPerkLevel}**!\n\n" +
                                 $"✨ **Active Global Buff**: `{receipt.PerkBonusDescription}`",
                    color: 0xFFD700);
            }
            else
            {
                await EditDeferredResponseEmbedAsync(interactionToken,
                    title: "⚠️ Perk Upgrade Failed",
                    description: receipt.Message,
                    color: 0xFFAA00);
            }
        }

        private async Task ExecuteSetPointsInteractionAsync(string interactionToken, JsonElement data, string authorName)
        {
            string userQuery = GetStringOption(data, "user") ?? "";
            int points = GetIntOption(data, "points", 0);
            string currency = GetStringOption(data, "currency") ?? "tech_points";

            if (string.IsNullOrWhiteSpace(userQuery))
            {
                await EditDeferredResponseEmbedAsync(interactionToken,
                    title: "⚠️ Invalid Player",
                    description: "Please specify a valid Discord User ID, Steam ID, or Player UID.",
                    color: 0xFFAA00);
                return;
            }

            string targetUid = ResolveUserQueryToPlayerUid(userQuery);
            bool isOnline = _presenceService != null && await _presenceService.IsPlayerOnlineAsync(targetUid);
            var receipt = await _economyService.SetPlayerTechnologyPointsAsync(targetUid, points, currency, isOnline);

            if (receipt.Success)
            {
                var sb = new StringBuilder();
                sb.AppendLine($"### ⚡ Technology Points Set by Admin `@{authorName}`");
                sb.AppendLine($"• **Pioneer**: `{receipt.PlayerName}` (`{receipt.PlayerUid}`)");
                sb.AppendLine($"• **Currency**: `{(receipt.Currency == "boss_points" ? "🔮 Ancient Boss Points" : "🪙 Technology Points")}`");
                sb.AppendLine($"• **Previous Balance**: `{receipt.PreviousPoints} pts`");
                sb.AppendLine($"• **New Balance**: `{receipt.NewPoints} pts`");
                sb.AppendLine($"• **Session Mode**: `{(isOnline ? "Live In-Game Sync (Instant)" : "Offline World Save")}`\n");
                sb.AppendLine($"💡 *{receipt.Message}*");

                await EditDeferredResponseEmbedAsync(interactionToken,
                    title: "✅ Player Balance Updated",
                    description: sb.ToString(),
                    color: 0x00FF88);
            }
            else
            {
                await EditDeferredResponseEmbedAsync(interactionToken,
                    title: "❌ Point Adjustment Failed",
                    description: receipt.Message,
                    color: 0xFF4466);
            }
        }

        private async Task ExecuteGrantPointsInteractionAsync(string interactionToken, JsonElement data, string authorName)
        {
            string userQuery = GetStringOption(data, "user") ?? "";
            int pointDelta = GetIntOption(data, "points", 0);
            string currency = GetStringOption(data, "currency") ?? "tech_points";

            if (string.IsNullOrWhiteSpace(userQuery))
            {
                await EditDeferredResponseEmbedAsync(interactionToken,
                    title: "⚠️ Invalid Player",
                    description: "Please specify a valid Discord User ID, Steam ID, or Player UID.",
                    color: 0xFFAA00);
                return;
            }

            string targetUid = ResolveUserQueryToPlayerUid(userQuery);
            bool isOnline = _presenceService != null && await _presenceService.IsPlayerOnlineAsync(targetUid);
            var receipt = await _economyService.GrantPlayerTechnologyPointsAsync(targetUid, pointDelta, currency, isOnline);

            if (receipt.Success)
            {
                var sb = new StringBuilder();
                sb.AppendLine($"### 🪙 Technology Points Granted by Admin `@{authorName}`");
                sb.AppendLine($"• **Pioneer**: `{receipt.PlayerName}` (`{receipt.PlayerUid}`)");
                sb.AppendLine($"• **Currency**: `{(receipt.Currency == "boss_points" ? "🔮 Ancient Boss Points" : "🪙 Technology Points")}`");
                sb.AppendLine($"• **Delta**: `{(receipt.Delta >= 0 ? "+" : "")}{receipt.Delta} pts`");
                sb.AppendLine($"• **New Balance**: `{receipt.NewPoints} pts`");
                sb.AppendLine($"• **Session Mode**: `{(isOnline ? "Live In-Game Sync (Instant)" : "Offline World Save")}`\n");
                sb.AppendLine($"💡 *{receipt.Message}*");

                await EditDeferredResponseEmbedAsync(interactionToken,
                    title: "✅ Player Points Granted",
                    description: sb.ToString(),
                    color: 0x00FF88);
            }
            else
            {
                await EditDeferredResponseEmbedAsync(interactionToken,
                    title: "❌ Point Grant Failed",
                    description: receipt.Message,
                    color: 0xFF4466);
            }
        }

        private string ResolveUserQueryToPlayerUid(string userQuery)
        {
            string clean = userQuery.Trim();
            if (clean.StartsWith("<@") && clean.EndsWith(">"))
            {
                clean = clean.Trim('<', '>', '@', '!');
                return _economyService.GetLinkedPlayerUid(clean);
            }
            if (ulong.TryParse(clean, out _) && clean.Length >= 17 && clean.Length <= 19 && !clean.StartsWith("7656"))
            {
                return _economyService.GetLinkedPlayerUid(clean);
            }
            return clean;
        }

        private static string? GetStringOption(JsonElement data, string optionName)
        {
            if (data.TryGetProperty("options", out var options) && options.ValueKind == JsonValueKind.Array)
            {
                foreach (var opt in options.EnumerateArray())
                {
                    if (opt.TryGetProperty("name", out var n) && n.GetString()?.Equals(optionName, StringComparison.OrdinalIgnoreCase) == true)
                    {
                        if (opt.TryGetProperty("value", out var v))
                        {
                            return v.GetString();
                        }
                    }
                }
            }
            return null;
        }

        private static int GetIntOption(JsonElement data, string optionName, int defaultValue = 1)
        {
            if (data.TryGetProperty("options", out var options) && options.ValueKind == JsonValueKind.Array)
            {
                foreach (var opt in options.EnumerateArray())
                {
                    if (opt.TryGetProperty("name", out var n) && n.GetString()?.Equals(optionName, StringComparison.OrdinalIgnoreCase) == true)
                    {
                        if (opt.TryGetProperty("value", out var v))
                        {
                            if (v.ValueKind == JsonValueKind.Number) return v.GetInt32();
                            if (int.TryParse(v.GetString(), out int parsed)) return parsed;
                        }
                    }
                }
            }
            return defaultValue;
        }



        private async Task ExecuteInventoryCommandAsync(string channelId, string authorId)
        {
            string targetUid = _economyService.GetLinkedPlayerUid(authorId);
            var profile = await _economyService.GetPlayerProfileAsync(targetUid, forceLiveRefresh: true);
            if (profile == null)
            {
                await SendEmbedMessageAsync(channelId,
                    title: "🎒 Pioneer Profile & Inventory",
                    description: $"Could not find player save for `{targetUid}`. Run `/link steam_id:<your_id>`.",
                    color: 0xFF4466);
                return;
            }

            var sb = new StringBuilder();
            sb.AppendLine($"• **Pioneer**: `{profile.PlayerName}` (Lv. {profile.Level})");
            sb.AppendLine($"• **🪙 Technology Points**: `{profile.TechnologyPoints} pts`");
            sb.AppendLine($"• **🔮 Ancient Boss Points**: `{profile.BossTechnologyPoints} pts`");

            await SendEmbedMessageAsync(channelId,
                title: "🎒 Pioneer Character Stats",
                description: sb.ToString(),
                color: 0x9966FF);
        }

        private async Task DeferInteractionAsync(string interactionId, string interactionToken, bool ephemeral = false)
        {
            try
            {
                object payload = ephemeral
                    ? new { type = 5, data = new { flags = 64 } }
                    : new { type = 5 };

                string json = JsonSerializer.Serialize(payload);
                var content = new StringContent(json, Encoding.UTF8, "application/json");

                var resp = await _interactionClient.PostAsync($"interactions/{interactionId}/{interactionToken}/callback", content);
                if (!resp.IsSuccessStatusCode)
                {
                    string err = await resp.Content.ReadAsStringAsync();
                    _logService.LogWarning($"Interaction defer callback returned {resp.StatusCode}: {err}", "DiscordBot");
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

                if (description != null && description.Length > 4000)
                {
                    description = description.Substring(0, 3990) + "\n...[truncated]";
                }

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

                var resp = await _interactionClient.PatchAsync($"webhooks/{appId}/{interactionToken}/messages/@original", content);
                if (!resp.IsSuccessStatusCode)
                {
                    string err = await resp.Content.ReadAsStringAsync();
                    _logService.LogWarning($"Edit deferred response returned {resp.StatusCode}: {err}", "DiscordBot");
                }
            }
            catch (Exception ex)
            {
                _logService.LogWarning($"Failed to edit deferred interaction response: {ex.Message}", "DiscordBot");
            }
        }

        private async Task RespondInteractionEmbedAsync(string interactionId, string interactionToken, string title, string description, int color, bool ephemeral = false)
        {
            try
            {
                if (description != null && description.Length > 4000)
                {
                    description = description.Substring(0, 3990) + "\n...[truncated]";
                }

                var payload = new
                {
                    type = 4, // CHANNEL_MESSAGE_WITH_SOURCE
                    data = new
                    {
                        flags = ephemeral ? 64 : 0,
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

                var resp = await _interactionClient.PostAsync($"interactions/{interactionId}/{interactionToken}/callback", content);
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
                if (description != null && description.Length > 4000)
                {
                    description = description.Substring(0, 3990) + "\n...[truncated]";
                }

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
                    await Task.Delay(15000, ct); // Auto-refresh every 15s
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

            bool isOnline = liveboard.IsOnline || liveboard.IsServerRunning;
            int embedColor = isOnline ? 0x00FF88 : 0x8899AA;

            var payload = new
            {
                embeds = new[]
                {
                    new
                    {
                        title = "📡 PalOdyssey Realm — 24/7 Liveboard & Server Telemetry",
                        description = liveboard.BuildDiscordSummaryMarkdown(),
                        color = embedColor,
                        footer = new
                        {
                            text = "PalOdyssey Autonomous Host • Auto-refreshes every 15s • Type /help for commands"
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

        private async Task ExecuteSetPointsCommandAsync(string channelId, string fullCommand, string authorName)
        {
            var parts = fullCommand.Split(' ', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
            if (parts.Length < 3)
            {
                await SendEmbedMessageAsync(channelId,
                    title: "⚠️ Usage: Set Points",
                    description: "**Usage**: `!setpoints <@user|steam_id|player_uid> <amount> [tech_points|boss_points]`\n\nExample: `!setpoints @Jack 50` or `!setpoints 76561198000000000 10 boss_points`",
                    color: 0xFFAA00);
                return;
            }

            string userQuery = parts[1];
            if (!int.TryParse(parts[2], out int points))
            {
                await SendEmbedMessageAsync(channelId,
                    title: "⚠️ Invalid Amount",
                    description: $"Could not parse `{parts[2]}` as a valid integer amount.",
                    color: 0xFFAA00);
                return;
            }

            string currency = parts.Length >= 4 ? parts[3] : "tech_points";
            string targetUid = ResolveUserQueryToPlayerUid(userQuery);

            bool isOnline = _presenceService != null && await _presenceService.IsPlayerOnlineAsync(targetUid);
            var receipt = await _economyService.SetPlayerTechnologyPointsAsync(targetUid, points, currency, isOnline);

            if (receipt.Success)
            {
                var sb = new StringBuilder();
                sb.AppendLine($"### ⚡ Technology Points Set by Admin `@{authorName}`");
                sb.AppendLine($"• **Pioneer**: `{receipt.PlayerName}` (`{receipt.PlayerUid}`)");
                sb.AppendLine($"• **Currency**: `{(receipt.Currency == "boss_points" ? "🔮 Ancient Boss Points" : "🪙 Technology Points")}`");
                sb.AppendLine($"• **Previous Balance**: `{receipt.PreviousPoints} pts`");
                sb.AppendLine($"• **New Balance**: `{receipt.NewPoints} pts`");
                sb.AppendLine($"• **Session Mode**: `{(isOnline ? "Live In-Game Sync (Instant)" : "Offline World Save")}`\n");
                sb.AppendLine($"💡 *{receipt.Message}*");

                await SendEmbedMessageAsync(channelId,
                    title: "✅ Player Balance Updated",
                    description: sb.ToString(),
                    color: 0x00FF88);
            }
            else
            {
                await SendEmbedMessageAsync(channelId,
                    title: "❌ Point Adjustment Failed",
                    description: receipt.Message,
                    color: 0xFF4466);
            }
        }

        private async Task ExecuteGrantPointsCommandAsync(string channelId, string fullCommand, string authorName)
        {
            var parts = fullCommand.Split(' ', StringSplitOptions.RemoveEmptyEntries | StringSplitOptions.TrimEntries);
            if (parts.Length < 3)
            {
                await SendEmbedMessageAsync(channelId,
                    title: "⚠️ Usage: Grant Points",
                    description: "**Usage**: `!grantpoints <@user|steam_id|player_uid> <amount> [tech_points|boss_points]`\n\nExample: `!grantpoints @Jack 10` or `!grantpoints 76561198000000000 5 boss_points`",
                    color: 0xFFAA00);
                return;
            }

            string userQuery = parts[1];
            if (!int.TryParse(parts[2], out int pointDelta))
            {
                await SendEmbedMessageAsync(channelId,
                    title: "⚠️ Invalid Amount",
                    description: $"Could not parse `{parts[2]}` as a valid integer amount.",
                    color: 0xFFAA00);
                return;
            }

            string currency = parts.Length >= 4 ? parts[3] : "tech_points";
            string targetUid = ResolveUserQueryToPlayerUid(userQuery);

            bool isOnline = _presenceService != null && await _presenceService.IsPlayerOnlineAsync(targetUid);
            var receipt = await _economyService.GrantPlayerTechnologyPointsAsync(targetUid, pointDelta, currency, isOnline);

            if (receipt.Success)
            {
                var sb = new StringBuilder();
                sb.AppendLine($"### 🪙 Technology Points Granted by Admin `@{authorName}`");
                sb.AppendLine($"• **Pioneer**: `{receipt.PlayerName}` (`{receipt.PlayerUid}`)");
                sb.AppendLine($"• **Currency**: `{(receipt.Currency == "boss_points" ? "🔮 Ancient Boss Points" : "🪙 Technology Points")}`");
                sb.AppendLine($"• **Delta**: `{(receipt.Delta >= 0 ? "+" : "")}{receipt.Delta} pts`");
                sb.AppendLine($"• **New Balance**: `{receipt.NewPoints} pts`");
                sb.AppendLine($"• **Session Mode**: `{(isOnline ? "Live In-Game Sync (Instant)" : "Offline World Save")}`\n");
                sb.AppendLine($"💡 *{receipt.Message}*");

                await SendEmbedMessageAsync(channelId,
                    title: "✅ Player Points Granted",
                    description: sb.ToString(),
                    color: 0x00FF88);
            }
            else
            {
                await SendEmbedMessageAsync(channelId,
                    title: "❌ Point Grant Failed",
                    description: receipt.Message,
                    color: 0xFF4466);
            }
        }

        public void Dispose()
        {
            _botCts?.Cancel();
            _botCts?.Dispose();
            _webSocket?.Dispose();
            _httpClient?.Dispose();
            _interactionClient?.Dispose();
        }
    }
}

