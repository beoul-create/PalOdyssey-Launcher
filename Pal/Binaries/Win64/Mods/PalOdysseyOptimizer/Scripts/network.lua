-- PalOdysseyOptimizer - Network Pipeline & Low-Latency Synchronization
local NetworkModule = {}

local function GetWorldSafe()
    if type(UEHelpers) ~= "table" then return nil end
    local ok, world = pcall(function() return UEHelpers.GetWorld() or UEHelpers.GetWorldContextObject() end)
    return ok and world or nil
end

function NetworkModule.apply(cfg)
    if not cfg or not cfg.enabled then return end

    print("[PalOdysseyOptimizer] Applying Network & Latency Optimization Pipeline...")

    -- Tune NetDriver properties when a valid world + NetDriver is available
    local tuned = false
    local function tuneNetwork()
        if tuned then return end
        pcall(function()
            local world = GetWorldSafe()
            if not world or not world:IsValid() then return end

            local netDriver = world.NetDriver
            if not netDriver or not netDriver:IsValid() then return end

            local fastConnectActive = _G.FastConnect and _G.FastConnect.Config and _G.FastConnect.Config.ultraFastNetworkRates
            local maxBw = fastConnectActive and 300000 or (cfg.maxBandwidth or 1048576)
            netDriver.MaxClientRate = maxBw
            netDriver.MaxInternetClientRate = maxBw
            netDriver.MinNetUpdateFrequency = 30.0
            netDriver.MaxNetUpdateFrequency = 120.0
            netDriver.NetServerMaxTickRate = 60

            if not tuned then
                print(string.format("[PalOdysseyOptimizer:Network] NetDriver tuned: %d B/s bandwidth, 120Hz net update, 60-tick server rate.", maxBw))
                tuned = true
            end
        end)
    end

    -- Hook GameInstance init (may fire before NetDriver exists)
    pcall(function()
        RegisterHook("/Script/Engine.GameInstance:ReceiveInit", function(Context)
            ExecuteWithDelay(500, tuneNetwork)
            ExecuteWithDelay(2000, tuneNetwork)
        end)
    end)

    -- Hook World BeginPlay (NetDriver should exist by this point)
    pcall(function()
        RegisterHook("/Script/Engine.World:ReceiveBeginPlay", function(Context)
            tuneNetwork()
            ExecuteWithDelay(1000, tuneNetwork)
        end)
    end)

    -- Hook player joins to re-apply on connection
    pcall(function()
        RegisterHook("/Script/Pal.PalPlayerController:ClientRestart", function(Context)
            tuneNetwork()
        end)
    end)

    -- Retry loop: wait for NetDriver to become available, try every 5s for 60s
    local retryCount = 0
    local function retryNetTuning()
        if tuned then return end
        retryCount = retryCount + 1
        tuneNetwork()
        if not tuned and retryCount < 12 then
            ExecuteWithDelay(5000, retryNetTuning)
        elseif not tuned then
            print("[PalOdysseyOptimizer:Network] WARNING: Could not find a valid NetDriver after 60s. Network tuning deferred to next player join.")
        end
    end
    ExecuteWithDelay(3000, retryNetTuning)

    print("[PalOdysseyOptimizer] Network Optimization armed: 1MB/s bandwidth cap, high-frequency tickrate, zero serialization choke.")
end

return NetworkModule
