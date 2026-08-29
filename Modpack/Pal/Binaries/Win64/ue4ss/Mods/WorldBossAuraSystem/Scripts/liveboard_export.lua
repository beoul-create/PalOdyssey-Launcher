local LiveboardExport = {}
local ScriptDir = debug.getinfo(1, "S").source:gsub("^@", ""):gsub("[^/\\]+$", "")
local StatePath = ScriptDir .. "../../../../../../Saved/liveboard_state.json"

local function EncodeJsonString(value)
    return '"' .. tostring(value)
        :gsub("\\", "\\\\")
        :gsub('"', '\\"')
        :gsub("\b", "\\b")
        :gsub("\f", "\\f")
        :gsub("\n", "\\n")
        :gsub("\r", "\\r")
        :gsub("\t", "\\t")
        :gsub("[%z\1-\31]", function(c) return string.format("\\u%04x", string.byte(c)) end)
        .. '"'
end

-- Lightweight pure-Lua JSON serializer for UE4SS runtime
local function EncodeJsonValue(val)
    local t = type(val)
    if t == "string" then
        return EncodeJsonString(val)
    elseif t == "number" then
        if val ~= val or val == math.huge or val == -math.huge then return "null" end
        return tostring(val)
    elseif t == "boolean" then
        return tostring(val)
    elseif t == "table" then
        local isArray = true
        local maxIndex = 0
        for k, v in pairs(val) do
            if type(k) == "number" and k > 0 and math.floor(k) == k then
                if k > maxIndex then maxIndex = k end
            else
                isArray = false
                break
            end
        end

        if isArray then
            local items = {}
            for i = 1, maxIndex do
                table.insert(items, EncodeJsonValue(val[i]))
            end
            return "[" .. table.concat(items, ",") .. "]"
        else
            local fields = {}
            for k, v in pairs(val) do
                table.insert(fields, EncodeJsonString(k) .. ":" .. EncodeJsonValue(v))
            end
            return "{" .. table.concat(fields, ",") .. "}"
        end
    else
        return "null"
    end
end

function LiveboardExport.DumpState(ActiveBosses, Config)
    local PlayersList = {}
    local World = GetWorldContext and GetWorldContext() or nil

    -- 1. Gather Online Players & Levels
    pcall(function()
        local GameplayStatics = StaticFindObject("/Script/Engine.Default__GameplayStatics")
        local PlayerStateClass = StaticFindObject("/Script/Pal.PalPlayerState")
        if GameplayStatics and GameplayStatics:IsValid() and PlayerStateClass and PlayerStateClass:IsValid() and World then
            local PlayerStates = GameplayStatics:GetAllActorsOfClass(World, PlayerStateClass)
            if PlayerStates and PlayerStates:IsValid() then
                for i = 1, PlayerStates:Num() do
                    local State = PlayerStates:Get(i)
                    if State and State:IsValid() then
                        local pName = "Unknown"
                        local pLevel = 1
                        local pGuild = "None"
                        pcall(function() pName = State:GetPlayerName():ToString() end)
                        pcall(function() pLevel = State:GetLevel() end)
                        pcall(function() pGuild = State:GetGuildName():ToString() end)

                        table.insert(PlayersList, {
                            Name = pName,
                            Level = pLevel,
                            GuildName = pGuild
                        })
                    end
                end
            end
        end
    end)

    -- 2. Format Active Boss Instances
    local BossesList = {}
    if ActiveBosses then
        for uid, boss in pairs(ActiveBosses) do
            table.insert(BossesList, {
                PalId = boss.PalId or "Unknown",
                Aura = boss.Aura or "Fiery",
                LocationName = boss.LocationName or "Wilderness",
                Coords = boss.Coords or { X = 0, Y = 0 },
                SpawnTime = boss.SpawnTime or os.time()
            })
        end
    end

    -- 3. Write Output File for Discord Bot
    local Data = {
        ServerOnline = true,
        ServerName = (Config and Config.ServerName) or "PalOdyssey Official",
        PlayerCount = #PlayersList,
        MaxPlayers = (Config and Config.MaxPlayers) or 32,
        Players = PlayersList,
        ActiveBosses = BossesList,
        Timestamp = os.time()
    }

    pcall(function()
        local File = io.open(StatePath, "w")
        if File then
            File:write(EncodeJsonValue(Data))
            File:close()
        end
    end)
end

return LiveboardExport
