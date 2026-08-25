using System;
using System.Collections.Generic;
using System.IO;
using System.Linq;
using System.Text.Json;
using System.Threading.Tasks;
using PalLauncher.Models;
using PalLauncher.Services.Interfaces;

namespace PalLauncher.Services
{
    public interface IEconomyService
    {
        IReadOnlyList<ShopItem> GetShopCatalog();
        IReadOnlyList<RecyclableItem> GetRecyclables();
        Task<PlayerEconomyProfile?> GetPlayerProfileAsync(string playerUid);
        Task<ExchangeReceipt> ExecuteExchangeAsync(string playerUid, string itemQuery, int quantity, bool isOnlineSession = false);
        Task<RecycleReceipt> ExecuteRecycleAsync(string playerUid, string itemQuery, int quantity, bool isOnlineSession = false);
        Task<GachaReceipt> ExecuteGachaAsync(string playerUid, int pulls, bool isOnlineSession = false);
        Task<WithdrawReceipt> ExecuteWithdrawAsync(string playerUid, string? itemQuery = null, int quantity = 0, bool isOnlineSession = false);
        ShopItem? FindShopItem(string query);
        RecyclableItem? FindRecyclableItem(string query);
        void LinkDiscordUser(string discordUserId, string playerUid);
        string GetLinkedPlayerUid(string discordUserId);
    }

    public class EconomyService : IEconomyService
    {
        private readonly ILogService _logService;
        private readonly IPalSaveService _saveService;
        private readonly IGuildLicenseService _licenseService;
        private readonly string _stateFilePath;
        private readonly Dictionary<string, string> _discordToPlayerMap = new();
        private readonly Dictionary<string, Dictionary<string, int>> _playerInventories = new(StringComparer.OrdinalIgnoreCase);
        private readonly Dictionary<string, int> _playerTechPoints = new(StringComparer.OrdinalIgnoreCase);
        private readonly object _lock = new();

        private static readonly List<ShopItem> _shopCatalog = new()
        {
            new ShopItem
            {
                Id = "dog_coin",
                Name = "Dog Coin",
                ItemCode = "DogCoin",
                TechPointCost = 2,
                Description = "Ancient currency required to purchase rare accessories, stats, and relics from Medal Merchants.",
                Emoji = "🪙"
            },
            new ShopItem
            {
                Id = "arena_ticket",
                Name = "Arena / Battle Ticket",
                ItemCode = "ArenaTicket",
                TechPointCost = 3,
                Description = "Exclusive admission pass for Pal Arena battles, raid trials, and colosseum duels.",
                Emoji = "🎟️"
            },
            new ShopItem
            {
                Id = "bounty_token",
                Name = "Bounty Token / Intel",
                ItemCode = "BountyToken",
                TechPointCost = 4,
                Description = "High-priority Syndicate bounty intel used to summon elite boss encounters and redeem faction loot.",
                Emoji = "📜"
            },
            new ShopItem
            {
                Id = "pal_reverser",
                Name = "Pal Reverser / Training Crystal",
                ItemCode = "PalReverser",
                TechPointCost = 5,
                Description = "Mystic crystalline catalyst used to re-roll, optimize, and reverse Pal passives & combat traits.",
                Emoji = "🔮"
            },
            new ShopItem
            {
                Id = "memory_reset_drug",
                Name = "Memory Reset Drug / Stat Elixir",
                ItemCode = "MemoryResetDrug",
                TechPointCost = 8,
                Description = "Pharmaceutical elixir that completely resets player character status points for full respeccing.",
                Emoji = "🧪"
            },
            new ShopItem
            {
                Id = "raid_boss_slab",
                Name = "Raid Boss Summoning Slab",
                ItemCode = "RaidBossSlab",
                TechPointCost = 10,
                Description = "Complete summoning slab required to initiate Bellanoir and high-tier endgame raid bosses.",
                Emoji = "🗿"
            },
            new ShopItem
            {
                Id = "passive_t1",
                Name = "Tier 1 Passive (Utility/Starter)",
                ItemCode = "PassiveT1",
                TechPointCost = 2,
                Description = "Modded Passive Skill Implant (Utility/Starter). In-game sync: 100,000 G.",
                Emoji = "💉"
            },
            new ShopItem
            {
                Id = "passive_t2",
                Name = "Tier 2 Passive (Combat/Speed)",
                ItemCode = "PassiveT2",
                TechPointCost = 5,
                Description = "Modded Passive Skill Implant (Combat/Speed). In-game sync: 500,000 G.",
                Emoji = "💉"
            },
            new ShopItem
            {
                Id = "passive_t3",
                Name = "Tier 3 Passive (Artisan/Musclehead)",
                ItemCode = "PassiveT3",
                TechPointCost = 10,
                Description = "Modded Passive Skill Implant (Artisan/Musclehead). In-game sync: 2,000,000 G.",
                Emoji = "💉"
            },
            new ShopItem
            {
                Id = "passive_t4",
                Name = "Tier 4 Passive (High-Tier Mod Traits)",
                ItemCode = "PassiveT4",
                TechPointCost = 18,
                Description = "Modded Passive Skill Implant (High-Tier Mod Traits). In-game sync: 6,000,000 G.",
                Emoji = "💉"
            },
            new ShopItem
            {
                Id = "passive_t5",
                Name = "Tier 5 Passive (World Tree/Apex)",
                ItemCode = "PassiveT5",
                TechPointCost = 30,
                Description = "Modded Passive Skill Implant (World Tree/Apex). In-game sync: 15,000,000 G.",
                Emoji = "💉"
            },
            new ShopItem
            {
                Id = "passive_apex",
                Name = "Mutations / Apex Traits",
                ItemCode = "PassiveApex",
                TechPointCost = 50,
                Description = "Ultimate Modded Passive Skill Implant (Mutations / Apex). In-game sync: 30,000,000 G.",
                Emoji = "🧬"
            },
            new ShopItem
            {
                Id = "guild_base_slot",
                Name = "Guild Base Expansion",
                ItemCode = "GuildBaseSlot",
                TechPointCost = 40,
                Description = "Adds +1 extra Base Camp slot to your Guild's maximum allowance.",
                Emoji = "⛺"
            },
            new ShopItem
            {
                Id = "breeding_pen_slot",
                Name = "Breeding Pen Expansion",
                ItemCode = "BreedingPenSlot",
                TechPointCost = 25,
                Description = "Adds +1 extra Breeding Pen / Egg Hatcher slot to your Guild's maximum allowance.",
                Emoji = "🥚"
            },
            new ShopItem
            {
                Id = "ranch_slot",
                Name = "Ranch Expansion",
                ItemCode = "RanchSlot",
                TechPointCost = 15,
                Description = "Adds +1 extra Ranch / Pasture slot to your Guild's maximum allowance.",
                Emoji = "🐑"
            }
        };

