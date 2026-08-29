-- PalOdysseyOptimizer - FPS Boost & GPU Assist Subsystem (Ultra-Performance Option B Profile)
local GraphicsModule = {}
local ExecuteConsole = require("console")

function GraphicsModule.apply(cfg, cpuCfg)
    if not cfg or not cfg.enabled then return end

    print("[PalOdysseyOptimizer] Initializing Ultra-Performance Option B GPU Pipeline (Mesh Shaders + SkinCache + URO + 512p CSM)...")

    local appliedOnce = false

    local function optimizeRenderSettings()
        pcall(function()
            local engine = UEHelpers.GetEngine()
            if engine and engine:IsValid() then
                if cfg.oneFrameThreadLag then
                    engine.bSmoothFrameRate = false
                end
            end
        end)

        -- 1. Nvidium-Style GPU Task/Mesh Shaders, GPUScene Occlusion & VRAM SkinCache
        ExecuteConsole("r.MeshShaders 1")
        ExecuteConsole("r.MeshShaders.Enable 1")
        ExecuteConsole("r.GPUScene.InstanceCulling 1")
        ExecuteConsole("r.EarlyZPass 2")
        ExecuteConsole("r.EarlyZPassMovable 1")
        ExecuteConsole("r.SkinCache.Mode 1")
        ExecuteConsole("r.SkinCache.CompileShaders 1")
        ExecuteConsole("r.SkinCache.RecomputeTangents 1")
        ExecuteConsole("r.HZBOcclusion 1")
        ExecuteConsole("r.AllowOcclusionQueries 1")
        ExecuteConsole("r.Occlusion.MaxQueriesPerFrame 50000")
        ExecuteConsole("r.D3D12.TextureCreationParallel 1")
        ExecuteConsole("r.D3D12.UseAsyncDescriptorCopy 1")

        -- 2. Skeletal URO + Pose Interpolation + Physics Tick Amortization (Lithium & ServerCore)
        ExecuteConsole("a.URO.Enable 1")
        ExecuteConsole("a.URO.TickDistanceScale 0.75")
        ExecuteConsole("a.URO.Interpolation 1")
        ExecuteConsole("a.URO.VisibilityBasedAnimTickRate 1")
        ExecuteConsole("r.SkeletalMeshLODBias 2")
        ExecuteConsole("p.RigidBodyLODSubStepping 0")
        ExecuteConsole("p.ClothPhysics 0")

        -- 3. Seamless Distance Falloff & Continuous Landscape CDLOD
        ExecuteConsole("r.DitheredLODTransition 1")
        ExecuteConsole("landscape.LODDistanceFactor 2.50")
        ExecuteConsole("landscape.LOD0DistributionScale 0.50")
        ExecuteConsole("r.StaticMeshLODDistanceScale 0.75")
        ExecuteConsole("r.MeshLODRange 0.85")
        ExecuteConsole("r.SkyAtmosphere.AerialPerspectiveLUT.FastSkyLUT 1")
        ExecuteConsole("foliage.CullDistanceScale 0.75")
        ExecuteConsole("r.ViewDistanceScale 0.90")

        -- 4. Asynchronous Texture Streaming & CPU Amortization (Sodium Equivalent)
        ExecuteConsole("r.TextureStreaming 1")
        ExecuteConsole("r.Streaming.AmortizeCPUWork 1")
        ExecuteConsole("r.Streaming.AmortizeCPUToGPUCopy 1")
        ExecuteConsole("r.Streaming.FramesForFullUpdate 25")
        ExecuteConsole("r.Streaming.MaxNumTexturesToStreamPerFrame 6")
        ExecuteConsole("r.Streaming.DefragDynamicBounds 1")
        ExecuteConsole("r.Streaming.LimitPoolSizeToVRAM 1")
        ExecuteConsole("r.Streaming.HLODStrategy 1")
        ExecuteConsole("r.Streaming.PoolSize 2048")
        ExecuteConsole("r.Streaming.Boost 1")

        -- 5. Asynchronous Shader Compilation, PSO Caching & Stutter Elimination (C2ME Equivalent)
        ExecuteConsole("r.CreateShadersOnLoad 1")
        ExecuteConsole("r.Shaders.Optimize 1")
        ExecuteConsole("r.ShaderPipelineCache.Enabled 1")
        ExecuteConsole("r.ShaderPipelineCache.StartupMode 1")
        ExecuteConsole("r.ShaderPipelineCache.BatchTime 2.0")

        -- 6. Shadows & Lighting (Option B: 512p CSM Shadows, 1 Cascade)
        ExecuteConsole("r.VolumetricCloud 0")
        ExecuteConsole("r.VolumetricFog 0")
        ExecuteConsole("r.VolumetricFog.GridPixelSize 16")
        ExecuteConsole("r.VolumetricFog.GridSizeZ 64")
        ExecuteConsole("r.ContactShadows 0")
        ExecuteConsole("r.DistanceFieldShadowing 0")
        ExecuteConsole("r.DistanceFieldAO 0")
        ExecuteConsole("r.DFShadowQuality 0")
        ExecuteConsole("r.Shadow.Virtual.Enable 0")
        ExecuteConsole("r.Shadow.CSM.MaxCascades 1")
        ExecuteConsole("r.Shadow.MaxCSMResolution 512")
        ExecuteConsole("r.Shadow.DistanceScale 0.50")
        ExecuteConsole("r.Lumen.Reflections.Allow 0")
        ExecuteConsole("r.Lumen.ScreenProbeGather.DownsampleFactor 16")
        ExecuteConsole("r.DynamicGlobalIlluminationMethod 0")
        ExecuteConsole("r.AmbientOcclusionLevels 0")
        ExecuteConsole("r.SSR.Quality 0")

        -- 7. Foliage & Particle VFX (Option B: 40% Grass, Capped Emitters)
        ExecuteConsole("grass.DensityScale 0.40")
        ExecuteConsole("foliage.LODDistanceScale 0.60")
        ExecuteConsole("r.LightMaxDrawDistanceScale 0.70")
        ExecuteConsole("fx.Niagara.QualityLevel 0")
        ExecuteConsole("r.EmitterSpawnRateScale 0.50")
        ExecuteConsole("fx.Niagara.Cull.MaxDistance 6000")
        ExecuteConsole("r.TranslucencyLightingVolumeDim 16")
        ExecuteConsole("r.ParticleLODBias 1")
        ExecuteConsole("r.Emitter.FastPool 1")

        -- 8. UI & Slate Batching (ImmediatelyFast Equivalent)
        ExecuteConsole("Slate.CacheRenderData 1")
        ExecuteConsole("Slate.EnableAsyncDraw 1")

        -- 9. Frame Pacing, Low-Latency Sync & Dynamic Upscaling (Option B: 85% TSR)
        ExecuteConsole("r.GTSyncType 1")
        ExecuteConsole("r.OneFrameThreadLag 1")
        ExecuteConsole("r.FinishCurrentFrame 0")
        -- Respect the player's display/VSync cap instead of forcing 165 FPS.
        ExecuteConsole("t.UnfocusedMaxFPS 30")
        ExecuteConsole("r.ScreenPercentage 85")
        ExecuteConsole("r.TemporalAA.Upsampling 1")
        ExecuteConsole("r.TSR.ShadingRejection.Flickering 1")

        -- 10. Memory & Post-Processing (FerriteCore Equivalent)
        ExecuteConsole("r.DepthOfFieldQuality 0")
        ExecuteConsole("r.MotionBlurQuality 0")
        ExecuteConsole("r.SceneColorFringeQuality 0")
        ExecuteConsole("r.Tonemapper.GrainQuantization 0")
        ExecuteConsole("r.Tonemapper.Quality 1")
        ExecuteConsole("r.FastVRam.BokehDOF 1")
        ExecuteConsole("r.BloomQuality 1")
        local purgeInterval = math.max(15, tonumber(cpuCfg and cpuCfg.gcIntervalSeconds) or 60)
        ExecuteConsole("gc.TimeBetweenPurgingPendingKillObjects " .. tostring(purgeInterval))

        if not appliedOnce then
            print("[PalOdysseyOptimizer:Graphics] All 80+ render CVars dispatched successfully.")
            appliedOnce = true
        end
    end

    -- Apply after each world is ready; CVars persist without a polling loop.
    pcall(function()
        RegisterHook("/Script/Engine.World:ReceiveBeginPlay", function(Context)
            ExecuteWithDelay(1500, optimizeRenderSettings)
        end)
    end)
    -- Backup pass for builds that do not expose World:ReceiveBeginPlay.
    ExecuteWithDelay(6000, optimizeRenderSettings)

    print("[PalOdysseyOptimizer] Ultra-Performance Option B GPU Pipeline loaded successfully.")
end

return GraphicsModule
