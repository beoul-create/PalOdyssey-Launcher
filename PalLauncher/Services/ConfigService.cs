using System;
using System.IO;
using System.Text.Json;
using System.Threading.Tasks;
using PalLauncher.Models;
using PalLauncher.Services.Interfaces;

namespace PalLauncher.Services
{
    public class ConfigService : IConfigService
    {
        private readonly string _configDirectory;
        private readonly string _configFilePath;
        private readonly JsonSerializerOptions _jsonOptions;
        private readonly ILogService _logService;
        private LauncherConfig _config = new();

        public LauncherConfig Config => _config;

        public ConfigService(ILogService logService, string? customConfigPath = null)
        {
            _logService = logService;
            if (!string.IsNullOrEmpty(customConfigPath))
            {
                _configFilePath = customConfigPath;
                _configDirectory = Path.GetDirectoryName(_configFilePath) ?? AppDomain.CurrentDomain.BaseDirectory;
            }
            else
            {
                _configDirectory = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
                    "PalLauncher");

                try
                {
                    if (!Directory.Exists(_configDirectory))
                    {
                        Directory.CreateDirectory(_configDirectory);
                    }
                }
                catch
                {
                    _configDirectory = AppDomain.CurrentDomain.BaseDirectory;
                }

                _configFilePath = Path.Combine(_configDirectory, "config.json");
            }

            _jsonOptions = new JsonSerializerOptions
            {
                WriteIndented = true,
                PropertyNameCaseInsensitive = true
            };
        }

        public async Task<LauncherConfig> LoadConfigAsync()
        {
            try
            {
                if (File.Exists(_configFilePath))
                {
                    string json = await File.ReadAllTextAsync(_configFilePath);
                    var loadedConfig = JsonSerializer.Deserialize<LauncherConfig>(json, _jsonOptions);
                    if (loadedConfig != null)
                    {
                        _config = loadedConfig;

                        // Decrypt DPAPI protected tokens if present
                        if (!string.IsNullOrEmpty(_config.DiscordBotToken))
                        {
                            _config.DiscordBotToken = UnprotectString(_config.DiscordBotToken);
                        }

                        // Prioritize Environment Variables & Secure Token File fallbacks
                        string? envBotToken = Environment.GetEnvironmentVariable("DISCORD_BOT_TOKEN");
                        if (!string.IsNullOrWhiteSpace(envBotToken))
                        {
                            _config.DiscordBotToken = envBotToken.Trim();
                        }
                        else if (string.IsNullOrWhiteSpace(_config.DiscordBotToken))
                        {
                            string appDataTokenPath = Path.Combine(_configDirectory, "bot_token.txt");
                            string baseDirTokenPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "bot_token.txt");
                            if (File.Exists(appDataTokenPath))
                            {
                                try { _config.DiscordBotToken = UnprotectString((await File.ReadAllTextAsync(appDataTokenPath)).Trim()); } catch { }
                            }
                            else if (File.Exists(baseDirTokenPath))
                            {
                                try { _config.DiscordBotToken = UnprotectString((await File.ReadAllTextAsync(baseDirTokenPath)).Trim()); } catch { }
                            }
                        }

                        string? envAdminPw = Environment.GetEnvironmentVariable("PALWORLD_ADMIN_PASSWORD");
                        if (!string.IsNullOrWhiteSpace(envAdminPw))
                        {
                            _config.ServerAdminPassword = envAdminPw.Trim();
                        }

                        string? envAccessKey = Environment.GetEnvironmentVariable("PALODYSSEY_ACCESS_KEY");
                        if (!string.IsNullOrWhiteSpace(envAccessKey))
                        {
                            _config.RemoteAccessKey = envAccessKey.Trim();
                        }

                        _logService.LogInfo($"Configuration loaded from {_configFilePath}", "Config");
                        return _config;
                    }
                }
            }
            catch (Exception ex)
            {
                _logService.LogWarning($"Failed to load config file. Using default settings.", "Config", ex.Message);
            }

            _config = new LauncherConfig();
            
            // Check fallback bot_token.txt for new default configuration
            try
            {
                string appDataTokenPath = Path.Combine(_configDirectory, "bot_token.txt");
                string baseDirTokenPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "bot_token.txt");
                if (File.Exists(appDataTokenPath))
                {
                    _config.DiscordBotToken = UnprotectString((await File.ReadAllTextAsync(appDataTokenPath)).Trim());
                }
                else if (File.Exists(baseDirTokenPath))
                {
                    _config.DiscordBotToken = UnprotectString((await File.ReadAllTextAsync(baseDirTokenPath)).Trim());
                }
            }
            catch { }

            await SaveConfigAsync(_config);
            return _config;
        }

        public async Task SaveConfigAsync(LauncherConfig? config = null)
        {
            if (config != null)
            {
                _config = config;
            }

            try
            {
                // Create a clone or serialization object with protected token if configured
                var configToSave = CloneConfig(_config);
                if (!string.IsNullOrEmpty(configToSave.DiscordBotToken) && !configToSave.DiscordBotToken.StartsWith("ENC:"))
                {
                    configToSave.DiscordBotToken = ProtectString(configToSave.DiscordBotToken);
                }

                string json = JsonSerializer.Serialize(configToSave, _jsonOptions);
                await File.WriteAllTextAsync(_configFilePath, json);

                // Keep bot_token.txt synchronized
                if (!string.IsNullOrWhiteSpace(_config.DiscordBotToken))
                {
                    try
                    {
                        string appDataTokenPath = Path.Combine(_configDirectory, "bot_token.txt");
                        await File.WriteAllTextAsync(appDataTokenPath, _config.DiscordBotToken.Trim());
                    }
                    catch { }
                }

                _logService.LogInfo("Configuration saved successfully.", "Config");
            }
            catch (Exception ex)
            {
                _logService.LogError("Failed to save configuration.", "Config", ex);
            }
        }

        public string GetConfigFilePath() => _configFilePath;

        public static string ProtectString(string plainText)
        {
            if (string.IsNullOrEmpty(plainText)) return string.Empty;
            if (plainText.StartsWith("ENC:")) return plainText;
            try
            {
                if (OperatingSystem.IsWindows())
                {
                    byte[] plainBytes = System.Text.Encoding.UTF8.GetBytes(plainText);
                    byte[] cipherBytes = System.Security.Cryptography.ProtectedData.Protect(plainBytes, null, System.Security.Cryptography.DataProtectionScope.CurrentUser);
                    return "ENC:" + Convert.ToBase64String(cipherBytes);
                }
            }
            catch { }
            return plainText;
        }

        public static string UnprotectString(string cipherOrPlain)
        {
            if (string.IsNullOrEmpty(cipherOrPlain)) return string.Empty;
            if (cipherOrPlain.StartsWith("ENC:"))
            {
                try
                {
                    if (OperatingSystem.IsWindows())
                    {
                        byte[] cipherBytes = Convert.FromBase64String(cipherOrPlain[4..]);
                        byte[] plainBytes = System.Security.Cryptography.ProtectedData.Unprotect(cipherBytes, null, System.Security.Cryptography.DataProtectionScope.CurrentUser);
                        return System.Text.Encoding.UTF8.GetString(plainBytes);
                    }
                }
                catch { }
            }
            return cipherOrPlain;
        }

        private static LauncherConfig CloneConfig(LauncherConfig source)
        {
            string json = JsonSerializer.Serialize(source);
            return JsonSerializer.Deserialize<LauncherConfig>(json) ?? new LauncherConfig();
        }
    }
}
