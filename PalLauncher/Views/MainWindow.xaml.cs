using System;
using System.IO;
using System.Windows;
using System.Windows.Input;
using System.Windows.Media;
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
        private LauncherConfig _config = null!;

        public MainWindow()
        {
            InitializeComponent();
            Loaded += MainWindow_Loaded;
            Closing += MainWindow_Closing;
        }

        private void MainWindow_Loaded(object sender, RoutedEventArgs e)
        {
            if (DataContext is MainViewModel vm)
            {
                _gameProcessService = vm.GameProcessService;
                _config = vm.Config;
            }
            else
            {
                _gameProcessService = new GameProcessService();
                _config = LauncherConfig.Load();
            }

            InitializeServerManagement();

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

            UpdateServerUIState(_gameProcessService.IsServerRunning);
        }

        private void OnServerStateChanged(bool isRunning)
        {
            Dispatcher.Invoke(() => UpdateServerUIState(isRunning));
        }

        private void UpdateServerUIState(bool isRunning)
        {
            if (isRunning)
            {
                ServerStatusIndicator.Fill = new SolidColorBrush((Color)ColorConverter.ConvertFromString("#10B981")); // Emerald
                ServerStatusText.Text = "ONLINE (Port: 8211)";
                ServerStatusText.Foreground = new SolidColorBrush((Color)ColorConverter.ConvertFromString("#10B981"));
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
                BtnServerToggle.Content = "Start Server";
                BtnServerToggle.Background = new SolidColorBrush((Color)ColorConverter.ConvertFromString("#0284C7")); // Blue

                if (string.IsNullOrEmpty(_detectedServerPath))
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

        private void BtnServerToggle_Click(object sender, RoutedEventArgs e)
        {
            if (DataContext is MainViewModel vm)
            {
                vm.ClickSoundCommand.Execute(null);
            }

            if (_gameProcessService.IsServerRunning)
            {
                _gameProcessService.StopDedicatedServer();
            }
            else
            {
                if (!string.IsNullOrEmpty(_detectedServerPath))
                {
                    _gameProcessService.StartDedicatedServer(_detectedServerPath, _config.ServerLaunchArguments);
                }
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
                UpdateServerUIState(false);
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
            Close();
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
            if (_gameProcessService != null)
            {
                _gameProcessService.ServerStateChanged -= OnServerStateChanged;
            }

            if (DataContext is IDisposable disposableVm)
            {
                disposableVm.Dispose();
            }
        }
    }
}
