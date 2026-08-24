using System;
using System.IO;
using System.Threading.Tasks;
using System.Windows;
using Microsoft.Win32;
using PalLauncher.Models;
using PalLauncher.Services;
using PalLauncher.Services.Interfaces;
using PalLauncher.ViewModels.Common;

namespace PalLauncher.ViewModels
{
    public class SettingsViewModel : ViewModelBase
    {
        private readonly IConfigService _configService;
        private readonly IGamePathDetector _pathDetector;
        private readonly ILaunchService _launchService;
        private readonly IUpdateService _updateService;
        private readonly ILogService _logService;

        private string _gamePath = string.Empty;
        private string _launchMode = "Client";
        private string _serverIp = "palodyssey.duckdns.org";
        private int _serverPort = 8211;
        private bool _autoJoinServer;
        private string _remoteManifestUrl = string.Empty;
        private string _paksRelativePath = @"Pal\Content\Paks\~mods";
        private bool _autoCheckUpdatesOnStartup = true;
        private bool _autoUpdateBeforeLaunch = true;
        private bool _closeLauncherOnLaunch;
        private bool _useDirectX11 = true;
        private bool _useAllCores = true;
        private bool _useHighPriority;
        private bool _noSplash = true;
        private bool _windowedMode;
        private string _customArguments = "-culture=en";

        // Detection & UI feedback
        private GamePathInfo _currentPathInfo = new();
        private string _statusMessage = string.Empty;
        private bool _isTestingUrl;

        public string GamePath
        {
            get => _gamePath;
            set
            {
                if (SetProperty(ref _gamePath, value))
                {
                    ValidateCurrentPath();
                    OnPropertyChanged(nameof(GeneratedArgumentsPreview));
                }
            }
        }

        public string LaunchMode
        {
            get => _launchMode;
            set
            {
                if (SetProperty(ref _launchMode, value))
                {
                    OnPropertyChanged(nameof(IsClientMode));
                    OnPropertyChanged(nameof(IsServerMode));
                    OnPropertyChanged(nameof(GeneratedArgumentsPreview));
                }
            }
        }

        public bool IsClientMode
        {
            get => LaunchMode == "Client";
            set
            {
                if (value) LaunchMode = "Client";
            }
        }

        public bool IsServerMode
        {
            get => LaunchMode == "Server";
            set
            {
                if (value) LaunchMode = "Server";
            }
        }

        public string ServerIp
        {
            get => _serverIp;
            set
            {
                if (SetProperty(ref _serverIp, value))
                {
                    OnPropertyChanged(nameof(GeneratedArgumentsPreview));
                }
            }
        }

        public int ServerPort
        {
            get => _serverPort;
            set
            {
                if (SetProperty(ref _serverPort, value))
                {
                    OnPropertyChanged(nameof(GeneratedArgumentsPreview));
                }
            }
        }

        private int _remoteManagementPort = 8215;
        private string _remoteAccessKey = "PalOdyssey2026Secure";
        private bool _enableRemoteHostDaemon = true;
        private bool _autoRemoteWakeOnLaunch = true;

        public int RemoteManagementPort
        {
            get => _remoteManagementPort;
            set => SetProperty(ref _remoteManagementPort, value);
        }

        public string RemoteAccessKey
        {
            get => _remoteAccessKey;
            set => SetProperty(ref _remoteAccessKey, value);
        }

        public bool EnableRemoteHostDaemon
        {
            get => _enableRemoteHostDaemon;
            set => SetProperty(ref _enableRemoteHostDaemon, value);
        }

        private bool _enableIdleAutoShutdown = true;
        private int _idleShutdownMinutes = 15;
        private bool _enablePlayitTunnel = true;

        public bool AutoRemoteWakeOnLaunch
        {
            get => _autoRemoteWakeOnLaunch;
            set => SetProperty(ref _autoRemoteWakeOnLaunch, value);
        }

        public bool EnableIdleAutoShutdown
        {
            get => _enableIdleAutoShutdown;
            set => SetProperty(ref _enableIdleAutoShutdown, value);
        }

        public int IdleShutdownMinutes
        {
            get => _idleShutdownMinutes;
            set => SetProperty(ref _idleShutdownMinutes, value);
        }

        public bool EnablePlayitTunnel
        {
            get => _enablePlayitTunnel;
            set => SetProperty(ref _enablePlayitTunnel, value);
        }

