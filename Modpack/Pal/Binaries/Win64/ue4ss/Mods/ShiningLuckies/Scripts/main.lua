-- Shining Luckies Visual Indicator Suite
-- PalOdyssey Cosmetic Polish Mod
local ShiningLuckies = {
    version = "1.0.0",
    config = {
        enabled = true,
        glowIntensity = "Moderate", -- "Subtle", "Moderate", "Vibrant"
        starGlintParticles = true,
        beaconBeamDistance = 100.0
    }
}

local function Init()
    print(string.format("[ShiningLuckies v%s] Initialized. Rare Pal visual shimmer active.", ShiningLuckies.version))
end

Init()
return ShiningLuckies
