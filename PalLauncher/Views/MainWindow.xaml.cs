using System;
using System.IO;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Threading;
using Microsoft.Win32;
using PalLauncher.Models;
using PalLauncher.Services;
using PalLauncher.ViewModels;

namespace PalLauncher.Views
{
    public partial class MainWindow : Window
    {
        private string? _detectedServerPath;
        private GameProcessService _gameProcessService = null!;
        private RemoteServerService _remoteServerService = null!;
        private LauncherConfig _config = null!;
        private DispatcherTimer? _serverPollTimer;
        private ServerStatusResponse? _lastRemoteStatus;
        private bool _isActionInProgress;
        private bool _isPollingServer;
        private bool _isGameRunning;

        public MainWindow()
        {
            InitializeComponent();
            Loaded += MainWindow_Loaded;
            Closing += MainWindow_Closing;
            StateChanged += MainWindow_StateChanged;
            IsVisibleChanged += (_, _) => UpdateBackgroundActivity();
        }

        private void MainWindow_Loaded(object sender, RoutedEventArgs e)
        {
            if (DataContext is MainViewModel vm)
            {
                _gameProcessService = vm.GameProcessService;
                _remoteServerService = vm.RemoteServerService;
                _config = vm.Config;
            }
            else
            {
                _gameProcessService = new GameProcessService();
                _remoteServerService = new RemoteServerService();
                _config = LauncherConfig.Load();
            }

            InitializeServerManagement();
            _gameProcessService.GameStarted += OnGameStarted;
            _gameProcessService.GameExited += OnGameExited;

            try
            {
                string videoPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "Assets", "background_loop.mp4");
                if (File.Exists(videoPath))
                {
                    BackgroundVideo.Source = new Uri(videoPath, UriKind.Absolute);
                    BackgroundVideo.Play();
                }
            }
            catch (Exception)
            {
                // Fallback gradient remains visible
            }
        }

        private void InitializeServerManagement()
        {
            _detectedServerPath = _gameProcessService.DetectServerPath(_config.ServerInstallPath);
            _gameProcessService.ServerStateChanged += OnServerStateChanged;

            // Start 4-second polling timer for remote server daemon status
            _serverPollTimer = new DispatcherTimer
            {
                Interval = TimeSpan.FromSeconds(4)
            };
            _serverPollTimer.Tick += async (_, _) => await PollServerStatusAsync();
            _serverPollTimer.Start();

            // Initial poll
            _ = PollServerStatusAsync();
        }

        private async Task PollServerStatusAsync()
        {
            if (_isActionInProgress || _isPollingServer) return;
            _isPollingServer = true;

            try
            {
                if (!string.IsNullOrWhiteSpace(_config.RemoteServerApiUrl))
                {
                    _lastRemoteStatus = await _remoteServerService.GetRemoteStatusAsync(_config.RemoteServerApiUrl);
                }

                UpdateServerUIState(_gameProcessService.IsServerRunning, _lastRemoteStatus);
            }
            finally
            {
                _isPollingServer = false;
            }
        }

        [System.Runtime.InteropServices.DllImport("psapi.dll")]
        private static extern int EmptyWorkingSet(IntPtr hwProc);

        private void OnGameStarted()
        {
            Dispatcher.BeginInvoke(() =>
            {
                _isGameRunning = true;
                if (_config.CloseLauncherOnStart)
                {
                    Application.Current?.Shutdown();
                    return;
                }

                WindowState = WindowState.Minimized;
                UpdateBackgroundActivity();

                try
                {
                    GC.Collect();
                    GC.WaitForPendingFinalizers();
                    EmptyWorkingSet(System.Diagnostics.Process.GetCurrentProcess().Handle);
                }
                catch { }
            });
        }

        private void OnGameExited()
        {
            Dispatcher.BeginInvoke(() =>
            {
                _isGameRunning = false;
                WindowState = WindowState.Normal;
                UpdateBackgroundActivity();
                _ = PollServerStatusAsync();
            });
        }