        private bool _enableDiscordRpc = true;
        private string _discordApplicationId = "1540924979095408700";
        private bool _enableDiscordBot = true;
        private string _discordBotToken = "";
        private string _discordCommandPrefix = "/";
        private string _discordBotChannelId = "1541333590707671160";
        private string _discordAdminRoleId = "";

        public bool EnableDiscordRpc
        {
            get => _enableDiscordRpc;
            set => SetProperty(ref _enableDiscordRpc, value);
        }

        public string DiscordApplicationId
        {
            get => _discordApplicationId;
            set => SetProperty(ref _discordApplicationId, value);
        }

        public bool EnableDiscordBot
        {
            get => _enableDiscordBot;
            set => SetProperty(ref _enableDiscordBot, value);
        }

        public string DiscordBotToken
        {
            get => _discordBotToken;
            set => SetProperty(ref _discordBotToken, value);
        }

        public string DiscordCommandPrefix
        {
            get => _discordCommandPrefix;
            set => SetProperty(ref _discordCommandPrefix, value);
        }

        public string DiscordBotChannelId
        {
            get => _discordBotChannelId;
            set => SetProperty(ref _discordBotChannelId, value);
        }

        public string DiscordAdminRoleId
        {
            get => _discordAdminRoleId;
            set => SetProperty(ref _discordAdminRoleId, value);
        }

        public bool AutoJoinServer
        {
            get => _autoJoinServer;
            set
            {
                if (SetProperty(ref _autoJoinServer, value))
                {
                    OnPropertyChanged(nameof(GeneratedArgumentsPreview));
                }
            }
        }

        public string RemoteManifestUrl
        {
            get => _remoteManifestUrl;
            set => SetProperty(ref _remoteManifestUrl, value);
        }

        public string PaksRelativePath
        {
            get => _paksRelativePath;
            set => SetProperty(ref _paksRelativePath, value);
        }

        public bool AutoCheckUpdatesOnStartup
        {
            get => _autoCheckUpdatesOnStartup;
            set => SetProperty(ref _autoCheckUpdatesOnStartup, value);
        }

        public bool AutoUpdateBeforeLaunch
        {
            get => _autoUpdateBeforeLaunch;
            set => SetProperty(ref _autoUpdateBeforeLaunch, value);
        }

        public bool CloseLauncherOnLaunch
        {
            get => _closeLauncherOnLaunch;
            set => SetProperty(ref _closeLauncherOnLaunch, value);
        }

        public bool UseDirectX11
        {
            get => _useDirectX11;
            set
            {
                if (SetProperty(ref _useDirectX11, value))
                {
                    OnPropertyChanged(nameof(GeneratedArgumentsPreview));
                }
            }
        }

        public bool UseAllCores
        {
            get => _useAllCores;
            set
            {
                if (SetProperty(ref _useAllCores, value))
                {
                    OnPropertyChanged(nameof(GeneratedArgumentsPreview));
                }
            }
        }

        public bool UseHighPriority
        {
            get => _useHighPriority;
            set
            {
                if (SetProperty(ref _useHighPriority, value))
                {
                    OnPropertyChanged(nameof(GeneratedArgumentsPreview));
                }
            }
        }

        public bool NoSplash
        {
            get => _noSplash;
            set
            {
                if (SetProperty(ref _noSplash, value))
                {
                    OnPropertyChanged(nameof(GeneratedArgumentsPreview));
                }
            }
        }

        public bool WindowedMode
        {
            get => _windowedMode;
            set
            {
                if (SetProperty(ref _windowedMode, value))
                {
                    OnPropertyChanged(nameof(GeneratedArgumentsPreview));
                }
            }
        }

        private bool _enableRawInputOptimization = true;

        public bool EnableRawInputOptimization
        {
            get => _enableRawInputOptimization;
            set => SetProperty(ref _enableRawInputOptimization, value);
        }

        public string CustomArguments
        {
            get => _customArguments;
            set
            {
                if (SetProperty(ref _customArguments, value))
                {
                    OnPropertyChanged(nameof(GeneratedArgumentsPreview));
                }
            }
        }

        public GamePathInfo CurrentPathInfo
        {
            get => _currentPathInfo;
            set
            {
                if (SetProperty(ref _currentPathInfo, value))
                {
                    OnPropertyChanged(nameof(IsPathValid));
                    OnPropertyChanged(nameof(PathStatusText));
                }
            }
        }

