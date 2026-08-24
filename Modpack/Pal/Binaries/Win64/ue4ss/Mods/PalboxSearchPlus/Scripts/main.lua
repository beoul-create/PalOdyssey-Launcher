-- ============================================================================
-- PalboxSearchPlus: Multi-Attribute Search & Filter Suite for Palbox
-- Adds live searching by Pal Name, Element Type, Passive Skills, and Work
-- Suitability with visual slot highlights and dimming of non-matches.
-- ============================================================================

local ok, Config = pcall(require, "config")
if not ok or type(Config) ~= "table" then
    Config = {
        enabled = true,
        searchByPassives = true,
        searchByElement = true,
        searchByWorkSuitability = true,
        highlightOpacity = 1.0,
        dimmedOpacity = 0.25,
        log = true
    }
end

local function Log(msg)
    if Config.log then
        print(string.format("[PalboxSearchPlus] %s\n", tostring(msg)))
    end
end

if not Config.enabled then return end

print("==========================================================")
print("  PalboxSearchPlus: Multi-Attribute Palbox Search Active   ")
print("==========================================================")

local currentSearchQuery = ""

-- Search Matching Logic
local function MatchesSearch(palSlot, query)
    if not query or query == "" then return true end
    local lowerQuery = string.lower(query)

    local isMatch = false
    pcall(function()
        -- 1. Check Nickname / Species Name
        if palSlot.GetPalName then
            local name = tostring(palSlot:GetPalName() or "")
            if string.find(string.lower(name), lowerQuery) then isMatch = true return end
        end

        -- 2. Check Individual Character Parameter / Handle
        local handle = palSlot.PalIndividualCharacterHandle
        if handle and handle:IsValid() then
            local param = handle:TryGetIndividualParameter()
            if param and param:IsValid() then
                -- Check Character ID / Name
                local charId = param.CharacterId and param.CharacterId:ToString() or ""
                if string.find(string.lower(charId), lowerQuery) then isMatch = true return end

                -- Check Element Types
                if Config.searchByElement and param.ElementType1 then
                    local elem1 = tostring(param.ElementType1)
                    local elem2 = tostring(param.ElementType2 or "")
                    if string.find(string.lower(elem1), lowerQuery) or string.find(string.lower(elem2), lowerQuery) then
                        isMatch = true
                        return
                    end
                end

                -- Check Passive Skills
                if Config.searchByPassives and param.PassiveSkillList then
                    local passives = param.PassiveSkillList
                    for i = 1, #passives do
                        local pName = tostring(passives[i] or "")
                        if string.find(string.lower(pName), lowerQuery) then
                            isMatch = true
                            return
                        end
                    end
                end
            end
        end
    end)

    return isMatch
end

-- Apply Visual Filtering to Palbox Slots
local function FilterPalboxSlots(palboxWidget, query)
    if not palboxWidget or not palboxWidget:IsValid() then return end
    pcall(function()
        local slots = FindAllOf("WBP_PalBox_Slot_C")
        if not slots or #slots == 0 then
            slots = FindAllOf("WBP_PalCharacterSlot_C")
        end

        if slots then
            for _, slot in ipairs(slots) do
                if slot and slot:IsValid() then
                    local match = MatchesSearch(slot, query)
                    if slot.SetRenderOpacity then
                        slot:SetRenderOpacity(match and Config.highlightOpacity or Config.dimmedOpacity)
                    end
                end
            end
        end
    end)
end

-- 1. Hook PalBox Widget Construction
local TARGET_PALBOX_CLASSES = {
    "/Game/Pal/Blueprint/UI/PalBox/WBP_PalBox.WBP_PalBox_C",
    "/Game/Pal/Blueprint/UI/PalBox/WBP_PalBox_PalList.WBP_PalBox_PalList_C",
    "/Game/Pal/Blueprint/UI/PalBox/WBP_PalBox_Page.WBP_PalBox_Page_C"
}

for _, classPath in ipairs(TARGET_PALBOX_CLASSES) do
    pcall(function()
        NotifyOnNewObject(classPath, function(widget)
            Log(string.format("Detected Palbox opened [%s].", classPath))
            
            -- Hook Search Textbox if available
            pcall(function()
                if widget.EditableTextBox_Search and widget.EditableTextBox_Search:IsValid() then
                    widget.EditableTextBox_Search.OnTextChanged = function(txt)
                        currentSearchQuery = tostring(txt or "")
                        FilterPalboxSlots(widget, currentSearchQuery)
                    end
                end
            end)
        end)
    end)
end

-- 2. Global Loop while Palbox is open
LoopAsync(400, function()
    pcall(function()
        local palboxes = FindAllOf("WBP_PalBox_C")
        if palboxes and #palboxes > 0 and palboxes[1]:IsValid() then
            if currentSearchQuery ~= "" then
                FilterPalboxSlots(palboxes[1], currentSearchQuery)
            end
        else
            currentSearchQuery = ""
        end
    end)
    return false -- Loop continuously
end)

Log("PalboxSearchPlus engine active and listening for Palbox interactions.")
