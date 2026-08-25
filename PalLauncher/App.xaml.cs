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
                    if (_configService?.Config.RunInBackgroundOnClose == true && isHeadlessDaemon)
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
                    if (!isHeadlessDaemon)
                    {
                        CleanupResources();
                        Environment.Exit(0);
                    }
                };

                if (isHeadlessDaemon)
                {
                    mainWindow.WindowState = WindowState.Minimized;
                    mainWindow.ShowInTaskbar = false;
                    mainWindow.Visibility = Visibility.Hidden;
                    _logService.LogSuccess("PalLauncher started in Headless Background Host Daemon mode (24/7 Armed on port 8211).", "App");
                    _ = _mainViewModel.InitializeAsync();
                }
                else
                {
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
