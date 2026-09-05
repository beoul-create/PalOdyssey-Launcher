local AuraSystem = {}
local Performance = require("performance")

local Config = {}
local ResolvedAssets = {}
local AttachedAuras = {}

local AuraMap = {
    ["Fiery"] = {
        "/Game/Pal/Effect/Niagara/Common/NS_Burn_01.NS_Burn_01",
        "/Game/Pal/Effect/Niagara/Common/NS_Status_Fire.NS_Status_Fire",
        "/Game/Pal/Effect/Niagara/Skill/Fire/NS_Skill_Fire_Breath_01.NS_Skill_Fire_Breath_01"
    },
    ["Glacial"] = {
        "/Game/Pal/Effect/Niagara/Common/NS_Status_Freeze.NS_Status_Freeze",
        "/Game/Pal/Effect/Niagara/Common/NS_Status_Ice.NS_Status_Ice",
        "/Game/Pal/Effect/Niagara/Skill/Ice/NS_Skill_Ice_Breath_01.NS_Skill_Ice_Breath_01"
    },
    ["Celestial"] = {
        "/Game/Pal/Effect/Niagara/Common/NS_Status_Electric.NS_Status_Electric",
        "/Game/Pal/Effect/Niagara/Skill/Thunder/NS_Skill_Thunder_ThunderStorm_01.NS_Skill_Thunder_ThunderStorm_01"
    },
    ["Corrupted"] = {
        "/Game/Pal/Effect/Niagara/Common/NS_Status_Dark.NS_Status_Dark",
        "/Game/Pal/Effect/Niagara/Skill/Dark/NS_Skill_Dark_Laser_01.NS_Skill_Dark_Laser_01"
    },
    ["Verdant"] = {
        "/Game/Pal/Effect/Niagara/Common/NS_Status_Poison.NS_Status_Poison",
        "/Game/Pal/Effect/Niagara/Common/NS_Status_Vine.NS_Status_Vine",
        "/Game/Pal/Effect/Niagara/Skill/Grass/NS_Skill_Grass_SeedMine_01.NS_Skill_Grass_SeedMine_01"
    },
    ["Tidal"] = {
        "/Game/Pal/Effect/Niagara/Common/NS_Status_Water.NS_Status_Water",
        "/Game/Pal/Effect/Niagara/Common/NS_Status_Wet.NS_Status_Wet",
        "/Game/Pal/Effect/Niagara/Skill/Water/NS_Skill_Water_Breath_01.NS_Skill_Water_Breath_01"
    },
    ["Draconic"] = {
        "/Game/Pal/Effect/Niagara/Skill/Dragon/NS_Skill_Dragon_Breath_01.NS_Skill_Dragon_Breath_01",
        "/Game/Pal/Effect/Niagara/Skill/Dragon/NS_Skill_Dragon_Ball_01.NS_Skill_Dragon_Ball_01"
    },
    ["Radiant"] = {
        "/Game/Pal/Effect/Niagara/Common/NS_LevelUp_01.NS_LevelUp_01",
        "/Game/Pal/Effect/Niagara/Common/NS_Capture_Success.NS_Capture_Success",
        "/Game/Pal/Effect/Niagara/Common/NS_Pal_Revive.NS_Pal_Revive"
    },
    ["Transmigrator"] = {
        "/Game/Pal/Effect/Niagara/Common/NS_Pal_Vanish.NS_Pal_Vanish",
        "/Game/Pal/Effect/Niagara/Skill/Dark/NS_Skill_Dark_Laser_01.NS_Skill_Dark_Laser_01",
        "/Game/Pal/Effect/Niagara/Common/NS_Capture_Success.NS_Capture_Success"
    },
    ["Regressor"] = {
        "/Game/Pal/Effect/Niagara/Common/NS_LevelUp_01.NS_LevelUp_01",
        "/Game/Pal/Effect/Niagara/Common/NS_Common_Hit_Critical.NS_Common_Hit_Critical",
        "/Game/Pal/Effect/Niagara/Common/NS_Status_Fire.NS_Status_Fire"
    }
}

local AuraMetadata = {
    ["Fiery"] = { Passive = "FlameEmperor", Color = 16724736, Desc = "Infused with raging inferno flames (+20% Fire Damage)" },
    ["Glacial"] = { Passive = "IceEmperor", Color = 52479, Desc = "Sheathed in sub-zero frozen mist (+20% Ice Damage)" },
    ["Celestial"] = { Passive = "ThunderEmperor", Color = 16766720, Desc = "Crackling with thunderstorm voltage (+20% Lightning Damage)" },
    ["Corrupted"] = { Passive = "LordOfTheUnderworld", Color = 8388736, Desc = "Swirling with abyssal shadow miasma (+20% Dark Damage)" },
    ["Verdant"] = { Passive = "SpiritEmperor", Color = 3066993, Desc = "Blooming with primal flora essence (+20% Grass Damage)" },
    ["Tidal"] = { Passive = "LordOfSea", Color = 2003199, Desc = "Surging with high-pressure ocean currents (+20% Water Damage)" },
    ["Draconic"] = { Passive = "DivineDragon", Color = 15277667, Desc = "Empowered by ancient dragon majesty (+20% Dragon Damage)" },
    ["Radiant"] = { Passive = "Legend", Color = 15844367, Desc = "Blessed by divine celestial light (+20% Atk, +20% Def, +15% Speed)" },
    ["Transmigrator"] = {
        Passive = "Passive_Transmigrator",
        SecondaryPassives = { "Swift", "Runner" },
        Color = 10840509,
        Desc = "🌌 Transcends dimensional boundaries: Unlimited Level Cap & 2x Movement Speed!"
    },
    ["Regressor"] = {
        Passive = "Passive_Regressor",
        SecondaryPassives = { "Passive_Regressor_Cooldown", "CoolTimeReduction_Up_1", "CoolTimeReduction_Up_2" },
        Color = 16718105,
        Desc = "⏳ Relives infinite temporal loops: 4x Stats & 100% Skill Cooldown Reduction!"
    }
}

