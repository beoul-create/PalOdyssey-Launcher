-- PalOdysseyOptimizer - FPS Boost & GPU Assist Subsystem
local GraphicsModule = {}

local function ExecuteConsole(cmd)
    pcall(function()
        local kismet = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
        if kismet and kismet:IsValid() then
            kismet:ExecuteConsoleCommand(nil, cmd, nil)
        end
    end)
end

function GraphicsModule.apply(cfg)
    if not cfg or not cfg.enabled then return end

    print("[PalOdysseyOptimizer] Initializing GPU Assist & Frame Pacing Engine...")

    local function optimizeRenderSettings()
        pcall(function()
            local engine = UEHelpers.GetEngine()
            if engine and engine:IsValid() then
                if cfg.oneFrameThreadLag then
                    engine.bSmoothFrameRate = false
                end
            end

            -- Apply lightweight console variables for low GPU/CPU overhead
            ExecuteConsole("t.UnfocusedMaxFPS 30")
            ExecuteConsole("r.Streaming.PoolSize 2560")
            ExecuteConsole("r.Streaming.LimitPoolSizeToVRAM 1")
            ExecuteConsole("r.VolumetricFog.GridPixelSize 16")
            ExecuteConsole("r.Shadow.DistanceScale 0.75")
            ExecuteConsole("r.DepthOfFieldQuality 0")
            ExecuteConsole("r.MotionBlurQuality 0")
            ExecuteConsole("r.Emitter.FastPool 1")
            ExecuteConsole("gc.TimeBetweenPurgingPendingKillObjects 45")
        end)
    end

    -- Hook GameEngine Init and also run with delay
    pcall(function()
        RegisterHook("/Script/Engine.GameEngine:Init", function(Context)
            optimizeRenderSettings()
        end)
    end)

    ExecuteWithDelay(3000, optimizeRenderSettings)
    ExecuteWithDelay(8000, optimizeRenderSettings)

    print("[PalOdysseyOptimizer] GPU Assist & Graphics Pipeline loaded successfully.")
end

return GraphicsModule
