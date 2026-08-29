-- ============================================================================
-- EconomySystem v2.5.0 - Interactive Technology Point & Ancient Point Shop
-- Features:
--   • [F6] Interactive Graphical Shop Window with Clickable [BUY] / [GACHA] buttons
--   • Live Mouse Cursor & Focus Management (Canvas HUD)
--   • Silent Private Chat Interception (!shop, !buy, !gacha, !recycle, !points)
--   • Top HUD Banner & Persistent Chat Receipts
-- ============================================================================

print("[EconomySystem] Booting EconomySystem v2.5.0 Interactive Suite...")

local Config = {
    GachaCostTechPoints = 3,
    GachaPool = {},
    ShopItems = {
        respec = { ItemId = "PalItem_StatResetMedicine", Cost = 3, Count = 1, Currency = "ancient", Desc = "Memory Reset Drug" }
    },
    RecycleRates = {}
}

-- Safe config loader
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
                    print("[EconomySystem] Loaded configuration from: " .. path)
                    return
                end
            end
        end
    end
end)

-- UI & State Variables
local IsShopWindowOpen = false
local ClickableButtons = {} -- { { x1, y1, x2, y2, action } }
local LastClickTime = 0

-- Core Game State Accessors
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

-- Transactions
local function HandleExchange(Player, ItemKey, Quantity)
    Quantity = math.min(999, math.max(1, math.floor(tonumber(Quantity) or 1)))
    if not ItemKey or not Config.ShopItems or not Config.ShopItems[ItemKey:lower()] then
        SendPlayerMessage(Player, "❌ Invalid item key.")
        return
    end

    local Item = Config.ShopItems[ItemKey:lower()]
    local isAncient = (Item.Currency == "ancient")
    local TotalCost = math.max(0, tonumber(Item.Cost) or 1) * Quantity
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
    if not GiveItem(Player, Item.ItemId, math.max(1, tonumber(Item.Count) or 1) * Quantity) then
        AddPlayerTechPoints(Player, TotalCost, isAncient)
        SendPlayerMessage(Player, "❌ Item delivery failed; points refunded.")
        return
    end
    SendPlayerMessage(Player, string.format("✅ Purchased %dx %s for %d %s!", Quantity, Item.Desc or ItemKey, TotalCost, currLabel))
end

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
            table.insert(results, string.format("  🎁 [%s] %dx %s", Outcome.Rarity or "Reward", Outcome.Count or 1, Outcome.ItemId))
        end
    end
    SendPlayerMessage(Player, table.concat(results, "\n"))
end

local function HandleRecycle(Player, ItemKey, Quantity)
    Quantity = math.min(999, math.max(1, math.floor(tonumber(Quantity) or 1)))
    if not ItemKey or not Config.RecycleRates or not Config.RecycleRates[ItemKey] then
        SendPlayerMessage(Player, "❌ Item cannot be recycled.")
        return
    end

    local Rate = math.max(0, tonumber(Config.RecycleRates[ItemKey]) or 1)
    local Payout = Rate * Quantity

    if not TakeItem(Player, ItemKey, Quantity) then
        SendPlayerMessage(Player, "❌ You do not have enough of that item.")
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
    local lines = { "=== 🛒 TECHNOLOGY POINT SHOP ===" }
    if Config.ShopItems then
        for key, item in pairs(Config.ShopItems) do
            local currType = (item.Currency == "ancient") and "Ancient Tech Pts" or "Tech Pts"
            table.insert(lines, string.format("• !buy %s — %s (%d %s)", key, item.Desc or key, item.Cost or 1, currType))
        end
    end
    table.insert(lines, "• !gacha [rolls] — Roll technology gacha (3 Tech Pts/roll)")
    table.insert(lines, "• Press [F6] to open interactive GUI!")
    SendPlayerMessage(Player, table.concat(lines, "\n"))
end

local function HandleBalance(Player)
    local normPts, ancPts = GetPlayerTechPoints(Player)
    SendPlayerMessage(Player, string.format("💳 Technology Points: %d  |  Ancient Tech Points: %d", normPts, ancPts))
end

-- Toggle Interactive Window
local function ToggleShopWindow()
    IsShopWindowOpen = not IsShopWindowOpen
    pcall(function()
        local pc = GetPlayerController()
        if pc and pc:IsValid() then
            pc.bShowMouseCursor = IsShopWindowOpen
        end
    end)
    if IsShopWindowOpen then
        print("[EconomySystem] Interactive Shop GUI opened.")
    else
        print("[EconomySystem] Interactive Shop GUI closed.")
    end
end

