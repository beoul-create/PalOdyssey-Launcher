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
        local a = (g.A or 0) & 0xFFFFFFFF
        local b = (g.B or 0) & 0xFFFFFFFF
        local c = (g.C or 0) & 0xFFFFFFFF
        local d = (g.D or 0) & 0xFFFFFFFF
        return string.format("%08X%08X%08X%08X", a, b, c, d)
    end)
    if not ok or str == "00000000000000000000000000000000" then return nil end
    return str
end

local function cleanStr(s)
    if not s then return "" end
    return string.upper(string.gsub(string.gsub(tostring(s), "-", ""), " ", ""))
end

local function getQueueFilePaths()
    local paths = {
        "ue4ss/Mods/PalOdysseyOptimizer/pending-deliveries.csv",
        "Mods/PalOdysseyOptimizer/pending-deliveries.csv",
        "pending-deliveries.csv",
        "Pal/Binaries/Win64/ue4ss/Mods/PalOdysseyOptimizer/pending-deliveries.csv"
    }
    local localApp = os.getenv("LOCALAPPDATA")
    if localApp then
        table.insert(paths, localApp .. "/PalLauncher/pending-deliveries.csv")
        table.insert(paths, localApp .. "\\PalLauncher\\pending-deliveries.csv")
        table.insert(paths, localApp .. "/Pal/Saved/Config/Windows/pending-deliveries.csv")
        table.insert(paths, localApp .. "\\Pal\\Saved\\Config\\Windows\\pending-deliveries.csv")
    end
    return paths
end

local cachedQueuePath = nil
local function findQueueFile()
    if cachedQueuePath then return cachedQueuePath end
    for _, path in ipairs(getQueueFilePaths()) do
        local ok, f = pcall(io.open, path, "r")
        if ok and f then
            f:close()
            cachedQueuePath = path
            return path
        end
    end
    cachedQueuePath = "Mods/PalOdysseyOptimizer/pending-deliveries.csv"
    return cachedQueuePath
end

local function is_dedicated_server_process()
    local command = string.lower(tostring(os.getenv("CMDCMDLINE") or ""))
    if string.find(command, "dedicated", 1, true) or string.find(command, "palserver", 1, true) then
        return true
    end
    local source = debug.getinfo(1, "S").source:lower():gsub("\\", "/")
    if string.find(source, "/palserver/") ~= nil then
        return true
    end
    local ok, engine = pcall(function() return FindFirstOf("GameEngine") end)
    if ok and engine ~= nil then
        local ok_net, net_mode = pcall(function() return engine.NetMode end)
        if ok_net and type(net_mode) == "number" and net_mode == 3 then
            return true
        end
    end
    return false
end

