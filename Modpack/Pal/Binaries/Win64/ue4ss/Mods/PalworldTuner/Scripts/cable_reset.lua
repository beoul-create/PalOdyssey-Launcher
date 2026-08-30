-- ============================================================================
-- PalworldTuner - Cable & Weapon Dismount Physics Restorer
-- Fixes Unreal Engine 5 CableComponent particle stretching on Pal dismount
-- ============================================================================

local CableReset = {}

local function ResetAllCables()
    pcall(function()
        local cables = FindAllOf("CableComponent") or {}
        for _, cable in ipairs(cables) do
            if cable and cable:IsValid() then
                pcall(function()
                    -- Momentarily toggle visibility to force UE5 to purge distant vertex buffer
                    cable:SetVisibility(false, true)
                    
                    if type(cable.ResetParticles) == "function" then
                        cable:ResetParticles()
                    end
                    
                    cable.bEnableStiffness = true

                    -- Re-enable visibility at correct local socket offset after 1 frame
                    if ExecuteWithDelay then
                        ExecuteWithDelay(60, function()
                            if cable and cable:IsValid() then
                                cable:SetVisibility(true, true)
                            end
                        end)
                    else
                        cable:SetVisibility(true, true)
                    end
                end)
            end
        end
    end)
end

function CableReset.Init()
    -- Hook all mount / dismount / weapon equip transition events
    local dismountHooks = {
        "/Script/Pal.PalRideMarkerComponent:OnEndRiding",
        "/Script/Pal.PalActionRide:OnEndAction",
        "/Script/Pal.PalPlayerCharacter:OnEndRide",
        "/Script/Pal.PalPlayerCharacter:OnUnRide",
        "/Script/Pal.PalCharacter:OnEndRide",
        "/Script/Pal.PalWeaponBase:OnEquip",
        "/Script/Pal.PalWeaponBase:OnAttachWeapon",
        "/Script/Engine.PlayerController:ClientRestart"
    }

    for _, hookName in ipairs(dismountHooks) do
        pcall(RegisterHook, hookName, function()
            if ExecuteWithDelay then
                ExecuteWithDelay(50, ResetAllCables)
                ExecuteWithDelay(200, ResetAllCables)
            else
                ResetAllCables()
            end
        end)
    end

    print("[PalworldTuner] CableReset module active: Dismount fishing rod particle stretching fix initialized.")
end

return CableReset