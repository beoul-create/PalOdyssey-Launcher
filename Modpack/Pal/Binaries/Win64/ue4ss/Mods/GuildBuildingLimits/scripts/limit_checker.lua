local LimitChecker = {}
local Config = {}
local UpgradesCache = {}
local ScriptDir = debug.getinfo(1, "S").source:gsub("^@", ""):gsub("[^/\\]+$", "")
local UpgradesFile = ScriptDir .. "../guild_upgrades.json"

local function LoadGuildUpgrades()
    pcall(function()
        local paths = { UpgradesFile }
        for _, path in ipairs(paths) do
            local f = io.open(path, "r")
            if f then
                local raw = f:read("*all")
                f:close()
                local decoders = {}
                if JSON and type(JSON.parse) == "function" then table.insert(decoders, JSON.parse) end
                if json and type(json.decode) == "function" then table.insert(decoders, json.decode) end
                if _G.json and type(_G.json.decode) == "function" then table.insert(decoders, _G.json.decode) end
                for _, d in ipairs(decoders) do
                    local ok, parsed = pcall(d, raw)
                    if ok and type(parsed) == "table" then
                        UpgradesCache = parsed
                        return
                    end
                end
            end
        end
    end)
end

function LimitChecker.GetPlayerGuildId(Player)
    local guildId = nil
    local guildName = nil
    pcall(function()
        if not Player or not Player:IsValid() then return end
        local PlayerState = Player.PlayerState
        if PlayerState and PlayerState:IsValid() then
            if PlayerState.GuildId ~= nil then
                guildId = tostring(PlayerState.GuildId)
            elseif type(PlayerState.GetGuildId) == "function" then
                local id = PlayerState:GetGuildId()
                if id then guildId = tostring(id) end
            elseif type(PlayerState.GetGuildName) == "function" then
                local g = PlayerState:GetGuildName()
                if g then guildName = g:ToString(); guildId = guildName end
            end
            if type(PlayerState.GetGuildName) == "function" then
                local g = PlayerState:GetGuildName()
                if g then guildName = g:ToString() end
            end
        end
    end)
    return guildId, guildName
end

function LimitChecker.CountGuildStructures(GuildId, TargetTypeIds, GuildName)
    local Count = 0
    if not GuildId then return Count end
    local ok, err = pcall(function()
        local world = GetWorldContext and GetWorldContext() or nil
        if not world then error("world context unavailable") end
        local GameplayStatics = StaticFindObject("/Script/Engine.Default__GameplayStatics")
        if not GameplayStatics or not GameplayStatics:IsValid() then return end

        local targetClasses = {
            StaticFindObject("/Script/Pal.PalBuildObject"),
            StaticFindObject("/Script/Pal.PalMapObject"),
            StaticFindObject("/Script/Pal.PalBuildObjectFarm_Breed"),
            StaticFindObject("/Script/Pal.PalBuildObjectFarm_Pasture")
        }

        local seenActors = {}
        for _, uclass in ipairs(targetClasses) do
            if uclass and uclass:IsValid() then
                local actors = GameplayStatics:GetAllActorsOfClass(world, uclass)
                if actors and type(actors.ForEach) == "function" then
                    actors:ForEach(function(_, actorParam)
                        local obj = actorParam and actorParam.get and actorParam:get() or actorParam
                        if obj and obj:IsValid() and not seenActors[obj] then
                            seenActors[obj] = true
                            local belongsToGuild = false
                            pcall(function()
                                if obj.BelongGuildId ~= nil then
                                    local g = tostring(obj.BelongGuildId)
                                    if g == GuildId then
                                        belongsToGuild = true
                                    end
                                elseif obj.GetGuildId then
                                    local g = obj:GetGuildId()
                                    if g and tostring(g) == GuildId then
                                        belongsToGuild = true
                                    end
                                elseif obj.GetGuildName and GuildName then
                                    local g = obj:GetGuildName()
                                    if g and g:ToString() == GuildName then belongsToGuild = true end
                                end
                            end)

                            if belongsToGuild then
                                local typeStr = ""
                                pcall(function()
                                    if obj.GetMapObjectId then
                                        local id = obj:GetMapObjectId()
                                        if id then typeStr = id:ToString() end
                                    end
                                    if typeStr == "" and obj.GetBuildTypeId then
                                        local id = obj:GetBuildTypeId()
                                        if id then typeStr = id:ToString() end
                                    end
                                    if typeStr == "" then
                                        typeStr = obj:GetFullName() or ""
                                    end
                                end)

                                for _, target in ipairs(TargetTypeIds) do
                                    if string.find(typeStr:lower(), target:lower(), 1, true) then
                                        Count = Count + 1
                                        break
                                    end
                                end
                            end
                        end
                    end)
                end
            end
        end
    end)
    if not ok then print("[GuildBuildingLimits] Structure scan failed: " .. tostring(err)) end
    return Count
