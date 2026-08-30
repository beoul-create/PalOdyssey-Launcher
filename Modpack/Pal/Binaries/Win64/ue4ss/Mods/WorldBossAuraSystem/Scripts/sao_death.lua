local SAODeath = {}
local RecentlyHandled = setmetatable({}, { __mode = "k" })
local OriginalState = setmetatable({}, { __mode = "k" })

-- Native Palworld disintegration & crystal burst effects
local CandidateParticles = {
    "/Game/Pal/Effect/Niagara/Common/NS_Capture_Success.NS_Capture_Success",
    "/Game/Pal/Effect/Niagara/Common/NS_Pal_Vanish.NS_Pal_Vanish",
    "/Game/Pal/Effect/Niagara/Common/NS_PalDead_Dissolve.NS_PalDead_Dissolve",
    "/Game/Pal/Effect/Niagara/Common/NS_Common_Hit_Critical.NS_Common_Hit_Critical",
    "/Game/Pal/Effect/Niagara/Common/NS_Common_Hit_01.NS_Common_Hit_01"
}

local CandidateSounds = {
    "/Game/Pal/Sound/Events/SE/SE_Pal_Capture_Success.SE_Pal_Capture_Success",
    "/Game/Pal/Sound/Events/SE/SE_Damage_Critical.SE_Damage_Critical"
}

local function FindFirstValidAsset(candidates)
    for _, path in ipairs(candidates) do
        local obj = StaticFindObject(path)
        if (not obj or not obj:IsValid()) and type(LoadAsset) == "function" then
            local ok, loaded = pcall(LoadAsset, path)
            if ok then obj = loaded end
        end
        if obj and obj:IsValid() then
            return obj
        end
    end
    return nil
end

local function HandleSAODeath(Character)
    if not Character or not Character:IsValid() then return end
    local now = os.clock()
    if RecentlyHandled[Character] and now - RecentlyHandled[Character] < 1.0 then return end
    RecentlyHandled[Character] = now

    pcall(function()
        local Location = Character:K2_GetActorLocation()
        local Rotation = Character:K2_GetActorRotation()
        local World = Character:GetWorld()

        -- 1. Disable Actor Collision & Ragdoll Physics across all components
        local Mesh = Character.Mesh
        local state = { actorCollision = true, meshCollision = 1, meshPhysics = false }
        pcall(function() state.actorCollision = Character:GetActorEnableCollision() end)
        pcall(function() if Mesh then state.meshCollision = Mesh:GetCollisionEnabled() end end)
        pcall(function() if Mesh then state.meshPhysics = Mesh:IsSimulatingPhysics() end end)
        OriginalState[Character] = state
        Character:SetActorEnableCollision(false)

        if Character.PalDeadRagdollComponent and Character.PalDeadRagdollComponent:IsValid() then
            Character.PalDeadRagdollComponent.bEnablePhysics = false
            if type(Character.PalDeadRagdollComponent.Deactivate) == "function" then
                Character.PalDeadRagdollComponent:Deactivate()
            end
        end

        if Mesh and Mesh:IsValid() then
            if type(Mesh.SetSimulatePhysics) == "function" then
                Mesh:SetSimulatePhysics(false)
            end
            if type(Mesh.SetCollisionEnabled) == "function" then
                Mesh:SetCollisionEnabled(0) -- ECollisionEnabled::NoCollision
            end
            Mesh:SetVisibility(false, true)
        end

        -- 2. Spawn Crystal Polygon Burst (SAO Shatter Effect)
        local NiagaraFunc = StaticFindObject("/Script/Niagara.Default__NiagaraFunctionLibrary")
        local NiagaraAsset = FindFirstValidAsset(CandidateParticles)

        if NiagaraFunc and NiagaraFunc:IsValid() and NiagaraAsset and NiagaraAsset:IsValid() and World then
            NiagaraFunc:SpawnSystemAtLocation(World, NiagaraAsset, Location, Rotation, { X=2.0, Y=2.0, Z=2.0 }, true, true, 0, true)
        else
            local PalUtil = StaticFindObject("/Script/Pal.Default__PalUtility")
            if PalUtil and PalUtil:IsValid() and type(PalUtil.PlayEffectAtLocation) == "function" then
                PalUtil:PlayEffectAtLocation(World, Location, Rotation)
            end
        end

        -- 3. Play Glass / Crystal Shatter Sound
        local SoundAsset = FindFirstValidAsset(CandidateSounds)
        local GameplayStatics = StaticFindObject("/Script/Engine.Default__GameplayStatics")
        if GameplayStatics and GameplayStatics:IsValid() and SoundAsset and SoundAsset:IsValid() and World then
            GameplayStatics:PlaySoundAtLocation(World, SoundAsset, Location, 1.2, 1.0, 0.0, nil, nil, nil)
        end
    end)
end

local function RestoreCharacter(Character)
    pcall(function()
        if not Character or not Character:IsValid() then return end
        RecentlyHandled[Character] = nil
        local state = OriginalState[Character] or {}
        Character:SetActorEnableCollision(state.actorCollision ~= false)
        local Mesh = Character.Mesh
        if Mesh and Mesh:IsValid() then
            Mesh:SetVisibility(true, true)
            if type(Mesh.SetCollisionEnabled) == "function" then Mesh:SetCollisionEnabled(state.meshCollision or 1) end
            if type(Mesh.SetSimulatePhysics) == "function" then Mesh:SetSimulatePhysics(state.meshPhysics == true) end
        end
        OriginalState[Character] = nil
    end)
end

function SAODeath.Init()
    -- Universal death hooks covering Wild Pals, Bosses, Human NPCs, and Players
    local deathHooks = {
        "/Script/Pal.PalCharacter:OnDead",
        "/Script/Pal.PalMonsterCharacter:OnDead",
        "/Script/Pal.PalPlayerCharacter:OnDead",
        "/Script/Pal.PalNPC:OnDead"
    }

    for _, hookName in ipairs(deathHooks) do
        pcall(RegisterHook, hookName, function(Context, DeadCharacter)
            local char = Context and Context.get and Context:get() or Context
            HandleSAODeath(char)
        end)
    end

    -- Hook Ragdoll Component to prevent it from ever turning on physical ragdolls
    pcall(RegisterHook, "/Script/Pal.PalDeadRagdollComponent:Activate", function(Context)
        pcall(function()
            local comp = Context and Context.get and Context:get() or Context
            if comp and comp:IsValid() then
                comp.bEnablePhysics = false
                local owner = comp:GetOwner()
                if owner and owner:IsValid() then
                    HandleSAODeath(owner)
                end
            end
        end)
    end)

    pcall(RegisterHook, "/Script/Pal.PalCharacter:OnRevive", function(Context)
        RestoreCharacter(Context and Context.get and Context:get() or Context)
    end)
    pcall(RegisterHook, "/Script/Engine.PlayerController:ClientRestart", function(Context, NewPawn)
        RestoreCharacter(NewPawn and NewPawn.get and NewPawn:get() or NewPawn)
    end)

    print("[WorldBossAuraSystem] Universal SAO Death Disintegration initialized (Pals, NPCs, and Players).")
end

return SAODeath
