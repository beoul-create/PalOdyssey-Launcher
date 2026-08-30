using System;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Runtime.CompilerServices;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media;
using Microsoft.Win32;
using PalLauncher.Models;
using PalLauncher.Services;

namespace PalLauncher.ViewModels
{
    public enum LauncherState
    {
        Idle,
        CheckingUpdates,
        VerifyingIntegrity,
        Downloading,
        GameRunning,
        Error
    }

    public class MainViewModel : INotifyPropertyChanged, IDisposable
    {
        private readonly HashService _hashService;
        private readonly ManifestService _manifestService;
        private readonly DownloadManager _downloadManager;
        private readonly GameProcessService _gameProcessService;
        private readonly RemoteServerService _remoteServerService;
        private readonly DiscordRpcService _discordRpcService;
        private readonly AudioService _audioService;
        private readonly ServerQueryService _serverQueryService;
        private readonly LauncherUpdaterService _launcherUpdaterService;

        private LauncherConfig _config;
        private LocalCache _cache;
        private readonly string _cacheFilePath;
        private ManifestModel? _currentManifest;

        private LauncherState _currentState = LauncherState.Idle;
        private string _statusMessage = "READY TO EMBARK";
        private string _subStatusMessage = "All mods verified. Server online.";
        private string _actionButtonText = "PLAY NOW";
        private double _downloadPercentage;
        private string _downloadSpeedText = "0.00 MB/s";
        private string _currentProgressText = "";
        private bool _isProgressVisible;
        private bool _isActionEnabled = true;
        private string _gamePath = "";
        private string _serverStatusText = "ONLINE";
        private string _onlinePlayersText = "0 / 32 Players";
        private string _topBeaconStatusText = "CHECKING...";
        private string _topBeaconColor = "#10B981";
        private string _serverPingText = "-- ms";
        private string _serverPingColor = "#34D399";
        private string _serverName = "PalOdyssey Official Modded Realm";
        private string _gameVersion = "v0.3.5 Modded";
        private bool _isSettingsFlyoutOpen;
        private bool _isSoundEnabled = true;
        private bool _isDiscordRpcEnabled = true;

        private bool _isLauncherUpdateAvailable;
        private string _launcherUpdateVersion = "";
        private string _launcherUpdateNotes = "";
        private LauncherReleaseInfo? _pendingLauncherRelease;

        public event PropertyChangedEventHandler? PropertyChanged;

        public ObservableCollection<ServerNewsItem> NewsItems { get; } = new();

        public ICommand PlayCommand { get; }
        public ICommand BrowseGamePathCommand { get; }
        public ICommand ToggleSettingsCommand { get; }
        public ICommand ToggleSoundCommand { get; }
        public ICommand ToggleDiscordRpcCommand { get; }
        public ICommand OpenDiscordCommand { get; }
        public ICommand LaunchWithoutUpdatingCommand { get; }
        public ICommand HoverSoundCommand { get; }
        public ICommand ClickSoundCommand { get; }
        public ICommand UpdateLauncherCommand { get; }
        public ICommand DismissLauncherUpdateCommand { get; }

        public MainViewModel()
        {
            _cacheFilePath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "cache.json");
            _cache = LocalCache.Load(_cacheFilePath);
            _config = LauncherConfig.Load();

            _hashService = new HashService();
            _manifestService = new ManifestService(_hashService);
            _downloadManager = new DownloadManager(_hashService);
            _gameProcessService = new GameProcessService();
            _remoteServerService = new RemoteServerService();
            _discordRpcService = new DiscordRpcService();
            _audioService = new AudioService();
            _serverQueryService = new ServerQueryService(_config.ServerIp, _config.ServerPort, _config.ServerInstallPath);
            _launcherUpdaterService = new LauncherUpdaterService(_hashService);

            _isSoundEnabled = _config.SoundEnabled;
            _isDiscordRpcEnabled = _config.DiscordRpcEnabled;
            _closeLauncherOnStart = _config.CloseLauncherOnStart;
            _audioService.IsSoundEnabled = _isSoundEnabled;

