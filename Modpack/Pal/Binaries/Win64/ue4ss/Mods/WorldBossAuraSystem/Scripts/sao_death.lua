local SAODeath = {}

local NS_SAODeathPath = "/Game/Mods/SAODeath/NS_SAODeath.NS_SAODeath"
local A_SAOSoundPath = "/Game/Mods/SAODeath/A_SAODeathShatter.A_SAODeathShatter"

function SAODeath.Init()
    -- Universal death hook on character damage resolution
    RegisterHook("/Script/Pal.PalCharacter:OnDead", function(Context, DeadCharacter)
        local Character = Context:get()
        if not Character or not Character:IsValid() then return end

        local Mesh = Character.Mesh
        local World = Character:GetWorld()
        local Location = Character:K2_GetActorLocation()
        local Rotation = Character:K2_GetActorRotation()

        -- 1. Disable Actor Collision & Ragdoll Physics
        Character:SetActorEnableCollision(false)
        if Character.PalDeadRagdollComponent and Character.PalDeadRagdollComponent:IsValid() then
            Character.PalDeadRagdollComponent.bEnablePhysics = false
        end

        -- 2. Spawn SAO Particle System & Shatter Sound
        local NiagaraFunc = StaticFindObject("/Script/Niagara.NiagaraFunctionLibrary")
        local NiagaraAsset = StaticFindObject(NS_SAODeathPath)
        if NiagaraFunc:IsValid() and NiagaraAsset:IsValid() then
            NiagaraFunc:SpawnSystemAtLocation(World, NiagaraAsset, Location, Rotation, { X=1, Y=1, Z=1 }, true, true, 0, true)
        end

        local GameplayStatics = StaticFindObject("/Script/Engine.GameplayStatics")
        local SoundAsset = StaticFindObject(A_SAOSoundPath)
        if GameplayStatics:IsValid() and SoundAsset:IsValid() then
            GameplayStatics:PlaySoundAtLocation(World, SoundAsset, Location, 1.0, 1.0, 0.0, nil, nil, nil)
        end

        -- 3. Hide Skeletal Mesh Immediately
        if Mesh and Mesh:IsValid() then
            Mesh:SetVisibility(false, true)
        end

        -- 4. Queue actor cleanup after a slight tick delay to let loot drop routines resolve
        ExecuteWithDelay(150, function()
            if Character and Character:IsValid() then
                Character:K2_DestroyActor()
            end
        end)
    end)
end

return SAODeath
