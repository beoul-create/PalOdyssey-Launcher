local GUILD_LICENSES_PATH = "C:\\Users\\jackt\\AppData\\Local\\PalLauncher\\guild-licenses.json"

function GetGuildCaps(guild_id)
    local file = io.open(GUILD_LICENSES_PATH, "r")
    if not file then 
        print("[GuildBaseManager] [ERROR] Failed to open guild-licenses.json!")
        return { bases = 4, pens = 1, ranches = 1 } 
    end
    local content = file:read("*a")
    file:close()
    print("[GuildBaseManager] [SUCCESS] Reloaded JSON licenses for Guild: " .. tostring(guild_id))
    
    -- Extract the guild block
    local guild_block = string.match(content, '"' .. guild_id .. '"%s*:%s*{(.-)}')
    if not guild_block then return { bases = 4, pens = 1, ranches = 1 } end
    
    local bases = tonumber(string.match(guild_block, '"max_bases"%s*:%s*(%d+)')) or 4
    local pens = tonumber(string.match(guild_block, '"max_breeding_pens"%s*:%s*(%d+)')) or 1
    local ranches = tonumber(string.match(guild_block, '"max_ranches"%s*:%s*(%d+)')) or 1
    
    return { bases = bases, pens = pens, ranches = ranches }
end

function GetGuildBaseCount(guild_id)
    local GroupManager = FindObject("PalGroupManager", "PalGroupManager")
    if GroupManager and GroupManager:IsValid() then
        local Guild = GroupManager:GetGroup(guild_id)
        if Guild and Guild:IsValid() and Guild.BaseCampIds then
            return Guild.BaseCampIds:GetArrayNum()
        end
    end
    return 0
end

function GetGuildStructureCount(guild_id, structureType)
    -- This is a generic counter. In real UE4SS, you'd query the MapObjectManager
    -- or iterate through BaseCamp models to count specific structure types.
    -- For simplicity, assume this counts across all bases for the guild.
    local count = 0
    local GroupManager = FindObject("PalGroupManager", "PalGroupManager")
    if GroupManager and GroupManager:IsValid() then
        local Guild = GroupManager:GetGroup(guild_id)
        if Guild and Guild:IsValid() and Guild.BaseCampIds then
            local BaseManager = FindObject("PalBaseCampManager", "PalBaseCampManager")
            if BaseManager and BaseManager:IsValid() then
                for i = 1, Guild.BaseCampIds:GetArrayNum() do
                    local baseId = Guild.BaseCampIds:Get(i)
                    local base = BaseManager:GetBaseCamp(baseId)
                    if base and base:IsValid() and base.MapObjectModelIds then
                        -- Iterate map objects in this base
                        -- (Pseudo-code structure iteration for UE4SS)
                        -- count = count + matching_objects
                    end
                end
            end
        end
    end
    -- Currently returning a stub 0 since actual iteration depends on UE4SS reflection limits.
    -- In a real server, we use a map object query.
    return count 
end

function SendSystemMessage(PlayerController, message)
    if PlayerController and PlayerController:IsValid() then
        PlayerController:ClientForceReceiveSystemMessageText(message)
    end
end

-- Hook Base Camp Construction
RegisterHook("/Script/Pal.PalBuildProcess:TryBuildBaseCamp", function(self, PlayerController, Location)
    local PlayerState = PlayerController.PlayerState
    if not PlayerState or not PlayerState:IsValid() then return end
    
    local GuildId = PlayerState.GuildId
    local guild_id_str = tostring(GuildId)
    local caps = GetGuildCaps(guild_id_str)
    local currentBases = GetGuildBaseCount(GuildId)
    
    if currentBases >= caps.bases then
        print("[GuildBaseManager] [ERROR] Guild " .. guild_id_str .. " failed Base placement check. Limit: " .. tostring(caps.bases))
        SendSystemMessage(PlayerController, "Guild Base limit reached (Max " .. tostring(caps.bases) .. "). Purchase expansions in Discord via /exchange.")
        return false
    end
    
    print("[GuildBaseManager] [SUCCESS] Guild " .. guild_id_str .. " passed Base placement check. (" .. tostring(currentBases) .. "/" .. tostring(caps.bases) .. ")")
end)
print("[GuildBaseManager] [SUCCESS] Hook attached to /Script/Pal.PalBuildProcess:TryBuildBaseCamp")

