using System;
using System.Collections.Generic;
using System.Text.Json.Serialization;

namespace PalLauncher.Models
{
    public class ShopItem
    {
        [JsonPropertyName("id")]
        public string Id { get; set; } = string.Empty;

        [JsonPropertyName("name")]
        public string Name { get; set; } = string.Empty;

        [JsonPropertyName("techPointCost")]
        public int TechPointCost { get; set; }

        [JsonPropertyName("description")]
        public string Description { get; set; } = string.Empty;

        [JsonPropertyName("emoji")]
        public string Emoji { get; set; } = "📦";

        [JsonPropertyName("itemCode")]
        public string ItemCode { get; set; } = string.Empty;

        [JsonPropertyName("ancientPointCost")]
        public int AncientPointCost { get; set; } = 0;

        [JsonPropertyName("category")]
        public string Category { get; set; } = "Standard";
    }

    public class RecyclableItem
    {
        [JsonPropertyName("id")]
        public string Id { get; set; } = string.Empty;

        [JsonPropertyName("name")]
        public string Name { get; set; } = string.Empty;

        [JsonPropertyName("aliases")]
        public string[] Aliases { get; set; } = Array.Empty<string>();

        [JsonPropertyName("pointsMultiplier")]
        public double PointsMultiplier { get; set; } = 1.0;

        [JsonPropertyName("minQuantityForOnePoint")]
        public int MinQuantityForOnePoint { get; set; } = 1;

        [JsonPropertyName("description")]
        public string Description { get; set; } = string.Empty;

        [JsonPropertyName("emoji")]
        public string Emoji { get; set; } = "♻️";
    }

    public class PlayerEconomyProfile
    {
        [JsonPropertyName("playerUid")]
        public string PlayerUid { get; set; } = string.Empty;

        [JsonPropertyName("steamId")]
        public string SteamId { get; set; } = string.Empty;

        [JsonPropertyName("discordId")]
        public string DiscordId { get; set; } = string.Empty;

        [JsonPropertyName("discordUsername")]
        public string DiscordUsername { get; set; } = string.Empty;

        [JsonPropertyName("playerName")]
        public string PlayerName { get; set; } = "Pioneer";

        [JsonPropertyName("technologyPoints")]
        public int TechnologyPoints { get; set; }

        [JsonPropertyName("bossTechnologyPoints")]
        public int BossTechnologyPoints { get; set; }

        [JsonPropertyName("level")]
        public int Level { get; set; } = 1;

        [JsonPropertyName("exp")]
        public long Exp { get; set; }

        [JsonPropertyName("inventoryItems")]
        public Dictionary<string, int> InventoryItems { get; set; } = new(StringComparer.OrdinalIgnoreCase);

        [JsonPropertyName("speedUpgradeCount")]
        public int SpeedUpgradeCount { get; set; } = 0;

        public int PermanentSpeedBonusPercent => SpeedUpgradeCount * 5;

        [JsonPropertyName("lastUpdated")]
        public DateTime LastUpdated { get; set; } = DateTime.UtcNow;
    }

    public class ExchangeReceipt
    {
        [JsonPropertyName("success")]
        public bool Success { get; set; }

        [JsonPropertyName("transactionId")]
        public string TransactionId { get; set; } = Guid.NewGuid().ToString("N")[..8].ToUpperInvariant();

        [JsonPropertyName("itemName")]
        public string ItemName { get; set; } = string.Empty;

        [JsonPropertyName("quantity")]
        public int Quantity { get; set; }

        [JsonPropertyName("totalCost")]
        public int TotalCost { get; set; }

        [JsonPropertyName("isAncientCurrency")]
        public bool IsAncientCurrency { get; set; }

        [JsonPropertyName("previousTechPoints")]
        public int PreviousTechPoints { get; set; }

        [JsonPropertyName("newTechPoints")]
        public int NewTechPoints { get; set; }

        [JsonPropertyName("previousAncientPoints")]
        public int PreviousAncientPoints { get; set; }

        [JsonPropertyName("newAncientPoints")]
        public int NewAncientPoints { get; set; }

        [JsonPropertyName("message")]
        public string Message { get; set; } = string.Empty;