        private static readonly List<RecyclableItem> _recyclables = new()
        {
            new RecyclableItem
            {
                Id = "precious_pelt",
                Name = "Precious Pelt",
                Aliases = new[] { "pelt", "precious_pelt", "preciouspelt" },
                PointsMultiplier = 0.5,
                MinQuantityForOnePoint = 2,
                Description = "Pristine monster pelt.",
                Emoji = "🥋"
            },
            new RecyclableItem
            {
                Id = "precious_feather",
                Name = "Precious Feather",
                Aliases = new[] { "feather", "precious_feather", "preciousfeather" },
                PointsMultiplier = 0.5,
                MinQuantityForOnePoint = 2,
                Description = "Gleaming avian feather.",
                Emoji = "🪶"
            },
            new RecyclableItem
            {
                Id = "precious_claw",
                Name = "Precious Claw",
                Aliases = new[] { "claw", "precious_claw", "preciousclaw" },
                PointsMultiplier = 0.5,
                MinQuantityForOnePoint = 2,
                Description = "Razor-sharp predator claw.",
                Emoji = "🐾"
            },
            new RecyclableItem
            {
                Id = "precious_entrails",
                Name = "Precious Entrails",
                Aliases = new[] { "entrails", "precious_entrails", "preciousentrails" },
                PointsMultiplier = 3.0,
                MinQuantityForOnePoint = 1,
                Description = "Valuable organ component.",
                Emoji = "🫀"
            },
            new RecyclableItem
            {
                Id = "dragon_stone",
                Name = "Dragon Stone",
                Aliases = new[] { "dragonstone", "dragon_stone" },
                PointsMultiplier = 3.0,
                MinQuantityForOnePoint = 1,
                Description = "Mineral infused with draconic essence.",
                Emoji = "🐉"
            },
            new RecyclableItem
            {
                Id = "ruby",
                Name = "Ruby",
                Aliases = new[] { "ruby", "rubies" },
                PointsMultiplier = 3.0,
                MinQuantityForOnePoint = 1,
                Description = "Lustrous crimson gemstone.",
                Emoji = "🔴"
            },
            new RecyclableItem
            {
                Id = "sapphire",
                Name = "Sapphire",
                Aliases = new[] { "sapphire", "sapphires" },
                PointsMultiplier = 3.0,
                MinQuantityForOnePoint = 1,
                Description = "Brilliant azure jewel.",
                Emoji = "🔷"
            },
            new RecyclableItem
            {
                Id = "emerald",
                Name = "Emerald",
                Aliases = new[] { "emerald", "emeralds" },
                PointsMultiplier = 3.0,
                MinQuantityForOnePoint = 1,
                Description = "Radiant green mineral gem.",
                Emoji = "🟢"
            },
            new RecyclableItem
            {
                Id = "diamond",
                Name = "Diamond",
                Aliases = new[] { "diamond", "diamonds" },
                PointsMultiplier = 6.0,
                MinQuantityForOnePoint = 1,
                Description = "Flawless sparkling diamond.",
                Emoji = "💎"
            },
            new RecyclableItem
            {
                Id = "bronze_key",
                Name = "Bronze Key",
                Aliases = new[] { "bronzekey", "bronze_key", "bronze" },
                PointsMultiplier = 1.0,
                MinQuantityForOnePoint = 1,
                Description = "Common dungeon key.",
                Emoji = "🗝️"
            },
            new RecyclableItem
            {
                Id = "silver_key",
                Name = "Silver Key",
                Aliases = new[] { "silverkey", "silver_key", "silver" },
                PointsMultiplier = 2.0,
                MinQuantityForOnePoint = 1,
                Description = "Mid-tier chest key.",
                Emoji = "🔑"
            },
            new RecyclableItem
            {
                Id = "gold_key",
                Name = "Gold Key",
                Aliases = new[] { "goldkey", "gold_key", "gold" },
                PointsMultiplier = 5.0,
                MinQuantityForOnePoint = 1,
                Description = "Rare gilded chest key.",
                Emoji = "🪙"
            },
            new RecyclableItem
            {
                Id = "ancient_parts",
                Name = "Ancient Civilization Parts",
                Aliases = new[] { "ancientparts", "civparts", "parts", "ancient_parts", "ancient_civilization_parts" },
                PointsMultiplier = 0.5,
                MinQuantityForOnePoint = 2,
                Description = "Salvaged ancient machinery.",
                Emoji = "⚙️"
            },
            new RecyclableItem
            {
                Id = "slab_fragment",
                Name = "Excess Raid Slab Fragment",
                Aliases = new[] { "fragment", "slabfragment", "slab_fragment", "fragments" },
                PointsMultiplier = 2.0,
                MinQuantityForOnePoint = 1,
                Description = "Broken slab component.",
                Emoji = "🧩"
            },
            new RecyclableItem
            {
                Id = "schematic_uncommon",
                Name = "Uncommon Schematic (Tier 1)",
                Aliases = new[] { "tier1", "uncommon_schematic", "uncommon", "t1" },
                PointsMultiplier = 2.0,
                MinQuantityForOnePoint = 1,
                Description = "Green tier crafting blueprint.",
                Emoji = "📗"
            },
            new RecyclableItem
            {
                Id = "schematic_rare",
                Name = "Rare Schematic (Tier 2)",
                Aliases = new[] { "tier2", "rare_schematic", "rare", "t2" },
                PointsMultiplier = 4.0,
                MinQuantityForOnePoint = 1,
                Description = "Blue tier crafting blueprint.",
                Emoji = "📘"
            },
            new RecyclableItem
            {
                Id = "schematic_epic",
                Name = "Epic Schematic (Tier 3)",
                Aliases = new[] { "tier3", "epic_schematic", "epic", "t3" },
                PointsMultiplier = 7.0,
                MinQuantityForOnePoint = 1,
                Description = "Purple tier legendary blueprint.",
                Emoji = "📕"
            }
        };

