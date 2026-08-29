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
        -- High-Performance Visual Pipeline (Optimized Reflections, Screen Space Lighting & Efficient Volumetrics)
        KismetSystemLibrary:ExecuteConsoleCommand(PlayerController, "r.DynamicGlobalIlluminationMethod 0", nil)
        KismetSystemLibrary:ExecuteConsoleCommand(PlayerController, "r.ReflectionMethod 1", nil)
        KismetSystemLibrary:ExecuteConsoleCommand(PlayerController, "r.DistanceFields 0", nil)
        KismetSystemLibrary:ExecuteConsoleCommand(PlayerController, "r.DistanceFieldShadowing 0", nil)
        
        KismetSystemLibrary:ExecuteConsoleCommand(PlayerController, "r.Water.SingleLayer.Reflection 1", nil)
        KismetSystemLibrary:ExecuteConsoleCommand(PlayerController, "r.SSR.Quality 2", nil)
        KismetSystemLibrary:ExecuteConsoleCommand(PlayerController, "r.Water.SingleLayer.ShadingQuality 1", nil)
        KismetSystemLibrary:ExecuteConsoleCommand(PlayerController, "r.Water.SingleLayer.WaterDepthQuality 1", nil)
        KismetSystemLibrary:ExecuteConsoleCommand(PlayerController, "r.Water.SingleLayer.UseSSR 1", nil)
        
        KismetSystemLibrary:ExecuteConsoleCommand(PlayerController, "r.RayTracing.Translucency 0", nil)
        
        KismetSystemLibrary:ExecuteConsoleCommand(PlayerController, "r.VolumetricCloud 1", nil)
        KismetSystemLibrary:ExecuteConsoleCommand(PlayerController, "r.VolumetricCloud.HighQuality 0", nil)
        KismetSystemLibrary:ExecuteConsoleCommand(PlayerController, "r.VolumetricCloud.ViewRaySampleCountMax 64", nil)
        KismetSystemLibrary:ExecuteConsoleCommand(PlayerController, "r.VolumetricCloud.Shadow.ViewRaySampleCountMax 32", nil)
        KismetSystemLibrary:ExecuteConsoleCommand(PlayerController, "r.VolumetricCloud.SkyAO 0", nil)
        
        KismetSystemLibrary:ExecuteConsoleCommand(PlayerController, "r.SkyAtmosphere.TransmittanceLUT.UseSmallFormat 1", nil)
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
