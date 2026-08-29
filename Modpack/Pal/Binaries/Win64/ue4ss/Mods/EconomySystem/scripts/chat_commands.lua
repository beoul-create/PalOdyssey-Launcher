local ChatCommands = {}
local GachaEngine = require("gacha_engine")
local ShopCatalog = require("shop_catalog")

function ChatCommands.Init(LoadedConfig)
    Config = LoadedConfig or {}

    local function HandleIncomingChat(Context, Param1, Param2)
        local SenderPlayer = nil
        local Text = ""

        -- 1. Try to extract player controller/state
        pcall(function()
            if Context and Context.IsA and Context:IsA("/Script/Pal.PalPlayerController") then
                SenderPlayer = Context
            elseif Context and type(Context.get) == "function" then
                local obj = Context:get()
                if obj and obj.IsA and obj:IsA("/Script/Pal.PalPlayerController") then
                    SenderPlayer = obj
                end
            end
        end)

        if not SenderPlayer then
            pcall(function()
                local controllers = FindAllOf("PalPlayerController") or {}
                if #controllers > 0 and controllers[1]:IsValid() then
                    SenderPlayer = controllers[1]
                end
            end)
        end

        -- 2. Extract text from all potential parameter positions
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
        local prefix = Text:sub(1, 1)
        if prefix ~= "/" and prefix ~= "!" then return end

        -- Tokenize command
        local Args = {}
        for word in Text:gmatch("%S+") do
            table.insert(Args, word)
        end

        if #Args == 0 then return end
        local RawCommand = Args[1]:lower()
        local Command = RawCommand:gsub("^[!/]", "")

        if Command == "shop" or Command == "store" then
            ChatCommands.HandleShopList(SenderPlayer)
        elseif Command == "exchange" or Command == "buy" then
            ChatCommands.HandleExchange(SenderPlayer, Args[2], tonumber(Args[3]) or 1)
        elseif Command == "recycle" or Command == "sell" then
            ChatCommands.HandleRecycle(SenderPlayer, Args[2], tonumber(Args[3]) or 1)
        elseif Command == "gacha" or Command == "roll" then
            ChatCommands.HandleGacha(SenderPlayer, tonumber(Args[2]) or 1)
        elseif Command == "points" or Command == "tech" or Command == "balance" then
            ChatCommands.HandleBalance(SenderPlayer)
        elseif Command == "help_economy" or Command == "help" then
            ChatCommands.HandleHelp(SenderPlayer)
        end
    end

    -- Hook all possible chat ingress points
    pcall(RegisterHook, "/Script/Pal.PalChatSubsystem:OnReceivedChatMessage", function(Context, Param1, Param2)
        HandleIncomingChat(Context, Param1, Param2)
    end)
    pcall(RegisterHook, "/Script/Pal.PalChatSubsystem:BroadcastChatMessage", function(Context, Param1, Param2)
        HandleIncomingChat(Context, Param1, Param2)
    end)
    pcall(RegisterHook, "/Script/Pal.PalPlayerController:SendChatMessage", function(Context, Param1, Param2)
        HandleIncomingChat(Context, Param1, Param2)
    end)
    pcall(RegisterHook, "/Script/Pal.PalPlayerController:ClientReceiveChatMessage", function(Context, Param1, Param2)
        HandleIncomingChat(Context, Param1, Param2)
    end)
end

function ChatCommands.SendPlayerMessage(Player, Text, ColorHex)
    pcall(function()
        local str = tostring(Text or "")
        local PalUtil = StaticFindObject("/Script/Pal.Default__PalUtility")
        local pc = Player
        if not pc or not pc:IsValid() then
            pc = FindFirstOf("PalPlayerController")
        end
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