            // Wire commands
            PlayCommand = new AsyncRelayCommand(OnPlayClickedAsync, () => IsActionEnabled);
            BrowseGamePathCommand = new RelayCommand(OnBrowseGamePath);
            ToggleSettingsCommand = new RelayCommand(() => IsSettingsFlyoutOpen = !IsSettingsFlyoutOpen);
            ToggleSoundCommand = new RelayCommand(OnToggleSound);
            ToggleDiscordRpcCommand = new RelayCommand(OnToggleDiscordRpc);
            OpenDiscordCommand = new RelayCommand(OnOpenDiscord);
            LaunchWithoutUpdatingCommand = new AsyncRelayCommand(OnLaunchDirectAsync);
            HoverSoundCommand = new RelayCommand(() => _audioService.PlayHover());
            ClickSoundCommand = new RelayCommand(() => _audioService.PlayClick());
            UpdateLauncherCommand = new AsyncRelayCommand(OnUpdateLauncherAsync);
            DismissLauncherUpdateCommand = new RelayCommand(() => IsLauncherUpdateAvailable = false);

            // Wire game process events
            _gameProcessService.GameStarted += OnGameStarted;
            _gameProcessService.GameExited += OnGameExited;
            _serverQueryService.ServerStatusUpdated += OnServerStatusUpdated;

            // Initialize services
            _audioService.Initialize();
            if (_isDiscordRpcEnabled)
            {
                _discordRpcService.Initialize();
            }

            // Detect Game Directory
            InitializeGamePath();

            // Load initial news and fallback manifest
            var fallbackManifest = ManifestService.GetDefaultFallbackManifest();
            LoadManifestData(fallbackManifest);
        }

        #region Properties

        public LauncherState CurrentState
        {
            get => _currentState;
            set
            {
                if (SetProperty(ref _currentState, value))
                {
                    UpdateStatePresentation();
                }
            }
        }

        public string StatusMessage
        {
            get => _statusMessage;
            set => SetProperty(ref _statusMessage, value);
        }

        public string SubStatusMessage
        {
            get => _subStatusMessage;
            set => SetProperty(ref _subStatusMessage, value);
        }

        public string ActionButtonText
        {
            get => _actionButtonText;
            set => SetProperty(ref _actionButtonText, value);
        }

        public double DownloadPercentage
        {
            get => _downloadPercentage;
            set => SetProperty(ref _downloadPercentage, value);
        }

        public string DownloadSpeedText
        {
            get => _downloadSpeedText;
            set => SetProperty(ref _downloadSpeedText, value);
        }

        public string CurrentProgressText
        {
            get => _currentProgressText;
            set => SetProperty(ref _currentProgressText, value);
        }

        public bool IsProgressVisible
        {
            get => _isProgressVisible;
            set => SetProperty(ref _isProgressVisible, value);
        }

        public bool IsActionEnabled
        {
            get => _isActionEnabled;
            set => SetProperty(ref _isActionEnabled, value);
        }

        public string GamePath
        {
            get => _gamePath;
            set
            {
                if (SetProperty(ref _gamePath, value))
                {
                    _config.GamePath = value;
                    _config.Save();
                }
            }
        }

        public string ServerStatusText
        {
            get => _serverStatusText;
            set => SetProperty(ref _serverStatusText, value);
        }

        public string OnlinePlayersText
        {
            get => _onlinePlayersText;
            set => SetProperty(ref _onlinePlayersText, value);
        }

        public string TopBeaconStatusText
        {
            get => _topBeaconStatusText;
            set => SetProperty(ref _topBeaconStatusText, value);
        }

