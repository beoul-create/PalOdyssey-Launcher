local MOD = "TechPointShopBridge"
local SCRIPT_DIR = debug.getinfo(1, "S").source:gsub("^@", ""):gsub("[^/\\]+$", "")

local okConfig, Config = pcall(dofile, SCRIPT_DIR .. "../config.lua")
if not okConfig or type(Config) ~= "table" then
    print("[" .. MOD .. "] ERROR: config.lua could not be loaded: " .. tostring(Config))
    return
end
if Config.enabled ~= true then
    print("[" .. MOD .. "] Disabled in config.lua")
    return
end

local TOKEN_ID = tostring(Config.currencyItemId or "PalOdyssey_TechPointToken")
local SETUP_HOOK = "/Script/Pal.PalNetworkShopComponent:SetupShopDataForActor_ToServer"
local BUY_HOOK = "/Script/Pal.PalNetworkShopComponent:RequestBuyProduct_ToServer"
local SELL_HOOK = "/Script/Pal.PalNetworkShopComponent:RequestSellItems_ToServer"

-- Only Alpha Boss drops, Ancient Relics, and Precious Stones award Technology Points
local BOSS_DROPS = {
    AncientCore = 5,
    PalItem_AncientCore = 5,
    AncientParts = 1,
    PalItem_AncientParts = 1,
    PreciousDragonStone_03 = 6,
    PalItem_PreciousDragonStone_03 = 6,
    PreciousDragonStone_02 = 4,
    PalItem_PreciousDragonStone_02 = 4,
    PreciousDragonStone_01 = 2,
    PalItem_PreciousDragonStone_01 = 2,
    PreciousPelt_03 = 3,
    PalItem_PreciousPelt_03 = 3,
    PreciousPelt_02 = 2,
    PalItem_PreciousPelt_02 = 2,
    PreciousPelt_01 = 1,
    PalItem_PreciousPelt_01 = 1,
    PreciousClaw_03 = 3,
    PalItem_PreciousClaw_03 = 3,
    PreciousClaw_02 = 2,
    PalItem_PreciousClaw_02 = 2,
    PreciousClaw_01 = 1,
    PalItem_PreciousClaw_01 = 1,
    PreciousFang_03 = 3,
    PalItem_PreciousFang_03 = 3,
    PreciousFang_02 = 2,
    PalItem_PreciousFang_02 = 2,
    PreciousFang_01 = 1,
    PalItem_PreciousFang_01 = 1,
    PalUpgradeStone3 = 2,
    PalUpgradeStone2 = 1,
    PalUpgradeStone1 = 1,
    TechnologyBook_G3 = 8,
    PalItem_TechnologyBook_G3 = 8,
    TechnologyBook_G2 = 4,
    PalItem_TechnologyBook_G2 = 4,
    TechnologyBook_G1 = 2,
    PalItem_TechnologyBook_G1 = 2,
    AncientTechnologyPointBook = 5,
    PalItem_AncientTechnologyPointBook = 5,
    AncientTechnologyBook_G1 = 5
}

-- State is keyed by the server-owned network shop component. Nothing supplied
-- by the client is trusted for player identity or balance.
local sessions = {}
local consumeHelper = nil

local function log(message, force)
    if force or Config.diagnostics == true then
        print("[" .. MOD .. "] " .. tostring(message))
    end
end

local function unwrap(value)
    if value == nil then return nil end
    local ok, result = pcall(function()
        if type(value.get) == "function" then return value:get() end
        return value
    end)
    return ok and result or value
end

local function alive(value)
    if value == nil then return false end
    local ok, result = pcall(function()
        return type(value.IsValid) ~= "function" or value:IsValid()
    end)
    return ok and result ~= false
end

local function objectKey(value)
    local obj = unwrap(value)
    local ok, address = pcall(function() return obj:GetAddress() end)
    if ok and address then return tostring(address) end
    return tostring(obj)
end

local function isAuthority(component)
    local ok, result = pcall(function()
        local transmitter = component:GetOwner()
        return alive(transmitter) and transmitter:HasAuthority()
    end)
    return ok and result == true
