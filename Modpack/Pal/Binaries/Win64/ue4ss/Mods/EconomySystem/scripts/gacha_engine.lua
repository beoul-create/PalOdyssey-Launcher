local GachaEngine = {}

function GachaEngine.Roll(Pool)
    if not Pool or #Pool == 0 then
        return { ItemId = "PalSphere_Legend", Count = 1, Rarity = "Common" }
    end

    local TotalWeight = 0
    for _, entry in ipairs(Pool) do
        TotalWeight = TotalWeight + math.max(0, tonumber(entry.Weight) or 1)
    end

    if TotalWeight <= 0 then TotalWeight = 1 end

    local Roll = math.random() * TotalWeight
    local CurrentWeight = 0

    for _, entry in ipairs(Pool) do
        CurrentWeight = CurrentWeight + math.max(0, tonumber(entry.Weight) or 1)
        if Roll <= CurrentWeight then
            return entry
        end
    end

    return Pool[1]
end

return GachaEngine
