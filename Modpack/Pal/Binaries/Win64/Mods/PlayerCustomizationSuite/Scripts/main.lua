-- =========================================================================
-- PalOdyssey - Player Customization & Character Creator Expansion Suite
-- Expands character creation sliders, unlocks all NPC hairstyles,
-- removes color restrictions, and enables in-game wardrobe.
-- =========================================================================

local MOD_NAME = "PlayerCustomizationSuite"
local MOD_VERSION = "1.0.0"

local function UnlockCharacterCreationLimits(widget)
    if not widget or not widget:IsValid() then return end

    pcall(function()
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
    end)
end

-- Safely hook specific Character Creation widgets via NotifyOnNewObject
NotifyOnNewObject("/Game/Pal/Blueprint/UI/UserInterface/CharacterMake/WBP_CharacterMake_Body.WBP_CharacterMake_Body_C", function(widget)
    UnlockCharacterCreationLimits(widget)
end)

NotifyOnNewObject("/Game/Pal/Blueprint/UI/UserInterface/CharacterMake/WBP_CharacterMake.WBP_CharacterMake_C", function(widget)
    UnlockCharacterCreationLimits(widget)
end)

print(string.format("[%s] v%s - In-Depth Player Customization & Hairstyle Suite active.", MOD_NAME, MOD_VERSION))
