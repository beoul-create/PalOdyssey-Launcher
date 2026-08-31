-- ============================================================================
-- PalworldTuner - Cable & Weapon Dismount Physics Restorer
-- Robust Multi-Target Cable Particle Reset (Player + Weapon + Mount + Sockets)
-- ============================================================================

local CableReset = {}

local function ResetActorCables(actor, cableClass)
    if not actor or not actor:IsValid() then return end
    pcall(function()
        if type(actor.GetComponentsByClass) == "function" then
            local comps = actor:GetComponentsByClass(cableClass)
            if comps and comps:IsValid() then
                for i = 1, comps:Num() do
                    local cable = comps:Get(i)
                    if cable and cable:IsValid() then
                        cable:SetVisibility(false, true)
                        if type(cable.ResetParticles) == "function" then
                            cable:ResetParticles()
                        end
                        cable.bEnableStiffness = true
                        ExecuteWithDelay(50, function()
                            if cable and cable:IsValid() then
                                cable:SetVisibility(true, true)
                            end
                        end)
                    end
                end
            end
        end
    end)
end

local function ResetAllPlayerCables()
    pcall(function()
        local cableClass = StaticFindObject("/Script/CableComponent.CableComponent")
        if not cableClass or not cableClass:IsValid() then return end

        local pc = UEHelpers and UEHelpers.GetPlayerController and UEHelpers.GetPlayerController()
        local targetActors = {}

        if pc and pc:IsValid() then
            if pc.Pawn and pc.Pawn:IsValid() then table.insert(targetActors, pc.Pawn) end
            if pc.Character and pc.Character:IsValid() then table.insert(targetActors, pc.Character) end
            if pc.MyPalCharacter and pc.MyPalCharacter:IsValid() then table.insert(targetActors, pc.MyPalCharacter) end
        end

        for _, actor in ipairs(targetActors) do
            -- 1. Direct actor cables
            ResetActorCables(actor, cableClass)

            -- 2. Equipped weapon cables
            if actor.ShooterComponent and actor.ShooterComponent:IsValid() and actor.ShooterComponent.EquippedWeapon then
                ResetActorCables(actor.ShooterComponent.EquippedWeapon, cableClass)
            end

            -- 3. Attached socket actors (e.g. back-sheathed or socketed fishing rods)
            if type(actor.GetAttachedActors) == "function" then
                local attached = {}
                actor:GetAttachedActors(attached)
                if attached and #attached > 0 then
                    for _, att in ipairs(attached) do
                        ResetActorCables(att, cableClass)
                    end
                end
            end
        end
    end)
end

function CableReset.Init()
    local mountEvents = {
        "/Script/Pal.PalRideMarkerComponent:OnEndRiding",
        "/Script/Pal.PalRideMarkerComponent:OnStartRiding",
        "/Script/Pal.PalActionRide:OnEndAction",
        "/Script/Pal.PalActionRide:OnBeginAction",
        "/Script/Pal.PalCharacter:OnEndRiding",
        "/Script/Pal.PalPlayerCharacter:OnEndRiding"
    }

    for _, eventName in ipairs(mountEvents) do
        pcall(RegisterHook, eventName, function()
            -- Immediate reset
            ResetAllPlayerCables()
            -- Delayed passes for post-physics detached state
            ExecuteWithDelay(80, ResetAllPlayerCables)
            ExecuteWithDelay(250, ResetAllPlayerCables)
        end)
    end

    print("[PalworldTuner] Multi-target Cable & Fishing Rod physics restorer active.")
end

return CableReset