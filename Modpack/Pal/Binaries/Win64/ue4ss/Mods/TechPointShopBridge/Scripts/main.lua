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
local CLOSE_HOOK = "/Script/Pal.PalNetworkShopComponent:RemoveShopData_ToServer"

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

local function vendorMatches(vendor)
    if not alive(vendor) then return false end
    local fullName = tostring(vendor)
    pcall(function() fullName = vendor:GetFullName() end)
    local lowered = fullName:lower()
    for _, pattern in ipairs(Config.vendorNamePatterns or {}) do
        if lowered:find(tostring(pattern):lower(), 1, true) then
            return true, fullName
        end
    end
    return false, fullName
end

local function syncDisplayBalance(component, reason)
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
    log(string.format("Synced %d Technology Point token(s): %s", balance, tostring(reason)))
    return true
end

local function closeSession(component, reason)
    local key = objectKey(component)
    local session = sessions[key]
    sessions[key] = nil
    local _, _, inventory = getPlayerData(component)
    if alive(inventory) then removeTokens(inventory) end
    if session then log("Closed VC merchant session: " .. tostring(reason)) end
end

local function setupPost(selfParam, vendorParam)
    local component = unwrap(selfParam)
    if not alive(component) or not isAuthority(component) then return end
    local vendor = unwrap(vendorParam)
    local matches, fullName = vendorMatches(vendor)
    if not matches then return end

    local key = objectKey(component)
    sessions[key] = { active = true, pending = nil, vendor = fullName }
    syncDisplayBalance(component, "merchant opened")
    log("Activated for vendor " .. tostring(fullName))
end

local function buyPre(selfParam, ...)
    local component = unwrap(selfParam)
    if not alive(component) or not isAuthority(component) then return end
    local key = objectKey(component)
    local session = sessions[key]
    if not session or not session.active then return end
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
    local closeOk, closeErr = pcall(function()
        RegisterHook(CLOSE_HOOK, closePre)
    end)

    log(string.format("hooks setup=%s buy=%s close=%s", tostring(setupOk), tostring(buyOk), tostring(closeOk)), true)
    if not setupOk then log("Setup hook error: " .. tostring(setupErr), true) end
    if not buyOk then log("Buy hook error: " .. tostring(buyErr), true) end
    if not closeOk then log("Close hook error: " .. tostring(closeErr), true) end
end

registerHooks()
log("Loaded; VC merchant CurrencyItemID must be " .. TOKEN_ID, true)
