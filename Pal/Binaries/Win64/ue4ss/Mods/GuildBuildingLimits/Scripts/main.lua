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

-- Protection Hook: Ensure Technology Merchant (Male_Trader01_v04, Male_Trader01_v10) is uncatchable and unkillable
pcall(function()
    local function isProtectedMerchant(actor)
        if not actor or not actor:IsValid() then return false end
        local fName = ""
        pcall(function() fName = actor:GetFullName() end)
        if fName:find("Male_Trader01_v10") or fName:find("Male_Trader01_v04") then
            return true
        end
        local charId = ""
        pcall(function()
            local param = actor.GetCharacterParameter and actor:GetCharacterParameter()
            if param and param:IsValid() and param.GetIndividualCharacterParameter then
                local ind = param:GetIndividualCharacterParameter()
                if ind and ind:IsValid() and ind.GetCharacterId then
                    charId = ind:GetCharacterId():ToString()
                end
            end
        end)
        if charId == "Male_Trader01_v10" or charId == "Male_Trader01_v04" then
            return true
        end
        return false
    end

    -- Hook capture throw / capture judge to block capture
    local captureHooks = {
        "/Script/Pal.PalUtility:CanCaptureCharacter",
        "/Script/Pal.PalCaptureJudgeComponent:CanCapture",
        "/Script/Pal.PalCaptureJudgeComponent:ChallengeCapture"
    }
    for _, chName in ipairs(captureHooks) do
        pcall(RegisterHook, chName, function(Context, TargetActor)
            local target = TargetActor and TargetActor.get and TargetActor:get() or TargetActor
            if isProtectedMerchant(target) then
                return false
            end
        end)
    end

    -- Hook damage reception so Technology Merchant takes 0 damage
    pcall(RegisterHook, "/Script/Pal.PalDamageReactionComponent:CallOnActualDamageProcessed_ToAll", function(Context, Attacker, Defender, DamageInfo)
        local def = Defender and Defender.get and Defender:get() or Defender
        if isProtectedMerchant(def) then
            pcall(function()
                if DamageInfo and DamageInfo.get then
                    local d = DamageInfo:get()
                    if d and d.Damage then d.Damage = 0 end
                end
            end)
        end
    end)
    print("[GuildBuildingLimits] Technology Merchant invulnerability & capture-immunity hooks armed.")
end)
