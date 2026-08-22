using System;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Data;
using PalLauncher.Models;
using PalLauncher.Services.Interfaces;
using PalLauncher.ViewModels.Common;

namespace PalLauncher.ViewModels
{
    public class LogsViewModel : ViewModelBase
    {
        private readonly ILogService _logService;
        private readonly ICrashLogService _crashLogService;
        private readonly IGamePathDetector? _pathDetector;
        private readonly IConfigService? _configService;
        private string _selectedFilter = "All";
        private bool _autoScroll = true;
        private readonly ICollectionView _filteredLogsView;

        public ObservableCollection<LogEntry> LogEntries => _logService.LogEntries;
        public ICollectionView FilteredLogsView => _filteredLogsView;

        public string SelectedFilter
        {
            get => _selectedFilter;
            set
            {
                if (SetProperty(ref _selectedFilter, value))
                {
                    _filteredLogsView.Refresh();
                }
            }
        }

        public bool AutoScroll
        {
            get => _autoScroll;
            set => SetProperty(ref _autoScroll, value);
        }

        public RelayCommand ClearLogsCommand { get; }
        public RelayCommand OpenLogFolderCommand { get; }
        public RelayCommand OpenCrashesFolderCommand { get; }
        public RelayCommand CopyLogsCommand { get; }
        public AsyncRelayCommand InspectCrashDiagnosticsCommand { get; }
        public AsyncRelayCommand ViewUe4ssLogCommand { get; }
        public AsyncRelayCommand ViewEngineLogCommand { get; }