        public EconomyService(ILogService logService, IPalSaveService saveService, IGuildLicenseService? licenseService = null, string? customStateFilePath = null)
        {
            _logService = logService;
            _saveService = saveService;
            _licenseService = licenseService ?? new GuildLicenseService(_logService, _saveService);

            if (!string.IsNullOrWhiteSpace(customStateFilePath))
            {
                _stateFilePath = customStateFilePath;
            }
            else
            {
                string dir = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    "PalLauncher");
                if (!Directory.Exists(dir)) Directory.CreateDirectory(dir);
                _stateFilePath = Path.Combine(dir, "economy_state.json");
            }
            LoadState();
        }

        public IReadOnlyList<ShopItem> GetShopCatalog() => _shopCatalog;
        public IReadOnlyList<RecyclableItem> GetRecyclables() => _recyclables;

        public ShopItem? FindShopItem(string query)
        {
            if (string.IsNullOrWhiteSpace(query)) return null;
            string clean = query.Trim().ToLowerInvariant().Replace(" ", "").Replace("_", "").Replace("-", "");

            return _shopCatalog.FirstOrDefault(i =>
                i.Id.Replace("_", "").Equals(clean, StringComparison.OrdinalIgnoreCase) ||
                i.Name.ToLowerInvariant().Replace(" ", "").Replace("/", "").Contains(clean) ||
                i.ItemCode.ToLowerInvariant().Equals(clean, StringComparison.OrdinalIgnoreCase));
        }

        public RecyclableItem? FindRecyclableItem(string query)
        {
            if (string.IsNullOrWhiteSpace(query)) return null;
            string clean = query.Trim().ToLowerInvariant().Replace(" ", "").Replace("_", "").Replace("-", "");

            return _recyclables.FirstOrDefault(r =>
                r.Id.Replace("_", "").Equals(clean, StringComparison.OrdinalIgnoreCase) ||
                r.Name.ToLowerInvariant().Replace(" ", "").Replace("/", "").Contains(clean) ||
                r.Aliases.Any(a => a.Replace("_", "").Equals(clean, StringComparison.OrdinalIgnoreCase)));
        }

