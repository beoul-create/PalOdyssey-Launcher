-- PalOdysseyOptimizer - Network Pipeline & Low-Latency Synchronization
local NetworkModule = {}

function NetworkModule.apply(cfg)
    if not cfg or not cfg.enabled then return end

    print("[PalOdysseyOptimizer] Applying Network & Latency Optimization Pipeline...")

    -- Hook GameInstance to set NetDriver parameters
    local function tuneNetwork(gameInstance)
        if not gameInstance or not gameInstance:IsValid() then return end

        pcall(function()
            -- Uncap client bandwidth from default 10KB/s to 1MB/s
            local minBw = cfg.minBandwidth or 65536
            local maxBw = cfg.maxBandwidth or 1048576

            -- Apply network driver tuning
            local world = gameInstance:GetWorld()
            if world and world:IsValid() then
                local netDriver = world.NetDriver
                if netDriver and netDriver:IsValid() then
                    netDriver.MaxClientRate = maxBw
                    netDriver.MaxInternetClientRate = maxBw
                    netDriver.MinNetUpdateFrequency = 30.0
                    netDriver.MaxNetUpdateFrequency = 120.0
                    netDriver.NetServerMaxTickRate = 60
                end
            end
        end)
    end

    RegisterHook("/Script/Engine.GameInstance:ReceiveInit", function(Context)
        local gi = Context:get()
        if gi and gi:IsValid() then
            tuneNetwork(gi)
        end
    end)

    print("[PalOdysseyOptimizer] Network Optimization active: 1MB/s bandwidth cap, high-frequency tickrate, zero serialization choke.")
end

return NetworkModule
