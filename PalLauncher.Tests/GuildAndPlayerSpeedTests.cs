using System;
using System.IO;
using System.Text.Json;
using System.Threading.Tasks;
using PalLauncher.Models;
using PalLauncher.Services;
using Xunit;

namespace PalLauncher.Tests
{
    public class GuildAndPlayerSpeedTests
    {
        [Fact]
        public void ShopCatalog_ContainsSwiftLotusItem()
        {
            var logService = new LogService();
            var saveService = new PalSaveService(logService);
            var economyService = new EconomyService(logService, saveService);
            var catalog = economyService.GetShopCatalog();

            var swiftLotus = economyService.FindShopItem("swift_lotus");
            Assert.NotNull(swiftLotus);
            Assert.Equal("SwiftLotus", swiftLotus.ItemCode);
            Assert.Equal(3, swiftLotus.AncientPointCost);
            Assert.Equal("Ancient", swiftLotus.Category);
            Assert.Contains("Movement Speed", swiftLotus.Description);
        }

        [Fact]
        public void GuildPerksState_MoveSpeedCalculatesCorrectly()
        {
            var perks = new GuildPerksState
            {
                WorkSpeedLevel = 5,
                ExpBoostLevel = 2,
                MoveSpeedLevel = 4
            };

            Assert.Equal(5, perks.TotalWorkSpeedPercent);
            Assert.Equal(10, perks.TotalExpBoostPercent);
            Assert.Equal(8, perks.TotalMovementSpeedPercent); // 4 * 2% = 8%
        }

        [Fact]
        public void PlayerEconomyProfile_PermanentSpeedCalculatesCorrectly()
        {
            var profile = new PlayerEconomyProfile
            {
                PlayerUid = "TEST_PIONEER_001",
                SpeedUpgradeCount = 5
            };

            Assert.Equal(25, profile.PermanentSpeedBonusPercent); // 5 * 5% = 25%
        }

        [Fact]
        public async Task EconomyService_UpgradeMoveSpeedPerk_Success()
        {
            var logService = new LogService();
            var saveService = new PalSaveService(logService);
            var economyService = new EconomyService(logService, saveService);
            string testUid = "SPEED_TEST_PLAYER_" + Guid.NewGuid().ToString("N")[..8];
            await economyService.SetPlayerTechnologyPointsAsync(testUid, 30, "ancient", isOnlineSession: false);

            var receipt = await economyService.ExecuteUpgradePerkAsync(testUid, "move_speed", isOnlineSession: false);

            Assert.True(receipt.Success);
            Assert.Equal("move_speed", receipt.PerkType);
            Assert.Equal("Guild Swift Strider Speed", receipt.PerkName);
            Assert.Equal(10, receipt.AncientCost);
            Assert.True(receipt.NewPerkLevel >= 1);

            var updatedPerks = economyService.GetGuildPerks();
            Assert.True(updatedPerks.MoveSpeedLevel >= 1);
            Assert.True(updatedPerks.TotalMovementSpeedPercent >= 2);
        }

        [Fact]
        public void GuildPerksState_Serialization_PreservesMoveSpeed()
        {
            var perks = new GuildPerksState
            {
                WorkSpeedLevel = 3,
                ExpBoostLevel = 4,
                MoveSpeedLevel = 6
            };

            string json = JsonSerializer.Serialize(perks);
            var deserialized = JsonSerializer.Deserialize<GuildPerksState>(json);

            Assert.NotNull(deserialized);
            Assert.Equal(3, deserialized.WorkSpeedLevel);
            Assert.Equal(4, deserialized.ExpBoostLevel);
            Assert.Equal(6, deserialized.MoveSpeedLevel);
            Assert.Equal(12, deserialized.TotalMovementSpeedPercent);
        }
    }
}
