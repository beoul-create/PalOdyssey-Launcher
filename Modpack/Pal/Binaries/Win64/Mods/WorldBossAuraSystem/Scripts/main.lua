local ScriptDir = debug.getinfo(1, "S").source:gsub("^@", ""):gsub("[^/\\]+$", "")
package.path = ScriptDir .. "?.lua;" .. ScriptDir .. "../?.lua;" .. package.path
package.path = ScriptDir .. "../../shared/?.lua;" .. package.path
local Json = require("palodyssey_json")

local SAODeath = require("sao_death")
local WorldBoss = require("world_boss")
local LiveboardExport = require("liveboard_export")
local AutoShutdown = require("auto_shutdown")
local BossMusic = require("boss_music")

local function DecodeJson(Content)
    local decoders = {}
    if JSON and type(JSON.parse) == "function" then table.insert(decoders, JSON.parse) end
    if json and type(json.decode) == "function" then table.insert(decoders, json.decode) end
    if _G.json and type(_G.json.decode) == "function" then table.insert(decoders, _G.json.decode) end
    table.insert(decoders, Json.decode)
    for _, decoder in ipairs(decoders) do
        if type(decoder) == "function" then
            local ok, parsed = pcall(decoder, Content)
            if ok and type(parsed) == "table" then return parsed end
        end
    end
    return nil
end

local function LoadConfigFile()
    local Config = {
        ServerName = "PalOdyssey Official Modded Realm",
        MaxPlayers = 32,
        SpawnIntervalSeconds = 900,
        MaxActiveBosses = 1,
        SpawnCommandCooldownSeconds = 60,
        LiveboardExportIntervalSeconds = 15,
        DiscordWebhookURL = "YOUR_DISCORD_WEBHOOK_URL_HERE",
        BossPalPool = { "Kitsunebi", "ThunderDragonMan", "GrassMammoth", "WeaselDragon", "Anubis" },
        BossLevel = 100,
        BossScaleWorld = 3.0,
        BossScaleCaptured = 2.0,
        SpawnPoints = {
            { Name = "Grassy Behemoth Hills", X = 172000.0, Y = -420000.0, Z = 3500.0 },
            { Name = "Desolate Dunes", X = -120000.0, Y = -180000.0, Z = 4200.0 },
            { Name = "Astral Mountains", X = -320000.0, Y = 250000.0, Z = 12000.0 }
        }
    }

    local File = io.open(ScriptDir .. "../config.json", "r")
    if not File then
        print("[WorldBossAuraSystem] config.json was not found; using safe defaults.")
        return Config
    end
    local Content = File:read("*all")
    File:close()

    local Parsed = DecodeJson(Content)
    if not Parsed then
        print("[WorldBossAuraSystem] config.json could not be decoded; using safe defaults.")
        return Config
    end

    for Key, Value in pairs(Parsed) do Config[Key] = Value end
    return Config
end

local Config = LoadConfigFile()
SAODeath.Init()
WorldBoss.LoadConfig(Config)
WorldBoss.InitHooks()
AutoShutdown.Init()
BossMusic.Init()

-- Initial liveboard export
LiveboardExport.DumpState(WorldBoss.GetActiveBosses(), Config)

-- Periodic Background Timers (0% Game Thread Tick Overhead)
local LiveboardIntervalMs = math.max(5000, (tonumber(Config.LiveboardExportIntervalSeconds) or 15) * 1000)
local BossIntervalMs = math.max(60000, (tonumber(Config.SpawnIntervalSeconds) or 900) * 1000)

-- Initial Spawn Check (15 seconds after server start). Keep retrying while the
-- server is empty because the verified native SpawnMonster fallback requires
-- an online player's controller and cheat manager.
pcall(function()
    local delay = ExecuteInGameThreadWithDelay or ExecuteWithDelay
    if delay then
        local function TryInitialSpawn()
            pcall(function()
                local bosses = WorldBoss.GetActiveBosses()
                local count = 0
                for _ in pairs(bosses) do count = count + 1 end
                if count == 0 then
                    if WorldBoss.HasOnlinePlayer() then
                        print("[WorldBossAuraSystem] Triggering initial startup World Boss spawn...")
                        WorldBoss.SpawnEvent()
                    else
                        print("[WorldBossAuraSystem] Initial boss spawn waiting for an online player.")
                        delay(15000, TryInitialSpawn)
                    end
                end
            end)
        end
        delay(15000, TryInitialSpawn)
    end
end)

-- Reactive Join / Leave Event Hooks (Instant Liveboard Update)
local function TriggerReactiveUpdate()
    pcall(function()
        if ExecuteWithDelay then
            ExecuteWithDelay(1000, function()
                pcall(LiveboardExport.DumpState, WorldBoss.GetActiveBosses(), Config)
            end)
        else
            LiveboardExport.DumpState(WorldBoss.GetActiveBosses(), Config)
        end
    end)
end

local joinLeaveHooks = {
    "/Script/Engine.GameModeBase:OnPostLogin",
    "/Script/Engine.GameModeBase:Logout",
    "/Script/Pal.PalGameMode:OnPostLogin",
    "/Script/Pal.PalGameMode:Logout",
    "/Script/Pal.PalPlayerState:OnCompleteSyncPlayer"
}

for _, hookName in ipairs(joinLeaveHooks) do
    pcall(RegisterHook, hookName, function()
        TriggerReactiveUpdate()
    end)
end

local function StartGameThreadLoop(intervalMs, callback)
    if type(LoopInGameThreadWithDelay) == "function" then
        return LoopInGameThreadWithDelay(intervalMs, function() pcall(callback) end)
    end
    return LoopAsync(intervalMs, function()
        if type(ExecuteInGameThread) == "function" then
            ExecuteInGameThread(function() pcall(callback) end)
        else
            pcall(callback)
        end
        return false
    end)
end

-- Periodic background checks (Liveboard, Spawns, Despawns)
StartGameThreadLoop(LiveboardIntervalMs, function()
    LiveboardExport.DumpState(WorldBoss.GetActiveBosses(), Config)
end)
StartGameThreadLoop(BossIntervalMs, function() WorldBoss.SpawnEvent() end)
StartGameThreadLoop(30000, function() WorldBoss.CheckDespawns() end)
