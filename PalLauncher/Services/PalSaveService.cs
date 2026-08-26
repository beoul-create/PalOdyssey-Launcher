using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.IO;
using System.IO.Compression;
using System.Net.Http;
using System.Net.Http.Headers;
using System.Text;
using System.Text.Json;
using System.Threading.Tasks;
using PalLauncher.Models;
using PalLauncher.Services.Interfaces;

namespace PalLauncher.Services
{
    public interface IPalSaveService
    {
        string? FindSaveGamesDirectory();
        List<string> GetAvailablePlayerUids();
        Task<PlayerEconomyProfile?> ReadPlayerProfileAsync(string playerUid);
        Task<bool> UpdateTechnologyPointsAsync(string playerUid, int pointDelta, bool isAbsolute = false);
        Task<bool> UpdateBossTechnologyPointsAsync(string playerUid, int pointDelta, bool isAbsolute = false);
        Task<bool> CreateBackupAsync(string playerUid);
        Task<bool> IsPlayerOnlineAsync(string playerUid);
        Task<bool> RequestWorldSaveAsync();
        string ResolvePlayerUid(string? userQuery);
        Task<string?> ExtractGuildIdFromLevelSavAsync(string playerUid);
        Task<bool> UpdatePalWorldSettingsAsync(int newBaseCap = 10);
        Task<bool> ApplyServerStabilityAndNetworkOptimizationsAsync(string? serverRootPath = null);
        Task<int> PruneExcessBackupsAsync(int maxBackupsToKeep = 24);
    }

    public class PlayerIdentityRecord
    {
        public string PlayerId { get; set; } = string.Empty;
        public string UserId { get; set; } = string.Empty;
        public string PlayerName { get; set; } = string.Empty;
        public string AccountName { get; set; } = string.Empty;
        public int Level { get; set; } = 1;
        public DateTime LastSeen { get; set; } = DateTime.UtcNow;
    }

    public class PalSaveService : IPalSaveService
    {
        private readonly ILogService _logService;
        private readonly string? _customSaveDirectory;
        private static readonly HttpClient _httpClient = CreateRestClient();

        private static readonly object _identityLock = new();
        private static readonly Dictionary<string, PlayerIdentityRecord> _playerIdentities = new(StringComparer.OrdinalIgnoreCase);
        private static bool _identitiesLoaded = false;
        private static readonly ConcurrentDictionary<string, (string GuildId, string GuildName, DateTime Timestamp)> _guildCache = new(StringComparer.OrdinalIgnoreCase);
        private static DateTime _lastLevelSavWriteTime = DateTime.MinValue;
        private static readonly string _identitiesFilePath = Path.Combine(
            Environment.GetEnvironmentVariable("LOCALAPPDATA") ?? Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
            "PalLauncher", "player_identities.json");

        private static void EnsurePlayerIdentitiesLoaded()
        {
            lock (_identityLock)
            {
                if (_identitiesLoaded) return;
                _identitiesLoaded = true;

                // Pre-seed known mappings
                _playerIdentities["9EDC20A9000000000000000000000000"] = new PlayerIdentityRecord
                {
                    PlayerId = "9EDC20A9000000000000000000000000",
                    UserId = "steam_76561198095071863",
                    PlayerName = "Beoul",
                    AccountName = "Beoul",
                    Level = 5
                };
                _playerIdentities["76561198095071863"] = _playerIdentities["9EDC20A9000000000000000000000000"];
                _playerIdentities["steam_76561198095071863"] = _playerIdentities["9EDC20A9000000000000000000000000"];
                _playerIdentities["Beoul"] = _playerIdentities["9EDC20A9000000000000000000000000"];

                _playerIdentities["BBC87443000000000000000000000000"] = new PlayerIdentityRecord
                {
                    PlayerId = "BBC87443000000000000000000000000",
                    UserId = "steam_76561198098116882",
                    PlayerName = "Chazz",
                    AccountName = "Chuck e Cheese",
                    Level = 7
                };
                _playerIdentities["76561198098116882"] = _playerIdentities["BBC87443000000000000000000000000"];
                _playerIdentities["steam_76561198098116882"] = _playerIdentities["BBC87443000000000000000000000000"];
                _playerIdentities["Chazz"] = _playerIdentities["BBC87443000000000000000000000000"];

                try
                {
                    if (File.Exists(_identitiesFilePath))
                    {
                        string json = File.ReadAllText(_identitiesFilePath);
                        var loaded = JsonSerializer.Deserialize<Dictionary<string, PlayerIdentityRecord>>(json);
                        if (loaded != null)
                        {
                            foreach (var kvp in loaded)
                            {
                                _playerIdentities[kvp.Key] = kvp.Value;
                                if (!string.IsNullOrWhiteSpace(kvp.Value.UserId))
                                {
                                    _playerIdentities[kvp.Value.UserId] = kvp.Value;
                                    string cleanSteam = kvp.Value.UserId.Replace("steam_", "");
                                    _playerIdentities[cleanSteam] = kvp.Value;
                                }
                                if (!string.IsNullOrWhiteSpace(kvp.Value.PlayerName))
                                {
                                    _playerIdentities[kvp.Value.PlayerName] = kvp.Value;
                                }
                            }
                        }
                    }
                }
                catch { }
            }
        }

        public static void RegisterPlayerIdentity(string playerId, string userId, string playerName, string accountName, int level)
        {
            if (string.IsNullOrWhiteSpace(playerId)) return;
            EnsurePlayerIdentitiesLoaded();

            lock (_identityLock)
            {
                var rec = new PlayerIdentityRecord
                {
                    PlayerId = playerId,
                    UserId = userId,
                    PlayerName = playerName,
                    AccountName = accountName,
                    Level = Math.Max(1, level),
                    LastSeen = DateTime.UtcNow
                };

                _playerIdentities[playerId] = rec;
                if (!string.IsNullOrWhiteSpace(userId))
                {
                    _playerIdentities[userId] = rec;
                    string cleanSteam = userId.Replace("steam_", "");
                    _playerIdentities[cleanSteam] = rec;
                }
                if (!string.IsNullOrWhiteSpace(playerName))
                {
                    _playerIdentities[playerName] = rec;
                }

                try
                {
                    string dir = Path.GetDirectoryName(_identitiesFilePath)!;
                    if (!Directory.Exists(dir)) Directory.CreateDirectory(dir);
                    var dictToSave = new Dictionary<string, PlayerIdentityRecord>();
                    foreach (var r in _playerIdentities.Values)
                    {
                        dictToSave[r.PlayerId] = r;
                    }
                    string json = JsonSerializer.Serialize(dictToSave, new JsonSerializerOptions { WriteIndented = true });
                    File.WriteAllText(_identitiesFilePath, json);
                }
                catch { }
            }
        }