        public bool IsPathValid => CurrentPathInfo.IsValid;
        public string PathStatusText => CurrentPathInfo.IsValid
            ? $"✓ Palworld installation verified ({CurrentPathInfo.DetectedSource})"
            : "⚠ Palworld directory or executable not detected";

        public string StatusMessage
        {
            get => _statusMessage;
            set => SetProperty(ref _statusMessage, value);
        }

        public bool IsTestingUrl
        {
            get => _isTestingUrl;
            set => SetProperty(ref _isTestingUrl, value);
        }

        public string GeneratedArgumentsPreview
        {
            get
            {
                var dummyConfig = CreateConfigFromProperties();
                if (IsServerMode)
                {
                    return _launchService.BuildServerCommandLineArguments(dummyConfig);
                }
                return _launchService.BuildCommandLineArguments(dummyConfig);
            }
        }

        public RelayCommand BrowsePathCommand { get; }
        public RelayCommand AutoDetectPathCommand { get; }
        private readonly ISystemSpecService _specService;
        private SystemHardwareProfile _hardwareProfile = new();

        public SystemHardwareProfile HardwareProfile
        {
            get => _hardwareProfile;
            set => SetProperty(ref _hardwareProfile, value);
        }

        public AsyncRelayCommand SaveSettingsCommand { get; }
        public AsyncRelayCommand TestManifestUrlCommand { get; }
        public RelayCommand ResetDefaultsCommand { get; }
        public AsyncRelayCommand AutoOptimizeFlagsCommand { get; }

        public SettingsViewModel(
            IConfigService configService,
            IGamePathDetector pathDetector,
            ILaunchService launchService,
            IUpdateService updateService,
            ILogService logService,
            ISystemSpecService? specService = null)
        {
            _configService = configService;
            _pathDetector = pathDetector;
            _launchService = launchService;
            _updateService = updateService;
            _logService = logService;
            _specService = specService ?? new SystemSpecService(_logService);

            BrowsePathCommand = new RelayCommand(ExecuteBrowsePath);
            AutoDetectPathCommand = new RelayCommand(ExecuteAutoDetectPath);
            SaveSettingsCommand = new AsyncRelayCommand(ExecuteSaveSettingsAsync);
            TestManifestUrlCommand = new AsyncRelayCommand(ExecuteTestManifestUrlAsync);
            ResetDefaultsCommand = new RelayCommand(ExecuteResetDefaults);
            AutoOptimizeFlagsCommand = new AsyncRelayCommand(ExecuteAutoOptimizeFlagsAsync);

            LoadFromConfig(_configService.Config);
            _ = InitializeHardwareSpecsAsync();
        }

        public async Task InitializeHardwareSpecsAsync()
        {
            try
            {
                var profile = await _specService.DetectSystemSpecsAsync();
                HardwareProfile = profile;
            }
            catch { }
        }

        private bool _isCalibrating;
        public bool IsCalibrating
        {
            get => _isCalibrating;
            set => SetProperty(ref _isCalibrating, value);
        }

        private int _calibrationProgress;
        public int CalibrationProgress
        {
            get => _calibrationProgress;
            set => SetProperty(ref _calibrationProgress, value);
        }

        private string _calibrationStageText = string.Empty;
        public string CalibrationStageText
        {
            get => _calibrationStageText;
            set => SetProperty(ref _calibrationStageText, value);
        }

        public async Task ExecuteAutoOptimizeFlagsAsync()
        {
            try
            {
                IsCalibrating = true;
                CalibrationProgress = 5;
                CalibrationStageText = "Initializing hardware & benchmark pipeline...";
                StatusMessage = "⚡ Auto-calibrating system hardware & benchmark pipeline...";

                var progressHandler = new Progress<CalibrationProgressInfo>(p =>
                {
                    CalibrationProgress = p.Percent;
                    CalibrationStageText = $"{p.Stage} ({p.Percent}%)";
                    StatusMessage = p.Details;
                });

                var profile = await _specService.AutoCalibrateAsync(progressHandler, GamePath);
                HardwareProfile = profile;

                UseAllCores = profile.RecommendAllCores;
                UseDirectX11 = profile.RecommendDirectX11;
                NoSplash = profile.RecommendNoSplash;
                UseHighPriority = profile.RecommendHighPriority;
                WindowedMode = profile.RecommendWindowedMode;

                if (!string.IsNullOrWhiteSpace(profile.RecommendedCustomArguments))
                {
                    CustomArguments = profile.RecommendedCustomArguments;
                }

                StatusMessage = $"⚡ Calibrated for {profile.PerformanceTier} • Target: {profile.EstimatedAvgFps}";
                _logService.LogSuccess($"Auto-calibrated startup flags & modpack: {profile.RecommendationSummary}", "Optimizer");
            }
            catch (Exception ex)
            {
                StatusMessage = $"Failed to auto-calibrate: {ex.Message}";
                _logService.LogError("Auto-calibrate exception occurred.", "Optimizer", ex);
            }
            finally
            {
                IsCalibrating = false;
            }
        }

