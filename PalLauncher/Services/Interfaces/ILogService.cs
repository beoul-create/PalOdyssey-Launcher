using System;
using System.Collections.ObjectModel;
using PalLauncher.Models;

namespace PalLauncher.Services.Interfaces
{
    public interface ILogService
    {
        ObservableCollection<LogEntry> LogEntries { get; }
        void Log(string message, LogLevel level = LogLevel.Info, string source = "Launcher", string? details = null);
        void LogInfo(string message, string source = "Launcher");
        void LogSuccess(string message, string source = "Launcher");
        void LogWarning(string message, string source = "Launcher", string? details = null);
        void LogError(string message, string source = "Launcher", Exception? ex = null);
        void ClearLogs();
        string ExportLogsAsString();
        string GetLogDirectory();
    }
}
