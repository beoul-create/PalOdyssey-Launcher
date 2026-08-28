using System;
using System.Collections.Generic;
using System.Collections.ObjectModel;
using System.IO;
using System.Net;
using System.Net.Http;
using System.Threading;
using System.Threading.Tasks;
using Xunit;
using Xunit.Abstractions;
using PalLauncher.Services;
using PalLauncher.Services.Interfaces;
using PalLauncher.Models;

namespace PalLauncher.Tests
{
    public class LiveShopGuardTests : IDisposable
    {
        private readonly ITestOutputHelper _output;
        private readonly string _testBaseDir;
        private readonly string _appDataDir;

        public LiveShopGuardTests(ITestOutputHelper output)
        {
            _output = output;
            _testBaseDir = Path.Combine(Path.GetTempPath(), "PalOdyssey_ShopGuardTest_" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(_testBaseDir);

            // Mock AppData since QueueDelivery uses it
            _appDataDir = Path.Combine(_testBaseDir, "AppData", "PalLauncher");
            Directory.CreateDirectory(_appDataDir);
            Environment.SetEnvironmentVariable("LOCALAPPDATA", Path.Combine(_testBaseDir, "AppData"));
        }

        public void Dispose()
        {
            if (Directory.Exists(_testBaseDir))
            {
                try { Directory.Delete(_testBaseDir, true); } catch { }
            }
        }

        private class MockLogService : ILogService
        {
            private readonly ITestOutputHelper _output;
            public ObservableCollection<LogEntry> LogEntries { get; } = new();

            public MockLogService(ITestOutputHelper output) => _output = output;
            public void Log(string message, LogLevel level = LogLevel.Info, string source = "Launcher", string? details = null) => _output.WriteLine($"[{level}] [{source}] {message}");
            public void LogInfo(string message, string source = "Launcher") => _output.WriteLine($"[Info] [{source}] {message}");
            public void LogSuccess(string message, string source = "Launcher") => _output.WriteLine($"[Success] [{source}] {message}");
            public void LogWarning(string message, string source = "Launcher", string? details = null) => _output.WriteLine($"[Warning] [{source}] {message}");
            public void LogError(string message, string source = "Launcher", Exception? ex = null) => _output.WriteLine($"[Error] [{source}] {message}: {ex?.Message}");
            public void ClearLogs() => LogEntries.Clear();
            public string ExportLogsAsString() => "";
            public string GetLogDirectory() => "";
        }

        private class MockPalSaveService : IPalSaveService
        {
            public int CurrentTechPoints { get; set; } = 100;
            public bool OfflineBinarySaveEdited { get; private set; } = false;

            public string? FindSaveGamesDirectory() => null;
            public List<string> GetAvailablePlayerUids() => new() { "Steam_123" };
            public string ResolvePlayerUid(string? targetPlayerId) => targetPlayerId ?? "Steam_123";
            public Task<bool> CreateBackupAsync(string playerUid) => Task.FromResult(true);
            public Task<bool> IsPlayerOnlineAsync(string playerUid) => Task.FromResult(false);
            public Task<bool> RequestWorldSaveAsync() => Task.FromResult(true);
            public Task<string?> ExtractGuildIdFromLevelSavAsync(string playerUid) => Task.FromResult<string?>("MockGuild_1");
            public Task<bool> UpdatePalWorldSettingsAsync(int newBaseCap = 10) => Task.FromResult(true);
            public Task<bool> ApplyServerStabilityAndNetworkOptimizationsAsync(string? serverRootPath = null) => Task.FromResult(true);
            public Task<int> PruneExcessBackupsAsync(int maxBackupsToKeep = 24) => Task.FromResult(0);

            public Task<PlayerEconomyProfile?> ReadPlayerProfileAsync(string playerUid)
            {
                return Task.FromResult<PlayerEconomyProfile?>(new PlayerEconomyProfile
                {
                    TechnologyPoints = CurrentTechPoints
                });
            }

            public Task<bool> UpdateTechnologyPointsAsync(string playerUid, int pointsDelta, bool isAbsolute = false)
            {
                if (isAbsolute)
                {
                    CurrentTechPoints = pointsDelta;
                }
                else
                {
                    CurrentTechPoints += pointsDelta;
                }
                OfflineBinarySaveEdited = true;
                return Task.FromResult(true);
            }

            public Task<bool> UpdateBossTechnologyPointsAsync(string playerUid, int pointsDelta, bool isAbsolute = false)
            {
                OfflineBinarySaveEdited = true;
                return Task.FromResult(true);
            }
        }

        private class MockHttpMessageHandler : HttpMessageHandler
        {
            public string ResponseContent { get; set; } = "{}";
            public HttpStatusCode StatusCode { get; set; } = HttpStatusCode.OK;
            public HttpRequestMessage? LastRequest { get; private set; }

            protected override Task<HttpResponseMessage> SendAsync(HttpRequestMessage request, CancellationToken cancellationToken)
            {
                LastRequest = request;
                return Task.FromResult(new HttpResponseMessage(StatusCode)
                {
                    Content = new StringContent(ResponseContent)
                });
            }
        }

        private class MockConfigService : IConfigService
        {
            public LauncherConfig Config { get; set; } = new LauncherConfig
            {
                ServerAdminPassword = "ServerAdminPassword",
                RestApiPort = 8212
            };
            public Task<LauncherConfig> LoadConfigAsync() => Task.FromResult(Config);
            public Task SaveConfigAsync(LauncherConfig? config = null) => Task.CompletedTask;
            public string GetConfigFilePath() => "mock_config.json";
        }

        [Fact]
        public async Task OnlinePresenceCheck_ReturnsTrue_WhenPlayerIsOnline()
        {
            _output.WriteLine("Running OnlinePresenceCheck_ReturnsTrue_WhenPlayerIsOnline");
            
            var handler = new MockHttpMessageHandler
            {
                ResponseContent = @"{""players"":[{""accountId"":""Steam_76561198012345678"",""userId"":""abcdef""}]}"
            };
            var httpClient = new HttpClient(handler);
            var presenceService = new PlayerPresenceService(new MockConfigService(), new MockLogService(_output), httpClient);

            bool isOnline = await presenceService.IsPlayerOnlineAsync("76561198012345678");

            Assert.True(isOnline);
            Assert.NotNull(handler.LastRequest);
            Assert.Equal("Basic", handler.LastRequest.Headers.Authorization?.Scheme);
            _output.WriteLine("Presence Check SUCCESS: Matched Steam ID successfully.");
        }

        [Fact]
        public async Task DeliveryQueue_AppendsProperly_WithoutBinarySaveConflict()
        {
            _output.WriteLine("Running DeliveryQueue_AppendsProperly_WithoutBinarySaveConflict");
            
            var mockSave = new MockPalSaveService { CurrentTechPoints = 100 };
            var economyService = new EconomyService(new MockLogService(_output), mockSave, null, Path.Combine(_testBaseDir, "economy.json"));

            // Perform online exchange
            _output.WriteLine("Simulating online exchange for 1x Dog Coin (cost: 2 TP)");
            var receipt = await economyService.ExecuteExchangeAsync("Steam_123", "dog_coin", 1, isOnlineSession: true);

            // Verify receipt
            Assert.True(receipt.Success);
            Assert.Equal(2, receipt.TotalCost);

            // Verify binary save WAS edited to ensure authoritative disk sync
            Assert.True(mockSave.OfflineBinarySaveEdited, "Binary save should be updated to ensure in-game points remain in sync!");

            // Verify pending-deliveries.csv was created and written to
            string queueFile = Path.Combine(_appDataDir, "pending-deliveries.csv");
            Assert.True(File.Exists(queueFile), "Queue file was not created!");
            
            string content = await File.ReadAllTextAsync(queueFile);
            _output.WriteLine("Queue Contents:");
            _output.WriteLine(content);

            Assert.Contains("Steam_123,Exchange,DogCoin,1,-2", content);
            _output.WriteLine("Queue Test SUCCESS: CSV appended correctly and save file updated.");
        }

        [Fact]
        public async Task OfflinePlayer_EditsSaveFile_InsteadOfQueue()
        {
            _output.WriteLine("Running OfflinePlayer_EditsSaveFile_InsteadOfQueue");
            
            var mockSave = new MockPalSaveService { CurrentTechPoints = 100 };
            var economyService = new EconomyService(new MockLogService(_output), mockSave, null, Path.Combine(_testBaseDir, "economy.json"));

            // Perform offline exchange
            _output.WriteLine("Simulating offline exchange for 2x Dog Coin (cost: 4 TP)");
            var receipt = await economyService.ExecuteExchangeAsync("Steam_123", "dog_coin", 2, isOnlineSession: false);

            Assert.True(receipt.Success);
            Assert.True(mockSave.OfflineBinarySaveEdited, "Binary save SHOULD be edited during an offline session!");
            Assert.Equal(96, mockSave.CurrentTechPoints);

            string queueFile = Path.Combine(_appDataDir, "pending-deliveries.csv");
            Assert.False(File.Exists(queueFile), "Queue file should not be created for offline deliveries.");
            
            _output.WriteLine("Offline Test SUCCESS: Save edited properly when safe to do so.");
        }
    }
}
