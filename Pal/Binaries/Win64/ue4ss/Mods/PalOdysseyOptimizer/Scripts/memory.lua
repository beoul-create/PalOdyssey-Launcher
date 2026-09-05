-- PalOdysseyOptimizer - RAM & Memory Trimming Subsystem
local MemoryModule = {}
local ExecuteConsole = require("console")

function MemoryModule.apply(cfg)
    if not cfg or not cfg.enabled then return end

    print("[PalOdysseyOptimizer] Initializing RAM Reduction & Working Set Sweep Engine...")

    -- Periodic non-intrusive GC cleanup scheduler (every 60s)
    local trimIntervalMs = (cfg.trimIntervalMinutes or 1) * 60 * 1000

    local function performMemoryMaintenance()
        pcall(function()
            -- Incremental non-blocking Lua GC step (never halts game thread)
            collectgarbage("step", 100)
            if cfg.autoTrimWorkingSet == true then
                ExecuteConsole("obj gc")
            end
            if cfg.defragTexturePool == true then
                ExecuteConsole("r.Streaming.PurgeUnused")
            end
        end)

        -- Re-queue next maintenance pass
        ExecuteWithDelay(trimIntervalMs, performMemoryMaintenance)
    end

    -- Fast-Travel hook
    pcall(function()
        RegisterHook("/Script/Engine.PlayerController:ClientTravel", function(Context)
            ExecuteWithDelay(15000, function()
                collectgarbage("step", 100)
                if not (_G.FastConnect and _G.FastConnect.Config and _G.FastConnect.Config.accelerateLoadingScreens) then
                    ExecuteConsole("obj gc")
                end
            end)
        end)
    end)

    -- Start initial delayed memory passes
    ExecuteWithDelay(15000, performMemoryMaintenance)

    print("[PalOdysseyOptimizer] Proactive Memory Cleaner scheduled (Interval: " .. tostring(cfg.trimIntervalMinutes or 1) .. " mins).")
end

return MemoryModule
