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

local function ExecuteConsole(cmd)
    pcall(function()
        if type(_G.ExecuteConsoleCommand) == "function" then
            _G.ExecuteConsoleCommand(cmd)
        end
    end)
    pcall(function()
        if type(UEHelpers) ~= "table" then return end
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
        local world = type(UEHelpers) == "table" and (UEHelpers.GetWorld() or UEHelpers.GetWorldContextObject())
        if kismet and kismet:IsValid() and world and world:IsValid() then
            kismet:ExecuteConsoleCommand(world, cmd, nil)
        end
    end)
end

local function ApplyVisualTweaks()
    pcall(function()
        -- 1. Atmospheric Clarity & Cloud Raymarching Trimming
        if Config.removeFogHaze then
            ExecuteConsole("r.VolumetricFog 0")
            ExecuteConsole("r.VolumetricCloud 0")
            ExecuteConsole("r.ContactShadows 0")
        end
        if Config.disableChromaticAberration then
            ExecuteConsole("r.SceneColorFringeQuality 0")
        end
        if Config.disableFilmGrain then
            ExecuteConsole("r.Tonemapper.GrainQuantization 0")
            ExecuteConsole("r.Tonemapper.Quality 1")
        end
        if Config.crispDepthOfField then
            ExecuteConsole("r.DepthOfFieldQuality 0")
            ExecuteConsole("r.MotionBlurQuality 0")
        end

        -- 2. Better Night Light & Atmosphere
        if Config.betterNightLight then
            ExecuteConsole("r.SkylightIntensityMultiplier 1.35")
            ExecuteConsole("r.Lumen.DiffuseIndirect.MinRoughness 0.1")
        end

        -- 3. Seamless Distance Falloff & Dithered Blending (Zero Pop-In)
        if Config.enhancedLODDistance then
            ExecuteConsole("r.DitheredLODTransition 1")
            ExecuteConsole("landscape.LODDistanceFactor 2.50")
            ExecuteConsole("landscape.LOD0DistributionScale 0.50")
            ExecuteConsole("r.ViewDistanceScale 0.90")
            ExecuteConsole("foliage.LODDistanceScale 0.60")
            ExecuteConsole("grass.DensityScale 0.40")
            ExecuteConsole("r.StaticMeshLODDistanceScale 0.75")
            ExecuteConsole("r.MeshLODRange 0.85")
            ExecuteConsole("r.SkyAtmosphere.AerialPerspectiveLUT.FastSkyLUT 1")
        end

        -- 4. Ultra-Wide 21:9 & 32:9 HUD Fix
        if Config.ultraWideSupport then
            ExecuteConsole("r.AspectRatioAxisConstraint 1")
        end

        -- 5. Async Texture Streaming & Stutter Elimination (Sodium Equivalent)
        if Config.asyncTextureStreaming then
            ExecuteConsole("r.TextureStreaming 1")
            ExecuteConsole("r.Streaming.AmortizeCPUWork 1")
            ExecuteConsole("r.Streaming.AmortizeCPUToGPUCopy 1")
            ExecuteConsole("r.Streaming.FramesForFullUpdate 25")
            ExecuteConsole("r.Streaming.MaxNumTexturesToStreamPerFrame 6")
            ExecuteConsole("r.Streaming.HLODStrategy 1")
            ExecuteConsole("r.Streaming.DefragDynamicBounds 1")
            ExecuteConsole("r.Streaming.LimitPoolSizeToVRAM 1")
        end

        -- 6. Frame Pacing & Low-Latency Sync
        if Config.framePacingReflex then
            ExecuteConsole("r.GTSyncType 1")
            ExecuteConsole("r.OneFrameThreadLag 1")
            ExecuteConsole("r.FinishCurrentFrame 0")
        end

        -- 7. Enhanced Upscaling Reconstruction & Anti-Aliasing (Option B: 85% TSR)
        if Config.enhancedUpscaling then
            ExecuteConsole("r.ScreenPercentage 85")
            ExecuteConsole("r.TSR.ShadingRejection.Flickering 1")
            ExecuteConsole("r.TemporalAA.Upsampling 1")
        end

        Log("Applied comprehensive Option B visual, lighting, LOD, and upscaling enhancements.")
    end)
end

-- Apply on game start and world entry
local function SafeDelayedApply()
    ExecuteWithDelay(3000, ApplyVisualTweaks)
    ExecuteWithDelay(8000, ApplyVisualTweaks)
end

pcall(function()
    NotifyOnNewObject("/Script/Pal.PalGameSetting", function()
        SafeDelayedApply()
    end)
end)

pcall(function()
    RegisterHook("/Script/Engine.PlayerController:ClientRestart", function(Context)
        SafeDelayedApply()
    end)
end)

SafeDelayedApply()

Log("PalClearVision initialized successfully.")

Log("PalClearVision Visual & Rendering Suite loaded successfully.")
