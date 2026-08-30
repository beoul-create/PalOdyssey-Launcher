local ScriptDir = debug.getinfo(1, "S").source:gsub("^@", ""):gsub("[^/\\]+$", "")
package.path = ScriptDir .. "?.lua;" .. ScriptDir .. "../?.lua;" .. package.path
package.path = ScriptDir .. "../../shared/?.lua;" .. package.path
local Json = require("palodyssey_json")

local LimitChecker = require("limit_checker")

local function DecodeJson(Content)
    local decoders = {}
    if JSON and type(JSON.parse) == "function" then table.insert(decoders, JSON.parse) end
    if json and type(json.decode) == "function" then table.insert(decoders, json.decode) end
    if _G.json and type(_G.json.decode) == "function" then table.insert(decoders, _G.json.decode) end
    table.insert(decoders, Json.decode)
    for _, decoder in ipairs(decoders) do
        if type(decoder) == "function" then
            local ok, parsed = pcall(decoder, Content)
            if ok and type(parsed) == "table" then return parsed end
        end
    end
    return nil
end

local function LoadConfig()
    local Config = {
        RestrictedBuildings = {
            Farm_Breed = {
                DisplayName = "Breeding Farm",
                MaxPerGuild = 1,
                BuildingTypeIds = { "Build_Farm_Breed", "Farm_Breed" }
            },
            Farm_Pasture = {
                DisplayName = "Ranch",
                MaxPerGuild = 1,
                BuildingTypeIds = { "Build_Farm_Pasture", "Farm_Pasture" }
            }
        },
        NotificationMessage = "❌ Guild building limit reached: Your guild is capped at %d %s(s) to maintain server economy balance."
    }

    local File = io.open(ScriptDir .. "../config.json", "r")
    if not File then
        print("[GuildBuildingLimits] config.json was not found; using safe defaults.")
        return Config
    end
    local Content = File:read("*all")
    File:close()

    local Parsed = DecodeJson(Content)
    if not Parsed then
        print("[GuildBuildingLimits] config.json could not be decoded; using safe defaults.")
        return Config
    end

    for Key, Value in pairs(Parsed) do Config[Key] = Value end

    return Config
end

local Config = LoadConfig()
if Config then
    LimitChecker.Init(Config)
    print("[GuildBuildingLimits] Successfully initialized build placement interceptor (Cap: 1 Breeding Farm & 1 Ranch per guild).")
end
