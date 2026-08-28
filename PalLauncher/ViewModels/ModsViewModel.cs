using System;
using System.Collections.ObjectModel;
using System.ComponentModel;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Data;
using PalLauncher.Models;
using PalLauncher.Services.Interfaces;
using PalLauncher.ViewModels.Common;

namespace PalLauncher.ViewModels
{
    public class ModsViewModel : ViewModelBase
    {
        private readonly IUpdateService _updateService;
        private readonly IConfigService _configService;
        private readonly IGamePathDetector _pathDetector;
        private readonly ILogService _logService;

        private ObservableCollection<ModInfo> _mods = new();
        private ICollectionView _filteredModsView;
        private ModInfo? _selectedMod;
        private string _selectedFilter = "All";
        private string _selectedCategory = "All";
        private string _searchQuery = string.Empty;
        private string _sortBy = "Name";
        private string _statusText = "Ready";
        private double _overallProgress;
        private string _currentSpeedText = string.Empty;
        private bool _isBusy;
        private CancellationTokenSource? _cts;

        public ObservableCollection<ModInfo> Mods => _mods;
        public ICollectionView FilteredModsView => _filteredModsView;

        public ModInfo? SelectedMod
        {
            get => _selectedMod;
            set => SetProperty(ref _selectedMod, value);
        }

        public string SelectedFilter
        {
            get => _selectedFilter;
            set
            {
                if (SetProperty(ref _selectedFilter, value))
                {
                    _filteredModsView.Refresh();
                    OnPropertyChanged(nameof(FilteredCountText));
                }
            }
        }

        public string SelectedCategory
        {
            get => _selectedCategory;
            set
            {
                if (SetProperty(ref _selectedCategory, value))
                {
                    _filteredModsView.Refresh();
                    OnPropertyChanged(nameof(FilteredCountText));
                }
            }
        }

        public string SearchQuery
        {
            get => _searchQuery;
            set
            {
                if (SetProperty(ref _searchQuery, value))
                {
                    _filteredModsView.Refresh();
                    OnPropertyChanged(nameof(FilteredCountText));
                    OnPropertyChanged(nameof(HasSearchQuery));
                }
            }
        }

        public bool HasSearchQuery => !string.IsNullOrWhiteSpace(SearchQuery);

        public string SortBy
        {
            get => _sortBy;
            set
            {
                if (SetProperty(ref _sortBy, value))
                {
                    ApplySorting();
                }
            }
        }

        public string StatusText
        {
            get => _statusText;
            set => SetProperty(ref _statusText, value);
        }

        public double OverallProgress
        {
            get => _overallProgress;
            set => SetProperty(ref _overallProgress, value);
        }

        public string CurrentSpeedText
        {
            get => _currentSpeedText;
            set => SetProperty(ref _currentSpeedText, value);
        }

        public bool IsBusy
        {
            get => _isBusy;
            set
            {
                if (SetProperty(ref _isBusy, value))
                {
                    CheckUpdatesCommand.RaiseCanExecuteChanged();
                    UpdateAllCommand.RaiseCanExecuteChanged();
                }
            }
        }

        public int TotalModsCount => _mods.Count;
        public int UpToDateCount => _mods.Count(m => m.Status == ModStatus.UpToDate);
        public int UpdatesAvailableCount => _mods.Count(m => m.Status == ModStatus.UpdateAvailable);
        public int MissingCount => _mods.Count(m => m.Status == ModStatus.Missing);
        public bool HasUpdatesPending => UpdatesAvailableCount > 0 || MissingCount > 0;

        public string FilteredCountText
        {
            get
            {
                int count = _filteredModsView.Cast<object>().Count();
                return $"{count} of {_mods.Count} mods";
            }
        }

        public AsyncRelayCommand CheckUpdatesCommand { get; }
        public AsyncRelayCommand UpdateAllCommand { get; }
        public AsyncRelayCommand UpdateSingleModCommand { get; }
        public RelayCommand CancelCommand { get; }
        public RelayCommand OpenModsFolderCommand { get; }
        public RelayCommand ClearSearchCommand { get; }
        public RelayCommand SetFilterCommand { get; }
        public RelayCommand SetCategoryCommand { get; }

