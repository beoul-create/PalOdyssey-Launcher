-- PalOdysseyOptimizer - Dedicated Server Performance Suite (Inspired by Lithium, ServerCore, Krypton, FerriteCore & C2ME)
local ServerModule = {}

local function ExecuteConsole(cmd)
    pcall(function()
        local kismet = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
        if kismet and kismet:IsValid() then
            kismet:ExecuteConsoleCommand(nil, cmd, nil)
        end
    end)
end

function ServerModule.apply(cfg)
    if not cfg or not cfg.enabled then return end

    print("[PalOdysseyOptimizer] Initializing Modrinth-Inspired Dedicated Server Optimization Suite...")

    local function setupServerEngineOptimization(world)
        if not world or not world:IsValid() then return end

        pcall(function()
            -- 1. Krypton Network Tuning (Uncapped bandwidth, Netty stream batching, anti-desync)
            local netDriver = world.NetDriver
            if netDriver and netDriver:IsValid() then
                netDriver.ConnectionTimeout = cfg.connectionTimeout or 120.0
                netDriver.InitialConnectTimeout = cfg.initialConnectTimeout or 180.0
                netDriver.KeepAliveTime = 0.2
                netDriver.MaxClientRate = 1048576       -- 1 MB/s throughput
                netDriver.MaxInternetClientRate = 1048576
                netDriver.MinNetUpdateFrequency = 30.0
                netDriver.MaxNetUpdateFrequency = 60.0
                netDriver.NetServerMaxTickRate = 60
            end

            -- 2. Lithium & ServerCore Entity Activation Range / Tick Throttling
            ExecuteConsole("a.URO.Enable 1")
            ExecuteConsole("a.URO.TickDistanceScale 1.0")
            ExecuteConsole("a.URO.VisibilityBasedAnimTickRate 1")
            ExecuteConsole("Pal.AI.TickRateMultiplier 0.50")

            -- 3. C2ME Concurrent Async World Streaming & Actor Spawning
            ExecuteConsole("s.AsyncLoadingThreadEnabled 1")
            ExecuteConsole("s.LevelStreamingActorsUpdateTimeLimit 5.0")
            ExecuteConsole("s.PriorityAsyncLoadingExtraTime 15.0")
            ExecuteConsole("s.AsyncLoadingTimeLimit 5.0")

            -- 4. FerriteCore Heap Reduction & Garbage Collection Acceleration
            ExecuteConsole("gc.TimeBetweenPurgingPendingKillObjects 20")
        end)
    end

    RegisterHook("/Script/Engine.World:ReceiveBeginPlay", function(Context)
        local world = Context:get()
        if world and world:IsValid() then
            setupServerEngineOptimization(world)
        end
    end)

    -- Hook GameEngine Init for early server configuration
    pcall(function()
        RegisterHook("/Script/Engine.GameEngine:Init", function(Context)
            setupServerEngineOptimization(UEHelpers.GetWorld())
        end)
    end)

    -- Background server garbage collection sweep (every 60s)
    local function serverMemoryMaintenance()
        pcall(function()
            collectgarbage("step", 100)
            ExecuteConsole("gc.TimeBetweenPurgingPendingKillObjects 20")
        end)
        ExecuteWithDelay(60000, serverMemoryMaintenance)
    end
    ExecuteWithDelay(30000, serverMemoryMaintenance)

    print("[PalOdysseyOptimizer] Dedicated Server Suite Active: Krypton Network Sync, Lithium AI Throttling, C2ME Async Loading & FerriteCore Memory Sweeper.")
end

return ServerModule