        private void MainWindow_StateChanged(object? sender, EventArgs e) => UpdateBackgroundActivity();

        private void UpdateBackgroundActivity()
        {
            bool shouldRun = !_isGameRunning && WindowState != WindowState.Minimized && IsVisible;
            if (DataContext is MainViewModel vm)
            {
                if (shouldRun && vm.IsSoundEnabled)
                {
                    vm.AudioService.StartBgm();
                }
                else
                {
                    vm.AudioService.StopBgm();
                }
            }

            if (shouldRun)
            {
                BackgroundVideo.Play();
                _serverPollTimer?.Start();
            }
            else
            {
                BackgroundVideo.Pause();
                _serverPollTimer?.Stop();

                try
                {
                    GC.Collect();
                    EmptyWorkingSet(System.Diagnostics.Process.GetCurrentProcess().Handle);
                }
                catch { }
            }
        }

        private void OnServerStateChanged(bool isRunning)
        {
            Dispatcher.Invoke(() => UpdateServerUIState(isRunning, _lastRemoteStatus));
        }

        private void UpdateServerUIState(bool isLocalRunning, ServerStatusResponse? remoteStatus)
        {
            bool isOnline = isLocalRunning || (remoteStatus != null && (remoteStatus.ServerOnline || remoteStatus.IsProcessRunning));

            if (isOnline)
            {
                ServerStatusIndicator.Fill = new SolidColorBrush((Color)ColorConverter.ConvertFromString("#10B981")); // Emerald
                ServerStatusText.Text = "ONLINE";
                ServerStatusText.Foreground = new SolidColorBrush((Color)ColorConverter.ConvertFromString("#10B981"));

                if (remoteStatus != null && remoteStatus.Success)
                {
                    ServerDetailText.Text = $"Remote Daemon Connected • {remoteStatus.PlayerCount}/{remoteStatus.MaxPlayers} Players";
                }
                else
                {
                    ServerDetailText.Text = "Local Server Process Active (Port: 8211)";
                }

                BtnServerToggle.Content = "Stop Server";
                BtnServerToggle.Background = new SolidColorBrush((Color)ColorConverter.ConvertFromString("#EF4444")); // Red
                BtnServerToggle.IsEnabled = true;
                BtnSelectServerPath.Visibility = Visibility.Collapsed;
            }
            else
            {
                ServerStatusIndicator.Fill = new SolidColorBrush((Color)ColorConverter.ConvertFromString("#EF4444")); // Crimson
                ServerStatusText.Text = "OFFLINE";
                ServerStatusText.Foreground = new SolidColorBrush((Color)ColorConverter.ConvertFromString("#EF4444"));
                ServerDetailText.Text = "Remote Controller Active";
                BtnServerToggle.Content = "Start Server";
                BtnServerToggle.Background = new SolidColorBrush((Color)ColorConverter.ConvertFromString("#0284C7")); // Blue

                if (string.IsNullOrEmpty(_detectedServerPath) && string.IsNullOrEmpty(_config.RemoteServerApiUrl))
                {
                    BtnServerToggle.IsEnabled = false;
                    BtnSelectServerPath.Visibility = Visibility.Visible;
                }
                else
                {
                    BtnServerToggle.IsEnabled = true;
                    BtnSelectServerPath.Visibility = Visibility.Collapsed;
                }
            }
        }