end

local function getPlayerController(component)
    local controller = nil
    pcall(function()
        local transmitter = component:GetOwner()
        if not alive(transmitter) then return end

        local owner = transmitter:GetOwner()
        if alive(owner) and owner.PlayerState then controller = owner return end

        local instigatorController = transmitter:GetInstigatorController()
        if alive(instigatorController) and instigatorController.PlayerState then
            controller = instigatorController
            return
        end

        if alive(transmitter.Owner) and transmitter.Owner.PlayerState then
            controller = transmitter.Owner
        end
    end)
    return controller
end

local function getPlayerData(component)
    local controller = getPlayerController(component)
    if not alive(controller) then return nil, nil, nil, nil end

    local state = nil
    local inventory = nil
    local technology = nil
    pcall(function()
        state = controller.PlayerState or controller:GetPlayerState()
        if alive(state) then
            inventory = state:GetInventoryData()
            technology = state:GetTechnologyData()
        end
    end)
    if not alive(state) or not alive(inventory) or not alive(technology) then
        return controller, nil, nil, nil
    end
    return controller, state, inventory, technology
end

local function techBalance(technology)
    local balance = 0
    pcall(function()
        balance = tonumber(technology:GetTechnologyPoints())
            or tonumber(technology.TechnologyPoint)
            or 0
    end)
    return math.max(0, math.floor(balance))
end

local function setTechBalance(technology, amount)
    local success = false
    local ok, err = pcall(function()
        technology.TechnologyPoint = math.max(0, math.floor(tonumber(amount) or 0))
        if type(technology.OnRep_TechnologyPoint) == "function" then
            technology:OnRep_TechnologyPoint()
        end
        success = true
    end)
    if not ok then log("Technology Point update failed: " .. tostring(err), true) end
    return success
end

local function tokenCount(inventory)
    local count = 0
    pcall(function()
        count = tonumber(inventory:CountItemNum(FName(TOKEN_ID))) or 0
    end)
    return math.max(0, math.floor(count))
end

local function getConsumeHelper()
    if alive(consumeHelper) then return consumeHelper end
    pcall(function()
        local helperClass = StaticFindObject("/Script/Pal.PalIncidentBase")
        local outer = (UEHelpers and UEHelpers.GetGameInstance and UEHelpers.GetGameInstance())
            or FindFirstOf("GameInstance")
        if alive(helperClass) and alive(outer) then
            consumeHelper = StaticConstructObject(helperClass, outer)
        end
    end)
    return consumeHelper
end

local function removeTokens(inventory)
    local before = tokenCount(inventory)
    if before <= 0 then return true, 0 end
    local helper = getConsumeHelper()
    if not alive(helper) then return false, before end

    local ok, err = pcall(function()
        helper:RequestConsumeInventoryItem(inventory, FName(TOKEN_ID), before)
    end)
    local remaining = tokenCount(inventory)
    if not ok then log("Token cleanup failed: " .. tostring(err), true) end
    return ok and remaining == 0, remaining
end

local function addTokens(inventory, amount)
    amount = math.max(0, math.floor(tonumber(amount) or 0))
    if amount == 0 then return true end
    local before = tokenCount(inventory)
    local ok, err = pcall(function()
        inventory:AddItem_ServerInternal(FName(TOKEN_ID), amount, true)
    end)
    local added = tokenCount(inventory) - before
    if not ok or added ~= amount then
        log(string.format("Token issue failed (wanted=%d added=%d): %s", amount, added, tostring(err)), true)
        return false
    end
    return true
end

local function vendorMatches(vendor, component)
    local fullName = tostring(vendor or "")
    if alive(vendor) then
        pcall(function() fullName = vendor:GetFullName() end)
        end
    end

    -- Check if the shop component itself specifies the TechPoint token currency
    local usesToken = false
    if alive(component) then
    local _, state, inventory, technology = getPlayerData(component)
    if not alive(state) then
        log("Cannot resolve the server player for " .. tostring(reason), true)
        return false
    end

    local removed = removeTokens(inventory)
    if not removed then
        log("Refusing to issue tokens because stale tokens could not be removed", true)
        return false
    end

    local balance = techBalance(technology)
    if not addTokens(inventory, balance) then
        removeTokens(inventory)
        return false
    end
    log(string.format("Synced %d Technology Point token(s): %s", balance, tostring(reason)), true)
    return true