-- Interactive Canvas HUD Renderer
local function DrawShopGUI(Canvas)
    if not IsShopWindowOpen or not Canvas then return end
    ClickableButtons = {}

    local pc = GetPlayerController()
    if not pc or not pc:IsValid() then return end

    local normPts, ancPts = GetPlayerTechPoints(pc)

    -- Window Dimensions (Centered)
    local WinW, WinH = 680, 520
    local WinX, WinY = 320, 180

    -- Background Box
    pcall(function()
        if type(Canvas.K2_DrawBox) == "function" then
            Canvas:K2_DrawBox({ X = WinX, Y = WinY }, { X = WinW, Y = WinH }, 1.0, { R = 0.06, G = 0.10, B = 0.16, A = 0.95 })
            Canvas:K2_DrawBox({ X = WinX - 2, Y = WinY - 2 }, { X = WinW + 4, Y = WinH + 4 }, 2.0, { R = 0.0, G = 0.9, B = 1.0, A = 1.0 })
        end
    end)

    -- Title & Balance
    pcall(function()
        if type(Canvas.K2_DrawText) == "function" then
            Canvas:K2_DrawText(nil, "🛒 PALODYSSEY TECHNOLOGY SHOP", { X = WinX + 24, Y = WinY + 20 }, { X = 1.2, Y = 1.2 }, { R = 0.0, G = 0.9, B = 1.0, A = 1.0 }, 0.0, { R = 0, G = 0, B = 0, A = 1 }, { X = 0, Y = 0 }, false, false, false, { R = 0, G = 0, B = 0, A = 1 })
            Canvas:K2_DrawText(nil, string.format("Tech Points: %d   |   Ancient Points: %d", normPts, ancPts), { X = WinX + 24, Y = WinY + 52 }, { X = 1.0, Y = 1.0 }, { R = 1.0, G = 0.84, B = 0.0, A = 1.0 }, 0.0, { R = 0, G = 0, B = 0, A = 1 }, { X = 0, Y = 0 }, false, false, false, { R = 0, G = 0, B = 0, A = 1 })
        end
    end)

    -- Close Button [✕]
    local CloseX, CloseY, CloseW, CloseH = WinX + WinW - 40, WinY + 16, 28, 28
    pcall(function()
        if type(Canvas.K2_DrawBox) == "function" then
            Canvas:K2_DrawBox({ X = CloseX, Y = CloseY }, { X = CloseW, Y = CloseH }, 1.0, { R = 0.8, G = 0.2, B = 0.2, A = 1.0 })
        end
        if type(Canvas.K2_DrawText) == "function" then
            Canvas:K2_DrawText(nil, "X", { X = CloseX + 8, Y = CloseY + 4 }, { X = 1.1, Y = 1.1 }, { R = 1, G = 1, B = 1, A = 1 }, 0.0, { R = 0, G = 0, B = 0, A = 1 }, { X = 0, Y = 0 }, false, false, false, { R = 0, G = 0, B = 0, A = 1 })
        end
    end)
    table.insert(ClickableButtons, { x1 = CloseX, y1 = CloseY, x2 = CloseX + CloseW, y2 = CloseY + CloseH, action = ToggleShopWindow })

    -- Shop Items List
    local ItemStartY = WinY + 90
    local RowIndex = 0
    if Config.ShopItems then
        for key, item in pairs(Config.ShopItems) do
            local RowY = ItemStartY + (RowIndex * 64)
            local isAncient = (item.Currency == "ancient")
            local currName = isAncient and "Ancient Pts" or "Tech Pts"
            local costColor = isAncient and { R = 1.0, G = 0.4, B = 0.8, A = 1.0 } or { R = 0.0, G = 1.0, B = 0.6, A = 1.0 }

            -- Item Card Outline
            pcall(function()
                if type(Canvas.K2_DrawBox) == "function" then
                    Canvas:K2_DrawBox({ X = WinX + 20, Y = RowY }, { X = WinW - 40, Y = 54 }, 1.0, { R = 0.12, G = 0.18, B = 0.26, A = 0.85 })
                end
                if type(Canvas.K2_DrawText) == "function" then
                    Canvas:K2_DrawText(nil, item.Desc or key, { X = WinX + 32, Y = RowY + 8 }, { X = 1.0, Y = 1.0 }, { R = 1, G = 1, B = 1, A = 1 }, 0.0, { R = 0, G = 0, B = 0, A = 1 }, { X = 0, Y = 0 }, false, false, false, { R = 0, G = 0, B = 0, A = 1 })
                    Canvas:K2_DrawText(nil, string.format("Price: %d %s", item.Cost or 1, currName), { X = WinX + 32, Y = RowY + 28 }, { X = 0.9, Y = 0.9 }, costColor, 0.0, { R = 0, G = 0, B = 0, A = 1 }, { X = 0, Y = 0 }, false, false, false, { R = 0, G = 0, B = 0, A = 1 })
                end
            end)

            -- [BUY 1] Button
            local BtnX, BtnY, BtnW, BtnH = WinX + WinW - 140, RowY + 12, 100, 30
            pcall(function()
                if type(Canvas.K2_DrawBox) == "function" then
                    Canvas:K2_DrawBox({ X = BtnX, Y = BtnY }, { X = BtnW, Y = BtnH }, 1.0, { R = 0.0, G = 0.7, B = 0.4, A = 1.0 })
                end
                if type(Canvas.K2_DrawText) == "function" then
                    Canvas:K2_DrawText(nil, "BUY 1", { X = BtnX + 26, Y = BtnY + 6 }, { X = 0.95, Y = 0.95 }, { R = 1, G = 1, B = 1, A = 1 }, 0.0, { R = 0, G = 0, B = 0, A = 1 }, { X = 0, Y = 0 }, false, false, false, { R = 0, G = 0, B = 0, A = 1 })
                end
            end)

            table.insert(ClickableButtons, {
                x1 = BtnX, y1 = BtnY, x2 = BtnX + BtnW, y2 = BtnY + BtnH,
                action = function() HandleExchange(pc, key, 1) end
            })

            RowIndex = RowIndex + 1
        end
    end

    -- Bottom Bar Actions: [🎰 ROLL GACHA (3 PTS)] & [♻️ RECYCLE]
    local BottomY = WinY + WinH - 64
    local GachaX, GachaY, GachaW, GachaH = WinX + 24, BottomY, 260, 40
    pcall(function()
        if type(Canvas.K2_DrawBox) == "function" then
            Canvas:K2_DrawBox({ X = GachaX, Y = GachaY }, { X = GachaW, Y = GachaH }, 1.0, { R = 0.9, G = 0.5, B = 0.0, A = 1.0 })
        end
        if type(Canvas.K2_DrawText) == "function" then
            Canvas:K2_DrawText(nil, "🎰 ROLL GACHA (3 Pts)", { X = GachaX + 36, Y = GachaY + 10 }, { X = 1.0, Y = 1.0 }, { R = 1, G = 1, B = 1, A = 1 }, 0.0, { R = 0, G = 0, B = 0, A = 1 }, { X = 0, Y = 0 }, false, false, false, { R = 0, G = 0, B = 0, A = 1 })
        end
    end)
    table.insert(ClickableButtons, {
        x1 = GachaX, y1 = GachaY, x2 = GachaX + GachaW, y2 = GachaY + GachaH,
        action = function() HandleGacha(pc, 1) end
    })

    local InfoX, InfoY = WinX + 310, BottomY + 10
    pcall(function()
        if type(Canvas.K2_DrawText) == "function" then
            Canvas:K2_DrawText(nil, "Shortcuts: [F6] Close | [F7] Gacha | [F8] Pts", { X = InfoX, Y = InfoY }, { X = 0.85, Y = 0.85 }, { R = 0.7, G = 0.8, B = 0.9, A = 1.0 }, 0.0, { R = 0, G = 0, B = 0, A = 1 }, { X = 0, Y = 0 }, false, false, false, { R = 0, G = 0, B = 0, A = 1 })
        end
    end)
