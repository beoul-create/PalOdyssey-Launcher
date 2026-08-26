using System;
using System.IO;
using System.Text;
using System.Windows;
using PalLauncher.Services;
using PalLauncher.Services.Interfaces;
using PalLauncher.ViewModels;
using PalLauncher.Views;
using Application = System.Windows.Application;

namespace PalLauncher
{
    public partial class App : Application
    {
        private ILogService? _logService;
        private IConfigService? _configService;
        private IGamePathDetector? _pathDetector;
        private IUpdateService? _updateService;
        private ILaunchService? _launchService;
        private MainViewModel? _mainViewModel;
        private SingleInstanceManager? _singleInstance;
        private TrayIconService? _trayService;

        protected override void OnStartup(StartupEventArgs e)
        {
            // Setup global crash loggers immediately before anything else
            SetupStartupCrashHandlers();

            AppDomain.CurrentDomain.ProcessExit += (s, args) =>
            {
                CleanupResources();
            };

            base.OnStartup(e);

            // Initialize Logging service
            _logService = new LogService();

            try
            {
                // 0. Handle Direct Terminal CLI Commands (e.g. PalLauncher.exe --set-points <uid> <amount>)
                if (HandleTerminalCliCommands(e.Args))
                {
                    Environment.Exit(0);
                    return;
                }

                bool isHeadlessDaemon = Array.Exists(e.Args, a => a.Equals("--daemon", StringComparison.OrdinalIgnoreCase) ||
                                                                 a.Equals("--headless", StringComparison.OrdinalIgnoreCase) ||
                                                                 a.Equals("-silent", StringComparison.OrdinalIgnoreCase) ||
                                                                 a.Equals("/silent", StringComparison.OrdinalIgnoreCase));

                ShutdownMode = isHeadlessDaemon ? ShutdownMode.OnExplicitShutdown : ShutdownMode.OnMainWindowClose;

                // Enforce single instance separated between GUI Client and 24/7 Daemon
                _singleInstance = new SingleInstanceManager(_logService);
                if (!_singleInstance.TryAcquire(isDaemon: isHeadlessDaemon))
                {
                    if (!isHeadlessDaemon)
                    {
                        _logService.LogInfo("Existing PalLauncher GUI instance detected. Signaling running instance to focus window...", "App");
                        SingleInstanceManager.SignalExistingInstanceToShowWindow();
                    }
                    else
                    {
                        _logService.LogWarning("Existing PalLauncher Daemon instance already active. Exiting duplicate daemon process.", "App");
                    }

                    CleanupResources();
                    Environment.Exit(0);
                    return;
                }

                // Initialize Services
                _configService = new ConfigService(_logService);
                _pathDetector = new GamePathDetector(_logService);
                _updateService = new UpdateService(_logService);
                var crashLogService = new CrashLogService(_logService);
                _launchService = new LaunchService(_logService, crashLogService);
                var specService = new SystemSpecService(_logService);
                var remoteDaemon = new RemoteServerDaemon(_logService, _launchService, _configService);
                var remoteClient = new RemoteClientService(_logService);
                var discordRpc = new DiscordRpcService(_logService);
                var steamDetection = new SteamDetectionService(_logService);
                var discordAuth = new DiscordAuthService(_logService);

                // Initialize ViewModels & View
                _mainViewModel = new MainViewModel(
                    _configService,
                    _pathDetector,
                    _updateService,
                    _launchService,
                    _logService,
                    specService,
                    remoteDaemon,
                    remoteClient,
                    discordRpc,
                    crashLogService,
                    discordBot: null,
                    steamDetection: steamDetection,
                    discordAuth: discordAuth);

                if (isHeadlessDaemon)
                {
                    _logService.LogSuccess("PalLauncher started in Headless Background Host Daemon mode (24/7 Armed on port 8211).", "App");
                    _ = _mainViewModel.InitializeAsync();
                }
                else
                {
                    var mainWindow = new MainWindow(_mainViewModel);
                    MainWindow = mainWindow;

                    // Initialize System Tray Icon
                    _trayService = new TrayIconService(_logService);
                    _trayService.Initialize(
                        onRestoreRequested: () =>
                        {
                            Dispatcher.Invoke(() =>
                            {
                                if (MainWindow != null)
                                {
                                    if (_mainViewModel != null)
                                    {
                                        _mainViewModel.ActiveView = "Dashboard";
                                        _mainViewModel.RefreshSteamProfile();
                                        _mainViewModel.AccountLink = discordAuth.GetCurrentLinkInfo();
                                    }
                                    MainWindow.Show();
                                    MainWindow.WindowState = WindowState.Normal;
                                    MainWindow.ShowInTaskbar = true;
                                    MainWindow.Visibility = Visibility.Visible;
                                    MainWindow.Activate();
                                    MainWindow.Focus();
                                }
                            });
                        },
                        onRestartBotRequested: () =>
                        {
                            _ = _mainViewModel?.RestartDiscordBotAsync();
                        },
                        onExitRequested: () =>
                        {
                            Dispatcher.Invoke(() =>
                            {
                                CleanupResources();
                                _mainViewModel?.CloseCommand?.Execute("force");
                                Environment.Exit(0);
                            });
                        });

                    // Listen for restore signals from secondary instance launches
                    _singleInstance.StartListeningForShowSignal(() =>
                    {
                        Dispatcher.Invoke(() =>
                        {
                            if (MainWindow != null)
                            {
                                if (_mainViewModel != null)
                                {
                                    _mainViewModel.ActiveView = "Dashboard";
                                    _mainViewModel.RefreshSteamProfile();
                                    _mainViewModel.AccountLink = discordAuth.GetCurrentLinkInfo();
                                }
                                MainWindow.Show();
                                MainWindow.WindowState = WindowState.Normal;
                                MainWindow.ShowInTaskbar = true;
                                MainWindow.Visibility = Visibility.Visible;
                                MainWindow.Activate();
                                MainWindow.Focus();
                            }
                        });
                    });

                    // Intercept window close to minimize to system tray when background operation is active
                    mainWindow.Closing += (s, args) =>
                    {
                        if (_configService?.Config.RunInBackgroundOnClose == true)
                        {
                            args.Cancel = true;
                            mainWindow.Hide();
                            _trayService.ShowNotification(
                                "PalOdyssey Background Host Active",
                                "PalLauncher is running in the background. The Discord Bot (/start, /status) and Server Auto-Wake remain active 24/7.");
                            _logService.LogInfo("Launcher window minimized to System Tray. 24/7 Discord bot remains active.", "App");
                        }
                    };

                    mainWindow.Closed += (s, args) =>
                    {
                        CleanupResources();
                        Environment.Exit(0);
                    };

                    mainWindow.Show();
                    mainWindow.Activate();
                    mainWindow.Focus();
                }
            }
            catch (Exception ex)
            {
                RecordFatalCrash(ex, "App.OnStartup");
                _logService?.LogError("Fatal exception during startup", "System", ex);
                MessageBox.Show($"Failed to initialize launcher: {ex.Message}\n\nDetails written to launcher-startup-crash.log", "PalLauncher Startup Error", MessageBoxButton.OK, MessageBoxImage.Error);
                CleanupResources();
                Environment.Exit(1);
            }
        }