        private static HttpClient CreateRestClient()
        {
            var client = new HttpClient { Timeout = TimeSpan.FromSeconds(3) };
            var authBytes = Encoding.UTF8.GetBytes("admin:0012");
            client.DefaultRequestHeaders.Authorization = new AuthenticationHeaderValue("Basic", Convert.ToBase64String(authBytes));
            return client;
        }

        public PalSaveService(ILogService logService, string? customSaveDirectory = null)
        {
            _logService = logService;
            _customSaveDirectory = customSaveDirectory;
        }

        public string? FindServerConfigDirectory(string? serverRootPath = null)
        {
            if (!string.IsNullOrWhiteSpace(serverRootPath))
            {
                string c1 = Path.Combine(serverRootPath, "Pal", "Saved", "Config", "WindowsServer");
                if (Directory.Exists(c1)) return c1;
                string c2 = Path.Combine(serverRootPath, "..", "PalServer", "Pal", "Saved", "Config", "WindowsServer");
                if (Directory.Exists(c2)) return Path.GetFullPath(c2);
            }

            var worldDir = FindSaveGamesDirectory();
            if (!string.IsNullOrEmpty(worldDir))
            {
                string candidate = Path.GetFullPath(Path.Combine(worldDir, "..", "..", "..", "Config", "WindowsServer"));
                if (Directory.Exists(candidate)) return candidate;
            }

            string[] candidates = {
                @"C:\SteamLibrary\steamapps\common\PalServer\Pal\Saved\Config\WindowsServer",
                @"D:\SteamLibrary\steamapps\common\PalServer\Pal\Saved\Config\WindowsServer",
                @"E:\SteamLibrary\steamapps\common\PalServer\Pal\Saved\Config\WindowsServer",
                @"C:\Program Files (x86)\Steam\steamapps\common\PalServer\Pal\Saved\Config\WindowsServer",
                @"C:\Program Files\Steam\steamapps\common\PalServer\Pal\Saved\Config\WindowsServer",
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), @"Pal\Saved\Config\WindowsServer")
            };

            foreach (var c in candidates)
            {
                if (Directory.Exists(c)) return c;
            }