local function exportLivePlayerData()
    if not is_dedicated_server_process() then return end
    local players = {}

    local function processPlayerState(ps, controller)
        if not ps or not ps:IsValid() then return end

        local pGuid = nil
        pcall(function()
            if controller and controller:IsValid() then
                pGuid = fmtGuid(controller:GetPlayerUId())
            end
        end)
        if not pGuid then
            pcall(function() pGuid = fmtGuid(ps.PlayerUId) end)
        end
        if not pGuid then
            pcall(function() pGuid = fmtGuid(ps:GetPlayerUId()) end)
        end
        if not pGuid then
            pcall(function()
                if ps.IndividualHandleId and ps.IndividualHandleId.PlayerUId then
                    pGuid = fmtGuid(ps.IndividualHandleId.PlayerUId)
                end
            end)
        end

        local cleanPGuid = cleanStr(pGuid)
        if cleanPGuid == "" or cleanPGuid == "00000000000000000000000000000000" then return end

        local pName = ""
        pcall(function()
            if ps.PlayerName then pName = ps.PlayerName:ToString() end
            if pName == "" and ps.GetPlayerName then pName = ps:GetPlayerName():ToString() end
        end)

        local techPts = 0
        local bossPts = 0
        local lvl = 1

        pcall(function()
            if ps.UnusedTechnologyPoint ~= nil then techPts = ps.UnusedTechnologyPoint end
        end)
        pcall(function()
            if techPts == 0 and ps.RecordData and ps.RecordData.UnusedTechnologyPoint ~= nil then
                techPts = ps.RecordData.UnusedTechnologyPoint
            end
        end)

        pcall(function()
            if ps.UnusedBossTechnologyPoint ~= nil then bossPts = ps.UnusedBossTechnologyPoint end
        end)
        pcall(function()
            if bossPts == 0 and ps.RecordData and ps.RecordData.UnusedBossTechnologyPoint ~= nil then
                bossPts = ps.RecordData.UnusedBossTechnologyPoint
            end
        end)

        pcall(function()
            if ps.GetLevel then lvl = ps:GetLevel() end
        end)

        players[cleanPGuid] = {
            playerUid = cleanPGuid,
            playerName = pName,
            unusedTechnologyPoints = techPts,
            unusedBossTechnologyPoints = bossPts,
            level = lvl
        }
    end

    -- Check Player Controllers
    local okFindC, controllers = pcall(FindAllOf, "PalPlayerController")
    if okFindC and controllers then
        for _, c in ipairs(controllers) do
            if c and c:IsValid() then
                local ps = nil
                pcall(function() ps = c.PlayerState end)
                if ps then processPlayerState(ps, c) end
            end
        end
    end

    -- Check Player States directly
    local okFindS, states = pcall(FindAllOf, "PalPlayerState")
    if okFindS and states then
        for _, s in ipairs(states) do
            if s and s:IsValid() then
                processPlayerState(s, nil)
            end
        end
    end

    local candidatePaths = {
        "ue4ss/Mods/PalOdysseyOptimizer/live-players.json",
        "Mods/PalOdysseyOptimizer/live-players.json",
        "live-players.json",
        "Pal/Binaries/Win64/ue4ss/Mods/PalOdysseyOptimizer/live-players.json"
    }

    local entries = {}
    for k, v in pairs(players) do
        table.insert(entries, string.format('"%s":{"playerUid":"%s","playerName":"%s","unusedTechnologyPoints":%d,"unusedBossTechnologyPoints":%d,"level":%d}',
            k, v.playerUid, v.playerName:gsub('"', '\\"'), v.unusedTechnologyPoints, v.unusedBossTechnologyPoints, v.level))
    end
    local jsonStr = string.format('{"timestamp":%d,"players":{%s}}', os.time(), table.concat(entries, ","))

    for _, path in ipairs(candidatePaths) do
        local okW, fW = pcall(io.open, path, "w")
        if okW and fW then
            fW:write(jsonStr)
            fW:close()
        end
    end
end

local function resolveStaticItemId(name)
    if not name then return "DogCoin" end
    local clean = string.upper(string.gsub(string.gsub(tostring(name), "-", ""), " ", ""))
    
    local map = {
        ["DOGCOIN"] = "DogCoin",
        ["DOGCOIN(X2)"] = "DogCoin",
        ["DOGCOINX2"] = "DogCoin",
        ["MEMORYRESETDRUG"] = "Drug_ResetStatusPoint",
        ["MEMORYRESETDRUG/STATELIXIR"] = "Drug_ResetStatusPoint",
        ["STATELIXIR"] = "Drug_ResetStatusPoint",
        ["POWERFRUIT"] = "Fruit_Attack",
        ["HEALTHFRUIT"] = "Fruit_HP",
        ["STAMINAFRUIT"] = "Fruit_SP",
        ["SKILLFRUITCHESTT3"] = "SkillUnlock_Fire_03",
        ["SKILLFRUITCHEST"] = "SkillUnlock_Fire_03",
        ["ANCIENTRELICBOX"] = "AncientParts",
        ["ANCIENTCIVPARTS"] = "AncientParts",
        ["RAIDSLAB"] = "BossSpecialDrop",
        ["RELICMYSTERYBOX"] = "AncientParts"
    }

    if map[clean] then return map[clean] end
    return name
end

