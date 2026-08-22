using System;
using System.Windows;
using PalLauncher.Services;
using PalLauncher.Services.Interfaces;
using PalLauncher.ViewModels;
using PalLauncher.Views;

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

        protected override void OnStartup(StartupEventArgs e)
        {
            base.OnStartup(e);

            // Initialize Logging first
            _logService = new LogService();

            // Global exception handlers
            AppDomain.CurrentDomain.UnhandledException += (s, args) =>
            {
                _logService?.LogError("Unhandled AppDomain Exception", "System", args.ExceptionObject as Exception);
            };

            DispatcherUnhandledException += (s, args) =>
            {
                _logService?.LogError("Unhandled Dispatcher Exception", "System", args.Exception);
                args.Handled = true;
                MessageBox.Show($"An unexpected error occurred: {args.Exception.Message}", "PalLauncher Error", MessageBoxButton.OK, MessageBoxImage.Error);
                if (MainWindow == null || !MainWindow.IsVisible)
                {
                    Shutdown(1);
                }
            };

            try
            {
                // Initialize Services
                _configService = new ConfigService(_logService);
                _pathDetector = new GamePathDetector(_logService);
                _updateService = new UpdateService(_logService);
                _launchService = new LaunchService(_logService);
                var specService = new SystemSpecService(_logService);
                var remoteDaemon = new RemoteServerDaemon(_logService, _launchService);
                var remoteClient = new RemoteClientService(_logService);
                var discordRpc = new DiscordRpcService(_logService);

                // Initialize ViewModels & View
                _mainViewModel = new MainViewModel(_configService, _pathDetector, _updateService, _launchService, _logService, specService, remoteDaemon, remoteClient, discordRpc);

                var mainWindow = new MainWindow(_mainViewModel);
                MainWindow = mainWindow;
                mainWindow.Show();
            }
            catch (Exception ex)
            {
                _logService?.LogError("Fatal exception during startup", "System", ex);
                MessageBox.Show($"Failed to initialize launcher: {ex.Message}", "PalLauncher Startup Error", MessageBoxButton.OK, MessageBoxImage.Error);
                Shutdown(1);
            }
        }
    }
}
