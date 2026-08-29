local ChatCommands = require("scripts.chat_commands")

local function LoadJsonConfig()
    local File = io.open("Pal/Binaries/Win64/ue4ss/Mods/EconomySystem/config.json", "r")
    if not File then return nil end
    local Content = File:read("*all")
    File:close()

    -- Fallback config table if JSON parser is not present
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

    if JSON and JSON.parse then
        pcall(function()
            local parsed = JSON.parse(Content)
            if parsed then Config = parsed end
        end)
    end

    return Config
end

local Config = LoadJsonConfig()
if Config then
    ChatCommands.Init(Config)
    print("[EconomySystem] Successfully initialized /shop, /exchange, /recycle, and /gacha hooks.")
end
