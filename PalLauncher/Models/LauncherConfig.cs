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
        public const string DirectHostEndpoint = "palodyssey.duckdns.org";
        public const int OfficialServerPort = 8211;
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

        [JsonPropertyName("enablePlayitTunnel")]
        public bool EnablePlayitTunnel { get; set; } = false;

        [JsonPropertyName("enableDiscordRpc")]
        public bool EnableDiscordRpc { get; set; } = true;

        [JsonPropertyName("discordApplicationId")]
        public string DiscordApplicationId { get; set; } = "1540924979095408700";

        [JsonPropertyName("enableDiscordBot")]
        public bool EnableDiscordBot { get; set; } = false;

        [JsonPropertyName("discordBotToken")]
        public string DiscordBotToken { get; set; } = "";

        [JsonPropertyName("discordCommandPrefix")]
        public string DiscordCommandPrefix { get; set; } = "/";

        [JsonPropertyName("discordBotChannelId")]
        public string DiscordBotChannelId { get; set; } = "";

        [JsonPropertyName("discordAdminRoleId")]
        public string DiscordAdminRoleId { get; set; } = "";

        [JsonPropertyName("autoJoinServer")]
        public bool AutoJoinServer { get; set; } = false;

        [JsonPropertyName("launchServerWithGame")]
        public bool LaunchServerWithGame { get; set; } = true;

        public const string OfficialManifestUrl = "https://raw.githubusercontent.com/beoul-create/PalOdyssey-Launcher/main/Modpack/version.json";

        [JsonPropertyName("remoteManifestUrl")]
        public string RemoteManifestUrl { get; set; } = OfficialManifestUrl;

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

        [JsonPropertyName("enableRawInputOptimization")]
        public bool EnableRawInputOptimization { get; set; } = true;

        [JsonPropertyName("customArguments")]
        public string CustomArguments { get; set; } = "-culture=en";
    }
}
