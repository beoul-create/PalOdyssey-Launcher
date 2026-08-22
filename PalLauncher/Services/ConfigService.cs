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
                string json = JsonSerializer.Serialize(_config, _jsonOptions);
                await File.WriteAllTextAsync(_configFilePath, json);
                _logService.LogInfo("Configuration saved successfully.", "Config");
            }
            catch (Exception ex)
            {
                _logService.LogError("Failed to save configuration.", "Config", ex);
            }
        }

        public string GetConfigFilePath() => _configFilePath;
    }
}
