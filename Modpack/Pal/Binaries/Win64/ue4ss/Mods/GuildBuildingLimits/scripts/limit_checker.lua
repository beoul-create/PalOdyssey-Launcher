local LimitChecker = {}
local Config = {}

function LimitChecker.Init(LoadedConfig)
    Config = LoadedConfig or {}

    -- Hook server build placement request before construction begins
    RegisterHook("/Script/Pal.PalBuildSubsystem:RequestBuild", function(Context, RequestPlayer, BuildTypeId, Location, Rotation)
        local Subsystem = Context:get()
        local Player = RequestPlayer:get()
        if not Subsystem or not Subsystem:IsValid() or not Player or not Player:IsValid() then return end

        local TargetBuildingStr = ""
        pcall(function() TargetBuildingStr = BuildTypeId:get():ToString() end)
        if TargetBuildingStr == "" then return end

        local RestrictionRule = LimitChecker.GetRestrictionRule(TargetBuildingStr)
        if not RestrictionRule then
            return -- Not a restricted structure; allow standard placement
        end

        local GuildId = LimitChecker.GetPlayerGuildId(Player)
        if not GuildId then return end

        -- Count existing structures across this guild's base camp(s)
        local CurrentCount = LimitChecker.CountGuildStructures(GuildId, RestrictionRule.BuildingTypeIds)

        if CurrentCount >= (RestrictionRule.MaxPerGuild or 1) then
            -- 1. Cancel the building execution context
            pcall(function() Context:SetReturn(false) end)

            -- 2. Send in-game chat alert to the player
            local ChatSubsystem = FindFirstOf("PalChatSubsystem")
            if ChatSubsystem and ChatSubsystem:IsValid() then
                local templateMsg = Config.NotificationMessage or "❌ Guild building limit reached: Your guild is capped at %d %s(s)."
                local Msg = string.format(templateMsg, RestrictionRule.MaxPerGuild or 1, RestrictionRule.DisplayName or "Restricted Facility")
                ChatSubsystem:SendSystemChatMessage(Player, FText(Msg))
            end

            -- 3. Refund materials if inventory deducted preliminary cost
            LimitChecker.RefundMaterials(Player, TargetBuildingStr)
        end
    end)
end

function LimitChecker.GetRestrictionRule(BuildingTypeIdStr)
    if not Config or not Config.RestrictedBuildings then return nil end
    for _, rule in pairs(Config.RestrictedBuildings) do
        if rule.BuildingTypeIds then
            for _, id in ipairs(rule.BuildingTypeIds) do
                if id == BuildingTypeIdStr or string.find(BuildingTypeIdStr, id) then
                    return rule
                end
            end
        end
    end
    return nil
end

function LimitChecker.GetPlayerGuildId(Player)
    local guildId = nil
    pcall(function()
        local PlayerState = Player.PlayerState
        if PlayerState and PlayerState:IsValid() then
            local GuildData = PlayerState:GetGuildName()
            if GuildData then
                guildId = GuildData:ToString()
            end
        end
    end)
    return guildId
end

function LimitChecker.CountGuildStructures(GuildId, TargetTypeIds)
    local Count = 0
    local World = GetWorldContext and GetWorldContext() or nil

    pcall(function()
        local GameplayStatics = StaticFindObject("/Script/Engine.Default__GameplayStatics")
        local MapObjectClass = StaticFindObject("/Script/Pal.PalMapObject")
        if GameplayStatics and GameplayStatics:IsValid() and MapObjectClass and MapObjectClass:IsValid() and World then
            local MapObjects = GameplayStatics:GetAllActorsOfClass(World, MapObjectClass)
            if MapObjects and MapObjects:IsValid() then
                for i = 1, MapObjects:Num() do
                    local Obj = MapObjects:Get(i)
                    if Obj and Obj:IsValid() and Obj.GetGuildName then
                        local gObj = Obj:GetGuildName()
                        local gStr = gObj and gObj:ToString() or ""
                        if gStr == GuildId then
                            local TypeId = ""
                            pcall(function()
                                local idObj = Obj.GetMapObjectId and Obj:GetMapObjectId()
                                TypeId = idObj and idObj:ToString() or ""
                            end)
                            for _, target in ipairs(TargetTypeIds) do
                                if TypeId == target or string.find(TypeId, target) then
                                    Count = Count + 1
                                    break
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

function LimitChecker.RefundMaterials(Player, BuildingTypeIdStr)
    pcall(function()
        if Player.CharacterParameterComponent and Player.CharacterParameterComponent:IsValid() then
            Player.CharacterParameterComponent:ClearCurrentBuildingQueue()
        end
    end)
end

return LimitChecker
