using System;
using System.Collections.Concurrent;
using System.Collections.ObjectModel;
using System.IO;
using System.Text;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Threading;
using PalLauncher.Models;
using PalLauncher.Services.Interfaces;

namespace PalLauncher.Services
{
    public class LogService : ILogService, IDisposable
    {
        private readonly object _lock = new();
        private readonly string _logFilePath;
        private readonly string _logDirectory;
        private readonly BlockingCollection<string> _fileWriteQueue = new(new ConcurrentQueue<string>());
        private readonly CancellationTokenSource _cts = new();
        private readonly Task _writerTask;

        public ObservableCollection<LogEntry> LogEntries { get; } = new();

        public LogService()
        {
            _logDirectory = Path.Combine(
                Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData),
                "PalLauncher",
                "Logs");

            try
            {
                if (!Directory.Exists(_logDirectory))
                {
                    Directory.CreateDirectory(_logDirectory);
                }
            }
            catch
            {
                _logDirectory = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "Logs");
                Directory.CreateDirectory(_logDirectory);
            }

            _logFilePath = Path.Combine(_logDirectory, $"launcher_{DateTime.Now:yyyyMMdd}.log");

            // Start dedicated background file writer thread
            _writerTask = Task.Run(ProcessFileWriteQueue);

            LogInfo("LogService initialized.", "System");
        }

        private async Task ProcessFileWriteQueue()
        {
            try
            {
                while (!_cts.Token.IsCancellationRequested)
                {
                    if (_fileWriteQueue.TryTake(out string? line, 100, _cts.Token))
                    {
                        if (line != null)
                        {
                            try
                            {
                                await File.AppendAllTextAsync(_logFilePath, line + Environment.NewLine, Encoding.UTF8, _cts.Token);
                            }
                            catch { }
                        }
                    }
                }
            }
            catch (OperationCanceledException) { }
            catch { }
        }

        public void Log(string message, LogLevel level = LogLevel.Info, string source = "Launcher", string? details = null)
        {
            var entry = new LogEntry
            {
                Timestamp = DateTime.Now,
                Level = level,
                Source = source,
                Message = message,
                Details = details
            };

            // Safely post to UI collection with background priority so UI stays fluid
            if (Application.Current != null)
            {
                Application.Current.Dispatcher.BeginInvoke(DispatcherPriority.Background, () =>
                {
                    lock (_lock)
                    {
                        LogEntries.Add(entry);
                        if (LogEntries.Count > 1000)
                        {
                            LogEntries.RemoveAt(0);
                        }
                    }
                });
            }
            else
            {
                lock (_lock)
                {
                    LogEntries.Add(entry);
                }
            }

            // Queue to background disk writer without blocking calling thread
            string formattedLine = $"[{entry.FormattedTimestamp}] [{entry.Level,-7}] [{entry.Source}] {entry.Message}";
            if (!string.IsNullOrEmpty(entry.Details))
            {
                formattedLine += $"\n    Details: {entry.Details}";
            }
            _fileWriteQueue.TryAdd(formattedLine);
        }

        public void Dispose()
        {
            try
            {
                _cts.Cancel();
                _fileWriteQueue.CompleteAdding();
            }
            catch { }
        }

        public void LogInfo(string message, string source = "Launcher") =>
            Log(message, LogLevel.Info, source);

        public void LogSuccess(string message, string source = "Launcher") =>
            Log(message, LogLevel.Success, source);

        public void LogWarning(string message, string source = "Launcher", string? details = null) =>
            Log(message, LogLevel.Warning, source, details);

        public void LogError(string message, string source = "Launcher", Exception? ex = null) =>
            Log(message, LogLevel.Error, source, ex?.ToString());

        public void ClearLogs()
        {
            if (Application.Current != null)
            {
                Application.Current.Dispatcher.Invoke(() => LogEntries.Clear());
            }
            else
            {
                LogEntries.Clear();
            }
        }

        public string ExportLogsAsString()
        {
            var sb = new StringBuilder();
            lock (_lock)
            {
                foreach (var entry in LogEntries)
                {
                    sb.AppendLine($"[{entry.FormattedTimestamp}] [{entry.Level,-7}] [{entry.Source}] {entry.Message}");
                    if (!string.IsNullOrEmpty(entry.Details))
                    {
                        sb.AppendLine($"    {entry.Details}");
                    }
                }
            }
            return sb.ToString();
        }

        public string GetLogDirectory() => _logDirectory;
    }
}
