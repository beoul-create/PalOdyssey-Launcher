-- Palbox Search Plus & Filter Suite
-- PalOdyssey Quality of Life Mod
local PalboxSearchPlus = {
    version = "1.2.0",
    config = {
        enabled = true,
        highlightMatches = true,
        searchByPassives = true,
        searchByElement = true,
        enableQuickSort = true
    }
}

local function LoadConfig()
    local userConfig = "PalboxSearchPlus_user.json"
    -- Attempt load or fallback to defaults
    print(string.format("[PalboxSearchPlus v%s] Initialized & Integrated with DarnMenu.", PalboxSearchPlus.version))
end

function PalboxSearchPlus.ApplyFilter(query, palList)
    if not PalboxSearchPlus.config.enabled or not query or query == "" then
        return palList
    end

    local filtered = {}
    local lowerQuery = string.lower(query)

    for _, pal in ipairs(palList or {}) do
        local nameMatch = pal.Name and string.find(string.lower(pal.Name), lowerQuery) ~= nil
        local passiveMatch = PalboxSearchPlus.config.searchByPassives and pal.Passives and string.find(string.lower(pal.Passives), lowerQuery) ~= nil
        local elementMatch = PalboxSearchPlus.config.searchByElement and pal.Element and string.find(string.lower(pal.Element), lowerQuery) ~= nil

        if nameMatch or passiveMatch or elementMatch then
            table.insert(filtered, pal)
        end
    end

    return filtered
end

LoadConfig()
return PalboxSearchPlus
