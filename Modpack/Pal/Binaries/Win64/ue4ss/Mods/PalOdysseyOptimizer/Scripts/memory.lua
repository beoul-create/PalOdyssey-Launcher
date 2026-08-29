-- PalOdysseyOptimizer - RAM & Memory Trimming Subsystem
local MemoryModule = {}
local ExecuteConsole = require("console")

function MemoryModule.apply(cfg)
    if not cfg or not cfg.enabled then return end

    print("[PalOdysseyOptimizer] Initializing RAM Reduction & Working Set Sweep Engine...")

    -- Periodic non-intrusive GC cleanup scheduler
    local trimIntervalMs = (cfg.trimIntervalMinutes or 3) * 60 * 1000

    local function performMemoryMaintenance()
        pcall(function()
            -- 1. Incremental Lua GC step
            collectgarbage("step", 100)

            -- 2. Engine-level unused object and texture pool purge
            if cfg.autoTrimWorkingSet then
                ExecuteConsole("obj gc")
            end
            if cfg.defragTexturePool then
                ExecuteConsole("r.Streaming.PurgeUnused")
            end
        end)

        -- Re-queue next maintenance pass
        ExecuteWithDelay(trimIntervalMs, performMemoryMaintenance)
    end

    -- Use incremental Lua collection on travel; forced engine GC causes visible stalls.
    pcall(function()
        RegisterHook("/Script/Pal.PalPlayerController:ClientRestart", function(Context)
            ExecuteWithDelay(2000, function()
                collectgarbage("step", 200)
            end)
        end)
    end)

    -- Start initial delayed memory passes
    ExecuteWithDelay(30000, performMemoryMaintenance)

    print("[PalOdysseyOptimizer] Memory & Working Set Cleaner scheduled (Interval: " .. tostring(cfg.trimIntervalMinutes or 3) .. " mins).")
end

return MemoryModule
