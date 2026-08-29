local AuraSystem = {}

local AuraMap = {
    ["Fiery"] = "/Game/Mods/Auras/NS_Aura_Fire.NS_Aura_Fire",
    ["Corrupted"] = "/Game/Mods/Auras/NS_Aura_Void.NS_Aura_Void",
    ["Celestial"] = "/Game/Mods/Auras/NS_Aura_Holy.NS_Aura_Holy"
}

function AuraSystem.Attach(Character, AuraType)
    if not Character or not Character:IsValid() then return nil end
    local Mesh = Character.Mesh
    if not Mesh or not Mesh:IsValid() then return nil end

    local AssetPath = AuraMap[AuraType] or AuraMap["Fiery"]
    local NiagaraAsset = StaticFindObject(AssetPath)
    local NiagaraFunc = StaticFindObject("/Script/Niagara.NiagaraFunctionLibrary")

    if NiagaraFunc:IsValid() and NiagaraAsset:IsValid() then
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
    return nil
end

return AuraSystem
