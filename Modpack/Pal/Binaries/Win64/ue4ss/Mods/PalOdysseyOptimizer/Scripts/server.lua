-- PalOdysseyOptimizer - Dedicated Server Performance Suite (Inspired by Lithium, ServerCore, Krypton, FerriteCore & C2ME)
local ServerModule = {}
local ExecuteConsole = require("console")

local function GetWorldSafe()
    if type(UEHelpers) ~= "table" then return nil end
    local ok, world = pcall(function() return UEHelpers.GetWorld() or UEHelpers.GetWorldContextObject() end)
    return ok and world or nil
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
                local fastConnectActive = _G.FastConnect and _G.FastConnect.Config and _G.FastConnect.Config.ultraFastNetworkRates
                netDriver.MaxClientRate = fastConnectActive and 300000 or 1048576
                netDriver.MaxInternetClientRate = 1048576
                netDriver.MinNetUpdateFrequency = 30.0
                netDriver.MaxNetUpdateFrequency = 60.0
                netDriver.NetServerMaxTickRate = 60
                if not appliedOnce then
                    print("[PalOdysseyOptimizer:Server] NetDriver tuned: 1MB/s bandwidth, 60-tick netrate.")
                end
            end
        end)

        -- 2. Lithium & ServerCore Entity Activation Range, Pathfinding & Physics Solver
        ExecuteConsole("a.URO.TickDistanceScale 1.0")
        ExecuteConsole("a.URO.VisibilityBasedAnimTickRate 1")
        ExecuteConsole("a.URO.Interpolation 1")
        ExecuteConsole("ai.MaxSimultaneousPathRequests 150")
        ExecuteConsole("ai.PathfindingBudgetInMilliseconds 2.0")
        ExecuteConsole("p.PhysX.SolverIterations 4")
        ExecuteConsole("p.PhysX.Substepping 0")
        ExecuteConsole("p.ClothPhysics 0")
        ExecuteConsole("p.RigidBodyLODSubStepping 0")
        ExecuteConsole("s.AsyncLoadingTimeLimit 20.0")
        ExecuteConsole("s.AsyncLoadingUseFullTimeLimit 0")

        -- 3. Anti-Rubberband Momentum Tolerances, Zero-Delay Movement & Network Scaling
        ExecuteConsole("net.DormancyEnable 1")
        ExecuteConsole("net.ClientMoveCorrectionThreshold 200.0")
        ExecuteConsole("p.NetCorrectionThreshold 200.0")
        ExecuteConsole("p.NetEnableMoveErrorSimulation 0")
        ExecuteConsole("p.NetMovementSmoothing 1")
        ExecuteConsole("p.NetEnableMoveCombining 0")
        ExecuteConsole("net.PackageMap.MaxNetGUIDsPerFrame 15000")
        ExecuteConsole("net.MaxRPCPerSecond 2000")
        ExecuteConsole("gc.CreateGCClusters 1")
        ExecuteConsole("gc.MergeGCClusters 1")
        ExecuteConsole("gc.TimeBetweenPurgingPendingKillObjects 300")
    -- One backup pass covers builds where the world hook is unavailable.
    ExecuteWithDelay(6000, function() setupServerEngineOptimization(GetWorldSafe()) end)

    -- Apply once when each world becomes ready; engine CVars then persist.
    pcall(function()
        RegisterHook("/Script/Engine.World:ReceiveBeginPlay", function(Context)
            ExecuteWithDelay(1500, function() setupServerEngineOptimization(GetWorldSafe()) end)
        end)
    end)

    -- Incremental Lua maintenance only; engine/CVar sweeps create periodic stalls.
    local function serverMemoryMaintenance()
        pcall(function()
            collectgarbage("step", 100)
        end)
        ExecuteWithDelay(60000, serverMemoryMaintenance)
    end
    ExecuteWithDelay(60000, serverMemoryMaintenance)

    print("[PalOdysseyOptimizer] Dedicated Server Suite Active: Krypton Network Sync, Lithium AI Throttling, C2ME Async Loading & FerriteCore Memory Sweeper.")
end

return ServerModule
