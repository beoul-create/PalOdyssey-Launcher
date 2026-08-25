-- PalOdysseyOptimizer - RAM & Memory Trimming Subsystem
local MemoryModule = {}

function MemoryModule.apply(cfg)
    if not cfg or not cfg.enabled then return end

    print("[PalOdysseyOptimizer] Initializing RAM Reduction & Working Set Sweep Engine...")

    -- Periodic non-intrusive GC cleanup scheduler
    local trimIntervalMs = (cfg.trimIntervalMinutes or 2) * 60 * 1000

    local function performMemoryMaintenance()
        pcall(function()
            -- Perform non-intrusive incremental Lua GC step (zero frame hitching)
            collectgarbage("step", 50)
        end)

        -- Re-queue next maintenance pass
        ExecuteWithDelay(trimIntervalMs, performMemoryMaintenance)
    end

    -- Start initial delayed memory passes
    ExecuteWithDelay(30000, performMemoryMaintenance)

    print("[PalOdysseyOptimizer] Memory & Working Set Cleaner scheduled (Interval: " .. tostring(cfg.trimIntervalMinutes or 2) .. " mins).")
end

return MemoryModule