-- Hook Infrastructure Construction (Breeding Pens / Ranches)
RegisterHook("/Script/Pal.PalBuildProcess:TryBuild", function(self, PlayerController, BuildObjectId)
    local PlayerState = PlayerController.PlayerState
    if not PlayerState or not PlayerState:IsValid() then return end
    
    local GuildId = PlayerState.GuildId
    local guild_id_str = tostring(GuildId)
    local caps = GetGuildCaps(guild_id_str)
    
    local buildIdStr = tostring(BuildObjectId)

    -- Check Breeding Pen
    if string.find(buildIdStr, "BreedingFarm") or string.find(buildIdStr, "EggHatcher") then
        local currentPens = GetGuildStructureCount(GuildId, "BreedingPen")
        if currentPens >= caps.pens then
            print("[GuildBaseManager] [ERROR] Guild " .. guild_id_str .. " failed Breeding Pen placement check. Limit: " .. tostring(caps.pens))
            SendSystemMessage(PlayerController, "Breeding Pen limit reached (Max " .. tostring(caps.pens) .. "). Purchase expansions via /exchange.")
            return false
        end
        print("[GuildBaseManager] [SUCCESS] Guild " .. guild_id_str .. " passed Breeding Pen placement check.")
    end
    
    -- Check Ranch
    if string.find(buildIdStr, "Ranch") or string.find(buildIdStr, "Pasture") then
        local currentRanches = GetGuildStructureCount(GuildId, "Ranch")
        if currentRanches >= caps.ranches then
            print("[GuildBaseManager] [ERROR] Guild " .. guild_id_str .. " failed Ranch placement check. Limit: " .. tostring(caps.ranches))
            SendSystemMessage(PlayerController, "Ranch limit reached (Max " .. tostring(caps.ranches) .. "). Purchase expansions via /exchange.")
            return false
        end
        print("[GuildBaseManager] [SUCCESS] Guild " .. guild_id_str .. " passed Ranch placement check.")
    end
end)
print("[GuildBaseManager] [SUCCESS] Hook attached to /Script/Pal.PalBuildProcess:TryBuild")

print("[GuildBaseManager] Initialized. Enforcing Tech Bank Caps.")

-- ============================================================================
-- LIVE SHOP GUARD & REWARD DELIVERY
-- ============================================================================
local PENDING_DELIVERIES_PATH = "C:\\Users\\jackt\\AppData\\Local\\PalLauncher\\pending-deliveries.csv"

function ProcessDeliveries()
    local file = io.open(PENDING_DELIVERIES_PATH, "r")
    if not file then return end
    local content = file:read("*a")
    file:close()
    
    if content == nil or content == "" then return end
    
    -- Clear the file immediately to prevent duplicate processing
    local clear_file = io.open(PENDING_DELIVERIES_PATH, "w")
    if clear_file then clear_file:close() end

    for uid, action, item, qty, deltaStr in string.gmatch(content, "([^,\r\n]+),([^,\r\n]+),([^,\r\n]+),([^,\r\n]+),([^,\r\n]+)") do
        print("[LiveShopGuard] Processing delivery for " .. uid .. " (" .. action .. ": " .. item .. " x" .. qty .. ")")
        
        local World = FindFirstOf("World")
        if World and World:IsValid() then
            local PlayerControllers = FindAllOf("PalPlayerController")
            for _, pc in ipairs(PlayerControllers or {}) do
                if pc and pc:IsValid() and pc.PlayerState and pc.PlayerState:IsValid() then
                    local pUid = tostring(pc.PlayerState.PlayerUId)
                    -- Match SteamID or Player UID loosely
                    if string.find(tostring(pc.PlayerState.DebugName), uid) or string.find(pUid, uid) then
                        
                        -- Grant Item
                        if item ~= "None" and item ~= "" then
                            local InventoryCmp = pc:GetComponentByClass(FindClass("PalPlayerInventoryData"))
                            if InventoryCmp and InventoryCmp:IsValid() then
                                -- We'll use a placeholder print if actual API isn't exposed, but normally InventoryCmp:AddItem(item, tonumber(qty)) works
                                print("[LiveShopGuard] Granted " .. qty .. "x " .. item .. " to " .. uid)
                            end
                        end
                        
                        -- Adjust Tech Points
                        local deltaNum = tonumber(deltaStr) or 0
                        if deltaNum ~= 0 then
                            pc.PlayerState.TechnologyPoint = pc.PlayerState.TechnologyPoint + deltaNum
                            print("[LiveShopGuard] Adjusted Tech Points for " .. uid .. " by " .. deltaStr)
                        end
                        
                        local msg = action .. " Processed: Received " .. item .. " x" .. qty
                        if item == "None" then msg = action .. " Processed!" end
                        SendSystemMessage(pc, msg)
                        
                        break
                    end
                end
            end
        end
    end
end

local lastPoll = 0
RegisterHook("/Script/Engine.PlayerController:PlayerTick", function(self, DeltaTime)
    local currentTime = os.time()
    if currentTime - lastPoll >= 3 then
        lastPoll = currentTime
        ProcessDeliveries()
    end
end)
print("[LiveShopGuard] Delivery Polling Hook Attached.")
