-- PalClearVision: Comprehensive Visual Clarity, Night Atmosphere, Ultrawide, LOD, and Engine Rendering Suite
local ok, Config = pcall(require, "config")
if not ok or type(Config) ~= "table" then
    Config = {
        enabled = true,
        removeFogHaze = true,
        disableChromaticAberration = true,
        disableFilmGrain = true,
        crispDepthOfField = true,
        betterNightLight = true,
        enhancedLODDistance = true,
        ultraWideSupport = true,
        asyncTextureStreaming = true,
        framePacingReflex = true,
        enhancedUpscaling = true,
        log = true
    }
end

local function Log(msg)
    if Config.log then
        print(string.format("[PalClearVision] %s\n", tostring(msg)))
    end
end

if not Config.enabled then return end

local function ApplyVisualTweaks()
    pcall(function()
        local player = GetPlayerController()
        if not player or not player:IsValid() then return end

        -- 1. Atmospheric Clarity & Cloud Raymarching Trimming
        if Config.removeFogHaze then
            ExecuteConsoleCommand("r.VolumetricFog 0")
            ExecuteConsoleCommand("r.VolumetricCloud 0")
            ExecuteConsoleCommand("r.ContactShadows 0")
        end
        if Config.disableChromaticAberration then
            ExecuteConsoleCommand("r.SceneColorFringeQuality 0")
        end
        if Config.disableFilmGrain then
            ExecuteConsoleCommand("r.Tonemapper.GrainQuantization 0")
            ExecuteConsoleCommand("r.Tonemapper.Quality 1")
        end
        if Config.crispDepthOfField then
            ExecuteConsoleCommand("r.DepthOfFieldQuality 0")
            ExecuteConsoleCommand("r.MotionBlurQuality 0")
        end

        -- 2. Better Night Light & Atmosphere
        if Config.betterNightLight then
            ExecuteConsoleCommand("r.SkylightIntensityMultiplier 1.35")
            ExecuteConsoleCommand("r.Lumen.DiffuseIndirect.MinRoughness 0.1")
        end

        -- 3. Seamless Distance Falloff & Dithered Blending (Zero Pop-In)
        if Config.enhancedLODDistance then
            ExecuteConsoleCommand("r.DitheredLODTransition 1")
            ExecuteConsoleCommand("landscape.LODDistanceFactor 2.50")
            ExecuteConsoleCommand("landscape.LOD0DistributionScale 0.50")
            ExecuteConsoleCommand("r.ViewDistanceScale 1.0")
            ExecuteConsoleCommand("foliage.LODDistanceScale 0.60")
            ExecuteConsoleCommand("grass.DensityScale 0.40")
            ExecuteConsoleCommand("r.StaticMeshLODDistanceScale 0.75")
            ExecuteConsoleCommand("r.MeshLODRange 0.85")
            ExecuteConsoleCommand("r.SkyAtmosphere.AerialPerspectiveLUT.FastSkyLUT 1")
        end

        -- 4. Ultra-Wide 21:9 & 32:9 HUD Fix
        if Config.ultraWideSupport then
            ExecuteConsoleCommand("r.AspectRatioAxisConstraint 1")
        end

        -- 5. Async Texture Streaming & Stutter Elimination (Sodium Equivalent)
        if Config.asyncTextureStreaming then
            ExecuteConsoleCommand("r.TextureStreaming 1")
            ExecuteConsoleCommand("r.Streaming.AmortizeCPUWork 1")
            ExecuteConsoleCommand("r.Streaming.AmortizeCPUToGPUCopy 1")
            ExecuteConsoleCommand("r.Streaming.FramesForFullUpdate 25")
            ExecuteConsoleCommand("r.Streaming.MaxNumTexturesToStreamPerFrame 6")
            ExecuteConsoleCommand("r.Streaming.HLODStrategy 1")
            ExecuteConsoleCommand("r.Streaming.DefragDynamicBounds 1")
            ExecuteConsoleCommand("r.Streaming.LimitPoolSizeToVRAM 1")
        end

        -- 6. Frame Pacing & Low-Latency Sync
        if Config.framePacingReflex then
            ExecuteConsoleCommand("r.GTSyncType 1")
            ExecuteConsoleCommand("r.OneFrameThreadLag 1")
            ExecuteConsoleCommand("r.FinishCurrentFrame 0")
        end

        -- 7. Enhanced Upscaling Reconstruction & Anti-Aliasing (Option B: 85% TSR)
        if Config.enhancedUpscaling then
            ExecuteConsoleCommand("r.ScreenPercentage 85")
            ExecuteConsoleCommand("r.TSR.ShadingRejection.Flickering 1")
            ExecuteConsoleCommand("r.TemporalAA.Upsampling 1")
        end

        Log("Applied comprehensive Option B visual, lighting, LOD, and upscaling enhancements.")
    end)
end

-- Apply on game start and world entry
NotifyOnNewObject("/Script/Pal.PalGameSetting", function()
    LoopAsync(3000, function()
        ApplyVisualTweaks()
        return true -- Run once per session after player spawns
    end)
end)

Log("PalClearVision Visual & Rendering Suite loaded successfully.")
