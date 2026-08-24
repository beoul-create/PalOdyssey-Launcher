using System;
using System.Threading.Tasks;
using System.Windows;
using PalLauncher.Models;
using PalLauncher.Services;
using PalLauncher.Services.Interfaces;
using PalLauncher.ViewModels.Common;

namespace PalLauncher.ViewModels
{
    public class MainViewModel : ViewModelBase
    {
        private readonly IConfigService _configService;
        private readonly IGamePathDetector _pathDetector;
        private readonly IUpdateService _updateService;
        private readonly ILaunchService _launchService;
        private readonly ILogService _logService;

        private string _activeView = "Dashboard";
        private string _statusText = "Ready to Launch";
        private double _progressPercentage;
        private bool _isBusy;
        private bool _isGameRunning;
        private string _newsAnnouncement = "Welcome to PalOdyssey Launcher. Verify your core paks and launch your expedition.";

        public string ActiveView
        {
            get => _activeView;
            set
            {
                if (SetProperty(ref _activeView, value))
                {
                    OnPropertyChanged(nameof(IsDashboardActive));
                    OnPropertyChanged(nameof(IsModsActive));
                    OnPropertyChanged(nameof(IsSettingsActive));
                    OnPropertyChanged(nameof(IsLogsActive));
                }
            }
        }

        public bool IsDashboardActive
        {
            get => ActiveView == "Dashboard";
            set
            {
                if (value) ActiveView = "Dashboard";
            }
        }

        public bool IsModsActive
        {
            get => ActiveView == "Mods";
            set
            {
                if (value) ActiveView = "Mods";
            }
        }

        public bool IsSettingsActive
        {
            get => ActiveView == "Settings";
            set
            {
                if (value) ActiveView = "Settings";
            }
        }

        public bool IsLogsActive
        {
            get => ActiveView == "Logs";
            set
            {
                if (value) ActiveView = "Logs";
            }
        }

        public string StatusText
        {
            get => _statusText;
            set
            {
                if (SetProperty(ref _statusText, value))
                {
                    OnPropertyChanged(nameof(StatusMessage));
                }
            }
        }

        public string StatusMessage => StatusText;
        public bool CanLaunch => !IsBusy;
        public AsyncRelayCommand CheckForUpdatesCommand => QuickCheckUpdatesCommand;

        public double ProgressPercentage
        {
            get => _progressPercentage;
            set => SetProperty(ref _progressPercentage, value);
        }

        public bool IsBusy
        {
            get => _isBusy;
            set
            {
                if (SetProperty(ref _isBusy, value))
                {
                    LaunchGameCommand.RaiseCanExecuteChanged();
                    OnPropertyChanged(nameof(LaunchButtonText));
                    OnPropertyChanged(nameof(CanLaunch));
                    OnPropertyChanged(nameof(GameStatusBadge));
                }
            }
        }

        public bool IsGameRunning
        {
            get => _isGameRunning;
            set
            {
                if (SetProperty(ref _isGameRunning, value))
                {
                    OnPropertyChanged(nameof(LaunchButtonText));
                    OnPropertyChanged(nameof(GameStatusBadge));
                }
            }
        }

        public string GameStatusBadge
        {
            get
            {
                if (IsGameRunning) return "Server & Client Active";
                if (IsBusy) return "Starting...";
                return "Ready";
            }
        }

        public string NewsAnnouncement
        {
            get => _newsAnnouncement;
            set => SetProperty(ref _newsAnnouncement, value);
        }

        public string LaunchButtonText
        {
            get
            {
                if (IsGameRunning) return "STOP EXPEDITION & SERVER";
                if (IsBusy) return "STARTING EXPEDITION...";
                return "LAUNCH EXPEDITION";
            }
        }

        public ModsViewModel ModsVM { get; }
        public SettingsViewModel SettingsVM { get; }
        public LogsViewModel LogsVM { get; }

