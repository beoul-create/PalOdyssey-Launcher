local ChatCommands = {}
local GachaEngine = require("gacha_engine")
local ShopCatalog = require("shop_catalog")

function ChatCommands.Init(LoadedConfig)
    Config = LoadedConfig or {}

    local function HandleIncomingChat(Context, Param1, Param2)
        local SenderPlayer = nil
        local Text = ""

        -- 1. Extract Player Controller
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

        -- 2. Extract Text
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
    local normalPoints = 0
    local ancientPoints = 0
    pcall(function()
        local ParamComp = Player.CharacterParameterComponent
        if ParamComp and ParamComp:IsValid() then
            normalPoints = ParamComp:GetTechnologyPoint() or 0
            if type(ParamComp.GetbossTechnologyPoint) == "function" then
                ancientPoints = ParamComp:GetbossTechnologyPoint() or 0
            end
        end
    end)
    return normalPoints, ancientPoints
end

function ChatCommands.AddPlayerTechPoints(Player, Amount, isAncient)
    local success = false
    pcall(function()
        local ParamComp = Player.CharacterParameterComponent
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

function ChatCommands.GiveItem(Player, ItemId, Count)
    local success = false
    pcall(function()
        local InvSubsystem = FindFirstOf("PalInventorySubsystem")
        if InvSubsystem and InvSubsystem:IsValid() and Player and Player:IsValid() then
            local res = InvSubsystem:RequestAddItem(Player, FName(ItemId), Count, true)
            if res ~= false then success = true end
        end
        if not success then
            local PalUtil = StaticFindObject("/Script/Pal.Default__PalUtility")
            if PalUtil and PalUtil:IsValid() and Player and Player:IsValid() then
                if type(PalUtil.AddSingleItemToInventory) == "function" then
                    PalUtil:AddSingleItemToInventory(Player, FName(ItemId), Count)
                    success = true
                end
            end
        end
    end)
    return success
end

function ChatCommands.TakeItem(Player, ItemId, Count)
    local success = false
    pcall(function()
        local InvSubsystem = FindFirstOf("PalInventorySubsystem")
        if InvSubsystem and InvSubsystem:IsValid() and Player and Player:IsValid() then
            local result = InvSubsystem:RequestRemoveItem(Player, FName(ItemId), Count)
            success = result ~= false
        end
    end)
    return success
end

-- COMMAND HANDLERS
function ChatCommands.HandleHelp(Player)
    local helpText = "=== 📜 ECONOMY SYSTEM COMMANDS ===\n"
        .. "• !shop — View available catalog items\n"
        .. "• !buy <item> [qty] — Purchase item with Tech Points\n"
        .. "• !recycle <item> [qty] — Sell rare books/cores for Tech Points\n"
        .. "• !gacha [1-10] — Roll gacha pool (3 Tech Pts per roll)\n"
        .. "• !points — Check your Tech Point balance\n"
        .. "• [F6] Shop  |  [F7] Gacha  |  [F8] Balance"
    ChatCommands.SendPlayerMessage(Player, helpText)
end

function ChatCommands.HandleShopList(Player)
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

    ChatCommands.SendPlayerMessage(Player, table.concat(lines, "\n"))
end

function ChatCommands.HandleBalance(Player)
    local normPts, ancPts = ChatCommands.GetPlayerTechPoints(Player)
    ChatCommands.SendPlayerMessage(Player, string.format("💳 Technology Points: %d  |  Ancient Tech Points: %d", normPts, ancPts))
end

function ChatCommands.HandleExchange(Player, ItemKey, Quantity)
    Quantity = math.min(999, math.max(1, math.floor(tonumber(Quantity) or 1)))
    if not ItemKey or not Config.ShopItems or not Config.ShopItems[ItemKey:lower()] then
        ChatCommands.SendPlayerMessage(Player, "❌ Invalid item. Use !shop or [F6] to see available items.")
        return
    end

    local Item = Config.ShopItems[ItemKey:lower()]
    local isAncient = (Item.Currency == "ancient")
    local TotalCost = math.max(0, tonumber(Item.Cost) or 1) * Quantity
    local normPts, ancPts = ChatCommands.GetPlayerTechPoints(Player)
    local available = isAncient and ancPts or normPts
    local currLabel = isAncient and "Ancient Tech Points" or "Tech Points"

    if available < TotalCost then
        ChatCommands.SendPlayerMessage(Player, string.format("❌ Insufficient points. Required: %d %s (Available: %d).", TotalCost, currLabel, available))
        return
    end

    -- Process Transaction
    if not ChatCommands.AddPlayerTechPoints(Player, -TotalCost, isAncient) then
        ChatCommands.SendPlayerMessage(Player, "❌ Purchase failed because point balance could not be updated.")
        return
    end
    if not ChatCommands.GiveItem(Player, Item.ItemId, math.max(1, tonumber(Item.Count) or 1) * Quantity) then
        ChatCommands.AddPlayerTechPoints(Player, TotalCost, isAncient)
        ChatCommands.SendPlayerMessage(Player, "❌ Item delivery failed; points were refunded.")
        return
    end
    ChatCommands.SendPlayerMessage(Player, string.format("✅ Purchased %dx %s for %d %s!", Quantity, Item.Desc or ItemKey, TotalCost, currLabel))
end

function ChatCommands.HandleRecycle(Player, ItemKey, Quantity)
    Quantity = math.min(999, math.max(1, math.floor(tonumber(Quantity) or 1)))
    if not ItemKey or not Config.RecycleRates or not Config.RecycleRates[ItemKey] then
        ChatCommands.SendPlayerMessage(Player, "❌ This item cannot be recycled into Tech Points.")
        return
    end

    local Rate = math.max(0, tonumber(Config.RecycleRates[ItemKey]) or 1)
    local Payout = Rate * Quantity

    -- Remove item and credit points
    if not ChatCommands.TakeItem(Player, ItemKey, Quantity) then
        ChatCommands.SendPlayerMessage(Player, "❌ Recycle failed; verify that you have enough of that item.")
        return
    end
    if not ChatCommands.AddPlayerTechPoints(Player, Payout, false) then
        ChatCommands.GiveItem(Player, ItemKey, Quantity)
        ChatCommands.SendPlayerMessage(Player, "❌ Point credit failed; items were restored.")
        return
    end
    ChatCommands.SendPlayerMessage(Player, string.format("♻️ Recycled %dx %s for +%d Tech Points!", Quantity, ItemKey, Payout))
end

function ChatCommands.HandleGacha(Player, Rolls)
    Rolls = math.min(math.max(1, math.floor(tonumber(Rolls) or 1)), 10)
    local CostPerRoll = math.max(0, tonumber(Config.GachaCostTechPoints) or 3)
    local TotalCost = CostPerRoll * Rolls
    local normPts, _ = ChatCommands.GetPlayerTechPoints(Player)

    if normPts < TotalCost then
        ChatCommands.SendPlayerMessage(Player, string.format("❌ Not enough Tech Points. Rolling %dx costs %d points (You have: %d).", Rolls, TotalCost, normPts))
        return
    end

    if not ChatCommands.AddPlayerTechPoints(Player, -TotalCost, false) then
        ChatCommands.SendPlayerMessage(Player, "❌ Gacha failed because point balance could not be updated.")
        return
    end

    local results = { string.format("🎰 Rolling Gacha (%dx)...", Rolls) }

    for i = 1, Rolls do
        local Outcome = GachaEngine.Roll(Config.GachaPool)
        if not Outcome or not Outcome.ItemId or not ChatCommands.GiveItem(Player, Outcome.ItemId, math.max(1, tonumber(Outcome.Count) or 1)) then
            ChatCommands.AddPlayerTechPoints(Player, CostPerRoll, false)
            table.insert(results, "  ❌ Reward delivery failed; this roll was refunded.")
        else
            table.insert(results, string.format("  🎁 [%s] %dx %s", Outcome.Rarity or "Reward", Outcome.Count or 1, Outcome.ItemId))
        end
    end
    ChatCommands.SendPlayerMessage(Player, table.concat(results, "\n"))
end

return ChatCommands

