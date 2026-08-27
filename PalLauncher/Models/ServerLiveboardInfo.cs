using System;
using System.Collections.Generic;
using System.Text;
using System.Text.Json.Serialization;

namespace PalLauncher.Models
{
    public class PlayerInfo
    {
        [JsonPropertyName("name")]
        public string Name { get; set; } = "Expedition Leader";

        [JsonPropertyName("level")]
        public int Level { get; set; } = 1;

        [JsonPropertyName("playerUid")]
        public string PlayerUid { get; set; } = string.Empty;

        [JsonPropertyName("steamId")]
        public string SteamId { get; set; } = string.Empty;

        [JsonPropertyName("pingMs")]
        public int PingMs { get; set; } = 25;

        [JsonPropertyName("location")]
        public string Location { get; set; } = "Palpagos Islands";

        [JsonPropertyName("joinedTime")]
        public DateTime JoinedTime { get; set; } = DateTime.Now;

        [JsonIgnore]
        public string LevelBadge => $"Lv. {Level}";

        [JsonIgnore]
        public string PingBadge => $"{PingMs}ms";

        [JsonIgnore]
        public string FormattedSummary => $"{Name} (Lv. {Level}) • {PingMs}ms • {Location}";
    }

    public class ServerLiveboardInfo
    {
        [JsonPropertyName("isOnline")]
        public bool IsOnline { get; set; }

        [JsonPropertyName("isServerRunning")]
        public bool IsServerRunning { get; set; }

        [JsonPropertyName("serverName")]
        public string ServerName { get; set; } = "PalOdyssey Realm";

        [JsonPropertyName("serverAddress")]
        public string ServerAddress { get; set; } = "palodyssey.duckdns.org:8211";

        [JsonPropertyName("version")]
        public string Version { get; set; } = "1.5.4";

        [JsonPropertyName("uptimeSeconds")]
        public double UptimeSeconds { get; set; }

        [JsonPropertyName("playerCount")]
        public int PlayerCount { get; set; }

        [JsonPropertyName("maxPlayers")]
        public int MaxPlayers { get; set; } = 32;

        [JsonPropertyName("players")]
        public List<PlayerInfo> Players { get; set; } = new();

        [JsonPropertyName("isIdleCountingDown")]
        public bool IsIdleCountingDown { get; set; }

        [JsonPropertyName("idleMinutesRemaining")]
        public int IdleMinutesRemaining { get; set; } = 20;

        [JsonPropertyName("idleSecondsRemaining")]
        public int IdleSecondsRemaining { get; set; } = 1200;

        [JsonPropertyName("idleShutdownEnabled")]
        public bool IdleShutdownEnabled { get; set; } = true;

        [JsonPropertyName("serverFps")]
        public int ServerFps { get; set; } = 60;

        [JsonIgnore]
        public bool HasActivePlayers => PlayerCount > 0;

        [JsonIgnore]
        public bool HasNoPlayers => PlayerCount == 0;

        [JsonIgnore]
        public int OccupancyPercentage => Math.Clamp((int)Math.Round((double)PlayerCount / Math.Max(1, MaxPlayers) * 100), 0, 100);

        [JsonIgnore]
        public string FpsBadge => ServerFps > 0 ? $"{ServerFps} FPS" : "60 FPS";

        [JsonIgnore]
        public string PerformanceHealthText => ServerFps >= 50 ? "🟢 Optimal (60 FPS)" : (ServerFps >= 30 ? "🟡 Normal" : "🔴 High Load");

        [JsonIgnore]
        public string UptimeFormatted
        {
            get
            {
                if (!IsServerRunning || UptimeSeconds <= 0) return "00m 00s";
                var ts = TimeSpan.FromSeconds(UptimeSeconds);
                if (ts.TotalHours >= 1)
                {
                    return $"{(int)ts.TotalHours:D2}h {ts.Minutes:D2}m {ts.Seconds:D2}s";
                }
                return $"{ts.Minutes:D2}m {ts.Seconds:D2}s";
            }
        }

        [JsonIgnore]
        public string PlayerCountSummary => $"{PlayerCount} / {MaxPlayers} Players Online";