        public RelayCommand NavigateCommand { get; }
        public AsyncRelayCommand LaunchGameCommand { get; }
        public AsyncRelayCommand QuickCheckUpdatesCommand { get; }
        public AsyncRelayCommand RefreshServerStatusCommand { get; }
        public RelayCommand MinimizeCommand { get; }
        public RelayCommand MaximizeCommand { get; }
        public RelayCommand CloseCommand { get; }
        private readonly ISystemSpecService _specService;
        private readonly IRemoteServerDaemon _remoteDaemon;
        private readonly IRemoteClientService _remoteClient;
        private readonly IDiscordRpcService _discordRpc;
        private RemoteServerStatus _serverStatus = new();
        private ServerLiveboardInfo _liveboard = new();
        private CancellationTokenSource? _pollingCts;
        private System.Windows.Threading.DispatcherTimer? _uptimeTimer;

        public ServerLiveboardInfo Liveboard
        {
            get => _liveboard;
            set
            {
                if (SetProperty(ref _liveboard, value))
                {
                    OnPropertyChanged(nameof(ServerStatusBadgeText));
                    OnPropertyChanged(nameof(IsServerOnline));
                }
            }
        }

        public RemoteServerStatus ServerStatus
        {
            get => _serverStatus;
            set
            {
                if (SetProperty(ref _serverStatus, value))
                {
                    OnPropertyChanged(nameof(ServerStatusBadgeText));
                    OnPropertyChanged(nameof(IsServerOnline));
                }
            }
        }

        public bool IsServerOnline => _launchService.IsServerRunning || _liveboard.IsServerRunning || _serverStatus.IsServerRunning;

        public string ServerStatusBadgeText
        {
            get
            {
                if (_launchService.IsServerRunning) return "Local Server Active";
                if (_liveboard.IsServerRunning || _serverStatus.IsServerRunning) return "Server Online";
                if (_liveboard.IsOnline || _serverStatus.IsOnline) return "Server Sleeping (Auto-Wake Ready)";
                return "Server Offline (Auto-Wake Ready)";
            }
        }

        public MainViewModel(
            IConfigService configService,
            IGamePathDetector pathDetector,
            IUpdateService updateService,
            ILaunchService launchService,
            ILogService logService,
            ISystemSpecService? specService = null,
            IRemoteServerDaemon? remoteDaemon = null,
            IRemoteClientService? remoteClient = null,
            IDiscordRpcService? discordRpc = null,
            ICrashLogService? crashLogService = null)
        {
            _configService = configService;
            _pathDetector = pathDetector;
            _updateService = updateService;
            _launchService = launchService;
            _logService = logService;
            _specService = specService ?? new SystemSpecService(_logService);
            _remoteDaemon = remoteDaemon ?? new RemoteServerDaemon(_logService, _launchService);
            _remoteClient = remoteClient ?? new RemoteClientService(_logService);
            _discordRpc = discordRpc ?? new DiscordRpcService(_logService);

            var crashService = crashLogService ?? new Services.CrashLogService(_logService);

            ModsVM = new ModsViewModel(_updateService, _configService, _pathDetector, _logService);
            SettingsVM = new SettingsViewModel(_configService, _pathDetector, _launchService, _updateService, _logService, _specService);
            LogsVM = new LogsViewModel(_logService, crashService, _pathDetector, _configService);

            SettingsVM.PropertyChanged += (s, e) =>
            {
                if (e.PropertyName is nameof(SettingsViewModel.LaunchMode) or nameof(SettingsViewModel.IsServerMode) or nameof(SettingsViewModel.IsClientMode))
                {
                    OnPropertyChanged(nameof(LaunchButtonText));
                    OnPropertyChanged(nameof(GameStatusBadge));
                }
                else if (e.PropertyName is nameof(SettingsViewModel.EnableIdleAutoShutdown) or nameof(SettingsViewModel.IdleShutdownMinutes))
                {
                    _remoteDaemon.ConfigureIdleAutoShutdown(SettingsVM.EnableIdleAutoShutdown, SettingsVM.IdleShutdownMinutes);
                }
            };

            NavigateCommand = new RelayCommand(param =>
            {
                if (param is string viewName)
                {
                    ActiveView = viewName;
                }
            });

            LaunchGameCommand = new AsyncRelayCommand(ExecuteLaunchOrStopAsync);
            QuickCheckUpdatesCommand = new AsyncRelayCommand(ExecuteQuickCheckUpdatesAsync);
            RefreshServerStatusCommand = new AsyncRelayCommand(RefreshServerStatusAsync);

            MinimizeCommand = new RelayCommand(_ =>
            {
                if (Application.Current?.MainWindow != null)
                {
                    Application.Current.MainWindow.WindowState = WindowState.Minimized;
                }
            });

            MaximizeCommand = new RelayCommand(_ =>
            {
                if (Application.Current?.MainWindow != null)
                {
                    Application.Current.MainWindow.WindowState =
                        Application.Current.MainWindow.WindowState == WindowState.Maximized
                            ? WindowState.Normal
                            : WindowState.Maximized;
                }
            });

            _uptimeTimer = new System.Windows.Threading.DispatcherTimer
            {
                Interval = TimeSpan.FromSeconds(1)
            };
            _uptimeTimer.Tick += (s, e) =>
            {
                if (IsServerOnline && Liveboard != null)
                {
                    if (Liveboard.UptimeSeconds > 0)
                    {
                        Liveboard.UptimeSeconds += 1;
                        OnPropertyChanged(nameof(Liveboard));
                    }
                }
            };
            _uptimeTimer.Start();

            CloseCommand = new RelayCommand(_ =>
            {
                _uptimeTimer?.Stop();
                _pollingCts?.Cancel();
                _remoteDaemon.Dispose();
                _discordRpc.Dispose();
                Application.Current?.Shutdown();
            });

            _launchService.ProcessStateChanged += OnProcessStateChanged;

            _ = InitializeAsync();
        }