        public void LinkDiscordUser(string discordUserId, string playerUid)
        {
            lock (_lock)
            {
                _discordToPlayerMap[discordUserId] = playerUid;
                SaveState();
            }
        }

        public string GetLinkedPlayerUid(string discordUserId)
        {
            lock (_lock)
            {
                if (_discordToPlayerMap.TryGetValue(discordUserId, out var uid))
                {
                    return uid;
                }
            }

            // Check account-links.json
            try
            {
                string linksDir = Path.GetDirectoryName(_stateFilePath) ?? Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    "PalLauncher");
                string accountLinksFile = Path.Combine(linksDir, "account-links.json");

                if (File.Exists(accountLinksFile))
                {
                    string json = File.ReadAllText(accountLinksFile);
                    using var doc = JsonDocument.Parse(json);
                    if (doc.RootElement.TryGetProperty(discordUserId, out var userObj))
                    {
                        if (userObj.TryGetProperty("playerUid", out var pUid) && !string.IsNullOrWhiteSpace(pUid.GetString()))
                        {
                            return pUid.GetString()!;
                        }
                        if (userObj.TryGetProperty("steamId64", out var sId) && !string.IsNullOrWhiteSpace(sId.GetString()))
                        {
                            return _saveService.ResolvePlayerUid(sId.GetString()!);
                        }
                    }
                }
            }
            catch { }