local function grantPlayerItem(controller, ps, rawItemName, qty)
    local itemId = resolveStaticItemId(rawItemName)
    local amount = math.max(1, tonumber(qty) or 1)
    local granted = false

    -- 1. Try PalPlayerInventoryData directly on Controller or PlayerState
    pcall(function()
        local inv = nil
        if controller.GetPalPlayerInventoryData then
            inv = controller:GetPalPlayerInventoryData()
        end
        if not inv then
            inv = controller.InventoryData or (ps and ps.InventoryData)
        end

        if inv and inv:IsValid() then
            if inv.AddItem then
                inv:AddItem(FName(itemId), amount, true)
                granted = true
            elseif inv.TryAddItem then
                inv:TryAddItem(FName(itemId), amount)
                granted = true
            elseif inv.RequestAddItem then
                inv:RequestAddItem(FName(itemId), amount)
                granted = true
            end

            -- Try specific sub-containers (Normal, Common, Essential)
            if not granted then
                pcall(function()
                    if inv.NormalInventory and inv.NormalInventory:IsValid() and inv.NormalInventory.AddItem then
                        inv.NormalInventory:AddItem(FName(itemId), amount)
                        granted = true
                    elseif inv.CommonContainer and inv.CommonContainer:IsValid() and inv.CommonContainer.AddItem then
                        inv.CommonContainer:AddItem(FName(itemId), amount)
                        granted = true
                    elseif inv.EssentialInventory and inv.EssentialInventory:IsValid() and inv.EssentialInventory.AddItem then
                        inv.EssentialInventory:AddItem(FName(itemId), amount)
                        granted = true
                    end
                end)
            end
        end
    end)

    -- 2. Try PalUtility engine functions
    if not granted then
        pcall(function()
            local palUtil = StaticFindObject("/Script/Pal.Default__PalUtility")
            if palUtil and palUtil:IsValid() then
                if palUtil.GrantItem then
                    palUtil:GrantItem(controller, FName(itemId), amount)
                    granted = true
                elseif palUtil.AddPlayerItem then
                    palUtil:AddPlayerItem(controller, FName(itemId), amount)
                    granted = true
                elseif palUtil.GrantPlayerItem then
                    palUtil:GrantPlayerItem(controller, FName(itemId), amount)
                    granted = true
                end
            end
        end)
    end

    -- 3. Try Character Pawn
    if not granted then
        pcall(function()
            local pawn = controller:GetPawn()
            if pawn and pawn:IsValid() then
                if pawn.AddItem then
                    pawn:AddItem(FName(itemId), amount)
                    granted = true
                elseif pawn.InventoryComponent and pawn.InventoryComponent:IsValid() and pawn.InventoryComponent.AddItem then
                    pawn.InventoryComponent:AddItem(FName(itemId), amount)
                    granted = true
                end
            end
        end)
    end

    log(string.format("Item delivery attempt for '%s' (StaticId: '%s', Qty: %d) -> Result: %s", tostring(rawItemName), itemId, amount, tostring(granted)))
    return granted
end

local processedDeliveryCache = {}
local lastPlayerExport = 0

