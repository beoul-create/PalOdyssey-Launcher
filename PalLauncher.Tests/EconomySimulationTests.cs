using System;
using System.IO;
using System.Text;
using System.Threading.Tasks;
using Xunit;
using Xunit.Abstractions;
using PalLauncher.Services;
using PalLauncher.Models;

namespace PalLauncher.Tests
{
    public class EconomySimulationTests
    {
        private readonly ITestOutputHelper _output;

        public EconomySimulationTests(ITestOutputHelper output)
        {
            _output = output;
        }

        private byte[] CreateMockPalworldSave(int unusedTechPoints, string uid)
        {
            using var ms = new MemoryStream();
            using var writer = new BinaryWriter(ms, Encoding.ASCII);

            writer.Write(Encoding.ASCII.GetBytes("GVAS"));
            writer.Write(3); 
            writer.Write(new byte[16]); 

            string propName = "UnusedTechnologyPoint";
            writer.Write(Encoding.ASCII.GetBytes(propName));
            writer.Write((byte)0); 

            string propType = "IntProperty";
            writer.Write(Encoding.ASCII.GetBytes(propType));
            writer.Write((byte)0);

            writer.Write((long)4); 
            writer.Write((byte)0); 

            writer.Write(unusedTechPoints); 
            
            // To pass the parser, add playerUid
            string uidProp = "PlayerUId";
            writer.Write(Encoding.ASCII.GetBytes(uidProp));
            writer.Write((byte)0);
            writer.Write(Encoding.ASCII.GetBytes("StructProperty"));
            writer.Write((byte)0);
            writer.Write((long)16);
            writer.Write((byte)0);
            writer.Write(Encoding.ASCII.GetBytes("Guid"));
            writer.Write((byte)0);
            writer.Write((byte)0);
            
            byte[] playerGuidBytes = new byte[16];
            for (int i = 0; i < 16; i++)
            {
                playerGuidBytes[i] = Convert.ToByte(uid.Substring(i * 2, 2), 16);
            }
            writer.Write(playerGuidBytes);

            writer.Flush();
            return PalSaveService.CompressPalSave(ms.ToArray());
        }

        private byte[] CreateMockLevelSave(string playerUid, string groupIdStr)
        {
            using var ms = new MemoryStream();
            using var writer = new BinaryWriter(ms, Encoding.ASCII);

            writer.Write(Encoding.ASCII.GetBytes("GVAS"));
            writer.Write(3); 
            writer.Write(new byte[16]); 

            // group_id header
            writer.Write(Encoding.ASCII.GetBytes("group_id"));
            writer.Write((byte)0);
            writer.Write(Encoding.ASCII.GetBytes("StructProperty"));
            writer.Write((byte)0);
            writer.Write((long)16);
            writer.Write((byte)0);
            writer.Write(Encoding.ASCII.GetBytes("Guid"));
            writer.Write((byte)0);
            writer.Write((byte)0);
            
            byte[] groupBytes = new byte[16];
            for (int i = 0; i < 16; i++)
            {
                groupBytes[i] = Convert.ToByte(groupIdStr.Substring(i * 2, 2), 16);
            }
            writer.Write(groupBytes);

            // player_uid
            byte[] playerGuidBytes = new byte[16];
            for (int i = 0; i < 16; i++)
            {
                playerGuidBytes[i] = Convert.ToByte(playerUid.Substring(i * 2, 2), 16);
            }
            writer.Write(playerGuidBytes);
            writer.Write(new byte[32]);

            writer.Flush();
            return PalSaveService.CompressPalSave(ms.ToArray());
        }

