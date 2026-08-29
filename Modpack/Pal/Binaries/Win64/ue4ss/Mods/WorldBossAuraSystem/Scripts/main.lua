local SAODeath = require("scripts.sao_death")
local WorldBoss = require("scripts.world_boss")
local LiveboardExport = require("scripts.liveboard_export")
local AutoShutdown = require("scripts.auto_shutdown")

local function LoadConfigFile()
    local File = io.open("Pal/Binaries/Win64/ue4ss/Mods/WorldBossAuraSystem/config.json", "r")
    if not File then return {} end
    local Content = File:read("*all")
    File:close()

    -- Simple JSON/Table unpack with fallback defaults
    return {
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
end

local Config = LoadConfigFile()
SAODeath.Init()
WorldBoss.LoadConfig(Config)
WorldBoss.InitHooks()
AutoShutdown.Init()

-- Initial liveboard export
LiveboardExport.DumpState(WorldBoss.GetActiveBosses(), Config)

-- Periodic Timer Ticker
local AccumulatedBossTime = 0
local AccumulatedLiveboardTime = 0
local LiveboardInterval = Config.LiveboardExportIntervalSeconds or 15

RegisterHook("/Script/Engine.World:Tick", function(Context, DeltaSeconds)
    local dt = DeltaSeconds:get()
    AccumulatedBossTime = AccumulatedBossTime + dt
    AccumulatedLiveboardTime = AccumulatedLiveboardTime + dt

    -- 1. Periodic World Boss Spawner (e.g. 1800s / 30m)
    if AccumulatedBossTime >= Config.SpawnIntervalSeconds then
        AccumulatedBossTime = 0
        WorldBoss.SpawnEvent()
    end

    -- 2. Periodic Liveboard Telemetry Dumper (e.g. 15s)
    if AccumulatedLiveboardTime >= LiveboardInterval then
        AccumulatedLiveboardTime = 0
        LiveboardExport.DumpState(WorldBoss.GetActiveBosses(), Config)
    end
end)
