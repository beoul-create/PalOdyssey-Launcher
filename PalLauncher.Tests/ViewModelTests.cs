using System;
using System.IO;
using System.Linq;
using System.Threading.Tasks;
using PalLauncher.Models;
using PalLauncher.Services;
using PalLauncher.ViewModels;
using Xunit;

namespace PalLauncher.Tests
{
    public class ViewModelTests : IDisposable
    {
        private readonly string _tempDir;
        private readonly LogService _logService;
        private readonly ConfigService _configService;
        private readonly GamePathDetector _pathDetector;
        private readonly UpdateService _updateService;
        private readonly LaunchService _launchService;

        public ViewModelTests()
        {
            _tempDir = Path.Combine(Path.GetTempPath(), "PalLauncherVMTests_" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(_tempDir);

            _logService = new LogService();
            _configService = new ConfigService(_logService, Path.Combine(_tempDir, "config.json"));
            _pathDetector = new GamePathDetector(_logService);
            _updateService = new UpdateService(_logService);
            _launchService = new LaunchService(_logService);
        }

        public void Dispose()
        {
            try
            {
                if (Directory.Exists(_tempDir))
                {
                    Directory.Delete(_tempDir, true);
                }
            }
            catch { }
        }

        [Fact]
        public void MainViewModel_Navigation_UpdatesActiveViewAndBooleanFlags()
        {
            var mainVm = new MainViewModel(_configService, _pathDetector, _updateService, _launchService, _logService);

            Assert.True(mainVm.IsDashboardActive);
            Assert.False(mainVm.IsModsActive);
            Assert.False(mainVm.IsSettingsActive);
            Assert.False(mainVm.IsLogsActive);

            mainVm.NavigateCommand.Execute("Mods");
            Assert.False(mainVm.IsDashboardActive);
            Assert.True(mainVm.IsModsActive);
            Assert.Equal("Mods", mainVm.ActiveView);

            mainVm.IsSettingsActive = true;
            Assert.True(mainVm.IsSettingsActive);
            Assert.Equal("Settings", mainVm.ActiveView);

            mainVm.IsLogsActive = true;
            Assert.True(mainVm.IsLogsActive);
            Assert.Equal("Logs", mainVm.ActiveView);
        }

        [Fact]
        public void SettingsViewModel_GeneratedArgumentsPreview_UpdatesDynamically()
        {
            var settingsVm = new SettingsViewModel(_configService, _pathDetector, _launchService, _updateService, _logService);

            settingsVm.LaunchMode = "Client";
            settingsVm.AutoJoinServer = true;
            settingsVm.ServerIp = "127.0.0.1";
            settingsVm.ServerPort = 8211;
            settingsVm.UseDirectX11 = true;
            settingsVm.UseAllCores = true;
            settingsVm.NoSplash = true;
            settingsVm.CustomArguments = "-culture=en";

            string preview = settingsVm.GeneratedArgumentsPreview;
            Assert.DoesNotContain("127.0.0.1", preview);
            Assert.Contains("-dx11", preview);
            Assert.Contains("-USEALLAVAILABLECORES", preview);
            Assert.Contains("-nosplash", preview);
            Assert.Contains("-culture=en", preview);

            // Switch to Server Mode
            settingsVm.IsServerMode = true;
            Assert.True(settingsVm.IsServerMode);
            Assert.False(settingsVm.IsClientMode);
            Assert.Contains("-port=8211", settingsVm.GeneratedArgumentsPreview);
        }

        [Fact]
        public void SettingsViewModel_RawInputOptimization_RoundtripsConfig()
        {
            var settingsVm = new SettingsViewModel(_configService, _pathDetector, _launchService, _updateService, _logService);
            
            var config = new LauncherConfig
            {
                EnableRawInputOptimization = true
            };
            settingsVm.LoadFromConfig(config);
            Assert.True(settingsVm.EnableRawInputOptimization);

            settingsVm.EnableRawInputOptimization = false;
            var savedConfig = settingsVm.CreateConfigFromProperties();
            Assert.False(savedConfig.EnableRawInputOptimization);
        }

        [Fact]
        public void LogsViewModel_Filtering_FiltersLogsCorrectly()
        {
            var logService = new LogService();
            logService.ClearLogs();

            logService.LogInfo("Information message", "Test");
            logService.LogSuccess("Success message", "Test");
            logService.LogWarning("Warning message", "Test");
            logService.LogError("Error message", "Test");

            var logsVm = new LogsViewModel(logService);

            logsVm.SelectedFilter = "All";
            Assert.Equal(4, logsVm.FilteredLogsView.Cast<object>().Count());

            logsVm.SelectedFilter = "Error";
            Assert.Single(logsVm.FilteredLogsView.Cast<object>());

            logsVm.SelectedFilter = "Warning";
            Assert.Single(logsVm.FilteredLogsView.Cast<object>());

            logsVm.SelectedFilter = "Success";
            Assert.Single(logsVm.FilteredLogsView.Cast<object>());
        }

        [Fact]
        public void ModsViewModel_FilteringAndCounts_ReflectsModStates()
        {
            var modsVm = new ModsViewModel(_updateService, _configService, _pathDetector, _logService);

            modsVm.Mods.Add(new ModInfo { Id = "m1", Name = "Mod 1", Status = ModStatus.UpToDate, IsRequired = true });
            modsVm.Mods.Add(new ModInfo { Id = "m2", Name = "Mod 2", Status = ModStatus.UpdateAvailable, IsRequired = true });
            modsVm.Mods.Add(new ModInfo { Id = "m3", Name = "Mod 3", Status = ModStatus.Missing, IsRequired = false });

            modsVm.UpdateCounts();

            Assert.Equal(3, modsVm.TotalModsCount);
            Assert.Equal(1, modsVm.UpToDateCount);
            Assert.Equal(1, modsVm.UpdatesAvailableCount);
            Assert.Equal(1, modsVm.MissingCount);
            Assert.True(modsVm.HasUpdatesPending);

            modsVm.SelectedFilter = "Updates";
            Assert.Equal(2, modsVm.FilteredModsView.Cast<object>().Count());

            modsVm.SelectedFilter = "Required";
            Assert.Equal(2, modsVm.FilteredModsView.Cast<object>().Count());
        }
    }
}
