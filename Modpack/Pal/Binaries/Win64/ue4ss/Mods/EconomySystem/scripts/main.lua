-- ============================================================================
-- EconomySystem v3.2.0 - Unified Technology & Ancient Point Economy
-- Features:
--   • [F6] Interactive Graphical Shop Window with Clickable [BUY], [GACHA], [CONVERT]
--   • Direct Player Stat Boosting Items (Might, Vitality, Stamina, Speed, Burden)
--   • Guild Base, Breeding Pen & Ranch Expansion Permits
--   • Azomer's Custom Passive Skill Implants (APSE)
--   • Boss Drop Recycling for Technology Points
--   • High-Stakes Gacha: Dog Coins, Gold, and Legendary/Epic/Rare Schematics
--   • Two-Way Point Currency Converter (5 Normal <-> 1 Ancient)
-- ============================================================================

print("[EconomySystem] Booting EconomySystem v3.2.0 Unified Economy Suite...")

local ScriptDir = debug.getinfo(1, "S").source:gsub("^@", ""):gsub("[^/\\]+$", "")
package.path = ScriptDir .. "../../shared/?.lua;" .. package.path
local Json = require("palodyssey_json")

local Config = {
    GachaCostTechPoints = 3,
    PointExchangeRate = 5,
    GachaPool = {},
    ShopItems = {},
    RecycleRates = {}
}

-- Safe config loader
pcall(function()
    local candidates = {
        ScriptDir .. "../config.json",
        ScriptDir .. "config.json",
        "C:/SteamLibrary/steamapps/common/Palworld/Pal/Binaries/Win64/ue4ss/Mods/EconomySystem/config.json",
        "C:/SteamLibrary/steamapps/common/PalServer/Pal/Binaries/Win64/ue4ss/Mods/EconomySystem/config.json"
    }
    for _, path in ipairs(candidates) do
        local f = io.open(path, "r")
        if f then
            local raw = f:read("*all")
            f:close()
            local decoders = {}
            if JSON and type(JSON.parse) == "function" then table.insert(decoders, JSON.parse) end
            if json and type(json.decode) == "function" then table.insert(decoders, json.decode) end
            if _G.json and type(_G.json.decode) == "function" then table.insert(decoders, _G.json.decode) end
            table.insert(decoders, Json.decode)
            for _, d in ipairs(decoders) do
                local ok, parsed = pcall(d, raw)
                if ok and type(parsed) == "table" then
                    for k, v in pairs(parsed) do Config[k] = v end
                    print("[EconomySystem] Successfully loaded configuration from: " .. path)
                    return
                end
            end
        end
    end
end)

local GuildUpgrades = {}
-- Runtime state is authoritative in the active installation only. Never write
-- into the launcher workspace or another Palworld process' installation.
local UPGRADES_FILE = ScriptDir .. "../../GuildBuildingLimits/guild_upgrades.json"

local function LoadGuildUpgrades()
    pcall(function()
        local paths = { UPGRADES_FILE }
        for _, path in ipairs(paths) do
            local f = io.open(path, "r")
            if f then
                local raw = f:read("*all")
                f:close()
                local decoders = {}
                if JSON and type(JSON.parse) == "function" then table.insert(decoders, JSON.parse) end
                if json and type(json.decode) == "function" then table.insert(decoders, json.decode) end
                if _G.json and type(_G.json.decode) == "function" then table.insert(decoders, _G.json.decode) end
                table.insert(decoders, Json.decode)
                for _, d in ipairs(decoders) do
                    local ok, parsed = pcall(d, raw)
                    if ok and type(parsed) == "table" then
                        GuildUpgrades = parsed
                        return
                    end
                end
            end
        end
    end)
end
LoadGuildUpgrades()

local function SaveGuildUpgrades()
    local saved = false
    local ok, err = pcall(function()
        local encoder = nil
        if JSON and type(JSON.stringify) == "function" then encoder = JSON.stringify end
        if not encoder and json and type(json.encode) == "function" then encoder = json.encode end
        if not encoder and _G.json and type(_G.json.encode) == "function" then encoder = _G.json.encode end
        if not encoder then encoder = Json.encode end
        
        local raw = "{}"
        if encoder then
            local ok, str = pcall(encoder, GuildUpgrades)
            if ok and str then raw = str end
        else
            local parts = {}
            local function EscapeJson(value)
                return tostring(value):gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\r", "\\r"):gsub("\n", "\\n")
            end
            for gId, upgrades in pairs(GuildUpgrades) do
                local subparts = {}
                for k, v in pairs(upgrades) do
                    table.insert(subparts, string.format('"%s": %d', EscapeJson(k), tonumber(v) or 0))
                end
                table.insert(parts, string.format('"%s": { %s }', EscapeJson(gId), table.concat(subparts, ", ")))
            end
            raw = "{\n  " .. table.concat(parts, ",\n  ") .. "\n}"
        end

        local tempPath = UPGRADES_FILE .. ".tmp"
        local backupPath = UPGRADES_FILE .. ".bak"
        local f, openErr = io.open(tempPath, "w")
        if not f then error(openErr or "unable to open temporary upgrade file") end
        local writeOk, writeErr = f:write(raw)
        f:flush()
        f:close()
        if not writeOk then error(writeErr or "unable to write upgrade file") end

        os.remove(backupPath)
        local hadOriginal = os.rename(UPGRADES_FILE, backupPath)
        local renamed, renameErr = os.rename(tempPath, UPGRADES_FILE)
        if not renamed then
            if hadOriginal then os.rename(backupPath, UPGRADES_FILE) end
            error(renameErr or "unable to publish upgrade file")
        end
        os.remove(backupPath)
        saved = true
    end)
    if not ok then print("[EconomySystem] Failed to save guild upgrades: " .. tostring(err)) end
    return saved
end

-- UI State Variables
local IsShopWindowOpen = false
local CurrentPage = 1
local ItemsPerPage = 5
local ClickableButtons = {}
local LastClickTime = 0
local LastChatCommand = ""
local LastChatCommandTime = 0
local CanvasFont = nil
local HudDrawErrorReported = false

