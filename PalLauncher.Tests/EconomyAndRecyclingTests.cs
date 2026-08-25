using System;
using System.IO;
using System.IO.Compression;
using System.Text;
using System.Threading.Tasks;
using PalLauncher.Models;
using PalLauncher.Services;
using PalLauncher.Services.Interfaces;
using Xunit;

namespace PalLauncher.Tests
{
    public class EconomyAndRecyclingTests
    {
        private readonly ILogService _logService = new LogService();

        private byte[] CreateMockPalworldSave(int unusedTechPoints, int level)
        {
            // Build a small mock GVAS payload containing the IntProperty UnusedTechnologyPoint
            using var ms = new MemoryStream();
            using var writer = new BinaryWriter(ms, Encoding.ASCII);

            // GVAS Magic
            writer.Write(Encoding.ASCII.GetBytes("GVAS"));
            writer.Write(3); // Save Version
            writer.Write(new byte[16]); // Engine Version

            // Write UnusedTechnologyPoint property
            string propName = "UnusedTechnologyPoint";
            writer.Write(Encoding.ASCII.GetBytes(propName));
            writer.Write((byte)0); // Null terminator

            string propType = "IntProperty";
            writer.Write(Encoding.ASCII.GetBytes(propType));
            writer.Write((byte)0);

            writer.Write((long)4); // Data size
            writer.Write((byte)0); // Terminator

            writer.Write(unusedTechPoints); // Value

            // Write Level property
            string lvlProp = "Level";
            writer.Write(Encoding.ASCII.GetBytes(lvlProp));
            writer.Write((byte)0);
            writer.Write(Encoding.ASCII.GetBytes(propType));
            writer.Write((byte)0);
            writer.Write((long)4);
            writer.Write((byte)0);
            writer.Write(level);

            writer.Flush();
            byte[] decompressed = ms.ToArray();

            return PalSaveService.CompressPalSave(decompressed);
        }

        [Fact]
        public void ShopCatalog_ContainsAllRequiredEconomyItemsWithExactPrices()
        {
            var saveService = new PalSaveService(_logService);
            var economyService = new EconomyService(_logService,  saveService);

            var catalog = economyService.GetShopCatalog();

            Assert.NotEmpty(catalog);

            // 1. Dog Coins: 2 Tech Points
            var dogCoin = economyService.FindShopItem("dog_coin");
            Assert.NotNull(dogCoin);
            Assert.Equal(2, dogCoin.TechPointCost);

            // 2. Arena / Battle Tickets: 3 Tech Points
            var arenaTicket = economyService.FindShopItem("arena_ticket");
            Assert.NotNull(arenaTicket);
            Assert.Equal(3, arenaTicket.TechPointCost);

            // 3. Bounty Tokens / Intel: 4 Tech Points
            var bountyToken = economyService.FindShopItem("bounty_token");
            Assert.NotNull(bountyToken);
            Assert.Equal(4, bountyToken.TechPointCost);

            // 4. Pal Reverser / Training Crystal: 5 Tech Points
            var palReverser = economyService.FindShopItem("pal_reverser");
            Assert.NotNull(palReverser);
            Assert.Equal(5, palReverser.TechPointCost);

            // 5. Memory Reset Drug / Stat Elixir: 8 Tech Points
            var resetDrug = economyService.FindShopItem("memory_reset_drug");
            Assert.NotNull(resetDrug);
            Assert.Equal(8, resetDrug.TechPointCost);

            // 6. Raid Boss Summoning Slab: 10 Tech Points
            var raidSlab = economyService.FindShopItem("raid_boss_slab");
            Assert.NotNull(raidSlab);
            Assert.Equal(10, raidSlab.TechPointCost);
        }

