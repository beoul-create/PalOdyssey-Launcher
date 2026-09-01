local isServer = string.find(debug.getinfo(1, "S").source:lower():gsub("\\", "/"), "/palserver/") ~= nil
if isServer then return {} end

local CableReset = {}

local function ResetSingleCable(cable)
    if not cable or not cable:IsValid() then return end
    pcall(function()
        cable.bEnableStiffness = true
        cable.bEnableCollision = false
        if type(cable.ResetParticles) == "function" then
            cable:ResetParticles()
        end
        cable:SetVisibility(false, true)
        ExecuteWithDelay(40, function()
            if cable and cable:IsValid() then
                if type(cable.ResetParticles) == "function" then
                    cable:ResetParticles()
                end
                cable:SetVisibility(true, true)
            end
        end)
    end)
end

local function ResetActorComponents(actor)
    if not actor or not actor:IsValid() then return end
    pcall(function()
        -- 1. Check all direct components
        if type(actor.K2_GetComponentsByClass) == "function" then
            local compClass = StaticFindObject("/Script/Engine.ActorComponent")
            if compClass and compClass:IsValid() then
                local comps = actor:K2_GetComponentsByClass(compClass)
                if comps and comps:IsValid() then
                    for i = 1, comps:Num() do
                        local comp = comps:Get(i)
                        if comp and comp:IsValid() then
                            local name = comp:GetClass():GetName()
                            if name:find("Cable") or name:find("Line") or name:find("Fishing") then
                                ResetSingleCable(comp)
                            end
                        end
                    end
                end
            end
        end

        -- 2. Check weapon actor
        if actor.ShooterComponent and actor.ShooterComponent:IsValid() and actor.ShooterComponent.EquippedWeapon then
            local wep = actor.ShooterComponent.EquippedWeapon
            if wep and wep:IsValid() then
                ResetActorComponents(wep)
            end
        end

        -- 3. Check attached child actors
        if type(actor.GetAttachedActors) == "function" then
            local attached = {}
            actor:GetAttachedActors(attached)
            if attached and #attached > 0 then
                for _, att in ipairs(attached) do
                    if att and att:IsValid() then
                        ResetActorComponents(att)
                    end
                end
            end
        end
    end)
end

local function ResetAllCablesUniversal()
    pcall(function()
        -- Strategy 1: FindAllOf for all live CableComponents
        local cableComps = FindAllOf("CableComponent") or {}
        local palCables = FindAllOf("PalCableComponent") or {}
        for _, c in ipairs(cableComps) do ResetSingleCable(c) end
        for _, c in ipairs(palCables) do ResetSingleCable(c) end

        -- Strategy 2: Direct local player hierarchy inspection
        local pc = UEHelpers and UEHelpers.GetPlayerController and UEHelpers.GetPlayerController()
        if pc and pc:IsValid() then
            if pc.Pawn and pc.Pawn:IsValid() then ResetActorComponents(pc.Pawn) end
            if pc.Character and pc.Character:IsValid() then ResetActorComponents(pc.Character) end
            if pc.MyPalCharacter and pc.MyPalCharacter:IsValid() then ResetActorComponents(pc.MyPalCharacter) end
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
        "/Script/Pal.PalCharacter:OnStartRiding",
        "/Script/Pal.PalPlayerCharacter:OnEndRiding",
        "/Script/Pal.PalPlayerCharacter:OnStartRiding",
        "/Script/Pal.PalShooterComponent:OnAttachWeapon",
        "/Script/Pal.PalShooterComponent:OnDetachWeapon",
        "/Script/Pal.PalShooterComponent:ChangeWeapon"
    }

    for _, eventName in ipairs(mountEvents) do
        pcall(RegisterHook, eventName, function()
            ResetAllCablesUniversal()
            ExecuteWithDelay(60, ResetAllCablesUniversal)
            ExecuteWithDelay(200, ResetAllCablesUniversal)
            ExecuteWithDelay(500, ResetAllCablesUniversal)
        end)
    end

    -- Periodic heartbeat safety pass (runs every 1000ms, ultra-lightweight)
    LoopAsync(1000, function()
        ResetAllCablesUniversal()
        return false
    end)

    print("[PalworldTuner] Universal Multi-Strategy Cable & Fishing Rod physics restorer active.")
end

return CableReset