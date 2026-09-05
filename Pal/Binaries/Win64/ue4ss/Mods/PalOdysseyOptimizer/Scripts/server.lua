-- PalOdysseyOptimizer - Dedicated Server Performance Suite (Inspired by Lithium, ServerCore, Krypton, FerriteCore & C2ME)
local ServerModule = {}
local ExecuteConsole = require("console")

local function GetWorldSafe()
    if type(UEHelpers) ~= "table" then return nil end
    local ok, world = pcall(function() return UEHelpers.GetWorld() or UEHelpers.GetWorldContextObject() end)
    return ok and world or nil
end

local function is_dedicated_server_process()
    local command = string.lower(tostring(os.getenv("CMDCMDLINE") or ""))
    if string.find(command, "dedicated", 1, true)
        or string.find(command, "palserver", 1, true) then
        return true
    end
    local source = debug.getinfo(1, "S").source:lower():gsub("\\", "/")
    if string.find(source, "/palserver/") ~= nil then
        return true
    end
    local ok, engine = pcall(function()
        return FindFirstOf("GameEngine")
    end)
    if ok and engine ~= nil then
        local ok_net, net_mode = pcall(function()
            return engine.NetMode
        end)
        if ok_net and type(net_mode) == "number" and net_mode == 3 then
            return true
        end
    end
    local ok_geo, is_ded = pcall(function()
        local GameplayStatics = StaticFindObject("/Script/Engine.Default__GameplayStatics")
        local world = (UEHelpers and UEHelpers.GetWorldContextObject and UEHelpers.GetWorldContextObject()) or (GetWorldContext and GetWorldContext())
        if GameplayStatics and GameplayStatics:IsValid() and world and world:IsValid() and type(GameplayStatics.IsDedicatedServer) == "function" then
            return GameplayStatics:IsDedicatedServer(world)
        end
        return false
    end)
    if ok_geo and is_ded then return true end
    return false
end

function ServerModule.apply(cfg)
    if not cfg or not cfg.enabled then return end
    if not is_dedicated_server_process() then
        print("[PalOdysseyOptimizer] Client environment detected; Dedicated Server Performance Suite idle.")
        return
    end

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
                netDriver.MinNetUpdateFrequency = 10.0
                netDriver.MaxNetUpdateFrequency = 33.0
                netDriver.NetServerMaxTickRate = 33
                if not appliedOnce then
                    print("[PalOdysseyOptimizer:Server] NetDriver tuned: 1MB/s bandwidth, 33-tick stable netrate.")
                end
            end
        end)

        -- 2. Lithium & ServerCore Entity Activation Range, Pathfinding & Physics Solver
        ExecuteConsole("a.URO.TickDistanceScale 1.0")
        ExecuteConsole("a.URO.VisibilityBasedAnimTickRate 1")
        ExecuteConsole("a.URO.Interpolation 1")
        ExecuteConsole("ai.MaxSimultaneousPathRequests 60")
        ExecuteConsole("ai.PathfindingBudgetInMilliseconds 1.0")
        ExecuteConsole("p.PhysX.SolverIterations 4")
        ExecuteConsole("p.PhysX.Substepping 0")
        ExecuteConsole("p.ClothPhysics 0")
        ExecuteConsole("p.RigidBodyLODSubStepping 0")
        ExecuteConsole("s.AsyncLoadingTimeLimit 20.0")
        ExecuteConsole("s.AsyncLoadingUseFullTimeLimit 0")

        -- 3. Anti-Rubberband Momentum Tolerances, Zero-Delay Movement & Network Scaling
        ExecuteConsole("net.DormancyEnable 1")
        ExecuteConsole("net.ClientMoveCorrectionThreshold 100.0")
        ExecuteConsole("p.NetCorrectionThreshold 100.0")
        ExecuteConsole("p.NetEnableMoveErrorSimulation 0")
        ExecuteConsole("p.NetMovementSmoothing 1")
        ExecuteConsole("p.NetEnableMoveCombining 1")
        ExecuteConsole("net.PackageMap.MaxNetGUIDsPerFrame 5000")
        ExecuteConsole("net.MaxRPCPerSecond 500")
        ExecuteConsole("gc.CreateGCClusters 1")
        ExecuteConsole("gc.MergeGCClusters 1")
        ExecuteConsole("gc.TimeBetweenPurgingPendingKillObjects 300")
    end

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
