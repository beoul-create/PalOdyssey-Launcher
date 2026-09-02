local AuraSystem = {}

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
    ["Radiant"] = { Passive = "Legend", Color = 15844367, Desc = "Blessed by divine celestial light (+20% Atk, +20% Def, +15% Speed)" }
}

function AuraSystem.GetMetadata(auraType)
    return AuraMetadata[auraType] or AuraMetadata["Fiery"]
end

function AuraSystem.GetAllAuras()
    return { "Fiery", "Glacial", "Celestial", "Corrupted", "Verdant", "Tidal", "Draconic", "Radiant" }
end

local function FindValidAura(auraType)
    local list = AuraMap[auraType] or AuraMap["Fiery"]
    for _, path in ipairs(list) do
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

function AuraSystem.Attach(Character, AuraType)
    pcall(function()
        if not Character or not Character:IsValid() then return nil end
        local Mesh = Character.Mesh
        if not Mesh or not Mesh:IsValid() then return nil end

        local NiagaraAsset = FindValidAura(AuraType)
        local NiagaraFunc = StaticFindObject("/Script/Niagara.Default__NiagaraFunctionLibrary")

        if NiagaraFunc and NiagaraFunc:IsValid() and NiagaraAsset and NiagaraAsset:IsValid() then
            return NiagaraFunc:SpawnSystemAttached(
                NiagaraAsset,
                Mesh,
                FName("pelvis"),
                { X = 0, Y = 0, Z = 0 },
                { Pitch = 0, Yaw = 0, Roll = 0 },
                1, -- EAttachLocation::KeepRelativeOffset
                true, true, 0, true
            )
        end
    end)
    return nil
end

return AuraSystem