-- Core Game State Accessors
local CachedPC = nil
local function GetPlayerController(Context)
    if Context and Context.IsA and Context:IsA("/Script/Pal.PalPlayerController") then
        CachedPC = Context
        return Context
    end
    if Context and type(Context.get) == "function" then
        local obj = Context:get()
        if obj and obj.IsA and obj:IsA("/Script/Pal.PalPlayerController") then
            CachedPC = obj
            return obj
        end
    end
    if CachedPC and CachedPC.IsValid and CachedPC:IsValid() then
        return CachedPC
    end
    if UEHelpers and type(UEHelpers.GetPlayerController) == "function" then
        local pc = UEHelpers.GetPlayerController()
        if pc and pc:IsValid() then
            CachedPC = pc
            return pc
        end
    end
    local pc = FindFirstOf("PalPlayerController") or FindFirstOf("PlayerController")
    if pc and pc:IsValid() then
        CachedPC = pc
        return pc
    end
    return nil
end

local function GetPlayerGuildId(Player)
    local guildId = "Solo_Guild"
    pcall(function()
        local pc = Player or GetPlayerController()
        local PlayerState = pc and pc.PlayerState
        if PlayerState and PlayerState:IsValid() then
            if PlayerState.GuildId ~= nil then
                guildId = tostring(PlayerState.GuildId)
            elseif type(PlayerState.GetGuildId) == "function" then
                local id = PlayerState:GetGuildId()
                if id then guildId = tostring(id) end
            elseif type(PlayerState.GetGuildName) == "function" then
                local GuildData = PlayerState:GetGuildName()
                if GuildData then guildId = GuildData:ToString() end
            end
        end
    end)
    return guildId
end

-- Dynamic Scaling: Cost = Base * 2^(PurchasedCount)
local function GetItemCurrentCost(Player, ItemKey)
    local item = Config.ShopItems and Config.ShopItems[ItemKey:lower()]
    if not item then return 1 end
    local baseCost = tonumber(item.Cost) or 1
    if not item.IsGuildExpansion then
        return baseCost
    end

    local guildId = GetPlayerGuildId(Player)
    LoadGuildUpgrades()
    local gData = GuildUpgrades[guildId] or {}
    local currentLevel = tonumber(gData[ItemKey:lower()]) or 0

    local multiplier = math.floor(2 ^ currentLevel)
    return baseCost * multiplier, currentLevel
end

local function SendPlayerMessage(Player, Text)
    pcall(function()
        local str = tostring(Text or "")
        local pc = Player or GetPlayerController()
        local ps = pc and pc.PlayerState
        local world = (UEHelpers and UEHelpers.GetWorldContextObject and UEHelpers.GetWorldContextObject())
            or (GetWorldContext and GetWorldContext()) or nil
        local PalUtil = StaticFindObject("/Script/Pal.Default__PalUtility")

        -- 1. PalChatSubsystem
        local chatSubsystem = FindFirstOf("PalChatSubsystem")
        if chatSubsystem and chatSubsystem:IsValid() then
            if type(chatSubsystem.SendSystemChatMessage) == "function" and pc then
                pcall(function() chatSubsystem:SendSystemChatMessage(pc, FText(str)) end)
            end
            if type(chatSubsystem.BroadcastChatMessage) == "function" then
                pcall(function() chatSubsystem:BroadcastChatMessage(FText(str)) end)
            end
        end

        -- 2. Direct PlayerController RPC
        if pc and pc:IsValid() then
            if type(pc.ClientReceiveChatMessage) == "function" then
                pcall(function() pc:ClientReceiveChatMessage(str) end)
            end
            if type(pc.Client_SendSystemAnnounce) == "function" then
                pcall(function() pc:Client_SendSystemAnnounce(str) end)
            end
        end

        -- 3. PalUtility SendSystemToPlayerChat
        if PalUtil and PalUtil:IsValid() and world and ps and ps:IsValid() and ps.PlayerUId then
            pcall(function() PalUtil:SendSystemToPlayerChat(world, str, ps.PlayerUId) end)
        end
    end)
    print("[EconomySystem] " .. tostring(Text))
end

local function GetPlayerTechPoints(Player)
    local normalPoints = 0
    local ancientPoints = 0
    pcall(function()
        local pc = Player or GetPlayerController()
        local ps = pc and pc.PlayerState
        local tech = ps and type(ps.GetTechnologyData) == "function" and ps:GetTechnologyData() or nil
        if tech and tech:IsValid() then
            normalPoints = tech:GetTechnologyPoints() or tech.TechnologyPoint or 0
            ancientPoints = tech:GetBossTechnologyPoints() or tech.bossTechnologyPoint or 0
        end
    end)
    return normalPoints, ancientPoints
end

local function AddPlayerTechPoints(Player, Amount, isAncient)
    local success = false
    pcall(function()
        local pc = Player or GetPlayerController()
        local ps = pc and pc.PlayerState
        local tech = ps and type(ps.GetTechnologyData) == "function" and ps:GetTechnologyData() or nil
        if tech and tech:IsValid() then
            if isAncient then
                local current = tech:GetBossTechnologyPoints() or tech.bossTechnologyPoint or 0
                tech.bossTechnologyPoint = math.max(0, current + Amount)
                if type(tech.OnRep_BossTechnologyPoint) == "function" then tech:OnRep_BossTechnologyPoint() end
            else
                local current = tech:GetTechnologyPoints() or tech.TechnologyPoint or 0
                tech.TechnologyPoint = math.max(0, current + Amount)
                if type(tech.OnRep_TechnologyPoint) == "function" then tech:OnRep_TechnologyPoint() end
            end
            success = true
        end
    end)
    return success
end

local function GiveItem(Player, ItemId, Count)
    local success = false
    pcall(function()
        local pc = Player or GetPlayerController()
        local ps = pc and pc.PlayerState
        local inventory = ps and type(ps.GetInventoryData) == "function" and ps:GetInventoryData() or nil
        if inventory and inventory:IsValid() then
            inventory:AddItem_ServerInternal(FName(ItemId), Count, true)
            success = true
        end
    end)
    return success
