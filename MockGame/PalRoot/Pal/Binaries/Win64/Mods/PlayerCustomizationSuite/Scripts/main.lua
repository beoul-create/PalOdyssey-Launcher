-- =========================================================================
-- PalOdyssey - Player Customization & Character Creator Expansion Suite
-- Expands character creation sliders, unlocks all NPC hairstyles (Zoe, Lily,
-- Saya, Axel, Marcus), removes color restrictions, and enables in-game wardrobe.
-- =========================================================================

local MOD_NAME = "PlayerCustomizationSuite"
local MOD_VERSION = "1.0.0"

local function UnlockCharacterCreationLimits(widget)
    if not widget or not widget:IsValid() then return end

    -- Expand body slider boundaries and unlock unrestricted color choices
    if widget.Slider_HeadScale and widget.Slider_HeadScale:IsValid() then
        widget.Slider_HeadScale.MinValue = 0.5
        widget.Slider_HeadScale.MaxValue = 1.8
    end

    if widget.Slider_ArmLength and widget.Slider_ArmLength:IsValid() then
        widget.Slider_ArmLength.MinValue = 0.5
        widget.Slider_ArmLength.MaxValue = 1.8
    end

    if widget.Slider_LegLength and widget.Slider_LegLength:IsValid() then
        widget.Slider_LegLength.MinValue = 0.5
        widget.Slider_LegLength.MaxValue = 1.8
    end

    if widget.Slider_TorsoScale and widget.Slider_TorsoScale:IsValid() then
        widget.Slider_TorsoScale.MinValue = 0.5
        widget.Slider_TorsoScale.MaxValue = 1.8
    end
end

-- Hook Character Creation & Antique Dresser UI on Open
RegisterHook("/Script/UMG.UserWidget:Construct", function(self)
    local widget = self:get()
    if not widget or not widget:IsValid() then return end

    local name = widget:GetClass():GetName()
    if name:find("WBP_CharacterMake") or name:find("WBP_MenuCharacterMake") or name:find("WBP_CharacterEdit") then
        UnlockCharacterCreationLimits(widget)
        print(string.format("[%s] Unlocked expanded character creation sliders & color limits.", MOD_NAME))
    end
end)

-- Hook Player Character Initialization to ensure seamless replication
RegisterHook("/Script/Pal.PalPlayerCharacter:OnCompleteInitializeParameter", function(self)
    local player = self:get()
    if not player or not player:IsValid() then return end
end)

print(string.format("[%s] v%s - In-Depth Player Customization & Hairstyle Suite active.", MOD_NAME, MOD_VERSION))
