-- QuickDeposit: Hotkey to automatically deposit matching items into nearby base chests
local ok, Config = pcall(require, "config")
if not ok or type(Config) ~= "table" then
    Config = {
        enabled = true,
        depositKey = "G",
        depositRadius = 1500.0,
        notifyOnDeposit = true,
        log = true
    }
end

local function Log(msg)
    if Config.log then
        print(string.format("[QuickDeposit] %s\n", tostring(msg)))
    end
end

if not Config.enabled then return end

local function DepositMatchingItems()
    pcall(function()
        local player = GetPlayerController()
        if not player or not player:IsValid() then return end
        local pawn = player.Pawn
        if not pawn or not pawn:IsValid() then return end

        local playerLoc = pawn:K2_GetActorLocation()
        if not playerLoc then return end

        local mapObjects = FindAllOf("PalMapObject")
        if not mapObjects then return end

        local chestCount = 0
        local transferredItems = 0

        for _, obj in ipairs(mapObjects) do
            if obj and obj:IsValid() then
                local objLoc = obj:K2_GetActorLocation()
                if objLoc then
                    local dx = objLoc.X - playerLoc.X
                    local dy = objLoc.Y - playerLoc.Y
                    local dz = objLoc.Z - playerLoc.Z
                    local dist = math.sqrt(dx * dx + dy * dy + dz * dz)

                    if dist <= (Config.depositRadius or 1500.0) then
                        -- Check if object has container / storage component
                        pcall(function()
                            local containerModule = obj:GetComponentByClass(StaticFindObject("/Script/Pal.PalMapObjectItemContainerModule"))
                            if containerModule and containerModule:IsValid() then
                                chestCount = chestCount + 1
                                -- Trigger auto-stack request
                                if containerModule.RequestAutoStackFromPlayer then
                                    containerModule:RequestAutoStackFromPlayer(player)
                                    transferredItems = transferredItems + 1
                                end
                            end
                        end)
                    end
                end
            end
        end

        Log(string.format("Scanned %d nearby chests for quick-deposit.", chestCount))
    end)
end

-- Register Keybind
pcall(function()
    local keyName = Config.depositKey or "G"
    local k = Key[keyName] or Key.G
    RegisterKeyBind(k, function()
        DepositMatchingItems()
    end)
    Log(string.format("Registered QuickDeposit hotkey [%s]", keyName))
end)

Log("QuickDeposit loaded successfully.")
