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
            -- 1. Incremental Lua GC step
            collectgarbage("collect")

            -- 2. Engine-level unused object and texture pool purge
            if cfg.autoTrimWorkingSet ~= false then
                ExecuteConsole("obj gc")
            end
            if cfg.defragTexturePool ~= false then
                ExecuteConsole("r.Streaming.PurgeUnused")
            end
        end)

        -- Re-queue next maintenance pass
        ExecuteWithDelay(trimIntervalMs, performMemoryMaintenance)
    end

    -- Fast-Travel hook
    pcall(function()
        RegisterHook("/Script/Pal.PalPlayerController:ClientRestart", function(Context)
            ExecuteWithDelay(2000, function()
                collectgarbage("collect")
                ExecuteConsole("obj gc")
            end)
        end)
    end)

    -- Start initial delayed memory passes
    ExecuteWithDelay(15000, performMemoryMaintenance)

    print("[PalOdysseyOptimizer] Proactive Memory Cleaner scheduled (Interval: " .. tostring(cfg.trimIntervalMinutes or 1) .. " mins).")
end

return MemoryModule
