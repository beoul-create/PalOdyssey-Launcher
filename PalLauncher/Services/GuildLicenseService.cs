using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.IO;
using System.Text.Json;
using System.Text.Json.Serialization;
using System.Threading.Tasks;
using PalLauncher.Services.Interfaces;

namespace PalLauncher.Services
{
    public class GuildLicenseState
    {
        [JsonPropertyName("guild_name")]
        public string GuildName { get; set; } = "Unknown";
        
        [JsonPropertyName("guild_bank_balance")]
        public int GuildBankBalance { get; set; } = 0;
        
        [JsonPropertyName("contributions")]
        public Dictionary<string, int> Contributions { get; set; } = new(StringComparer.OrdinalIgnoreCase);
        
        [JsonPropertyName("max_bases")]
        public int MaxBases { get; set; } = 4;
        
        [JsonPropertyName("max_breeding_pens")]
        public int MaxBreedingPens { get; set; } = 1;
        
        [JsonPropertyName("max_ranches")]
        public int MaxRanches { get; set; } = 1;
    }

    public class GuildLicenseData
    {
        [JsonPropertyName("guilds")]
        public ConcurrentDictionary<string, GuildLicenseState> Guilds { get; set; } = new();
    }

    public interface IGuildLicenseService
    {
        Task<int> GetPurchasedBasesAsync(string guildId);
        Task<bool> IncrementLicenseAsync(string guildId, int limit = 6);
        Task<string?> ResolveGuildIdAsync(string playerUid);
        
        // New Bank Endpoints
        Task<GuildLicenseState?> GetGuildStateAsync(string guildId);
        Task<bool> DepositToBankAsync(string guildId, string playerUid, int amount);
        Task<bool> PurchaseInfrastructureAsync(string guildId, string playerUid, string structureType, int cost);
        Task<bool> UpdateGuildNameAsync(string guildId, string guildName);
    }

    public class GuildLicenseService : IGuildLicenseService
    {
        private readonly string _licenseFilePath;
        private readonly IPalSaveService _saveService;
        private readonly ILogService _logService;
        private readonly object _fileLock = new object();
        private GuildLicenseData _data;

        public GuildLicenseService(ILogService logService, IPalSaveService saveService, string? customFilePath = null)
        {
            _logService = logService;
            _saveService = saveService;
            
            _licenseFilePath = customFilePath ?? Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), "PalLauncher", "guild-licenses.json");
            string? directory = Path.GetDirectoryName(_licenseFilePath);
            if (!string.IsNullOrEmpty(directory))
            {
                Directory.CreateDirectory(directory);
            }

