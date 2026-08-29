local ScriptDir = debug.getinfo(1, "S").source:gsub("^@", ""):gsub("[^/\\]+$", "")
package.path = ScriptDir .. "?.lua;" .. ScriptDir .. "../?.lua;" .. package.path

local ChatCommands = require("chat_commands")

local function DecodeJson(Content)
    local decoders = {}
    if JSON and type(JSON.parse) == "function" then table.insert(decoders, JSON.parse) end
    if json and type(json.decode) == "function" then table.insert(decoders, json.decode) end
    if _G.json and type(_G.json.decode) == "function" then table.insert(decoders, _G.json.decode) end
    for _, decoder in ipairs(decoders) do
        if type(decoder) == "function" then
            local ok, parsed = pcall(decoder, Content)
            if ok and type(parsed) == "table" then return parsed end
        end
    end
    return nil
end

local function LoadJsonConfig()
    local Config = {
        GachaCostTechPoints = 3,
        GachaPool = {
            { ItemId = "PalItem_TechnologyBook_G3", Weight = 5, Count = 1, Rarity = "Legendary" },
            { ItemId = "PalSphere_Legend", Weight = 15, Count = 5, Rarity = "Epic" },
            { ItemId = "PalSphere_Master", Weight = 30, Count = 10, Rarity = "Rare" },
            { ItemId = "PalItem_AncientTechnologyPointBook", Weight = 20, Count = 1, Rarity = "Rare" },
            { ItemId = "PalItem_PureQuartz", Weight = 30, Count = 50, Rarity = "Common" }
        },
        ShopItems = {
            cake = { ItemId = "Cake", Cost = 2, Count = 1, Desc = "Breeding Cake" },
            legendsphere = { ItemId = "PalSphere_Legend", Cost = 1, Count = 3, Desc = "Legendary Pal Sphere x3" },
            ancientcore = { ItemId = "PalItem_AncientCore", Cost = 4, Count = 1, Desc = "Ancient Civilization Core" },
            respec = { ItemId = "PalItem_StatResetMedicine", Cost = 5, Count = 1, Desc = "Memory Reset Drug" }
        },
        RecycleRates = {
            PalItem_TechnologyBook_G1 = 1,
            PalItem_TechnologyBook_G2 = 2,
            PalItem_TechnologyBook_G3 = 5,
            PalItem_AncientCore = 2
        }
    }

    local File = io.open(ScriptDir .. "../config.json", "r")
    if not File then
        print("[EconomySystem] config.json was not found; using safe defaults.")
        return Config
    end
    local Content = File:read("*all")
    File:close()

    local Parsed = DecodeJson(Content)
    if not Parsed then
        print("[EconomySystem] config.json could not be decoded; using safe defaults.")
        return Config
    end

    for Key, Value in pairs(Parsed) do Config[Key] = Value end

    return Config
end

local Config = LoadJsonConfig()
if Config then
    ChatCommands.Init(Config)
    print("[EconomySystem] Successfully initialized /shop, /exchange, /recycle, and /gacha hooks.")

    -- Register optional convenient hotkeys (F6: Shop, F7: Gacha, F8: Balance)
    pcall(function()
        local function GetLocalPlayer()
            local controllers = FindAllOf("PalPlayerController") or {}
            if #controllers > 0 and controllers[1]:IsValid() then
                return controllers[1]
            end
            return nil
        end

        if type(RegisterKeyBindAsync) == "function" and Key then
            if Key.F6 then
                RegisterKeyBindAsync(Key.F6, {}, function()
                    local p = GetLocalPlayer()
                    if p then ChatCommands.HandleShopList(p) end
                end)
            end
            if Key.F7 then
                RegisterKeyBindAsync(Key.F7, {}, function()
                    local p = GetLocalPlayer()
                    if p then ChatCommands.HandleGacha(p, 1) end
                end)
            end
            if Key.F8 then
                RegisterKeyBindAsync(Key.F8, {}, function()
                    local p = GetLocalPlayer()
                    if p then ChatCommands.HandleBalance(p) end
                end)
            end
            print("[EconomySystem] Keybinds registered: [F6] Open Shop, [F7] Roll Gacha, [F8] Check Balance.")
        end
    end)
end