        public async Task InitializeAsync()
        {
            await _configService.LoadConfigAsync();
            SettingsVM.LoadFromConfig(_configService.Config);

            var pathInfo = _pathDetector.DetectPalworldInstallation(_configService.Config.GamePath);

            // If remote host daemon is enabled, start the daemon to manage liveboard and inactivity auto-shutdown
            if (_configService.Config.EnableRemoteHostDaemon)
            {
                _remoteDaemon.ConfigureIdleAutoShutdown(_configService.Config.EnableIdleAutoShutdown, _configService.Config.IdleShutdownMinutes);
                await _remoteDaemon.StartDaemonAsync(
                    _configService.Config.RemoteManagementPort,
                    _configService.Config.RemoteAccessKey,
                    onStartServerRequested: async () =>
                    {
                        var cfg = _configService.Config;
                        cfg.LaunchMode = "Server";
                        cfg.LaunchServerWithGame = true;
                        var currentPath = _pathDetector.DetectPalworldInstallation(cfg.GamePath);
                        return await _launchService.LaunchGameAsync(cfg, currentPath);
                    },
                    onStopServerRequested: async () =>
                    {
                        return await _launchService.StopGameAsync();
                    });
            }

            // Initialize Discord Rich Presence if enabled
            if (_configService.Config.EnableDiscordRpc)
            {
                await _discordRpc.InitializeAsync(_configService.Config.DiscordApplicationId);
                await _discordRpc.UpdatePresenceAsync("In Launcher", "Preparing Expedition", isPlaying: false);
            }

            // Immediately detect and announce server status upon opening the launcher
            await RefreshServerStatusAsync();

            // Start background status polling loop
            _pollingCts?.Cancel();
            _pollingCts = new CancellationTokenSource();
            _ = StartServerStatusPollingLoopAsync(_pollingCts.Token);

            // Auto-check updates on startup if configured
            if (_configService.Config.AutoCheckUpdatesOnStartup)
            {
                await ExecuteQuickCheckUpdatesAsync();
            }
        }

        public async Task RefreshServerStatusAsync()
        {
            try
            {
                StatusText = "Detecting server status...";
                var liveboard = await _remoteClient.FetchLiveboardAsync(
                    _configService.Config.ServerIp,
                    _configService.Config.RemoteManagementPort,
                    timeoutMs: 1500);

                Application.Current?.Dispatcher.Invoke(() =>
                {
                    Liveboard = liveboard;
                    ServerStatus = new RemoteServerStatus
                    {
                        IsOnline = liveboard.IsOnline,
                        IsServerRunning = liveboard.IsServerRunning,
                        ServerPort = 8211,
                        UptimeSeconds = liveboard.UptimeSeconds,
                        ServerName = liveboard.ServerName
                    };

                    OnPropertyChanged(nameof(IsServerOnline));
                    OnPropertyChanged(nameof(ServerStatusBadgeText));

                    string displayHost = string.IsNullOrWhiteSpace(_configService.Config.ServerIp) ||
                                         _configService.Config.ServerIp == LauncherConfig.DirectHostEndpoint ||
                                         _configService.Config.ServerIp.Equals(LauncherConfig.OfficialServerHost, StringComparison.OrdinalIgnoreCase)
                                         ? "PalOdyssey Realm"
                                         : _configService.Config.ServerIp;

                    if (IsServerOnline)
                    {
                        StatusText = $"🟢 {displayHost} ONLINE — Ready to launch!";
                        _logService.LogSuccess($"Server status check: ONLINE ({displayHost})", "Network");
                    }
                    else
                    {
                        StatusText = $"⚪ {displayHost} Sleeping — Auto-wake ready on launch.";
                        _logService.LogInfo($"Server status check: OFFLINE/Sleeping ({displayHost}). Will start automatically on launch.", "Network");
                    }
                });
            }
            catch (Exception ex)
            {
                _logService.LogWarning($"Server status detection encountered: {ex.Message}", "Network");
            }
        }

