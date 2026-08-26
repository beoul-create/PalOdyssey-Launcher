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
            local engine = UEHelpers.GetEngine()
            if engine and engine:IsValid() and engine:GetFullName():find("Server") then
                isServer = true
            end
        end
    end)
    return isServer
end

local function LoadOrFindObject(path, className)
    local obj = nil
    pcall(function()
        obj = StaticFindObject(path)
        if (not obj or not obj:IsValid()) and StaticLoadObject then
            local uclass = className and StaticFindObject(className) or StaticFindObject("/Script/CoreUObject.Class")
            obj = StaticLoadObject(uclass, nil, path, nil, 0, nil, false)
        end
    end)
    return obj
end

local function ResolveAssets()
    pcall(function()
        NiagaraFunctionLibrary = StaticFindObject("/Script/Niagara.Default__NiagaraFunctionLibrary")
        GameplayStatics = StaticFindObject("/Script/Engine.Default__GameplayStatics")
        
        -- 1. Primary SAO Cooked Package Assets
        SAONiagaraSystem = LoadOrFindObject("/Game/Mods/SAODeath/NS_SAODeath.NS_SAODeath", "/Script/Niagara.NiagaraSystem")
        SAOSoundCue = LoadOrFindObject("/Game/Mods/SAODeath/A_SAODeathShatter.A_SAODeathShatter", "/Script/Engine.SoundCue")

        -- 2. Fallbacks to native high-visibility crystal/burst systems if cooked pak is mounting
        if not SAONiagaraSystem or not SAONiagaraSystem:IsValid() then
            local fallbacks = {
                "/Game/Pal/Effect/Common/Niagara/NS_Common_Hit_01.NS_Common_Hit_01",
                "/Game/Pal/Effect/Skill/Unique/NS_Burst_Cyan.NS_Burst_Cyan",
                "/Game/Pal/FX/Common/Death/NS_PalDeath_Default.NS_PalDeath_Default",
                "/Game/Pal/Effect/Common/Niagara/NS_Item_Drop_Rare.NS_Item_Drop_Rare"
            }
            for _, fb in ipairs(fallbacks) do
                local candidate = LoadOrFindObject(fb, "/Script/Niagara.NiagaraSystem")
                if candidate and candidate:IsValid() then
                    SAONiagaraSystem = candidate
                    break
                end
            end
        end

        if not SAOSoundCue or not SAOSoundCue:IsValid() then
            local soundFallbacks = {
                "/Game/Pal/Sound/Common/Cue/SE_Pal_Common_Death.SE_Pal_Common_Death",
                "/Game/Pal/Sound/Common/Cue/SE_Pal_Capture_Success.SE_Pal_Capture_Success",
                "/Game/Pal/Sound/Common/Cue/SE_Common_Hit_Critical.SE_Common_Hit_Critical"
            }
            for _, fb in ipairs(soundFallbacks) do
                local candidate = LoadOrFindObject(fb, "/Script/Engine.SoundBase")
                if candidate and candidate:IsValid() then
                    SAOSoundCue = candidate
                    break
                end
            end
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
            local comp = NiagaraFunctionLibrary:SpawnSystemAtLocation(
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

            -- Inject Vibrant SAO Cyan Emissive Parameters (#00F0FF / RGB: 0, 240, 255)
            if comp and comp:IsValid() then
                pcall(function()
                    local cyanColor = { R = 0.0, G = 0.94, B = 1.0, A = 1.0 }
                    local emissiveColor = { R = 0.0, G = 3.5, B = 4.0, A = 1.0 }
                    
                    if comp.SetColorParameter then
                        comp:SetColorParameter("Color", cyanColor)
                        comp:SetColorParameter("User.Color", cyanColor)
                        comp:SetColorParameter("User.EmissiveColor", emissiveColor)
                    end
                    if comp.SetVectorParameter then
                        comp:SetVectorParameter("User.Scale", scale)
                    end
                    if comp.SetFloatParameter then
                        comp:SetFloatParameter("User.SpawnRate", Config.particleCount or 80.0)
                        comp:SetFloatParameter("User.Lifetime", 1.4)
                        comp:SetFloatParameter("User.Velocity", 300.0)
                    end
                end)
            end

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

                -- 2. Instant Mesh Visibility Cull (with fallback shimmer)
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
