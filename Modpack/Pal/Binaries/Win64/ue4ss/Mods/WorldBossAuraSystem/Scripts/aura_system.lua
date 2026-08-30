local AuraSystem = {}

local AuraMap = {
    ["Fiery"] = {
        "/Game/Pal/Effect/Niagara/Common/NS_Burn_01.NS_Burn_01",
        "/Game/Pal/Effect/Niagara/Common/NS_Status_Fire.NS_Status_Fire",
        "/Game/Pal/Effect/Niagara/Skill/Fire/NS_Skill_Fire_Breath_01.NS_Skill_Fire_Breath_01"
    },
    ["Corrupted"] = {
        "/Game/Pal/Effect/Niagara/Common/NS_Status_Dark.NS_Status_Dark",
        "/Game/Pal/Effect/Niagara/Skill/Dark/NS_Skill_Dark_Laser_01.NS_Skill_Dark_Laser_01"
    },
    ["Celestial"] = {
        "/Game/Pal/Effect/Niagara/Common/NS_Status_Electric.NS_Status_Electric",
        "/Game/Pal/Effect/Niagara/Skill/Thunder/NS_Skill_Thunder_ThunderStorm_01.NS_Skill_Thunder_ThunderStorm_01"
    }
}

local function FindValidAura(auraType)
    local list = AuraMap[auraType] or AuraMap["Fiery"]
    for _, path in ipairs(list) do
        local obj = StaticFindObject(path)
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
