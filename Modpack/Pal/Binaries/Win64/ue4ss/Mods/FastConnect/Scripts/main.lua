-- FastConnect & Seamless Loading Pipeline for PalOdyssey
local Config = require("config")

local function Log(msg)
    print(string.format("[FastConnect] %s", tostring(msg)))
end

-- Multi-Path Console Command Dispatcher
local function ExecuteConsole(command)
    if not command or command == "" then return false end

    -- Path 1: Global UE4SS console executor
    if type(_G.ExecuteConsoleCommand) == "function" then
        local ok = pcall(_G.ExecuteConsoleCommand, command)
        if ok then return true end
    end

    -- Path 2: PlayerController ConsoleCommand (with fallback to FindAllOf)
    local ok2, pc = pcall(function()
        if UEHelpers and type(UEHelpers.GetPlayerController) == "function" then
            local p = UEHelpers.GetPlayerController()
            if p and p:IsValid() then return p end
        end
        local pcs = FindAllOf and (FindAllOf("PalPlayerController") or FindAllOf("PlayerController"))
        if pcs and #pcs > 0 and pcs[1]:IsValid() then
            return pcs[1]
        end
        return nil
    end)

    if ok2 and pc and pc:IsValid() then
        local executed = pcall(function()
            pc:ConsoleCommand(command, true)
        end)
        if executed then return true end
    end

    -- Path 3: KismetSystemLibrary fallback
    pcall(function()
        local kismet = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
        local world = UEHelpers and UEHelpers.GetWorldContextObject and UEHelpers.GetWorldContextObject()
        if kismet and kismet:IsValid() and world and world:IsValid() then
            kismet:ExecuteConsoleCommand(world, command, nil)
        end
    end)

    return true
end

-- 1. Apply Automatic Ultra-Fast Server Connection & Network Rates
local function ApplyFastNetworkRates()
    pcall(function()
        if not Config.ultraFastNetworkRates then return end

        -- 10x Bandwidth for instant server handshake and world snapshot replication
        ExecuteConsole("net.IpNetDriver.MaxClientRate 150000")
        ExecuteConsole("net.PackageMap.MaxNetGUIDsPerFrame 3000")
        ExecuteConsole("net.MaxRPCPerSecond 500")
        ExecuteConsole("net.ReliableBufferSize 4194304")
        Log("Ultra-fast network replication and server handshake bandwidth applied.")
    end)
end

-- 2. Apply Engine Loading Time & Async Streaming Acceleration
local function ApplyLoadingOptimizations()
    pcall(function()
        if not Config.accelerateLoadingScreens then return end

        -- Maximize frame time allocation for asynchronous world/shader loading
        ExecuteConsole("s.AsyncLoadingTimeLimit 25.0")
        ExecuteConsole("s.PriorityAsyncLoadingExtraTime 50.0")
        ExecuteConsole("s.LevelStreamingActorsUpdateTimeLimit 25.0")
        ExecuteConsole("s.UnregisterComponentsTimeLimit 25.0")
        ExecuteConsole("s.AsyncLoadingUseFullTimeLimit 1")
        ExecuteConsole("r.Streaming.MaxNumTexturesToStreamPerFrame 20")
        ExecuteConsole("r.Streaming.HLODStrategy 2")
        ExecuteConsole("r.Streaming.DefragDynamicBounds 1")
        ExecuteConsole("r.Streaming.AmortizeCPUWork 1")
        ExecuteConsole("r.Streaming.Boost 2")
        ExecuteConsole("r.Streaming.LimitPoolSizeToVRAM 1")
        ExecuteConsole("r.Streaming.FramesForFullUpdate 20")

        if Config.prewarmShaderPipelines then
            ExecuteConsole("r.CreateShadersOnLoad 1")
            ExecuteConsole("r.Shaders.Optimize 1")
        end

        -- Batch GC allocations and prevent mid-load GC hitching
        ExecuteConsole("gc.TimeBetweenPurgingPendingKillObjects 120")
        ExecuteConsole("gc.NumRetriesBeforeForcingCSGC 0")
        ExecuteConsole("gc.CreateGCClusters 1")
        
        Log("Instant world loading and shader streaming parameters applied.")
    end)
end

-- 3. Skip Intro Movies / Opening Splashes Automatically
local function SkipIntroMovies()
    pcall(function()
        if not Config.bypassIntroMovies then return end
        ExecuteConsole("MoviePlayer.SkipMovie")
        ExecuteConsole("r.MovieSubsystem.Skip 1")
    end)
end

-- 4. Fast Travel / Map Transition Acceleration
local function OnPlayerTransition()
    pcall(function()
        if not Config.bypassFastTravelWait then return end
        ExecuteConsole("r.Streaming.PurgeUnused")
        ExecuteConsole("s.AsyncLoadingUseFullTimeLimit 1")
        ApplyFastNetworkRates()
    end)
end

-- Delayed enforcement helper to overcome engine resets on world transitions
local function SafeDelayedEnforce()
    ApplyFastNetworkRates()
    ApplyLoadingOptimizations()
    SkipIntroMovies()
    ExecuteWithDelay(1500, function()
        ApplyFastNetworkRates()
        ApplyLoadingOptimizations()
    end)
    ExecuteWithDelay(4000, function()
        ApplyFastNetworkRates()
        ApplyLoadingOptimizations()
    end)
end

-- Hook World, Network & Game Setting Initialization (Fully Automated)
pcall(function()
    NotifyOnNewObject("/Script/Pal.PalGameSetting", function()
        SafeDelayedEnforce()
    end)
end)

pcall(function()
    NotifyOnNewObject("/Script/Pal.PalGameStateInGame", function()
        SafeDelayedEnforce()
    end)
end)

pcall(function()
    NotifyOnNewObject("/Script/Pal.PalGameStateInTitle", function()
        SafeDelayedEnforce()
    end)
end)

pcall(function()
    NotifyOnNewObject("/Script/Engine.NetConnection", function()
        ApplyFastNetworkRates()
        ApplyLoadingOptimizations()
    end)
end)

pcall(function()
    RegisterHook("/Script/Engine.PlayerController:ClientRestart", function(Context)
        OnPlayerTransition()
        ApplyLoadingOptimizations()
    end)
end)

pcall(function()
    RegisterHook("/Script/Engine.PlayerController:ClientTravel", function(Context)
        SafeDelayedEnforce()
    end)
end)

-- Initial execution on game boot
SafeDelayedEnforce()

-- Expose global API
_G.FastConnect = {
    ApplyNetworkRates = ApplyFastNetworkRates,
    ApplyOptimizations = ApplyLoadingOptimizations,
    Config = Config
}

Log("FastConnect & Instant Loading Pipeline active (Fully Automatic Mode).")