function AuraSystem.GetMetadata(auraType)
    return AuraMetadata[auraType] or AuraMetadata["Fiery"]
end

function AuraSystem.GetAllAuras()
    return { "Fiery", "Glacial", "Celestial", "Corrupted", "Verdant", "Tidal", "Draconic", "Radiant", "Transmigrator", "Regressor" }
end

function AuraSystem.LoadConfig(config)
    Config = config or {}
end

local function GetCharacterKey(character)
    if not character then return nil end
    local key = nil
    pcall(function()
        if type(character.get_address) == "function" then
            key = tostring(character:get_address())
        elseif type(character.GetAddress) == "function" then
            key = tostring(character:GetAddress())
        end
    end)
    return key
end

local function FindValidAura(auraType)
    local cached = ResolvedAssets[auraType]
    if cached and cached:IsValid() then
        Performance.Count("aura_asset_cache_hits")
        return cached
    end

    local list = AuraMap[auraType] or AuraMap["Fiery"]
    for _, path in ipairs(list) do
        local obj = StaticFindObject(path)
        if (not obj or not obj:IsValid()) and type(LoadAsset) == "function" then
            local loadStartedAt = Performance.Start()
            local ok, loaded = pcall(LoadAsset, path)
            Performance.Finish("aura_asset_load", loadStartedAt, ok and loaded ~= nil)
            Performance.Count(ok and loaded and "aura_asset_load_successes" or "aura_asset_load_failures")
            if ok then obj = loaded end
        end
        if obj and obj:IsValid() then
            ResolvedAssets[auraType] = obj
            return obj
        end
    end
    return nil
end

function AuraSystem.Attach(Character, AuraType)
    if Config.EnableVisualAuras == false then return nil end
    local startedAt = Performance.Start()
    local attached = nil
    local ok = pcall(function()
        if not Character or not Character:IsValid() then return nil end
        local Mesh = Character.Mesh
        if not Mesh or not Mesh:IsValid() then return nil end

        local key = GetCharacterKey(Character)
        local existing = key and AttachedAuras[key] or nil
        if existing and existing:IsValid() then
            Performance.Count("aura_duplicate_attach_prevented")
            attached = existing
            return
        end

        local NiagaraAsset = FindValidAura(AuraType)
        local NiagaraFunc = StaticFindObject("/Script/Niagara.Default__NiagaraFunctionLibrary")

        if NiagaraFunc and NiagaraFunc:IsValid() and NiagaraAsset and NiagaraAsset:IsValid() then
            attached = NiagaraFunc:SpawnSystemAttached(
                NiagaraAsset,
                Mesh,
                FName("pelvis"),
                { X = 0, Y = 0, Z = 0 },
                { Pitch = 0, Yaw = 0, Roll = 0 },
                1, -- EAttachLocation::KeepRelativeOffset
                true, true, 0, true
            )
            if key and attached and attached:IsValid() then
                AttachedAuras[key] = attached
            end
        end
    end)
    Performance.Finish("aura_attach", startedAt, ok and attached ~= nil)
    return attached
end

function AuraSystem.WarmUp(schedule)
    if Config.AuraWarmupEnabled ~= true then return end
    local auraTypes = AuraSystem.GetAllAuras()
    local index = 1
    local function LoadNext()
        local auraType = auraTypes[index]
        if not auraType then
            print("[WorldBossAuraSystem] Aura asset warm-up completed.")
            return
        end
        FindValidAura(auraType)
        index = index + 1
        if type(schedule) == "function" then schedule(1000, LoadNext) else LoadNext() end
    end
    LoadNext()
end

function AuraSystem.Detach(Character, Component)
    local startedAt = Performance.Start()
    local key = GetCharacterKey(Character)
    local aura = Component or (key and AttachedAuras[key]) or nil
    local ok = pcall(function()
        if aura and aura:IsValid() then
            if type(aura.Deactivate) == "function" then aura:Deactivate() end
            if type(aura.DestroyComponent) == "function" then
                aura:DestroyComponent()
            elseif type(aura.K2_DestroyComponent) == "function" then
                aura:K2_DestroyComponent(aura)
            end
        end
    end)
    if key then AttachedAuras[key] = nil end
    Performance.Finish("aura_detach", startedAt, ok)
end

function AuraSystem.ClearCaches()
    ResolvedAssets = {}
    AttachedAuras = {}
end

return AuraSystem