        public string TopBeaconColor
        {
            get => _topBeaconColor;
            set
            {
                if (SetProperty(ref _topBeaconColor, value))
                {
                    PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(TopBeaconBrush)));
                    PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(TopBeaconBackgroundBrush)));
                    PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(TopBeaconBorderBrush)));
                }
            }
        }

        public SolidColorBrush TopBeaconBrush => new((Color)ColorConverter.ConvertFromString(TopBeaconColor));

        public SolidColorBrush TopBeaconBackgroundBrush
        {
            get
            {
                var c = (Color)ColorConverter.ConvertFromString(TopBeaconColor);
                return new SolidColorBrush(Color.FromArgb(26, c.R, c.G, c.B));
            }
        }

        public SolidColorBrush TopBeaconBorderBrush
        {
            get
            {
                var c = (Color)ColorConverter.ConvertFromString(TopBeaconColor);
                return new SolidColorBrush(Color.FromArgb(51, c.R, c.G, c.B));
            }
        }

        public string ServerPingText
        {
            get => _serverPingText;
            set => SetProperty(ref _serverPingText, value);
        }

        public SolidColorBrush ServerPingBrush => new((Color)ColorConverter.ConvertFromString(_serverPingColor));

        public string ServerName
        {
            get => _serverName;
            set => SetProperty(ref _serverName, value);
        }

        public string GameVersion
        {
            get => _gameVersion;
            set => SetProperty(ref _gameVersion, value);
        }

        public bool IsSettingsFlyoutOpen
        {
            get => _isSettingsFlyoutOpen;
            set => SetProperty(ref _isSettingsFlyoutOpen, value);
        }

        public bool IsSoundEnabled
        {
            get => _isSoundEnabled;
            set
            {
                if (SetProperty(ref _isSoundEnabled, value))
                {
                    _audioService.IsSoundEnabled = value;
                    _config.SoundEnabled = value;
                    _config.Save();
                }
            }
        }

        public bool IsDiscordRpcEnabled
        {
            get => _isDiscordRpcEnabled;
            set
            {
                if (SetProperty(ref _isDiscordRpcEnabled, value))
                {
                    _config.DiscordRpcEnabled = value;
                    _config.Save();
                    if (value) _discordRpcService.Initialize();
                    else _discordRpcService.Dispose();
                }
            }
        }

        private bool _closeLauncherOnStart;
        public bool CloseLauncherOnStart
        {
            get => _closeLauncherOnStart;
            set
            {
                if (SetProperty(ref _closeLauncherOnStart, value))
                {
                    _config.CloseLauncherOnStart = value;
                    _config.Save();
                }
            }
        }

        public GameProcessService GameProcessService => _gameProcessService;
        public RemoteServerService RemoteServerService => _remoteServerService;
        public LauncherConfig Config => _config;

        public string RemoteServerApiUrl
        {
            get => _config.RemoteServerApiUrl;
            set
            {
                if (_config.RemoteServerApiUrl != value)
                {
                    _config.RemoteServerApiUrl = value;
                    _config.Save();
                    PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(RemoteServerApiUrl)));
                }
            }
        }

        public string RemoteAdminKey
        {
            get => _config.RemoteAdminKey;
            set
            {
                if (_config.RemoteAdminKey != value)
                {
                    _config.RemoteAdminKey = value;
                    _config.Save();
                    PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(RemoteAdminKey)));
                }
            }
        }

        public bool IsLauncherUpdateAvailable
        {
            get => _isLauncherUpdateAvailable;
            set => SetProperty(ref _isLauncherUpdateAvailable, value);
        }

        public string LauncherUpdateVersion
        {
            get => _launcherUpdateVersion;
            set => SetProperty(ref _launcherUpdateVersion, value);
        }

        public string LauncherUpdateNotes
        {
            get => _launcherUpdateNotes;
            set => SetProperty(ref _launcherUpdateNotes, value);
        }

        public string RemoteManifestUrl
        {
            get => _config.RemoteManifestUrl;
            set
            {
                if (_config.RemoteManifestUrl != value)
                {
                    _config.RemoteManifestUrl = value;
                    _config.Save();
                    PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(RemoteManifestUrl)));
                }
            }
        }

        #endregion

        #region Actions & Orchestration

        private void InitializeGamePath()
        {
            if (!string.IsNullOrWhiteSpace(_config.GamePath) && _gameProcessService.IsValidGameDirectory(_config.GamePath))
            {
                GamePath = _config.GamePath;
                return;
            }

            string? detectedPath = _gameProcessService.DetectGameDirectory();
            if (!string.IsNullOrEmpty(detectedPath))
            {
                GamePath = detectedPath;
            }
            else
            {
                StatusMessage = "PALWORLD NOT FOUND";
                SubStatusMessage = "Click Settings or Browse to set your Palworld installation folder.";
            }
        }

        private void LoadManifestData(ManifestModel manifest)
        {
            _currentManifest = manifest;
            ServerName = manifest.ServerName;
            GameVersion = manifest.GameVersion;

            NewsItems.Clear();
            foreach (var news in manifest.News)
            {
                NewsItems.Add(news);
            }

            _ = Task.Run(async () =>
            {
                try
                {
                    var (hasUpdate, releaseInfo) = await _launcherUpdaterService.CheckForLauncherUpdateAsync(manifest);
                    if (hasUpdate && releaseInfo != null)
                    {
                        App.Current?.Dispatcher?.Invoke(() =>
                        {
                            _pendingLauncherRelease = releaseInfo;
                            LauncherUpdateVersion = $"v{releaseInfo.Version}";
                            LauncherUpdateNotes = releaseInfo.ReleaseNotes;
                            IsLauncherUpdateAvailable = true;
                        });
                    }
                }
                catch { }
            });
        }

        private async Task OnUpdateLauncherAsync()
        {
            if (_pendingLauncherRelease == null) return;
            _audioService.PlayClick();

            try
            {
                CurrentState = LauncherState.Downloading;
                StatusMessage = "UPDATING LAUNCHER...";
                SubStatusMessage = $"Downloading PalLauncher {_pendingLauncherRelease.Version}...";
                IsProgressVisible = true;
                DownloadPercentage = 0;
                DownloadSpeedText = "Connecting...";

                var downloadProgress = new Progress<DownloadProgressReport>(report =>
                {
                    DownloadPercentage = report.Percentage;
                    DownloadSpeedText = report.FormattedSpeedText;
                    CurrentProgressText = report.FormattedProgressText;
                    SubStatusMessage = $"Downloading update ({report.FormattedProgressText})";
                });

                await _launcherUpdaterService.DownloadAndApplyUpdateAsync(_pendingLauncherRelease, downloadProgress);
            }
            catch (Exception ex)
            {
                CurrentState = LauncherState.Error;
                StatusMessage = "UPDATE FAILED";
                SubStatusMessage = ex.Message;
                MessageBox.Show($"Failed to apply launcher update:\n\n{ex.Message}", "Launcher Update Error", MessageBoxButton.OK, MessageBoxImage.Error);
            }
        }

        public async Task OnPlayClickedAsync()
        {
            _audioService.PlayClick();

            // 1. Validate Game Directory
            if (string.IsNullOrWhiteSpace(GamePath) || !_gameProcessService.IsValidGameDirectory(GamePath))
            {
                StatusMessage = "SET GAME PATH";
                SubStatusMessage = "Please select your Palworld installation directory.";
                OnBrowseGamePath();
                if (string.IsNullOrWhiteSpace(GamePath) || !_gameProcessService.IsValidGameDirectory(GamePath))
                {
                    return;
                }
            }

            try
            {
                // 2. Fetch Manifest
                CurrentState = LauncherState.CheckingUpdates;
                StatusMessage = "CHECKING UPDATES...";
                SubStatusMessage = "Connecting to PalOdyssey sync servers...";

                string localFallbackPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "manifest.json");
                _currentManifest = await _manifestService.FetchManifestAsync(_config.RemoteManifestUrl, localFallbackPath);
                LoadManifestData(_currentManifest);

                // 2.5 Check Launcher Self-Update
                var (hasLauncherUpdate, releaseInfo) = await _launcherUpdaterService.CheckForLauncherUpdateAsync(_currentManifest);
                if (hasLauncherUpdate && releaseInfo != null)
                {
                    _pendingLauncherRelease = releaseInfo;
                    LauncherUpdateVersion = $"v{releaseInfo.Version}";
                    LauncherUpdateNotes = releaseInfo.ReleaseNotes;
                    IsLauncherUpdateAvailable = true;

                    var promptResult = MessageBox.Show(
                        $"A new version of the PalOdyssey Launcher is available ({LauncherUpdateVersion})!\n\n" +
                        $"Release Notes: {releaseInfo.ReleaseNotes}\n\n" +
                        "Would you like to update the launcher now?",
                        "Launcher Update Available",
                        MessageBoxButton.YesNo,
                        MessageBoxImage.Information);

                    if (promptResult == MessageBoxResult.Yes || releaseInfo.Mandatory)
                    {
                        await OnUpdateLauncherAsync();
                        return;
                    }
                }

                // 3. Verify Delta & Hashing
                CurrentState = LauncherState.VerifyingIntegrity;
                StatusMessage = "VERIFYING INTEGRITY...";
                IsProgressVisible = true;
                DownloadPercentage = 0;
                DownloadSpeedText = "Calculating hashes...";

                var statusReporter = new Progress<string>(msg =>
                {
                    SubStatusMessage = msg;
                });

                var delta = await _manifestService.CalculateDeltaAsync(
                    _currentManifest,
                    GamePath,
                    _cache,
                    statusReporter);

                _cache.Save(_cacheFilePath);

                // 4. Download missing / mismatched files if any
                if (delta.FilesToDownload.Count > 0)
                {
                    CurrentState = LauncherState.Downloading;
                    StatusMessage = "DOWNLOADING MODS...";

                    var downloadProgress = new Progress<DownloadProgressReport>(report =>
                    {
                        DownloadPercentage = report.Percentage;
                        DownloadSpeedText = report.FormattedSpeedText;
                        CurrentProgressText = report.FormattedProgressText;
                        SubStatusMessage = $"Syncing {report.CurrentFileName} ({report.CurrentFileIndex}/{report.TotalFileCount})";
                    });

                    await _downloadManager.DownloadFilesAsync(
                        delta.FilesToDownload,
                        GamePath,
                        _cache,
                        _cacheFilePath,
                        downloadProgress);
                }

                // 5. Cleanup orphan .paks in ~mods
                int deletedOrphans = _downloadManager.CleanupOrphanPakFiles(GamePath, delta.ValidPakFileNames);
                if (deletedOrphans > 0)
                {
                    SubStatusMessage = $"Cleaned {deletedOrphans} outdated mod pak(s).";
                }

                // 6. Launch Game
                await OnLaunchDirectAsync();
            }
            catch (IOException ioEx)
            {
                CurrentState = LauncherState.Error;
                StatusMessage = "FILE ACCESS LOCKED";
                SubStatusMessage = ioEx.Message;
                MessageBox.Show(
                    $"Failed to update mod files because one or more files are locked:\n\n{ioEx.Message}\n\nPlease ensure Palworld is completely closed and try again.",
                    "File Lock Detected",
                    MessageBoxButton.OK,
                    MessageBoxImage.Warning);
            }
            catch (Exception ex)
            {
                CurrentState = LauncherState.Error;
                StatusMessage = "SYNC ERROR";
                SubStatusMessage = ex.Message;

                var result = MessageBox.Show(
                    $"Unable to complete server synchronization:\n{ex.Message}\n\nWould you like to launch Palworld with current local files?",
                    "Sync Failed",
                    MessageBoxButton.YesNo,
                    MessageBoxImage.Question);

                if (result == MessageBoxResult.Yes)
                {
                    await OnLaunchDirectAsync();
                }
            }
        }

        public async Task OnLaunchDirectAsync()
        {
            if (string.IsNullOrWhiteSpace(GamePath) || !_gameProcessService.IsValidGameDirectory(GamePath))
                return;

            try
            {
                CurrentState = LauncherState.GameRunning;
                StatusMessage = "GAME RUNNING";
                SubStatusMessage = $"Connected to {ServerName}";
                IsProgressVisible = false;

                if (_isDiscordRpcEnabled)
                {
                    _discordRpcService.SetInGamePresence(ServerName);
                }

                await _gameProcessService.LaunchGameAsync(
                    GamePath,
                    _config.ServerIp,
                    _config.ServerPort,
                    _config.LaunchViaSteamProtocol);

                if (_config.CloseLauncherOnStart)
                {
                    Application.Current?.Shutdown();
                }
            }
            catch (Exception ex)
            {
                CurrentState = LauncherState.Error;
                StatusMessage = "LAUNCH FAILED";
                SubStatusMessage = ex.Message;
                MessageBox.Show($"Failed to launch Palworld:\n{ex.Message}", "Launch Error", MessageBoxButton.OK, MessageBoxImage.Error);
            }
        }

        private void OnGameStarted()
        {
            _serverQueryService.SetPollingEnabled(false);
            Application.Current?.Dispatcher.Invoke(() =>
            {
                CurrentState = LauncherState.GameRunning;
            });
        }

        private void OnGameExited()
        {
            _serverQueryService.SetPollingEnabled(true);
            Application.Current?.Dispatcher.Invoke(() =>
            {
                CurrentState = LauncherState.Idle;
                StatusMessage = "READY TO EMBARK";
                SubStatusMessage = "Game closed. Launcher synced.";
                if (_isDiscordRpcEnabled)
                {
                    _discordRpcService.SetLauncherPresence(ServerName);
                }
            });
        }

        private void OnBrowseGamePath()
        {
            _audioService.PlayClick();

            var dialog = new OpenFolderDialog
            {
                Title = "Select Palworld Game Installation Folder"
            };

            if (dialog.ShowDialog() == true)
            {
                string selectedPath = dialog.FolderName;
                if (_gameProcessService.IsValidGameDirectory(selectedPath))
                {
                    GamePath = selectedPath;
                    StatusMessage = "GAME LOCATED";
                    SubStatusMessage = selectedPath;
                }
                else
                {
                    MessageBox.Show(
                        "The selected folder does not contain 'Pal\\Binaries\\Win64\\Palworld-Win64-Shipping.exe'. Please choose the main Palworld installation folder.",
                        "Invalid Palworld Path",
                        MessageBoxButton.OK,
                        MessageBoxImage.Warning);
                }
            }
        }

        private void OnToggleSound()
        {
            IsSoundEnabled = !IsSoundEnabled;
            if (IsSoundEnabled) _audioService.PlayClick();
        }

        private void OnToggleDiscordRpc()
        {
            IsDiscordRpcEnabled = !IsDiscordRpcEnabled;
            _audioService.PlayClick();
        }

        private void OnOpenDiscord()
        {
            _audioService.PlayClick();
            try
            {
                Process.Start(new ProcessStartInfo
                {
                    FileName = "https://discord.gg/8YCVeQgUVq",
                    UseShellExecute = true
                });
            }
            catch { }
        }

        private void OnServerStatusUpdated(ServerStatusInfo info)
        {
            App.Current?.Dispatcher?.Invoke(() =>
            {
                TopBeaconStatusText = info.StatusText;
                TopBeaconColor = info.ColorHex;
                OnlinePlayersText = info.PlayersText;
                ServerPingText = info.PingText;
                _serverPingColor = info.IsOnline ? "#34D399" : "#EF4444";
                PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(nameof(ServerPingBrush)));
            });
        }

        private void UpdateStatePresentation()
        {
            switch (CurrentState)
            {
                case LauncherState.Idle:
                    ActionButtonText = "PLAY NOW";
                    IsActionEnabled = true;
                    IsProgressVisible = false;
                    break;
                case LauncherState.CheckingUpdates:
                    ActionButtonText = "CHECKING UPDATES...";
                    IsActionEnabled = false;
                    IsProgressVisible = false;
                    break;
                case LauncherState.VerifyingIntegrity:
                    ActionButtonText = "VERIFYING...";
                    IsActionEnabled = false;
                    IsProgressVisible = true;
                    break;
                case LauncherState.Downloading:
                    ActionButtonText = "DOWNLOADING...";
                    IsActionEnabled = false;
                    IsProgressVisible = true;
                    break;
                case LauncherState.GameRunning:
                    ActionButtonText = "GAME RUNNING";
                    IsActionEnabled = false;
                    IsProgressVisible = false;
                    break;
                case LauncherState.Error:
                    ActionButtonText = "RETRY LAUNCH";
                    IsActionEnabled = true;
                    IsProgressVisible = false;
                    break;
            }
        }

        #endregion

        #region Helper & INotifyPropertyChanged

        protected bool SetProperty<T>(ref T storage, T value, [CallerMemberName] string? propertyName = null)
        {
            if (Equals(storage, value)) return false;
            storage = value;
            PropertyChanged?.Invoke(this, new PropertyChangedEventArgs(propertyName));
            return true;
        }

        public void Dispose()
        {
            _gameProcessService.GameStarted -= OnGameStarted;
            _gameProcessService.GameExited -= OnGameExited;
            _serverQueryService.ServerStatusUpdated -= OnServerStatusUpdated;
            _serverQueryService.Dispose();
            _downloadManager.Dispose();
            _remoteServerService.Dispose();
            _discordRpcService.Dispose();
            _audioService.Dispose();
            GC.SuppressFinalize(this);
        }

        #endregion
    }
}
