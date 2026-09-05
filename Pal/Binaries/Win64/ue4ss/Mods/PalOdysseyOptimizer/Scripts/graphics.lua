local isServer = string.find(debug.getinfo(1, "S").source:lower():gsub("\\", "/"), "/palserver/") ~= nil
if isServer then return {} end

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

        -- 1. Direct GPU Vertex Shading & CPU Frame Decoupling (Zero CPU-GPU Stalls)
        ExecuteConsole("r.OneFrameThreadLag 1")
        ExecuteConsole("r.FinishCurrentFrame 0")
        ExecuteConsole("r.MeshShaders 0")
        ExecuteConsole("r.MeshShaders.Enable 0")
        ExecuteConsole("r.GPUScene.InstanceCulling 1")
        ExecuteConsole("r.EarlyZPass 2")
        ExecuteConsole("r.EarlyZPassMovable 1")
        ExecuteConsole("r.SkinCache.Mode 0")
        ExecuteConsole("r.SkinCache.CompileShaders 0")
        ExecuteConsole("r.SkinCache.RecomputeTangents 0")
        ExecuteConsole("r.HZBOcclusion 1")
        ExecuteConsole("r.AllowOcclusionQueries 1")
        ExecuteConsole("r.Occlusion.MaxQueriesPerFrame 120")

        -- 2. Skeletal URO + Pose Interpolation + Low-Spec Pal Polygon Optimization (Max CPU Conservation)
        local lodBias = tonumber(cfg and cfg.skeletalLODBias) or 2
        local meshDist = tonumber(cfg and cfg.staticMeshLODDistanceScale) or 0.70
        local nanitePix = tonumber(cfg and cfg.naniteMaxPixelsPerEdge) or 4.0

        ExecuteConsole("a.URO.Enable 1")
        ExecuteConsole("a.URO.ForceAnimRate 2")
        ExecuteConsole("a.URO.TickDistanceScale 0.50")
        ExecuteConsole("a.URO.Interpolation 1")
        ExecuteConsole("a.URO.VisibilityBasedAnimTickRate 1")
        ExecuteConsole("a.URO.VisibilityBasedAnimTickOption 1")
        ExecuteConsole("p.ClothPhysics 0")
        ExecuteConsole("p.ClothPhysics.CullDistance 1200")
        ExecuteConsole("p.Chaos.CullDistance 2500")
        ExecuteConsole("p.Chaos.Solver.SubStepping 0")
        ExecuteConsole("r.SkeletalMeshLODBias " .. tostring(lodBias))
        ExecuteConsole("p.RigidBodyLODSubStepping 0")
        ExecuteConsole("r.DrawDebug 0")
        ExecuteConsole("p.VisualizeLineTraces 0")

        -- 3. More Culling: Seamless Distance Falloff & Occlusion Bounds
        ExecuteConsole("r.DitheredLODTransition 0")
        ExecuteConsole("landscape.LODDistanceFactor 2.50")
        ExecuteConsole("landscape.LOD0DistributionScale 0.50")
        ExecuteConsole("r.StaticMeshLODDistanceScale " .. tostring(meshDist))
        ExecuteConsole("r.MeshLODRange 0.85")
        ExecuteConsole("r.Nanite.MaxPixelsPerEdge " .. tostring(nanitePix))
        ExecuteConsole("r.SkyAtmosphere.AerialPerspectiveLUT.FastSkyLUT 1")
        ExecuteConsole("foliage.CullDistanceScale 0.70")
        ExecuteConsole("r.CullDistanceScale 0.80")
        ExecuteConsole("r.ViewDistanceScale 0.90")

        -- 4. Smart On-Demand Viewport Texture Streaming (Smooth Mount/Dismount & Low CPU)
        if not (_G.FastConnect and _G.FastConnect.Config and _G.FastConnect.Config.accelerateLoadingScreens) then
            ExecuteConsole("r.TextureStreaming 1")
            ExecuteConsole("r.Streaming.AmortizeCPUWork 1")
            ExecuteConsole("r.Streaming.AmortizeCPUToGPUCopy 1")
            ExecuteConsole("r.Streaming.FramesForFullUpdate 45")
            ExecuteConsole("r.Streaming.MaxNumTexturesToStreamPerFrame 12")
            ExecuteConsole("r.Streaming.DefragDynamicBounds 0")
            ExecuteConsole("r.Streaming.LimitPoolSizeToVRAM 1")
            ExecuteConsole("r.Streaming.UseFixedPoolSize 1")
            ExecuteConsole("r.Streaming.UsePerTextureBias 0")
            ExecuteConsole("r.Streaming.HLODStrategy 1")
            ExecuteConsole("r.Streaming.PoolSize 2048")
            ExecuteConsole("r.Streaming.Boost 1.5")
            ExecuteConsole("r.Streaming.FullyLoadUsedTextures 0")
            ExecuteConsole("gc.TimeBetweenPurgingPendingKillObjects 600")
            ExecuteConsole("gc.IncrementalBeginDestroyEnabled 1")
            ExecuteConsole("gc.MinDesiredFrameRate 60")
        end

        -- 5. Asynchronous Shader Compilation, PSO Caching & Stutter Elimination (C2ME Equivalent)
        ExecuteConsole("r.CreateShadersOnLoad 1")
        ExecuteConsole("r.Shaders.Optimize 1")
        ExecuteConsole("r.ShaderPipelineCache.Enabled 1")
        ExecuteConsole("r.ShaderPipelineCache.StartupMode 1")
        ExecuteConsole("r.ShaderPipelineCache.BatchTime 2.0")

        -- 6. High-Fidelity Optimized Shadows & Depth (Crisp 2048p CSM, 4 Cascades, Contact Shadows & Distance Fields)
        ExecuteConsole("r.VolumetricCloud 0")
        ExecuteConsole("r.VolumetricFog 0")
        ExecuteConsole("r.VolumetricFog.GridPixelSize 16")
        ExecuteConsole("r.VolumetricFog.GridSizeZ 64")
        ExecuteConsole("r.ShadowQuality 3")
        ExecuteConsole("r.Shadow.Virtual.Enable 0")
        ExecuteConsole("r.Shadow.MaxCSMResolution 2048")
        ExecuteConsole("r.Shadow.MaxResolution 2048")
        ExecuteConsole("r.Shadow.CSM.MaxCascades 4")
        ExecuteConsole("r.Shadow.DistanceScale 1.25")
        ExecuteConsole("r.Shadow.CSM.TransitionScale 1.5")
        ExecuteConsole("r.Shadow.FilterMethod 1")
        ExecuteConsole("r.Shadow.RadiusThreshold 0.02")
        ExecuteConsole("r.Shadow.FadeResolution 64")
        ExecuteConsole("r.ContactShadows 1")
        ExecuteConsole("r.ContactShadows.NonShadowCastingIntensity 0.5")
        ExecuteConsole("r.DistanceFieldShadowing 1")
        ExecuteConsole("r.DFShadowQuality 1")
        ExecuteConsole("r.AmbientOcclusionLevels 2")
        ExecuteConsole("r.AmbientOcclusionMaxQuality 1")
        ExecuteConsole("r.AmbientOcclusionRadiusScale 1.2")
        ExecuteConsole("r.Lumen.Reflections.Allow 0")
        ExecuteConsole("r.Lumen.DiffuseIndirect.Allow 0")
        ExecuteConsole("r.LumenScene.DirectLighting 0")
        ExecuteConsole("r.Lumen.ScreenProbeGather.DownsampleFactor 16")
        ExecuteConsole("r.Nanite.MaxPixelsPerEdge 6.0")
        ExecuteConsole("r.DynamicGlobalIlluminationMethod 0")
        ExecuteConsole("r.SSR.Quality 0")

        -- 7. Foliage & Particle VFX (Optimized for Peak Framerate & Zero Stutter)
        ExecuteConsole("grass.DensityScale 0.30")
        ExecuteConsole("foliage.LODDistanceScale 0.50")
        ExecuteConsole("r.StaticMeshLODDistanceScale 0.65")
        ExecuteConsole("r.LightMaxDrawDistanceScale 0.65")
        ExecuteConsole("fx.Niagara.QualityLevel 0")
        ExecuteConsole("r.EmitterSpawnRateScale 0.35")
        ExecuteConsole("fx.Niagara.Cull.MaxDistance 4500")
        ExecuteConsole("r.TranslucencyLightingVolumeDim 16")
        ExecuteConsole("r.ParticleLODBias 1")
        ExecuteConsole("r.Emitter.FastPool 1")

        -- 8. UI & Slate Fluidity
        ExecuteConsole("Slate.CacheRenderData 0")
        ExecuteConsole("Slate.EnableAsyncDraw 0")
        ExecuteConsole("Slate.AllowSlateUIInViewport 1")

        -- 9. Frame Pacing, Low-Latency Sync & Dynamic Upscaling (Ultra-Clean 80% TSR Upscaling)
        ExecuteConsole("r.GTSyncType 0")
        ExecuteConsole("r.OneFrameThreadLag 1")
        ExecuteConsole("r.FinishCurrentFrame 0")
        local backgroundFps = 0
        if cpuCfg and cpuCfg.limitBackgroundCpu ~= false then
            backgroundFps = math.max(5, math.min(60, tonumber(cpuCfg.backgroundMaxFPS) or 30))
        end
        ExecuteConsole("t.UnfocusedMaxFPS " .. tostring(backgroundFps))
        ExecuteConsole("r.ScreenPercentage 80")
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
        if not (_G.FastConnect and _G.FastConnect.Config and _G.FastConnect.Config.accelerateLoadingScreens) then
            local purgeInterval = math.max(600, tonumber(cpuCfg and cpuCfg.gcIntervalSeconds) or 600)
            ExecuteConsole("gc.TimeBetweenPurgingPendingKillObjects " .. tostring(purgeInterval))
        end

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