        [JsonPropertyName("timestamp")]
        public DateTime Timestamp { get; set; } = DateTime.UtcNow;
    }

    public class RecycleReceipt
    {
        [JsonPropertyName("success")]
        public bool Success { get; set; }

        [JsonPropertyName("transactionId")]
        public string TransactionId { get; set; } = Guid.NewGuid().ToString("N")[..8].ToUpperInvariant();

        [JsonPropertyName("itemName")]
        public string ItemName { get; set; } = string.Empty;

        [JsonPropertyName("quantity")]
        public int Quantity { get; set; }

        [JsonPropertyName("pointsAwarded")]
        public int PointsAwarded { get; set; }

        [JsonPropertyName("previousTechPoints")]
        public int PreviousTechPoints { get; set; }

        [JsonPropertyName("newTechPoints")]
        public int NewTechPoints { get; set; }

        [JsonPropertyName("message")]
        public string Message { get; set; } = string.Empty;

        [JsonPropertyName("timestamp")]
        public DateTime Timestamp { get; set; } = DateTime.UtcNow;
    }

    public class WithdrawReceipt
    {
        [JsonPropertyName("success")]
        public bool Success { get; set; }

        [JsonPropertyName("transactionId")]
        public string TransactionId { get; set; } = Guid.NewGuid().ToString("N")[..8].ToUpperInvariant();

        [JsonPropertyName("withdrawnItems")]
        public Dictionary<string, int> WithdrawnItems { get; set; } = new(StringComparer.OrdinalIgnoreCase);

        [JsonPropertyName("remainingVaultItems")]
        public Dictionary<string, int> RemainingVaultItems { get; set; } = new(StringComparer.OrdinalIgnoreCase);

        [JsonPropertyName("message")]
        public string Message { get; set; } = string.Empty;

        [JsonPropertyName("timestamp")]
        public DateTime Timestamp { get; set; } = DateTime.UtcNow;
    }

    public class TransmuteReceipt
    {
        [JsonPropertyName("success")]
        public bool Success { get; set; }

        [JsonPropertyName("transactionId")]
        public string TransactionId { get; set; } = Guid.NewGuid().ToString("N")[..8].ToUpperInvariant();

        [JsonPropertyName("ancientPointsSpent")]
        public int AncientPointsSpent { get; set; }

        [JsonPropertyName("techPointsGained")]
        public int TechPointsGained { get; set; }

        [JsonPropertyName("previousAncientPoints")]
        public int PreviousAncientPoints { get; set; }

        [JsonPropertyName("newAncientPoints")]
        public int NewAncientPoints { get; set; }

        [JsonPropertyName("remainingAncientPoints")]
        public int RemainingAncientPoints
        {
            get => NewAncientPoints;
            set => NewAncientPoints = value;
        }

        [JsonPropertyName("previousTechPoints")]
        public int PreviousTechPoints { get; set; }

        [JsonPropertyName("newTechPoints")]
        public int NewTechPoints { get; set; }

        [JsonPropertyName("message")]
        public string Message { get; set; } = string.Empty;

        [JsonPropertyName("timestamp")]
        public DateTime Timestamp { get; set; } = DateTime.UtcNow;
    }

    public class BasePerkReceipt
    {
        [JsonPropertyName("success")]
        public bool Success { get; set; }

        [JsonPropertyName("transactionId")]
        public string TransactionId { get; set; } = Guid.NewGuid().ToString("N")[..8].ToUpperInvariant();

        [JsonPropertyName("perkType")]
        public string PerkType { get; set; } = string.Empty;

        [JsonPropertyName("perkName")]
        public string PerkName { get; set; } = string.Empty;

        [JsonPropertyName("ancientCost")]
        public int AncientCost { get; set; }

        [JsonPropertyName("newPerkLevel")]
        public int NewPerkLevel { get; set; }

        [JsonPropertyName("perkBonusDescription")]
        public string PerkBonusDescription { get; set; } = string.Empty;

        [JsonPropertyName("remainingAncientPoints")]
        public int RemainingAncientPoints { get; set; }

        [JsonPropertyName("message")]
        public string Message { get; set; } = string.Empty;

        [JsonPropertyName("timestamp")]
        public DateTime Timestamp { get; set; } = DateTime.UtcNow;
    }

