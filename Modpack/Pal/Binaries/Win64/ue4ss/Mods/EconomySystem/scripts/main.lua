-- ============================================================================
-- EconomySystem - Standalone In-Engine Technology & Ancient Point Economy
-- Supported: !shop, !buy, !recycle, !gacha, !points, [F6], [F7], [F8]
-- ============================================================================

print("[EconomySystem] Booting EconomySystem v2.2.0...")

local Config = {
    GachaCostTechPoints = 3,
    GachaPool = {
        { ItemId = "PalItem_TechnologyBook_G3", Weight = 5, Count = 1, Rarity = "Legendary" },
        { ItemId = "PalSphere_Legend", Weight = 15, Count = 5, Rarity = "Epic" },
        { ItemId = "PalSphere_Master", Weight = 30, Count = 10, Rarity = "Rare" },
        { ItemId = "PalItem_AncientTechnologyPointBook", Weight = 20, Count = 1, Rarity = "Rare" },
        { ItemId = "PalItem_PureQuartz", Weight = 30, Count = 50, Rarity = "Common" }
    },
    ShopItems = {
        cake = { ItemId = "Cake", Cost = 2, Count = 1, Currency = "tech", Desc = "Breeding Cake" },
        legendsphere = { ItemId = "PalSphere_Legend", Cost = 1, Count = 3, Currency = "tech", Desc = "Legendary Pal Sphere x3" },
        ancientcore = { ItemId = "PalItem_AncientCore", Cost = 2, Count = 1, Currency = "ancient", Desc = "Ancient Civilization Core" },
        respec = { ItemId = "PalItem_StatResetMedicine", Cost = 3, Count = 1, Currency = "ancient", Desc = "Memory Reset Drug" }
    },
    RecycleRates = {
        PalItem_TechnologyBook_G1 = 1,
        PalItem_TechnologyBook_G2 = 2,
        PalItem_TechnologyBook_G3 = 5,
        PalItem_AncientCore = 2
    }
}