        [Fact]
        public void RecyclingValuationTable_MatchesAllSpecifiedRates()
        {
            var saveService = new PalSaveService(_logService);
            var economyService = new EconomyService(_logService,  saveService);

            var recyclables = economyService.GetRecyclables();
            Assert.NotEmpty(recyclables);

            // Precious Pelt: 1 pt per 2 items (0.5 pt each)
            var pelt = economyService.FindRecyclableItem("precious_pelt");
            Assert.NotNull(pelt);
            Assert.Equal(0.5, pelt.PointsMultiplier);

            // Ruby: 3 pts each
            var ruby = economyService.FindRecyclableItem("ruby");
            Assert.NotNull(ruby);
            Assert.Equal(3.0, ruby.PointsMultiplier);

            // Diamond: 6 pts each
            var diamond = economyService.FindRecyclableItem("diamond");
            Assert.NotNull(diamond);
            Assert.Equal(6.0, diamond.PointsMultiplier);

            // Bronze Keys: 1 pt per key
            var bronzeKey = economyService.FindRecyclableItem("bronze_key");
            Assert.NotNull(bronzeKey);
            Assert.Equal(1, bronzeKey.MinQuantityForOnePoint);

            // Silver Key: 2 pt each
            var silverKey = economyService.FindRecyclableItem("silver_key");
            Assert.NotNull(silverKey);
            Assert.Equal(2.0, silverKey.PointsMultiplier);

            // Gold Key: 5 pts each
            var goldKey = economyService.FindRecyclableItem("gold_key");
            Assert.NotNull(goldKey);
            Assert.Equal(5.0, goldKey.PointsMultiplier);

            // Ancient Civ Parts: 1 pt per 2 parts
            var civParts = economyService.FindRecyclableItem("ancient_parts");
            Assert.NotNull(civParts);
            Assert.Equal(2, civParts.MinQuantityForOnePoint);

            // Schematics T1, T2, T3
            var t1 = economyService.FindRecyclableItem("schematic_uncommon");
            Assert.NotNull(t1);
            Assert.Equal(2.0, t1.PointsMultiplier);

            var t2 = economyService.FindRecyclableItem("schematic_rare");
            Assert.NotNull(t2);
            Assert.Equal(4.0, t2.PointsMultiplier);

            var t3 = economyService.FindRecyclableItem("schematic_epic");
            Assert.NotNull(t3);
            Assert.Equal(7.0, t3.PointsMultiplier);
        }

        [Fact]
        public async Task PalSaveParser_DecompressAndCompressPreservesIntegrity()
        {
            string tempDir = Path.Combine(Path.GetTempPath(), "PalTestSaves_" + Guid.NewGuid().ToString("N"));
            string playersDir = Path.Combine(tempDir, "Players");
            Directory.CreateDirectory(playersDir);

            try
            {
                string playerUid = "TESTPLAYERUID0000000000000000001";
                string savePath = Path.Combine(playersDir, $"{playerUid}.sav");

                byte[] mockSave = CreateMockPalworldSave(unusedTechPoints: 20, level: 35);
                await File.WriteAllBytesAsync(savePath, mockSave);

                var saveService = new PalSaveService(_logService, tempDir);

                // 1. Read profile
                var profile = await saveService.ReadPlayerProfileAsync(playerUid);
                Assert.NotNull(profile);
                Assert.Equal(20, profile.TechnologyPoints);
                Assert.Equal(35, profile.Level);

                // 2. Modify Technology Points (-5)
                bool updated = await saveService.UpdateTechnologyPointsAsync(playerUid, -5);
                Assert.True(updated);

                // 3. Read updated profile
                var updatedProfile = await saveService.ReadPlayerProfileAsync(playerUid);
                Assert.NotNull(updatedProfile);
                Assert.Equal(15, updatedProfile.TechnologyPoints);

                // 4. Verify automated backup exists
                string backupDir = Path.Combine(tempDir, "backup", "economy_backups");
                Assert.True(Directory.Exists(backupDir));
                Assert.NotEmpty(Directory.GetFiles(backupDir, $"*_{playerUid}.sav"));
            }
            finally
            {
                if (Directory.Exists(tempDir)) Directory.Delete(tempDir, true);
            }
        }

