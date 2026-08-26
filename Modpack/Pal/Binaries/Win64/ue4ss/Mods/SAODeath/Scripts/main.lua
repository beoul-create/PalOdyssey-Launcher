-- ============================================================================
-- SAODeath: Sword Art Online Polygon-Shatter Death Effect Mod for Palworld
-- Replaces vanilla ragdoll physics across all characters (Players, Pals, NPCs)
-- with an instant crystalline polygon burst, zero CPU physics overhead, and clean GC.
-- ============================================================================

local ok, Config = pcall(require, "config")
if not ok or type(Config) ~= "table" then
    Config = {
        enabled = true,
        soundVolume = 1.0,
        particleScale = 1.0,
        particleCount = 80,
        suppressRagdollPhysics = true,
        instantMeshHide = true,
        cleanupDelayMs = 150,
        enablePlayerDeathEffect = true,
        enablePalDeathEffect = true,
        enableNpcDeathEffect = true,
        log = true
    }
end

local function Log(msg)
    if Config.log then
        print(string.format("[SAODeath] %s\n", tostring(msg)))
    end
end

if not Config.enabled then return end

print("==========================================================")
print("  SAODeath: Sword Art Online Polygon Shatter Engine Active")
print("==========================================================")

-- Cached Object References
local NiagaraFunctionLibrary = nil
local GameplayStatics = nil
local SAONiagaraSystem = nil
local SAOSoundCue = nil
local processedDeaths = {}

local function IsDedicatedServer()
    local isServer = false
    pcall(function()
        local player = GetPlayerController()
        if not player or not player:IsValid() then
            -- Check if running headless
            local engine = UEHelpers.GetEngine()
            if engine and engine:IsValid() and engine:GetFullName():find("Server") then
                isServer = true
            end
        end
    end)
    return isServer
end

local function ResolveAssets()
    pcall(function()
        NiagaraFunctionLibrary = StaticFindObject("/Script/Niagara.Default__NiagaraFunctionLibrary")
        GameplayStatics = StaticFindObject("/Script/Engine.Default__GameplayStatics")
        
        -- Primary SAO Cooked Package Assets
        SAONiagaraSystem = StaticFindObject("/Game/Mods/SAODeath/NS_SAODeath.NS_SAODeath")
        SAOSoundCue = StaticFindObject("/Game/Mods/SAODeath/A_SAODeathShatter.A_SAODeathShatter")

        -- Fallbacks if cooked pak is loaded dynamically or in dev
        if not SAONiagaraSystem or not SAONiagaraSystem:IsValid() then
            SAONiagaraSystem = StaticFindObject("/Game/Pal/FX/Common/Death/NS_PalDeath_Default.NS_PalDeath_Default")
        end
        if not SAOSoundCue or not SAOSoundCue:IsValid() then
            SAOSoundCue = StaticFindObject("/Game/Pal/Sound/Common/Cue/SE_Pal_Common_Death.SE_Pal_Common_Death")
        end
    end)
end

local function SpawnShatterVFX(world, location, rotation)
    if IsDedicatedServer() then return end
    if not world or not world:IsValid() or not location then return end

    pcall(function()
        if not NiagaraFunctionLibrary or not NiagaraFunctionLibrary:IsValid() then
            NiagaraFunctionLibrary = StaticFindObject("/Script/Niagara.Default__NiagaraFunctionLibrary")
        end
        if not SAONiagaraSystem or not SAONiagaraSystem:IsValid() then
            ResolveAssets()
        end

        local scale = { X = Config.particleScale or 1.0, Y = Config.particleScale or 1.0, Z = Config.particleScale or 1.0 }

        if NiagaraFunctionLibrary and NiagaraFunctionLibrary:IsValid() and SAONiagaraSystem and SAONiagaraSystem:IsValid() then
            NiagaraFunctionLibrary:SpawnSystemAtLocation(
                world,
                SAONiagaraSystem,
                location,
                rotation or { Pitch = 0, Yaw = 0, Roll = 0 },
                scale,
                true,   -- bAutoDestroy
                true,   -- bAutoActivate
                0,      -- PoolingMethod: None
                true    -- bPreCullCheck
            )
            Log(string.format("Spawned SAO Polygon Shatter Niagara burst at (X:%.1f, Y:%.1f, Z:%.1f)", location.X or 0, location.Y or 0, location.Z or 0))
        end

        -- Trigger Audio Shatter Cue
        if not GameplayStatics or not GameplayStatics:IsValid() then
            GameplayStatics = StaticFindObject("/Script/Engine.Default__GameplayStatics")
        end
        if GameplayStatics and GameplayStatics:IsValid() and SAOSoundCue and SAOSoundCue:IsValid() then
            GameplayStatics:PlaySoundAtLocation(
                world,
                SAOSoundCue,
                location,
                Config.soundVolume or 1.0,
                1.0,    -- PitchMultiplier
                0.0,    -- StartTime
                nil,    -- AttenuationSettings
                nil     -- ConcurrencySettings
            )
        end
    end)
