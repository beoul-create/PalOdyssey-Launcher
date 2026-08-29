local LimitChecker = {}
local Config = {}
local UpgradesCache = {}

local function LoadGuildUpgrades()
    pcall(function()
        local paths = {
            "C:/SteamLibrary/steamapps/common/PalServer/Pal/Binaries/Win64/ue4ss/Mods/GuildBuildingLimits/guild_upgrades.json",
            "C:/SteamLibrary/steamapps/common/Palworld/Pal/Binaries/Win64/ue4ss/Mods/GuildBuildingLimits/guild_upgrades.json",
            "C:/PalOdyssey Launcher 2.0/Pal/Binaries/Win64/ue4ss/Mods/GuildBuildingLimits/guild_upgrades.json"
        }
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
    pcall(function()
        if not Player or not Player:IsValid() then return end
        local PlayerState = Player.PlayerState
        if PlayerState and PlayerState:IsValid() then
            if type(PlayerState.GetGuildName) == "function" then
                local g = PlayerState:GetGuildName()
                if g then guildId = g:ToString() end
            end
            if not guildId and PlayerState.GuildId then
                guildId = tostring(PlayerState.GuildId)
            end
        end
    end)
    return guildId or "Default_Guild"
end

function LimitChecker.CountGuildStructures(GuildId, TargetTypeIds)
    local Count = 0
    pcall(function()
        local world = GetWorldContext and GetWorldContext() or nil
        local GameplayStatics = StaticFindObject("/Script/Engine.Default__GameplayStatics")
        if not GameplayStatics or not GameplayStatics:IsValid() then return end

        local targetClasses = {
            StaticFindObject("/Script/Pal.PalBuildObject"),
            StaticFindObject("/Script/Pal.PalMapObject"),
            StaticFindObject("/Script/Pal.PalBuildObjectFarm_Breed"),
            StaticFindObject("/Script/Pal.PalBuildObjectFarm_Pasture")
        }

        for _, uclass in ipairs(targetClasses) do
            if uclass and uclass:IsValid() then
                local actors = GameplayStatics:GetAllActorsOfClass(world, uclass)
                if actors and actors:IsValid() then
                    for i = 1, actors:Num() do
                        local obj = actors:Get(i)
                        if obj and obj:IsValid() then
                            local belongsToGuild = false
                            pcall(function()
                                if obj.GetGuildName then
                                    local g = obj:GetGuildName()
                                    if g and (g:ToString() == GuildId or GuildId == "Default_Guild") then
                                        belongsToGuild = true
                                    end
                                elseif obj.BelongGuildId then
                                    local g = tostring(obj.BelongGuildId)
                                    if g == GuildId or GuildId == "Default_Guild" then
                                        belongsToGuild = true
                                    end
                                else
                                    belongsToGuild = true
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
                                    if string.find(typeStr:lower(), target:lower()) then
                                        Count = Count + 1
                                        break
                                    end
                                end
                            end
                        end
                    end
                end
            end
        end
    end)
    return Count
end

function LimitChecker.GetRestrictionRule(BuildingTypeIdStr)
    if not Config or not Config.RestrictedBuildings then return nil end
    local cleanStr = BuildingTypeIdStr:lower()
    for ruleKey, rule in pairs(Config.RestrictedBuildings) do
        if rule.BuildingTypeIds then
            for _, id in ipairs(rule.BuildingTypeIds) do
                if string.find(cleanStr, id:lower()) then
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

local function ProcessBuildRequest(Context, RequestPlayer, BuildTypeId, Location, Rotation)
    local Subsystem = Context and Context.get and Context:get() or Context
    local Player = RequestPlayer and RequestPlayer.get and RequestPlayer:get() or RequestPlayer
    if not Subsystem or not Subsystem:IsValid() or not Player or not Player:IsValid() then return end

    local TargetBuildingStr = ""
    pcall(function()
        if BuildTypeId and BuildTypeId.get then
            local obj = BuildTypeId:get()
            if obj and obj.ToString then TargetBuildingStr = obj:ToString() else TargetBuildingStr = tostring(obj) end
        elseif BuildTypeId and type(BuildTypeId.ToString) == "function" then
            TargetBuildingStr = BuildTypeId:ToString()
        elseif BuildTypeId then
            TargetBuildingStr = tostring(BuildTypeId)
        end
    end)
    if TargetBuildingStr == "" then return end

    local RestrictionRule, RuleKey = LimitChecker.GetRestrictionRule(TargetBuildingStr)
    if not RestrictionRule then
        return
    end

    local GuildId = LimitChecker.GetPlayerGuildId(Player)

    LoadGuildUpgrades()
    local guildUpgrades = UpgradesCache[GuildId] or {}
    local extraSlots = 0
    if RuleKey == "Farm_Breed" then
        extraSlots = tonumber(guildUpgrades.guild_breeding_expand) or 0
    elseif RuleKey == "Farm_Pasture" then
        extraSlots = tonumber(guildUpgrades.guild_ranch_expand) or 0
    end

    local AllowedMax = (RestrictionRule.MaxPerGuild or 1) + extraSlots
    local CurrentCount = LimitChecker.CountGuildStructures(GuildId, RestrictionRule.BuildingTypeIds)

    if CurrentCount >= AllowedMax then
        pcall(function() Context:SetReturn(false) end)

        local ChatSubsystem = FindFirstOf("PalChatSubsystem")
        if ChatSubsystem and ChatSubsystem:IsValid() then
            local templateMsg = Config.NotificationMessage or "❌ Guild limit reached: Your guild is capped at %d %s(s). Upgrade in the Economy Shop [F6] to unlock more!"
            local Msg = string.format(templateMsg, AllowedMax, RestrictionRule.DisplayName or "Restricted Facility")
            ChatSubsystem:SendSystemChatMessage(Player, FText(Msg))
        end

        local PalUtil = StaticFindObject("/Script/Pal.Default__PalUtility")
        if PalUtil and PalUtil:IsValid() then
            PalUtil:SendSystemAnnounce(Player, string.format("❌ Guild Limit Reached (%d/%d %s)", CurrentCount, AllowedMax, RestrictionRule.DisplayName or "Facility"))
        end

        LimitChecker.RefundMaterials(Player, TargetBuildingStr)
    end
end

function LimitChecker.Init(LoadedConfig)
    Config = LoadedConfig or {}

    pcall(RegisterHook, "/Script/Pal.PalBuildSubsystem:RequestBuild", ProcessBuildRequest)
    pcall(RegisterHook, "/Script/Pal.PalBuildSubsystem:RequestBuild_Server", ProcessBuildRequest)
    pcall(RegisterHook, "/Script/Pal.PalBuildSubsystem:RequestBuildDirectly", ProcessBuildRequest)
    print("[GuildBuildingLimits] LimitChecker hooks registered with dynamic scaling support.")
end

return LimitChecker
