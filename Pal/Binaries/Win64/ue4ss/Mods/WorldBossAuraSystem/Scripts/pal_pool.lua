-- Canonical Palworld species IDs bundled for offline dedicated-server use.
-- The base list was generated from Palworld 1.0 game data on 2026-09-02.
-- Installed PalSchema data files are merged at startup so custom subspecies
-- remain updateable without changing this module.
local PalPool = {}

local VanillaIds = {
    "Alpaca",
    "AmaterasuWolf",
    "AmaterasuWolf_Dark",
    "Anubis",
    "BadCatgirl",
    "Baphomet",
    "Baphomet_Dark",
    "Bastet",
    "Bastet_Ice",
    "BerryGoat",
    "BerryGoat_Dark",
    "BirdDragon",
    "BirdDragon_Ice",
    "BlackCentaur",
    "BlackGriffon",
    "BlackMetalDragon",
    "BlackPuppy",
    "BlackPuppy_Ice",
    "BlueberryFairy",
    "BlueDragon",
    "BlueDragon_Ice",
    "BluePlatypus",
    "BluePlatypus_Fire",
    "BlueSkyDragon",
    "BlueThunderHorse",
    "Boar",
    "BrownRabbit",
    "CactusDoll",
    "CactusDoll_Dark",
    "CandleGhost",
    "CaptainPenguin",
    "CaptainPenguin_Black",
    "Carbunclo",
    "CatBat",
    "CatMage",
    "CatMage_Fire",
    "CatVampire",
    "ChickenPal",
    "ClioneTwins",
    "CloverFairy",
    "ClownRabbit",
    "ColorfulBird",
    "CowPal",
    "CubeTurtle",
    "CubeTurtle_Neutral",
    "CuteButterfly",
    "CuteFox",
    "CuteMole",
    "DandelionGirl",
    "DarkAlien",
    "DarkCrow",
    "DarkFlameFox",
    "DarkMechaDragon",
    "DarkScorpion",
    "DarkScorpion_Ground",
    "Deer",
    "Deer_Ground",
    "DomeArmorDragon",
    "DreamDemon",
    "DrillGame",
    "Eagle",
    "ElecCat",
    "ElecLizard",
    "ElecPanda",
    "ElecPomeranian",
    "ElecSnail",
    "ElecSnail_Ground",
    "FairyDragon",
    "FairyDragon_Water",
    "FeatherOstrich",
    "FengyunDeeper",
    "FengyunDeeper_Electric",
    "FireKirin",
    "FireKirin_Dark",
    "FlameBambi",
    "FlameBuffalo",
    "FlowerDinosaur",
    "FlowerDinosaur_Electric",
    "FlowerDoll",
    "FlowerDoll_Fire",
    "FlowerPrince",
    "FlowerRabbit",
    "FluffyBird",
    "FlyingManta",
    "FlyingManta_Thunder",
    "FoxExorcist",
    "FoxMage",
    "FoxMage_Dark",
    "Ganesha",
    "Garm",
    "GhostAnglerfish",
    "GhostAnglerfish_Fire",
    "GhostBeast",
    "GhostBlackCat",
    "GhostDragon",
    "GhostDragon_Fire",
    "GhostRabbit",
    "GhostRabbit_Grass",
    "GoldenHorse",
    "Gorilla",
    "Gorilla_Ground",
    "GrassGolem",
    "GrassGolem_Dark",
    "GrassMammoth",
    "GrassMammoth_Ice",
    "GrassMinotaur",
    "GrassMinotaur_Ice",
    "GrassPanda",
    "GrassPanda_Electric",
    "GrassRabbitMan",
    "GrimGirl",
    "GuardianDog",
    "HadesBird",
    "HadesBird_Electric",
    "HawkBird",
    "Hedgehog",
    "Hedgehog_Ice",
    "HerculesBeetle",
    "HerculesBeetle_Ground",
    "HoodGhost",
    "Horus",
    "Horus_Water",
    "IceCrocodile",
    "IceDeer",
    "IceFox",
    "IceHorse",
    "IceHorse_Dark",
    "IceNarwhal",
    "IceNarwhal_Fire",
    "IceSeal",
    "IceSeal_Ground",
    "IceWitch",
    "JellyfishFairy",
    "JellyfishGhost",
    "JetDragon",
    "KabukiMan",
    "Kelpie",
    "Kelpie_Fire",
    "KendoFrog",
    "KendoFrog_Dark",
    "KingAlpaca",
    "KingAlpaca_Ice",
    "KingBahamut",
    "KingBahamut_Dragon",
    "KingSunfish",
    "KingSunfish_Thunder",
    "Kirin",
    "Kirin_Ice",
    "Kitsunebi",
    "Kitsunebi_Ice",
    "LanternButler",
    "LavaGirl",
    "LazyCatfish",
    "LazyCatfish_Gold",
    "LazyDragon",
    "LazyDragon_Electric",
    "LeafMomonga",
    "LeafPrincess",
    "LegendDeer",
    "LilyQueen",
    "LilyQueen_Dark",
    "LittleBriarRose",
    "LizardMan",
    "LizardMan_Fire",
    "LongCat",
    "LotusDragon",
    "Manticore",
    "Manticore_Dark",
    "MimicDog",
    "Monkey",
    "Monkey_Fire",
    "MonochromeQueen",
    "MoonChild",
    "MoonQueen",
    "MopBaby",
    "MopKing",
    "Mothman",
    "MummyPal",
    "MushroomDragon",
    "MushroomDragon_Dark",
    "MushroomLady",
    "Mutant",
    "MysteryMask",
    "NaughtyCat",
    "NegativeKoala",
    "NegativeOctopus",
    "NegativeOctopus_Neutral",
    "NightBlueHorse",
    "NightBlueHorse_Neutral",
    "NightFox",
    "NightLady",
    "NightLady_Dark",
    "OctopusGirl",
    "OctopusGirl_Neutral",
    "OniGhostGirl",
    "PandaGirl",
    "Penguin",
    "Penguin_Electric",
    "PinkCat",
    "PinkLizard",
    "PinkRabbit",
    "PinkRabbit_Grass",
    "PlantSlime",
    "PlantSlime_Flower",
    "Plesiosaur",
    "PoseidonOrca",
    "PurpleSpider",
    "QueenBee",
    "RaijinDaughter",
    "RaijinDaughter_Water",
    "RedArmorBird",
    "RedFlowerBird",
    "RobinHood",
    "RobinHood_Ground",
    "RockBeast",
    "RockBeast_Ice",
    "Ronin",
    "Ronin_Dark",
    "SaintCentaur",
    "SakuraSaurus",
    "SakuraSaurus_Water",
    "SamuraiDog",
    "ScorpionMan",
    "ScorpionMan_Electric",
    "Sekhmet",
    "Serpent",
    "Serpent_Ground",
    "SharkKid",
    "SharkKid_Fire",
    "Sheepball",
    "SifuDog",
    "SkyDragon",
    "SkyDragon_Grass",
    "SleeveRabbit",
    "SmallArmadillo",
    "SmallYeti",
    "SnakeGirl",
    "SnowPeafowl",
    "SnowTigerBeastman",
    "SoldierBee",
    "StuffedShark",
    "StuffedShark_Fire",
    "SumoDog",
    "Suzaku",
    "Suzaku_Water",
    "SweetsSheep",
    "SweetsSheep_Ground",
    "SwordCutlassfish",
    "SwordCutlassfish_Fire",
    "TentacleTurtle",
    "TentacleTurtle_Ground",
    "ThiefBird",
    "ThunderBird",
    "ThunderBird_Ice",
    "ThunderDog",
    "ThunderDog_Ice",
    "ThunderDragonMan",
    "ThunderFluffyBird",
    "TropicalOstrich",
    "Umihebi",
    "Umihebi_Fire",
    "VenusFlytrap",
    "VioletFairy",
    "VolcanicMonster",
    "VolcanicMonster_Ice",
    "VolcanoDragon",
    "VolcanoDragon_Ice",
    "WeaselDragon",
    "WeaselDragon_Fire",
    "Werewolf",
    "Werewolf_Ice",
    "WhiteAlienDragon",
    "WhiteDeer",
    "WhiteDeer_Dark",
    "WhiteMoth",
    "WhiteMoth_Neutral",
    "WhiteShieldDragon",
    "WhiteTiger",
    "WhiteTiger_Ground",
    "WindChimes",
    "WindChimes_Ice",
    "WingGolem",
    "WingGolem_Fire",
    "WizardOwl",
    "WoolFox",
    "WorldTreeDragon",
    "Yeti",
    "Yeti_Grass",
}

