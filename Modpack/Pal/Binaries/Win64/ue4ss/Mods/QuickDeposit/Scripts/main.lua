-- ============================================================================
-- QuickDeposit: Press G (or configured key) near base chests to instantly
-- deposit matching inventory items into your base containers.
--
-- ARCHITECTURE:
--   1. Hotkey triggers on UE4SS thread, marshalled to GameThread.
--   2. Dispatches native Palworld bulk storage RPCs.
--   3. Provides intelligent multi-chest stack-matching scanner fallback:
--      - Locates nearby base chests / containers within range.
--      - Scans player's NormalInventory for item stacks.
--      - Transfers matching items to existing container stacks.
--   4. Displays clean Toast feedback with deposited items count.
-- ============================================================================

local ok, Config = pcall(require, "config")
if not ok or type(Config) ~= "table" then
    Config = {
        enabled = true,
        depositKey = "G",
        depositRadius = 3500.0,
        notifyOnDeposit = true,
        notifyToast = true,
        log = true
    }
end

local function Log(msg)
    if Config.log then
        print(string.format("[QuickDeposit] %s\n", tostring(msg)))
    end
end

if not Config.enabled then return end

-- Toast Notification Helper via DarnToasts
local Toast = nil
pcall(function()
    local SDIR = (debug.getinfo(1, "S").source:gsub("^@", ""):gsub("[^/\\]+$", ""))
    package.path = SDIR .. "../../DarnToasts/Scripts/?.lua;" .. package.path
    Toast = require("ToastLib").new("QuickDeposit")
end)

local function SendToast(msg, r, g, b)
    if Toast and Toast.notify and (Config.notifyToast or Config.notifyOnDeposit) then
        pcall(function() Toast.notify(msg, r or 0.0, g or 0.95, b or 1.0) end)
    end
end