        private async Task StartServerStatusPollingLoopAsync(CancellationToken ct)
        {
            while (!ct.IsCancellationRequested)
            {
                try
                {
                    ServerLiveboardInfo liveboard;
                    if (_launchService.IsServerRunning && _remoteDaemon.IsRunning)
                    {
                        liveboard = _remoteDaemon.GetCurrentLiveboard();
                    }
                    else
                    {
                        liveboard = await _remoteClient.FetchLiveboardAsync(
                            _configService.Config.ServerIp,
                            _configService.Config.RemoteManagementPort,
                            timeoutMs: 2000);
                    }

                    Application.Current?.Dispatcher.InvokeAsync(() =>
                    {
                        Liveboard = liveboard;
                        ServerStatus = new RemoteServerStatus
                        {
                            IsOnline = liveboard.IsOnline,
                            IsServerRunning = liveboard.IsServerRunning,
                            ServerPort = 8211,
                            UptimeSeconds = liveboard.UptimeSeconds,
                            ServerName = liveboard.ServerName
                        };
                        OnPropertyChanged(nameof(IsServerOnline));
                        OnPropertyChanged(nameof(ServerStatusBadgeText));
                    });
                }
                catch { }

                try
                {
                    await Task.Delay(3000, ct); // Liveboard refresh every 3s
                }
                catch (OperationCanceledException) { break; }
            }
        }

        private void OnProcessStateChanged(object? sender, GameProcessState state)
        {
            Application.Current?.Dispatcher.Invoke(() =>
            {
                IsGameRunning = state.IsRunning;
                if (state.IsRunning)
                {
                    StatusText = $"Palworld {state.Mode} is running (PID: {state.ProcessId})";
                    _ = _discordRpc.UpdatePresenceAsync("⚡ PalOdyssey Expedition", "Exploring Realm (Active Modpack)", isPlaying: true, targetPid: state.ProcessId);
                }
                else
                {
                    StatusText = "Palworld session ended. Ready to launch.";
                    ProgressPercentage = 0;
                    _ = _discordRpc.UpdatePresenceAsync("In Launcher", "Preparing Expedition", isPlaying: false, targetPid: Environment.ProcessId);
                }
            });
        }