end

local function closeSession(component, reason)
    local key = objectKey(component)
    local session = sessions[key]
    sessions[key] = nil
    local _, _, inventory, technology = getPlayerData(component)
    if alive(inventory) and alive(technology) then
        local remainingTokens = tokenCount(inventory)
        local initial = session and session.initialBalance or 0
        if remainingTokens > initial then
            local earned = remainingTokens - initial
            local currentTech = techBalance(technology)
            setTechBalance(technology, currentTech + earned)
            log(string.format("Player recycled items and earned %d Technology Points!", earned), true)
        end
        removeTokens(inventory)
    end
    if session then log("Closed VC merchant session: " .. tostring(reason), true) end
end

local function setupPost(selfParam, vendorParam)
    local component = unwrap(selfParam)
    if not alive(component) or not isAuthority(component) then return end
    local matches, fullName = vendorMatches(vendorParam, component)
    if not matches then return end

    local _, _, _, technology = getPlayerData(component)
    local initBal = alive(technology) and techBalance(technology) or 0

    local key = objectKey(component)
    sessions[key] = { active = true, pending = nil, vendor = fullName, initialBalance = initBal }
    syncDisplayBalance(component, "merchant opened")
    log("Activated for vendor " .. tostring(fullName), true)
end

local function buyPre(selfParam, ...)
    local component = unwrap(selfParam)
    if not alive(component) or not isAuthority(component) then return end
    local key = objectKey(component)
    local session = sessions[key]
    if not session then return end
    if session.pending then
        log("Rejected overlapping purchase normalization", true)
        return
    end

    local _, state, inventory, technology = getPlayerData(component)
    if not alive(state) then return end

    -- Normalize away any copied, dropped-and-recovered, or stale token balance.
    if not removeTokens(inventory) then return end
    local balance = techBalance(technology)
    if balance <= 0 then
        session.pending = { inventory = inventory, technology = technology, original = 0 }
        return
    end

    -- Escrow the full balance before native delivery. The post-hook refunds the
    -- unspent remainder, so a successful native purchase can never be free.
    if not setTechBalance(technology, 0) then return end
    if not addTokens(inventory, balance) then
        setTechBalance(technology, balance)
        return
    end

    session.pending = {
        inventory = inventory,
        technology = technology,
        original = balance
    }

    local watchdogMs = math.max(250, tonumber(Config.watchdogMilliseconds) or 2000)
    ExecuteWithDelay(watchdogMs, function()
        local current = sessions[key]
        if current and current.pending then
            log("Purchase post-hook watchdog performed recovery", true)
            local pending = current.pending
            current.pending = nil
            local remaining = tokenCount(pending.inventory)
            removeTokens(pending.inventory)
            setTechBalance(pending.technology, math.min(pending.original, remaining))
            syncDisplayBalance(component, "watchdog recovery")
        end
    end)
end

local function buyPost(selfParam, ...)
    local component = unwrap(selfParam)
    if not alive(component) or not isAuthority(component) then return end
    local key = objectKey(component)
    local session = sessions[key]
    if not session or not session.pending then return end

    local pending = session.pending
    session.pending = nil
    local remaining = math.min(pending.original, tokenCount(pending.inventory))
    local spent = math.max(0, pending.original - remaining)
    removeTokens(pending.inventory)

    -- The escrowed balance is currently zero. Refund only what the native shop
    -- did not consume; the difference is the authoritative TP purchase price.
    if not setTechBalance(pending.technology, remaining) then
        log("CRITICAL: could not finalize Technology Point balance", true)
        return
    end
    syncDisplayBalance(component, "purchase complete")
    log(string.format("Transaction finalized: spent=%d remaining=%d", spent, remaining), true)
end