local function AddId(result, seen, value)
    if type(value) ~= "string" then return end
    local id = value:match("^%s*(.-)%s*$")
    if id == "" or seen[id] then return end
    seen[id] = true
    result[#result + 1] = id
end

local function StripJsonComments(source)
    local output = {}
    local index, length = 1, #source
    local inString, escaped = false, false
    while index <= length do
        local current = source:sub(index, index)
        local nextChar = source:sub(index + 1, index + 1)
        if inString then
            output[#output + 1] = current
            if escaped then escaped = false
            elseif current == "\\" then escaped = true
            elseif current == '"' then inString = false end
            index = index + 1
        elseif current == '"' then
            inString = true
            output[#output + 1] = current
            index = index + 1
        elseif current == "/" and nextChar == "/" then
            index = index + 2
            while index <= length and not source:sub(index, index):match("[\r\n]") do index = index + 1 end
        elseif current == "/" and nextChar == "*" then
            index = index + 2
            while index <= length and not (source:sub(index, index) == "*" and source:sub(index + 1, index + 1) == "/") do
                index = index + 1
            end
            index = math.min(length + 1, index + 2)
        else
            output[#output + 1] = current
            index = index + 1
        end
    end
    return table.concat(output)
end

local function IsAbsolutePath(path)
    return path:match("^%a:[/\\]") ~= nil or path:match("^[/\\][/\\]") ~= nil or path:sub(1, 1) == "/"
end

local function LoadPalSchemaFile(path, scriptDir, decodeJson, result, seen)
    local resolvedPath = IsAbsolutePath(path) and path or (scriptDir .. path)
    local file = io.open(resolvedPath, "r")
    if not file then
        print("[WorldBossAuraSystem] Optional Pal data file not found: " .. tostring(path))
        return 0
    end
    local content = file:read("*all")
    file:close()

    local ok, parsed = pcall(decodeJson, StripJsonComments(content))
    if not ok or type(parsed) ~= "table" then
        print("[WorldBossAuraSystem] Could not decode Pal data file: " .. tostring(path))
        return 0
    end

    local added = 0
    for id, definition in pairs(parsed) do
        if type(id) == "string" and type(definition) == "table"
            and (definition.IsPal == true or definition.is_pal == true) and not seen[id] then
            AddId(result, seen, id)
            added = added + 1
        end
    end
    return added
end

function PalPool.Build(config, scriptDir, decodeJson)
    config = config or {}
    local result, seen = {}, {}
    local mode = tostring(config.BossPalPoolMode or "AllAvailable"):lower()
    local useAll = mode ~= "configured" and mode ~= "custom"

    if useAll then
        for _, id in ipairs(VanillaIds) do AddId(result, seen, id) end
    end

    -- In AllAvailable mode this is an additions list; in Configured mode it is
    -- the complete allow-list, preserving the old behavior when explicitly requested.
    for _, id in ipairs(config.BossPalPool or {}) do AddId(result, seen, id) end

    local schemaCount = 0
    if useAll and type(decodeJson) == "function" then
        local dataFiles = config.BossPalDataFiles
        if type(dataFiles) ~= "table" then
            dataFiles = { "../../PalSchema/mods/CustomSubspeciesBreeding/pals/SubspeciesPals.jsonc" }
        end
        for _, path in ipairs(dataFiles) do
            if type(path) == "string" and path ~= "" then
                schemaCount = schemaCount + LoadPalSchemaFile(path, scriptDir, decodeJson, result, seen)
            end
        end
    end

    local exclusions = {}
    for _, id in ipairs(config.BossPalPoolExclusions or {}) do
        if type(id) == "string" then exclusions[id] = true end
    end
    if next(exclusions) then
        local filtered = {}
        for _, id in ipairs(result) do
            if not exclusions[id] then filtered[#filtered + 1] = id end
        end
        result = filtered
    end

    return result, { Mode = useAll and "AllAvailable" or "Configured", SchemaCount = schemaCount }
end

return PalPool
