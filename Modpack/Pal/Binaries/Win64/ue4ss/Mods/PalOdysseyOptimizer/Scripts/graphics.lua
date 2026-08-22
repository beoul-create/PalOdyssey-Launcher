-- PalOdysseyOptimizer - FPS Boost & GPU Assist Subsystem
local GraphicsModule = {}

function GraphicsModule.apply(cfg)
    if not cfg or not cfg.enabled then return end

    print("[PalOdysseyOptimizer] Initializing GPU Assist & Frame Pacing Engine...")

    local function optimizeRenderSettings()
        pcall(function()
            -- Optimize Engine Console Variables when Engine is ready
            local engine = UEHelpers.GetEngine()
            if not engine or not engine:IsValid() then return end

            -- Enable one frame thread lag for maximum GPU pipelining
            if cfg.oneFrameThreadLag then
                engine.bSmoothFrameRate = false
            end
        end)
    end

    -- Hook GameEngine Init
    RegisterHook("/Script/Engine.GameEngine:Init", function(Context)
        optimizeRenderSettings()
    end)

    print("[PalOdysseyOptimizer] GPU Assist & Graphics Pipeline loaded successfully.")
end

return GraphicsModule