        private bool _launchServerWithGame = true;

        public bool LaunchServerWithGame
        {
            get => _launchServerWithGame;
            set => SetProperty(ref _launchServerWithGame, value);
        }

        public void LoadFromConfig(LauncherConfig config)
        {
            _gamePath = config.GamePath;
            _launchMode = config.LaunchMode;
            _serverIp = config.ServerIp;
            _serverPort = config.ServerPort;
            _autoJoinServer = config.AutoJoinServer;
            _launchServerWithGame = config.LaunchServerWithGame;
            _remoteManagementPort = config.RemoteManagementPort;
            _remoteAccessKey = config.RemoteAccessKey;
            _enableRemoteHostDaemon = config.EnableRemoteHostDaemon;
            _autoRemoteWakeOnLaunch = config.AutoRemoteWakeOnLaunch;
            _enableIdleAutoShutdown = config.EnableIdleAutoShutdown;
            _idleShutdownMinutes = config.IdleShutdownMinutes;
            _enablePlayitTunnel = config.EnablePlayitTunnel;
            _enableDiscordRpc = config.EnableDiscordRpc;
            _discordApplicationId = config.DiscordApplicationId;
            _enableDiscordBot = config.EnableDiscordBot;
            _discordBotToken = config.DiscordBotToken;
            _discordCommandPrefix = string.IsNullOrWhiteSpace(config.DiscordCommandPrefix) ? "/" : config.DiscordCommandPrefix;
            _discordBotChannelId = string.IsNullOrWhiteSpace(config.DiscordBotChannelId) ? "1541333590707671160" : config.DiscordBotChannelId;
            _discordAdminRoleId = config.DiscordAdminRoleId;
            _remoteManifestUrl = config.RemoteManifestUrl;
            _paksRelativePath = config.PaksRelativePath;
            _autoCheckUpdatesOnStartup = config.AutoCheckUpdatesOnStartup;
            _autoUpdateBeforeLaunch = config.AutoUpdateBeforeLaunch;
            _closeLauncherOnLaunch = config.CloseLauncherOnLaunch;
            _useDirectX11 = config.UseDirectX11;
            _useAllCores = config.UseAllCores;
            _useHighPriority = config.UseHighPriority;
            _noSplash = config.NoSplash;
            _windowedMode = config.WindowedMode;
            _enableRawInputOptimization = config.EnableRawInputOptimization;
            _customArguments = config.CustomArguments;

            OnPropertyChanged(string.Empty);

            if (string.IsNullOrWhiteSpace(_gamePath))
            {
                ExecuteAutoDetectPath();
            }
            else
            {
                ValidateCurrentPath();
            }
        }

        public LauncherConfig CreateConfigFromProperties()
        {
            return new LauncherConfig
            {
                GamePath = GamePath,
                LaunchMode = LaunchMode,
                ServerIp = ServerIp,
                ServerPort = ServerPort,
                AutoJoinServer = AutoJoinServer,
                LaunchServerWithGame = LaunchServerWithGame,
                RemoteManagementPort = RemoteManagementPort,
                RemoteAccessKey = RemoteAccessKey,
                EnableRemoteHostDaemon = EnableRemoteHostDaemon,
                AutoRemoteWakeOnLaunch = AutoRemoteWakeOnLaunch,
                EnableIdleAutoShutdown = EnableIdleAutoShutdown,
                IdleShutdownMinutes = IdleShutdownMinutes,
                EnablePlayitTunnel = EnablePlayitTunnel,
                EnableDiscordRpc = EnableDiscordRpc,
                DiscordApplicationId = DiscordApplicationId,
                EnableDiscordBot = EnableDiscordBot,
                DiscordBotToken = !string.IsNullOrWhiteSpace(DiscordBotToken) ? DiscordBotToken : _configService.Config.DiscordBotToken,
                DiscordCommandPrefix = string.IsNullOrWhiteSpace(DiscordCommandPrefix) ? "/" : DiscordCommandPrefix,
                DiscordBotChannelId = string.IsNullOrWhiteSpace(DiscordBotChannelId) ? "1541333590707671160" : DiscordBotChannelId,
                DiscordAdminRoleId = DiscordAdminRoleId,
                RemoteManifestUrl = RemoteManifestUrl,
                PaksRelativePath = PaksRelativePath,
                AutoCheckUpdatesOnStartup = AutoCheckUpdatesOnStartup,
                AutoUpdateBeforeLaunch = AutoUpdateBeforeLaunch,
                CloseLauncherOnLaunch = CloseLauncherOnLaunch,
                UseDirectX11 = UseDirectX11,
                UseAllCores = UseAllCores,
                UseHighPriority = UseHighPriority,
                NoSplash = NoSplash,
                WindowedMode = WindowedMode,
                EnableRawInputOptimization = EnableRawInputOptimization,
                CustomArguments = CustomArguments
            };
        }