-- Try to load overrides from config.json safely
pcall(function()
    local ScriptDir = debug.getinfo(1, "S").source:gsub("^@", ""):gsub("[^/\\]+$", "")
    local candidates = {
        ScriptDir .. "../config.json",
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

-- Core Helpers
local function GetPlayerController(Context)
    if Context and Context.IsA and Context:IsA("/Script/Pal.PalPlayerController") then
        return Context
    end
    if Context and type(Context.get) == "function" then
        local obj = Context:get()
        if obj and obj.IsA and obj:IsA("/Script/Pal.PalPlayerController") then
            return obj
        end
    end
    local controllers = FindAllOf("PalPlayerController") or {}
    if #controllers > 0 and controllers[1]:IsValid() then
        return controllers[1]
    end
    return nil
end

local function SendPlayerMessage(Player, Text)
    pcall(function()
        local str = tostring(Text or "")
        local pc = Player or GetPlayerController()
        local PalUtil = StaticFindObject("/Script/Pal.Default__PalUtility")
        if PalUtil and PalUtil:IsValid() and pc and pc:IsValid() then
            PalUtil:SendSystemAnnounce(pc, str)
        end
        local Subsystem = FindFirstOf("PalChatSubsystem")
        if Subsystem and Subsystem:IsValid() and pc and pc:IsValid() then
            Subsystem:SendSystemChatMessage(pc, FText(str))
        end
    end)
    print("[EconomySystem] " .. tostring(Text))
end

local function GetPlayerTechPoints(Player)
    local normalPoints = 0
    local ancientPoints = 0
    pcall(function()
        local pc = Player or GetPlayerController()
        local ParamComp = pc and pc.CharacterParameterComponent
        if ParamComp and ParamComp:IsValid() then
            normalPoints = ParamComp:GetTechnologyPoint() or 0
            if type(ParamComp.GetbossTechnologyPoint) == "function" then
                ancientPoints = ParamComp:GetbossTechnologyPoint() or 0
            end
        end
    end)
    return normalPoints, ancientPoints
end

local function AddPlayerTechPoints(Player, Amount, isAncient)
    local success = false
    pcall(function()
        local pc = Player or GetPlayerController()
        local ParamComp = pc and pc.CharacterParameterComponent
        if ParamComp and ParamComp:IsValid() then
            if isAncient and type(ParamComp.SetbossTechnologyPoint) == "function" then
                local Current = ParamComp:GetbossTechnologyPoint() or 0
                ParamComp:SetbossTechnologyPoint(math.max(0, Current + Amount))
                success = true
            else
                local Current = ParamComp:GetTechnologyPoint() or 0
                ParamComp:SetTechnologyPoint(math.max(0, Current + Amount))
                success = true
            end
        end
    end)
    return success
end

local function GiveItem(Player, ItemId, Count)
    local success = false
    pcall(function()
        local pc = Player or GetPlayerController()
        local InvSubsystem = FindFirstOf("PalInventorySubsystem")
        if InvSubsystem and InvSubsystem:IsValid() and pc and pc:IsValid() then
            local res = InvSubsystem:RequestAddItem(pc, FName(ItemId), Count, true)
            if res ~= false then success = true end
        end
        if not success then
            local PalUtil = StaticFindObject("/Script/Pal.Default__PalUtility")
            if PalUtil and PalUtil:IsValid() and pc and pc:IsValid() then
                if type(PalUtil.AddSingleItemToInventory) == "function" then
                    PalUtil:AddSingleItemToInventory(pc, FName(ItemId), Count)
                    success = true
                end
            end
        end
    end)
    return success
end

local function TakeItem(Player, ItemId, Count)
    local success = false
    pcall(function()
        local pc = Player or GetPlayerController()
        local InvSubsystem = FindFirstOf("PalInventorySubsystem")
        if InvSubsystem and InvSubsystem:IsValid() and pc and pc:IsValid() then
            local result = InvSubsystem:RequestRemoveItem(pc, FName(ItemId), Count)
            success = result ~= false
        end
    end)
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

-- Command Actions
local function HandleShopList(Player)
    local lines = {
        "=== 🛒 TECHNOLOGY POINT SHOP ==="
    }
    if Config.ShopItems then
        for key, item in pairs(Config.ShopItems) do
            local currType = (item.Currency == "ancient") and "Ancient Tech Pts" or "Tech Pts"
            table.insert(lines, string.format("• !buy %s [%s] — %s (%d %s)", key, key, item.Desc or key, item.Cost or 1, currType))
        end
    end
    table.insert(lines, "• !gacha [rolls] — Roll technology gacha (3 Tech Pts/roll)")
    table.insert(lines, "• Shortcuts: [F6] Shop  [F7] Gacha  [F8] Balance")
    SendPlayerMessage(Player, table.concat(lines, "\n"))
end

local function HandleBalance(Player)
    local normPts, ancPts = GetPlayerTechPoints(Player)
    SendPlayerMessage(Player, string.format("💳 Technology Points: %d  |  Ancient Tech Points: %d", normPts, ancPts))
end

local function HandleExchange(Player, ItemKey, Quantity)
    Quantity = math.min(999, math.max(1, math.floor(tonumber(Quantity) or 1)))
    if not ItemKey or not Config.ShopItems or not Config.ShopItems[ItemKey:lower()] then
        SendPlayerMessage(Player, "❌ Invalid item. Use !shop or [F6] to see available items.")
        return
    end

    local Item = Config.ShopItems[ItemKey:lower()]
    local isAncient = (Item.Currency == "ancient")
    local TotalCost = math.max(0, tonumber(Item.Cost) or 1) * Quantity
    local normPts, ancPts = GetPlayerTechPoints(Player)
    local available = isAncient and ancPts or normPts
    local currLabel = isAncient and "Ancient Tech Points" or "Tech Points"

    if available < TotalCost then
        SendPlayerMessage(Player, string.format("❌ Insufficient points. Required: %d %s (Available: %d).", TotalCost, currLabel, available))
        return
    end

    if not AddPlayerTechPoints(Player, -TotalCost, isAncient) then
        SendPlayerMessage(Player, "❌ Purchase failed because point balance could not be updated.")
        return
    end
    if not GiveItem(Player, Item.ItemId, math.max(1, tonumber(Item.Count) or 1) * Quantity) then
        AddPlayerTechPoints(Player, TotalCost, isAncient)
        SendPlayerMessage(Player, "❌ Item delivery failed; points were refunded.")
        return
    end
    SendPlayerMessage(Player, string.format("✅ Purchased %dx %s for %d %s!", Quantity, Item.Desc or ItemKey, TotalCost, currLabel))
end

local function HandleRecycle(Player, ItemKey, Quantity)
    Quantity = math.min(999, math.max(1, math.floor(tonumber(Quantity) or 1)))
    if not ItemKey or not Config.RecycleRates or not Config.RecycleRates[ItemKey] then
        SendPlayerMessage(Player, "❌ This item cannot be recycled into Tech Points.")
        return
    end

    local Rate = math.max(0, tonumber(Config.RecycleRates[ItemKey]) or 1)
    local Payout = Rate * Quantity

    if not TakeItem(Player, ItemKey, Quantity) then
        SendPlayerMessage(Player, "❌ Recycle failed; verify that you have enough of that item.")
        return
    end
    if not AddPlayerTechPoints(Player, Payout, false) then
        GiveItem(Player, ItemKey, Quantity)
        SendPlayerMessage(Player, "❌ Point credit failed; items were restored.")
        return
    end
    SendPlayerMessage(Player, string.format("♻️ Recycled %dx %s for +%d Tech Points!", Quantity, ItemKey, Payout))
end

local function HandleGacha(Player, Rolls)
    Rolls = math.min(math.max(1, math.floor(tonumber(Rolls) or 1)), 10)
    local CostPerRoll = math.max(0, tonumber(Config.GachaCostTechPoints) or 3)
    local TotalCost = CostPerRoll * Rolls
    local normPts, _ = GetPlayerTechPoints(Player)

    if normPts < TotalCost then
        SendPlayerMessage(Player, string.format("❌ Not enough Tech Points. Rolling %dx costs %d points (You have: %d).", Rolls, TotalCost, normPts))
        return
    end

    if not AddPlayerTechPoints(Player, -TotalCost, false) then
        SendPlayerMessage(Player, "❌ Gacha failed because point balance could not be updated.")
        return
    end

    local results = { string.format("🎰 Rolling Gacha (%dx)...", Rolls) }
    for i = 1, Rolls do
        local Outcome = RollGacha(Config.GachaPool)
        if not Outcome or not Outcome.ItemId or not GiveItem(Player, Outcome.ItemId, math.max(1, tonumber(Outcome.Count) or 1)) then
            AddPlayerTechPoints(Player, CostPerRoll, false)
            table.insert(results, "  ❌ Reward delivery failed; this roll was refunded.")
        else
            table.insert(results, string.format("  🎁 [%s] %dx %s", Outcome.Rarity or "Reward", Outcome.Count or 1, Outcome.ItemId))
        end
    end
    SendPlayerMessage(Player, table.concat(results, "\n"))
end

local function HandleHelp(Player)
    local helpText = "=== 📜 ECONOMY SYSTEM COMMANDS ===\n"
        .. "• !shop — View available catalog items\n"
        .. "• !buy <item> [qty] — Purchase item with Tech Points\n"
        .. "• !recycle <item> [qty] — Sell rare books/cores for Tech Points\n"
        .. "• !gacha [1-10] — Roll gacha pool (3 Tech Pts per roll)\n"
        .. "• !points — Check your Tech Point balance\n"
        .. "• Shortcuts: [F6] Shop  |  [F7] Gacha  |  [F8] Balance"
    SendPlayerMessage(Player, helpText)
end

-- Chat Interceptor Dispatcher
local function ProcessChatMessage(Context, Param1, Param2)
    local pc = GetPlayerController(Context)
    local Text = ""

    local function TryGetStr(val)
        if not val then return "" end
        local s = ""
        pcall(function()
            if type(val) == "string" then
                s = val
            elseif type(val.ToString) == "function" then
                s = val:ToString()
            elseif val.Message then
                if type(val.Message.ToString) == "function" then
                    s = val.Message:ToString()
                else
                    s = tostring(val.Message)
                end
            elseif type(val.get) == "function" then
                local inner = val:get()
                s = TryGetStr(inner)
            end
        end)
        return s
    end

    Text = TryGetStr(Param1)
    if Text == "" then Text = TryGetStr(Param2) end
    if Text == "" and Context and Context.Message then Text = TryGetStr(Context.Message) end

    if not Text or Text == "" then return end
    local cleanText = Text:gsub("^%s+", "")
    local prefix = cleanText:sub(1, 1)
    if prefix ~= "/" and prefix ~= "!" then return end

    local body = cleanText:sub(2):gsub("^%s+", "")
    local Args = {}
    for word in body:gmatch("%S+") do
        table.insert(Args, word)
    end
    if #Args == 0 then return end
    local Command = Args[1]:lower()

    print(string.format("[EconomySystem] Intercepted chat command: %s (args: %d)", Command, #Args - 1))

    if Command == "shop" or Command == "store" then
        HandleShopList(pc)
    elseif Command == "exchange" or Command == "buy" then
        HandleExchange(pc, Args[2], tonumber(Args[3]) or 1)
    elseif Command == "recycle" or Command == "sell" then
        HandleRecycle(pc, Args[2], tonumber(Args[3]) or 1)
    elseif Command == "gacha" or Command == "roll" then
        HandleGacha(pc, tonumber(Args[2]) or 1)
    elseif Command == "points" or Command == "tech" or Command == "balance" then
        HandleBalance(pc)
    elseif Command == "help_economy" or Command == "help" then
        HandleHelp(pc)
    end
end

-- Hook Ingress
pcall(RegisterHook, "/Script/Pal.PalChatSubsystem:OnReceivedChatMessage", function(Context, Param1, Param2)
    ProcessChatMessage(Context, Param1, Param2)
end)
pcall(RegisterHook, "/Script/Pal.PalChatSubsystem:BroadcastChatMessage", function(Context, Param1, Param2)
    ProcessChatMessage(Context, Param1, Param2)
end)
pcall(RegisterHook, "/Script/Pal.PalPlayerController:SendChatMessage", function(Context, Param1, Param2)
    ProcessChatMessage(Context, Param1, Param2)
end)
pcall(RegisterHook, "/Script/Pal.PalPlayerController:ClientReceiveChatMessage", function(Context, Param1, Param2)
    ProcessChatMessage(Context, Param1, Param2)
end)

-- Hotkey Registration
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
        BindKey(Key.F6, function()
            local p = GetPlayerController()
            HandleShopList(p)
        end)
        BindKey(Key.F7, function()
            local p = GetPlayerController()
            HandleGacha(p, 1)
        end)
        BindKey(Key.F8, function()
            local p = GetPlayerController()
            HandleBalance(p)
        end)
        print("[EconomySystem] Hotkeys registered: [F6] Open Shop, [F7] Roll Gacha, [F8] Check Balance.")
    end
end)

print("[EconomySystem] EconomySystem v2.2.0 initialized successfully.")