        private void SetupStartupCrashHandlers()
        {
            AppDomain.CurrentDomain.UnhandledException += (s, args) =>
            {
                var ex = args.ExceptionObject as Exception ?? new Exception($"Unhandled non-exception object: {args.ExceptionObject}");
                RecordFatalCrash(ex, "AppDomain.UnhandledException");
                _logService?.LogError("Unhandled AppDomain Exception", "System", ex);
                CleanupResources();
            };

            DispatcherUnhandledException += (s, args) =>
            {
                RecordFatalCrash(args.Exception, "DispatcherUnhandledException");
                _logService?.LogError($"Unhandled Dispatcher Exception: {args.Exception.Message}", "System", args.Exception);
                args.Handled = true;
                if (MainWindow == null || !MainWindow.IsVisible)
                {
                    CleanupResources();
                    Environment.Exit(1);
                }
            };
        }

        private static void RecordFatalCrash(Exception ex, string source)
        {
            try
            {
                var sb = new StringBuilder();
                sb.AppendLine("================================================================================");
                sb.AppendLine($"  PALODYSSEY LAUNCHER FATAL STARTUP CRASH REPORT - {DateTime.UtcNow:u}");
                sb.AppendLine("================================================================================");
                sb.AppendLine($"Source: {source}");
                sb.AppendLine($"Exception Type: {ex.GetType().FullName}");
                sb.AppendLine($"Message: {ex.Message}");
                sb.AppendLine($"Stack Trace:\n{ex.StackTrace}");
                if (ex.InnerException != null)
                {
                    sb.AppendLine($"Inner Exception: {ex.InnerException.GetType().FullName}: {ex.InnerException.Message}");
                    sb.AppendLine($"Inner Stack Trace:\n{ex.InnerException.StackTrace}");
                }
                sb.AppendLine();

                string content = sb.ToString();

                // 1. Write to BaseDirectory
                try
                {
                    string localCrashLog = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "launcher-startup-crash.log");
                    File.AppendAllText(localCrashLog, content);
                }
                catch { }

                // 2. Write to AppData directory
                try
                {
                    string appDataDir = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "PalLauncher");
                    if (!Directory.Exists(appDataDir)) Directory.CreateDirectory(appDataDir);
                    string appDataCrashLog = Path.Combine(appDataDir, "launcher-startup-crash.log");
                    File.AppendAllText(appDataCrashLog, content);
                }
                catch { }
            }
            catch { }
        }

        [System.Runtime.InteropServices.DllImport("kernel32.dll")]
        private static extern bool AttachConsole(int dwProcessId);

        private bool HandleTerminalCliCommands(string[] args)
        {
            if (args == null || args.Length == 0) return false;

            string first = args[0].ToLowerInvariant().Trim();
            if (first == "--set-points" || first == "-set-points" || first == "setpoints" || first == "set-points" ||
                first == "--grant-points" || first == "-grant-points" || first == "grantpoints" || first == "grant-points" || first == "addpoints" ||
                first == "--get-points" || first == "-get-points" || first == "getpoints" || first == "get-points")
            {
                AttachConsole(-1);
            }

            if (first == "--set-points" || first == "-set-points" || first == "setpoints" || first == "set-points")
            {
                if (args.Length < 3)
                {
                    Console.WriteLine("Usage: PalLauncher.exe --set-points <player_uid_or_steamid> <points> [currency]");
                    return true;
                }
                string uid = args[1];
                if (!int.TryParse(args[2], out int pts))
                {
                    Console.WriteLine($"Error: '{args[2]}' is not a valid integer amount.");
                    return true;
                }
                string currency = args.Length >= 4 ? args[3] : "tech_points";

                var saveService = new PalSaveService(_logService!);
                var economy = new EconomyService(_logService!, saveService);
                var presence = new PlayerPresenceService(new ConfigService(_logService!), _logService!);

                bool isOnline = presence.IsPlayerOnlineAsync(uid).GetAwaiter().GetResult();
                var receipt = economy.SetPlayerTechnologyPointsAsync(uid, pts, currency, isOnline).GetAwaiter().GetResult();

                Console.WriteLine(receipt.Success
                    ? $"[SUCCESS] Set {receipt.Currency} for {receipt.PlayerName} ({receipt.PlayerUid}) to {receipt.NewPoints} pts."
                    : $"[ERROR] {receipt.Message}");
                return true;
            }

            if (first == "--grant-points" || first == "-grant-points" || first == "grantpoints" || first == "grant-points" || first == "addpoints")
            {
                if (args.Length < 3)
                {
                    Console.WriteLine("Usage: PalLauncher.exe --grant-points <player_uid_or_steamid> <points> [currency]");
                    return true;
                }
                string uid = args[1];
                if (!int.TryParse(args[2], out int pts))
                {
                    Console.WriteLine($"Error: '{args[2]}' is not a valid integer amount.");
                    return true;
                }
                string currency = args.Length >= 4 ? args[3] : "tech_points";

                var saveService = new PalSaveService(_logService!);
                var economy = new EconomyService(_logService!, saveService);
                var presence = new PlayerPresenceService(new ConfigService(_logService!), _logService!);

                bool isOnline = presence.IsPlayerOnlineAsync(uid).GetAwaiter().GetResult();
                var receipt = economy.GrantPlayerTechnologyPointsAsync(uid, pts, currency, isOnline).GetAwaiter().GetResult();

                Console.WriteLine(receipt.Success
                    ? $"[SUCCESS] Granted {pts:+0;-0;0} {receipt.Currency} to {receipt.PlayerName} ({receipt.PlayerUid}). New Balance: {receipt.NewPoints} pts."
                    : $"[ERROR] {receipt.Message}");
                return true;
            }

            if (first == "--get-points" || first == "-get-points" || first == "getpoints" || first == "get-points")
            {
                if (args.Length < 2)
                {
                    Console.WriteLine("Usage: PalLauncher.exe --get-points <player_uid_or_steamid>");
                    return true;
                }
                string uid = args[1];
                var saveService = new PalSaveService(_logService!);
                var economy = new EconomyService(_logService!, saveService);

                var profile = economy.GetPlayerProfileAsync(uid, forceLiveRefresh: true).GetAwaiter().GetResult();
                if (profile != null)
                {
                    Console.WriteLine($"Pioneer: {profile.PlayerName} (Lv. {profile.Level}) | UID: {profile.PlayerUid}");
                    Console.WriteLine($"Technology Points: {profile.TechnologyPoints} pts");
                    Console.WriteLine($"Ancient Boss Points: {profile.BossTechnologyPoints} pts");
                }
                else
                {
                    Console.WriteLine($"[ERROR] Could not find player save for '{uid}'.");
                }
                return true;
            }

            return false;
        }

        private void CleanupResources()
        {
            try { _trayService?.Dispose(); } catch { }
            try { _singleInstance?.Dispose(); } catch { }
        }

        protected override void OnExit(ExitEventArgs e)
        {
            CleanupResources();
            base.OnExit(e);
            Environment.Exit(0);
        }
    }
}