        public ModsViewModel(
            IUpdateService updateService,
            IConfigService configService,
            IGamePathDetector pathDetector,
            ILogService logService)
        {
            _updateService = updateService;
            _configService = configService;
            _pathDetector = pathDetector;
            _logService = logService;

            _filteredModsView = CollectionViewSource.GetDefaultView(_mods);
            _filteredModsView.Filter = FilterMod;
            ApplySorting();

            CheckUpdatesCommand = new AsyncRelayCommand(ExecuteCheckUpdatesAsync, () => !IsBusy);
            UpdateAllCommand = new AsyncRelayCommand(ExecuteUpdateAllAsync, () => !IsBusy && _mods.Any(m => m.CanUpdate));
            UpdateSingleModCommand = new AsyncRelayCommand(ExecuteUpdateSingleModAsync, _ => !IsBusy);
            CancelCommand = new RelayCommand(ExecuteCancel, () => IsBusy);
            OpenModsFolderCommand = new RelayCommand(ExecuteOpenModsFolder);
            ClearSearchCommand = new RelayCommand(_ => SearchQuery = string.Empty);
            SetFilterCommand = new RelayCommand(param => { if (param is string f) SelectedFilter = f; });
            SetCategoryCommand = new RelayCommand(param => { if (param is string c) SelectedCategory = c; });
        }

        private void ApplySorting()
        {
            _filteredModsView.SortDescriptions.Clear();
            switch (_sortBy)
            {
                case "Category":
                    _filteredModsView.SortDescriptions.Add(new SortDescription(nameof(ModInfo.Category), ListSortDirection.Ascending));
                    _filteredModsView.SortDescriptions.Add(new SortDescription(nameof(ModInfo.Name), ListSortDirection.Ascending));
                    break;
                case "Size":
                    _filteredModsView.SortDescriptions.Add(new SortDescription(nameof(ModInfo.SizeBytes), ListSortDirection.Descending));
                    break;
                case "Status":
                    _filteredModsView.SortDescriptions.Add(new SortDescription(nameof(ModInfo.Status), ListSortDirection.Ascending));
                    _filteredModsView.SortDescriptions.Add(new SortDescription(nameof(ModInfo.Name), ListSortDirection.Ascending));
                    break;
                case "Name":
                default:
                    _filteredModsView.SortDescriptions.Add(new SortDescription(nameof(ModInfo.Name), ListSortDirection.Ascending));
                    break;
            }
        }

        private bool FilterMod(object obj)
        {
            if (obj is not ModInfo mod) return false;

            // 1. Status Filter
            bool matchesFilter = SelectedFilter switch
            {
                "Updates" => mod.CanUpdate,
                "Required" => mod.IsRequired,
                "Installed" => mod.Status == ModStatus.UpToDate,
                _ => true
            };
            if (!matchesFilter) return false;

            // 2. Category Filter
            if (!string.Equals(SelectedCategory, "All", StringComparison.OrdinalIgnoreCase))
            {
                if (!string.Equals(mod.Category, SelectedCategory, StringComparison.OrdinalIgnoreCase))
                    return false;
            }

            // 3. Search Query
            if (!string.IsNullOrWhiteSpace(SearchQuery))
            {
                string q = SearchQuery.Trim();
                bool matchesSearch =
                    (mod.Name?.Contains(q, StringComparison.OrdinalIgnoreCase) == true) ||
                    (mod.Description?.Contains(q, StringComparison.OrdinalIgnoreCase) == true) ||
                    (mod.Category?.Contains(q, StringComparison.OrdinalIgnoreCase) == true) ||
                    (mod.Id?.Contains(q, StringComparison.OrdinalIgnoreCase) == true) ||
                    (mod.RelativeInstallPath?.Contains(q, StringComparison.OrdinalIgnoreCase) == true);

                if (!matchesSearch) return false;
            }

            return true;
        }

        public async Task ExecuteCheckUpdatesAsync()
        {
            if (IsBusy) return;

            IsBusy = true;
            StatusText = "Checking for core mod updates...";
            OverallProgress = 0;
            CurrentSpeedText = string.Empty;
            _cts = new CancellationTokenSource();

            try
            {
                string manifestUrl = _configService.Config.RemoteManifestUrl;
                string gamePath = _configService.Config.GamePath;

                var detectedInfo = _pathDetector.DetectPalworldInstallation(gamePath);
                string effectivePath = detectedInfo.IsValid ? detectedInfo.GameRootPath : gamePath;

                var checkedMods = await _updateService.CheckForUpdatesAsync(manifestUrl, effectivePath, _cts.Token);

                _mods.Clear();
                foreach (var mod in checkedMods)
                {
                    _mods.Add(mod);
                }

                _filteredModsView.Refresh();
                UpdateCounts();

                if (HasUpdatesPending)
                {
                    StatusText = $"Update check complete: {UpdatesAvailableCount} update(s) available, {MissingCount} missing.";
                }
                else
                {
                    StatusText = "All core mod paks are verified and up to date!";
                }
            }
            catch (OperationCanceledException)
            {
                StatusText = "Update check cancelled.";
            }
            catch (Exception ex)
            {
                StatusText = $"Update check error: {ex.Message}";
                _logService.LogError("Error checking for mod updates.", "Updater", ex);
            }
            finally
            {
                IsBusy = false;
                UpdateAllCommand.RaiseCanExecuteChanged();
            }
        }

