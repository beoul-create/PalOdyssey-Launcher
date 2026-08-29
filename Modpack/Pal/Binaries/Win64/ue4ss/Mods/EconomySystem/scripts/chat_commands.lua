local ChatCommands = {}
local GachaEngine = require("gacha_engine")
local ShopCatalog = require("shop_catalog")

function ChatCommands.Init(LoadedConfig)
    Config = LoadedConfig or {}

    -- Hook server-side chat resolution
    RegisterHook("/Script/Pal.PalChatSubsystem:OnReceivedChatMessage", function(Context, ChatMessage)
        local Message = ChatMessage:get()
        if not Message then return end

        local SenderPlayer = Message.SenderPlayer
        if not SenderPlayer or not SenderPlayer:IsValid() then return end

        local Text = ""
        pcall(function() Text = Message.Message:ToString() end)
        if not Text or Text:sub(1, 1) ~= "/" then return end

        -- Tokenize command
        local Args = {}
        for word in Text:gmatch("%S+") do
            table.insert(Args, word)
        end

        if #Args == 0 then return end
        local Command = Args[1]:lower()

        if Command == "/shop" or Command == "/store" then
            ChatCommands.HandleShopList(SenderPlayer)
        elseif Command == "/exchange" or Command == "/buy" then
            ChatCommands.HandleExchange(SenderPlayer, Args[2], tonumber(Args[3]) or 1)
        elseif Command == "/recycle" or Command == "/sell" then
            ChatCommands.HandleRecycle(SenderPlayer, Args[2], tonumber(Args[3]) or 1)
        elseif Command == "/gacha" or Command == "/roll" then
            ChatCommands.HandleGacha(SenderPlayer, tonumber(Args[2]) or 1)
        elseif Command == "/points" or Command == "/tech" or Command == "/balance" then
            ChatCommands.HandleBalance(SenderPlayer)
        elseif Command == "/help_economy" then
            ChatCommands.HandleHelp(SenderPlayer)
        end
    end)
end

function ChatCommands.SendPlayerMessage(Player, Text, ColorHex)
    pcall(function()
        local Subsystem = FindFirstOf("PalChatSubsystem")
        if Subsystem and Subsystem:IsValid() and Player and Player:IsValid() then
            Subsystem:SendSystemChatMessage(Player, FText(Text))
        end
    end)
end

function ChatCommands.GetPlayerTechPoints(Player)
    local points = 0
    pcall(function()
        local ParamComp = Player.CharacterParameterComponent
        if ParamComp and ParamComp:IsValid() then
            points = ParamComp:GetTechnologyPoint()
        end
    end)
    return points
end

function ChatCommands.AddPlayerTechPoints(Player, Amount)
    local success = false
    pcall(function()
        local ParamComp = Player.CharacterParameterComponent
        if ParamComp and ParamComp:IsValid() then
            local Current = ParamComp:GetTechnologyPoint()
            ParamComp:SetTechnologyPoint(math.max(0, Current + Amount))
            success = true
        end
    end)
    return success
end

function ChatCommands.GiveItem(Player, ItemId, Count)
    local success = false
    pcall(function()
        local InvSubsystem = FindFirstOf("PalInventorySubsystem")
        if InvSubsystem and InvSubsystem:IsValid() and Player and Player:IsValid() then
            local result = InvSubsystem:RequestAddItem(Player, FName(ItemId), Count, true)
            success = result ~= false
        end
    end)
    return success
end

function ChatCommands.TakeItem(Player, ItemId, Count)
    local success = false
    pcall(function()
        local InvSubsystem = FindFirstOf("PalInventorySubsystem")
        if InvSubsystem and InvSubsystem:IsValid() and Player and Player:IsValid() then
            -- Fallback / inventory extraction
            local result = InvSubsystem:RequestRemoveItem(Player, FName(ItemId), Count)
            success = result ~= false
        end
    end)
    return success
end

-- COMMAND HANDLERS
function ChatCommands.HandleHelp(Player)
    ChatCommands.SendPlayerMessage(Player, "=== 📜 ECONOMY SYSTEM COMMANDS ===", "00E5FF")
    ChatCommands.SendPlayerMessage(Player, "• /shop — View available catalog items", "FFFFFF")
    ChatCommands.SendPlayerMessage(Player, "• /exchange <item> [qty] — Purchase item with Tech Points", "FFFFFF")
    ChatCommands.SendPlayerMessage(Player, "• /recycle <item> [qty] — Sell rare books/cores for Tech Points", "FFFFFF")
    ChatCommands.SendPlayerMessage(Player, "• /gacha [1-10] — Roll gacha pool (3 Tech Pts per roll)", "FFFFFF")
    ChatCommands.SendPlayerMessage(Player, "• /points — Check your current Tech Point balance", "FFFFFF")
end

function ChatCommands.HandleShopList(Player)
    ChatCommands.SendPlayerMessage(Player, "=== 🛒 TECHNOLOGY POINT SHOP ===", "00E5FF")
    if Config.ShopItems then
        for key, item in pairs(Config.ShopItems) do
            local line = string.format("• /exchange %s [qty] — %s (%d Tech Pts)", key, item.Desc or key, item.Cost or 1)
            ChatCommands.SendPlayerMessage(Player, line, "FFFFFF")
        end
    end
    ChatCommands.SendPlayerMessage(Player, "• /gacha [rolls] — Roll technology gacha (3 Tech Pts/roll)", "FFAA00")