end

local function HandleCharacterDeath(character)
    if not character or not character:IsValid() then return end
    local ptrKey = tostring(character:GetAddress())
    if processedDeaths[ptrKey] then return end
    processedDeaths[ptrKey] = true

    pcall(function()
        local name = character:GetFullName()
        local world = character:GetWorld()
        local loc = character:K2_GetActorLocation()
        local rot = character:K2_GetActorRotation()

        Log(string.format("Executing SAO Polygon Shatter for dying actor: %s", name))

        -- 1. Suppress Ragdoll Physics & Disable Actor Collision
        if Config.suppressRagdollPhysics then
            character:SetActorEnableCollision(false)

            -- Disable ragdoll component if present
            local ragdollComp = character.DeadRagdollComponent or character:GetComponentByClass(StaticFindObject("/Script/Pal.PalDeadRagdollComponent"))
            if ragdollComp and ragdollComp:IsValid() then
                ragdollComp.bEnableRagdoll = false
                ragdollComp.bIsRagdoll = false
            end

            -- Suppress skeletal mesh physics
            local mesh = character.Mesh or character:GetComponentByClass(StaticFindObject("/Script/Engine.SkeletalMeshComponent"))
            if mesh and mesh:IsValid() then
                mesh:SetSimulatePhysics(false)
                mesh:SetEnableGravity(false)
                mesh:SetCollisionProfileName("NoCollision", false)

                -- 2. Instant Mesh Visibility Cull
                if Config.instantMeshHide then
                    mesh:SetVisibility(false, true)
                end
            end
        end

        -- 3. Spawn SAO Polygon Burst & Glass Shatter Audio
        SpawnShatterVFX(world, loc, rot)

        -- 4. Clean Actor Garbage Collection (Delay 150ms to allow item drops to complete)
        local cleanupDelay = Config.cleanupDelayMs or 150
        ExecuteWithDelay(cleanupDelay, function()
            pcall(function()
                if character and character:IsValid() then
                    character:K2_DestroyActor()
                    Log(string.format("Cleanly purged dead actor handle %s (Address: %s) from memory.", name, ptrKey))
                end
                processedDeaths[ptrKey] = nil
            end)
        end)
    end)
end

-- ============================================================================
-- HOOKS: Intercept Universal Death and Ragdoll Triggers
-- ============================================================================

-- 1. Hook APalCharacter:OnDead
pcall(function()
    RegisterHook("/Script/Pal.PalCharacter:OnDead", function(Context)
        local char = Context:get()
        if char and char:IsValid() then
            HandleCharacterDeath(char)
        end
    end)
end)

-- 2. Intercept PalDeadRagdollComponent:SetupRagdoll to block Chaos physics
pcall(function()
    RegisterHook("/Script/Pal.PalDeadRagdollComponent:SetupRagdoll", function(Context)
        local comp = Context:get()
        if comp and comp:IsValid() and Config.suppressRagdollPhysics then
            comp.bEnableRagdoll = false
            comp.bIsRagdoll = false
            local owner = comp:GetOwner()
            if owner and owner:IsValid() then
                HandleCharacterDeath(owner)
            end
        end
    end)
end)

-- 3. Hook PalDamageSubsystem:OnDead (Broad Event Catch)
pcall(function()
    RegisterHook("/Script/Pal.PalDamageSubsystem:OnDead", function(Context, DeadActor)
        local actor = DeadActor and DeadActor:get()
        if actor and actor:IsValid() then
            HandleCharacterDeath(actor)
        end
    end)
end)

-- Initial asset resolution
ExecuteWithDelay(3000, ResolveAssets)

Log("SAODeath mod fully loaded & listening for character deaths.")