        public async Task ExecuteUpdateAllAsync()
        {
            if (IsBusy) return;

            string gamePath = _configService.Config.GamePath;
            var pathInfo = _pathDetector.DetectPalworldInstallation(gamePath);
            if (!pathInfo.IsValid && string.IsNullOrWhiteSpace(gamePath))
            {
                StatusText = "Cannot update: Palworld path not set or detected.";
                _logService.LogError("Update aborted: Palworld installation path is missing.", "Updater");
                return;
            }

            string targetRoot = pathInfo.IsValid ? pathInfo.GameRootPath : gamePath;

            IsBusy = true;
            _cts = new CancellationTokenSource();
            StatusText = "Downloading and verifying core mod paks...";
            OverallProgress = 0;

            var progress = new Progress<UpdateProgressInfo>(info =>
            {
                if (Application.Current != null)
                {
                    Application.Current.Dispatcher.InvokeAsync(() =>
                    {
                        OverallProgress = info.Percentage;
                        StatusText = info.StatusMessage;
                        CurrentSpeedText = info.FormattedSpeed;
                    });
                }
            });

            try
            {
                var modsToUpdate = _mods.Where(m => m.CanUpdate || !m.IsUpToDate).ToList();
                int updatedCount = await _updateService.DownloadAndInstallAllUpdatesAsync(modsToUpdate, targetRoot, progress, _cts.Token);

                StatusText = $"Successfully installed {updatedCount} core mod pak(s)!";
                UpdateCounts();
            }
            catch (OperationCanceledException)
            {
                StatusText = "Mod update cancelled.";
            }
            catch (Exception ex)
            {
                StatusText = $"Error installing mods: {ex.Message}";
                _logService.LogError("Batch mod update failed.", "Updater", ex);
            }
            finally
            {
                IsBusy = false;
                OverallProgress = 100;
                CurrentSpeedText = string.Empty;
                UpdateAllCommand.RaiseCanExecuteChanged();
            }
        }

        public async Task ExecuteUpdateSingleModAsync(object? param)
        {
            if (param is not ModInfo mod || IsBusy) return;

            string gamePath = _configService.Config.GamePath;
            var pathInfo = _pathDetector.DetectPalworldInstallation(gamePath);
            string targetRoot = pathInfo.IsValid ? pathInfo.GameRootPath : gamePath;

            if (string.IsNullOrWhiteSpace(targetRoot))
            {
                StatusText = "Palworld path is not configured.";
                return;
            }

            IsBusy = true;
            _cts = new CancellationTokenSource();
            StatusText = $"Updating {mod.Name}...";

            var progress = new Progress<UpdateProgressInfo>(info =>
            {
                if (Application.Current != null)
                {
                    Application.Current.Dispatcher.InvokeAsync(() =>
                    {
                        OverallProgress = info.Percentage;
                        StatusText = info.StatusMessage;
                        CurrentSpeedText = info.FormattedSpeed;
                    });
                }
            });

            try
            {
                bool ok = await _updateService.DownloadAndInstallModAsync(mod, targetRoot, progress, _cts.Token);
                StatusText = ok ? $"{mod.Name} installed and verified!" : $"Failed to install {mod.Name}.";
                UpdateCounts();
            }
            catch (Exception ex)
            {
                StatusText = $"Error: {ex.Message}";
            }
            finally
            {
                IsBusy = false;
                UpdateAllCommand.RaiseCanExecuteChanged();
            }
        }

        private void ExecuteCancel()
        {
            _cts?.Cancel();
            StatusText = "Cancelling operation...";
        }

        private void ExecuteOpenModsFolder()
        {
            try
            {
                string gamePath = _configService.Config.GamePath;
                var pathInfo = _pathDetector.DetectPalworldInstallation(gamePath);
                string targetDir = pathInfo.IsValid ? pathInfo.PaksDirectoryPath : Path.Combine(gamePath, @"Pal\Content\Paks");

                if (!Directory.Exists(targetDir))
                {
                    Directory.CreateDirectory(targetDir);
                }

                Process.Start(new ProcessStartInfo
                {
                    FileName = targetDir,
                    UseShellExecute = true
                });
            }
            catch (Exception ex)
            {
                _logService.LogError("Failed to open Paks folder.", "UI", ex);
            }
        }

        public void UpdateCounts()
        {
            OnPropertyChanged(nameof(TotalModsCount));
            OnPropertyChanged(nameof(UpToDateCount));
            OnPropertyChanged(nameof(UpdatesAvailableCount));
            OnPropertyChanged(nameof(MissingCount));
            OnPropertyChanged(nameof(HasUpdatesPending));
        }
    }
}