end

-- Register HUD Hook
pcall(RegisterHook, "/Game/Pal/Blueprint/UI/BP_PalHUD_InGame.BP_PalHUD_InGame_C:ReceiveDrawHUD", function(Context)
    pcall(function()
        local hud = Context:get()
        if hud and hud.Canvas and hud.Canvas:IsValid() then
            DrawShopGUI(hud.Canvas)
        end
    end)
end)

-- Mouse Click Handler for GUI Buttons
local function HandleScreenClick()
    if not IsShopWindowOpen then return end
    local now = os.clock()
    if (now - LastClickTime) < 0.2 then return end -- Debounce clicks
    LastClickTime = now

    pcall(function()
        local pc = GetPlayerController()
        if not pc or not pc:IsValid() then return end

        local mouseX, mouseY = 0, 0
        if type(pc.GetMousePosition) == "function" then
            local mx, my = pc:GetMousePosition(0, 0)
            if mx and my then mouseX, mouseY = mx, my end
        end

        for _, btn in ipairs(ClickableButtons) do
            if mouseX >= btn.x1 and mouseX <= btn.x2 and mouseY >= btn.y1 and mouseY <= btn.y2 then
                btn.action()
                return
            end
        end
    end)
end

-- Chat Ingress
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

    print(string.format("[EconomySystem] Chat command: %s (args: %d)", Command, #Args - 1))

    if Command == "shop" or Command == "store" or Command == "gui" then
        ToggleShopWindow()
    elseif Command == "exchange" or Command == "buy" then
        HandleExchange(pc, Args[2], tonumber(Args[3]) or 1)
    elseif Command == "recycle" or Command == "sell" then
        HandleRecycle(pc, Args[2], tonumber(Args[3]) or 1)
    elseif Command == "gacha" or Command == "roll" then
        HandleGacha(pc, tonumber(Args[2]) or 1)
    elseif Command == "points" or Command == "tech" or Command == "balance" then
        HandleBalance(pc)
    end
end

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

-- Keybinds Registration
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
        print("[EconomySystem] Hotkeys registered: [F6] Toggle Shop GUI, [F7] Roll Gacha, [F8] Balance.")
    end
end)

print("[EconomySystem] EconomySystem v2.5.0 Interactive Suite initialized.")


