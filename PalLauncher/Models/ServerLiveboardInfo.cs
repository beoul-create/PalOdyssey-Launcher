using System;
using System.Collections.Generic;
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
    }
}
