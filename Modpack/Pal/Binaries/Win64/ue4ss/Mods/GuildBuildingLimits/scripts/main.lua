local LimitChecker = require("scripts.limit_checker")

local function LoadConfig()
    local File = io.open("Pal/Binaries/Win64/ue4ss/Mods/GuildBuildingLimits/config.json", "r")
    if not File then return nil end
    local Content = File:read("*all")
    File:close()

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

    if JSON and JSON.parse then
        pcall(function()
            local parsed = JSON.parse(Content)
            if parsed then Config = parsed end
        end)
    end

    return Config
end

local Config = LoadConfig()
if Config then
    LimitChecker.Init(Config)
    print("[GuildBuildingLimits] Successfully initialized build placement interceptor (Cap: 1 Breeding Farm & 1 Ranch per guild).")
end
