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
    local SeenNames = {}

    -- 1. Gather Online Players from PlayerStates
    pcall(function()
        local pStates = FindAllOf("PalPlayerState") or {}
        for _, state in ipairs(pStates) do
            pcall(function()
                if not state or not state:IsValid() then return end
                local pName = ""
                local pLevel = 1
                local pGuild = "None"

                pcall(function()
                    if state.GetPlayerName then
                        pName = state:GetPlayerName():ToString()
                    elseif state.PlayerNamePrivate then
                        pName = state.PlayerNamePrivate:ToString()
                    end
                end)

                pcall(function()
                    if state.GetLevel then
                        pLevel = state:GetLevel()
                    elseif state.Level then
                        pLevel = state.Level
                    end
                end)

                pcall(function()
                    if state.GetGuildName then
                        pGuild = state:GetGuildName():ToString()
                    elseif state.GuildName then
                        pGuild = state.GuildName:ToString()
                    end
                end)

                if pName and pName ~= "" and pName ~= "Unknown" and not SeenNames[pName] then
                    SeenNames[pName] = true
                    table.insert(PlayersList, {
                        Name = pName,
                        Level = pLevel or 1,
                        GuildName = pGuild or "None"
                    })
                end
            end)
        end
    end)

    -- Fallback to PlayerControllers if needed
    if #PlayersList == 0 then
        pcall(function()
            local controllers = FindAllOf("PalPlayerController") or {}
            for _, pc in ipairs(controllers) do
                pcall(function()
                    if not pc or not pc:IsValid() then return end
                    local pState = pc.PlayerState
                    if pState and pState:IsValid() then
                        local pName = ""
                        pcall(function() pName = pState:GetPlayerName():ToString() end)
                        if pName and pName ~= "" and pName ~= "Unknown" and not SeenNames[pName] then
                            SeenNames[pName] = true
                            table.insert(PlayersList, {
                                Name = pName,
                                Level = 1,
                                GuildName = "None"
                            })
                        end
                    end
                end)
            end
        end)
    end

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