            return _saveService.ResolvePlayerUid(null);
        }

        public async Task<PlayerEconomyProfile?> GetPlayerProfileAsync(string playerUid)
        {
            string uid = _saveService.ResolvePlayerUid(playerUid);
            var profile = await _saveService.ReadPlayerProfileAsync(uid);
            if (profile == null) return null;

            lock (_lock)
            {
                if (_playerTechPoints.TryGetValue(uid, out int pts) ||
                    (!string.IsNullOrWhiteSpace(playerUid) && _playerTechPoints.TryGetValue(playerUid, out pts)))
                {
                    profile.TechnologyPoints = pts;
                }
                else
                {
                    _playerTechPoints[uid] = profile.TechnologyPoints;
                    if (!string.IsNullOrWhiteSpace(playerUid)) _playerTechPoints[playerUid] = profile.TechnologyPoints;
                }

                if (_playerInventories.TryGetValue(uid, out var inv) ||
                    (!string.IsNullOrWhiteSpace(playerUid) && _playerInventories.TryGetValue(playerUid, out inv)))
                {
                    profile.InventoryItems = new Dictionary<string, int>(inv);
                }
            }
            return profile;
        }

        private void QueueDelivery(string playerUid, string action, string itemCode, int quantity, int techPointsDelta)
        {
            string localAppData = Environment.GetEnvironmentVariable("LOCALAPPDATA") ?? Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            string dir = Path.Combine(localAppData, "PalLauncher");
            if (!Directory.Exists(dir)) Directory.CreateDirectory(dir);
            string queueFile = Path.Combine(dir, "pending-deliveries.csv");

            string serverQueuePath = @"C:\SteamLibrary\steamapps\common\PalServer\Pal\Binaries\Win64\ue4ss\Mods\PalOdysseyOptimizer\pending-deliveries.csv";
            string serverQueueDir = Path.GetDirectoryName(serverQueuePath)!;

            lock (_lock)
            {
                string line = $"{playerUid},{action},{itemCode},{quantity},{techPointsDelta}\n";
                File.AppendAllText(queueFile, line);

                try
                {
                    if (Directory.Exists(serverQueueDir))
                    {
                        File.AppendAllText(serverQueuePath, line);
                    }
                }
                catch { }
            }
        }

        public async Task<ExchangeReceipt> ExecuteExchangeAsync(string playerUid, string itemQuery, int quantity, bool isOnlineSession = false)
        {
            if (quantity <= 0) quantity = 1;
            string uid = _saveService.ResolvePlayerUid(playerUid);

            var item = FindShopItem(itemQuery);
            if (item == null)
            {
                return new ExchangeReceipt
                {
                    Success = false,
                    Message = $"Item `{itemQuery}` not found in the Shop Catalog. Use `/shop` to view available items."
                };
            }

            int totalCost = item.TechPointCost * quantity;
            var profile = await _saveService.ReadPlayerProfileAsync(uid);
            if (profile == null)
            {
                return new ExchangeReceipt
                {
                    Success = false,
                    Message = $"Could not load character save for Pioneer UID `{uid}`."
                };
            }

            bool isInfra = item.ItemCode == "GuildBaseSlot" || item.ItemCode == "BreedingPenSlot" || item.ItemCode == "RanchSlot";
            if (isInfra)
            {
                string? guildId = await _licenseService.ResolveGuildIdAsync(uid);
                if (string.IsNullOrWhiteSpace(guildId))
                {
                    return new ExchangeReceipt
                    {
                        Success = false,
                        Message = "Transaction failed. Could not locate your Guild in Level.sav. Ensure you are in a guild and the server has saved."
                    };
                }

                // 1. Try Guild Bank First
                bool bankPurchase = await _licenseService.PurchaseInfrastructureAsync(guildId, uid, item.ItemCode, totalCost);
                if (bankPurchase)
                {
                    _logService.LogSuccess($"[EXCHANGE] Guild {guildId} purchased {quantity}x {item.Name} using Guild Bank funds.", "Economy");
                    return new ExchangeReceipt
                    {
                        Success = true,
                        ItemName = item.Name,
                        Quantity = quantity,
                        TotalCost = totalCost,
                        PreviousTechPoints = profile.TechnologyPoints, // Personal points didn't change
                        NewTechPoints = profile.TechnologyPoints,
                        Message = $"Successfully purchased {quantity}x **{item.Name}** for {totalCost} Tech Points from the **Guild Bank**! The infrastructure has been expanded."
                    };
                }
                
                // 2. If Bank failed, we fall back to personal funds
                if (profile.TechnologyPoints < totalCost)
                {
                    return new ExchangeReceipt
                    {
                        Success = false,
                        Message = $"Insufficient funds in both Guild Bank and your personal wallet. You need **{totalCost} pts**."
                    };
                }

                // 3. Check caps by trying to "purchase" with 0 cost from the bank (which is guaranteed to pass funds check if balance >= 0)
                bool personalPurchase = await _licenseService.PurchaseInfrastructureAsync(guildId, uid, item.ItemCode, 0);
                if (!personalPurchase)
                {
                    return new ExchangeReceipt
                    {
                        Success = false,
                        Message = "Transaction failed. You have reached the maximum infrastructure limit for this type."
                    };
                }
                
                // Cap allowed it, and personal purchase claimed the slot. Now deduct personal points.
                bool updatedPersonal = await _saveService.UpdateTechnologyPointsAsync(uid, -totalCost);
                if (!updatedPersonal)
                {
                    // Fallback
                    return new ExchangeReceipt
                    {
                        Success = false,
                        Message = "Failed to update save file. Transaction cancelled."
                    };
                }

                return new ExchangeReceipt
                {
                    Success = true,
                    ItemName = item.Name,
                    Quantity = quantity,
                    TotalCost = totalCost,
                    PreviousTechPoints = profile.TechnologyPoints,
                    NewTechPoints = profile.TechnologyPoints - totalCost,
                    Message = $"Successfully purchased {quantity}x **{item.Name}** for {totalCost} Tech Points using your **Personal Wallet**. The infrastructure has been expanded."
                };
            }

            int currentPoints;
            lock (_lock)
            {
                if (!_playerTechPoints.TryGetValue(uid, out currentPoints) &&
                    (string.IsNullOrWhiteSpace(playerUid) || !_playerTechPoints.TryGetValue(playerUid, out currentPoints)))
                {
                    currentPoints = profile.TechnologyPoints;
                }
            }

            if (currentPoints < totalCost)
            {
                return new ExchangeReceipt
                {
                    Success = false,
                    ItemName = item.Name,
                    Quantity = quantity,
                    TotalCost = totalCost,
                    PreviousTechPoints = currentPoints,
                    NewTechPoints = currentPoints,
                    Message = $"Insufficient Technology Points. You need **{totalCost} pts** ({item.TechPointCost} × {quantity}), but currently have **{currentPoints} pts**."
                };
            }

            int newPoints = currentPoints - totalCost;

            // Credit items to Player Virtual Vault / Inventory & deduct Tech Points
            lock (_lock)
            {
                _playerTechPoints[uid] = newPoints;
                if (!string.IsNullOrWhiteSpace(playerUid)) _playerTechPoints[playerUid] = newPoints;

                if (!_playerInventories.TryGetValue(uid, out var inv))
                {
                    inv = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
                    _playerInventories[uid] = inv;
                }

                inv[item.Name] = inv.GetValueOrDefault(item.Name, 0) + quantity;
                SaveState();
            }

            if (isOnlineSession)
            {
                QueueDelivery(uid, "Exchange", item.ItemCode, quantity, -totalCost);
            }
            else
            {
                await _saveService.UpdateTechnologyPointsAsync(uid, -totalCost);
            }

            _logService.LogSuccess($"[EXCHANGE] {uid} purchased {quantity}x {item.Name} for {totalCost} Tech Points.", "Economy");

            return new ExchangeReceipt
            {
                Success = true,
                ItemName = item.Name,
                Quantity = quantity,
                TotalCost = totalCost,
                PreviousTechPoints = currentPoints,
                NewTechPoints = newPoints,
                Message = $"Successfully exchanged **{totalCost} Tech Points** for **{quantity}x {item.Name}** {item.Emoji}!"
            };
        }

        public async Task<RecycleReceipt> ExecuteRecycleAsync(string playerUid, string itemQuery, int quantity, bool isOnlineSession = false)
        {
            if (quantity <= 0) quantity = 1;
            string uid = _saveService.ResolvePlayerUid(playerUid);

            var item = FindRecyclableItem(itemQuery);
            if (item == null)
            {
                return new RecycleReceipt
                {
                    Success = false,
                    Message = $"Item `{itemQuery}` is not eligible for recycling. Use `/shop` to view recycling rates."
                };
            }

            // Calculate awarded Tech Points: Points = floor(quantity * multiplier)
            int pointsEarned = (int)Math.Floor(quantity * item.PointsMultiplier);
            if (pointsEarned <= 0)
            {
                return new RecycleReceipt
                {
                    Success = false,
                    ItemName = item.Name,
                    Quantity = quantity,
                    PointsAwarded = 0,
                    Message = $"Minimum quantity for **{item.Name}** is **{item.MinQuantityForOnePoint} items** to earn 1 Tech Point."
                };
            }

            var profile = await _saveService.ReadPlayerProfileAsync(uid);
            if (profile == null)
            {
                return new RecycleReceipt
                {
                    Success = false,
                    Message = $"Could not load character save for Pioneer UID `{uid}`."
                };
            }

            int currentPoints;
            lock (_lock)
            {
                if (!_playerTechPoints.TryGetValue(uid, out currentPoints) &&
                    (string.IsNullOrWhiteSpace(playerUid) || !_playerTechPoints.TryGetValue(playerUid, out currentPoints)))
                {
                    currentPoints = profile.TechnologyPoints;
                }
            }

            int newPoints = currentPoints + pointsEarned;

            // Deduct items from Player Vault if present & add Tech Points
            lock (_lock)
            {
                _playerTechPoints[uid] = newPoints;
                if (!string.IsNullOrWhiteSpace(playerUid)) _playerTechPoints[playerUid] = newPoints;

                if (_playerInventories.TryGetValue(uid, out var inv) ||
                    (!string.IsNullOrWhiteSpace(playerUid) && _playerInventories.TryGetValue(playerUid, out inv)))
                {
                    if (inv.ContainsKey(item.Name))
                    {
                        inv[item.Name] = Math.Max(0, inv[item.Name] - quantity);
                        if (inv[item.Name] == 0) inv.Remove(item.Name);
                    }
                }
                SaveState();
            }

            if (isOnlineSession)
            {
                QueueDelivery(uid, "Recycle", item.Id, quantity, pointsEarned);
            }
            else
            {
                await _saveService.UpdateTechnologyPointsAsync(uid, pointsEarned);
            }

            _logService.LogSuccess($"[RECYCLE] {uid} recycled {quantity}x {item.Name} for +{pointsEarned} Tech Points.", "Economy");

            return new RecycleReceipt
            {
                Success = true,
                ItemName = item.Name,
                Quantity = quantity,
                PointsAwarded = pointsEarned,
                PreviousTechPoints = currentPoints,
                NewTechPoints = newPoints,
                Message = $"Recycled **{quantity}x {item.Name}** {item.Emoji} into **+{pointsEarned} Technology Points**!"
            };
        }

        // ===== GACHA: Relic Mystery Box Drop Table =====
        private static readonly (GachaRarity Rarity, string Name, string Emoji, int Qty)[] _gachaDropTable = new[]
        {
            // Common (50% total weight = 4 entries)
            (GachaRarity.Common, "Mega/Giga Spheres", "⚪", 50),
            (GachaRarity.Common, "High-Grade Tech Manual", "📙", 2),
            (GachaRarity.Common, "Gold Coins", "🪙", 10000),
            (GachaRarity.Common, "Cake", "🎂", 5),

            // Uncommon (30% total weight = 4 entries)
            (GachaRarity.Uncommon, "Dog Coin", "🪙", 2),
            (GachaRarity.Uncommon, "Arena Ticket", "🎟️", 1),
            (GachaRarity.Uncommon, "Bounty Token", "📜", 1),
            (GachaRarity.Uncommon, "Large Pal Soul", "💜", 2),

            // Rare (15% total weight = 3 entries)
            (GachaRarity.Rare, "Pal Reverser / Training Crystal", "🔮", 1),
            (GachaRarity.Rare, "Memory Reset Drug", "🧪", 1),
            (GachaRarity.Rare, "Epic Skill Fruit", "🍎", 1),

            // Legendary (5% total weight = 3 entries)
            (GachaRarity.Legendary, "Legendary Schematic IV (Rocket Launcher / Assault Rifle)", "⭐", 1),
            (GachaRarity.Legendary, "Raid Boss Summon Slab (Bellanoir Libero / Blazamut Ryu)", "🗿", 1),
            (GachaRarity.Legendary, "Huge Dragon/Dark Egg", "🥚", 1)
        };

        private static readonly Random _gachaRng = new();

        private GachaDrop RollSingleGachaDrop(bool forceRareOrHigher = false)
        {
            int roll = _gachaRng.Next(100);
            GachaRarity rarity;

            if (forceRareOrHigher)
            {
                rarity = roll < 75 ? GachaRarity.Rare : GachaRarity.Legendary;
            }
            else if (roll < 50) rarity = GachaRarity.Common;
            else if (roll < 80) rarity = GachaRarity.Uncommon;
            else if (roll < 95) rarity = GachaRarity.Rare;
            else rarity = GachaRarity.Legendary;

            var candidates = _gachaDropTable.Where(d => d.Rarity == rarity).ToArray();
            var pick = candidates[_gachaRng.Next(candidates.Length)];

            return new GachaDrop
            {
                Name = pick.Name,
                Rarity = pick.Rarity,
                Emoji = pick.Emoji,
                Quantity = pick.Qty
            };
        }

        public async Task<GachaReceipt> ExecuteGachaAsync(string playerUid, int pulls, bool isOnlineSession = false)
        {
            if (pulls != 1 && pulls != 10) pulls = 1;
            string uid = _saveService.ResolvePlayerUid(playerUid);

            int totalCost = pulls == 10 ? 25 : 3;

            var profile = await _saveService.ReadPlayerProfileAsync(uid);
            if (profile == null)
            {
                return new GachaReceipt
                {
                    Success = false,
                    Pulls = pulls,
                    Message = $"Could not load character save for Pioneer UID `{uid}`."
                };
            }

            int currentPoints;
            lock (_lock)
            {
                if (!_playerTechPoints.TryGetValue(uid, out currentPoints) &&
                    (string.IsNullOrWhiteSpace(playerUid) || !_playerTechPoints.TryGetValue(playerUid, out currentPoints)))
                {
                    currentPoints = profile.TechnologyPoints;
                }
            }

            if (currentPoints < totalCost)
            {
                return new GachaReceipt
                {
                    Success = false,
                    Pulls = pulls,
                    TotalCost = totalCost,
                    PreviousTechPoints = currentPoints,
                    NewTechPoints = currentPoints,
                    Message = $"Insufficient Technology Points. You need **{totalCost} pts** for a {pulls}-pull, but currently have **{currentPoints} pts**."
                };
            }

            int newPoints = currentPoints - totalCost;

            // Roll drops
            var drops = new List<GachaDrop>();
            bool pityTriggered = false;

            for (int i = 0; i < pulls; i++)
            {
                drops.Add(RollSingleGachaDrop());
            }

            // Pity mechanic: If 10-pull and no Rare+ drops, replace the last drop with a forced Rare+
            if (pulls == 10 && !drops.Any(d => d.Rarity >= GachaRarity.Rare))
            {
                drops[pulls - 1] = RollSingleGachaDrop(forceRareOrHigher: true);
                pityTriggered = true;
            }

            bool hasLegendary = drops.Any(d => d.Rarity == GachaRarity.Legendary);

            // Credit items to Player Virtual Vault and deduct Technology Points
            lock (_lock)
            {
                _playerTechPoints[uid] = newPoints;
                if (!string.IsNullOrWhiteSpace(playerUid)) _playerTechPoints[playerUid] = newPoints;

                if (!_playerInventories.TryGetValue(uid, out var inv))
                {
                    inv = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
                    _playerInventories[uid] = inv;
                }

                foreach (var drop in drops)
                {
                    string itemName = drop.Quantity > 1 ? $"{drop.Name} (x{drop.Quantity})" : drop.Name;
                    inv[itemName] = inv.GetValueOrDefault(itemName, 0) + 1;
                }
                SaveState();
            }

            if (isOnlineSession)
            {
                QueueDelivery(uid, "Gacha", "RelicMysteryBox", pulls, -totalCost);
            }
            else
            {
                await _saveService.UpdateTechnologyPointsAsync(uid, -totalCost);
            }

            _logService.LogSuccess($"[GACHA] {uid} performed {pulls}-pull for {totalCost} Tech Points. " +
                                   $"Results: {string.Join(", ", drops.Select(d => $"[{d.Rarity}] {d.Name}"))}" +
                                   (hasLegendary ? " ★ JACKPOT!" : "") +
                                   (pityTriggered ? " (Pity)" : ""), "Economy");

            return new GachaReceipt
            {
                Success = true,
                Pulls = pulls,
                TotalCost = totalCost,
                PreviousTechPoints = currentPoints,
                NewTechPoints = newPoints,
                Drops = drops,
                HasLegendary = hasLegendary,
                PityTriggered = pityTriggered,
                Message = hasLegendary
                    ? $"🎰 **JACKPOT!** You pulled a **LEGENDARY** item from the Relic Mystery Box!"
                    : $"Opened **{pulls}x Relic Mystery Box** for **{totalCost} Tech Points**!"
            };
        }

        public async Task<WithdrawReceipt> ExecuteWithdrawAsync(string playerUid, string? itemQuery = null, int quantity = 0, bool isOnlineSession = false)
        {
            string uid = _saveService.ResolvePlayerUid(playerUid);
            var withdrawn = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
            var remaining = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);

            lock (_lock)
            {
                Dictionary<string, int>? inv = null;
                if (!_playerInventories.TryGetValue(uid, out inv) &&
                    (!string.IsNullOrWhiteSpace(playerUid) && !_playerInventories.TryGetValue(playerUid, out inv)))
                {
                    return new WithdrawReceipt
                    {
                        Success = false,
                        Message = "Your Virtual Vault is currently empty. Open `/gacha` or purchase items in `/shop` first!"
                    };
                }

                if (inv == null || inv.Count == 0)
                {
                    return new WithdrawReceipt
                    {
                        Success = false,
                        Message = "Your Virtual Vault is currently empty. Open `/gacha` or purchase items in `/shop` first!"
                    };
                }

                if (string.IsNullOrWhiteSpace(itemQuery) || itemQuery.Trim().Equals("all", StringComparison.OrdinalIgnoreCase))
                {
                    foreach (var kvp in inv)
                    {
                        if (kvp.Value > 0)
                        {
                            withdrawn[kvp.Key] = kvp.Value;
                        }
                    }
                    inv.Clear();
                }
                else
                {
                    string clean = itemQuery.Trim();
                    var match = inv.Keys.FirstOrDefault(k => k.Contains(clean, StringComparison.OrdinalIgnoreCase) || clean.Contains(k, StringComparison.OrdinalIgnoreCase));
                    if (match == null)
                    {
                        return new WithdrawReceipt
                        {
                            Success = false,
                            Message = $"Item `{itemQuery}` was not found in your Virtual Vault. Use `/inventory` to check stored items."
                        };
                    }

                    int available = inv[match];
                    int toWithdraw = (quantity <= 0 || quantity > available) ? available : quantity;

                    withdrawn[match] = toWithdraw;
                    int rem = available - toWithdraw;
                    if (rem > 0) inv[match] = rem;
                    else inv.Remove(match);
                }

                foreach (var kvp in inv)
                {
                    remaining[kvp.Key] = kvp.Value;
                }

                SaveState();
            }

            // Queue deliveries for each item
            foreach (var kvp in withdrawn)
            {
                QueueDelivery(uid, "Withdraw", kvp.Key, kvp.Value, 0);
            }

            _logService.LogSuccess($"[WITHDRAW] {uid} withdrew {withdrawn.Count} item types ({string.Join(", ", withdrawn.Select(w => $"{w.Value}x {w.Key}"))}) from Virtual Vault.", "Economy");

            return new WithdrawReceipt
            {
                Success = true,
                WithdrawnItems = withdrawn,
                RemainingVaultItems = remaining,
                Message = $"Successfully claimed **{withdrawn.Count} item types** from your Virtual Vault into your live character!"
            };
        }

        private void LoadState()
        {
            lock (_lock)
            {
                try
                {
                    if (File.Exists(_stateFilePath))
                    {
                        string json = File.ReadAllText(_stateFilePath);
                        using var doc = JsonDocument.Parse(json);
                        if (doc.RootElement.TryGetProperty("links", out var linksProp))
                        {
                            foreach (var prop in linksProp.EnumerateObject())
                            {
                                _discordToPlayerMap[prop.Name] = prop.Value.GetString() ?? "";
                            }
                        }
                        if (doc.RootElement.TryGetProperty("inventories", out var invProp))
                        {
                            foreach (var playerObj in invProp.EnumerateObject())
                            {
                                string rawKey = playerObj.Name;
                                string resolvedKey = _saveService.ResolvePlayerUid(rawKey);

                                if (!_playerInventories.TryGetValue(resolvedKey, out var inv))
                                {
                                    inv = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
                                    _playerInventories[resolvedKey] = inv;
                                }

                                foreach (var itemProp in playerObj.Value.EnumerateObject())
                                {
                                    inv[itemProp.Name] = inv.GetValueOrDefault(itemProp.Name, 0) + itemProp.Value.GetInt32();
                                }

                                if (!resolvedKey.Equals(rawKey, StringComparison.OrdinalIgnoreCase))
                                {
                                    _playerInventories[rawKey] = inv;
                                }
                            }
                        }
                        if (doc.RootElement.TryGetProperty("techPoints", out var techProp))
                        {
                            foreach (var prop in techProp.EnumerateObject())
                            {
                                string rawKey = prop.Name;
                                string resolvedKey = _saveService.ResolvePlayerUid(rawKey);
                                int pts = prop.Value.GetInt32();
                                _playerTechPoints[resolvedKey] = pts;
                                if (!resolvedKey.Equals(rawKey, StringComparison.OrdinalIgnoreCase))
                                {
                                    _playerTechPoints[rawKey] = pts;
                                }
                            }
                        }
                    }
                }
                catch { }
            }
        }

        private void SaveState()
        {
            lock (_lock)
            {
                try
                {
                    var data = new
                    {
                        links = _discordToPlayerMap,
                        inventories = _playerInventories,
                        techPoints = _playerTechPoints
                    };

                    string json = JsonSerializer.Serialize(data, new JsonSerializerOptions { WriteIndented = true });
                    File.WriteAllText(_stateFilePath, json);
                }
                catch { }
            }
        }
    }
}
