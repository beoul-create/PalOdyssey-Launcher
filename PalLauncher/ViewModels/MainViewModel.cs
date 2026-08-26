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
        public bool CanLaunch => !IsGameRunning && !IsBusy;
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
                    OnPropertyChanged(nameof(CanLaunch));
                    LaunchGameCommand.RaiseCanExecuteChanged();
                }
            }
        }

        public string GameStatusBadge
        {
            get
            {
                if (IsGameRunning) return "Game Running";
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
                if (IsGameRunning) return "Game is running";
                if (IsBusy) return "STARTING GAME...";
                return "LAUNCH GAME";
            }
        }

        public ModsViewModel ModsVM { get; }
        public SettingsViewModel SettingsVM { get; }
        public LogsViewModel LogsVM { get; }

        public RelayCommand NavigateCommand { get; }
        public AsyncRelayCommand LaunchGameCommand { get; }
        public AsyncRelayCommand QuickCheckUpdatesCommand { get; }
        public AsyncRelayCommand RefreshServerStatusCommand { get; }
        public RelayCommand CopyServerIpCommand { get; }
        public RelayCommand MinimizeCommand { get; }
        public RelayCommand MaximizeCommand { get; }
        public RelayCommand CloseCommand { get; }
        private readonly ISystemSpecService _specService;
        private readonly IRemoteServerDaemon _remoteDaemon;
        private readonly IRemoteClientService _remoteClient;
        private readonly IDiscordRpcService _discordRpc;
        private readonly IDiscordBotService _discordBot;
        private readonly ISteamDetectionService _steamDetection;
        private readonly ISteamAuthService _steamAuth;
        private readonly IDiscordAuthService _discordAuth;

        private RemoteServerStatus _serverStatus = new();
        private ServerLiveboardInfo _liveboard = new();
        private SteamProfileInfo _steamProfile = new();
        private AccountLinkInfo _accountLink = new();
        private bool _isConnectingSteam;
        private bool _isConnectingDiscord;
        private CancellationTokenSource? _pollingCts;
        private System.Windows.Threading.DispatcherTimer? _uptimeTimer;

        public SteamProfileInfo SteamProfile
        {
            get => _steamProfile;
            set
            {
                if (SetProperty(ref _steamProfile, value))
                {
                    OnPropertyChanged(nameof(SteamBadge));
                }
            }
        }

        public AccountLinkInfo AccountLink
        {
            get => _accountLink;
            set
            {
                if (SetProperty(ref _accountLink, value))
                {
                    OnPropertyChanged(nameof(IsDiscordLinked));
                    OnPropertyChanged(nameof(DiscordLinkBadge));
                }
            }
        }

        public bool IsConnectingSteam
        {
            get => _isConnectingSteam;
            set => SetProperty(ref _isConnectingSteam, value);
        }

        public bool IsConnectingDiscord
        {
            get => _isConnectingDiscord;
            set => SetProperty(ref _isConnectingDiscord, value);
        }

        public bool IsDiscordLinked => AccountLink?.IsLinked == true;
        public string DiscordLinkBadge => IsDiscordLinked ? $"🟢 Discord Linked: @{AccountLink.DiscordUsername}" : "⚪ Connect Discord";
        public string SteamBadge => SteamProfile?.IsDetected == true ? $"🎮 {SteamProfile.PersonaName} ({SteamProfile.SteamId64})" : "🎮 Steam Offline";

        public AsyncRelayCommand ConnectDiscordCommand { get; }
        public AsyncRelayCommand ConnectSteamCommand { get; }
        public RelayCommand UnlinkDiscordCommand { get; }
        public RelayCommand RefreshSteamCommand { get; }

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
            ICrashLogService? crashLogService = null,
            IDiscordBotService? discordBot = null,
            ISteamDetectionService? steamDetection = null,
            ISteamAuthService? steamAuth = null,
            IDiscordAuthService? discordAuth = null)
        {
            _configService = configService;
            _pathDetector = pathDetector;
            _updateService = updateService;
            _launchService = launchService;
            _logService = logService;
            _specService = specService ?? new SystemSpecService(_logService);
            _remoteDaemon = remoteDaemon ?? new RemoteServerDaemon(_logService, _launchService, _configService);
            _remoteClient = remoteClient ?? new RemoteClientService(_logService);
            _discordRpc = discordRpc ?? new DiscordRpcService(_logService);
            
            var presenceService = new PlayerPresenceService(_configService, _logService);
            _discordBot = discordBot ?? new DiscordBotService(_logService, null, presenceService);
            
            _steamDetection = steamDetection ?? new SteamDetectionService(_logService);
            _steamAuth = steamAuth ?? new SteamAuthService(_logService);
            _discordAuth = discordAuth ?? new DiscordAuthService(_logService);

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

            SettingsVM.SettingsSaved += async (s, e) =>
            {
                ConfigureWindowsStartup(_configService.Config.AutoStartWithWindows, _logService);
                await RestartDiscordBotAsync();
                await RestartDiscordRpcAsync();
            };

            SettingsVM.DiscordBotRestartRequested += async (s, e) =>
            {
                await RestartDiscordBotAsync();
                await RestartDiscordRpcAsync();
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
            CopyServerIpCommand = new RelayCommand(_ => ExecuteCopyServerIp());
            ConnectDiscordCommand = new AsyncRelayCommand(ExecuteConnectDiscordAsync);
            ConnectSteamCommand = new AsyncRelayCommand(ExecuteConnectSteamAsync);
            UnlinkDiscordCommand = new RelayCommand(_ => ExecuteUnlinkDiscord());
            RefreshSteamCommand = new RelayCommand(_ => RefreshSteamProfile());

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
                if (Liveboard != null && (IsServerOnline || Liveboard.IsServerRunning))
                {
                    if (Liveboard.IsServerRunning)
                    {
                        Liveboard.UptimeSeconds += 1;
                        if (Liveboard.IsIdleCountingDown && Liveboard.IdleSecondsRemaining > 0)
                        {
                            Liveboard.IdleSecondsRemaining--;
                            Liveboard.IdleMinutesRemaining = (int)Math.Ceiling(Liveboard.IdleSecondsRemaining / 60.0);
                        }
                    }
                    OnPropertyChanged(nameof(Liveboard));
                }
            };
            _uptimeTimer.Start();

            CloseCommand = new RelayCommand(param =>
            {
                bool forceExit = param is string s && s.Equals("force", StringComparison.OrdinalIgnoreCase);
                bool keepAlive = _configService.Config.RunInBackgroundOnClose &&
                                 (_configService.Config.EnableDiscordBot || _configService.Config.EnableRemoteHostDaemon || _launchService.IsServerRunning);

                if (keepAlive && !forceExit)
                {
                    if (Application.Current?.MainWindow != null)
                    {
                        Application.Current.MainWindow.Hide();
                        _logService.LogInfo("Launcher minimized to background tray. Discord bot and server host daemon remain active.", "App");
                    }
                }
                else
                {
                    _uptimeTimer?.Stop();
                    _pollingCts?.Cancel();
                    _remoteDaemon.Dispose();
                    _discordRpc.Dispose();
                    _discordBot.Dispose();
                    Application.Current?.Shutdown();
                }
            });

            _launchService.ProcessStateChanged += OnProcessStateChanged;
        }

        public static void ConfigureWindowsStartup(bool enable, ILogService? logService = null)
        {
            try
            {
                using var key = Microsoft.Win32.Registry.CurrentUser.OpenSubKey(@"Software\Microsoft\Windows\CurrentVersion\Run", true);
                if (key != null)
                {
                    string appExe = System.Diagnostics.Process.GetCurrentProcess().MainModule?.FileName ?? @"c:\PalOddessey\PalLauncher.exe";
                    if (enable)
                    {
                        key.SetValue("PalOdysseyHostDaemon", $"\"{appExe}\" --daemon");
                        logService?.LogSuccess("Configured PalOdyssey Background Host to auto-start with Windows.", "System");
                    }
                    else
                    {
                        key.DeleteValue("PalOdysseyHostDaemon", false);
                    }
                }
            }
            catch (Exception ex)
            {
                logService?.LogWarning($"Could not update Windows startup registry: {ex.Message}", "System");
            }
        }

        private bool _isInitialized;

        public async Task InitializeAsync()
        {
            if (_isInitialized) return;
            _isInitialized = true;

            await _configService.LoadConfigAsync();
            SettingsVM.LoadFromConfig(_configService.Config);

            if (_configService.Config.AutoStartWithWindows)
            {
                ConfigureWindowsStartup(true, _logService);
            }

            var pathInfo = _pathDetector.DetectPalworldInstallation(_configService.Config.GamePath);

            // Auto-detect local active Steam profile & load cached Discord link
            RefreshSteamProfile();
            AccountLink = _discordAuth.GetCurrentLinkInfo();

            // Always start Remote Host Daemon when enabled to support remote webhook start triggers and Discord commands independently of server state
            if (_configService.Config.EnableRemoteHostDaemon)
            {
                _remoteDaemon.ConfigureIdleAutoShutdown(_configService.Config.EnableIdleAutoShutdown, _configService.Config.IdleShutdownMinutes);
                await _remoteDaemon.StartDaemonAsync(
                    _configService.Config.RemoteManagementPort,
                    _configService.Config.RemoteAccessKey,
                    onStartServerRequested: async () =>
                    {
                        var cfg = _configService.Config;
                        var currentPath = _pathDetector.DetectPalworldInstallation(cfg.GamePath);
                        return await _launchService.StartServerOnlyAsync(cfg, currentPath);
                    },
                    onStopServerRequested: async () =>
                    {
                        return await _launchService.StopServerOnlyAsync();
                    },
                    onWebhookServerBooting: async (source) =>
                    {
                        if (_discordBot.IsRunning)
                        {
                            await _discordBot.BroadcastServerBootingAsync(source);
                        }
                    });
            }

            // Initialize Discord Bot Service unconditionally if enabled
            await RestartDiscordBotAsync();

            // Initialize Discord Rich Presence if enabled
            await RestartDiscordRpcAsync();

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
                IsGameRunning = state.IsClientRunning; // Button state strictly tracks the game client!
                if (state.IsClientRunning)
                {
                    StatusText = $"Palworld Game is running (PID: {state.ProcessId})";
                    _ = _discordRpc.UpdatePresenceAsync("⚡ PalOdyssey Expedition", "Exploring Realm (Active Modpack)", isPlaying: true, targetPid: state.ProcessId);
                }
                else if (state.IsServerRunning)
                {
                    StatusText = "🟢 PalOdyssey Dedicated Server is active. Ready to launch game!";
                    ProgressPercentage = 0;
                    _ = _discordRpc.UpdatePresenceAsync("In Launcher", "Ready to Launch", isPlaying: false, targetPid: Environment.ProcessId);
                }
                else
                {
                    StatusText = "Ready to launch.";
                    ProgressPercentage = 0;
                    _ = _discordRpc.UpdatePresenceAsync("In Launcher", "Preparing Expedition", isPlaying: false, targetPid: Environment.ProcessId);
                }
            });
        }

        private async Task ExecuteLaunchOrStopAsync()
        {
            if (IsGameRunning)
            {
                StatusText = "Palworld game is already running.";
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

                // Automatically copy server connection endpoint to clipboard for effortless paste in Multiplayer
                try
                {
                    string ipToCopy = string.IsNullOrWhiteSpace(config.ServerIp)
                        ? "palodyssey.duckdns.org:8211"
                        : $"{config.ServerIp}:{config.ServerPort}";

                    Application.Current?.Dispatcher.Invoke(() =>
                    {
                        Clipboard.SetDataObject(ipToCopy, true);
                    });
                    _logService.LogSuccess($"Server connection IP '{ipToCopy}' automatically copied to clipboard for 1-click paste in Multiplayer.", "Launcher");
                }
                catch { }

                ProgressPercentage = 90;
                StatusText = "Launching Palworld Client with Steam integration...";

                bool launched = await _launchService.LaunchGameAsync(config, pathInfo);
                if (launched)
                {
                    ProgressPercentage = 100;
                    StatusText = "🎮 Palworld launched! Server IP copied to clipboard (Paste into Multiplayer).";

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

        private void ExecuteCopyServerIp()
        {
            try
            {
                string ip = string.IsNullOrWhiteSpace(_configService.Config.ServerIp)
                    ? "palodyssey.duckdns.org:8211"
                    : $"{_configService.Config.ServerIp}:{_configService.Config.ServerPort}";

                Application.Current?.Dispatcher.Invoke(() =>
                {
                    Clipboard.SetDataObject(ip, true);
                });

                StatusText = $"📋 Server IP '{ip}' copied to clipboard! (Paste in Multiplayer)";
                _logService.LogSuccess($"Server IP '{ip}' copied to clipboard.", "Launcher");
            }
            catch (Exception ex)
            {
                StatusText = $"Failed to copy server IP: {ex.Message}";
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

        public async Task RestartDiscordBotAsync()
        {
            try
            {
                await _discordBot.StopAsync();

                if (!_configService.Config.EnableDiscordBot)
                {
                    _logService.LogInfo("Discord Bot is disabled in configuration.", "DiscordBot");
                    return;
                }

                string botToken = _configService.Config.DiscordBotToken;
                if (string.IsNullOrWhiteSpace(botToken))
                {
                    string appDataToken = System.IO.Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "PalLauncher", "bot_token.txt");
                    string baseDirToken = System.IO.Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "bot_token.txt");
                    if (System.IO.File.Exists(appDataToken))
                    {
                        try { botToken = System.IO.File.ReadAllText(appDataToken).Trim(); } catch { }
                    }
                    else if (System.IO.File.Exists(baseDirToken))
                    {
                        try { botToken = System.IO.File.ReadAllText(baseDirToken).Trim(); } catch { }
                    }
                }

                if (string.IsNullOrWhiteSpace(botToken))
                {
                    _logService.LogWarning("Discord Bot token is empty. Bot will not start.", "DiscordBot");
                    return;
                }

                await _discordBot.StartAsync(
                    botToken,
                    _configService.Config.DiscordCommandPrefix,
                    _configService.Config.DiscordBotChannelId,
                    _configService.Config.DiscordAdminRoleId,
                    onStartServer: async () =>
                    {
                        var cfg = _configService.Config;
                        var currentPath = _pathDetector.DetectPalworldInstallation(cfg.GamePath);
                        return await _launchService.StartServerOnlyAsync(cfg, currentPath);
                    },
                    onStopServer: async () =>
                    {
                        return await _launchService.StopServerOnlyAsync();
                    },
                    getLiveboard: () =>
                    {
                        if (_launchService.IsServerRunning)
                        {
                            var current = _remoteDaemon.IsRunning ? _remoteDaemon.GetCurrentLiveboard() : Liveboard;
                            if (current != null)
                            {
                                current.IsOnline = true;
                                current.IsServerRunning = true;
                                return current;
                            }
                        }
                        return Liveboard ?? new ServerLiveboardInfo();
                    });
            }
            catch (Exception ex)
            {
                _logService.LogError("Failed to restart Discord Bot service", "DiscordBot", ex);
            }
        }

        public async Task RestartDiscordRpcAsync()
        {
            try
            {
                if (_configService.Config.EnableDiscordRpc)
                {
                    await _discordRpc.InitializeAsync(_configService.Config.DiscordApplicationId);

                    bool isDedicatedServerMode = _configService.Config.LaunchMode.Equals("Server", StringComparison.OrdinalIgnoreCase);
                    if (isDedicatedServerMode)
                    {
                        await _discordRpc.UpdatePresenceAsync(
                            "PalOdyssey Dedicated Server",
                            "Hosting Realm (Port 8211)",
                            isPlaying: true,
                            targetPid: Environment.ProcessId);
                    }
                    else if (IsGameRunning)
                    {
                        await _discordRpc.UpdatePresenceAsync(
                            "⚡ PalOdyssey Expedition",
                            "Exploring Realm (Active Modpack)",
                            isPlaying: true);
                    }
                    else
                    {
                        await _discordRpc.UpdatePresenceAsync(
                            "In Launcher",
                            "Preparing Expedition",
                            isPlaying: false,
                            targetPid: Environment.ProcessId);
                    }
                }
                else
                {
                    await _discordRpc.ClearPresenceAsync();
                }
            }
            catch (Exception ex)
            {
                _logService.LogWarning($"Failed to restart Discord RPC service: {ex.Message}", "DiscordRPC");
            }
        }

        public void RefreshSteamProfile()
        {
            try
            {
                SteamProfile = _steamDetection.DetectActiveSteamUser();
                _logService.LogInfo($"Steam Profile refreshed: {SteamBadge}", "Steam");
            }
            catch (Exception ex)
            {
                _logService.LogWarning($"Steam detection error: {ex.Message}", "Steam");
            }
        }

        public async Task ExecuteConnectSteamAsync()
        {
            if (IsConnectingSteam) return;

            try
            {
                IsConnectingSteam = true;
                StatusText = "Connecting Steam: Opening OpenID authorization page in browser...";
                _logService.LogInfo("Initiating Steam OpenID authorization flow...", "SteamAuth");

                var steamProfile = await _steamAuth.InitiateSteamLoginAsync(localPort: 8766);
                
                if (steamProfile.IsDetected)
                {
                    SteamProfile = steamProfile;
                    StatusText = $"🎉 Connected Steam successfully! Welcome, Pioneer (ID: {steamProfile.SteamId64}).";
                }
                else
                {
                    StatusText = "Steam connection was not completed.";
                }
            }
            catch (Exception ex)
            {
                StatusText = $"Steam connection error: {ex.Message}";
                _logService.LogError("Steam OpenID linking failed", "SteamAuth", ex);
            }
            finally
            {
                IsConnectingSteam = false;
            }
        }

        public async Task ExecuteConnectDiscordAsync()
        {
            if (IsConnectingDiscord) return;

            try
            {
                IsConnectingDiscord = true;
                StatusText = "Connecting Discord: Opening authorization page in browser...";
                _logService.LogInfo("Initiating Discord OAuth2 authorization flow...", "DiscordAuth");

                if (!SteamProfile.IsDetected)
                {
                    RefreshSteamProfile();
                }

                var link = await _discordAuth.InitiateDiscordLinkAsync(SteamProfile, localPort: 8765);
                AccountLink = link;

                if (link.IsLinked)
                {
                    StatusText = $"🎉 Connected Discord @{link.DiscordUsername} ⇄ Steam {link.SteamPersonaName}!";
                    _logService.LogSuccess($"Account Linked: Discord @{link.DiscordUsername} ({link.DiscordId}) ⇄ Steam {link.SteamPersonaName} ({link.SteamId64})", "DiscordAuth");

                    await _discordAuth.PushAccountLinkToDaemonAsync(link, _configService.Config.RemoteManagementPort);
                }
                else
                {
                    StatusText = "Discord connection was not completed.";
                }
            }
            catch (Exception ex)
            {
                StatusText = $"Discord connection error: {ex.Message}";
                _logService.LogError("Discord OAuth linking failed", "DiscordAuth", ex);
            }
            finally
            {
                IsConnectingDiscord = false;
            }
        }

        public void ExecuteUnlinkDiscord()
        {
            _discordAuth.ClearLinkInfo();
            AccountLink = new AccountLinkInfo();
            StatusText = "Discord account unlinked.";
            _logService.LogInfo("Discord account unlinked from launcher.", "DiscordAuth");
        }
    }
}
