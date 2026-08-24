using System;
using System.Drawing;
using System.IO;
using System.Windows.Forms;
using PalLauncher.Services.Interfaces;

namespace PalLauncher.Services
{
    public class TrayIconService : IDisposable
    {
        private readonly ILogService? _logService;
        private NotifyIcon? _notifyIcon;
        private bool _disposed;

        public TrayIconService(ILogService? logService = null)
        {
            _logService = logService;
        }

        public void Initialize(
            Action onRestoreRequested,
            Action onRestartBotRequested,
            Action onExitRequested)
        {
            try
            {
                _notifyIcon = new NotifyIcon
                {
                    Text = "PalOdyssey Launcher (24/7 Active)",
                    Visible = true
                };

                try
                {
                    string iconPath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "Assets", "icon.ico");
                    if (File.Exists(iconPath))
                    {
                        _notifyIcon.Icon = new Icon(iconPath);
                    }
                    else
                    {
                        _notifyIcon.Icon = SystemIcons.Application;
                    }
                }
                catch
                {
                    _notifyIcon.Icon = SystemIcons.Application;
                }

                var contextMenu = new ContextMenuStrip();

                var openItem = new ToolStripMenuItem("Open PalLauncher", null, (s, e) => onRestoreRequested?.Invoke())
                {
                    Font = new Font(contextMenu.Font, FontStyle.Bold)
                };
                contextMenu.Items.Add(openItem);

                contextMenu.Items.Add(new ToolStripSeparator());

                var restartBotItem = new ToolStripMenuItem("Restart Discord Bot", null, (s, e) => onRestartBotRequested?.Invoke());
                contextMenu.Items.Add(restartBotItem);

                contextMenu.Items.Add(new ToolStripSeparator());

                var exitItem = new ToolStripMenuItem("Exit Launcher & Host", null, (s, e) => onExitRequested?.Invoke());
                contextMenu.Items.Add(exitItem);

                _notifyIcon.ContextMenuStrip = contextMenu;
                _notifyIcon.DoubleClick += (s, e) => onRestoreRequested?.Invoke();

                _logService?.LogInfo("System Tray Icon initialized successfully.", "App");
            }
            catch (Exception ex)
            {
                _logService?.LogWarning($"Failed to initialize system tray icon: {ex.Message}", "App");
            }
        }

        public void ShowNotification(string title, string message, ToolTipIcon icon = ToolTipIcon.Info, int timeoutMs = 3000)
        {
            try
            {
                if (_notifyIcon != null && _notifyIcon.Visible)
                {
                    _notifyIcon.ShowBalloonTip(timeoutMs, title, message, icon);
                }
            }
            catch (Exception ex)
            {
                _logService?.LogWarning($"Failed to display tray balloon tip: {ex.Message}", "App");
            }
        }

        public void Dispose()
        {
            if (_disposed) return;
            _disposed = true;

            try
            {
                if (_notifyIcon != null)
                {
                    _notifyIcon.Visible = false;
                    _notifyIcon.Icon?.Dispose();
                    _notifyIcon.ContextMenuStrip?.Dispose();
                    _notifyIcon.Dispose();
                    _notifyIcon = null;
                }
            }
            catch { }
        }
    }
}