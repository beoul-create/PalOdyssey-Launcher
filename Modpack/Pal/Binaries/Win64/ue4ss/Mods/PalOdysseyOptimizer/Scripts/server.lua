-- PalOdysseyOptimizer - Server Connection & Stability Improvements
local ServerModule = {}

function ServerModule.apply(cfg)
    if not cfg or not cfg.enabled then return end

    print("[PalOdysseyOptimizer] Applying Server Connection & Stability Improvements...")

    local function setupServerTimeouts(world)
        if not world or not world:IsValid() then return end

        pcall(function()
            local netDriver = world.NetDriver
            if netDriver and netDriver:IsValid() then
                -- Extend connection timeout to prevent drops during heavy world streaming
                netDriver.ConnectionTimeout = cfg.connectionTimeout or 120.0
                netDriver.InitialConnectTimeout = cfg.initialConnectTimeout or 180.0
                netDriver.KeepAliveTime = 0.2
            end
        end)
    end

    RegisterHook("/Script/Engine.World:ReceiveBeginPlay", function(Context)
        local world = Context:get()
        if world and world:IsValid() then
            setupServerTimeouts(world)
        end
    end)

    print("[PalOdysseyOptimizer] Server Connection Improvements Active (Connection Timeout: " .. tostring(cfg.connectionTimeout or 120) .. "s).")
end

return ServerModule