        private async void BtnServerToggle_Click(object sender, RoutedEventArgs e)
        {
            if (DataContext is MainViewModel vm)
            {
                vm.ClickSoundCommand.Execute(null);
            }

            if (_isActionInProgress) return;
            _isActionInProgress = true;
            BtnServerToggle.IsEnabled = false;

            bool isCurrentlyOnline = _gameProcessService.IsServerRunning ||
                                    (_lastRemoteStatus != null && (_lastRemoteStatus.ServerOnline || _lastRemoteStatus.IsProcessRunning));

            try
            {
                if (isCurrentlyOnline)
                {
                    ServerDetailText.Text = "Stopping server instance...";
                    bool remoteStopped = false;
                    if (!string.IsNullOrWhiteSpace(_config.RemoteServerApiUrl))
                    {
                        remoteStopped = await _remoteServerService.StopRemoteServerAsync(_config.RemoteServerApiUrl, _config.RemoteAdminKey);
                    }

                    if (_gameProcessService.IsServerRunning)
                    {
                        _gameProcessService.StopDedicatedServer();
                    }

                    await Task.Delay(1200);
                }
                else
                {
                    ServerDetailText.Text = "Starting server instance...";
                    bool remoteStarted = false;
                    if (!string.IsNullOrWhiteSpace(_config.RemoteServerApiUrl))
                    {
                        remoteStarted = await _remoteServerService.StartRemoteServerAsync(_config.RemoteServerApiUrl, _config.RemoteAdminKey);
                    }

                    if (!remoteStarted && !string.IsNullOrEmpty(_detectedServerPath))
                    {
                        _gameProcessService.StartDedicatedServer(_detectedServerPath, _config.ServerLaunchArguments);
                    }

                    await Task.Delay(2000);
                }
            }
            catch (Exception ex)
            {
                ServerDetailText.Text = $"Action error: {ex.Message}";
            }
            finally
            {
                _isActionInProgress = false;
                await PollServerStatusAsync();
                BtnServerToggle.IsEnabled = true;
            }
        }

        private void BtnSelectServerPath_Click(object sender, RoutedEventArgs e)
        {
            if (DataContext is MainViewModel vm)
            {
                vm.ClickSoundCommand.Execute(null);
            }

            var dialog = new OpenFileDialog
            {
                Filter = "Palworld Server|PalServer.exe;PalServer-Win64-Shipping.exe|All Files|*.*",
                Title = "Locate Palworld Dedicated Server Executable"
            };

            if (dialog.ShowDialog() == true)
            {
                _detectedServerPath = Path.GetDirectoryName(dialog.FileName);
                _config.ServerInstallPath = _detectedServerPath;
                _config.Save();
                UpdateServerUIState(false, _lastRemoteStatus);
            }
        }

        private void BackgroundVideo_MediaEnded(object sender, RoutedEventArgs e)
        {
            try
            {
                BackgroundVideo.Position = TimeSpan.Zero;
                BackgroundVideo.Play();
            }
            catch { }
        }

        private void BackgroundVideo_MediaFailed(object? sender, ExceptionRoutedEventArgs e)
        {
            // Silently fall back to dark aesthetic gradient background
            BackgroundVideo.Visibility = Visibility.Collapsed;
        }

        private void TitleBar_MouseDown(object sender, MouseButtonEventArgs e)
        {
            if (e.ChangedButton == MouseButton.Left)
            {
                DragMove();
            }
        }

        private void MinimizeButton_Click(object sender, RoutedEventArgs e)
        {
            WindowState = WindowState.Minimized;
        }

        private void CloseButton_Click(object sender, RoutedEventArgs e)
        {
            if (DataContext is MainViewModel vm)
            {
                vm.AudioService.StopBgm();
            }
            Close();
            Application.Current?.Shutdown();
        }

        private void PlayHoverSound(object sender, MouseEventArgs e)
        {
            if (DataContext is MainViewModel vm)
            {
                vm.HoverSoundCommand.Execute(null);
            }
        }

        private void MainWindow_Closing(object? sender, System.ComponentModel.CancelEventArgs e)
        {
            if (DataContext is MainViewModel vm)
            {
                vm.AudioService.StopBgm();
            }

            _serverPollTimer?.Stop();

            if (_gameProcessService != null)
            {
                _gameProcessService.ServerStateChanged -= OnServerStateChanged;
                _gameProcessService.GameStarted -= OnGameStarted;
                _gameProcessService.GameExited -= OnGameExited;
            }

            StateChanged -= MainWindow_StateChanged;

            if (DataContext is IDisposable disposableVm)
            {
                disposableVm.Dispose();
            }

            Application.Current?.Shutdown();
        }
    }
}