        public LogsViewModel(
            ILogService logService,
            ICrashLogService? crashLogService = null,
            IGamePathDetector? pathDetector = null,
            IConfigService? configService = null)
        {
            _logService = logService;
            _crashLogService = crashLogService ?? new Services.CrashLogService(logService);
            _pathDetector = pathDetector;
            _configService = configService;

            _filteredLogsView = CollectionViewSource.GetDefaultView(_logService.LogEntries);
            _filteredLogsView.Filter = FilterLogEntry;

            ClearLogsCommand = new RelayCommand(() =>
            {
                _logService.ClearLogs();
                _logService.LogInfo("Logs cleared by user.", "Console");
            });

            OpenLogFolderCommand = new RelayCommand(() =>
            {
                try
                {
                    string dir = _logService.GetLogDirectory();
                    if (Directory.Exists(dir))
                    {
                        Process.Start(new ProcessStartInfo
                        {
                            FileName = dir,
                            UseShellExecute = true
                        });
                    }
                }
                catch (Exception ex)
                {
                    _logService.LogError("Failed to open log folder.", "Logs", ex);
                }
            });

            OpenCrashesFolderCommand = new RelayCommand(() =>
            {
                try
                {
                    string crashDir = _crashLogService.GetCrashesDirectoryPath();
                    if (!Directory.Exists(crashDir))
                    {
                        Directory.CreateDirectory(crashDir);
                    }

                    Process.Start(new ProcessStartInfo
                    {
                        FileName = crashDir,
                        UseShellExecute = true
                    });
                    _logService.LogInfo($"Opened crash dumps folder: {crashDir}", "CrashDiagnostics");
                }
                catch (Exception ex)
                {
                    _logService.LogError("Failed to open crash dumps folder.", "CrashDiagnostics", ex);
                }
            });

            CopyLogsCommand = new RelayCommand(() =>
            {
                try
                {
                    string content = _logService.ExportLogsAsString();
                    Clipboard.SetText(content);
                    _logService.LogSuccess("Log output copied to clipboard.", "Console");
                }
                catch (Exception ex)
                {
                    _logService.LogError("Failed to copy logs to clipboard.", "Logs", ex);
                }
            });

            InspectCrashDiagnosticsCommand = new AsyncRelayCommand(async () =>
            {
                try
                {
                    _logService.LogInfo("Scanning system for latest Unreal Engine crash dump...", "CrashDiagnostics");
                    string? gameRoot = GetGameRoot();

                    var crash = await _crashLogService.GetLatestCrashReportAsync(gameRoot);
                    var ue4ssLog = await _crashLogService.GetLatestUe4ssLogAsync(gameRoot, 20);
                    var engineLog = await _crashLogService.GetLatestEngineLogAsync(gameRoot, 20);

                    string summary = _crashLogService.GenerateDiagnosticSummary(crash, ue4ssLog, engineLog);

                    if (crash != null && crash.HasCrashData)
                    {
                        _logService.LogError($"[CRASH FOUND] Timestamp: {crash.Timestamp:HH:mm:ss} | Module: {crash.PrimaryModule}", "CrashDiagnostics");
                        _logService.LogError($"[ERROR MESSAGE] {crash.ErrorMessage}", "CrashDiagnostics");
                        if (!string.IsNullOrEmpty(crash.SuggestedFix))
                        {
                            _logService.LogWarning($"[ACTIONABLE FIX] {crash.SuggestedFix}", "CrashDiagnostics");
                        }
                    }
                    else
                    {
                        _logService.LogSuccess("No active crash dumps recorded. Engine shutdown normally.", "CrashDiagnostics");
                    }

                    Clipboard.SetText(summary);
                    _logService.LogSuccess("Complete crash diagnostic report copied to clipboard!", "CrashDiagnostics");
                }
                catch (Exception ex)
                {
                    _logService.LogError("Error generating crash diagnostics.", "CrashDiagnostics", ex);
                }
            });

            ViewUe4ssLogCommand = new AsyncRelayCommand(async () =>
            {
                try
                {
                    string? gameRoot = GetGameRoot();
                    var logContent = await _crashLogService.GetLatestUe4ssLogAsync(gameRoot, 35);
                    if (string.IsNullOrWhiteSpace(logContent))
                    {
                        _logService.LogWarning("UE4SS.log not found or empty.", "UE4SS");
                        return;
                    }

                    _logService.LogInfo("--- BEGIN UE4SS.LOG RECENT OUTPUT ---", "UE4SS");
                    var lines = logContent.Split(new[] { "\r\n", "\r", "\n" }, StringSplitOptions.RemoveEmptyEntries);
                    foreach (var line in lines)
                    {
                        if (line.Contains("[error]", StringComparison.OrdinalIgnoreCase) || line.Contains("exception", StringComparison.OrdinalIgnoreCase))
                            _logService.LogError(line, "UE4SS");
                        else if (line.Contains("[warning]", StringComparison.OrdinalIgnoreCase))
                            _logService.LogWarning(line, "UE4SS");
                        else
                            _logService.LogInfo(line, "UE4SS");
                    }
                    _logService.LogInfo("--- END UE4SS.LOG OUTPUT ---", "UE4SS");
                }
                catch (Exception ex)
                {
                    _logService.LogError("Failed to read UE4SS log.", "UE4SS", ex);
                }
            });

            ViewEngineLogCommand = new AsyncRelayCommand(async () =>
            {
                try
                {
                    string? gameRoot = GetGameRoot();
                    var logContent = await _crashLogService.GetLatestEngineLogAsync(gameRoot, 35);
                    if (string.IsNullOrWhiteSpace(logContent))
                    {
                        _logService.LogWarning("Pal.log not found in Saved/Logs.", "PalEngine");
                        return;
                    }

                    _logService.LogInfo("--- BEGIN PAL.LOG RECENT OUTPUT ---", "PalEngine");
                    var lines = logContent.Split(new[] { "\r\n", "\r", "\n" }, StringSplitOptions.RemoveEmptyEntries);
                    foreach (var line in lines)
                    {
                        if (line.Contains("error", StringComparison.OrdinalIgnoreCase) || line.Contains("fatal", StringComparison.OrdinalIgnoreCase))
                            _logService.LogError(line, "PalEngine");
                        else if (line.Contains("warning", StringComparison.OrdinalIgnoreCase))
                            _logService.LogWarning(line, "PalEngine");
                        else
                            _logService.LogInfo(line, "PalEngine");
                    }
                    _logService.LogInfo("--- END PAL.LOG OUTPUT ---", "PalEngine");
                }
                catch (Exception ex)
                {
                    _logService.LogError("Failed to read Pal.log.", "PalEngine", ex);
                }
            });
        }

        private string? GetGameRoot()
        {
            if (_configService != null)
            {
                var cfg = _configService.Config;
                if (!string.IsNullOrEmpty(cfg.GamePath) && Directory.Exists(cfg.GamePath))
                    return cfg.GamePath;
            }
            if (_pathDetector != null)
            {
                var p = _pathDetector.DetectPalworldInstallation();
                if (p.IsValid) return p.GameRootPath;
            }
            return null;
        }

        private bool FilterLogEntry(object obj)
        {
            if (obj is not LogEntry entry) return false;

            return SelectedFilter switch
            {
                "Errors" or "Error" => entry.Level == LogLevel.Error,
                "Warnings" or "Warning" => entry.Level == LogLevel.Warning,
                "Success" => entry.Level == LogLevel.Success,
                "Info" => entry.Level == LogLevel.Info,
                "Server" or "PalServer" => entry.Source.Equals("PalServer", StringComparison.OrdinalIgnoreCase),
                "Crash" or "CrashDiagnostics" => entry.Source.Contains("Crash", StringComparison.OrdinalIgnoreCase) || entry.Source.Equals("UE4SS", StringComparison.OrdinalIgnoreCase),
                _ => true
            };
        }
    }
}
