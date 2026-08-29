local ScriptDir = debug.getinfo(1, "S").source:gsub("^@", ""):gsub("[^/\\]+$", "")
package.path = ScriptDir .. "?.lua;" .. ScriptDir .. "../?.lua;" .. package.path

local SAODeath = require("sao_death")
local WorldBoss = require("world_boss")
local LiveboardExport = require("liveboard_export")
local AutoShutdown = require("auto_shutdown")

local function DecodeJson(Content)
    local decoders = {}
    if JSON and type(JSON.parse) == "function" then table.insert(decoders, JSON.parse) end
    if json and type(json.decode) == "function" then table.insert(decoders, json.decode) end
    if _G.json and type(_G.json.decode) == "function" then table.insert(decoders, _G.json.decode) end
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
        SpawnIntervalSeconds = 1800,
        LiveboardExportIntervalSeconds = 15,
        DiscordWebhookURL = "YOUR_DISCORD_WEBHOOK_URL_HERE",
        BossPalPool = { "Foxparks", "Orserk", "Mammorest", "Chillet", "Anubis" },
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

-- Initial liveboard export
LiveboardExport.DumpState(WorldBoss.GetActiveBosses(), Config)

-- Periodic Background Timers (0% Game Thread Tick Overhead)
local LiveboardIntervalMs = math.max(5000, (tonumber(Config.LiveboardExportIntervalSeconds) or 15) * 1000)
local BossIntervalMs = math.max(60000, (tonumber(Config.SpawnIntervalSeconds) or 1800) * 1000)

-- 1. Periodic Liveboard Telemetry Dumper
LoopAsync(LiveboardIntervalMs, function()
    pcall(function()
        LiveboardExport.DumpState(WorldBoss.GetActiveBosses(), Config)
    end)
    return false -- continue looping
end)

-- 2. Periodic World Boss Spawner
LoopAsync(BossIntervalMs, function()
    pcall(function()
        WorldBoss.SpawnEvent()
    end)
    return false -- continue looping
end)