local function processQueue()
    -- Object enumeration plus four telemetry writes is the expensive part of
    -- this loop. Five-second data does not require doing that on every queue poll.
    local now = os.time()
    if is_dedicated_server_process() and (now - lastPlayerExport >= 30) then
        pcall(exportLivePlayerData)
        lastPlayerExport = now
    end

    local qPath = findQueueFile()
    local processingPath = qPath .. ".processing"
    local f = io.open(processingPath, "r")
    if not f then
        local claimed = os.rename(qPath, processingPath)
        if not claimed then return end
        f = io.open(processingPath, "r")
    end
    local okOpen = f ~= nil
    if not okOpen or not f then return end

    local lines = {}
    for line in f:lines() do
        if line and line:match("%S") then
            table.insert(lines, line)
        end
    end
    f:close()

    if #lines == 0 then os.remove(processingPath); return end

    local function Requeue(pending)
        if #pending == 0 then return true end
        local fOut = io.open(qPath, "a")
        if not fOut then return false end
        for _, pendingLine in ipairs(pending) do fOut:write(pendingLine .. "\n") end
        fOut:flush()
        fOut:close()
        return true
    end

    -- Find all Player States and Controllers across dedicated server & client
    local targets = {}
    local seenState = {}

    local okFindS, states = pcall(FindAllOf, "PalPlayerState")
    if okFindS and states then
        for _, ps in ipairs(states) do
            if ps and ps:IsValid() and not seenState[ps] then
                seenState[ps] = true
                table.insert(targets, { ps = ps, controller = nil })
            end
        end
    end

    local okFindC, controllers = pcall(FindAllOf, "PalPlayerController")
    if okFindC and controllers then
        for _, c in ipairs(controllers) do
            if c and c:IsValid() then
                local ps = nil
                pcall(function() ps = c.PlayerState end)
                if ps and ps:IsValid() then
                    if not seenState[ps] then
                        seenState[ps] = true
                        table.insert(targets, { ps = ps, controller = c })
                    else
                        for _, t in ipairs(targets) do
                            if t.ps == ps and not t.controller then
                                t.controller = c
                                break
                            end
                        end
                    end
                else
                    table.insert(targets, { ps = nil, controller = c })
                end
            end
        end
    end

    if #targets == 0 then
        -- Player states not loaded yet, preserve lines in queue
        if Requeue(lines) then os.remove(processingPath) end
        return
    end

    local palUtil = nil
    pcall(function()
        palUtil = StaticFindObject("/Script/Pal.Default__PalUtility")
    end)

    local remainingLines = {}
    local processedAny = false

    local function applyPointsDirectly(ps, techPts, isTechSet, bossPts, isBossSet)
        if not ps or not ps:IsValid() then return end

        if isTechSet and techPts ~= nil then
            pcall(function() ps.UnusedTechnologyPoint = techPts end)
            pcall(function()
                if ps.RecordData then
                    ps.RecordData.UnusedTechnologyPoint = techPts
                end
            end)
            pcall(function()
                if ps.TechnologyData and ps.TechnologyData:IsValid() then
                    ps.TechnologyData.UnusedTechnologyPoint = techPts
                    ps.TechnologyData.TechnologyPoint = techPts
                end
            end)
            pcall(function()
                if ps.GetTechnologyData then
                    local td = ps:GetTechnologyData()
                    if td and td:IsValid() then
                        td.UnusedTechnologyPoint = techPts
                    end
                end
            end)
            pcall(function()
                if ps.SetTechnologyPoint then ps:SetTechnologyPoint(techPts) end
            end)
            pcall(function()
                if ps.AddTechnologyPoint then ps:AddTechnologyPoint(0) end
            end)
        end

        if isBossSet and bossPts ~= nil then
            pcall(function() ps.UnusedBossTechnologyPoint = bossPts end)
            pcall(function() ps.BossTechnologyPoint = bossPts end)
            pcall(function()
                if ps.RecordData then
                    ps.RecordData.UnusedBossTechnologyPoint = bossPts
                end
            end)
            pcall(function()
                if ps.TechnologyData and ps.TechnologyData:IsValid() then
                    ps.TechnologyData.UnusedBossTechnologyPoint = bossPts
                    ps.TechnologyData.BossTechnologyPoint = bossPts
                end
            end)
            pcall(function()
                if ps.GetTechnologyData then
                    local td = ps:GetTechnologyData()
                    if td and td:IsValid() then
                        td.UnusedBossTechnologyPoint = bossPts
                    end
                end
            end)
            pcall(function()
                if ps.SetBossTechnologyPoint then ps:SetBossTechnologyPoint(bossPts) end
            end)
            pcall(function()
                if ps.AddBossTechnologyPoint then ps:AddBossTechnologyPoint(0) end
            end)
        end
    end

    for _, line in ipairs(lines) do
        if not processedDeliveryCache[line] then
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

            for _, target in ipairs(targets) do
                local ps = target.ps
                local controller = target.controller

                local pGuid = ""
                pcall(function()
                    if controller and controller:IsValid() then
                        pGuid = fmtGuid(controller:GetPlayerUId()) or ""
                    end
                end)
                if pGuid == "" and ps and ps:IsValid() then
                    pcall(function() pGuid = fmtGuid(ps.PlayerUId) or "" end)
                end
                if pGuid == "" and ps and ps:IsValid() and ps.GetPlayerUId then
                    pcall(function() pGuid = fmtGuid(ps:GetPlayerUId()) or "" end)
                end
                local cleanPGuid = cleanStr(pGuid)

                local pName = ""
                if ps and ps:IsValid() and ps.PlayerName then
                    pcall(function() pName = cleanStr(ps.PlayerName:ToString()) end)
                end
                if pName == "" and ps and ps:IsValid() and ps.GetPlayerName then
                    pcall(function() pName = cleanStr(ps:GetPlayerName():ToString()) end)
                end

                local isMatch = false
                if cleanPGuid ~= "" and (cleanPGuid == targetUid or string.find(cleanPGuid, targetUid, 1, true) or string.find(targetUid, cleanPGuid, 1, true)) then
                    isMatch = true
                elseif pName ~= "" and (pName == targetUid or string.find(targetUid, pName, 1, true)) then
                    isMatch = true
                elseif #targets == 1 and (targetUid == "DEFAULT" or string.find(targetUid, "7656", 1, true)) then
                    isMatch = true
                end

                if isMatch and ps and ps:IsValid() then
                    -- 1. Grant items if applicable (Withdraw / Claim / Exchange)
                    if action == "Withdraw" or action == "Claim" or action == "Exchange" then
                        if itemCode and itemCode ~= "None" and itemCode ~= "TechnologyPoints" and itemCode ~= "AncientBossPoints" and itemCode ~= "TechPointConversion" and itemCode ~= "RelicMysteryBox" and itemCode ~= "AncientRelicBox" then
                            if controller then
                                grantPlayerItem(controller, ps, itemCode, quantity)
                            end
                        end
                    end

                    -- 2. Apply Technology Points / Boss Points Modifications
                    if action == "SetTechPoints" or action == "SetPoints" then
                        local newPoints = math.max(0, techPointsDelta)
                        applyPointsDirectly(ps, newPoints, true, nil, false)
                        log(string.format("Directly set Technology Points for player %s to %d in active RAM", targetUid, newPoints))
                    elseif action == "SetBossPoints" then
                        local newPoints = math.max(0, techPointsDelta)
                        applyPointsDirectly(ps, nil, false, newPoints, true)
                        log(string.format("Directly set Boss Technology Points for player %s to %d in active RAM", targetUid, newPoints))
                    elseif action == "GrantBossPoints" or action == "AddBossPoints" then
                        local cur = ps.UnusedBossTechnologyPoint or 0
                        local updated = math.max(0, cur + techPointsDelta)
                        applyPointsDirectly(ps, nil, false, updated, true)
                        log(string.format("Granted Boss Points to player %s in active RAM: %+d -> %d", targetUid, techPointsDelta, updated))
                    elseif action == "DeductBossPoints" or action == "AncientGacha" or action == "AncientExchange" or action == "AncientPerk" then
                        local cur = ps.UnusedBossTechnologyPoint or 0
                        local delta = techPointsDelta < 0 and techPointsDelta or -math.abs(techPointsDelta)
                        local updated = math.max(0, cur + delta)
                        applyPointsDirectly(ps, nil, false, updated, true)
                        log(string.format("Deducted Boss Points from player %s in active RAM: %+d -> %d", targetUid, techPointsDelta, updated))
                    elseif techPointsDelta ~= 0 then
                        local cur = ps.UnusedTechnologyPoint or (ps.RecordData and ps.RecordData.UnusedTechnologyPoint) or 0
                        local updated = math.max(0, cur + techPointsDelta)
                        applyPointsDirectly(ps, updated, true, nil, false)
                        log(string.format("Synced Technology Points for player %s in active RAM: %d -> %d (%+d)", targetUid, cur, updated, techPointsDelta))
                    end

                        -- 2. Send In-Game System Notification / Chat safely deferred onto GameThread
                        local msg = ""
                        local pts = (ps and ps.UnusedTechnologyPoint) or 0
                        local bossPts = (ps and ps.UnusedBossTechnologyPoint) or 0
                        if action == "SetTechPoints" or action == "SetPoints" then
                            msg = string.format("⚡ [Admin] Your Technology Points balance has been set to: %d pts", pts)
                        elseif action == "SetBossPoints" then
                            msg = string.format("🔮 [Admin] Your Ancient Boss Points balance has been set to: %d pts", bossPts)
                        elseif action == "GrantTechPoints" or action == "AddTechPoints" then
                            msg = string.format("🪙 [Admin] Received %+d Technology Points! New balance: %d pts", techPointsDelta, pts)
                        elseif action == "GrantBossPoints" or action == "AddBossPoints" then
                            msg = string.format("🔮 [Admin] Received %+d Ancient Boss Points! New balance: %d pts", techPointsDelta, bossPts)
                        elseif action == "Gacha" then
                            if itemCode == "AncientRelicBox" then
                                msg = string.format("🔮 [Ancient Gacha] Opened %dx Ancient Relic Box! Rewards credited to Virtual Vault.", quantity)
                            else
                                msg = string.format("🎰 [Gacha] Opened %dx Mystery Box (Deducted %d Tech Pts). Balance: %d pts", quantity, math.abs(techPointsDelta), pts)
                            end
                        elseif action == "Transmute" then
                            msg = string.format("⚗️ [Transmute] Converted Ancient Points ➔ +%d Standard Tech Points! New Balance: %d pts", techPointsDelta, pts)
                        elseif action == "Perk" then
                            if itemCode == "move_speed" or itemCode == "speed" or itemCode == "swift" then
                                msg = string.format("🏃 [Guild Perk] Guild Swift Strider Speed upgraded! Movement & sprint speed increased globally.")
                            else
                                msg = string.format("🏰 [Perk] Server Perk upgraded! Active bonuses increased.")
                            end
                        elseif action == "Exchange" then
                            if itemCode == "SwiftLotus" then
                                msg = string.format("🪽 [Ancient Shop] Acquired Swift Lotus (+5%% Permanent Movement Speed)! Check your Virtual Vault or inventory.", quantity)
                            elseif techPointsDelta < 0 then
                                msg = string.format("🎟️ [Shop] Deducted %d Tech Points. Purchased %dx %s. Balance: %d pts", math.abs(techPointsDelta), quantity, itemCode, pts)
                            else
                                msg = string.format("🔮 [Ancient Shop] Purchased %dx %s with Ancient Points! Items credited to Virtual Vault.", quantity, itemCode)
                            end
                        elseif action == "Recycle" then
                            msg = string.format("♻️ [Recycle] Gained +%d Tech Points! Balance: %d pts", techPointsDelta, pts)
                        elseif action == "Withdraw" or action == "Claim" then
                            if itemCode == "SwiftLotus" then
                                msg = string.format("🪽 [Vault Delivery] Claimed %dx Swift Lotus (+5%% Speed) into your inventory!", quantity)
                            else
                                msg = string.format("📦 [Vault Delivery] Claimed %dx %s into your inventory!", quantity, itemCode)
                            end
                        end

                        if msg ~= "" and controller and controller:IsValid() then
                            local cRef = controller
                            local sendAction = function()
                                pcall(function()
                                    if cRef and cRef:IsValid() then
                                        local chatSub = FindFirstOf("PalChatSubsystem")
                                        if chatSub and chatSub:IsValid() then
                                            chatSub:SendSystemChatMessage(cRef, FText(msg))
                                            return
                                        end
                                        local palUtil = StaticFindObject("/Script/Pal.Default__PalUtility")
                                        if palUtil and palUtil:IsValid() then
                                            palUtil:SendSystemAnnounce(cRef, FText(msg))
                                        end
                                    end
                                end)
                            end

                            if type(_G.ExecuteInGameThreadWithDelay) == "function" then
                                pcall(_G.ExecuteInGameThreadWithDelay, 100, sendAction)
                            elseif type(_G.ExecuteWithDelay) == "function" then
                                pcall(_G.ExecuteWithDelay, 100, sendAction)
                            else
                                sendAction()
                            end
                        end

                        delivered = true
                        processedAny = true
                        processedDeliveryCache[line] = true
                        break
                    end
                end
            end

            if not delivered then
                table.insert(remainingLines, line)
            else
                processedDeliveryCache[line] = true
            end
        end
    end

    if Requeue(remainingLines) then os.remove(processingPath) end
end

function DeliveryModule.apply()
    log("Initializing Live Economy & Tech Points Synchronization Engine...")

    -- Keep deliveries responsive without continuously hitting the filesystem.
    if type(LoopInGameThreadWithDelay) == "function" then
        LoopInGameThreadWithDelay(10000, function() pcall(processQueue) end)
    else
        LoopAsync(10000, function()
            if type(ExecuteInGameThread) == "function" then ExecuteInGameThread(function() pcall(processQueue) end)
            else pcall(processQueue) end
            return false
        end)
    end

    log("Live Economy & Tech Points Synchronization Engine Active.")
end

return DeliveryModule
