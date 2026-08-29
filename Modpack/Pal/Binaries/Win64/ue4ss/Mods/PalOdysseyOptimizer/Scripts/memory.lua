-- PalOdysseyOptimizer - RAM & Memory Trimming Subsystem
local MemoryModule = {}

local function ExecuteConsole(cmd)
    pcall(function()
        if type(_G.ExecuteConsoleCommand) == "function" then
            _G.ExecuteConsoleCommand(cmd)
        end
    end)
    pcall(function()
        if type(UEHelpers) ~= "table" then return end
        local pc = UEHelpers.GetPlayerController()
        if pc and pc:IsValid() and pc.ConsoleCommand then
            pc:ConsoleCommand(cmd, true)
        end
    end)
    pcall(function()
        local kismet = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
        local world = type(UEHelpers) == "table" and (UEHelpers.GetWorld() or UEHelpers.GetWorldContextObject())
        if kismet and kismet:IsValid() and world and world:IsValid() then
            kismet:ExecuteConsoleCommand(world, cmd, nil)
        end
    end)
end

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

    -- Hook player respawns / fast travel to clean up orphaned assets
    pcall(function()
        RegisterHook("/Script/Pal.PalPlayerController:ClientRestart", function(Context)
            ExecuteWithDelay(2000, function()
                collectgarbage("collect")
                ExecuteConsole("r.Streaming.PurgeUnused")
            end)
        end)
    end)

    -- Start initial delayed memory passes
    ExecuteWithDelay(30000, performMemoryMaintenance)

    print("[PalOdysseyOptimizer] Memory & Working Set Cleaner scheduled (Interval: " .. tostring(cfg.trimIntervalMinutes or 3) .. " mins).")
end

return MemoryModule
