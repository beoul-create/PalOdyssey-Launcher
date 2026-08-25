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

            -- 1. Asynchronous Texture Streaming & CPU Amortization
            ExecuteConsole("r.TextureStreaming 1")
            ExecuteConsole("r.Streaming.AmortizeCPUWork 1")
            ExecuteConsole("r.Streaming.FramesForFullUpdate 20")
            ExecuteConsole("r.Streaming.DefragDynamicBounds 1")
            ExecuteConsole("r.Streaming.LimitPoolSizeToVRAM 1")
            ExecuteConsole("r.Streaming.HLODStrategy 1")
            ExecuteConsole("r.Streaming.PoolSize 3072")

            -- 2. Asynchronous Shader Compilation & Stutter Elimination
            ExecuteConsole("r.CreateShadersOnLoad 1")
            ExecuteConsole("r.Shaders.Optimize 1")
            ExecuteConsole("r.ShaderPipelineCache.BatchTime 2.0")

            -- 3. Shadows & Lighting (Crisp High-Res, Zero Stutter)
            ExecuteConsole("r.Shadow.Virtual.Enable 0")
            ExecuteConsole("r.Shadow.CSM.MaxCascades 2")
            ExecuteConsole("r.Shadow.DistanceScale 0.85")
            ExecuteConsole("r.ShadowQuality 3")
            ExecuteConsole("r.VolumetricFog 0")
            ExecuteConsole("r.VolumetricFog.GridPixelSize 16")
            ExecuteConsole("r.Lumen.Reflections.Allow 0")
            ExecuteConsole("r.Lumen.ScreenProbeGather.DownsampleFactor 16")

            -- 4. Frame Pacing & Low-Latency Sync
            ExecuteConsole("r.GTSyncType 1")
            ExecuteConsole("r.OneFrameThreadLag 1")
            ExecuteConsole("r.FinishCurrentFrame 0")
            ExecuteConsole("t.UnfocusedMaxFPS 30")
            ExecuteConsole("r.Emitter.FastPool 1")

            -- 5. Visual Post-Processing & Clarity
            ExecuteConsole("r.DepthOfFieldQuality 0")
            ExecuteConsole("r.MotionBlurQuality 0")
            ExecuteConsole("r.SceneColorFringeQuality 0")
            ExecuteConsole("r.Tonemapper.GrainQuantization 0")
            ExecuteConsole("r.TSR.ShadingRejection.Flickering 1")
            ExecuteConsole("gc.TimeBetweenPurgingPendingKillObjects 60")
        end)
    end

    -- Hook GameEngine Init and also run with delay
    pcall(function()
        RegisterHook("/Script/Engine.GameEngine:Init", function(Context)
            optimizeRenderSettings()
        end)
    end)

    ExecuteWithDelay(2500, optimizeRenderSettings)
    ExecuteWithDelay(7000, optimizeRenderSettings)

    print("[PalOdysseyOptimizer] GPU Assist & Graphics Pipeline loaded successfully.")
end

return GraphicsModule