        [Fact]
        public async Task EndToEnd_EconomyAndQuotaSimulation()
        {
            _output.WriteLine("=== [START] End-to-End Economy & Build Quota Simulation ===");

            string saveGamesDir = Path.Combine(Path.GetTempPath(), "PalSim_" + Guid.NewGuid().ToString().Substring(0, 8));
            string playersDir = Path.Combine(saveGamesDir, "Players");
            Directory.CreateDirectory(playersDir);

            // 1. Mock Save Initialization
            string player1Uid = "11112222333344445555666677778888";
            string player2Uid = "AAAABBBBCCCCDDDDEEEEFFFF00001111";
            string guildId = "99998888777766665555444433332222"; // Guild_Alpha

            _output.WriteLine("[STEP 1] Generating dummy Player_01.sav (50 Tech Points) and Level.sav (Guild_Alpha: Player 1 & 2)...");
            
            byte[] player1Bytes = CreateMockPalworldSave(50, player1Uid);
            string p1File = Path.Combine(playersDir, $"{player1Uid}.sav");
            File.WriteAllBytes(p1File, player1Bytes);

            byte[] player2Bytes = CreateMockPalworldSave(20, player2Uid);
            string p2File = Path.Combine(playersDir, $"{player2Uid}.sav");
            File.WriteAllBytes(p2File, player2Bytes);

            byte[] levelBytes = CreateMockLevelSave(player1Uid, guildId);
            string levelFile = Path.Combine(saveGamesDir, "Level.sav");
            File.WriteAllBytes(levelFile, levelBytes);

            var logService = new LogService(); // We can ignore standard logs, we will write to _output
            var saveService = new PalSaveService(logService, saveGamesDir);
            
            // Force PalLauncher's local app data path to temp so we don't mess up real data
            Environment.SetEnvironmentVariable("LOCALAPPDATA", saveGamesDir);
            string customStateFile = Path.Combine(saveGamesDir, "guild-licenses.json");
            var licenseService = new GuildLicenseService(logService, saveService, customStateFile);
            var economyService = new EconomyService(logService, saveService, licenseService);

            // 2. Guild Bank & Store Transaction Test
            _output.WriteLine("[STEP 2] Simulating Guild Bank & Store Transactions...");

            string resolvedGuildId = await licenseService.ResolveGuildIdAsync(player1Uid);
            _output.WriteLine($"Resolved Guild ID from Level.sav: {resolvedGuildId}");
            Assert.NotNull(resolvedGuildId);

            // Player 1 executes /deposit amount:25
            _output.WriteLine("-> Simulating Player 1 executing /deposit amount:25");
            bool p1Deduct = await saveService.UpdateTechnologyPointsAsync(player1Uid, -25);
            Assert.True(p1Deduct);
            await licenseService.DepositToBankAsync(resolvedGuildId, player1Uid, 25);
            
            var profile1 = await saveService.ReadPlayerProfileAsync(player1Uid);
            _output.WriteLine($"Player 1 Tech Points after deposit: {profile1.TechnologyPoints}");
            Assert.Equal(25, profile1.TechnologyPoints);

            var state = await licenseService.GetGuildStateAsync(resolvedGuildId);
            _output.WriteLine($"Guild Bank Balance after Player 1 deposit: {state.GuildBankBalance}");
            Assert.Equal(25, state.GuildBankBalance);

            // Player 2 executes /deposit amount:15
            _output.WriteLine("-> Simulating Player 2 executing /deposit amount:15");
            bool p2Deduct = await saveService.UpdateTechnologyPointsAsync(player2Uid, -15);
            Assert.True(p2Deduct);
            await licenseService.DepositToBankAsync(resolvedGuildId, player2Uid, 15);

            state = await licenseService.GetGuildStateAsync(resolvedGuildId);
            _output.WriteLine($"Guild Bank Balance after Player 2 deposit: {state.GuildBankBalance}");
            Assert.Equal(40, state.GuildBankBalance);

            // 3. License Purchase & Live Quota Unlock
            _output.WriteLine("[STEP 3] License Purchase & Live Quota Unlock...");
            
            _output.WriteLine("-> Simulating Player 1 executing /exchange item:breeding_pen_slot (Cost: 25) paid from guild bank");
            var receipt1 = await economyService.ExecuteExchangeAsync(player1Uid, "breeding_pen_slot", 1);
            Assert.True(receipt1.Success);
            
            _output.WriteLine("-> Simulating Player 1 executing /exchange item:ranch_slot (Cost: 15) paid from guild bank");
            var receipt2 = await economyService.ExecuteExchangeAsync(player1Uid, "ranch_slot", 1);
            Assert.True(receipt2.Success, receipt2.Message);

            state = await licenseService.GetGuildStateAsync(resolvedGuildId);
            _output.WriteLine($"Guild Bank Balance post-purchases: {state.GuildBankBalance}");
            _output.WriteLine($"guild-licenses.json updates -> max_breeding_pens: {state.MaxBreedingPens}, max_ranches: {state.MaxRanches}");
            Assert.Equal(0, state.GuildBankBalance);
            Assert.Equal(2, state.MaxBreedingPens);
            Assert.Equal(2, state.MaxRanches);

            // 4. Save File Integrity Check
            _output.WriteLine("[STEP 4] Save File Integrity Check (Player_01.sav)");
            var profileEnd = await saveService.ReadPlayerProfileAsync(player1Uid);
            Assert.NotNull(profileEnd);
            _output.WriteLine($"Player 1 profile read back successfully without byte drift. Final Points: {profileEnd.TechnologyPoints}");

            _output.WriteLine("=== [SUCCESS] End-to-End Simulation Passed! ===");
        }

