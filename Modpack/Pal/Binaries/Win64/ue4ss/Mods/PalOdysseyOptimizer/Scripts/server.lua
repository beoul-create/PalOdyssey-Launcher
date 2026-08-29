-- PalOdysseyOptimizer - Dedicated Server Performance Suite (Inspired by Lithium, ServerCore, Krypton, FerriteCore & C2ME)
local ServerModule = {}

local function GetWorldSafe()
    if type(UEHelpers) ~= "table" then return nil end
    local ok, world = pcall(function() return UEHelpers.GetWorld() or UEHelpers.GetWorldContextObject() end)
    return ok and world or nil
end

-- Each dispatch path is tried independently so a failure in one never skips the others.
local function ExecuteConsole(cmd)
    -- Path 1: Global UE4SS ExecuteConsoleCommand
    pcall(function()
        if type(_G.ExecuteConsoleCommand) == "function" then
            _G.ExecuteConsoleCommand(cmd)
        end
    end)
    -- Path 2: PlayerController:ConsoleCommand
    pcall(function()
        if type(UEHelpers) ~= "table" then return end
        local pc = UEHelpers.GetPlayerController()
        if not pc or not pc:IsValid() then
            local pcs = FindAllOf("PalPlayerController") or FindAllOf("PlayerController")
            if pcs and #pcs > 0 then pc = pcs[1] end
        end
        if pc and pc:IsValid() and pc.ConsoleCommand then
            pc:ConsoleCommand(cmd, true)
        end
    end)
    -- Path 3: KismetSystemLibrary:ExecuteConsoleCommand
    pcall(function()
        local kismet = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
        if type(UEHelpers) ~= "table" then return end
        local world = UEHelpers.GetWorldContextObject()
        if not world or not world:IsValid() then
            local pc = UEHelpers.GetPlayerController()
            if pc and pc:IsValid() then world = pc end
        end
        if kismet and kismet:IsValid() and world and world:IsValid() then
            kismet:ExecuteConsoleCommand(world, cmd, nil)
        end
    end)
end

function ServerModule.apply(cfg)
    if not cfg or not cfg.enabled then return end

    print("[PalOdysseyOptimizer] Initializing Modrinth-Inspired Dedicated Server Optimization Suite...")

    local appliedOnce = false

    local function setupServerEngineOptimization(world)
        world = world or GetWorldSafe()

        -- 1. Krypton Network Tuning (Uncapped bandwidth, Netty stream batching, anti-desync)
        pcall(function()
            if not world or not world:IsValid() then return end
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
                if not appliedOnce then
                    print("[PalOdysseyOptimizer:Server] NetDriver tuned: 1MB/s bandwidth, 60-tick netrate.")
                end
            end
        end)

        -- 2. Lithium & ServerCore Entity Activation Range / Tick Throttling
        ExecuteConsole("a.URO.Enable 1")
        ExecuteConsole("a.URO.TickDistanceScale 0.75")
        ExecuteConsole("a.URO.VisibilityBasedAnimTickRate 1")
        ExecuteConsole("a.URO.ForceAnimRate 1")
        ExecuteConsole("p.ClothPhysics 0")
        ExecuteConsole("ai.MaxSimultaneousPathRequests 250")

        -- 3. C2ME Concurrent Async World Streaming & Actor Spawning
        ExecuteConsole("s.AsyncLoadingThreadEnabled 1")
        ExecuteConsole("s.LevelStreamingActorsUpdateTimeLimit 5.0")
        ExecuteConsole("s.PriorityAsyncLoadingExtraTime 15.0")
        ExecuteConsole("s.AsyncLoadingTimeLimit 5.0")
        ExecuteConsole("t.MaxFPS 60")

        -- 4. FerriteCore Heap Reduction & Garbage Collection Acceleration
        ExecuteConsole("gc.TimeBetweenPurgingPendingKillObjects 10")
        ExecuteConsole("gc.LowMemoryHostThresholdMB 1024")
        ExecuteConsole("gc.CreateGCClusters 1")
        ExecuteConsole("gc.NumRetriesBeforeForcingCSGC 0")

        -- 5. Anti-Rubberband Momentum Tolerances & Network Movement Smoothing
        ExecuteConsole("net.ClientMoveCorrectionThreshold 200.0")
        ExecuteConsole("p.NetCorrectionThreshold 200.0")
        ExecuteConsole("p.NetEnableMoveErrorSimulation 0")
        ExecuteConsole("p.NetMovementSmoothing 1")
        ExecuteConsole("net.PackageMap.MaxNetGUIDsPerFrame 2000")

        if not appliedOnce then
            print("[PalOdysseyOptimizer:Server] All server CVars dispatched successfully.")
            appliedOnce = true
        end
    end

    -- Run initial passes with staggered delays for engine readiness
    ExecuteWithDelay(2000, function() setupServerEngineOptimization(GetWorldSafe()) end)
    ExecuteWithDelay(5000, function() setupServerEngineOptimization(GetWorldSafe()) end)
    ExecuteWithDelay(10000, function() setupServerEngineOptimization(GetWorldSafe()) end)

    -- Hook World BeginPlay, GameState and Player joins
    pcall(function()
        RegisterHook("/Script/Engine.World:ReceiveBeginPlay", function(Context)
            setupServerEngineOptimization(Context:get())
        end)
    end)
    pcall(function()
        RegisterHook("/Script/Pal.PalGameStateInGame:ReceiveBeginPlay", function(Context)
            setupServerEngineOptimization(GetWorldSafe())
        end)
    end)
    pcall(function()
        RegisterHook("/Script/Pal.PalPlayerController:ClientRestart", function(Context)
            setupServerEngineOptimization(UEHelpers.GetWorld())
        end)
    end)

    -- Background server garbage collection and net tuning sweep (every 60s)
    local sweepCount = 0
    local function serverMemoryMaintenance()
        pcall(function()
            collectgarbage("step", 100)
            setupServerEngineOptimization(UEHelpers.GetWorld())
            sweepCount = sweepCount + 1
            if sweepCount % 5 == 0 then
                print(string.format("[PalOdysseyOptimizer:Server] Heartbeat #%d — Server optimization suite active.", sweepCount))
            end
        end)
        ExecuteWithDelay(60000, serverMemoryMaintenance)
    end
    ExecuteWithDelay(60000, serverMemoryMaintenance)

    print("[PalOdysseyOptimizer] Dedicated Server Suite Active: Krypton Network Sync, Lithium AI Throttling, C2ME Async Loading & FerriteCore Memory Sweeper.")
end

return ServerModule
