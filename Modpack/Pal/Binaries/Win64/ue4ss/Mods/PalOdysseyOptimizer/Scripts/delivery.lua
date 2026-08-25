-- ============================================================================
-- PalOdysseyOptimizer - Live Delivery & Tech Points Synchronization Module
-- ============================================================================

local DeliveryModule = {}

local function log(msg)
    print(string.format("[PalOdysseyLive] %s\n", tostring(msg)))
end

local function fmtGuid(g)
    if g == nil then return nil end
    local ok, str = pcall(function()
        return string.format("%08X%08X%08X%08X", g.A, g.B, g.C, g.D)
    end)
    return ok and str or nil
end

local function cleanStr(s)
    if not s then return "" end
    return string.upper(string.gsub(string.gsub(tostring(s), "-", ""), " ", ""))
end

local function getQueueFilePaths()
    return {
        "ue4ss/Mods/PalOdysseyOptimizer/pending-deliveries.csv",
        "Mods/PalOdysseyOptimizer/pending-deliveries.csv",
        "pending-deliveries.csv",
        "Pal/Binaries/Win64/ue4ss/Mods/PalOdysseyOptimizer/pending-deliveries.csv"
    }
end

local function findQueueFile()
    for _, path in ipairs(getQueueFilePaths()) do
        local ok, f = pcall(io.open, path, "r")
        if ok and f then
            f:close()
            return path
        end
    end
    return "Mods/PalOdysseyOptimizer/pending-deliveries.csv"
end

local function processQueue()
    local qPath = findQueueFile()
    local okOpen, f = pcall(io.open, qPath, "r")
    if not okOpen or not f then return end

    local lines = {}
    for line in f:lines() do
        if line and line:match("%S") then
            table.insert(lines, line)
        end
    end
    f:close()

    if #lines == 0 then return end

    local okFind, controllers = pcall(FindAllOf, "PalPlayerController")
    if not okFind or not controllers or #controllers == 0 then return end

    local palUtil = nil
    pcall(function()
        palUtil = StaticFindObject("/Script/Pal.Default__PalUtility")
    end)

    local remainingLines = {}
    local processedAny = false

    for _, line in ipairs(lines) do
        local parts = {}
        for part in string.gmatch(line, "([^,]+)") do
            table.insert(parts, part)
        end

        if #parts >= 5 then
            local targetUid = cleanStr(parts[1])
            local action = parts[2]
            local itemCode = parts[3]
            local quantity = tonumber(parts[4]) or 1
            local techPointsDelta = tonumber(parts[5]) or 0

            local delivered = false

            for _, controller in ipairs(controllers) do
                if controller and controller:IsValid() then
                    local pGuid = ""
                    pcall(function()
                        pGuid = fmtGuid(controller:GetPlayerUId()) or ""
                    end)
                    local cleanPGuid = cleanStr(pGuid)

                    local pName = ""
                    local ps = nil
                    pcall(function()
                        ps = controller.PlayerState
                        if ps and ps:IsValid() and ps.PlayerName then
                            pName = cleanStr(ps.PlayerName:ToString())
                        end
                    end)

                    local isMatch = false
                    if cleanPGuid ~= "" and (cleanPGuid == targetUid or string.find(cleanPGuid, targetUid, 1, true) or string.find(targetUid, cleanPGuid, 1, true)) then
                        isMatch = true
                    elseif pName ~= "" and (pName == targetUid or string.find(targetUid, pName, 1, true)) then
                        isMatch = true
                    elseif #controllers == 1 and (targetUid == "DEFAULT" or string.find(targetUid, "7656", 1, true)) then
                        isMatch = true
                    end

                    if isMatch and ps and ps:IsValid() then
                        -- 1. Apply Technology Points Delta
                        if techPointsDelta ~= 0 then
                            pcall(function()
                                if ps.UnusedTechnologyPoint ~= nil then
                                    local cur = ps.UnusedTechnologyPoint
                                    local updated = math.max(0, cur + techPointsDelta)
                                    ps.UnusedTechnologyPoint = updated
                                    log(string.format("Synced Technology Points for player %s: %d -> %d (%+d)", targetUid, cur, updated, techPointsDelta))
                                end
                            end)
                            pcall(function()
                                if ps.RecordData and ps.RecordData:IsValid() and ps.RecordData.UnusedTechnologyPoint ~= nil then
                                    local cur = ps.RecordData.UnusedTechnologyPoint
                                    local updated = math.max(0, cur + techPointsDelta)
                                    ps.RecordData.UnusedTechnologyPoint = updated
                                end
                            end)
                        end

                        -- 2. Send In-Game System Notification / Chat
                        if palUtil and palUtil:IsValid() then
                            pcall(function()
                                local msg = ""
                                local pts = ps.UnusedTechnologyPoint or 0
                                if action == "Gacha" then
                                    msg = string.format("🎰 [Gacha] Deducted %d Tech Points. Balance: %d pts", math.abs(techPointsDelta), pts)
                                elseif action == "Exchange" then
                                    msg = string.format("🎟️ [Shop] Deducted %d Tech Points. Purchased %dx %s. Balance: %d pts", math.abs(techPointsDelta), quantity, itemCode, pts)
                                elseif action == "Recycle" then
                                    msg = string.format("♻️ [Recycle] Gained +%d Tech Points! Balance: %d pts", techPointsDelta, pts)
                                elseif action == "Withdraw" or action == "Claim" then
                                    msg = string.format("📦 [Vault Delivery] Claimed %dx %s into your inventory!", quantity, itemCode)
                                end
                                if msg ~= "" then
                                    palUtil:SendSystemToPlayerChat(controller, msg, { controller:GetPlayerUId() })
                                end
                            end)
                        end

                        delivered = true
                        processedAny = true
                        break
                    end
                end
            end

            if not delivered then
                table.insert(remainingLines, line)
            end
        end
    end

    if processedAny then
        local okWrite, fOut = pcall(io.open, qPath, "w")
        if okWrite and fOut then
            for _, rem in ipairs(remainingLines) do
                fOut:write(rem .. "\n")
            end
            fOut:close()
        end
    end
end

function DeliveryModule.apply()
    log("Initializing Live Economy & Tech Points Synchronization Engine...")

    -- Poll every 1.5 seconds for instant in-game updates
    LoopAsync(1500, function()
        pcall(processQueue)
        return false -- keep looping indefinitely
    end)

    log("Live Economy & Tech Points Synchronization Engine Active.")
end

return DeliveryModule