end

local InventoryConsumeHelper = nil

local function GetInventoryConsumeHelper()
    if InventoryConsumeHelper and InventoryConsumeHelper.IsValid and InventoryConsumeHelper:IsValid() then
        return InventoryConsumeHelper
    end

    local incidentClass = StaticFindObject("/Script/Pal.PalIncidentBase")
    local outer = (UEHelpers and UEHelpers.GetGameInstance and UEHelpers.GetGameInstance())
        or FindFirstOf("GameInstance")
    if incidentClass and incidentClass:IsValid() and outer and outer:IsValid() then
        InventoryConsumeHelper = StaticConstructObject(incidentClass, outer)
    end
    return InventoryConsumeHelper
end

local function TakeItem(Player, ItemId, Count)
    local success = false
    local ok, err = pcall(function()
        local pc = Player or GetPlayerController()
        local ps = pc and pc.PlayerState
        local inventory = ps and type(ps.GetInventoryData) == "function" and ps:GetInventoryData() or nil
        if not inventory or not inventory:IsValid() then return end

        local requested = math.max(1, math.floor(tonumber(Count) or 1))
        local itemName = FName(ItemId)
        local before = tonumber(inventory:CountItemNum(itemName)) or 0
        if before < requested then return end

        local helper = GetInventoryConsumeHelper()
        if not helper or not helper:IsValid() then return end
        helper:RequestConsumeInventoryItem(inventory, itemName, requested)

        local after = tonumber(inventory:CountItemNum(itemName)) or before
        local removed = math.max(0, before - after)
        if removed == requested then
            success = true
        elseif removed > 0 then
            -- The native call should be atomic, but never leave a partial removal
            -- behind if the engine rejects part of the requested quantity.
            inventory:AddItem_ServerInternal(itemName, removed, true)
        end
    end)
    if not ok then
        print("[EconomySystem] Inventory consumption failed: " .. tostring(err))
    end
    return success
end

