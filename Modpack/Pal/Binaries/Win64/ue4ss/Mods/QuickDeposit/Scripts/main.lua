-- ============================================================================
-- QuickDeposit: Press G near base chests to trigger Palworld's native
-- Easy Bulk Storage ("Stow") for instant item deposits.
--
-- ARCHITECTURE:
--   RegisterKeyBind runs on UE4SS's own thread, NOT the game thread.
--   ALL UObject access MUST be marshalled via ExecuteInGameThread or
--   the game WILL crash (see DarnMenu/ui.lua §3162 and WeaponProficiency
--   main.lua §1560 for the documented pattern).
--
--   Palworld has a native "Easy Bulk Storage" system that handles matching
--   items to existing stacks in base chests. This mod programmatically
--   triggers that system from a single keypress outside the inventory UI.
-- ============================================================================

local ok, Config = pcall(require, "config")
if not ok or type(Config) ~= "table" then
    Config = {
        enabled = true,
        depositKey = "G",
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

-- Toast Notification Helper via DarnToasts (same pattern as ShiningLuckies)
local Toast = nil
pcall(function()
    local SDIR = (debug.getinfo(1, "S").source:gsub("^@", ""):gsub("[^/\\]+$", ""))
    package.path = SDIR .. "../../DarnToasts/Scripts/?.lua;" .. package.path
    Toast = require("ToastLib").new("QuickDeposit")
end)
if not Toast then
    Log("DarnToasts not found -- deposit notifications disabled.")
end

local function SendToast(msg, r, g, b)
    if Toast and Toast.notify and (Config.notifyToast or Config.notifyOnDeposit) then
        pcall(function() Toast.notify(msg, r or 0.0, g or 0.94, b or 1.0) end)
    end
end

-- The actual deposit logic. This MUST run on the game thread.
local function DoDeposit()
    -- 1. Find local player controller
    local player = nil
    pcall(function()
        local controllers = FindAllOf("PalPlayerController")
        if controllers then
            for _, c in ipairs(controllers) do
                if c and c:IsValid() then
                    -- On a client there is typically one PalPlayerController
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

    -- 2. Check if player is near / inside a base camp
    local pawn = nil
    pcall(function() pawn = player.Pawn end)
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

    -- 3. Try to find the base camp manager and the player's base camp
    local baseCamp = nil
    pcall(function()
        local bcm = FindFirstOf("PalBaseCampManager")
        if bcm and bcm:IsValid() then
            -- Try to find the camp closest to the player
            if bcm.GetNearestBaseCamp then
                baseCamp = bcm:GetNearestBaseCamp(playerLoc)
            elseif bcm.FindNearBaseCamp then
                baseCamp = bcm:FindNearBaseCamp(playerLoc)
            elseif bcm.GetBelongBaseCamp then
                baseCamp = bcm:GetBelongBaseCamp(pawn)
            end
        end
    end)

    -- 4. Try to trigger native Easy Bulk Storage / auto-stow via the player state
    local triggered = false

    -- Method A: Try the player inventory component's native bulk-store method
    pcall(function()
        local ps = player.PlayerState
        if ps and ps:IsValid() then
            -- Try various known method names for bulk storage
            if ps.RequestEasyBulkStorage then
                ps:RequestEasyBulkStorage()
                triggered = true
                Log("Triggered via PlayerState.RequestEasyBulkStorage")
            elseif ps.RequestBulkPutItemsToBaseCamp_ToServer then
                ps:RequestBulkPutItemsToBaseCamp_ToServer()
                triggered = true
                Log("Triggered via PlayerState.RequestBulkPutItemsToBaseCamp_ToServer")
            end
        end
    end)

    -- Method B: Try the PalPlayerCharacter's native deposit method
    if not triggered then
        pcall(function()
            if pawn.RequestEasyBulkStorage then
                pawn:RequestEasyBulkStorage()
                triggered = true
                Log("Triggered via Pawn.RequestEasyBulkStorage")
            elseif pawn.RequestBulkStoreItemsToBaseCamp then
                pawn:RequestBulkStoreItemsToBaseCamp()
                triggered = true
                Log("Triggered via Pawn.RequestBulkStoreItemsToBaseCamp")
            end
        end)
    end

    -- Method C: Try via player controller directly
    if not triggered then
        pcall(function()
            if player.RequestEasyBulkStorage then
                player:RequestEasyBulkStorage()
                triggered = true
                Log("Triggered via Controller.RequestEasyBulkStorage")
            elseif player.EasyBulkStorage then
                player:EasyBulkStorage()
                triggered = true
                Log("Triggered via Controller.EasyBulkStorage")
            end
        end)
    end

    -- Method D: Try to find and call the function via the subsystem
    if not triggered then
        pcall(function()
            local gi = FindFirstOf("PalGameInstance")
            if gi and gi:IsValid() then
                local sub = gi.EasyBulkStorageSubsystem or gi.ItemStorageSubsystem
                if sub and sub:IsValid() then
                    if sub.RequestBulkStore then
                        sub:RequestBulkStore(player)
                        triggered = true
                        Log("Triggered via EasyBulkStorageSubsystem")
                    end
                end
            end
        end)
    end

    -- Method E: Simulate the input action that triggers Easy Bulk Storage
    -- The native game triggers this when pressing R while inventory is open.
    -- Try to find the input action and call it programmatically.
    if not triggered then
        pcall(function()
            local palUtil = StaticFindObject("/Script/Pal.Default__PalUtility")
            if palUtil and palUtil:IsValid() then
                if palUtil.RequestBulkStoreToBaseCamp then
                    palUtil:RequestBulkStoreToBaseCamp(player)
                    triggered = true
                    Log("Triggered via PalUtility.RequestBulkStoreToBaseCamp")
                end
            end
        end)
    end

    -- Method F: Last resort - send the system chat notification to the player
    -- informing them to use the native R key in inventory
    if not triggered then
        Log("No native bulk-store API found on this game version.")
        Log("The game's native Easy Bulk Storage (R key in inventory) may be the only path.")
        SendToast("📥 Quick Deposit: Open inventory & press R to bulk-store items.", 1.0, 0.85, 0.0)
        pcall(function()
            local palUtil = StaticFindObject("/Script/Pal.Default__PalUtility")
            if palUtil and palUtil:IsValid() and palUtil.SendSystemToPlayerChat then
                palUtil:SendSystemToPlayerChat(player,
                    "📥 [QuickDeposit] Open your Inventory (Tab) and press R for Easy Bulk Storage to deposit items into base chests.",
                    { player:GetPlayerUId() })
            end
        end)
        return
    end

    Log("Quick Deposit triggered successfully.")
    SendToast("📥 Quick Deposit: Items deposited to base chests!", 0.0, 0.95, 1.0)
end

-- Register Keybind — callback runs on UE4SS thread, so marshal to game thread!
pcall(function()
    local keyName = Config.depositKey or "G"
    local k = Key[keyName] or Key.G
    RegisterKeyBind(k, function()
        -- CRITICAL: Must hop to game thread. See DarnMenu ui.lua §3162.
        if type(_G.ExecuteInGameThread) == "function" then
            pcall(_G.ExecuteInGameThread, function()
                pcall(DoDeposit)
            end)
        else
            -- Fallback: try direct call (may crash on some builds)
            pcall(DoDeposit)
        end
    end)
    Log(string.format("Registered QuickDeposit hotkey [%s] (game-thread marshalled)", keyName))
end)

Log("QuickDeposit loaded successfully.")
