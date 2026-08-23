using System;
using System.Collections.Generic;
using System.Text.Json.Serialization;

namespace PalLauncher.Models
{
    public class ModManifest
    {
        [JsonPropertyName("manifestVersion")]
        public string ManifestVersion { get; set; } = "1.0.0";

        [JsonPropertyName("gameVersion")]
        public string GameVersion { get; set; } = "0.3.x";

        [JsonPropertyName("serverName")]
        public string ServerName { get; set; } = "PalOdyssey Official";

        [JsonPropertyName("serverAddress")]
        public string ServerAddress { get; set; } = "palodyssey.duckdns.org";

        [JsonPropertyName("serverPort")]
        public int ServerPort { get; set; } = 57294;

        [JsonPropertyName("lastUpdated")]
        public DateTime LastUpdated { get; set; } = DateTime.UtcNow;

        [JsonPropertyName("newsAnnouncement")]
        public string NewsAnnouncement { get; set; } = "Welcome to PalOdyssey! Make sure your core mod paks are up-to-date before launching.";

        [JsonPropertyName("baseDownloadUrl")]
        public string? BaseDownloadUrl { get; set; }

        [JsonPropertyName("mods")]
        public List<ModInfo> Mods { get; set; } = new();
    }
}