        [Fact]
        public async Task Exchange_DeductsPointsAndAddsItemsToDepot()
        {
            string tempDir = Path.Combine(Path.GetTempPath(), "PalTestExchange_" + Guid.NewGuid().ToString("N"));
            string playersDir = Path.Combine(tempDir, "Players");
            Directory.CreateDirectory(playersDir);

            try
            {
                string playerUid = "TESTEXCHANGE00000000000000000001";
                string savePath = Path.Combine(playersDir, $"{playerUid}.sav");

                byte[] mockSave = CreateMockPalworldSave(unusedTechPoints: 30, level: 40);
                await File.WriteAllBytesAsync(savePath, mockSave);

                var saveService = new PalSaveService(_logService, tempDir);
                var economyService = new EconomyService(_logService, saveService, customStateFilePath: Path.Combine(tempDir, "test_economy_state.json"));

                // 1. Exchange 2x Dog Coins (2 Tech Points each = 4 total)
                var receipt = await economyService.ExecuteExchangeAsync(playerUid, "dog_coin", 2);
                Assert.True(receipt.Success);
                Assert.Equal(4, receipt.TotalCost);
                Assert.Equal(30, receipt.PreviousTechPoints);
                Assert.Equal(26, receipt.NewTechPoints);

                // 2. Verify points deducted on save
                var profile = await economyService.GetPlayerProfileAsync(playerUid);
                Assert.NotNull(profile);
                Assert.Equal(26, profile.TechnologyPoints);
                Assert.True(profile.InventoryItems.ContainsKey("Dog Coin"));
                Assert.Equal(2, profile.InventoryItems["Dog Coin"]);

                // 3. Fail on insufficient points
                var failReceipt = await economyService.ExecuteExchangeAsync(playerUid, "raid_boss_slab", 10); // 100 points needed
                Assert.False(failReceipt.Success);
                Assert.Contains("Insufficient", failReceipt.Message);
            }
            finally
            {
                if (Directory.Exists(tempDir)) Directory.Delete(tempDir, true);
            }
        }

        [Fact]
        public async Task Recycle_ConvertsItemsIntoTechPoints()
        {
            string tempDir = Path.Combine(Path.GetTempPath(), "PalTestRecycle_" + Guid.NewGuid().ToString("N"));
            string playersDir = Path.Combine(tempDir, "Players");
            Directory.CreateDirectory(playersDir);

            try
            {
                string playerUid = "TESTRECYCLE000000000000000000001";
                string savePath = Path.Combine(playersDir, $"{playerUid}.sav");

                byte[] mockSave = CreateMockPalworldSave(unusedTechPoints: 10, level: 25);
                await File.WriteAllBytesAsync(savePath, mockSave);

                var saveService = new PalSaveService(_logService, tempDir);
                var economyService = new EconomyService(_logService, saveService, customStateFilePath: Path.Combine(tempDir, "test_economy_state.json"));

                // 1. Recycle 4x Diamonds (+6 pts each = +24 pts)
                var receipt = await economyService.ExecuteRecycleAsync(playerUid, "diamond", 4);
                Assert.True(receipt.Success);
                Assert.Equal(24, receipt.PointsAwarded);
                Assert.Equal(10, receipt.PreviousTechPoints);
                Assert.Equal(34, receipt.NewTechPoints);

                // 2. Recycle 10x Ancient Civ Parts (1 pt per 2 = +5 pts)
                var receipt2 = await economyService.ExecuteRecycleAsync(playerUid, "civparts", 10);
                Assert.True(receipt2.Success);
                Assert.Equal(5, receipt2.PointsAwarded);
                Assert.Equal(34, receipt2.PreviousTechPoints);
                Assert.Equal(39, receipt2.NewTechPoints);

                // 3. Verify character save has 39 Tech Points
                var profile = await economyService.GetPlayerProfileAsync(playerUid);
                Assert.NotNull(profile);
                Assert.Equal(39, profile.TechnologyPoints);
            }
            finally
            {
                if (Directory.Exists(tempDir)) Directory.Delete(tempDir, true);
            }
        }
        [Fact]
        public async Task Gacha_SinglePull_CostsThreePointsAndReturnsOneDrop()
        {
            string tempDir = Path.Combine(Path.GetTempPath(), "PalGachaTest1_" + Guid.NewGuid().ToString("N"));
            string playersDir = Path.Combine(tempDir, "Players");
            Directory.CreateDirectory(playersDir);

            try
            {
                string playerUid = "GachaTestPlayer1";
                string savePath = Path.Combine(playersDir, $"{playerUid}.sav");
                File.WriteAllBytes(savePath, CreateMockPalworldSave(50, 20)); // 50 Tech Points

                var saveService = new PalSaveService(_logService, tempDir);
                string stateFile = Path.Combine(tempDir, "gacha_test_state.json");
                var economyService = new EconomyService(_logService, saveService, customStateFilePath: stateFile);

                var receipt = await economyService.ExecuteGachaAsync(playerUid, 1);

                Assert.True(receipt.Success);
                Assert.Equal(1, receipt.Pulls);
                Assert.Equal(3, receipt.TotalCost);
                Assert.Equal(50, receipt.PreviousTechPoints);
                Assert.Equal(47, receipt.NewTechPoints);
                Assert.Single(receipt.Drops);
                Assert.NotEmpty(receipt.Drops[0].Name);
            }
            finally
            {
                if (Directory.Exists(tempDir)) Directory.Delete(tempDir, true);
            }
        }

