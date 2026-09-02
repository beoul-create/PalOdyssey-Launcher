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

local ActiveSoulFlames = setmetatable({}, { __mode = "k" })

local function IsBaseCampPal(Character)
    local isBase = false
    pcall(function()
        if not Character or not Character:IsValid() then return end
        local param = Character.CharacterParameterComponent
        if param and param:IsValid() then
            if type(param.GetAssignedBaseCamp) == "function" then
                local base = param:GetAssignedBaseCamp()
                if base and base:IsValid() then isBase = true return end
            end
            if type(param.IsBaseCampPal) == "function" and param:IsBaseCampPal() then
                isBase = true return
            end
        end
        local ind = (type(Character.GetIndividualParameter) == "function" and Character:GetIndividualParameter())
        if ind and ind:IsValid() then
            if type(ind.GetSlotID) == "function" then
                local slot = ind:GetSlotID()
                if slot and tostring(slot):find("Base") then isBase = true return end
            end
        end
    end)
    return isBase
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

        -- BASE CAMP PAL SPECIAL HANDLING: Floating Soul Flame!
        if IsBaseCampPal(Character) then
            local Mesh = Character.Mesh or (type(Character.GetMesh) == "function" and Character:GetMesh())
            if Mesh and Mesh:IsValid() then
                local AnimInstance = Mesh:GetAnimInstance()
                if AnimInstance and AnimInstance:IsValid() and type(AnimInstance.Montage_Stop) == "function" then
                    AnimInstance:Montage_Stop(0.0)
                end
                if type(Mesh.SetSimulatePhysics) == "function" then Mesh:SetSimulatePhysics(false) end
                if type(Mesh.SetCollisionEnabled) == "function" then Mesh:SetCollisionEnabled(0) end
                Mesh:SetVisibility(false, true)
            end

            -- Suppress child mesh attachments
            local skelClass = StaticFindObject("/Script/Engine.SkeletalMeshComponent")
            if skelClass and type(Character.K2_GetComponentsByClass) == "function" then
                for _, comp in ipairs(Character:K2_GetComponentsByClass(skelClass) or {}) do
                    if comp and comp:IsValid() and comp ~= Mesh then
                        comp:SetVisibility(false, true)
                    end
                end
            end

            -- IMPORTANT: Preserve Actor and Collision so other Base Pals can pick up and carry the soul flame!
            Character:SetActorEnableCollision(true)

            -- Spawn & Attach Floating Soul Flame Particle
            if not ActiveSoulFlames[Character] then
                local NiagaraFunc = StaticFindObject("/Script/Niagara.Default__NiagaraFunctionLibrary")
                local SoulFlameParticles = {
                    "/Game/Pal/Effect/Niagara/Common/NS_Status_Fire.NS_Status_Fire",
                    "/Game/Pal/Effect/Niagara/Common/NS_Status_Electric.NS_Status_Electric",
                    "/Game/Pal/Effect/Niagara/Common/NS_Status_Dark.NS_Status_Dark"
                }
                local FlameAsset = FindFirstValidAsset(SoulFlameParticles)
                local RootComp = Character:K2_GetRootComponent() or Character.RootComponent or Mesh
                if NiagaraFunc and NiagaraFunc:IsValid() and FlameAsset and FlameAsset:IsValid() and RootComp then
                    local soulEmitter = NiagaraFunc:SpawnSystemAttached(
                        FlameAsset,
                        RootComp,
                        FName("pelvis"),
                        { X = 0, Y = 0, Z = 40 },
                        { Pitch = 0, Yaw = 0, Roll = 0 },
                        1, -- EAttachLocation::KeepRelativeOffset
                        true, true, 0, true
                    )
                    ActiveSoulFlames[Character] = soulEmitter
                end
            end
            return
        end

        -- 1. Disable Actor Collision & Suppress Ragdoll Physics across all components
        local Mesh = Character.Mesh or (type(Character.GetMesh) == "function" and Character:GetMesh())
        local state = { actorCollision = true, meshCollision = 1, meshPhysics = false }
        pcall(function() state.actorCollision = Character:GetActorEnableCollision() end)
        pcall(function() if Mesh then state.meshCollision = Mesh:GetCollisionEnabled() end end)
        pcall(function() if Mesh then state.meshPhysics = Mesh:IsSimulatingPhysics() end end)
        OriginalState[Character] = state

        -- Stop Actor Collision (Do NOT hide actor as it reveals debug primitives like Arrow/Capsule)
        Character:SetActorEnableCollision(false)

        -- Suppress Ragdoll Component
        if Character.PalDeadRagdollComponent and Character.PalDeadRagdollComponent:IsValid() then
            Character.PalDeadRagdollComponent.bEnablePhysics = false
            if type(Character.PalDeadRagdollComponent.Deactivate) == "function" then
                Character.PalDeadRagdollComponent:Deactivate()
            end
        end

        -- Suppress Primary Mesh
        if Mesh and Mesh:IsValid() then
            -- A. Stop active death animation / collapse montage
            pcall(function()
                local AnimInstance = Mesh:GetAnimInstance()
                if AnimInstance and AnimInstance:IsValid() and type(AnimInstance.Montage_Stop) == "function" then
                    AnimInstance:Montage_Stop(0.0)
                end
            end)

            -- B. Stop physics calculations and cut collision
            if type(Mesh.SetSimulatePhysics) == "function" then
                Mesh:SetSimulatePhysics(false)
            end
            if type(Mesh.SetCollisionEnabled) == "function" then
                Mesh:SetCollisionEnabled(0) -- ECollisionEnabled::NoCollision
            end

            -- C. Hide Mesh instantly propagating to all attached equipment/props
            Mesh:SetVisibility(false, true)
        end

        -- Suppress all attached child Skeletal Mesh components (Hair, Armor, Saddles, Weapons)
        pcall(function()
            local skelClass = StaticFindObject("/Script/Engine.SkeletalMeshComponent")
            if skelClass and type(Character.K2_GetComponentsByClass) == "function" then
                local components = Character:K2_GetComponentsByClass(skelClass) or {}
                for _, comp in ipairs(components) do
                    if comp and comp:IsValid() then
                        if type(comp.SetSimulatePhysics) == "function" then comp:SetSimulatePhysics(false) end
                        if type(comp.SetCollisionEnabled) == "function" then comp:SetCollisionEnabled(0) end
                        comp:SetVisibility(false, true)
                    end
                end
            end
        end)

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

        -- Extinguish Soul Flame if active on Base Pal
        if ActiveSoulFlames[Character] then
            pcall(function()
                local emitter = ActiveSoulFlames[Character]
                if emitter and emitter:IsValid() and type(emitter.Deactivate) == "function" then
                    emitter:Deactivate()
                end
            end)
            ActiveSoulFlames[Character] = nil
        end

        local state = OriginalState[Character] or {}
        Character:SetActorEnableCollision(state.actorCollision ~= false)
        local Mesh = Character.Mesh or (type(Character.GetMesh) == "function" and Character:GetMesh())
        if Mesh and Mesh:IsValid() then
            Mesh:SetVisibility(true, true)
            if type(Mesh.SetCollisionEnabled) == "function" then Mesh:SetCollisionEnabled(state.meshCollision or 1) end
            if type(Mesh.SetSimulatePhysics) == "function" then Mesh:SetSimulatePhysics(state.meshPhysics == true) end
        end

        -- Recursively ensure all debug/editor collision primitives (ArrowComponent, SphereComponent, CapsuleComponent, etc.) are strictly hidden
        pcall(function()
            local function HideIfDebug(comp)
                if not comp or not comp:IsValid() then return end
                local cName = tostring(comp:GetClass():GetName())
                if cName:find("Arrow") or cName:find("Sphere") or cName:find("Capsule") or cName:find("Box") or cName:find("Frustum") or cName:find("Spline") or cName:find("Debug") then
                    pcall(function() comp:SetHiddenInGame(true, true) end)
                    pcall(function() comp:SetVisibility(false, true) end)
                end
            end

            -- 1. Actor components
            local compClass = StaticFindObject("/Script/Engine.ActorComponent")
            if compClass and type(Character.GetComponentsByClass) == "function" then
                for _, comp in ipairs(Character:GetComponentsByClass(compClass) or {}) do
                    HideIfDebug(comp)
                end
            end

            -- 2. Mesh child components
            if Mesh and Mesh:IsValid() and type(Mesh.GetChildrenComponents) == "function" then
                for _, child in ipairs(Mesh:GetChildrenComponents(true) or {}) do
                    HideIfDebug(child)
                end
            end

            -- 3. RootComponent child components
            local root = Character:K2_GetRootComponent() or Character.RootComponent
            if root and root:IsValid() and type(root.GetChildrenComponents) == "function" then
                for _, child in ipairs(root:GetChildrenComponents(true) or {}) do
                    HideIfDebug(child)
                end
            end
        end)
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

    -- Hooks to restore/revive characters and extinguish soul flames when placed on bed or revived
    pcall(RegisterHook, "/Script/Pal.PalCharacter:OnRevive", function(Context)
        RestoreCharacter(Context and Context.get and Context:get() or Context)
    end)
    pcall(RegisterHook, "/Script/Pal.PalCharacter:OnSleeping", function(Context)
        RestoreCharacter(Context and Context.get and Context:get() or Context)
    end)
    pcall(RegisterHook, "/Script/Pal.PalCharacterParameterComponent:OnUpdateHP", function(Context, PrevHP, NowHP)
        pcall(function()
            local nowVal = NowHP and NowHP.get and NowHP:get() or NowHP
            if type(nowVal) == "number" and nowVal > 0 then
                local comp = Context and Context.get and Context:get() or Context
                if comp and comp:IsValid() and comp.GetOwner then
                    RestoreCharacter(comp:GetOwner())
                end
            end
        end)
    end)
    pcall(RegisterHook, "/Script/Engine.PlayerController:ClientRestart", function(Context, NewPawn)
        RestoreCharacter(NewPawn and NewPawn.get and NewPawn:get() or NewPawn)
    end)

    print("[WorldBossAuraSystem] Universal SAO Death Disintegration & Base Pal Soul Flames initialized.")
end

return SAODeath