local function sellPre(selfParam, ...)
    local component = unwrap(selfParam)
    if not alive(component) or not isAuthority(component) then return end
    local key = objectKey(component)
    local session = sessions[key]
    if not session or not session.active then return end

    local _, _, inventory = getPlayerData(component)
    if not alive(inventory) then return end

    local snapshot = {}
    for itemId, _ in pairs(BOSS_DROPS) do
        local count = 0
        pcall(function() count = tonumber(inventory:CountItemNum(FName(itemId))) or 0 end)
        if count > 0 then
            snapshot[itemId] = count
        end
    end
    session.sellSnapshot = snapshot
end

local function sellPost(selfParam, ...)
    local component = unwrap(selfParam)
    if not alive(component) or not isAuthority(component) then return end
    local key = objectKey(component)
    local session = sessions[key]
    if not session or not session.sellSnapshot then return end

    local controller, state, inventory, technology = getPlayerData(component)
    if not alive(inventory) or not alive(technology) then return end

    local snapshot = session.sellSnapshot
    session.sellSnapshot = nil

    local totalPoints = 0
    local breakdown = {}

    for itemId, beforeCount in pairs(snapshot) do
        local afterCount = 0
        pcall(function() afterCount = tonumber(inventory:CountItemNum(FName(itemId))) or 0 end)
        local diff = beforeCount - afterCount
        if diff > 0 then
            local rate = BOSS_DROPS[itemId] or 1
            local pts = diff * rate
            totalPoints = totalPoints + pts
            table.insert(breakdown, string.format("%dx %s (+%d TP)", diff, itemId, pts))
        end
    end

    if totalPoints > 0 then
        local curBal = techBalance(technology)
        setTechBalance(technology, curBal + totalPoints)
        syncDisplayBalance(component, "recycled boss drops")

        pcall(function()
            local ChatSubsystem = FindFirstOf("PalChatSubsystem")
            if ChatSubsystem and ChatSubsystem:IsValid() and alive(controller) then
                ChatSubsystem:SendSystemChatMessage(controller, FText(string.format("✨ [Technology Merchant] Recycled: %s! Deposited +%d Technology Points.", table.concat(breakdown, ", "), totalPoints)))
            end
            local PalUtil = StaticFindObject("/Script/Pal.Default__PalUtility")
            if PalUtil and PalUtil:IsValid() and alive(controller) then
                PalUtil:SendSystemAnnounce(controller, string.format("✨ Recycled Boss Drops: +%d Technology Points!", totalPoints))
            end
        end)
        log(string.format("Player recycled boss drops for +%d Technology Points (%s)", totalPoints, table.concat(breakdown, ", ")), true)
    else
        pcall(function()
            local ChatSubsystem = FindFirstOf("PalChatSubsystem")
            if ChatSubsystem and ChatSubsystem:IsValid() and alive(controller) then
                ChatSubsystem:SendSystemChatMessage(controller, FText("⚠️ [Technology Merchant] Only Alpha Boss drops, Ancient Relics, and Precious Stones award Technology Points."))
            end
        end)
    end
end

local function closePre(selfParam, ...)
    local component = unwrap(selfParam)
    if alive(component) and isAuthority(component) then
        closeSession(component, "merchant closed")
    end
end

local function registerHooks()
    local setupOk, setupErr = pcall(function()
        RegisterHook(SETUP_HOOK, function() end, setupPost)
    end)
    local buyOk, buyErr = pcall(function()
        RegisterHook(BUY_HOOK, buyPre, buyPost)
    end)
    local sellOk, sellErr = pcall(function()
        RegisterHook(SELL_HOOK, sellPre, sellPost)
    end)

    log(string.format("hooks setup=%s buy=%s sell=%s", tostring(setupOk), tostring(buyOk), tostring(sellOk)), true)
    if not setupOk then log("Setup hook error: " .. tostring(setupErr), true) end
    if not buyOk then log("Buy hook error: " .. tostring(buyErr), true) end
    if not sellOk then log("Sell hook error: " .. tostring(sellErr), true) end
end

registerHooks()
log("Loaded; VC merchant CurrencyItemID must be " .. TOKEN_ID, true)
