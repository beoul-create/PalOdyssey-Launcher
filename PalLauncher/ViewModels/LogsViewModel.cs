using System;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
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
        public RelayCommand CopyLogsCommand { get; }

        public LogsViewModel(ILogService logService)
        {
            _logService = logService;
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
                _ => true
            };
        }
    }
}
