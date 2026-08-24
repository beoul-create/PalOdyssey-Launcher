using System;
using System.Text.Json.Serialization;

namespace PalLauncher.Models
{
    public class AccountLinkInfo
    {
        [JsonPropertyName("discordId")]
        public string DiscordId { get; set; } = string.Empty;

        [JsonPropertyName("discordUsername")]
        public string DiscordUsername { get; set; } = string.Empty;

        [JsonPropertyName("discordGlobalName")]
        public string DiscordGlobalName { get; set; } = string.Empty;

        [JsonPropertyName("steamId64")]
        public string SteamId64 { get; set; } = string.Empty;

        [JsonPropertyName("steamPersonaName")]
        public string SteamPersonaName { get; set; } = string.Empty;

        [JsonPropertyName("playerUid")]
        public string PlayerUid { get; set; } = string.Empty;

        [JsonPropertyName("linkedAt")]
        public DateTime LinkedAt { get; set; } = DateTime.UtcNow;

        [JsonPropertyName("isLinked")]
        public bool IsLinked { get; set; }

        [JsonIgnore]
        public string DisplayBadge => IsLinked
            ? $"🟢 Linked: @{DiscordUsername} ⇄ {SteamPersonaName}"
            : "⚪ Not Linked";
    }

    public class AccountLinkRequest
    {
        [JsonPropertyName("discord_id")]
        public string DiscordId { get; set; } = string.Empty;

        [JsonPropertyName("steam_id")]
        public string SteamId { get; set; } = string.Empty;

        [JsonPropertyName("discord_name")]
        public string DiscordName { get; set; } = string.Empty;

        [JsonPropertyName("steam_name")]
        public string SteamName { get; set; } = string.Empty;

        [JsonPropertyName("player_uid")]
        public string PlayerUid { get; set; } = string.Empty;
    }
}