        [Fact]
        public async Task Gacha_TenPull_CostsTwentyFivePointsAndReturnsCorrectDropCount()
        {
            string tempDir = Path.Combine(Path.GetTempPath(), "PalGachaTest10_" + Guid.NewGuid().ToString("N"));
            string playersDir = Path.Combine(tempDir, "Players");
            Directory.CreateDirectory(playersDir);

            try
            {
                string playerUid = "GachaTestPlayer10";
                string savePath = Path.Combine(playersDir, $"{playerUid}.sav");
                File.WriteAllBytes(savePath, CreateMockPalworldSave(100, 30)); // 100 Tech Points

                var saveService = new PalSaveService(_logService, tempDir);
                string stateFile = Path.Combine(tempDir, "gacha_test_state10.json");
                var economyService = new EconomyService(_logService, saveService, customStateFilePath: stateFile);

                var receipt = await economyService.ExecuteGachaAsync(playerUid, 10);

                Assert.True(receipt.Success);
                Assert.Equal(10, receipt.Pulls);
                Assert.Equal(25, receipt.TotalCost);
                Assert.Equal(100, receipt.PreviousTechPoints);
                Assert.Equal(75, receipt.NewTechPoints);
                Assert.Equal(10, receipt.Drops.Count);

                // All drops must have valid names and rarities
                foreach (var drop in receipt.Drops)
                {
                    Assert.NotEmpty(drop.Name);
                    Assert.True(Enum.IsDefined(typeof(GachaRarity), drop.Rarity));
                }
            }
            finally
            {
                if (Directory.Exists(tempDir)) Directory.Delete(tempDir, true);
            }
        }

        [Fact]
        public async Task Gacha_InsufficientPoints_ReturnsFailure()
        {
            string tempDir = Path.Combine(Path.GetTempPath(), "PalGachaFail_" + Guid.NewGuid().ToString("N"));
            string playersDir = Path.Combine(tempDir, "Players");
            Directory.CreateDirectory(playersDir);

            try
            {
                string playerUid = "GachaTestFail";
                string savePath = Path.Combine(playersDir, $"{playerUid}.sav");
                File.WriteAllBytes(savePath, CreateMockPalworldSave(2, 10)); // Only 2 Tech Points

                var saveService = new PalSaveService(_logService, tempDir);
                string stateFile = Path.Combine(tempDir, "gacha_fail_state.json");
                var economyService = new EconomyService(_logService, saveService, customStateFilePath: stateFile);

                // 1-pull costs 3, player only has 2
                var receipt = await economyService.ExecuteGachaAsync(playerUid, 1);

                Assert.False(receipt.Success);
                Assert.Contains("Insufficient", receipt.Message);
            }
            finally
            {
                if (Directory.Exists(tempDir)) Directory.Delete(tempDir, true);
            }
        }

        [Fact]
        public void GachaDropTable_ContainsAllFourRarityTiers()
        {
            // Verify the gacha system recognizes all 4 rarity tiers
            var rarities = Enum.GetValues(typeof(GachaRarity));
            Assert.Equal(4, rarities.Length);

            // Verify model label generation
            var commonDrop = new GachaDrop { Rarity = GachaRarity.Common, Name = "Test" };
            var uncommonDrop = new GachaDrop { Rarity = GachaRarity.Uncommon, Name = "Test" };
            var rareDrop = new GachaDrop { Rarity = GachaRarity.Rare, Name = "Test" };
            var legendaryDrop = new GachaDrop { Rarity = GachaRarity.Legendary, Name = "Test" };

            Assert.Contains("Common", commonDrop.RarityLabel);
            Assert.Contains("Uncommon", uncommonDrop.RarityLabel);
            Assert.Contains("Rare", rareDrop.RarityLabel);
            Assert.Contains("LEGENDARY", legendaryDrop.RarityLabel);

            // Verify distinct rarity colors
            Assert.NotEqual(commonDrop.RarityColor, legendaryDrop.RarityColor);
            Assert.NotEqual(uncommonDrop.RarityColor, rareDrop.RarityColor);
        }
    }
}