        private void ExecuteBrowsePath()
        {
            try
            {
                // In .NET 8 WPF, OpenFolderDialog is supported natively
                var folderDialog = new OpenFolderDialog
                {
                    Title = "Select Palworld Installation Directory (containing Palworld.exe or Pal folder)",
                    InitialDirectory = Directory.Exists(GamePath) ? GamePath : @"C:\Program Files (x86)\Steam\steamapps\common"
                };

                if (folderDialog.ShowDialog() == true)
                {
                    GamePath = folderDialog.FolderName;
                    _logService.LogInfo($"User selected game folder: {GamePath}", "Settings");
                }
            }
            catch
            {
                // Fallback using OpenFileDialog if folder picker is unavailable
                var fileDialog = new OpenFileDialog
                {
                    Title = "Select Palworld.exe or PalServer.exe",
                    Filter = "Executable files (*.exe)|*.exe|All files (*.*)|*.*"
                };

                if (fileDialog.ShowDialog() == true)
                {
                    var dir = Path.GetDirectoryName(fileDialog.FileName);
                    if (!string.IsNullOrEmpty(dir))
                    {
                        GamePath = dir;
                    }
                }
            }
        }

        private void ExecuteAutoDetectPath()
        {
            StatusMessage = "Scanning registry and Steam libraries for Palworld...";
            var info = _pathDetector.DetectPalworldInstallation();
            if (info.IsValid)
            {
                GamePath = info.GameRootPath;
                CurrentPathInfo = info;
                StatusMessage = $"Found Palworld via {info.DetectedSource}!";
            }
            else
            {
                CurrentPathInfo = info;
                StatusMessage = "Automatic detection did not locate Palworld. Please click 'Browse' to select your game folder.";
            }
        }

        private void ValidateCurrentPath()
        {
            if (string.IsNullOrWhiteSpace(GamePath))
            {
                CurrentPathInfo = new GamePathInfo { IsValid = false, DetectedSource = "None" };
                return;
            }

            CurrentPathInfo = _pathDetector.ValidatePath(GamePath);
        }

        private async Task ExecuteSaveSettingsAsync()
        {
            var config = CreateConfigFromProperties();
            await _configService.SaveConfigAsync(config);
            StatusMessage = "Settings saved successfully!";
        }

        private async Task ExecuteTestManifestUrlAsync()
        {
            if (string.IsNullOrWhiteSpace(RemoteManifestUrl))
            {
                StatusMessage = "Please enter a valid manifest URL.";
                return;
            }

            IsTestingUrl = true;
            StatusMessage = "Connecting to manifest URL...";

            try
            {
                var manifest = await _updateService.FetchManifestAsync(RemoteManifestUrl);
                if (manifest != null)
                {
                    StatusMessage = $"Connection successful! Found v{manifest.ManifestVersion} with {manifest.Mods.Count} mods.";
                }
                else
                {
                    StatusMessage = "Connection failed. Please check the URL.";
                }
            }
            catch (Exception ex)
            {
                StatusMessage = $"Error: {ex.Message}";
            }
            finally
            {
                IsTestingUrl = false;
            }
        }

        private void ExecuteResetDefaults()
        {
            var defaultConfig = new LauncherConfig();
            LoadFromConfig(defaultConfig);
            StatusMessage = "Settings reset to defaults.";
        }
    }
}
