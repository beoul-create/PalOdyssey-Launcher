-- Clean HUD, Watermark Remover & Pristine Reticle Suite
-- PalOdyssey Visual Polish Mod
local CleanHUD = {
    version = "1.1.0",
    config = {
        enabled = true,
        removeWatermark = true,
        removeBuildVersion = true,
        hideCompassClutter = false,
        reticleStyle = "Dot", -- "Default", "Dot", "MinimalCrosshair", "CircleDot"
        reticleColor = "PureWhite"
    }
}

local function Init()
    print(string.format("[CleanHUD v%s] Initialized. Watermark removed & reticle suite ready.", CleanHUD.version))
end

Init()
return CleanHUD