    public class GuildPerksState
    {
        [JsonPropertyName("workSpeedLevel")]
        public int WorkSpeedLevel { get; set; } = 0;

        [JsonPropertyName("expBoostLevel")]
        public int ExpBoostLevel { get; set; } = 0;

        [JsonPropertyName("moveSpeedLevel")]
        public int MoveSpeedLevel { get; set; } = 0;

        public int TotalWorkSpeedPercent => WorkSpeedLevel * 1;
        public int TotalMovementSpeedPercent => MoveSpeedLevel * 2;
        public int TotalExpBoostPercent => ExpBoostLevel * 5;
    }

    public enum GachaRarity
    {
        Common,
        Uncommon,
        Rare,
        Legendary
    }

    public class GachaDrop
    {
        [JsonPropertyName("name")]
        public string Name { get; set; } = string.Empty;

        [JsonPropertyName("rarity")]
        public GachaRarity Rarity { get; set; }

        [JsonPropertyName("emoji")]
        public string Emoji { get; set; } = "📦";

        [JsonPropertyName("quantity")]
        public int Quantity { get; set; } = 1;

        public string RarityLabel => Rarity switch
        {
            GachaRarity.Common => "⚪ Common",
            GachaRarity.Uncommon => "🟢 Uncommon",
            GachaRarity.Rare => "🔵 Rare",
            GachaRarity.Legendary => "🟡 LEGENDARY",
            _ => "⚪ Common"
        };

        public int RarityColor => Rarity switch
        {
            GachaRarity.Common => 0xAAAAAA,
            GachaRarity.Uncommon => 0x00CC66,
            GachaRarity.Rare => 0x3399FF,
            GachaRarity.Legendary => 0xFFD700,
            _ => 0xAAAAAA
        };
    }

    public class GachaReceipt
    {
        [JsonPropertyName("success")]
        public bool Success { get; set; }

        [JsonPropertyName("transactionId")]
        public string TransactionId { get; set; } = Guid.NewGuid().ToString("N")[..8].ToUpperInvariant();

        [JsonPropertyName("pulls")]
        public int Pulls { get; set; }

        [JsonPropertyName("totalCost")]
        public int TotalCost { get; set; }

        [JsonPropertyName("currencyUsed")]
        public string CurrencyUsed { get; set; } = "tech_points";

        [JsonPropertyName("previousTechPoints")]
        public int PreviousTechPoints { get; set; }

        [JsonPropertyName("newTechPoints")]
        public int NewTechPoints { get; set; }

        [JsonPropertyName("previousAncientPoints")]
        public int PreviousAncientPoints { get; set; }

        [JsonPropertyName("newAncientPoints")]
        public int NewAncientPoints { get; set; }

        [JsonPropertyName("drops")]
        public List<GachaDrop> Drops { get; set; } = new();

        [JsonPropertyName("hasLegendary")]
        public bool HasLegendary { get; set; }

        [JsonPropertyName("pityTriggered")]
        public bool PityTriggered { get; set; }

        [JsonPropertyName("message")]
        public string Message { get; set; } = string.Empty;

        [JsonPropertyName("timestamp")]
        public DateTime Timestamp { get; set; } = DateTime.UtcNow;
    }

    public class SetPointsReceipt
    {
        [JsonPropertyName("success")]
        public bool Success { get; set; }

        [JsonPropertyName("playerUid")]
        public string PlayerUid { get; set; } = string.Empty;

        [JsonPropertyName("playerName")]
        public string PlayerName { get; set; } = string.Empty;

        [JsonPropertyName("currency")]
        public string Currency { get; set; } = "tech_points";

        [JsonPropertyName("previousPoints")]
        public int PreviousPoints { get; set; }

        [JsonPropertyName("newPoints")]
        public int NewPoints { get; set; }

        [JsonPropertyName("delta")]
        public int Delta { get; set; }

        [JsonPropertyName("isAbsoluteSet")]
        public bool IsAbsoluteSet { get; set; }

        [JsonPropertyName("message")]
        public string Message { get; set; } = string.Empty;

        [JsonPropertyName("timestamp")]
        public DateTime Timestamp { get; set; } = DateTime.UtcNow;
    }
}