local function RollGacha(Pool)
    if not Pool or #Pool == 0 then return nil end
    local TotalWeight = 0
    for _, entry in ipairs(Pool) do
        TotalWeight = TotalWeight + (tonumber(entry.Weight) or 10)
    end
    local Picked = math.random(1, math.max(1, TotalWeight))
    local Accumulated = 0
    for _, entry in ipairs(Pool) do
        Accumulated = Accumulated + (tonumber(entry.Weight) or 10)
        if Picked <= Accumulated then
            return entry
        end
    end
    return Pool[#Pool]
end

-- Currency Conversion
local function HandleConvertCurrency(Player, Direction, Quantity)
    Quantity = math.min(100, math.max(1, math.floor(tonumber(Quantity) or 1)))
    local rate = tonumber(Config.PointExchangeRate) or 5
    local normPts, ancPts = GetPlayerTechPoints(Player)

    if Direction == "normal" or Direction == "to_ancient" then
        -- Convert Normal Tech Points -> Ancient Tech Points
        local costNormal = rate * Quantity
        if normPts < costNormal then
            SendPlayerMessage(Player, string.format("❌ Insufficient Normal Tech Points. Need: %d (Have: %d).", costNormal, normPts))
            return
        end
        if AddPlayerTechPoints(Player, -costNormal, false) then
            if not AddPlayerTechPoints(Player, Quantity, true) then
                AddPlayerTechPoints(Player, costNormal, false)
                SendPlayerMessage(Player, "❌ Conversion failed; points restored.")
                return
            end
            SendPlayerMessage(Player, string.format("🔄 Converted %d Normal Tech Points into +%d Ancient Tech Point(s)!", costNormal, Quantity))
        end
    elseif Direction == "ancient" or Direction == "to_normal" then
        -- Convert Ancient Tech Points -> Normal Tech Points
        if ancPts < Quantity then
            SendPlayerMessage(Player, string.format("❌ Insufficient Ancient Tech Points. Need: %d (Have: %d).", Quantity, ancPts))
            return
        end
        local gainNormal = rate * Quantity
        if AddPlayerTechPoints(Player, -Quantity, true) then
            if not AddPlayerTechPoints(Player, gainNormal, false) then
                AddPlayerTechPoints(Player, Quantity, true)
                SendPlayerMessage(Player, "❌ Conversion failed; points restored.")
                return
            end
            SendPlayerMessage(Player, string.format("🔄 Converted %d Ancient Tech Point(s) into +%d Normal Tech Points!", Quantity, gainNormal))
        end
    else
        SendPlayerMessage(Player, "❌ Usage: !convert normal [qty]  or  !convert ancient [qty]")
    end
end

-- Purchase Handler
local function HandleExchange(Player, ItemKey, Quantity)
    Quantity = math.min(10, math.max(1, math.floor(tonumber(Quantity) or 1)))
    local cleanKey = ItemKey and ItemKey:lower() or ""
    if not Config.ShopItems or not Config.ShopItems[cleanKey] then
        SendPlayerMessage(Player, "❌ Invalid item key. Use !shop or [F6] to view catalog.")
        return
    end

    local Item = Config.ShopItems[cleanKey]
    if Item.Enabled == false then
        SendPlayerMessage(Player, "❌ This upgrade is temporarily unavailable until its native base-cap hook is verified.")
        return
    end
    local isAncient = (Item.Currency == "ancient")
    local unitCost, currentLevel = GetItemCurrentCost(Player, cleanKey)
    local TotalCost = unitCost * Quantity
    if Item.IsGuildExpansion then
        -- Sum the geometric series so every tier in a bulk purchase is priced.
        TotalCost = unitCost * ((2 ^ Quantity) - 1)
    end
    local normPts, ancPts = GetPlayerTechPoints(Player)
    local available = isAncient and ancPts or normPts
    local currLabel = isAncient and "Ancient Tech Points" or "Tech Points"

    if available < TotalCost then
        SendPlayerMessage(Player, string.format("❌ Not enough points. Need: %d %s (Have: %d).", TotalCost, currLabel, available))
        return
    end

    if not AddPlayerTechPoints(Player, -TotalCost, isAncient) then
        SendPlayerMessage(Player, "❌ Transaction failed.")
        return
    end

    if Item.IsGuildExpansion then
        local guildId = GetPlayerGuildId(Player)
        GuildUpgrades[guildId] = GuildUpgrades[guildId] or {}
        local oldLevel = tonumber(GuildUpgrades[guildId][cleanKey]) or 0
        local newLevel = oldLevel + Quantity
        GuildUpgrades[guildId][cleanKey] = newLevel
        if not SaveGuildUpgrades() then
            GuildUpgrades[guildId][cleanKey] = oldLevel
            AddPlayerTechPoints(Player, TotalCost, isAncient)
            SendPlayerMessage(Player, "❌ Upgrade could not be saved; points restored.")
            return
        end

        local nextCost = unitCost * (2 ^ Quantity)
        SendPlayerMessage(Player, string.format("✅ Upgraded %s to Tier %d! Total Guild Limit: +%d slots. Next upgrade cost: %d %s.", Item.Desc or cleanKey, newLevel, newLevel, nextCost, currLabel))
        return
    end

    if not GiveItem(Player, Item.ItemId, math.max(1, tonumber(Item.Count) or 1) * Quantity) then
        AddPlayerTechPoints(Player, TotalCost, isAncient)
        SendPlayerMessage(Player, "❌ Item delivery failed; points refunded.")
        return
    end
    SendPlayerMessage(Player, string.format("✅ Purchased %dx %s for %d %s!", Quantity, Item.Desc or cleanKey, TotalCost, currLabel))
end

-- Gacha Handler
local function HandleGacha(Player, Rolls)
    Rolls = math.min(math.max(1, math.floor(tonumber(Rolls) or 1)), 10)
    local CostPerRoll = math.max(0, tonumber(Config.GachaCostTechPoints) or 3)
    local TotalCost = CostPerRoll * Rolls
    local normPts, _ = GetPlayerTechPoints(Player)

    if normPts < TotalCost then
        SendPlayerMessage(Player, string.format("❌ Need %d Tech Points for %dx rolls (Have: %d).", TotalCost, Rolls, normPts))
        return
    end

    if not AddPlayerTechPoints(Player, -TotalCost, false) then
        SendPlayerMessage(Player, "❌ Gacha transaction failed.")
        return
    end

    local results = { string.format("🎰 Gacha Results (%dx):", Rolls) }
    for i = 1, Rolls do
        local Outcome = RollGacha(Config.GachaPool)
        if not Outcome or not Outcome.ItemId or not GiveItem(Player, Outcome.ItemId, math.max(1, tonumber(Outcome.Count) or 1)) then
            AddPlayerTechPoints(Player, CostPerRoll, false)
            table.insert(results, "  ❌ Delivery failed; refunded.")
        else
            table.insert(results, string.format("  🎁 [%s] %s (x%d)", Outcome.Rarity or "Reward", Outcome.Desc or Outcome.ItemId, Outcome.Count or 1))
        end
    end
    SendPlayerMessage(Player, table.concat(results, "\n"))
end

-- Boss Drops Recycling Handler
local function HandleRecycle(Player, ItemKey, Quantity)
    Quantity = math.min(999, math.max(1, math.floor(tonumber(Quantity) or 1)))
    if not ItemKey or not Config.RecycleRates or not Config.RecycleRates[ItemKey] then
        SendPlayerMessage(Player, "❌ Item cannot be recycled into Tech Points.")
        return
    end

    local Rate = math.max(0, tonumber(Config.RecycleRates[ItemKey]) or 1)
    local Payout = Rate * Quantity

    if not TakeItem(Player, ItemKey, Quantity) then
        SendPlayerMessage(Player, "❌ You do not have enough of that boss drop item in your inventory.")
        return
    end
    if not AddPlayerTechPoints(Player, Payout, false) then
        GiveItem(Player, ItemKey, Quantity)
        SendPlayerMessage(Player, "❌ Point payout failed; item returned.")
        return
    end
    SendPlayerMessage(Player, string.format("♻️ Recycled %dx %s for +%d Tech Points!", Quantity, ItemKey, Payout))
end

local function HandleShopList(Player)
    local lines = { "=== 🛒 PALODYSSEY TECHNOLOGY SHOP ===" }
    if Config.ShopItems then
        for key, item in pairs(Config.ShopItems) do
            if item.Enabled ~= false then
            local currType = (item.Currency == "ancient") and "Ancient Pts" or "Tech Pts"
            table.insert(lines, string.format("• !buy %s — %s (%d %s)", key, item.Desc or key, item.Cost or 1, currType))
            end
        end
    end
    table.insert(lines, "• !convert normal [qty] — Exchange 5 Tech Pts -> 1 Ancient Pt")
    table.insert(lines, "• !convert ancient [qty] — Exchange 1 Ancient Pt -> 5 Tech Pts")
    table.insert(lines, "• !gacha [rolls] — Roll Schematics & Coin Gacha (3 Tech Pts/roll)")
    table.insert(lines, "• Shortcuts: [F6] Open GUI  [F7] Gacha  [F8] Balance")
    SendPlayerMessage(Player, table.concat(lines, "\n"))
end

local function HandleBalance(Player)
    local normPts, ancPts = GetPlayerTechPoints(Player)
    SendPlayerMessage(Player, string.format("💳 Technology Points: %d  |  Ancient Tech Points: %d", normPts, ancPts))
end

-- Toggle Interactive Window & Display Shop Catalog
local function ToggleShopWindow()
    pcall(function()
        local pc = GetPlayerController()
        if pc and pc:IsValid() then
            PrintHelp(pc)
        end
    end)
    if UniPalUI and type(UniPalUI.OpenTab) == "function" then
        UniPalUI.OpenTab("🛒 Technology Shop")
    end
end

local function GetCanvasFont()
    if CanvasFont and CanvasFont.IsValid and CanvasFont:IsValid() then return CanvasFont end
    pcall(function()
        CanvasFont = StaticFindObject("/Engine/EngineFonts/Roboto.Roboto")
        if not CanvasFont or not CanvasFont:IsValid() then
            local engine = FindFirstOf("Engine")
            CanvasFont = engine and (engine.MediumFont or engine.SmallFont) or nil
        end
    end)
    return CanvasFont
end

-- Interactive Canvas HUD Renderer
local function DrawShopGUI(Canvas, ForceDraw)
    if (not IsShopWindowOpen and not ForceDraw) or not Canvas then return end
    ClickableButtons = {}

    local pc = GetPlayerController()
    if not pc or not pc:IsValid() then return end

    local normPts, ancPts = GetPlayerTechPoints(pc)

    -- Window Dimensions
    local WinW, WinH = 760, 580
    local WinX, WinY = 280, 140

    -- Background Box
    pcall(function()
        if type(Canvas.K2_DrawBox) == "function" then
            Canvas:K2_DrawBox({ X = WinX, Y = WinY }, { X = WinW, Y = WinH }, 1.0, { R = 0.05, G = 0.08, B = 0.14, A = 0.96 })
            Canvas:K2_DrawBox({ X = WinX - 2, Y = WinY - 2 }, { X = WinW + 4, Y = WinH + 4 }, 2.0, { R = 0.0, G = 0.85, B = 1.0, A = 1.0 })
        end
    end)

    -- Header Title
    pcall(function()
        if type(Canvas.K2_DrawText) == "function" then
            Canvas:K2_DrawText(GetCanvasFont(), "PALODYSSEY TECHNOLOGY SHOP", { X = WinX + 24, Y = WinY + 16 }, { X = 1.2, Y = 1.2 }, { R = 0.0, G = 0.9, B = 1.0, A = 1.0 }, 0.0, { R = 0, G = 0, B = 0, A = 1 }, { X = 0, Y = 0 }, false, false, false, { R = 0, G = 0, B = 0, A = 1 })
            Canvas:K2_DrawText(GetCanvasFont(), string.format("Tech Points: %d   |   Ancient Points: %d", normPts, ancPts), { X = WinX + 24, Y = WinY + 46 }, { X = 1.0, Y = 1.0 }, { R = 1.0, G = 0.84, B = 0.0, A = 1.0 }, 0.0, { R = 0, G = 0, B = 0, A = 1 }, { X = 0, Y = 0 }, false, false, false, { R = 0, G = 0, B = 0, A = 1 })
        end
    end)

    -- Close Button [✕]
    local CloseX, CloseY, CloseW, CloseH = WinX + WinW - 40, WinY + 14, 28, 28
    pcall(function()
        if type(Canvas.K2_DrawBox) == "function" then
            Canvas:K2_DrawBox({ X = CloseX, Y = CloseY }, { X = CloseW, Y = CloseH }, 1.0, { R = 0.8, G = 0.2, B = 0.2, A = 1.0 })
        end
        if type(Canvas.K2_DrawText) == "function" then
            Canvas:K2_DrawText(GetCanvasFont(), "X", { X = CloseX + 8, Y = CloseY + 4 }, { X = 1.1, Y = 1.1 }, { R = 1, G = 1, B = 1, A = 1 }, 0.0, { R = 0, G = 0, B = 0, A = 1 }, { X = 0, Y = 0 }, false, false, false, { R = 0, G = 0, B = 0, A = 1 })
        end
    end)
    table.insert(ClickableButtons, { x1 = CloseX, y1 = CloseY, x2 = CloseX + CloseW, y2 = CloseY + CloseH, action = ToggleShopWindow })

    -- Currency Converter Buttons
    local Conv1X, Conv1Y, Conv1W, Conv1H = WinX + 440, WinY + 42, 140, 26
    local Conv2X, Conv2Y, Conv2W, Conv2H = WinX + 590, WinY + 42, 140, 26
    pcall(function()
        if type(Canvas.K2_DrawBox) == "function" then
            Canvas:K2_DrawBox({ X = Conv1X, Y = Conv1Y }, { X = Conv1W, Y = Conv1H }, 1.0, { R = 0.1, G = 0.4, B = 0.8, A = 1.0 })
            Canvas:K2_DrawBox({ X = Conv2X, Y = Conv2Y }, { X = Conv2W, Y = Conv2H }, 1.0, { R = 0.6, G = 0.2, B = 0.8, A = 1.0 })
        end
        if type(Canvas.K2_DrawText) == "function" then
            Canvas:K2_DrawText(GetCanvasFont(), "5 Tech -> 1 Ancient", { X = Conv1X + 8, Y = Conv1Y + 5 }, { X = 0.8, Y = 0.8 }, { R = 1, G = 1, B = 1, A = 1 }, 0.0, { R = 0, G = 0, B = 0, A = 1 }, { X = 0, Y = 0 }, false, false, false, { R = 0, G = 0, B = 0, A = 1 })
            Canvas:K2_DrawText(GetCanvasFont(), "1 Ancient -> 5 Tech", { X = Conv2X + 8, Y = Conv2Y + 5 }, { X = 0.8, Y = 0.8 }, { R = 1, G = 1, B = 1, A = 1 }, 0.0, { R = 0, G = 0, B = 0, A = 1 }, { X = 0, Y = 0 }, false, false, false, { R = 0, G = 0, B = 0, A = 1 })
        end
    end)
    table.insert(ClickableButtons, { x1 = Conv1X, y1 = Conv1Y, x2 = Conv1X + Conv1W, y2 = Conv1Y + Conv1H, action = function() HandleConvertCurrency(pc, "normal", 1) end })
    table.insert(ClickableButtons, { x1 = Conv2X, y1 = Conv2Y, x2 = Conv2X + Conv2W, y2 = Conv2Y + Conv2H, action = function() HandleConvertCurrency(pc, "ancient", 1) end })

    -- Paginated Items List
    local itemList = {}
    if Config.ShopItems then
        for k, v in pairs(Config.ShopItems) do
            if v.Enabled ~= false then table.insert(itemList, { key = k, data = v }) end
        end
    end
    table.sort(itemList, function(a, b) return (a.data.Cost or 0) < (b.data.Cost or 0) end)

    local totalPages = math.max(1, math.ceil(#itemList / ItemsPerPage))
    CurrentPage = math.min(totalPages, math.max(1, CurrentPage))

    local startIndex = (CurrentPage - 1) * ItemsPerPage + 1
    local endIndex = math.min(#itemList, startIndex + ItemsPerPage - 1)

    local RowY = WinY + 80
    for i = startIndex, endIndex do
        local entry = itemList[i]
        local item = entry.data
        local isAncient = (item.Currency == "ancient")
        local currName = isAncient and "Ancient Pts" or "Tech Pts"
        local costColor = isAncient and { R = 1.0, G = 0.4, B = 0.8, A = 1.0 } or { R = 0.0, G = 1.0, B = 0.6, A = 1.0 }
        local currentCost, curLvl = GetItemCurrentCost(pc, entry.key)

        local descText = item.Desc or entry.key
        if item.IsGuildExpansion and curLvl then
            descText = string.format("%s [Tier %d]", descText, curLvl + 1)
        end

        -- Item Row
        pcall(function()
            if type(Canvas.K2_DrawBox) == "function" then
                Canvas:K2_DrawBox({ X = WinX + 20, Y = RowY }, { X = WinW - 40, Y = 62 }, 1.0, { R = 0.10, G = 0.15, B = 0.22, A = 0.9 })
            end
            if type(Canvas.K2_DrawText) == "function" then
                Canvas:K2_DrawText(GetCanvasFont(), descText, { X = WinX + 32, Y = RowY + 8 }, { X = 1.0, Y = 1.0 }, { R = 1, G = 1, B = 1, A = 1 }, 0.0, { R = 0, G = 0, B = 0, A = 1 }, { X = 0, Y = 0 }, false, false, false, { R = 0, G = 0, B = 0, A = 1 })
                Canvas:K2_DrawText(GetCanvasFont(), string.format("Price: %d %s", currentCost, currName), { X = WinX + 32, Y = RowY + 34 }, { X = 0.9, Y = 0.9 }, costColor, 0.0, { R = 0, G = 0, B = 0, A = 1 }, { X = 0, Y = 0 }, false, false, false, { R = 0, G = 0, B = 0, A = 1 })
            end
        end)

        -- [BUY 1] Button
        local BtnX, BtnY, BtnW, BtnH = WinX + WinW - 140, RowY + 14, 100, 34
        pcall(function()
            if type(Canvas.K2_DrawBox) == "function" then
                Canvas:K2_DrawBox({ X = BtnX, Y = BtnY }, { X = BtnW, Y = BtnH }, 1.0, { R = 0.0, G = 0.7, B = 0.4, A = 1.0 })
            end
            if type(Canvas.K2_DrawText) == "function" then
                Canvas:K2_DrawText(GetCanvasFont(), "BUY 1", { X = BtnX + 26, Y = BtnY + 8 }, { X = 0.95, Y = 0.95 }, { R = 1, G = 1, B = 1, A = 1 }, 0.0, { R = 0, G = 0, B = 0, A = 1 }, { X = 0, Y = 0 }, false, false, false, { R = 0, G = 0, B = 0, A = 1 })
            end
        end)
        table.insert(ClickableButtons, {
            x1 = BtnX, y1 = BtnY, x2 = BtnX + BtnW, y2 = BtnY + BtnH,
            action = function() HandleExchange(pc, entry.key, 1) end
        })

        RowY = RowY + 70
    end

    -- Pagination Controls [◀ Prev] Page X/Y [Next ▶]
    local PageY = WinY + 440
    local PrevX, PrevY, PrevW, PrevH = WinX + 240, PageY, 80, 28
    local NextX, NextY, NextW, NextH = WinX + 440, PageY, 80, 28

    pcall(function()
        if type(Canvas.K2_DrawBox) == "function" then
            Canvas:K2_DrawBox({ X = PrevX, Y = PrevY }, { X = PrevW, Y = PrevH }, 1.0, { R = 0.2, G = 0.3, B = 0.4, A = 1.0 })
            Canvas:K2_DrawBox({ X = NextX, Y = NextY }, { X = NextW, Y = NextH }, 1.0, { R = 0.2, G = 0.3, B = 0.4, A = 1.0 })
        end
        if type(Canvas.K2_DrawText) == "function" then
            Canvas:K2_DrawText(GetCanvasFont(), "< Prev", { X = PrevX + 16, Y = PrevY + 6 }, { X = 0.9, Y = 0.9 }, { R = 1, G = 1, B = 1, A = 1 }, 0.0, { R = 0, G = 0, B = 0, A = 1 }, { X = 0, Y = 0 }, false, false, false, { R = 0, G = 0, B = 0, A = 1 })
            Canvas:K2_DrawText(GetCanvasFont(), string.format("Page %d / %d", CurrentPage, totalPages), { X = WinX + 345, Y = PageY + 6 }, { X = 0.95, Y = 0.95 }, { R = 0.9, G = 0.9, B = 0.9, A = 1 }, 0.0, { R = 0, G = 0, B = 0, A = 1 }, { X = 0, Y = 0 }, false, false, false, { R = 0, G = 0, B = 0, A = 1 })
            Canvas:K2_DrawText(GetCanvasFont(), "Next >", { X = NextX + 16, Y = NextY + 6 }, { X = 0.9, Y = 0.9 }, { R = 1, G = 1, B = 1, A = 1 }, 0.0, { R = 0, G = 0, B = 0, A = 1 }, { X = 0, Y = 0 }, false, false, false, { R = 0, G = 0, B = 0, A = 1 })
        end
    end)
    table.insert(ClickableButtons, { x1 = PrevX, y1 = PrevY, x2 = PrevX + PrevW, y2 = PrevY + PrevH, action = function() CurrentPage = math.max(1, CurrentPage - 1) end })
    table.insert(ClickableButtons, { x1 = NextX, y1 = NextY, x2 = NextX + NextW, y2 = NextY + NextH, action = function() CurrentPage = math.min(totalPages, CurrentPage + 1) end })

    -- Bottom Bar: [🎰 SCHEMATICS & COIN GACHA (3 PTS)]
    local BottomY = WinY + WinH - 64
    local GachaX, GachaY, GachaW, GachaH = WinX + 24, BottomY, 320, 42
    pcall(function()
        if type(Canvas.K2_DrawBox) == "function" then
            Canvas:K2_DrawBox({ X = GachaX, Y = GachaY }, { X = GachaW, Y = GachaH }, 1.0, { R = 0.9, G = 0.5, B = 0.0, A = 1.0 })
        end
        if type(Canvas.K2_DrawText) == "function" then
            Canvas:K2_DrawText(GetCanvasFont(), "SCHEMATICS GACHA (3 Pts)", { X = GachaX + 24, Y = GachaY + 11 }, { X = 1.05, Y = 1.05 }, { R = 1, G = 1, B = 1, A = 1 }, 0.0, { R = 0, G = 0, B = 0, A = 1 }, { X = 0, Y = 0 }, false, false, false, { R = 0, G = 0, B = 0, A = 1 })
        end
    end)
    table.insert(ClickableButtons, {
        x1 = GachaX, y1 = GachaY, x2 = GachaX + GachaW, y2 = GachaY + GachaH,
        action = function() HandleGacha(pc, 1) end
    })

    local InfoX, InfoY = WinX + 370, BottomY + 12
    pcall(function()
        if type(Canvas.K2_DrawText) == "function" then
            Canvas:K2_DrawText(GetCanvasFont(), "Shortcuts: [F6] Close | [F7] Gacha | [F8] Pts", { X = InfoX, Y = InfoY }, { X = 0.85, Y = 0.85 }, { R = 0.7, G = 0.8, B = 0.9, A = 1.0 }, 0.0, { R = 0, G = 0, B = 0, A = 1 }, { X = 0, Y = 0 }, false, false, false, { R = 0, G = 0, B = 0, A = 1 })
        end
    end)
end

-- Register against the always-loaded native HUD event. Blueprint-only paths
-- are not present when UE4SS starts and previously failed silently.
local function OnHudDraw(Context)
    local ok, err = pcall(function()
        local hud = Context and Context.get and Context:get() or Context
        if hud and hud:IsValid() and hud.Canvas and hud.Canvas:IsValid() then
            DrawShopGUI(hud.Canvas)
        end
    end)
    if not ok and not HudDrawErrorReported then
        HudDrawErrorReported = true
        print("[EconomySystem] HUD draw error: " .. tostring(err))
    end
end

local isServer = string.find(debug.getinfo(1, "S").source:lower():gsub("\\", "/"), "/palserver/") ~= nil
if not isServer then
    pcall(RegisterHook, "/Script/Engine.HUD:ReceiveDrawHUD", OnHudDraw)
    pcall(RegisterHook, "/Script/Pal.PalHUDInGame:ReceiveDrawHUD", OnHudDraw)
    pcall(RegisterHook, "/Script/Pal.PalHUD:ReceiveDrawHUD", OnHudDraw)
    pcall(RegisterHook, "/Script/Engine.GameViewportClient:PostRender", function(Context, Canvas)
        if Canvas and Canvas:IsValid() then
            OnHudDraw(Canvas)
        end
    end)
    pcall(NotifyOnNewObject, "/Game/Pal/Blueprint/UI/BP_PalHUD_InGame.BP_PalHUD_InGame_C", function()
        pcall(RegisterHook, "/Game/Pal/Blueprint/UI/BP_PalHUD_InGame.BP_PalHUD_InGame_C:ReceiveDrawHUD", OnHudDraw)
    end)
    print("[EconomySystem] Multi-layer HUD draw hooks registered.")
end

-- Screen Click Handler
local function HandleScreenClick(InputX, InputY, ForceInput)
    if not IsShopWindowOpen and not ForceInput then return false end
    local now = os.clock()
    if (now - LastClickTime) < 0.2 then return end
    LastClickTime = now

    local clicked = false
    pcall(function()
        local pc = GetPlayerController()
        if not pc or not pc:IsValid() then return end

        local mouseX, mouseY = tonumber(InputX), tonumber(InputY)
        if (not mouseX or not mouseY) and type(pc.GetMousePosition) == "function" then
            local a, b, c = pc:GetMousePosition()
            if type(a) == "boolean" then
                mouseX, mouseY = tonumber(b), tonumber(c)
            else
                mouseX, mouseY = tonumber(a), tonumber(b)
            end
        end

        if not mouseX or not mouseY then return end

        for _, btn in ipairs(ClickableButtons) do
            if mouseX >= btn.x1 and mouseX <= btn.x2 and mouseY >= btn.y1 and mouseY <= btn.y2 then
                if type(btn.action) == "function" then
                    btn.action()
                    clicked = true
                    break
                end
            end
        end
    end)
    return clicked
end

-- Chat Ingress
local function ProcessChatMessage(Context, Param1, Param2)
    local function DirectController(value)
        local controller = nil
        pcall(function()
            local obj = value and value.get and value:get() or value
            if obj and obj.IsA and obj:IsA("/Script/Pal.PalPlayerController") then
                controller = obj
                return
            end
            if obj and obj.IsA and obj:IsA("/Script/Pal.PalPlayerState") then
                local owner = type(obj.GetOwner) == "function" and obj:GetOwner() or obj.Owner
                if owner and owner.IsA and owner:IsA("/Script/Pal.PalPlayerController") then
                    controller = owner
                    return
                end
            end
            for _, field in ipairs({ "PlayerController", "Sender", "SenderPlayer", "Owner" }) do
                local candidate = obj and obj[field]
                if candidate and candidate.IsA and candidate:IsA("/Script/Pal.PalPlayerController") then
                    controller = candidate
                    return
                end
            end
            if not controller and obj and obj.SenderPlayerUId then
                local function GuidText(guid)
                    local text = ""
                    pcall(function()
                        text = string.format("%08X%08X%08X%08X", guid.A & 0xFFFFFFFF,
                            guid.B & 0xFFFFFFFF, guid.C & 0xFFFFFFFF, guid.D & 0xFFFFFFFF)
                    end)
                    return text
                end
                local senderUid = GuidText(obj.SenderPlayerUId)
                for _, candidate in ipairs(FindAllOf("PalPlayerController") or {}) do
                    local ps = candidate and candidate.PlayerState
                    if ps and ps:IsValid() and GuidText(ps.PlayerUId) == senderUid then
                        controller = candidate
                        return
                    end
                end
            end
        end)
        return controller
    end

    local pc = DirectController(Context) or DirectController(Param1) or DirectController(Param2)
    local Text = ""

    local function TryGetStr(val)
        if not val then return "" end
        local s = ""
        pcall(function()
            local obj = val
            if type(val.get) == "function" then obj = val:get() end
            if type(obj) == "string" then
                s = obj
            elseif type(obj.ToString) == "function" then
                s = obj:ToString()
            elseif obj.Message then
                if type(obj.Message.ToString) == "function" then
                    s = obj.Message:ToString()
                else
                    s = tostring(obj.Message)
                end
            end
        end)
        return s
    end

    Text = TryGetStr(Param1)
    if Text == "" then Text = TryGetStr(Param2) end
    if Text == "" then pcall(function() Text = TryGetStr(Context and Context.Message) end) end

    if not Text or Text == "" then return end
    local cleanText = Text:gsub("^%s+", "")
    local prefix = cleanText:sub(1, 1)
    local body = cleanText
    if prefix == "!" or prefix == "." or prefix == "/" or prefix == "#" then
        body = cleanText:sub(2):gsub("^%s+", "")
    end

    local Args = {}
    for word in body:gmatch("%S+") do
        table.insert(Args, word)
    end
    if #Args == 0 then return end
    local Command = Args[1]:lower()

    local dedupeKey = tostring(pc) .. "|" .. cleanText:lower()
    local now = os.clock()
    if dedupeKey == LastChatCommand and now - LastChatCommandTime < 1.0 then return end
    LastChatCommand, LastChatCommandTime = dedupeKey, now

    print(string.format("[EconomySystem] Command: %s (args: %d)", Command, #Args - 1))

    if Command == "shop" or Command == "store" or Command == "gui" or Command == "help" then
        HandleShopList(pc)
        return
    end

    -- Purchases and point changes must execute only where GameMode exists
    -- (dedicated/listen server or standalone), never on a remote client.
    local gameMode = FindFirstOf("PalGameMode")
    if not gameMode or not gameMode:IsValid() then return end
    if not pc or not pc:IsValid() then
        print("[EconomySystem] Command ignored because its sender could not be resolved safely.")
        return
    end

    if Command == "exchange" or Command == "buy" then
        HandleExchange(pc, Args[2], tonumber(Args[3]) or 1)
    elseif Command == "convert" or Command == "exchange_points" then
        HandleConvertCurrency(pc, Args[2] and Args[2]:lower() or "normal", tonumber(Args[3]) or 1)
    elseif Command == "recycle" or Command == "sell" then
        HandleRecycle(pc, Args[2], tonumber(Args[3]) or 1)
    elseif Command == "gacha" or Command == "roll" then
        HandleGacha(pc, tonumber(Args[2]) or 1)
    elseif Command == "points" or Command == "tech" or Command == "balance" then
        HandleBalance(pc)
    end
end

-- Palworld v0.3.5 chat enters through PlayerState and is then broadcast by
-- GameState. Both are reflected native functions in this build.
local chatHookCount = 0
for _, hookPath in ipairs({
    "/Script/Pal.PalPlayerState:EnterChat",
    "/Script/Pal.PalGameStateInGame:BroadcastChatMessage"
}) do
    local ok, preId = pcall(RegisterHook, hookPath, ProcessChatMessage)
    if ok and preId then
        chatHookCount = chatHookCount + 1
        print("[EconomySystem] Chat ingress registered: " .. hookPath)
    end
end
print(string.format("[EconomySystem] %d chat ingress hook(s) registered.", chatHookCount))

-- Keybinds
pcall(function()
    local function BindKey(k, action)
        if not k then return end
        if type(RegisterKeyBind) == "function" then
            pcall(RegisterKeyBind, k, action)
        elseif type(RegisterKeyBindAsync) == "function" then
            pcall(RegisterKeyBindAsync, k, {}, action)
        end
    end

    if Key then
        BindKey(Key.F6, ToggleShopWindow)
        BindKey(Key.F7, function()
            local p = GetPlayerController()
            HandleGacha(p, 1)
        end)
        BindKey(Key.F8, function()
            local p = GetPlayerController()
            HandleBalance(p)
        end)
        if Key.LeftMouseButton then
            BindKey(Key.LeftMouseButton, HandleScreenClick)
        end
        print("[EconomySystem] Hotkeys registered: [F6] Toggle Shop GUI, [F7] Roll Gacha, [F8] Check Balance.")
    end
end)

-- Register into UniPalUI Dashboard [F5] as an integrated tab
pcall(function()
    if UniPalUI and type(UniPalUI.RegisterTab) == "function" then
        UniPalUI.RegisterTab("🛒 Technology Shop", function(Canvas)
            DrawShopGUI(Canvas, true)
        end, function(X, Y)
            return HandleScreenClick(X, Y, true)
        end)
        print("[EconomySystem] Registered tab with UniPalUI Framework [F5].")
    end
end)

print("[EconomySystem] EconomySystem v3.2.0 Unified Suite initialized successfully.")
