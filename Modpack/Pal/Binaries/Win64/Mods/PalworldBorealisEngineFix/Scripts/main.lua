---@diagnostic disable: undefined-global
-- ============================================================================
-- Palworld Borealis Engine Unlocks (Clouds, Sky, Water)
-- 100% Original Custom Script 
-- ============================================================================

local isApplied = false

local function ApplyEngineUnlocks(PlayerController)
    if isApplied then return end

    local KismetSystemLibrary = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
    
    if KismetSystemLibrary and KismetSystemLibrary:IsValid() and PlayerController and PlayerController:IsValid() then
        -- Send the console commands using the PlayerController as the World Context
        KismetSystemLibrary:ExecuteConsoleCommand(PlayerController, "r.DynamicGlobalIlluminationMethod 1", nil)
        KismetSystemLibrary:ExecuteConsoleCommand(PlayerController, "r.ReflectionMethod 1", nil)
        KismetSystemLibrary:ExecuteConsoleCommand(PlayerController, "r.Lumen.DiffuseIndirect.Allow 1", nil)
        KismetSystemLibrary:ExecuteConsoleCommand(PlayerController, "r.Lumen.Reflections.Allow 1", nil)
        KismetSystemLibrary:ExecuteConsoleCommand(PlayerController, "r.DistanceFields 1", nil)
        KismetSystemLibrary:ExecuteConsoleCommand(PlayerController, "r.DistanceFieldShadowing 1", nil)
        
        KismetSystemLibrary:ExecuteConsoleCommand(PlayerController, "r.Water.SingleLayer.Reflection 1", nil)
        KismetSystemLibrary:ExecuteConsoleCommand(PlayerController, "r.Lumen.TranslucencyReflections.FrontLayer.Enable 1", nil)
        KismetSystemLibrary:ExecuteConsoleCommand(PlayerController, "r.SSR.Quality 4", nil)
        KismetSystemLibrary:ExecuteConsoleCommand(PlayerController, "r.Water.SingleLayer.ShadingQuality 1", nil)
        KismetSystemLibrary:ExecuteConsoleCommand(PlayerController, "r.Water.SingleLayer.WaterDepthQuality 1", nil)
        KismetSystemLibrary:ExecuteConsoleCommand(PlayerController, "r.Water.SingleLayer.UseSSR 1", nil)
        
        KismetSystemLibrary:ExecuteConsoleCommand(PlayerController, "r.RayTracing.Translucency 1", nil)
        KismetSystemLibrary:ExecuteConsoleCommand(PlayerController, "r.Lumen.Reflections.MaxRoughnessToTrace 1", nil)
        
        KismetSystemLibrary:ExecuteConsoleCommand(PlayerController, "r.VolumetricCloud 1", nil)
        KismetSystemLibrary:ExecuteConsoleCommand(PlayerController, "r.VolumetricCloud.HighQuality 1", nil)
        KismetSystemLibrary:ExecuteConsoleCommand(PlayerController, "r.VolumetricCloud.ViewRaySampleCountMax 512", nil)
        KismetSystemLibrary:ExecuteConsoleCommand(PlayerController, "r.VolumetricCloud.Shadow.ViewRaySampleCountMax 256", nil)
        KismetSystemLibrary:ExecuteConsoleCommand(PlayerController, "r.VolumetricCloud.SkyAO 1", nil)
        
        KismetSystemLibrary:ExecuteConsoleCommand(PlayerController, "r.SkyAtmosphere.TransmittanceLUT.UseSmallFormat 0", nil)
        -- (Removed) r.ContactShadows 1 caused the player's hip lantern to self-shadow in caves, making them pitch black.
        -- KismetSystemLibrary:ExecuteConsoleCommand(PlayerController, "r.ContactShadows 1", nil)
        -- KismetSystemLibrary:ExecuteConsoleCommand(PlayerController, "r.ContactShadows.MaxRayTraceDistance 50", nil)
        
        print("[BorealisEngineFix] Custom Volumetric & Water Graphics Unlocked!\n")
        isApplied = true
    end
end

-- Hook into ClientRestart which fires exactly when the player spawns into the world
RegisterHook("/Script/Engine.PlayerController:ClientRestart", function(Context)
    local PlayerController = Context:get()
    
    ExecuteInGameThread(function()
        ApplyEngineUnlocks(PlayerController)
    end)
end)
