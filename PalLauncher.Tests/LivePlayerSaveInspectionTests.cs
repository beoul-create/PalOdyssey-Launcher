using System;
using System.IO;
using System.Threading.Tasks;
using Xunit;
using Xunit.Abstractions;
using PalLauncher.Services;

namespace PalLauncher.Tests
{
    public class LivePlayerSaveInspectionTests
    {
        private readonly ITestOutputHelper _output;

        public LivePlayerSaveInspectionTests(ITestOutputHelper output)
        {
            _output = output;
        }

        [Fact]
        public async Task Test_Inspect_And_Set_LivePlayerSave()
        {
            var logService = new LogService();
            var saveService = new PalSaveService(logService, customSaveDirectory: null);

            string worldDir = saveService.FindSaveGamesDirectory() ?? "";
            _output.WriteLine($"Discovered World Dir: {worldDir}");

            string uid = "9EDC20A9000000000000000000000000";
            string backupFile = Path.Combine(worldDir, "backup", "economy_backups", "20260828_011313_9EDC20A9000000000000000000000000.sav");
            string playerSave = Path.Combine(worldDir, "Players", "9EDC20A9000000000000000000000000.sav");
            
            // Restore from clean backup
            File.Copy(backupFile, playerSave, overwrite: true);
            _output.WriteLine($"Restored clean backup to playerSave (Length: {new FileInfo(playerSave).Length})");

            var profBefore = await saveService.ReadPlayerProfileAsync("9EDC20A9000000000000000000000000");
            _output.WriteLine($"Profile before edit: TechPoints={profBefore?.TechnologyPoints}, BossTechPoints={profBefore?.BossTechnologyPoints}");

            var economyService = new EconomyService(logService, saveService);
            var setReceipt = await economyService.SetPlayerTechnologyPointsAsync("9EDC20A9000000000000000000000000", 7, "tech_points", isOnlineSession: false);
            _output.WriteLine($"SetPlayerTechnologyPointsAsync returned: Success={setReceipt.Success}, NewPoints={setReceipt.NewPoints}, Msg={setReceipt.Message}");

            var profFinal = await economyService.GetPlayerProfileAsync("9EDC20A9000000000000000000000000", forceLiveRefresh: true);
            _output.WriteLine($"GetPlayerProfileAsync: Name={profFinal?.PlayerName}, TechPoints={profFinal?.TechnologyPoints}, BossTechPoints={profFinal?.BossTechnologyPoints}");

            Assert.True(setReceipt.Success);
            Assert.NotNull(profFinal);
            Assert.Equal(7, profFinal.TechnologyPoints);
        }
    }
}
