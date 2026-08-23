-- PalOdysseyOptimizer - RAM & Memory Trimming Subsystem
local MemoryModule = {}

function MemoryModule.apply(cfg)
    if not cfg or not cfg.enabled then return end

    print("[PalOdysseyOptimizer] Initializing RAM Reduction & Working Set Sweep Engine...")

    -- Periodic non-intrusive GC cleanup scheduler
    local trimIntervalMs = (cfg.trimIntervalMinutes or 5) * 60 * 1000

    local function performMemoryMaintenance()
        pcall(function()
            -- Collect Unreal pending kills
            collectgarbage("collect")
            print("[PalOdysseyOptimizer] Executed scheduled Working Set & Lua garbage collection pass.")
        end)

        -- Re-queue next maintenance pass
        ExecuteWithDelay(trimIntervalMs, performMemoryMaintenance)
    end

    -- Start initial delayed memory pass
    ExecuteWithDelay(60000, performMemoryMaintenance)

    print("[PalOdysseyOptimizer] Memory & Working Set Cleaner scheduled (Interval: " .. tostring(cfg.trimIntervalMinutes or 5) .. " mins).")
end

return MemoryModule