end

function LimitChecker.GetRestrictionRule(BuildingTypeIdStr)
    if not Config or not Config.RestrictedBuildings then return nil end
    local cleanStr = BuildingTypeIdStr:lower()
    for ruleKey, rule in pairs(Config.RestrictedBuildings) do
        if rule.BuildingTypeIds then
            for _, id in ipairs(rule.BuildingTypeIds) do
        if string.find(cleanStr, id:lower(), 1, true) then
                    return rule, ruleKey
                end
            end
        end
    end
    return nil
end

function LimitChecker.RefundMaterials(Player, BuildingTypeIdStr)
    pcall(function()
        if Player and Player.CharacterParameterComponent and Player.CharacterParameterComponent:IsValid() then
            if type(Player.CharacterParameterComponent.ClearCurrentBuildingQueue) == "function" then
                Player.CharacterParameterComponent:ClearCurrentBuildingQueue()
            end
        end
    end)
end

local function ProcessBuildRequest(Context, ...)
    local Subsystem = Context and Context.get and Context:get() or Context
    if not Subsystem or not Subsystem:IsValid() then return end

    local Player = nil
    local TargetBuildingStr = ""
    local args = { ... }
    for _, param in ipairs(args) do
        local value = param and param.get and param:get() or param
        if value then
            pcall(function()
                if not Player and value.IsA and value:IsA("/Script/Pal.PalPlayerController") then
                    Player = value
                elseif not Player and value.PlayerController and value.PlayerController:IsValid() then
                    Player = value.PlayerController
                end
            end)
            pcall(function()
                local candidate = type(value) == "string" and value
                    or (type(value.ToString) == "function" and value:ToString())
                    or tostring(value)
                if TargetBuildingStr == "" and LimitChecker.GetRestrictionRule(candidate) then
                    TargetBuildingStr = candidate
                end
            end)
        end
    end
    if not Player or not Player:IsValid() then return end

    if TargetBuildingStr == "" then return end

    local RestrictionRule, RuleKey = LimitChecker.GetRestrictionRule(TargetBuildingStr)
    if not RestrictionRule then
        return
    end

    local GuildId, GuildName = LimitChecker.GetPlayerGuildId(Player)
    if not GuildId then
        print("[GuildBuildingLimits] Skipping limit check: stable guild ID unavailable.")
        return
    end

    LoadGuildUpgrades()
    local guildUpgrades = UpgradesCache[GuildId] or {}
    local extraSlots = 0
    if RuleKey == "Farm_Breed" then
        extraSlots = tonumber(guildUpgrades.guild_breeding_expand) or 0
    elseif RuleKey == "Farm_Pasture" then
        extraSlots = tonumber(guildUpgrades.guild_ranch_expand) or 0
    end

    local AllowedMax = (RestrictionRule.MaxPerGuild or 1) + extraSlots
    local CurrentCount = LimitChecker.CountGuildStructures(GuildId, RestrictionRule.BuildingTypeIds, GuildName)

    if CurrentCount >= AllowedMax then
        pcall(function()
            local ChatSubsystem = FindFirstOf("PalChatSubsystem")
            if ChatSubsystem and ChatSubsystem:IsValid() then
                local templateMsg = Config.NotificationMessage or "❌ Guild limit reached: Your guild is capped at %d %s(s). Upgrade in the Economy Shop [F6] to unlock more!"
                ChatSubsystem:SendSystemChatMessage(Player, FText(string.format(templateMsg, AllowedMax, RestrictionRule.DisplayName or "Restricted Facility")))
            end
            local PalUtil = StaticFindObject("/Script/Pal.Default__PalUtility")
            if PalUtil and PalUtil:IsValid() then
                PalUtil:SendSystemAnnounce(Player, string.format("❌ Guild Limit Reached (%d/%d %s)", CurrentCount, AllowedMax, RestrictionRule.DisplayName or "Facility"))
            end
        end)
        -- UE4SS hook return values override the UFunction result. No materials
        -- are refunded here because this is a pre-construction rejection.
        return false
    end
end

function LimitChecker.Init(LoadedConfig)
    Config = LoadedConfig or {}

    local registered = 0
    for _, hookName in ipairs({
        "/Script/Pal.PalBuildSubsystem:RequestBuild",
        "/Script/Pal.PalBuildSubsystem:RequestBuild_Server",
        "/Script/Pal.PalBuildSubsystem:RequestBuildDirectly"
    }) do
        local ok, preId = pcall(RegisterHook, hookName, ProcessBuildRequest)
        if ok and preId then registered = registered + 1
        else print("[GuildBuildingLimits] Hook unavailable: " .. hookName) end
    end
    print(string.format("[GuildBuildingLimits] %d/3 limit hooks registered.", registered))
end

return LimitChecker
