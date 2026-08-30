-- ============================================================================
-- PalworldTuner - Cable & Weapon Dismount Physics Restorer
-- Lightweight direct-pointer cable particle reset (Zero Global Array Scans)
-- ============================================================================

local CableReset = {}

local function ResetTargetActorCables(Actor)
    if not Actor or not Actor:IsValid() then return end
    pcall(function()
        -- Directly check components on the actor without scanning FUObjectArray
        if type(Actor.GetComponentsByClass) == "function" then
            local cableClass = StaticFindObject("/Script/CableComponent.CableComponent")
            if cableClass and cableClass:IsValid() then
                local comps = Actor:GetComponentsByClass(cableClass)
                if comps and comps:IsValid() then
                    for i = 1, comps:Num() do
                        local cable = comps:Get(i)
                        if cable and cable:IsValid() then
                            cable:SetVisibility(false, true)
                            if type(cable.ResetParticles) == "function" then
                                cable:ResetParticles()
                            end
                            cable.bEnableStiffness = true
                            if ExecuteWithDelay then
                                ExecuteWithDelay(50, function()
                                    if cable and cable:IsValid() then
                                        cable:SetVisibility(true, true)
                                    end
                                end)
                            else
                                cable:SetVisibility(true, true)
                            end
                        end
                    end
                end
            end
        end
    end)
end

function CableReset.Init()
    -- Only hook dismount end action directly
    local dismountHooks = {
        "/Script/Pal.PalRideMarkerComponent:OnEndRiding",
        "/Script/Pal.PalActionRide:OnEndAction"
    }

    for _, hookName in ipairs(dismountHooks) do
        pcall(RegisterHook, hookName, function(Context)
            pcall(function()
                local obj = Context and Context.get and Context:get() or Context
                if not obj or not obj:IsValid() then return end
                
                local char = nil
                if type(obj.GetOwner) == "function" then
                    char = obj:GetOwner()
                elseif obj.Character then
                    char = obj.Character
                end

                if char and char:IsValid() then
                    -- Check equipped weapon on character
                    if char.ShooterComponent and char.ShooterComponent:IsValid() and char.ShooterComponent.EquippedWeapon then
                        ResetTargetActorCables(char.ShooterComponent.EquippedWeapon)
                    end
                end
            end)
        end)
    end

    print("[PalworldTuner] Lightweight CableReset initialized (Zero UObject table scanning).")
end

return CableReset