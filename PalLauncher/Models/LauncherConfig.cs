using System;
using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;

namespace PalLauncher.Models
{
    public class LauncherConfig
    {
        [JsonPropertyName("gamePath")]
        public string GamePath { get; set; } = string.Empty;

        [JsonIgnore]
        public string? GameInstallPath
        {
            get => GamePath;
            set => GamePath = value ?? string.Empty;
        }

        [JsonPropertyName("serverInstallPath")]
        public string? ServerInstallPath { get; set; }

        [JsonPropertyName("serverLaunchArguments")]
        public string ServerLaunchArguments { get; set; } = "-useperfthreads -NoAsyncLoadingThread -port=8211";

        [JsonPropertyName("autoStartServerWithClient")]
        public bool AutoStartServerWithClient { get; set; } = false;

        [JsonPropertyName("remoteManifestUrl")]
        public string RemoteManifestUrl { get; set; } = "https://raw.githubusercontent.com/beoul-create/PalOdessey-Modpack/main/manifest.json";

        [JsonPropertyName("serverIp")]
        public string ServerIp { get; set; } = "palodyssey.duckdns.org";

        [JsonPropertyName("serverPort")]
        public int ServerPort { get; set; } = 8211;

        [JsonPropertyName("autoLaunchGame")]
        public bool AutoLaunchGame { get; set; } = false;

        [JsonPropertyName("soundEnabled")]
        public bool SoundEnabled { get; set; } = true;

        [JsonPropertyName("discordRpcEnabled")]
        public bool DiscordRpcEnabled { get; set; } = true;

        [JsonIgnore]
        public bool EnableDiscordRpc
        {
            get => DiscordRpcEnabled;
            set => DiscordRpcEnabled = value;
        }

        [JsonPropertyName("closeLauncherOnStart")]
        public bool CloseLauncherOnStart { get; set; } = false;

        [JsonPropertyName("launchViaSteamProtocol")]
        public bool LaunchViaSteamProtocol { get; set; } = false;

        private static readonly JsonSerializerOptions JsonOptions = new()
        {
            WriteIndented = true,
            DefaultIgnoreCondition = JsonIgnoreCondition.WhenWritingNull
        };

        public static string DefaultConfigPath => Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "launcher_config.json");

        public static LauncherConfig Load(string? path = null)
        {
            path ??= DefaultConfigPath;
            try
            {
                if (File.Exists(path))
                {
                    string json = File.ReadAllText(path);
                    return JsonSerializer.Deserialize<LauncherConfig>(json, JsonOptions) ?? new LauncherConfig();
                }
            }
            catch (Exception)
            {
                // Fallback to default
            }

            return new LauncherConfig();
        }

        public void Save(string? path = null)
        {
            path ??= DefaultConfigPath;
            try
            {
                string? dir = Path.GetDirectoryName(path);
                if (!string.IsNullOrEmpty(dir) && !Directory.Exists(dir))
                {
                    Directory.CreateDirectory(dir);
                }

                string json = JsonSerializer.Serialize(this, JsonOptions);
                string tempPath = path + ".tmp." + Guid.NewGuid().ToString("N");
                File.WriteAllText(tempPath, json);
                File.Move(tempPath, path, overwrite: true);
            }
            catch (Exception)
            {
                // Silently handle save failures
            }
        }
    }
}
