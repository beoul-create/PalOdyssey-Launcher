-- FastConnect & Seamless Loading Pipeline for PalOdyssey
local Config = require("config")
local ConnectionPhase = false

local function Log(msg)
    print(string.format("[FastConnect] %s", tostring(msg)))
end

if Config.enabled == false then
    Log("Disabled in config.")
    return
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

        -- Maximum network bandwidth for instant server handshake and world snapshot replication
        ExecuteConsole("net.IpNetDriver.MaxClientRate 400000")
        ExecuteConsole("net.PackageMap.MaxNetGUIDsPerFrame 15000")
        ExecuteConsole("net.MaxRPCPerSecond 2000")
        ExecuteConsole("net.ReliableBufferSize 8388608")
        ExecuteConsole("net.TrackNetBandwidth 0")
        ExecuteConsole("net.TickRate 60")
        ExecuteConsole("p.NetEnableMoveCombining 0")
        Log("Ultra-fast low-latency network replication & zero-delay movement applied.")
    end)
end

-- 2. Apply Engine Loading Time & Async Streaming Acceleration
local function ApplyLoadingOptimizations()
    pcall(function()
        if not Config.accelerateLoadingScreens then return end

        ExecuteConsole("s.AsyncLoadingTimeLimit 10.0")
        ExecuteConsole("s.PriorityAsyncLoadingExtraTime 10.0")
        ExecuteConsole("s.LevelStreamingActorsUpdateTimeLimit 5.0")
        ExecuteConsole("s.UnregisterComponentsTimeLimit 2.0")
        ExecuteConsole("s.AsyncLoadingUseFullTimeLimit 0")
        ExecuteConsole("r.Streaming.MaxNumTexturesToStreamPerFrame 30")
        ExecuteConsole("r.Streaming.HLODStrategy 1")
        ExecuteConsole("r.Streaming.DefragDynamicBounds 0")
        ExecuteConsole("r.Streaming.AmortizeCPUWork 1")
        ExecuteConsole("r.Streaming.Boost 2")
        ExecuteConsole("r.Streaming.PoolSize 2048")
        ExecuteConsole("r.Streaming.LimitPoolSizeToVRAM 1")
        ExecuteConsole("r.Streaming.FramesForFullUpdate 45")

        if Config.prewarmShaderPipelines then
            ExecuteConsole("r.CreateShadersOnLoad 1")
            ExecuteConsole("r.Shaders.Optimize 1")
        end

        ExecuteConsole("gc.TimeBetweenPurgingPendingKillObjects 600")
    ExecuteConsole("gc.IncrementalBeginDestroyEnabled 1")
    ExecuteConsole("gc.MinDesiredFrameRate 60")
        ExecuteConsole("gc.CreateGCClusters 1")
        
        Log("Smooth world loading and shader streaming parameters applied.")
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

local function ApplySteadyStateStreaming()
    ConnectionPhase = false
    ExecuteConsole("s.AsyncLoadingUseFullTimeLimit 0")
    ExecuteConsole("s.AsyncLoadingTimeLimit 2.0")
    ExecuteConsole("s.PriorityAsyncLoadingExtraTime 2.0")
    ExecuteConsole("s.LevelStreamingActorsUpdateTimeLimit 3.0")
    ExecuteConsole("s.UnregisterComponentsTimeLimit 1.0")
    ExecuteConsole("r.Streaming.MaxNumTexturesToStreamPerFrame 12")
    ExecuteConsole("r.Streaming.HLODStrategy 1")
    ExecuteConsole("r.Streaming.DefragDynamicBounds 0")
    ExecuteConsole("r.Streaming.Boost 1.5")
    ExecuteConsole("r.Streaming.FramesForFullUpdate 45")
    ExecuteConsole("gc.TimeBetweenPurgingPendingKillObjects 600")
    ExecuteConsole("gc.IncrementalBeginDestroyEnabled 1")
    ExecuteConsole("gc.MinDesiredFrameRate 60")
    Log("Steady-state gameplay streaming activated (Zero game-thread async loading stalls).")
end

-- 4. Fast Travel / Map Transition Acceleration
local function OnPlayerTransition()
    pcall(function()
        if not Config.bypassFastTravelWait then return end
        -- ExecuteConsole("r.Streaming.PurgeUnused") -- Disabled: PurgeUnused forces synchronous hitch
        ApplyFastNetworkRates()
        ApplySteadyStateStreaming()
    end)
end

local function BeginConnectionPhase()
    ConnectionPhase = true
    ApplyFastNetworkRates()
    ApplyLoadingOptimizations()
end

local function ScheduleSteadyState(delayMs)
    ExecuteWithDelay(delayMs, function()
        ApplySteadyStateStreaming()
    end)
end

-- Delayed enforcement helper to overcome engine resets on world transitions
local function SafeDelayedEnforce()
    ApplyFastNetworkRates()
    ApplySteadyStateStreaming()
    SkipIntroMovies()
    ExecuteWithDelay(800, function()
        ApplyFastNetworkRates()
        ApplySteadyStateStreaming()
    end)
    ExecuteWithDelay(2500, function()
        ApplyFastNetworkRates()
        ApplySteadyStateStreaming()
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
        BeginConnectionPhase()
        ScheduleSteadyState(5000)
    end)
end)

pcall(function()
    RegisterHook("/Script/Engine.PlayerController:ClientTravel", function(Context)
        -- ClientRestart also fires for ordinary pawn possession changes such as
        -- mounting and dismounting.  Cleanup belongs on actual travel only;
        -- purging the streaming cache during a mount transition stalls the game
        -- thread while the server continues the possession change.
        OnPlayerTransition()
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