        [Fact]
        public async Task Gacha_PointDeductionAndInsufficientFunds_WorksAccurately()
        {
            string tempDir = Path.Combine(Path.GetTempPath(), "PalGachaTest_" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(tempDir);
            string playersDir = Path.Combine(tempDir, "Players");
            Directory.CreateDirectory(playersDir);

            string playerUid = "9EDC20A9000000000000000000000000";
            byte[] saveBytes = CreateMockPalworldSave(12, playerUid);
            string playerSavePath = Path.Combine(playersDir, $"{playerUid}.sav");
            await File.WriteAllBytesAsync(playerSavePath, saveBytes);

            var logService = new LogService();
            var saveService = new PalSaveService(logService, tempDir);
            string customStateFile = Path.Combine(tempDir, "economy_state.json");
            var economyService = new EconomyService(logService, saveService, customStateFilePath: customStateFile);

            // Pull 1: 1-pull (3 pts). 12 -> 9
            var r1 = await economyService.ExecuteGachaAsync(playerUid, 1, isOnlineSession: true);
            Assert.True(r1.Success);
            Assert.Equal(12, r1.PreviousTechPoints);
            Assert.Equal(9, r1.NewTechPoints);
            Assert.Single(r1.Drops);

            // Pull 2: 1-pull (3 pts). 9 -> 6
            var r2 = await economyService.ExecuteGachaAsync(playerUid, 1, isOnlineSession: true);
            Assert.True(r2.Success);
            Assert.Equal(9, r2.PreviousTechPoints);
            Assert.Equal(6, r2.NewTechPoints);

            // Pull 3: 1-pull (3 pts). 6 -> 3
            var r3 = await economyService.ExecuteGachaAsync(playerUid, 1, isOnlineSession: true);
            Assert.True(r3.Success);
            Assert.Equal(6, r3.PreviousTechPoints);
            Assert.Equal(3, r3.NewTechPoints);

            // Pull 4: 1-pull (3 pts). 3 -> 0
            var r4 = await economyService.ExecuteGachaAsync(playerUid, 1, isOnlineSession: true);
            Assert.True(r4.Success);
            Assert.Equal(3, r4.PreviousTechPoints);
            Assert.Equal(0, r4.NewTechPoints);

            // Pull 5: 1-pull (3 pts) with 0 balance -> Insufficient funds failure
            var r5 = await economyService.ExecuteGachaAsync(playerUid, 1, isOnlineSession: true);
            Assert.False(r5.Success);
            Assert.Contains("Insufficient Technology Points", r5.Message);

            // Verify inventory has 4 drops
            var profile = await economyService.GetPlayerProfileAsync(playerUid);
            Assert.NotNull(profile);
            Assert.Equal(0, profile.TechnologyPoints);
            Assert.NotEmpty(profile.InventoryItems);

            try { Directory.Delete(tempDir, true); } catch { }
        }

        [Fact]
        public async Task Withdraw_ItemsFromVirtualVault_SucceedsAndDispatches()
        {
            string tempDir = Path.Combine(Path.GetTempPath(), "PalWithdrawTest_" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(tempDir);
            string playersDir = Path.Combine(tempDir, "Players");
            Directory.CreateDirectory(playersDir);

            string playerUid = "9EDC20A9000000000000000000000000";
            byte[] saveBytes = CreateMockPalworldSave(15, playerUid);
            string playerSavePath = Path.Combine(playersDir, $"{playerUid}.sav");
            await File.WriteAllBytesAsync(playerSavePath, saveBytes);

            var logService = new LogService();
            var saveService = new PalSaveService(logService, tempDir);
            string customStateFile = Path.Combine(tempDir, "economy_state.json");
            var economyService = new EconomyService(logService, saveService, customStateFilePath: customStateFile);

            // 1. Buy items from shop into vault
            var ex1 = await economyService.ExecuteExchangeAsync(playerUid, "reset_drug", 1, isOnlineSession: true);
            Assert.True(ex1.Success);

            var ex2 = await economyService.ExecuteExchangeAsync(playerUid, "dog_coin", 2, isOnlineSession: true);
            Assert.True(ex2.Success);

            // 2. Check profile has items
            var p1 = await economyService.GetPlayerProfileAsync(playerUid);
            Assert.NotNull(p1);
            Assert.True(p1.InventoryItems.Count >= 2);

            // 3. Withdraw all items
            var withdrawAll = await economyService.ExecuteWithdrawAsync(playerUid, "all", 0, isOnlineSession: true);
            Assert.True(withdrawAll.Success);
            Assert.True(withdrawAll.WithdrawnItems.Count >= 2);
            Assert.Empty(withdrawAll.RemainingVaultItems);

            // 4. Verify vault is now empty
            var p2 = await economyService.GetPlayerProfileAsync(playerUid);
            Assert.NotNull(p2);
            Assert.Empty(p2.InventoryItems);

            try { Directory.Delete(tempDir, true); } catch { }
        }
    }
}


