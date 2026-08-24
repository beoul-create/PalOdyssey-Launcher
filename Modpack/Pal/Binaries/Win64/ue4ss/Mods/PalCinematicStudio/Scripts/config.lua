-- ============================================================================
-- PalCinematicStudio: Configuration
-- 360° FreeCam, Time Freeze, Super-Resolution Screenshot & Photo Mode Suite
-- ============================================================================

local Config = {
    enabled = true,
    
    -- Hotkeys (Configurable)
    freeCamKey = "F8",          -- Toggle 360° Detached FreeCam (Fly anywhere)
    timeFreezeKey = "F9",       -- Freeze/Resume world time (slomo 0.0001)
    toggleHudKey = "F10",       -- Toggle Clean Viewport / Hide HUD
    highResShotKey = "F11",     -- Capture Super-Resolution uncompressed screenshot
    
    -- Screenshot Settings
    highResMultiplier = 2,      -- 2x Screen Resolution (e.g. 1080p -> 4K, 1440p -> 5K)
    
    -- Lens & Depth of Field (FOV)
    defaultFov = 90.0,
    portraitFov = 45.0,
    fovStep = 5.0,
    
    -- Logging
    log = true
}

function Config.load()
    return Config
end

return Config
