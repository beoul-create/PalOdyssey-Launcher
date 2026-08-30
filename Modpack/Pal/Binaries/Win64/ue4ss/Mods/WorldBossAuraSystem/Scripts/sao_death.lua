local SAODeath = {}

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
        if obj and obj:IsValid() then
            return obj
        end
    end
    return nil
end

function SAODeath.Init()
    -- Hook character death for SAO polygon crystal shatter effect
    pcall(RegisterHook, "/Script/Pal.PalCharacter:OnDead", function(Context, DeadCharacter)
        pcall(function()
            local Character = Context and Context.get and Context:get() or Context
            if not Character or not Character:IsValid() then return end

            local Location = Character:K2_GetActorLocation()
            local Rotation = Character:K2_GetActorRotation()
            local World = Character:GetWorld()

            -- 1. Disable Ragdoll & Collision so character doesn't flop as a physical corpse
            Character:SetActorEnableCollision(false)
            if Character.PalDeadRagdollComponent and Character.PalDeadRagdollComponent:IsValid() then
                Character.PalDeadRagdollComponent.bEnablePhysics = false
            end

            -- 2. Spawn Crystal Polygon Burst (SAO Shatter Effect)
            local NiagaraFunc = StaticFindObject("/Script/Niagara.Default__NiagaraFunctionLibrary")
            local NiagaraAsset = FindFirstValidAsset(CandidateParticles)

            if NiagaraFunc and NiagaraFunc:IsValid() and NiagaraAsset and NiagaraAsset:IsValid() and World then
                NiagaraFunc:SpawnSystemAtLocation(World, NiagaraAsset, Location, Rotation, { X=2.0, Y=2.0, Z=2.0 }, true, true, 0, true)
            else
                -- Fallback via PalUtility effect spawner
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

            -- 4. Hide Mesh and Dissolve safely
            local Mesh = Character.Mesh
            if Mesh and Mesh:IsValid() then
                Mesh:SetVisibility(false, true)
            end
        end)
    end)
    print("[WorldBossAuraSystem] SAO Death Disintegration effect initialized.")
end

return SAODeath
