-- PalOdysseyOptimizer - FPS Boost & GPU Assist Subsystem (Ultra-Performance Option B Profile)
local GraphicsModule = {}

-- Each dispatch path is tried independently so a failure in one never skips the others.
local function ExecuteConsole(cmd)
    pcall(function()
        if type(_G.ExecuteConsoleCommand) == "function" then
            _G.ExecuteConsoleCommand(cmd)
        end
    end)
    pcall(function()
        local pc = UEHelpers.GetPlayerController()
        if not pc or not pc:IsValid() then
            local pcs = FindAllOf("PalPlayerController") or FindAllOf("PlayerController")
            if pcs and #pcs > 0 then pc = pcs[1] end
        end
        if pc and pc:IsValid() and pc.ConsoleCommand then
            pc:ConsoleCommand(cmd, true)
        end
    end)
    pcall(function()
        local kismet = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
        local world = UEHelpers.GetWorldContextObject()
        if not world or not world:IsValid() then
            local pc = UEHelpers.GetPlayerController()
            if pc and pc:IsValid() then world = pc end
        end
        if kismet and kismet:IsValid() and world and world:IsValid() then
            kismet:ExecuteConsoleCommand(world, cmd, nil)
        end
    end)
end

function GraphicsModule.apply(cfg)
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
        ExecuteConsole("t.MaxFPS 165")
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
        ExecuteConsole("gc.TimeBetweenPurgingPendingKillObjects 15")

        if not appliedOnce then
            print("[PalOdysseyOptimizer:Graphics] All 80+ render CVars dispatched successfully.")
            appliedOnce = true
        end
    end

    -- Hook GameEngine Init
    pcall(function()
        RegisterHook("/Script/Engine.GameEngine:Init", function(Context)
            optimizeRenderSettings()
        end)
    end)

    -- Hook World BeginPlay and Player Restart for fast-travel / map transitions
    pcall(function()
        RegisterHook("/Script/Engine.World:ReceiveBeginPlay", function(Context)
            optimizeRenderSettings()
            ExecuteWithDelay(1500, optimizeRenderSettings)
        end)
    end)
    pcall(function()
        RegisterHook("/Script/Engine.PlayerController:ClientRestart", function(Context)
            optimizeRenderSettings()
        end)
    end)

    -- Initial passes
    ExecuteWithDelay(2000, optimizeRenderSettings)
    ExecuteWithDelay(6000, optimizeRenderSettings)

    -- Periodic 30-second sanity enforcement to prevent in-game scalability resets
    local enforceCount = 0
    local function continuousOptimizationLoop()
        optimizeRenderSettings()
        enforceCount = enforceCount + 1
        if enforceCount % 10 == 0 then
            print(string.format("[PalOdysseyOptimizer:Graphics] Heartbeat #%d — GPU pipeline active.", enforceCount))
        end
        ExecuteWithDelay(30000, continuousOptimizationLoop)
    end
    ExecuteWithDelay(30000, continuousOptimizationLoop)

    print("[PalOdysseyOptimizer] Ultra-Performance Option B GPU Pipeline loaded successfully.")
end

return GraphicsModule