        [JsonIgnore]
        public string OccupancySummary => $"{PlayerCount} / {MaxPlayers} ({OccupancyPercentage}%)";

        [JsonIgnore]
        public string AutoShutdownStatusText
        {
            get
            {
                if (!IsServerRunning) return "Server Sleeping (Wake on Demand Ready)";
                if (PlayerCount > 0) return $"Active ({PlayerCount} Online) • Auto-Shutdown Paused";
                if (IsIdleCountingDown && IdleShutdownEnabled)
                {
                    return $"0 Players Online • Auto-Shutdown in {IdleMinutesRemaining}m";
                }
                return "0 Players Online • Server Standing By";
            }
        }

        public string BuildDiscordSummaryMarkdown()
        {
            long unixSeconds = DateTimeOffset.UtcNow.ToUnixTimeSeconds();
            bool active = IsServerRunning;
            string statusBadge = active ? "🟢 **ONLINE & READY**" : "💤 **STANDBY (Sleeping)**";

            var sb = new StringBuilder();
            sb.AppendLine("### 🗺️ PalOdyssey Realm Status & Telemetry");
            sb.AppendLine($"• **Status**: {statusBadge}");
            sb.AppendLine($"• **Connection Endpoint**: `palodyssey.duckdns.org:8211`");
            sb.AppendLine($"• **Active Uptime**: `{(active ? UptimeFormatted : "Standby (00m 00s)")}`");
            sb.AppendLine($"• **Engine Version**: `v{Version}` • **Tickrate**: `{FpsBadge}` *(32 Max Capacity)*");
            sb.AppendLine();

            // Active Pioneers section
            sb.AppendLine($"### 👥 Pioneers Online ({PlayerCount} / {MaxPlayers} — {OccupancyPercentage}% Occupied)");
            if (Players != null && Players.Count > 0)
            {
                foreach (var p in Players)
                {
                    string steamTag = !string.IsNullOrWhiteSpace(p.SteamId) ? $" | `{p.SteamId}`" : "";
                    sb.AppendLine($"• 🛡️ **{p.Name}** (`{p.LevelBadge}`) — `{p.PingBadge}` | 📍 *{p.Location}*{steamTag}");
                }
            }
            else
            {
                sb.AppendLine(active 
                    ? "*No pioneers currently in realm. Server standing by for connections.*"
                    : "*Realm is sleeping to conserve resources. Launch launcher or type `/start` to boot.*");
            }
            sb.AppendLine();

            // Autonomous Watchdog section
            sb.AppendLine("### ⏳ Inactivity Auto-Shutdown");
            if (!active)
            {
                sb.AppendLine("💤 **Standby Mode**: Server is resting. Type `/start` or click **LAUNCH GAME** in the launcher to wake.");
            }
            else if (PlayerCount > 0)
            {
                sb.AppendLine($"🟢 **Active Session**: Auto-shutdown paused while **{PlayerCount}** pioneer(s) are exploring.");
            }
            else if (IdleShutdownEnabled)
            {
                int remMin = Math.Max(0, IdleSecondsRemaining / 60);
                int remSec = Math.Max(0, IdleSecondsRemaining % 60);
                sb.AppendLine($"⏳ **Countdown Active**: Server will save & sleep in **{remMin}m {remSec:D2}s** if no players join.");
            }
            else
            {
                sb.AppendLine("🛡️ **24/7 Always-On**: Inactivity auto-shutdown is disabled.");
            }
            sb.AppendLine();

            // Connection Guide & Shortcuts
            sb.AppendLine("### 🎮 Quick Connection Guide");
            sb.AppendLine("1. Open **PalOdyssey Launcher** ➔ Click **LAUNCH GAME** (copies IP automatically).");
            sb.AppendLine("2. Or In-Game: **Join Multiplayer Game** ➔ Enter `palodyssey.duckdns.org:8211` ➔ Connect.");
            sb.AppendLine();
            sb.AppendLine($"💡 *Shortcuts:* `/start` • `/shop` • `/exchange` • `/inventory` • `/gacha` • `/help`");
            sb.AppendLine($"🔄 *Last Synchronized:* <t:{unixSeconds}:R>");

            return sb.ToString();
        }
    }
}

