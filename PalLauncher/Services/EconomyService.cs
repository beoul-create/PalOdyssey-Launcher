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
        Task<PlayerEconomyProfile?> GetPlayerProfileAsync(string playerUid, bool forceLiveRefresh = false);
        Task<ExchangeReceipt> ExecuteExchangeAsync(string playerUid, string itemQuery, int quantity, bool isOnlineSession = false);
        Task<RecycleReceipt> ExecuteRecycleAsync(string playerUid, string itemQuery, int quantity, bool isOnlineSession = false);
        Task<GachaReceipt> ExecuteGachaAsync(string playerUid, int pulls, string currency = "tech_points", bool isOnlineSession = false);
        Task<WithdrawReceipt> ExecuteWithdrawAsync(string playerUid, string? itemQuery = null, int quantity = 0, bool isOnlineSession = false);
        Task<TransmuteReceipt> ExecuteTransmuteAsync(string playerUid, int ancientPointsToConvert, bool isOnlineSession = false);
        Task<BasePerkReceipt> ExecuteUpgradePerkAsync(string playerUid, string perkType, bool isOnlineSession = false);
        Task<SetPointsReceipt> SetPlayerTechnologyPointsAsync(string playerUid, int points, string currency = "tech_points", bool isOnlineSession = false);
        Task<SetPointsReceipt> GrantPlayerTechnologyPointsAsync(string playerUid, int pointDelta, string currency = "tech_points", bool isOnlineSession = false);
        GuildPerksState GetGuildPerks();
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
        private readonly Dictionary<string, int> _playerBossPoints = new(StringComparer.OrdinalIgnoreCase);
        private GuildPerksState _guildPerks = new();
        private readonly object _lock = new();

        public GuildPerksState GetGuildPerks()
        {
            lock (_lock)
            {
                return new GuildPerksState
                {
                    WorkSpeedLevel = _guildPerks.WorkSpeedLevel,
                    ExpBoostLevel = _guildPerks.ExpBoostLevel
                };
            }
        }

        private static readonly List<ShopItem> _shopCatalog = new()
        {
            // Ancient Tech Shop Category (Purchasable with Ancient Technology Points)
            new ShopItem
            {
                Id = "power_fruit",
                Name = "Power Fruit / Lotus (+2 Attack)",
                ItemCode = "PowerFruit",
                TechPointCost = 0,
                AncientPointCost = 3,
                Category = "Ancient",
                Description = "Sacred lotus fruit that permanently increases Player Character Attack by +2.",
                Emoji = "🍎"
            },
            new ShopItem
            {
                Id = "life_fruit",
                Name = "Life Fruit / Lotus (+50 HP)",
                ItemCode = "LifeFruit",
                TechPointCost = 0,
                AncientPointCost = 3,
                Category = "Ancient",
                Description = "Sacred lotus fruit that permanently increases Player Character Max HP by +50.",
                Emoji = "🍇"
            },
            new ShopItem
            {
                Id = "stout_fruit",
                Name = "Stout Fruit / Lotus (+2 Defense)",
                ItemCode = "StoutFruit",
                TechPointCost = 0,
                AncientPointCost = 3,
                Category = "Ancient",
                Description = "Sacred lotus fruit that permanently increases Player Character Defense by +2.",
                Emoji = "🥥"
            },
            new ShopItem
            {
                Id = "skill_fruit_chest",
                Name = "Skill Fruit Chest (Tier 3)",
                ItemCode = "SkillFruitChestT3",
                TechPointCost = 0,
                AncientPointCost = 4,
                Category = "Ancient",
                Description = "Ancient relic chest containing a high-grade Tier-3 elemental active skill fruit.",
                Emoji = "🎁"
            },
            new ShopItem
            {
                Id = "ancient_civ_core",
                Name = "Ancient Civilization Core (x2)",
                ItemCode = "AncientCivCore",
                TechPointCost = 0,
                AncientPointCost = 2,
                Category = "Ancient",
                Description = "Crucial raid catalyst harvested from high-tier Alpha bosses for legendary craft structures.",
                Emoji = "🔮"
            },
            new ShopItem
            {
                Id = "ancient_civ_parts",
                Name = "Ancient Civilization Parts (x10)",
                ItemCode = "AncientCivParts",
                TechPointCost = 0,
                AncientPointCost = 1,
                Category = "Ancient",
                Description = "Essential parts for building Ancient Technology structures and high-tier spheres.",
                Emoji = "⚙️"
            },
            new ShopItem
            {
                Id = "large_pal_soul",
                Name = "Large Pal Soul (x3)",
                ItemCode = "LargePalSoul",
                TechPointCost = 0,
                AncientPointCost = 2,
                Category = "Ancient",
                Description = "Crystalline soul essence used at the Power Statue to max out Pal combat attributes.",
                Emoji = "✨"
            },

            // Standard Technology Points Category
            new ShopItem
            {
                Id = "dog_coin",
                Name = "Dog Coin",
                ItemCode = "DogCoin",
                TechPointCost = 2,
                AncientPointCost = 0,
                Category = "Standard",
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

        public async Task<PlayerEconomyProfile?> GetPlayerProfileAsync(string playerUid, bool forceLiveRefresh = false)
        {
            string uid = _saveService.ResolvePlayerUid(playerUid);
            var profile = await _saveService.ReadPlayerProfileAsync(uid);
            if (profile == null) return null;

            lock (_lock)
            {
                if (forceLiveRefresh)
                {
                    // Freshly sync in-memory tech points and boss points cache with live game/save data
                    _playerTechPoints[uid] = profile.TechnologyPoints;
                    if (!string.IsNullOrWhiteSpace(playerUid)) _playerTechPoints[playerUid] = profile.TechnologyPoints;

                    _playerBossPoints[uid] = profile.BossTechnologyPoints;
                    if (!string.IsNullOrWhiteSpace(playerUid)) _playerBossPoints[playerUid] = profile.BossTechnologyPoints;

                    SaveState();
                }
                else
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

                    if (_playerBossPoints.TryGetValue(uid, out int bossPts) ||
                        (!string.IsNullOrWhiteSpace(playerUid) && _playerBossPoints.TryGetValue(playerUid, out bossPts)))
                    {
                        profile.BossTechnologyPoints = bossPts;
                    }
                    else
                    {
                        _playerBossPoints[uid] = profile.BossTechnologyPoints;
                        if (!string.IsNullOrWhiteSpace(playerUid)) _playerBossPoints[playerUid] = profile.BossTechnologyPoints;
                    }
                }

                if (_playerInventories.TryGetValue(uid, out var inv) ||
                    (!string.IsNullOrWhiteSpace(playerUid) && _playerInventories.TryGetValue(playerUid, out inv)))
                {
                    profile.InventoryItems = new Dictionary<string, int>(inv);
                }

                if (string.IsNullOrWhiteSpace(profile.DiscordId))
                {
                    foreach (var kvp in _discordToPlayerMap)
                    {
                        if (kvp.Value.Equals(uid, StringComparison.OrdinalIgnoreCase) ||
                            (!string.IsNullOrWhiteSpace(playerUid) && kvp.Value.Equals(playerUid, StringComparison.OrdinalIgnoreCase)))
                        {
                            profile.DiscordId = kvp.Key;
                            break;
                        }
                    }
                }
            }

            if (string.IsNullOrWhiteSpace(profile.DiscordId) || string.IsNullOrWhiteSpace(profile.SteamId))
            {
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
                        foreach (var prop in doc.RootElement.EnumerateObject())
                        {
                            string discId = prop.Name;
                            var userObj = prop.Value;
                            string? pUid = userObj.TryGetProperty("playerUid", out var pu) ? pu.GetString() : null;
                            string? sId = userObj.TryGetProperty("steamId64", out var si) ? si.GetString() : null;

                            bool matches = (pUid != null && (pUid.Equals(uid, StringComparison.OrdinalIgnoreCase) || pUid.Equals(playerUid, StringComparison.OrdinalIgnoreCase))) ||
                                           (sId != null && (sId.Equals(uid, StringComparison.OrdinalIgnoreCase) || sId.Equals(playerUid, StringComparison.OrdinalIgnoreCase)));

                            string? dName = userObj.TryGetProperty("discordGlobalName", out var dgn) && !string.IsNullOrWhiteSpace(dgn.GetString())
                                ? dgn.GetString()
                                : (userObj.TryGetProperty("discordUsername", out var dun) ? dun.GetString() : null);

                            if (matches)
                            {
                                if (string.IsNullOrWhiteSpace(profile.DiscordId)) profile.DiscordId = discId;
                                if (string.IsNullOrWhiteSpace(profile.SteamId) && !string.IsNullOrWhiteSpace(sId)) profile.SteamId = sId;
                                if (string.IsNullOrWhiteSpace(profile.DiscordUsername) && !string.IsNullOrWhiteSpace(dName)) profile.DiscordUsername = dName;
                                break;
                            }
                        }
                    }
                }
                catch { }
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

            string line = $"{playerUid},{action},{itemCode},{quantity},{techPointsDelta}\n";
            try
            {
                File.AppendAllText(queueFile, line);
                if (Directory.Exists(serverQueueDir))
                {
                    File.AppendAllText(serverQueuePath, line);
                }
            }
            catch { }
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

            bool isAncient = item.AncientPointCost > 0;
            int unitCost = isAncient ? item.AncientPointCost : item.TechPointCost;
            int totalCost = unitCost * quantity;

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
                        PreviousTechPoints = profile.TechnologyPoints,
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

                // 3. Check caps
                bool personalPurchase = await _licenseService.PurchaseInfrastructureAsync(guildId, uid, item.ItemCode, 0);
                if (!personalPurchase)
                {
                    return new ExchangeReceipt
                    {
                        Success = false,
                        Message = "Transaction failed. You have reached the maximum infrastructure limit for this type."
                    };
                }
                
                bool updatedPersonal = await _saveService.UpdateTechnologyPointsAsync(uid, -totalCost);
                if (!updatedPersonal)
                {
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
                if (isAncient)
                {
                    if (!_playerBossPoints.TryGetValue(uid, out currentPoints) &&
                        (string.IsNullOrWhiteSpace(playerUid) || !_playerBossPoints.TryGetValue(playerUid, out currentPoints)))
                    {
                        currentPoints = profile.BossTechnologyPoints;
                    }
                }
                else
                {
                    if (!_playerTechPoints.TryGetValue(uid, out currentPoints) &&
                        (string.IsNullOrWhiteSpace(playerUid) || !_playerTechPoints.TryGetValue(playerUid, out currentPoints)))
                    {
                        currentPoints = profile.TechnologyPoints;
                    }
                }
            }

            if (currentPoints < totalCost)
            {
                string pointType = isAncient ? "Ancient Technology Points" : "Technology Points";
                return new ExchangeReceipt
                {
                    Success = false,
                    ItemName = item.Name,
                    Quantity = quantity,
                    TotalCost = totalCost,
                    IsAncientCurrency = isAncient,
                    PreviousTechPoints = isAncient ? profile.TechnologyPoints : currentPoints,
                    NewTechPoints = isAncient ? profile.TechnologyPoints : currentPoints,
                    PreviousAncientPoints = isAncient ? currentPoints : profile.BossTechnologyPoints,
                    NewAncientPoints = isAncient ? currentPoints : profile.BossTechnologyPoints,
                    Message = $"Insufficient {pointType}. You need **{totalCost} pts** ({unitCost} × {quantity}), but currently have **{currentPoints} pts**."
                };
            }

            int newPoints = currentPoints - totalCost;

            // Credit items to Player Virtual Vault / Inventory & deduct Points
            lock (_lock)
            {
                if (isAncient)
                {
                    _playerBossPoints[uid] = newPoints;
                    if (!string.IsNullOrWhiteSpace(playerUid)) _playerBossPoints[playerUid] = newPoints;
                }
                else
                {
                    _playerTechPoints[uid] = newPoints;
                    if (!string.IsNullOrWhiteSpace(playerUid)) _playerTechPoints[playerUid] = newPoints;
                }

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
                QueueDelivery(uid, "Exchange", item.ItemCode, quantity, isAncient ? 0 : -totalCost);
            }
            else if (!isAncient)
            {
                await _saveService.UpdateTechnologyPointsAsync(uid, -totalCost);
            }

            _logService.LogSuccess($"[EXCHANGE] {uid} purchased {quantity}x {item.Name} for {totalCost} {(isAncient ? "Ancient Points" : "Tech Points")}.", "Economy");

            return new ExchangeReceipt
            {
                Success = true,
                ItemName = item.Name,
                Quantity = quantity,
                TotalCost = totalCost,
                IsAncientCurrency = isAncient,
                PreviousTechPoints = isAncient ? profile.TechnologyPoints : currentPoints,
                NewTechPoints = isAncient ? profile.TechnologyPoints : newPoints,
                PreviousAncientPoints = isAncient ? currentPoints : profile.BossTechnologyPoints,
                NewAncientPoints = isAncient ? newPoints : profile.BossTechnologyPoints,
                Message = $"Successfully exchanged **{totalCost} {(isAncient ? "Ancient Technology Points" : "Tech Points")}** for **{quantity}x {item.Name}** {item.Emoji}! Items have been delivered to your Virtual Vault."
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
                    Message = $"Item `{itemQuery}` is not eligible for Trash-to-Tech recycling. Use `/shop` to view accepted materials."
                };
            }

            if (quantity < item.MinQuantityForOnePoint)
            {
                return new RecycleReceipt
                {
                    Success = false,
                    Message = $"Quantity `{quantity}` of `{item.Name}` is below the minimum threshold. You need at least `{item.MinQuantityForOnePoint}` to produce 1 point."
                };
            }

            int pointsEarned = (int)Math.Floor(quantity * item.PointsMultiplier);
            if (pointsEarned <= 0)
            {
                return new RecycleReceipt
                {
                    Success = false,
                    Message = $"Quantity `{quantity}` of `{item.Name}` is below the minimum threshold. You need at least `{item.MinQuantityForOnePoint}` to produce 1 point."
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

            lock (_lock)
            {
                _playerTechPoints[uid] = newPoints;
                if (!string.IsNullOrWhiteSpace(playerUid)) _playerTechPoints[playerUid] = newPoints;
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

        // ===== GACHA: Standard Relic Mystery Box Drop Table =====
        private static readonly (GachaRarity Rarity, string Name, string Emoji, int Qty)[] _standardGachaDropTable = new[]
        {
            // Common (50% total weight)
            (GachaRarity.Common, "Mega/Giga Spheres", "⚪", 50),
            (GachaRarity.Common, "High-Grade Tech Manual", "📙", 2),
            (GachaRarity.Common, "Gold Coins", "🪙", 10000),
            (GachaRarity.Common, "Cake", "🎂", 5),

            // Uncommon (30% total weight)
            (GachaRarity.Uncommon, "Dog Coin", "🪙", 2),
            (GachaRarity.Uncommon, "Arena Ticket", "🎟️", 1),
            (GachaRarity.Uncommon, "Bounty Token", "📜", 1),
            (GachaRarity.Uncommon, "Large Pal Soul", "💜", 2),

            // Rare (15% total weight)
            (GachaRarity.Rare, "Pal Reverser / Training Crystal", "🔮", 1),
            (GachaRarity.Rare, "Memory Reset Drug", "🧪", 1),
            (GachaRarity.Rare, "Epic Skill Fruit", "🍎", 1),

            // Legendary (5% total weight)
            (GachaRarity.Legendary, "Legendary Schematic IV (Rocket Launcher / Assault Rifle)", "⭐", 1),
            (GachaRarity.Legendary, "Raid Boss Summon Slab (Bellanoir Libero / Blazamut Ryu)", "🗿", 1),
            (GachaRarity.Legendary, "Huge Dragon/Dark Egg", "🥚", 1)
        };

        // ===== GACHA: Ancient Relic & Sacred Lotus Drop Table =====
        private static readonly (GachaRarity Rarity, string Name, string Emoji, int Qty)[] _ancientGachaDropTable = new[]
        {
            // Common (35% total weight)
            (GachaRarity.Common, "Ancient Civilization Parts", "⚙️", 10),
            (GachaRarity.Common, "Medium Pal Soul", "✨", 3),
            (GachaRarity.Common, "Ultra Sphere", "🔵", 10),
            (GachaRarity.Common, "High-Tier Skill Fruit", "🍏", 1),

            // Uncommon (35% total weight)
            (GachaRarity.Uncommon, "Ancient Civilization Core", "🔮", 1),
            (GachaRarity.Uncommon, "Large Pal Soul", "💜", 3),
            (GachaRarity.Uncommon, "Legendary Sphere", "🟡", 5),
            (GachaRarity.Uncommon, "Skill Fruit (Tier 2/3)", "🍊", 1),

            // Rare (20% total weight)
            (GachaRarity.Rare, "Power Fruit / Lotus (+2 Attack)", "🍎", 1),
            (GachaRarity.Rare, "Life Fruit / Lotus (+50 HP)", "🍇", 1),
            (GachaRarity.Rare, "Stout Fruit / Lotus (+2 Defense)", "🥥", 1),
            (GachaRarity.Rare, "Skill Fruit Chest (Tier 3)", "🎁", 1),
            (GachaRarity.Rare, "Ancient Civilization Core", "🔮", 3),

            // Legendary (10% total weight)
            (GachaRarity.Legendary, "Power Fruit / Lotus (x2)", "🍎", 2),
            (GachaRarity.Legendary, "Life Fruit / Lotus (x2)", "🍇", 2),
            (GachaRarity.Legendary, "Stout Fruit / Lotus (x2)", "🥥", 2),
            (GachaRarity.Legendary, "Legendary Schematic IV (Rocket Launcher 4 / Assault Rifle 4)", "⭐", 1),
            (GachaRarity.Legendary, "Ancient Civilization Core (x5)", "🔮", 5)
        };

        private static readonly Random _gachaRng = new();

        private GachaDrop RollSingleGachaDrop(bool isAncientGacha = false, bool forceRareOrHigher = false)
        {
            int roll = _gachaRng.Next(100);
            GachaRarity rarity;

            if (isAncientGacha)
            {
                if (forceRareOrHigher)
                {
                    rarity = roll < 65 ? GachaRarity.Rare : GachaRarity.Legendary;
                }
                else if (roll < 35) rarity = GachaRarity.Common;
                else if (roll < 70) rarity = GachaRarity.Uncommon;
                else if (roll < 90) rarity = GachaRarity.Rare;
                else rarity = GachaRarity.Legendary;

                var candidates = _ancientGachaDropTable.Where(d => d.Rarity == rarity).ToArray();
                var pick = candidates[_gachaRng.Next(candidates.Length)];

                return new GachaDrop
                {
                    Name = pick.Name,
                    Rarity = pick.Rarity,
                    Emoji = pick.Emoji,
                    Quantity = pick.Qty
                };
            }
            else
            {
                if (forceRareOrHigher)
                {
                    rarity = roll < 75 ? GachaRarity.Rare : GachaRarity.Legendary;
                }
                else if (roll < 50) rarity = GachaRarity.Common;
                else if (roll < 80) rarity = GachaRarity.Uncommon;
                else if (roll < 95) rarity = GachaRarity.Rare;
                else rarity = GachaRarity.Legendary;

                var candidates = _standardGachaDropTable.Where(d => d.Rarity == rarity).ToArray();
                var pick = candidates[_gachaRng.Next(candidates.Length)];

                return new GachaDrop
                {
                    Name = pick.Name,
                    Rarity = pick.Rarity,
                    Emoji = pick.Emoji,
                    Quantity = pick.Qty
                };
            }
        }

        public async Task<GachaReceipt> ExecuteGachaAsync(string playerUid, int pulls, string currency = "tech_points", bool isOnlineSession = false)
        {
            if (pulls != 1 && pulls != 10) pulls = 1;
            string uid = _saveService.ResolvePlayerUid(playerUid);
            bool isAncient = currency.Equals("ancient_points", StringComparison.OrdinalIgnoreCase) || currency.Equals("ancient", StringComparison.OrdinalIgnoreCase);

            int totalCost = isAncient ? (pulls == 10 ? 18 : 2) : (pulls == 10 ? 25 : 3);

            var profile = await _saveService.ReadPlayerProfileAsync(uid);
            if (profile == null)
            {
                return new GachaReceipt
                {
                    Success = false,
                    Pulls = pulls,
                    CurrencyUsed = isAncient ? "ancient_points" : "tech_points",
                    Message = $"Could not load character save for Pioneer UID `{uid}`."
                };
            }

            int currentPoints;
            lock (_lock)
            {
                if (isAncient)
                {
                    if (!_playerBossPoints.TryGetValue(uid, out currentPoints) &&
                        (string.IsNullOrWhiteSpace(playerUid) || !_playerBossPoints.TryGetValue(playerUid, out currentPoints)))
                    {
                        currentPoints = profile.BossTechnologyPoints;
                    }
                }
                else
                {
                    if (!_playerTechPoints.TryGetValue(uid, out currentPoints) &&
                        (string.IsNullOrWhiteSpace(playerUid) || !_playerTechPoints.TryGetValue(playerUid, out currentPoints)))
                    {
                        currentPoints = profile.TechnologyPoints;
                    }
                }
            }

            if (currentPoints < totalCost)
            {
                string pointLabel = isAncient ? "Ancient Technology Points" : "Technology Points";
                return new GachaReceipt
                {
                    Success = false,
                    Pulls = pulls,
                    TotalCost = totalCost,
                    CurrencyUsed = isAncient ? "ancient_points" : "tech_points",
                    PreviousTechPoints = isAncient ? profile.TechnologyPoints : currentPoints,
                    NewTechPoints = isAncient ? profile.TechnologyPoints : currentPoints,
                    PreviousAncientPoints = isAncient ? currentPoints : profile.BossTechnologyPoints,
                    NewAncientPoints = isAncient ? currentPoints : profile.BossTechnologyPoints,
                    Message = $"Insufficient {pointLabel}. You need **{totalCost} pts** for a {pulls}-pull, but currently have **{currentPoints} pts**."
                };
            }

            int newPoints = currentPoints - totalCost;

            // Roll drops
            var drops = new List<GachaDrop>();
            bool pityTriggered = false;

            for (int i = 0; i < pulls; i++)
            {
                drops.Add(RollSingleGachaDrop(isAncientGacha: isAncient));
            }

            // Pity mechanic: If 10-pull and no Rare+ drops, replace the last drop with a forced Rare+
            if (pulls == 10 && !drops.Any(d => d.Rarity >= GachaRarity.Rare))
            {
                drops[pulls - 1] = RollSingleGachaDrop(isAncientGacha: isAncient, forceRareOrHigher: true);
                pityTriggered = true;
            }

            bool hasLegendary = drops.Any(d => d.Rarity == GachaRarity.Legendary);

            // Credit items to Player Virtual Vault and deduct Points
            lock (_lock)
            {
                if (isAncient)
                {
                    _playerBossPoints[uid] = newPoints;
                    if (!string.IsNullOrWhiteSpace(playerUid)) _playerBossPoints[playerUid] = newPoints;
                }
                else
                {
                    _playerTechPoints[uid] = newPoints;
                    if (!string.IsNullOrWhiteSpace(playerUid)) _playerTechPoints[playerUid] = newPoints;
                }

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
                QueueDelivery(uid, "Gacha", isAncient ? "AncientRelicBox" : "RelicMysteryBox", pulls, isAncient ? 0 : -totalCost);
            }
            else if (!isAncient)
            {
                await _saveService.UpdateTechnologyPointsAsync(uid, -totalCost);
            }

            _logService.LogSuccess($"[GACHA] {uid} performed {pulls}-pull using {(isAncient ? "Ancient Points" : "Tech Points")} (Cost: {totalCost}). " +
                                   $"Results: {string.Join(", ", drops.Select(d => $"[{d.Rarity}] {d.Name}"))}" +
                                   (hasLegendary ? " ★ JACKPOT!" : "") +
                                   (pityTriggered ? " (Pity)" : ""), "Economy");

            return new GachaReceipt
            {
                Success = true,
                Pulls = pulls,
                TotalCost = totalCost,
                CurrencyUsed = isAncient ? "ancient_points" : "tech_points",
                PreviousTechPoints = isAncient ? profile.TechnologyPoints : currentPoints,
                NewTechPoints = isAncient ? profile.TechnologyPoints : newPoints,
                PreviousAncientPoints = isAncient ? currentPoints : profile.BossTechnologyPoints,
                NewAncientPoints = isAncient ? newPoints : profile.BossTechnologyPoints,
                Drops = drops,
                HasLegendary = hasLegendary,
                PityTriggered = pityTriggered,
                Message = $"Successfully opened **{pulls}x {(isAncient ? "Ancient Relic" : "Mystery")} Box** for **{totalCost} {(isAncient ? "Ancient" : "Tech")} Points**!"
            };
        }

        public async Task<TransmuteReceipt> ExecuteTransmuteAsync(string playerUid, int ancientPointsToConvert, bool isOnlineSession = false)
        {
            if (ancientPointsToConvert <= 0) ancientPointsToConvert = 1;
            string uid = _saveService.ResolvePlayerUid(playerUid);

            var profile = await _saveService.ReadPlayerProfileAsync(uid);
            if (profile == null)
            {
                return new TransmuteReceipt
                {
                    Success = false,
                    Message = $"Could not load character save for Pioneer UID `{uid}`."
                };
            }

            int currentAncient;
            int currentTech;
            lock (_lock)
            {
                if (!_playerBossPoints.TryGetValue(uid, out currentAncient) &&
                    (string.IsNullOrWhiteSpace(playerUid) || !_playerBossPoints.TryGetValue(playerUid, out currentAncient)))
                {
                    currentAncient = profile.BossTechnologyPoints;
                }

                if (!_playerTechPoints.TryGetValue(uid, out currentTech) &&
                    (string.IsNullOrWhiteSpace(playerUid) || !_playerTechPoints.TryGetValue(playerUid, out currentTech)))
                {
                    currentTech = profile.TechnologyPoints;
                }
            }

            if (currentAncient < ancientPointsToConvert)
            {
                return new TransmuteReceipt
                {
                    Success = false,
                    AncientPointsSpent = ancientPointsToConvert,
                    PreviousAncientPoints = currentAncient,
                    RemainingAncientPoints = currentAncient,
                    PreviousTechPoints = currentTech,
                    NewTechPoints = currentTech,
                    Message = $"Insufficient Ancient Technology Points. You requested to convert **{ancientPointsToConvert} pts**, but currently have **{currentAncient} pts**."
                };
            }

            int techPointsGained = ancientPointsToConvert * 2;
            int newAncient = currentAncient - ancientPointsToConvert;
            int newTech = currentTech + techPointsGained;

            lock (_lock)
            {
                _playerBossPoints[uid] = newAncient;
                _playerTechPoints[uid] = newTech;
                if (!string.IsNullOrWhiteSpace(playerUid))
                {
                    _playerBossPoints[playerUid] = newAncient;
                    _playerTechPoints[playerUid] = newTech;
                }
                SaveState();
            }

            if (isOnlineSession)
            {
                QueueDelivery(uid, "Transmute", "TechPointConversion", techPointsGained, techPointsGained);
            }
            else
            {
                await _saveService.UpdateTechnologyPointsAsync(uid, techPointsGained);
            }

            _logService.LogSuccess($"[TRANSMUTE] {uid} converted {ancientPointsToConvert} Ancient Points into +{techPointsGained} Standard Tech Points.", "Economy");

            return new TransmuteReceipt
            {
                Success = true,
                AncientPointsSpent = ancientPointsToConvert,
                TechPointsGained = techPointsGained,
                PreviousAncientPoints = currentAncient,
                RemainingAncientPoints = newAncient,
                PreviousTechPoints = currentTech,
                NewTechPoints = newTech,
                Message = $"Successfully transmuted **{ancientPointsToConvert} Ancient Technology Points** into **+{techPointsGained} Standard Technology Points**! (1 Ancient = 2 Normal)"
            };
        }

        public async Task<BasePerkReceipt> ExecuteUpgradePerkAsync(string playerUid, string perkType, bool isOnlineSession = false)
        {
            string uid = _saveService.ResolvePlayerUid(playerUid);
            var profile = await _saveService.ReadPlayerProfileAsync(uid);
            if (profile == null)
            {
                return new BasePerkReceipt
                {
                    Success = false,
                    Message = $"Could not load character save for Pioneer UID `{uid}`."
                };
            }

            string cleanType = perkType.ToLowerInvariant().Trim();
            int cost;
            string perkName;
            string bonusDesc;

            if (cleanType == "exp_boost" || cleanType == "exp")
            {
                cost = 20;
                perkName = "Global Server EXP Boost";
            }
            else
            {
                cleanType = "work_speed";
                cost = 5;
                perkName = "Base Pal Work & Movement Speed";
            }

            int currentAncient;
            lock (_lock)
            {
                if (!_playerBossPoints.TryGetValue(uid, out currentAncient) &&
                    (string.IsNullOrWhiteSpace(playerUid) || !_playerBossPoints.TryGetValue(playerUid, out currentAncient)))
                {
                    currentAncient = profile.BossTechnologyPoints;
                }
            }

            if (currentAncient < cost)
            {
                return new BasePerkReceipt
                {
                    Success = false,
                    PerkType = cleanType,
                    PerkName = perkName,
                    AncientCost = cost,
                    RemainingAncientPoints = currentAncient,
                    Message = $"Insufficient Ancient Technology Points. **{perkName}** requires **{cost} Ancient Points**, but you currently have **{currentAncient} pts**."
                };
            }

            int newAncient = currentAncient - cost;
            int newLevel;

            lock (_lock)
            {
                _playerBossPoints[uid] = newAncient;
                if (!string.IsNullOrWhiteSpace(playerUid)) _playerBossPoints[playerUid] = newAncient;

                if (cleanType == "exp_boost" || cleanType == "exp")
                {
                    _guildPerks.ExpBoostLevel++;
                    newLevel = _guildPerks.ExpBoostLevel;
                    bonusDesc = $"+{newLevel * 5}% Total Server EXP Boost (+5% added)";
                }
                else
                {
                    _guildPerks.WorkSpeedLevel++;
                    newLevel = _guildPerks.WorkSpeedLevel;
                    bonusDesc = $"+{newLevel * 1}% Base Pal Work & Movement Speed (+1% added)";
                }
                SaveState();
            }

            if (isOnlineSession)
            {
                QueueDelivery(uid, "Perk", cleanType, 1, 0);
            }

            _logService.LogSuccess($"[PERK] {uid} upgraded {perkName} to Tier {newLevel} for {cost} Ancient Points.", "Economy");

            return new BasePerkReceipt
            {
                Success = true,
                PerkType = cleanType,
                PerkName = perkName,
                AncientCost = cost,
                NewPerkLevel = newLevel,
                PerkBonusDescription = bonusDesc,
                RemainingAncientPoints = newAncient,
                Message = $"🎉 **{perkName}** successfully upgraded to **Tier {newLevel}**! Active Buff: **{bonusDesc}**"
            };
        }

        public Task<WithdrawReceipt> ExecuteWithdrawAsync(string playerUid, string? itemQuery = null, int quantity = 0, bool isOnlineSession = false)
        {
            string uid = _saveService.ResolvePlayerUid(playerUid);
            var withdrawn = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);
            var remaining = new Dictionary<string, int>(StringComparer.OrdinalIgnoreCase);

            lock (_lock)
            {
                if (!_playerInventories.TryGetValue(uid, out var inv) || inv.Count == 0)
                {
                    return Task.FromResult(new WithdrawReceipt
                    {
                        Success = false,
                        Message = "Your Virtual Vault is currently empty! Use `/shop` or `/gacha` to acquire items first."
                    });
                }

                if (string.IsNullOrWhiteSpace(itemQuery) || itemQuery.Equals("all", StringComparison.OrdinalIgnoreCase))
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
                    string targetKey = "";
                    foreach (var k in inv.Keys)
                    {
                        if (k.Equals(itemQuery, StringComparison.OrdinalIgnoreCase) ||
                            k.Contains(itemQuery, StringComparison.OrdinalIgnoreCase))
                        {
                            targetKey = k;
                            break;
                        }
                    }

                    if (string.IsNullOrEmpty(targetKey))
                    {
                        return Task.FromResult(new WithdrawReceipt
                        {
                            Success = false,
                            RemainingVaultItems = new Dictionary<string, int>(inv),
                            Message = $"Item `{itemQuery}` was not found in your Virtual Vault."
                        });
                    }

                    int available = inv[targetKey];
                    int take = (quantity <= 0 || quantity >= available) ? available : quantity;

                    withdrawn[targetKey] = take;
                    int left = available - take;
                    if (left <= 0)
                    {
                        inv.Remove(targetKey);
                    }
                    else
                    {
                        inv[targetKey] = left;
                    }
                }

                remaining = new Dictionary<string, int>(inv);
                SaveState();
            }

            foreach (var kvp in withdrawn)
            {
                if (isOnlineSession)
                {
                    QueueDelivery(uid, "Withdraw", kvp.Key, kvp.Value, 0);
                }
            }

            _logService.LogSuccess($"[WITHDRAW] {uid} claimed {withdrawn.Count} item types from Virtual Vault.", "Economy");

            return Task.FromResult(new WithdrawReceipt
            {
                Success = true,
                WithdrawnItems = withdrawn,
                RemainingVaultItems = remaining,
                Message = $"Successfully claimed **{withdrawn.Count} item types** from your Virtual Vault into your live character!"
            });
        }

        public async Task<SetPointsReceipt> SetPlayerTechnologyPointsAsync(string playerUid, int points, string currency = "tech_points", bool isOnlineSession = false)
        {
            string uid = _saveService.ResolvePlayerUid(playerUid);
            var profile = await _saveService.ReadPlayerProfileAsync(uid);
            if (profile == null)
            {
                return new SetPointsReceipt
                {
                    Success = false,
                    Message = $"Could not find player save for `{playerUid}`."
                };
            }

            bool isBossPoints = currency.Equals("boss_points", StringComparison.OrdinalIgnoreCase) ||
                                currency.Equals("ancient_points", StringComparison.OrdinalIgnoreCase) ||
                                currency.Equals("ancient", StringComparison.OrdinalIgnoreCase);

            int targetPoints = Math.Max(0, points);
            int previousPoints;
            int delta;

            lock (_lock)
            {
                if (isBossPoints)
                {
                    if (!_playerBossPoints.TryGetValue(uid, out previousPoints) &&
                        (string.IsNullOrWhiteSpace(playerUid) || !_playerBossPoints.TryGetValue(playerUid, out previousPoints)))
                    {
                        previousPoints = profile.BossTechnologyPoints;
                    }

                    delta = targetPoints - previousPoints;
                    _playerBossPoints[uid] = targetPoints;
                    if (!string.IsNullOrWhiteSpace(playerUid)) _playerBossPoints[playerUid] = targetPoints;
                }
                else
                {
                    if (!_playerTechPoints.TryGetValue(uid, out previousPoints) &&
                        (string.IsNullOrWhiteSpace(playerUid) || !_playerTechPoints.TryGetValue(playerUid, out previousPoints)))
                    {
                        previousPoints = profile.TechnologyPoints;
                    }

                    delta = targetPoints - previousPoints;
                    _playerTechPoints[uid] = targetPoints;
                    if (!string.IsNullOrWhiteSpace(playerUid)) _playerTechPoints[playerUid] = targetPoints;
                }
                SaveState();
            }

            if (isOnlineSession)
            {
                string action = isBossPoints ? "SetBossPoints" : "SetTechPoints";
                QueueDelivery(uid, action, isBossPoints ? "AncientBossPoints" : "TechnologyPoints", targetPoints, targetPoints);
            }
            else
            {
                if (isBossPoints)
                {
                    await _saveService.UpdateBossTechnologyPointsAsync(uid, targetPoints, isAbsolute: true);
                }
                else
                {
                    await _saveService.UpdateTechnologyPointsAsync(uid, targetPoints, isAbsolute: true);
                }
            }

            string currName = isBossPoints ? "Ancient Boss Points" : "Technology Points";
            _logService.LogSuccess($"[ADMIN-ECONOMY] Set {currName} for {uid} ({profile.PlayerName}): {previousPoints} -> {targetPoints}", "Economy");

            return new SetPointsReceipt
            {
                Success = true,
                PlayerUid = uid,
                PlayerName = profile.PlayerName,
                Currency = isBossPoints ? "boss_points" : "tech_points",
                PreviousPoints = previousPoints,
                NewPoints = targetPoints,
                Delta = delta,
                IsAbsoluteSet = true,
                Message = $"Successfully set **{profile.PlayerName}**'s {currName} to **{targetPoints} pts** (Previous: {previousPoints} pts)."
            };
        }

        public async Task<SetPointsReceipt> GrantPlayerTechnologyPointsAsync(string playerUid, int pointDelta, string currency = "tech_points", bool isOnlineSession = false)
        {
            string uid = _saveService.ResolvePlayerUid(playerUid);
            var profile = await _saveService.ReadPlayerProfileAsync(uid);
            if (profile == null)
            {
                return new SetPointsReceipt
                {
                    Success = false,
                    Message = $"Could not find player save for `{playerUid}`."
                };
            }

            bool isBossPoints = currency.Equals("boss_points", StringComparison.OrdinalIgnoreCase) ||
                                currency.Equals("ancient_points", StringComparison.OrdinalIgnoreCase) ||
                                currency.Equals("ancient", StringComparison.OrdinalIgnoreCase);

            int previousPoints;
            int newPoints;

            lock (_lock)
            {
                if (isBossPoints)
                {
                    if (!_playerBossPoints.TryGetValue(uid, out previousPoints) &&
                        (string.IsNullOrWhiteSpace(playerUid) || !_playerBossPoints.TryGetValue(playerUid, out previousPoints)))
                    {
                        previousPoints = profile.BossTechnologyPoints;
                    }

                    newPoints = Math.Max(0, previousPoints + pointDelta);
                    _playerBossPoints[uid] = newPoints;
                    if (!string.IsNullOrWhiteSpace(playerUid)) _playerBossPoints[playerUid] = newPoints;
                }
                else
                {
                    if (!_playerTechPoints.TryGetValue(uid, out previousPoints) &&
                        (string.IsNullOrWhiteSpace(playerUid) || !_playerTechPoints.TryGetValue(playerUid, out previousPoints)))
                    {
                        previousPoints = profile.TechnologyPoints;
                    }

                    newPoints = Math.Max(0, previousPoints + pointDelta);
                    _playerTechPoints[uid] = newPoints;
                    if (!string.IsNullOrWhiteSpace(playerUid)) _playerTechPoints[playerUid] = newPoints;
                }
                SaveState();
            }

            if (isOnlineSession)
            {
                string action = isBossPoints ? "GrantBossPoints" : "GrantTechPoints";
                QueueDelivery(uid, action, isBossPoints ? "AncientBossPoints" : "TechnologyPoints", Math.Abs(pointDelta), pointDelta);
            }
            else
            {
                if (isBossPoints)
                {
                    await _saveService.UpdateBossTechnologyPointsAsync(uid, pointDelta, isAbsolute: false);
                }
                else
                {
                    await _saveService.UpdateTechnologyPointsAsync(uid, pointDelta, isAbsolute: false);
                }
            }

            string currName = isBossPoints ? "Ancient Boss Points" : "Technology Points";
            _logService.LogSuccess($"[ADMIN-ECONOMY] Granted {pointDelta:+0;-0;0} {currName} to {uid} ({profile.PlayerName}): {previousPoints} -> {newPoints}", "Economy");

            return new SetPointsReceipt
            {
                Success = true,
                PlayerUid = uid,
                PlayerName = profile.PlayerName,
                Currency = isBossPoints ? "boss_points" : "tech_points",
                PreviousPoints = previousPoints,
                NewPoints = newPoints,
                Delta = pointDelta,
                IsAbsoluteSet = false,
                Message = $"Successfully granted **{(pointDelta >= 0 ? "+" : "")}{pointDelta} {currName}** to **{profile.PlayerName}**! New Balance: **{newPoints} pts**."
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
                        if (doc.RootElement.TryGetProperty("bossPoints", out var bossProp))
                        {
                            foreach (var prop in bossProp.EnumerateObject())
                            {
                                string rawKey = prop.Name;
                                string resolvedKey = _saveService.ResolvePlayerUid(rawKey);
                                int pts = prop.Value.GetInt32();
                                _playerBossPoints[resolvedKey] = pts;
                                if (!resolvedKey.Equals(rawKey, StringComparison.OrdinalIgnoreCase))
                                {
                                    _playerBossPoints[rawKey] = pts;
                                }
                            }
                        }
                        if (doc.RootElement.TryGetProperty("guildPerks", out var perkProp))
                        {
                            _guildPerks = JsonSerializer.Deserialize<GuildPerksState>(perkProp.GetRawText()) ?? new GuildPerksState();
                        }
                    }
                }
                catch { }
            }
        }

        private void SaveState()
        {
            string json;
            lock (_lock)
            {
                try
                {
                    var data = new
                    {
                        links = new Dictionary<string, string>(_discordToPlayerMap),
                        inventories = _playerInventories.ToDictionary(k => k.Key, v => new Dictionary<string, int>(v.Value, StringComparer.OrdinalIgnoreCase), StringComparer.OrdinalIgnoreCase),
                        techPoints = new Dictionary<string, int>(_playerTechPoints, StringComparer.OrdinalIgnoreCase),
                        bossPoints = new Dictionary<string, int>(_playerBossPoints, StringComparer.OrdinalIgnoreCase),
                        guildPerks = new GuildPerksState
                        {
                            WorkSpeedLevel = _guildPerks.WorkSpeedLevel,
                            ExpBoostLevel = _guildPerks.ExpBoostLevel
                        }
                    };

                    json = JsonSerializer.Serialize(data, new JsonSerializerOptions { WriteIndented = true });
                }
                catch
                {
                    return;
                }
            }

            try
            {
                File.WriteAllText(_stateFilePath, json);
            }
            catch { }
        }
    }
}