-- Helper: Safe vector distance calculation
local function GetDistance(v1, v2)
    if not v1 or not v2 then return 999999 end
    local dx = (v1.X or 0) - (v2.X or 0)
    local dy = (v1.Y or 0) - (v2.Y or 0)
    local dz = (v1.Z or 0) - (v2.Z or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

-- Helper: Extract Static Item ID name from FName or string
local function GetItemStaticId(itemIdObj)
    if not itemIdObj then return nil end
    local s = nil
    pcall(function()
        if type(itemIdObj) == "string" then
            s = itemIdObj
        elseif itemIdObj.StaticItemId then
            s = itemIdObj.StaticItemId:ToString()
        elseif itemIdObj.GetFName then
            s = itemIdObj:GetFName():ToString()
        elseif itemIdObj.ToString then
            s = itemIdObj:ToString()
        end
    end)
    if s and s ~= "None" and s ~= "" then
        return s
    end
    return nil
end

-- Fallback Scanner: Scans nearby base camp chests and transfers matching items
local function ScanAndDepositToNearbyChests(player, pawn, playerLoc, maxRadius)
    local totalDepositedTypes = 0
    local totalDepositedCount = 0
    local depositedItems = {}

    local invData = nil
    pcall(function()
        if player.GetPalPlayerInventoryData then
            invData = player:GetPalPlayerInventoryData()
        end
        if not invData then
            invData = player.InventoryData or (player.PlayerState and player.PlayerState.InventoryData)
        end
    end)

    if not invData or not invData:IsValid() then
        return 0, 0, {}
    end

    local normalInv = nil
    pcall(function()
        normalInv = invData.NormalInventory or invData.CommonContainer
    end)

    if not normalInv or not normalInv:IsValid() then
        return 0, 0, {}
    end

    -- 1. Find all Chest / Storage Map Objects
    local chestModels = {}
    pcall(function()
        local chests = FindAllOf("PalMapObjectItemChestModel")
        if chests then
            for _, c in ipairs(chests) do
                if c and c:IsValid() then
                    local loc = nil
                    pcall(function() loc = c:K2_GetActorLocation() end)
                    if not loc then
                        pcall(function()
                            local actor = c:GetOwner() or c.ConcreteModel
                            if actor and actor:IsValid() then
                                loc = actor:K2_GetActorLocation()
                            end
                        end)
                    end

                    if not loc or GetDistance(playerLoc, loc) <= maxRadius then
                        table.insert(chestModels, c)
                    end
                end
            end
        end
    end)

    -- If no specific chest models found, try concrete storage models
    if #chestModels == 0 then
        pcall(function()
            local models = FindAllOf("PalMapObjectConcreteModelBase")
            if models then
                for _, m in ipairs(models) do
                    if m and m:IsValid() then
                        local hasContainer = false
                        pcall(function()
                            if m.GetItemContainer or m.ItemContainer or m.Container then
                                hasContainer = true
                            end
                        end)
                        if hasContainer then
                            table.insert(chestModels, m)
                        end
                    end
                end
            end
        end)
    end

    if #chestModels == 0 then
        return 0, 0, {}
    end

    -- 2. Inspect chest containers to index existing item types
    local chestContainers = {}
    local chestExistingItems = {} -- ItemId -> true

    for _, cm in ipairs(chestModels) do
        local container = nil
        pcall(function()
            if cm.GetItemContainer then
                container = cm:GetItemContainer()
            elseif cm.ItemContainer then
                container = cm.ItemContainer
            elseif cm.Container then
                container = cm.Container
            end
        end)

        if container and container:IsValid() then
            table.insert(chestContainers, container)
            pcall(function()
                local slots = container.ItemSlots or (container.GetItemSlots and container:GetItemSlots())
                if slots then
                    for _, slot in ipairs(slots) do
                        if slot and slot:IsValid() then
                            local id = GetItemStaticId(slot:GetItemId())
                            local count = (slot.GetStackCount and slot:GetStackCount()) or slot.StackCount or 0
                            if id and count > 0 then
                                chestExistingItems[id] = true
                            end
                        end
                    end
                end
            end)
        end
    end

    if #chestContainers == 0 then
        return 0, 0, {}
    end

    -- 3. Check player's items against existing chest items
    local playerSlots = nil
    pcall(function()
        playerSlots = normalInv.ItemSlots or (normalInv.GetItemSlots and normalInv:GetItemSlots())
    end)

    if not playerSlots then return 0, 0, {} end

    for _, pSlot in ipairs(playerSlots) do
        if pSlot and pSlot:IsValid() then
            local id = GetItemStaticId(pSlot:GetItemId())
            local count = (pSlot.GetStackCount and pSlot:GetStackCount()) or pSlot.StackCount or 0

            if id and count > 0 and chestExistingItems[id] then
                -- Try to transfer this stack into matching chest container
                local transferred = false

                for _, targetContainer in ipairs(chestContainers) do
                    pcall(function()
                        if targetContainer.AddItem then
                            targetContainer:AddItem(FName(id), count, true)
                            transferred = true
                        elseif invData.RequestMoveInventoryItemToContainer then
                            local slotId = pSlot.SlotId or pSlot:GetSlotId()
                            local contId = targetContainer:GetContainerId()
                            invData:RequestMoveInventoryItemToContainer(slotId, contId, count)
                            transferred = true
                        end
                    end)

                    if transferred then
                        -- Decrement / empty player slot if direct add
                        pcall(function()
                            if pSlot.Empty then
                                pSlot:Empty()
                            elseif pSlot.SetStackCount then
                                pSlot:SetStackCount(0)
                            end
                        end)

                        totalDepositedTypes = totalDepositedTypes + 1
                        totalDepositedCount = totalDepositedCount + count
                        depositedItems[id] = (depositedItems[id] or 0) + count
                        break
                    end
                end
            end
        end
    end

    return totalDepositedTypes, totalDepositedCount, depositedItems
end

-- The main deposit entrypoint (Runs on GameThread)
local function DoDeposit()
    -- 1. Find local player controller
    local player = nil
    pcall(function()
        local controllers = FindAllOf("PalPlayerController")
        if controllers then
            for _, c in ipairs(controllers) do
                if c and c:IsValid() then
                    player = c
                    break
                end
            end
        end
    end)

    if not player then
        Log("No player controller found.")
        SendToast("⚠ Quick Deposit: Player not ready.", 1.0, 0.5, 0.0)
        return
    end

    -- 2. Verify player pawn and location
    local pawn = nil
    pcall(function() pawn = player.Pawn or player:GetPawn() end)
    if not pawn or not pawn:IsValid() then
        Log("No player pawn found.")
        SendToast("⚠ Quick Deposit: Not in world yet.", 1.0, 0.5, 0.0)
        return
    end

    local playerLoc = nil
    pcall(function() playerLoc = pawn:K2_GetActorLocation() end)
    if not playerLoc then
        Log("Could not get player location.")
        return
    end

    local triggered = false
    local maxRadius = tonumber(Config.depositRadius) or 3500.0

    -- 3. Method A: Try native Palworld Quick Move RPCs
    pcall(function()
        local invData = nil
        if player.GetPalPlayerInventoryData then
            invData = player:GetPalPlayerInventoryData()
        end
        if not invData then
            invData = player.InventoryData or (player.PlayerState and player.PlayerState.InventoryData)
        end

        if invData and invData:IsValid() then
            if invData.RequestQuickMoveToBelongBaseCampContainer then
                invData:RequestQuickMoveToBelongBaseCampContainer()
                triggered = true
                Log("Triggered via invData.RequestQuickMoveToBelongBaseCampContainer")
            elseif invData.RequestQuickMove then
                invData:RequestQuickMove()
                triggered = true
                Log("Triggered via invData.RequestQuickMove")
            elseif invData.RequestAutoDeposit then
                invData:RequestAutoDeposit()
                triggered = true
                Log("Triggered via invData.RequestAutoDeposit")
            end
        end
    end)

    -- Method B: Try Network Player Component RPC
    if not triggered then
        pcall(function()
            local netComp = player.NetworkPlayerComponent or (player.PlayerState and player.PlayerState.NetworkPlayerComponent)
            if netComp and netComp:IsValid() then
                if netComp.RequestQuickMoveItemsToBelongBaseCamp then
                    netComp:RequestQuickMoveItemsToBelongBaseCamp()
                    triggered = true
                    Log("Triggered via NetworkPlayerComponent.RequestQuickMoveItemsToBelongBaseCamp")
                end
            end
        end)
    end

    -- Method C: Intelligent Multi-Chest Fallback Scanner
    if not triggered then
        local types, count, items = ScanAndDepositToNearbyChests(player, pawn, playerLoc, maxRadius)
        if count > 0 then
            triggered = true
            Log(string.format("Direct stack transfer succeeded: deposited %d items across %d types.", count, types))
            SendToast(string.format("📥 Quick Stored: %d items deposited into base chests!", count), 0.0, 0.95, 1.0)
            return
        end
    end

    if triggered then
        Log("Quick Deposit triggered successfully.")
        SendToast("📥 Quick Deposit: Matching items stored into base chests!", 0.0, 0.95, 1.0)
    else
        Log("No matching items or chests nearby.")
        SendToast("📥 Quick Deposit: No matching items or base chests nearby.", 1.0, 0.85, 0.2)
    end
end

-- Register Keybind — callback runs on UE4SS thread, marshalled to game thread
pcall(function()
    local keyName = Config.depositKey or "G"
    local k = Key[keyName] or Key.G
    RegisterKeyBind(k, function()
        if type(_G.ExecuteInGameThread) == "function" then
            pcall(_G.ExecuteInGameThread, function()
                pcall(DoDeposit)
            end)
        else
            pcall(DoDeposit)
        end
    end)
    Log(string.format("Registered QuickDeposit hotkey [%s] (GameThread marshalled)", keyName))
end)

Log("QuickDeposit v2.0 loaded successfully.")
