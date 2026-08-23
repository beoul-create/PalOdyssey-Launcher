using System.Collections.Generic;
using System.Text.Json.Serialization;

namespace PalLauncher.Models
{
    public class LauncherConfig
    {
        [JsonPropertyName("gamePath")]
        public string GamePath { get; set; } = string.Empty;

        [JsonPropertyName("gameExecutableName")]
        public string GameExecutableName { get; set; } = "Palworld.exe";

        [JsonPropertyName("serverExecutableName")]
        public string ServerExecutableName { get; set; } = "PalServer.exe";

        [JsonPropertyName("launchMode")]
        public string LaunchMode { get; set; } = "Client"; // "Client" or "Server"

        public const string OfficialServerHost = "palodyssey.duckdns.org";
        public const int OfficialServerPort = 57294;
        public const int OfficialManagementPort = 8215;
        public const string DefaultRealmAccessKey = "PalOdyssey2026Secure";

        [JsonPropertyName("serverIp")]
        public string ServerIp { get; set; } = OfficialServerHost;

        [JsonPropertyName("serverPort")]
        public int ServerPort { get; set; } = OfficialServerPort;

        [JsonPropertyName("remoteManagementPort")]
        public int RemoteManagementPort { get; set; } = OfficialManagementPort;

        [JsonPropertyName("remoteAccessKey")]
        public string RemoteAccessKey { get; set; } = DefaultRealmAccessKey;

        [JsonPropertyName("enableRemoteHostDaemon")]
        public bool EnableRemoteHostDaemon { get; set; } = true;

        [JsonPropertyName("autoRemoteWakeOnLaunch")]
        public bool AutoRemoteWakeOnLaunch { get; set; } = true;

        [JsonPropertyName("enableIdleAutoShutdown")]
        public bool EnableIdleAutoShutdown { get; set; } = true;

        [JsonPropertyName("idleShutdownMinutes")]
        public int IdleShutdownMinutes { get; set; } = 15;

        [JsonPropertyName("enableDiscordRpc")]
        public bool EnableDiscordRpc { get; set; } = true;

        [JsonPropertyName("discordApplicationId")]
        public string DiscordApplicationId { get; set; } = "1540924979095408700";

        [JsonPropertyName("autoJoinServer")]
        public bool AutoJoinServer { get; set; } = false;

        [JsonPropertyName("launchServerWithGame")]
        public bool LaunchServerWithGame { get; set; } = true;

        [JsonPropertyName("remoteManifestUrl")]
        public string RemoteManifestUrl { get; set; } = "https://raw.githubusercontent.com/beoul-create/PalOdessey-Modpack/main/Modpack/version.json";

        [JsonPropertyName("paksRelativePath")]
        public string PaksRelativePath { get; set; } = @"Pal\Content\Paks\~mods";

        [JsonPropertyName("autoCheckUpdatesOnStartup")]
        public bool AutoCheckUpdatesOnStartup { get; set; } = true;

        [JsonPropertyName("autoUpdateBeforeLaunch")]
        public bool AutoUpdateBeforeLaunch { get; set; } = true;

        [JsonPropertyName("closeLauncherOnLaunch")]
        public bool CloseLauncherOnLaunch { get; set; } = false;

        [JsonPropertyName("useDirectX11")]
        public bool UseDirectX11 { get; set; } = true;

        [JsonPropertyName("useAllCores")]
        public bool UseAllCores { get; set; } = true;

        [JsonPropertyName("useHighPriority")]
        public bool UseHighPriority { get; set; } = false;

        [JsonPropertyName("noSplash")]
        public bool NoSplash { get; set; } = true;

        [JsonPropertyName("windowedMode")]
        public bool WindowedMode { get; set; } = false;

        [JsonPropertyName("customArguments")]
        public string CustomArguments { get; set; } = "-culture=en";
    }
}