        private async Task ExecuteLaunchOrStopAsync()
        {
            if (IsGameRunning)
            {
                StatusText = "Stopping game process...";
                await _launchService.StopGameAsync();
                return;
            }

            if (IsBusy) return;

            IsBusy = true;
            ProgressPercentage = 0;

            try
            {
                var config = SettingsVM.CreateConfigFromProperties();
                await _configService.SaveConfigAsync(config);

                StatusText = "Checking game installation path...";
                var pathInfo = _pathDetector.DetectPalworldInstallation(config.GamePath);

                if (!pathInfo.IsValid)
                {
                    StatusText = "Cannot launch: Palworld directory is not found. Please set your path in Settings.";
                    _logService.LogError("Game launch aborted. Valid Palworld executable not detected.", "Launcher");
                    ActiveView = "Settings";
                    return;
                }

                // If in Client mode and connecting to a remote host, send remote wake signal if server is not running
                bool isHostingLocally = config.LaunchMode.Equals("Server", StringComparison.OrdinalIgnoreCase)
                    || (config.LaunchServerWithGame && (config.ServerIp == "127.0.0.1" || config.ServerIp.Equals("localhost", StringComparison.OrdinalIgnoreCase)));

                if (!isHostingLocally && config.AutoRemoteWakeOnLaunch && !string.IsNullOrWhiteSpace(config.ServerIp))
                {
                    var currentServerStatus = await _remoteClient.QueryServerStatusAsync(config.ServerIp, config.RemoteManagementPort, 2000);
                    if (!currentServerStatus.IsServerRunning)
                    {
                        string targetDisplay = string.IsNullOrWhiteSpace(config.ServerIp) ||
                                               config.ServerIp == LauncherConfig.DirectHostEndpoint ||
                                               config.ServerIp.Equals(LauncherConfig.OfficialServerHost, StringComparison.OrdinalIgnoreCase)
                                               ? "PalOdyssey Realm"
                                               : config.ServerIp;
                        StatusText = $"Transmitting wake signal to {targetDisplay}...";
                        ProgressPercentage = 15;

                        var wakeProgress = new Progress<string>(msg =>
                        {
                            Application.Current?.Dispatcher.InvokeAsync(() =>
                            {
                                StatusText = msg;
                            });
                        });

                        await _remoteClient.RequestRemoteServerStartAsync(
                            config.ServerIp,
                            config.RemoteManagementPort,
                            config.RemoteAccessKey,
                            wakeProgress,
                            timeoutSeconds: 30);
                    }
                }

                // If auto-update before launch is enabled, check and update required mods
                if (config.AutoUpdateBeforeLaunch)
                {
                    StatusText = "Verifying core mod paks before launch...";
                    ProgressPercentage = 30;

                    var mods = await _updateService.CheckForUpdatesAsync(config.RemoteManifestUrl, pathInfo.GameRootPath);
                    var pendingMods = mods.FindAll(m => m.CanUpdate || !m.IsUpToDate);

                    if (pendingMods.Count > 0)
                    {
                        StatusText = $"Auto-updating {pendingMods.Count} outdated/missing mod paks...";
                        var progress = new Progress<UpdateProgressInfo>(p =>
                        {
                            Application.Current?.Dispatcher.InvokeAsync(() =>
                            {
                                StatusText = p.StatusMessage;
                                ProgressPercentage = 30 + (p.Percentage * 0.5); // 30% to 80%
                            });
                        });

                        int updated = await _updateService.DownloadAndInstallAllUpdatesAsync(pendingMods, pathInfo.GameRootPath, progress);
                        _logService.LogSuccess($"Auto-updated {updated} mods prior to launching.", "Launcher");
                    }
                    else
                    {
                        _logService.LogSuccess("All mod paks verified.", "Launcher");
                    }
                }

                ProgressPercentage = 90;
                StatusText = "Launching Palworld Client...";

                bool launched = await _launchService.LaunchGameAsync(config, pathInfo);
                if (launched)
                {
                    ProgressPercentage = 100;
                    StatusText = "Game launched successfully! Enjoy your expedition.";

                    if (config.CloseLauncherOnLaunch)
                    {
                        await Task.Delay(1500);
                        Application.Current?.Shutdown();
                    }
                }
                else
                {
                    StatusText = "Failed to launch game process. Check logs for details.";
                }
            }
            catch (Exception ex)
            {
                StatusText = $"Launch error: {ex.Message}";
                _logService.LogError("Launch execution failed with exception.", "Launcher", ex);
            }
            finally
            {
                IsBusy = false;
            }
        }

        public async Task ExecuteQuickCheckUpdatesAsync()
        {
            StatusText = "Synchronizing Realm: Checking for updates...";
            ProgressPercentage = 15;
            await ModsVM.ExecuteCheckUpdatesAsync();

            if (ModsVM.HasUpdatesPending)
            {
                int pendingCount = ModsVM.UpdatesAvailableCount + ModsVM.MissingCount;
                StatusText = $"Synchronizing Realm: Installing {pendingCount} missing/outdated mod(s)...";
                ProgressPercentage = 35;
                await ModsVM.ExecuteUpdateAllAsync();
                ProgressPercentage = 100;
                StatusText = $"Realm synchronized! {ModsVM.UpToDateCount} of {ModsVM.TotalModsCount} mods verified & ready.";
            }
            else
            {
                ProgressPercentage = 100;
                StatusText = "All realm mods are synchronized & up to date!";
            }
        }
    }
}