            _data = LoadData();
        }

        private GuildLicenseData LoadData()
        {
            lock (_fileLock)
            {
                if (File.Exists(_licenseFilePath))
                {
                    try
                    {
                        string json = File.ReadAllText(_licenseFilePath);
                        var parsed = JsonSerializer.Deserialize<GuildLicenseData>(json);
                        if (parsed != null) 
                        {
                            _logService.LogSuccess($"[SUCCESS] Reloaded guild licenses from {_licenseFilePath}. Loaded {parsed.Guilds.Count} guilds.", "GuildLicenseService");
                            return parsed;
                        }
                    }
                    catch (Exception ex)
                    {
                        _logService.LogError($"[ERROR] Failed to load guild-licenses.json: {ex.Message}", "GuildLicenseService", ex);
                    }
                }
                return new GuildLicenseData();
            }
        }

        private void SaveData()
        {
            string json;
            lock (_fileLock)
            {
                try
                {
                    json = JsonSerializer.Serialize(_data, new JsonSerializerOptions { WriteIndented = true });
                }
                catch (Exception ex)
                {
                    _logService.LogError($"[ERROR] Failed to serialize guild-licenses.json: {ex.Message}", "GuildLicenseService", ex);
                    return;
                }
            }

            try
            {
                File.WriteAllText(_licenseFilePath, json);
                _logService.LogSuccess($"[SUCCESS] Saved guild licenses to {_licenseFilePath}.", "GuildLicenseService");
            }
            catch (Exception ex)
            {
                _logService.LogError($"[ERROR] Failed to save guild-licenses.json: {ex.Message}", "GuildLicenseService", ex);
            }
        }

        public Task<bool> UpdateGuildNameAsync(string guildId, string guildName)
        {
            if (string.IsNullOrWhiteSpace(guildId) || string.IsNullOrWhiteSpace(guildName)) return Task.FromResult(false);
            lock (_fileLock)
            {
                var state = EnsureGuild(guildId);
                state.GuildName = guildName;
                SaveData();
                return Task.FromResult(true);
            }
        }

        private GuildLicenseState EnsureGuild(string guildId)
        {
            return _data.Guilds.GetOrAdd(guildId, _ => new GuildLicenseState());
        }

        public Task<int> GetPurchasedBasesAsync(string guildId)
        {
            if (string.IsNullOrWhiteSpace(guildId)) return Task.FromResult(0);
            if (_data.Guilds.TryGetValue(guildId, out var state))
            {
                return Task.FromResult(Math.Max(0, state.MaxBases - 4));
            }
            return Task.FromResult(0);
        }

        public Task<bool> IncrementLicenseAsync(string guildId, int limit = 6)
        {
            if (string.IsNullOrWhiteSpace(guildId)) return Task.FromResult(false);

            lock (_fileLock)
            {
                var state = EnsureGuild(guildId);
                int purchased = state.MaxBases - 4;
                if (purchased >= limit) return Task.FromResult(false);
                
                state.MaxBases++;
                SaveData();
                return Task.FromResult(true);
            }
        }

        public async Task<string?> ResolveGuildIdAsync(string playerUid)
        {
            try
            {
                return await _saveService.ExtractGuildIdFromLevelSavAsync(playerUid);
            }
            catch (Exception ex)
            {
                _logService.LogError($"Failed to resolve Guild ID for Player {playerUid}: {ex.Message}", "GuildLicenseService", ex);
                return null;
            }
        }

        public Task<GuildLicenseState?> GetGuildStateAsync(string guildId)
        {
            if (string.IsNullOrWhiteSpace(guildId)) return Task.FromResult<GuildLicenseState?>(null);
            _data.Guilds.TryGetValue(guildId, out var state);
            return Task.FromResult(state);
        }

        public Task<bool> DepositToBankAsync(string guildId, string playerUid, int amount)
        {
            if (string.IsNullOrWhiteSpace(guildId)) return Task.FromResult(false);
            lock (_fileLock)
            {
                var state = EnsureGuild(guildId);
                state.GuildBankBalance += amount;
                
                int currentContribution = state.Contributions.GetValueOrDefault(playerUid, 0);
                state.Contributions[playerUid] = currentContribution + amount;
                
                SaveData();
                return Task.FromResult(true);
            }
        }

        public Task<bool> PurchaseInfrastructureAsync(string guildId, string playerUid, string structureType, int cost)
        {
            if (string.IsNullOrWhiteSpace(guildId)) return Task.FromResult(false);
            
            lock (_fileLock)
            {
                var state = EnsureGuild(guildId);
                
                // Check if bank has enough funds
                if (state.GuildBankBalance < cost)
                {
                    return Task.FromResult(false);
                }

                // Check caps based on structure type
                if (structureType == "GuildBaseSlot" && (state.MaxBases - 4) >= 6) return Task.FromResult(false);
                if (structureType == "BreedingPenSlot") { /* No hard cap specified, but we can allow it */ }
                if (structureType == "RanchSlot") { /* No hard cap specified */ }

                // Process Purchase
                state.GuildBankBalance -= cost;
                
                if (structureType == "GuildBaseSlot") state.MaxBases++;
                else if (structureType == "BreedingPenSlot") state.MaxBreedingPens++;
                else if (structureType == "RanchSlot") state.MaxRanches++;
                
                SaveData();
                return Task.FromResult(true);
            }
        }
    }
}