end

function ChatCommands.HandleBalance(Player)
    local Pts = ChatCommands.GetPlayerTechPoints(Player)
    ChatCommands.SendPlayerMessage(Player, string.format("💳 You currently have %d Technology Point(s).", Pts), "00FF88")
end

function ChatCommands.HandleExchange(Player, ItemKey, Quantity)
    Quantity = math.min(999, math.max(1, math.floor(tonumber(Quantity) or 1)))
    if not ItemKey or not Config.ShopItems or not Config.ShopItems[ItemKey:lower()] then
        ChatCommands.SendPlayerMessage(Player, "❌ Invalid item. Use /shop to see available inventory.", "FF4444")
        return
    end

    local Item = Config.ShopItems[ItemKey:lower()]
    local TotalCost = math.max(0, tonumber(Item.Cost) or 1) * Quantity
    local CurrentPoints = ChatCommands.GetPlayerTechPoints(Player)

    if CurrentPoints < TotalCost then
        ChatCommands.SendPlayerMessage(Player, string.format("❌ Insufficient points. Required: %d, Available: %d.", TotalCost, CurrentPoints), "FF4444")
        return
    end

    -- Process Transaction
    if not ChatCommands.AddPlayerTechPoints(Player, -TotalCost) then
        ChatCommands.SendPlayerMessage(Player, "❌ Purchase failed because the point balance could not be updated.", "FF4444")
        return
    end
    if not ChatCommands.GiveItem(Player, Item.ItemId, math.max(1, tonumber(Item.Count) or 1) * Quantity) then
        ChatCommands.AddPlayerTechPoints(Player, TotalCost)
        ChatCommands.SendPlayerMessage(Player, "❌ Item delivery failed; your Technology Points were refunded.", "FF4444")
        return
    end
    ChatCommands.SendPlayerMessage(Player, string.format("✅ Purchased %dx %s for %d Tech Points!", Quantity, Item.Desc or ItemKey, TotalCost), "00FF88")
end

function ChatCommands.HandleRecycle(Player, ItemKey, Quantity)
    Quantity = math.min(999, math.max(1, math.floor(tonumber(Quantity) or 1)))
    if not ItemKey or not Config.RecycleRates or not Config.RecycleRates[ItemKey] then
        ChatCommands.SendPlayerMessage(Player, "❌ This item cannot be recycled into Tech Points.", "FF4444")
        return
    end

    local Rate = math.max(0, tonumber(Config.RecycleRates[ItemKey]) or 1)
    local Payout = Rate * Quantity

    -- Remove item and credit points
    if not ChatCommands.TakeItem(Player, ItemKey, Quantity) then
        ChatCommands.SendPlayerMessage(Player, "❌ Recycle failed; verify that you have enough of that item.", "FF4444")
        return
    end
    if not ChatCommands.AddPlayerTechPoints(Player, Payout) then
        ChatCommands.GiveItem(Player, ItemKey, Quantity)
        ChatCommands.SendPlayerMessage(Player, "❌ Point credit failed; the removed items were restored.", "FF4444")
        return
    end
    ChatCommands.SendPlayerMessage(Player, string.format("♻️ Recycled %dx %s for +%d Tech Points!", Quantity, ItemKey, Payout), "00FF88")
end

function ChatCommands.HandleGacha(Player, Rolls)
    Rolls = math.min(math.max(1, math.floor(tonumber(Rolls) or 1)), 10)
    local CostPerRoll = math.max(0, tonumber(Config.GachaCostTechPoints) or 3)
    local TotalCost = CostPerRoll * Rolls
    local CurrentPoints = ChatCommands.GetPlayerTechPoints(Player)

    if CurrentPoints < TotalCost then
        ChatCommands.SendPlayerMessage(Player, string.format("❌ Not enough Tech Points. Rolling %dx costs %d points (You have: %d).", Rolls, TotalCost, CurrentPoints), "FF4444")
        return
    end

    if not ChatCommands.AddPlayerTechPoints(Player, -TotalCost) then
        ChatCommands.SendPlayerMessage(Player, "❌ Gacha failed because the point balance could not be updated.", "FF4444")
        return
    end
    ChatCommands.SendPlayerMessage(Player, string.format("🎰 Rolling Gacha (%dx)...", Rolls), "FFAA00")

    for i = 1, Rolls do
        local Outcome = GachaEngine.Roll(Config.GachaPool)
        if not Outcome or not Outcome.ItemId or not ChatCommands.GiveItem(Player, Outcome.ItemId, math.max(1, tonumber(Outcome.Count) or 1)) then
            ChatCommands.AddPlayerTechPoints(Player, CostPerRoll)
            ChatCommands.SendPlayerMessage(Player, "  ❌ Reward delivery failed; this roll was refunded.", "FF4444")
        else
        ChatCommands.SendPlayerMessage(Player, string.format("  🎁 [%s] Received: %dx %s", Outcome.Rarity or "Reward", Outcome.Count or 1, Outcome.ItemId), "FFFFFF")
        end
    end
end

return ChatCommands