            return null;
        }

        public async Task<bool> ApplyServerStabilityAndNetworkOptimizationsAsync(string? serverRootPath = null)
        {
            try
            {
                string? configDir = FindServerConfigDirectory(serverRootPath);
                if (string.IsNullOrEmpty(configDir))
                {
                    _logService.LogInfo("Server config directory not found. Stability settings will apply when server files are detected.", "ServerOptimizer");
                    return false;
                }

                if (!Directory.Exists(configDir)) Directory.CreateDirectory(configDir);

                // 1. Optimize PalWorldSettings.ini (AutoSaveSpan=300s to eliminate save-write hitches/RPC drops)
                string settingsIni = Path.Combine(configDir, "PalWorldSettings.ini");
                if (File.Exists(settingsIni))
                {
                    string content = await File.ReadAllTextAsync(settingsIni);
                    string autoSavePattern = @"AutoSaveSpan=[0-9]+(\.[0-9]+)?";
                    if (System.Text.RegularExpressions.Regex.IsMatch(content, autoSavePattern))
                    {
                        content = System.Text.RegularExpressions.Regex.Replace(content, autoSavePattern, "AutoSaveSpan=300.000000");
                    }
                    else if (content.Contains("OptionSettings=("))
                    {
                        content = content.Replace("OptionSettings=(", "OptionSettings=(AutoSaveSpan=300.000000,");
                    }

                    string npcInvulPattern = @"bEnableInvulnerableNPC=[A-Za-z]+";
                    if (System.Text.RegularExpressions.Regex.IsMatch(content, npcInvulPattern))
                    {
                        content = System.Text.RegularExpressions.Regex.Replace(content, npcInvulPattern, "bEnableInvulnerableNPC=False");
                    }

                    await File.WriteAllTextAsync(settingsIni, content);
                    _logService.LogSuccess("PalWorldSettings.ini tuned: AutoSaveSpan=300s (prevents cutscene/statue save-hitches).", "ServerOptimizer");
                }

                // 2. Optimize Engine.ini (Socket Timeout & Ghost Session Eviction Rules)
                string engineIni = Path.Combine(configDir, "Engine.ini");
                string engineContent = File.Exists(engineIni) ? await File.ReadAllTextAsync(engineIni) : "";

                string netDriverSection = @"[/Script/OnlineSubsystemUtils.IpNetDriver]
ConnectionTimeout=30.0
InitialConnectTimeout=45.0
KeepAliveTime=0.2
MaxClientRate=100000
MaxInternetClientRate=100000";

                string gcSection = @"[/Script/Engine.GarbageCollectionSettings]
gc.TimeBetweenPurgingPendingKillObjects=45
gc.IncrementalBeginTimeSlice=0.002
gc.MinDesiredTimeBetweenGarbageCollections=20
gc.CreateGCClusters=True
gc.ActorClusteringEnabled=True
gc.NumRetriesBeforeForcingGC=5";

                string sysSection = @"[SystemSettings]
net.MaxNetTickRate=60
net.MinNetUpdateFrequency=10
r.TextureStreaming=0
r.ShaderPipelineCache.BatchTime=2.0";

                if (!engineContent.Contains("[/Script/OnlineSubsystemUtils.IpNetDriver]"))
                {
                    engineContent = (engineContent.Trim() + Environment.NewLine + Environment.NewLine + netDriverSection).Trim();
                }

                if (!engineContent.Contains("[/Script/Engine.GarbageCollectionSettings]"))
                {
                    engineContent = (engineContent.Trim() + Environment.NewLine + Environment.NewLine + gcSection).Trim();
                }

                if (!engineContent.Contains("[SystemSettings]"))
                {
                    engineContent = (engineContent.Trim() + Environment.NewLine + Environment.NewLine + sysSection).Trim();
                }

                await File.WriteAllTextAsync(engineIni, engineContent);
                _logService.LogSuccess("Engine.ini optimized: Ghost Session Eviction, 60Hz Net Tick, and Low-Overhead Server GC active.", "ServerOptimizer");
                return true;
            }
            catch (Exception ex)
            {
                _logService.LogWarning($"Could not apply server stability optimizations: {ex.Message}", "ServerOptimizer");
                return false;
            }
        }

        public async Task<int> PruneExcessBackupsAsync(int maxBackupsToKeep = 24)
        {
            return await Task.Run(() =>
            {
                try
                {
                    var worldDir = FindSaveGamesDirectory();
                    if (string.IsNullOrEmpty(worldDir)) return 0;

                    string backupRoot = Path.Combine(worldDir, "backup");
                    if (!Directory.Exists(backupRoot)) return 0;

                    int totalPruned = 0;
                    long totalBytesFreed = 0;

                    // 1. Prune world backup snapshots
                    string worldBackupDir = Path.Combine(backupRoot, "world");
                    if (Directory.Exists(worldBackupDir))
                    {
                        var dirList = new DirectoryInfo(worldBackupDir).GetDirectories();
                        if (dirList.Length > maxBackupsToKeep)
                        {
                            var sorted = System.Linq.Enumerable.OrderBy(dirList, d => d.CreationTimeUtc).ToList();
                            int toDelete = sorted.Count - maxBackupsToKeep;

                            for (int i = 0; i < toDelete; i++)
                            {
                                try
                                {
                                    long dirSize = 0;
                                    foreach (var file in sorted[i].GetFiles("*", SearchOption.AllDirectories))
                                    {
                                        dirSize += file.Length;
                                    }
                                    sorted[i].Delete(recursive: true);
                                    totalPruned++;
                                    totalBytesFreed += dirSize;
                                }
                                catch { }
                            }
                        }
                    }

                    // 2. Prune player backup snapshots
                    string playerBackupDir = Path.Combine(backupRoot, "player");
                    if (Directory.Exists(playerBackupDir))
                    {
                        var playerDirs = new DirectoryInfo(playerBackupDir).GetDirectories();
                        if (playerDirs.Length > maxBackupsToKeep)
                        {
                            var sorted = System.Linq.Enumerable.OrderBy(playerDirs, d => d.CreationTimeUtc).ToList();
                            int toDelete = sorted.Count - maxBackupsToKeep;

                            for (int i = 0; i < toDelete; i++)
                            {
                                try
                                {
                                    long dirSize = 0;
                                    foreach (var file in sorted[i].GetFiles("*", SearchOption.AllDirectories))
                                    {
                                        dirSize += file.Length;
                                    }
                                    sorted[i].Delete(recursive: true);
                                    totalPruned++;
                                    totalBytesFreed += dirSize;
                                }
                                catch { }
                            }
                        }
                    }

                    // 3. Prune economy backups
                    string economyBackupDir = Path.Combine(backupRoot, "economy_backups");
                    if (Directory.Exists(economyBackupDir))
                    {
                        var economyFiles = new DirectoryInfo(economyBackupDir).GetFiles("*.sav");
                        if (economyFiles.Length > maxBackupsToKeep)
                        {
                            var sorted = System.Linq.Enumerable.OrderBy(economyFiles, f => f.CreationTimeUtc).ToList();
                            int toDelete = sorted.Count - maxBackupsToKeep;

                            for (int i = 0; i < toDelete; i++)
                            {
                                try
                                {
                                    long fSize = sorted[i].Length;
                                    sorted[i].Delete();
                                    totalPruned++;
                                    totalBytesFreed += fSize;
                                }
                                catch { }
                            }
                        }
                    }

                    if (totalPruned > 0)
                    {
                        double freedMb = totalBytesFreed / (1024.0 * 1024.0);
                        _logService.LogSuccess($"[STORAGE GUARD] Backup retention enforced: Purged {totalPruned} stale backup snapshots ({freedMb:F1} MB freed, kept {maxBackupsToKeep} recent).", "SaveService");
                    }

                    return totalPruned;
                }
                catch (Exception ex)
                {
                    _logService.LogWarning($"Backup pruning encountered: {ex.Message}", "SaveService");
                    return 0;
                }
            });
        }

        public string? FindSaveGamesDirectory()
        {
            if (!string.IsNullOrWhiteSpace(_customSaveDirectory) && Directory.Exists(_customSaveDirectory))
            {
                return _customSaveDirectory;
            }

            string[] candidates = {
                @"C:\SteamLibrary\steamapps\common\PalServer\Pal\Saved\SaveGames\0",
                @"D:\SteamLibrary\steamapps\common\PalServer\Pal\Saved\SaveGames\0",
                @"E:\SteamLibrary\steamapps\common\PalServer\Pal\Saved\SaveGames\0",
                @"C:\Program Files (x86)\Steam\steamapps\common\PalServer\Pal\Saved\SaveGames\0",
                @"C:\Program Files\Steam\steamapps\common\PalServer\Pal\Saved\SaveGames\0",
                Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData), @"Pal\Saved\SaveGames\0")
            };

            foreach (var candidate in candidates)
            {
                if (Directory.Exists(candidate))
                {
                    var worldDirs = Directory.GetDirectories(candidate);
                    foreach (var worldDir in worldDirs)
                    {
                        string playersDir = Path.Combine(worldDir, "Players");
                        if (Directory.Exists(playersDir))
                        {
                            return worldDir;
                        }
                    }
                    if (worldDirs.Length > 0) return worldDirs[0];
                }
            }

            return null;
        }

        public List<string> GetAvailablePlayerUids()
        {
            var result = new List<string>();
            var worldDir = FindSaveGamesDirectory();
            if (string.IsNullOrEmpty(worldDir)) return result;

            string playersDir = Path.Combine(worldDir, "Players");
            if (Directory.Exists(playersDir))
            {
                var files = Directory.GetFiles(playersDir, "*.sav");
                foreach (var file in files)
                {
                    string filename = Path.GetFileNameWithoutExtension(file);
                    if (!filename.Equals("Level", StringComparison.OrdinalIgnoreCase) &&
                        !filename.Equals("LevelMeta", StringComparison.OrdinalIgnoreCase))
                    {
                        result.Add(filename);
                    }
                }
            }
            return result;
        }

        private static DateTime _lastRestCheckTime = DateTime.MinValue;
        private static string? _lastRestPlayersJson = null;

        public string ResolvePlayerUid(string? userQuery)
        {
            EnsurePlayerIdentitiesLoaded();
            var uids = GetAvailablePlayerUids();

            if (!string.IsNullOrWhiteSpace(userQuery))
            {
                string q = userQuery.Trim();

                // 1. Live REST API Check (skip during tests or if cached recently)
                if (string.IsNullOrEmpty(_customSaveDirectory))
                {
                    try
                    {
                        string? json = null;
                        if ((DateTime.UtcNow - _lastRestCheckTime).TotalSeconds < 3 && _lastRestPlayersJson != null)
                        {
                            json = _lastRestPlayersJson;
                        }
                        else
                        {
                            using var cts = new CancellationTokenSource(TimeSpan.FromMilliseconds(300));
                            var liveResp = _httpClient.GetAsync("http://127.0.0.1:8212/v1/api/players", cts.Token).GetAwaiter().GetResult();
                            if (liveResp.IsSuccessStatusCode)
                            {
                                json = liveResp.Content.ReadAsStringAsync().GetAwaiter().GetResult();
                                _lastRestPlayersJson = json;
                                _lastRestCheckTime = DateTime.UtcNow;
                            }
                        }

                        if (!string.IsNullOrWhiteSpace(json))
                        {
                            using var doc = JsonDocument.Parse(json);
                            if (doc.RootElement.TryGetProperty("players", out var arr) && arr.ValueKind == JsonValueKind.Array)
                            {
                                foreach (var item in arr.EnumerateArray())
                                {
                                    string pid = item.TryGetProperty("playerId", out var p) ? p.GetString() ?? "" : "";
                                    string uid = item.TryGetProperty("userId", out var u) ? u.GetString() ?? "" : "";
                                    string name = item.TryGetProperty("name", out var n) ? n.GetString() ?? "" : "";
                                    string acc = item.TryGetProperty("accountName", out var a) ? a.GetString() ?? "" : "";
                                    int lvl = 1;
                                    if (item.TryGetProperty("level", out var lvlProp))
                                    {
                                        if (lvlProp.ValueKind == JsonValueKind.Number) lvl = lvlProp.GetInt32();
                                        else if (int.TryParse(lvlProp.GetString(), out int pl)) lvl = pl;
                                    }

                                    if (!string.IsNullOrWhiteSpace(pid))
                                    {
                                        RegisterPlayerIdentity(pid, uid, name, acc, lvl);
                                    }

                                    if (pid.Equals(q, StringComparison.OrdinalIgnoreCase) ||
                                        uid.Equals(q, StringComparison.OrdinalIgnoreCase) ||
                                        uid.Contains(q, StringComparison.OrdinalIgnoreCase) ||
                                        name.Equals(q, StringComparison.OrdinalIgnoreCase) ||
                                        acc.Equals(q, StringComparison.OrdinalIgnoreCase))
                                    {
                                        if (!string.IsNullOrWhiteSpace(pid)) return pid;
                                    }
                                }
                            }
                        }
                    }
                    catch { }
                }

                // 2. Check persistent Player Identities Registry (for offline lookups)
                lock (_identityLock)
                {
                    foreach (var rec in _playerIdentities.Values)
                    {
                        if (rec.PlayerId.Equals(q, StringComparison.OrdinalIgnoreCase) ||
                            rec.UserId.Equals(q, StringComparison.OrdinalIgnoreCase) ||
                            rec.UserId.Contains(q, StringComparison.OrdinalIgnoreCase) ||
                            rec.PlayerName.Equals(q, StringComparison.OrdinalIgnoreCase) ||
                            rec.AccountName.Equals(q, StringComparison.OrdinalIgnoreCase) ||
                            (!string.IsNullOrWhiteSpace(rec.UserId) && q.Contains(rec.UserId, StringComparison.OrdinalIgnoreCase)))
                        {
                            return rec.PlayerId;
                        }
                    }
                }

                // 3. Match against available .sav filenames
                string cleanQuery = q.Replace("-", "").ToUpperInvariant();
                foreach (var uid in uids)
                {
                    if (uid.Equals(cleanQuery, StringComparison.OrdinalIgnoreCase) ||
                        uid.StartsWith(cleanQuery, StringComparison.OrdinalIgnoreCase))
                    {
                        return uid;
                    }
                }

                if (uids.Count == 1) return uids[0];
                if (cleanQuery.Length >= 4) return cleanQuery;
            }

            return uids.Count > 0 ? uids[0] : "9EDC20A9000000000000000000000000";
        }

        public async Task<bool> IsPlayerOnlineAsync(string playerUid)
        {
            try
            {
                var resp = await _httpClient.GetAsync("http://127.0.0.1:8212/v1/api/players");
                if (resp.IsSuccessStatusCode)
                {
                    string json = await resp.Content.ReadAsStringAsync();
                    using var doc = JsonDocument.Parse(json);
                    if (doc.RootElement.TryGetProperty("players", out var arr) && arr.ValueKind == JsonValueKind.Array)
                    {
                        foreach (var item in arr.EnumerateArray())
                        {
                            if (item.TryGetProperty("playerId", out var pid) &&
                                pid.GetString()?.Equals(playerUid, StringComparison.OrdinalIgnoreCase) == true)
                            {
                                return true;
                            }
                            if (item.TryGetProperty("userId", out var uid) &&
                                uid.GetString()?.Equals(playerUid, StringComparison.OrdinalIgnoreCase) == true)
                            {
                                return true;
                            }
                        }
                    }
                }
            }
            catch { }
            return false;
        }

        public async Task<bool> RequestWorldSaveAsync()
        {
            try
            {
                var resp = await _httpClient.PostAsync("http://127.0.0.1:8212/v1/api/save", null);
                return resp.IsSuccessStatusCode;
            }
            catch { return false; }
        }

        public async Task<bool> UpdatePalWorldSettingsAsync(int newBaseCap = 10)
        {
            try
            {
                var worldDir = FindSaveGamesDirectory();
                if (string.IsNullOrEmpty(worldDir)) return false;

                // Path relative to SaveGames/0
                string iniPath = Path.GetFullPath(Path.Combine(worldDir, "..", "..", "..", "Config", "WindowsServer", "PalWorldSettings.ini"));
                if (!File.Exists(iniPath)) return false;

                string content = await File.ReadAllTextAsync(iniPath);
                
                // Regex or string replace to update BaseCampMaxNumInGuild
                string pattern = @"BaseCampMaxNumInGuild=[0-9]+";
                if (System.Text.RegularExpressions.Regex.IsMatch(content, pattern))
                {
                    content = System.Text.RegularExpressions.Regex.Replace(content, pattern, $"BaseCampMaxNumInGuild={newBaseCap}");
                }
                else
                {
                    // If not found but we have the OptionSettings block, append it
                    content = content.Replace("OptionSettings=(", $"OptionSettings=(BaseCampMaxNumInGuild={newBaseCap},");
                }

                await File.WriteAllTextAsync(iniPath, content);
                _logService.LogSuccess($"[SERVER] Updated PalWorldSettings.ini: BaseCampMaxNumInGuild={newBaseCap}", "SaveService");
                return true;
            }
            catch (Exception ex)
            {
                _logService.LogError($"Failed to update PalWorldSettings.ini: {ex.Message}", "SaveService", ex);
                return false;
            }
        }

        public async Task<string?> ExtractGuildIdFromLevelSavAsync(string playerUid)
        {
            if (string.IsNullOrWhiteSpace(playerUid)) return null;

            string cleanUid = playerUid.Replace("-", "").ToUpperInvariant();

            // 1. Check in-memory cache
            if (_guildCache.TryGetValue(cleanUid, out var cached) && (DateTime.UtcNow - cached.Timestamp).TotalSeconds < 60)
            {
                return cached.GuildId;
            }

            try
            {
                var worldDir = FindSaveGamesDirectory();
                if (string.IsNullOrEmpty(worldDir))
                {
                    return TryResolveGuildFromLicenses(cleanUid) ?? $"{cleanUid}_guild";
                }

                string levelSave = Path.Combine(worldDir, "Level.sav");
                if (!File.Exists(levelSave))
                {
                    return TryResolveGuildFromLicenses(cleanUid) ?? $"{cleanUid}_guild";
                }

                var fileInfo = new FileInfo(levelSave);
                if (fileInfo.LastWriteTimeUtc == _lastLevelSavWriteTime && _guildCache.TryGetValue(cleanUid, out var existing))
                {
                    return existing.GuildId;
                }

                // Request save if running
                await RequestWorldSaveAsync();

                byte[] rawBytes = await File.ReadAllBytesAsync(levelSave);
                byte[] decompressed = DecompressPalSave(rawBytes);
                _lastLevelSavWriteTime = fileInfo.LastWriteTimeUtc;

                // Convert clean UID to 16-byte Guid
                byte[] playerGuidBytes = new byte[16];
                if (cleanUid.Length >= 32)
                {
                    for (int i = 0; i < 16; i++)
                    {
                        playerGuidBytes[i] = Convert.ToByte(cleanUid.Substring(i * 2, 2), 16);
                    }
                }
                else
                {
                    Array.Copy(Encoding.ASCII.GetBytes(cleanUid.PadRight(16, '0')), playerGuidBytes, 16);
                }

                // Scan for the player's Guid
                int playerIdx = -1;
                for (int i = 0; i < decompressed.Length - 16; i++)
                {
                    bool match = true;
                    for (int j = 0; j < 16; j++)
                    {
                        if (decompressed[i + j] != playerGuidBytes[j])
                        {
                            match = false;
                            break;
                        }
                    }
                    if (match)
                    {
                        playerIdx = i;
                        break;
                    }
                }

                string resolvedGuildId = string.Empty;
                string resolvedGuildName = "Guild";

                if (playerIdx != -1)
                {
                    // Scan backward & forward for group_id (up to 8000 bytes)
                    int searchStart = Math.Max(0, playerIdx - 8000);
                    int searchEnd = Math.Min(decompressed.Length - 8, playerIdx + 8000);
                    byte[] groupIDHeader = Encoding.ASCII.GetBytes("group_id");

                    int groupIdIdx = -1;
                    for (int i = playerIdx; i >= searchStart; i--)
                    {
                        bool match = true;
                        for (int j = 0; j < groupIDHeader.Length; j++)
                        {
                            if (decompressed[i + j] != groupIDHeader[j])
                            {
                                match = false;
                                break;
                            }
                        }
                        if (match)
                        {
                            groupIdIdx = i;
                            break;
                        }
                    }

                    if (groupIdIdx == -1)
                    {
                        for (int i = playerIdx; i <= searchEnd; i++)
                        {
                            bool match = true;
                            for (int j = 0; j < groupIDHeader.Length; j++)
                            {
                                if (decompressed[i + j] != groupIDHeader[j])
                                {
                                    match = false;
                                    break;
                                }
                            }
                            if (match)
                            {
                                groupIdIdx = i;
                                break;
                            }
                        }
                    }

                    if (groupIdIdx != -1)
                    {
                        int guidOffset = FindAsciiSubstring(decompressed, "Guid", groupIdIdx, 128);
                        if (guidOffset > 0)
                        {
                            int guidValueOffset = guidOffset + 4 + 1 + 16;
                            if (guidValueOffset + 16 <= decompressed.Length)
                            {
                                var sb = new StringBuilder();
                                for (int b = 0; b < 16; b++)
                                {
                                    sb.Append(decompressed[guidValueOffset + b].ToString("X2"));
                                }
                                string candidateGuid = sb.ToString();
                                if (!candidateGuid.Equals("00000000000000000000000000000000", StringComparison.OrdinalIgnoreCase))
                                {
                                    resolvedGuildId = candidateGuid;
                                }
                            }
                        }
                    }
                }

                if (string.IsNullOrWhiteSpace(resolvedGuildId))
                {
                    resolvedGuildId = TryResolveGuildFromLicenses(cleanUid) ?? $"{cleanUid}_guild";
                }

                _guildCache[cleanUid] = (resolvedGuildId, resolvedGuildName, DateTime.UtcNow);
                _guildCache[playerUid] = (resolvedGuildId, resolvedGuildName, DateTime.UtcNow);
                return resolvedGuildId;
            }
            catch (Exception ex)
            {
                _logService.LogError($"Failed to extract guild id for {playerUid}", "SaveService", ex);
                return TryResolveGuildFromLicenses(cleanUid) ?? $"{cleanUid}_guild";
            }
        }

        private static string? TryResolveGuildFromLicenses(string playerUid)
        {
            try
            {
                string licensePath = Path.Combine(
                    Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData),
                    "PalLauncher", "guild-licenses.json");
                if (File.Exists(licensePath))
                {
                    string json = File.ReadAllText(licensePath);
                    using var doc = JsonDocument.Parse(json);
                    if (doc.RootElement.TryGetProperty("guilds", out var guildsObj))
                    {
                        foreach (var prop in guildsObj.EnumerateObject())
                        {
                            string gId = prop.Name;
                            if (prop.Value.TryGetProperty("contributions", out var contribObj))
                            {
                                foreach (var c in contribObj.EnumerateObject())
                                {
                                    if (c.Name.Equals(playerUid, StringComparison.OrdinalIgnoreCase) ||
                                        c.Name.Replace("-", "").Equals(playerUid.Replace("-", ""), StringComparison.OrdinalIgnoreCase))
                                    {
                                        return gId;
                                    }
                                }
                            }
                        }
                    }
                }
            }
            catch { }
            return null;
        }

        public async Task<bool> CreateBackupAsync(string playerUid)
        {
            try
            {
                var worldDir = FindSaveGamesDirectory();
                if (string.IsNullOrEmpty(worldDir)) return false;

                string playerSave = Path.Combine(worldDir, "Players", $"{playerUid}.sav");
                if (!File.Exists(playerSave)) return false;

                string backupDir = Path.Combine(worldDir, "backup", "economy_backups");
                if (!Directory.Exists(backupDir)) Directory.CreateDirectory(backupDir);

                string timestamp = DateTime.UtcNow.ToString("yyyyMMdd_HHmmss");
                string backupFile = Path.Combine(backupDir, $"{timestamp}_{playerUid}.sav");

                await Task.Run(() => File.Copy(playerSave, backupFile, overwrite: true));
                _logService.LogSuccess($"[SECURITY] Automated economy backup created: {Path.GetFileName(backupFile)}", "SaveService");
                return true;
            }
            catch (Exception ex)
            {
                _logService.LogWarning($"Failed to create save backup: {ex.Message}", "SaveService");
                return false;
            }
        }

        public async Task<PlayerEconomyProfile?> ReadPlayerProfileAsync(string playerUid)
        {
            EnsurePlayerIdentitiesLoaded();
            string actualUid = ResolvePlayerUid(playerUid);
            string resolvedPlayerName = "Pioneer";
            int resolvedLevel = 1;

            lock (_identityLock)
            {
                if (_playerIdentities.TryGetValue(actualUid, out var rec) ||
                    (!string.IsNullOrWhiteSpace(playerUid) && _playerIdentities.TryGetValue(playerUid, out rec)))
                {
                    if (!string.IsNullOrWhiteSpace(rec.PlayerName)) resolvedPlayerName = rec.PlayerName;
                    if (rec.Level > 0) resolvedLevel = rec.Level;
                }
            }

            try
            {
                var liveResp = await _httpClient.GetAsync("http://127.0.0.1:8212/v1/api/players");
                if (liveResp.IsSuccessStatusCode)
                {
                    string json = await liveResp.Content.ReadAsStringAsync();
                    using var doc = JsonDocument.Parse(json);
                    if (doc.RootElement.TryGetProperty("players", out var arr) && arr.ValueKind == JsonValueKind.Array)
                    {
                        foreach (var item in arr.EnumerateArray())
                        {
                            string pid = item.TryGetProperty("playerId", out var p) ? p.GetString() ?? "" : "";
                            string uid = item.TryGetProperty("userId", out var u) ? u.GetString() ?? "" : "";
                            string name = item.TryGetProperty("name", out var n) ? n.GetString() ?? "" : "";
                            string acc = item.TryGetProperty("accountName", out var a) ? a.GetString() ?? "" : "";

                            if (pid.Equals(actualUid, StringComparison.OrdinalIgnoreCase) ||
                                uid.Equals(actualUid, StringComparison.OrdinalIgnoreCase) ||
                                uid.Contains(playerUid, StringComparison.OrdinalIgnoreCase) ||
                                name.Equals(playerUid, StringComparison.OrdinalIgnoreCase) ||
                                pid.Equals(playerUid, StringComparison.OrdinalIgnoreCase))
                            {
                                if (!string.IsNullOrWhiteSpace(name)) resolvedPlayerName = name;
                                else if (!string.IsNullOrWhiteSpace(acc)) resolvedPlayerName = acc;

                                if (item.TryGetProperty("level", out var lvlProp))
                                {
                                    if (lvlProp.ValueKind == JsonValueKind.Number) resolvedLevel = lvlProp.GetInt32();
                                    else if (int.TryParse(lvlProp.GetString(), out int parsedLvl)) resolvedLevel = parsedLvl;
                                }

                                if (!string.IsNullOrWhiteSpace(pid))
                                {
                                    actualUid = pid;
                                    RegisterPlayerIdentity(pid, uid, resolvedPlayerName, acc, resolvedLevel);
                                }
                                break;
                            }
                        }
                    }
                }
            }
            catch { }

            var worldDir = FindSaveGamesDirectory();
            int techPoints = 0;
            int bossTechPoints = 0;

            // Check for live-players.json written by live in-game UE4SS optimizer
            try
            {
                string localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
                string[] liveSyncCandidates = {
                    Path.Combine(localAppData, "PalLauncher", "live-players.json"),
                    Path.Combine(localAppData, "Pal", "Saved", "Config", "Windows", "live-players.json"),
                    @"C:\SteamLibrary\steamapps\common\PalServer\Pal\Binaries\Win64\ue4ss\Mods\PalOdysseyOptimizer\live-players.json",
                    @"Pal\Binaries\Win64\ue4ss\Mods\PalOdysseyOptimizer\live-players.json",
                    @"ue4ss\Mods\PalOdysseyOptimizer\live-players.json",
                    "live-players.json"
                };

                foreach (var liveFile in liveSyncCandidates)
                {
                    if (File.Exists(liveFile))
                    {
                        try
                        {
                            string liveJson = await File.ReadAllTextAsync(liveFile);
                            if (!string.IsNullOrWhiteSpace(liveJson))
                            {
                                using var doc = JsonDocument.Parse(liveJson);
                                if (doc.RootElement.TryGetProperty("players", out var playersObj))
                                {
                                    var props = playersObj.EnumerateObject().ToList();
                                    bool matched = false;

                                    foreach (var pProp in props)
                                    {
                                        string pKey = pProp.Name.Replace("-", "").ToUpperInvariant();
                                        string cleanActual = actualUid.Replace("-", "").ToUpperInvariant();
                                        string cleanPlayer = (playerUid ?? "").Replace("-", "").ToUpperInvariant();

                                        bool isMatch = pKey == cleanActual ||
                                                       pKey == cleanPlayer ||
                                                       (!string.IsNullOrEmpty(cleanPlayer) && (pKey.Contains(cleanPlayer) || cleanPlayer.Contains(pKey))) ||
                                                       (!string.IsNullOrEmpty(cleanActual) && (pKey.Contains(cleanActual) || cleanActual.Contains(pKey)));

                                        if (isMatch)
                                        {
                                            var pVal = pProp.Value;
                                            if (pVal.TryGetProperty("unusedTechnologyPoints", out var techVal) && techVal.TryGetInt32(out int liveTech))
                                            {
                                                techPoints = liveTech;
                                            }
                                            if (pVal.TryGetProperty("unusedBossTechnologyPoints", out var bossVal) && bossVal.TryGetInt32(out int liveBoss))
                                            {
                                                bossTechPoints = liveBoss;
                                            }
                                            if (pVal.TryGetProperty("playerName", out var nameVal) && !string.IsNullOrWhiteSpace(nameVal.GetString()))
                                            {
                                                resolvedPlayerName = nameVal.GetString()!;
                                            }
                                            if (pVal.TryGetProperty("level", out var lvlVal) && lvlVal.TryGetInt32(out int liveLvl) && liveLvl > 0)
                                            {
                                                resolvedLevel = liveLvl;
                                            }
                                            matched = true;
                                            break;
                                        }
                                    }

                                    // Fallback for single connected player if UID format varies
                                    if (!matched && props.Count == 1)
                                    {
                                        var pVal = props[0].Value;
                                        if (pVal.TryGetProperty("unusedTechnologyPoints", out var techVal) && techVal.TryGetInt32(out int liveTech))
                                        {
                                            techPoints = liveTech;
                                        }
                                        if (pVal.TryGetProperty("unusedBossTechnologyPoints", out var bossVal) && bossVal.TryGetInt32(out int liveBoss))
                                        {
                                            bossTechPoints = liveBoss;
                                        }
                                        if (pVal.TryGetProperty("playerName", out var nameVal) && !string.IsNullOrWhiteSpace(nameVal.GetString()))
                                        {
                                            resolvedPlayerName = nameVal.GetString()!;
                                        }
                                        if (pVal.TryGetProperty("level", out var lvlVal) && lvlVal.TryGetInt32(out int liveLvl) && liveLvl > 0)
                                        {
                                            resolvedLevel = liveLvl;
                                        }
                                    }
                                }
                            }
                        }
                        catch { }
                    }
                }
            }
            catch { }

            if (!string.IsNullOrEmpty(worldDir))
            {
                string playerSave = Path.Combine(worldDir, "Players", $"{actualUid}.sav");
                if (!File.Exists(playerSave))
                {
                    string directSave = Path.Combine(worldDir, "Players", $"{playerUid}.sav");
                    if (File.Exists(directSave))
                    {
                        playerSave = directSave;
                        actualUid = playerUid;
                    }
                }

                if (File.Exists(playerSave))
                {
                    try
                    {
                        byte[] rawBytes = await File.ReadAllBytesAsync(playerSave);
                        byte[] decompressed = DecompressPalSave(rawBytes);

                        int extractedTech = ExtractIntProperty(decompressed, "UnusedTechnologyPoint", defaultValue: -1);
                        if (extractedTech < 0) extractedTech = ExtractIntProperty(decompressed, "TechnologyPoint", defaultValue: -1);

                        int extractedBoss = ExtractIntProperty(decompressed, "UnusedBossTechnologyPoint", defaultValue: -1);
                        if (extractedBoss < 0) extractedBoss = ExtractIntProperty(decompressed, "BossTechnologyPoint", defaultValue: -1);

                        int extractedLevel = ExtractIntProperty(decompressed, "Level", defaultValue: -1);

                        if (extractedTech >= 0) techPoints = extractedTech;
                        if (extractedBoss >= 0) bossTechPoints = extractedBoss;
                        if (extractedLevel > 0 && resolvedLevel <= 1) resolvedLevel = extractedLevel;
                    }
                    catch (Exception ex)
                    {
                        _logService.LogError($"Failed reading player save {actualUid}", "SaveService", ex);
                    }
                }
            }

            string resolvedSteamId = string.Empty;
            lock (_identityLock)
            {
                if (_playerIdentities.TryGetValue(actualUid, out var rec) ||
                    (!string.IsNullOrWhiteSpace(playerUid) && _playerIdentities.TryGetValue(playerUid, out rec)))
                {
                    if (!string.IsNullOrWhiteSpace(rec.UserId))
                    {
                        resolvedSteamId = rec.UserId.StartsWith("steam_", StringComparison.OrdinalIgnoreCase)
                            ? rec.UserId.Substring(6)
                            : rec.UserId;
                    }
                }
            }

            if (string.IsNullOrWhiteSpace(resolvedSteamId) && !string.IsNullOrWhiteSpace(playerUid))
            {
                string cleanQuery = playerUid.Trim();
                if (cleanQuery.StartsWith("steam_", StringComparison.OrdinalIgnoreCase))
                {
                    resolvedSteamId = cleanQuery.Substring(6);
                }
                else if (cleanQuery.StartsWith("7656") && cleanQuery.Length == 17)
                {
                    resolvedSteamId = cleanQuery;
                }
            }

            return new PlayerEconomyProfile
            {
                PlayerUid = actualUid,
                SteamId = resolvedSteamId,
                PlayerName = resolvedPlayerName != "Pioneer" ? resolvedPlayerName : $"Pioneer ({actualUid[..Math.Min(6, actualUid.Length)]})",
                TechnologyPoints = techPoints,
                BossTechnologyPoints = bossTechPoints,
                Level = Math.Max(1, resolvedLevel)
            };
        }

        public async Task<bool> UpdateTechnologyPointsAsync(string playerUid, int pointDelta, bool isAbsolute = false)
        {
            var worldDir = FindSaveGamesDirectory();
            if (string.IsNullOrEmpty(worldDir)) return false;

            string actualUid = ResolvePlayerUid(playerUid);
            string playerSave = Path.Combine(worldDir, "Players", $"{actualUid}.sav");
            if (!File.Exists(playerSave))
            {
                string direct = Path.Combine(worldDir, "Players", $"{playerUid}.sav");
                if (File.Exists(direct)) playerSave = direct;
                else return false;
            }

            // 1. Safety Protocol: Backup first
            await CreateBackupAsync(actualUid);

            try
            {
                byte[] rawBytes = await File.ReadAllBytesAsync(playerSave);
                byte[] decompressed = DecompressPalSave(rawBytes);

                int currentPoints = ExtractIntProperty(decompressed, "UnusedTechnologyPoint", defaultValue: 0);
                int newPoints = isAbsolute ? pointDelta : Math.Max(0, currentPoints + pointDelta);

                byte[] modified = SetIntProperty(decompressed, "UnusedTechnologyPoint", newPoints);
                byte[] recompressed = CompressPalSave(modified);

                string tmpFile = playerSave + ".tmp";
                await File.WriteAllBytesAsync(tmpFile, recompressed);
                File.Move(tmpFile, playerSave, overwrite: true);

                _logService.LogSuccess($"[ECONOMY] Updated Technology Points for {actualUid}: {currentPoints} -> {newPoints}", "SaveService");
                return true;
            }
            catch (Exception ex)
            {
                _logService.LogError($"Failed to update Tech Points for {actualUid}", "SaveService", ex);
                return false;
            }
        }

        public async Task<bool> UpdateBossTechnologyPointsAsync(string playerUid, int pointDelta, bool isAbsolute = false)
        {
            var worldDir = FindSaveGamesDirectory();
            if (string.IsNullOrEmpty(worldDir)) return false;

            string actualUid = ResolvePlayerUid(playerUid);
            string playerSave = Path.Combine(worldDir, "Players", $"{actualUid}.sav");
            if (!File.Exists(playerSave))
            {
                string direct = Path.Combine(worldDir, "Players", $"{playerUid}.sav");
                if (File.Exists(direct)) playerSave = direct;
                else return false;
            }

            // 1. Safety Protocol: Backup first
            await CreateBackupAsync(actualUid);

            try
            {
                byte[] rawBytes = await File.ReadAllBytesAsync(playerSave);
                byte[] decompressed = DecompressPalSave(rawBytes);

                int currentPoints = ExtractIntProperty(decompressed, "UnusedBossTechnologyPoint", defaultValue: 0);
                int newPoints = isAbsolute ? pointDelta : Math.Max(0, currentPoints + pointDelta);

                byte[] modified = SetIntProperty(decompressed, "UnusedBossTechnologyPoint", newPoints);
                byte[] recompressed = CompressPalSave(modified);

                string tmpFile = playerSave + ".tmp";
                await File.WriteAllBytesAsync(tmpFile, recompressed);
                File.Move(tmpFile, playerSave, overwrite: true);

                _logService.LogSuccess($"[ECONOMY] Updated Boss Technology Points for {actualUid}: {currentPoints} -> {newPoints}", "SaveService");
                return true;
            }
            catch (Exception ex)
            {
                _logService.LogError($"Failed to update Boss Tech Points for {actualUid}", "SaveService", ex);
                return false;
            }
        }

        public static byte[] DecompressPalSave(byte[] data)
        {
            if (data == null || data.Length < 12) return data ?? Array.Empty<byte>();

            if (data.Length >= 4 && data[0] == (byte)'G' && data[1] == (byte)'V' && data[2] == (byte)'A' && data[3] == (byte)'S')
            {
                return data;
            }

            if (data.Length >= 24 && data[20] == (byte)'G' && data[21] == (byte)'V' && data[22] == (byte)'A' && data[23] == (byte)'S')
            {
                byte[] gvas = new byte[data.Length - 20];
                Buffer.BlockCopy(data, 20, gvas, 0, gvas.Length);
                return gvas;
            }

            if (data.Length >= 16 && data[12] == (byte)'G' && data[13] == (byte)'V' && data[14] == (byte)'A' && data[15] == (byte)'S')
            {
                byte[] gvas = new byte[data.Length - 12];
                Buffer.BlockCopy(data, 12, gvas, 0, gvas.Length);
                return gvas;
            }

            try
            {
                using var inMs = new MemoryStream(data, 12, data.Length - 12);
                using var zlib = new ZLibStream(inMs, CompressionMode.Decompress);
                using var outMs = new MemoryStream();
                zlib.CopyTo(outMs);
                return outMs.ToArray();
            }
            catch
            {
                try
                {
                    using var inMs = new MemoryStream(data, 12, data.Length - 12);
                    using var deflate = new DeflateStream(inMs, CompressionMode.Decompress);
                    using var outMs = new MemoryStream();
                    deflate.CopyTo(outMs);
                    return outMs.ToArray();
                }
                catch { }
            }

            return data;
        }

        public static byte[] CompressPalSave(byte[] decompressedData)
        {
            using var outMs = new MemoryStream();
            using (var zlib = new ZLibStream(outMs, CompressionLevel.Optimal, leaveOpen: true))
            {
                zlib.Write(decompressedData, 0, decompressedData.Length);
            }

            byte[] compressedBytes = outMs.ToArray();

            byte[] finalData = new byte[12 + compressedBytes.Length];
            BitConverter.GetBytes(decompressedData.Length).CopyTo(finalData, 0);
            BitConverter.GetBytes(compressedBytes.Length).CopyTo(finalData, 4);
            Encoding.ASCII.GetBytes("PlM1").CopyTo(finalData, 8);
            compressedBytes.CopyTo(finalData, 12);

            return finalData;
        }

        private static int ExtractIntProperty(byte[] buffer, string propertyName, int defaultValue = 0)
        {
            int index = FindPropertyIndex(buffer, propertyName);
            if (index < 0 && propertyName.StartsWith("Technology", StringComparison.OrdinalIgnoreCase))
            {
                index = FindPropertyIndex(buffer, "TechnologyP");
                if (index < 0) index = FindPropertyIndex(buffer, "Technology");
            }
            if (index < 0 && propertyName.StartsWith("BossTechnology", StringComparison.OrdinalIgnoreCase))
            {
                index = FindPropertyIndex(buffer, "BossTechnology");
                if (index < 0) index = FindPropertyIndex(buffer, "BossTech");
            }
            if (index < 0) return defaultValue;

            int valOffset = LocatePropertyValueOffset(buffer, index, propertyName);
            if (valOffset >= 0 && valOffset + 4 <= buffer.Length)
            {
                return BitConverter.ToInt32(buffer, valOffset);
            }

            // Direct compact layout fallback: skip ASCII identifier characters
            int p = index;
            while (p < buffer.Length && ((buffer[p] >= 65 && buffer[p] <= 90) || (buffer[p] >= 97 && buffer[p] <= 122) || buffer[p] == 95))
            {
                p++;
            }
            while (p < buffer.Length && buffer[p] == 0) p++;

            if (p < buffer.Length)
            {
                if (p + 4 <= buffer.Length)
                {
                    int int32 = BitConverter.ToInt32(buffer, p);
                    if (int32 >= 0 && int32 < 100000)
                    {
                        return int32;
                    }
                }
                return buffer[p];
            }

            return defaultValue;
        }

        private static byte[] SetIntProperty(byte[] buffer, string propertyName, int newValue)
        {
            int index = FindPropertyIndex(buffer, propertyName);
            if (index < 0)
            {
                // Property not present; return existing buffer
                return buffer;
            }

            int valOffset = LocatePropertyValueOffset(buffer, index, propertyName);
            if (valOffset >= 0 && valOffset + 4 <= buffer.Length)
            {
                byte[] copy = (byte[])buffer.Clone();
                BitConverter.GetBytes(newValue).CopyTo(copy, valOffset);
                return copy;
            }

            return buffer;
        }

        private static int LocatePropertyValueOffset(byte[] buffer, int propNameIndex, string propName)
        {
            // In UE5 GVAS:
            // [PropertyName] [Null/Padding] [PropertyType e.g. IntProperty] [Padding] [Int64 Size] [Terminator 0] [Int32 Value]
            int searchStart = propNameIndex + propName.Length;
            int intPropIdx = FindAsciiSubstring(buffer, "IntProperty", searchStart, 64);
            if (intPropIdx >= 0)
            {
                // IntProperty header is ~25-30 bytes long until the 4-byte int payload
                // Skip IntProperty string + 1 byte null + type metadata
                int afterType = intPropIdx + "IntProperty".Length;
                while (afterType < buffer.Length && buffer[afterType] == 0) afterType++;
                // Skip length bytes (8 bytes for Int64 size) + 1 byte index/terminator
                int valuePos = afterType + 8 + 1;
                if (valuePos + 4 <= buffer.Length)
                {
                    return valuePos;
                }
            }
            return -1;
        }

        private static int FindPropertyIndex(byte[] buffer, string propertyName)
        {
            return FindAsciiSubstring(buffer, propertyName, 0, buffer.Length);
        }

        private static int FindAsciiSubstring(byte[] buffer, string text, int startIndex, int maxLookahead)
        {
            byte[] pattern = Encoding.ASCII.GetBytes(text);
            int end = Math.Min(buffer.Length - pattern.Length, startIndex + maxLookahead);

            for (int i = startIndex; i <= end; i++)
            {
                bool match = true;
                for (int j = 0; j < pattern.Length; j++)
                {
                    if (buffer[i + j] != pattern[j])
                    {
                        match = false;
                        break;
                    }
                }
                if (match) return i;
            }
            return -1;
        }
    }
}
