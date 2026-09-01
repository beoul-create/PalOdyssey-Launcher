local isServer = string.find(debug.getinfo(1, "S").source:lower():gsub("\\", "/"), "/palserver/") ~= nil
if isServer then
    print("[UniPalUI] Headless server detected. Disabling client UI subsystem.")
    return
end

print("[UniPalUI] Initializing UniPalUI Framework v1.2.0...")

UniPalUI = UniPalUI or {}
UniPalUI.Tabs = UniPalUI.Tabs or {}
UniPalUI.ActiveTab = 1
UniPalUI.IsOpen = false

local TopNavButtons = {}
local CanvasFont = nil

local function GetFont()
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

-- Public Registration API for other mods
function UniPalUI.RegisterTab(tabName, onDrawCallback, onInputCallback)
    table.insert(UniPalUI.Tabs, {
        Name = tabName,
        OnDraw = onDrawCallback,
        OnInput = onInputCallback
    })
    print(string.format("[UniPalUI] Registered tab '%s' (Total Tabs: %d)", tabName, #UniPalUI.Tabs))
end

local CachedPC = nil
local function GetPC()
    if CachedPC and CachedPC.IsValid and CachedPC:IsValid() then return CachedPC end
    if UEHelpers and type(UEHelpers.GetPlayerController) == "function" then
        local p = UEHelpers.GetPlayerController()
        if p and p:IsValid() then CachedPC = p; return p end
    end
    local p = FindFirstOf("PalPlayerController") or FindFirstOf("PlayerController")
    if p and p:IsValid() then CachedPC = p; return p end
    return nil
end

function UniPalUI.Open()
    UniPalUI.IsOpen = true
    pcall(function()
        local pc = GetPC()
        if pc and pc:IsValid() then
            pc.bShowMouseCursor = true
        end
    end)
end

function UniPalUI.Close()
    UniPalUI.IsOpen = false
    pcall(function()
        local pc = GetPC()
        if pc and pc:IsValid() then
            pc.bShowMouseCursor = false
        end
    end)
end

function UniPalUI.Toggle()
    if UniPalUI.IsOpen then
        UniPalUI.Close()
    else
        UniPalUI.Open()
    end
end

function UniPalUI.OpenTab(tabIdentifier)
    local targetIndex = 1
    if type(tabIdentifier) == "number" then
        targetIndex = tabIdentifier
    elseif type(tabIdentifier) == "string" then
        for i, tab in ipairs(UniPalUI.Tabs) do
            if tab.Name:find(tabIdentifier, 1, true) or tabIdentifier:find(tab.Name, 1, true) then
                targetIndex = i
                break
            end
        end
    end

    if UniPalUI.IsOpen and UniPalUI.ActiveTab == targetIndex then
        UniPalUI.Close()
    else
        UniPalUI.ActiveTab = targetIndex
        UniPalUI.Open()
    end
end

function UniPalUI.DispatchPointerInput(InputX, InputY)
    if not UniPalUI.IsOpen then return false end
    local handled = false

    pcall(function()
        local pc = GetPC()
        if not pc or not pc:IsValid() then return end

        local mouseX, mouseY = tonumber(InputX), tonumber(InputY)
        if (not mouseX or not mouseY) and type(pc.GetMousePosition) == "function" then
            local a, b, c = pc:GetMousePosition()
            if type(a) == "boolean" then mouseX, mouseY = tonumber(b), tonumber(c)
            else mouseX, mouseY = tonumber(a), tonumber(b) end
        end

        if not mouseX or not mouseY then return end

        -- Check Top Nav Bar clicks first
        for _, btn in ipairs(TopNavButtons) do
            if mouseX >= btn.x1 and mouseX <= btn.x2 and mouseY >= btn.y1 and mouseY <= btn.y2 then
                if type(btn.action) == "function" then
                    btn.action()
                    handled = true
                    return
                end
            end
        end

        -- Dispatch to Active Tab
        local tab = UniPalUI.Tabs[UniPalUI.ActiveTab]
        if tab and type(tab.OnInput) == "function" then
            handled = tab.OnInput(mouseX, mouseY) == true
        end
    end)
    return handled
end

-- Universal HUD Canvas Draw Pipeline
local function DrawDashboard(Context, CanvasParam)
    if not UniPalUI.IsOpen then return end
    pcall(function()
        local Canvas = CanvasParam
        if not Canvas or not Canvas:IsValid() then
            local hud = Context and Context.get and Context:get() or Context
            Canvas = (hud and hud.Canvas and hud.Canvas:IsValid() and hud.Canvas) or (Context and Context.Canvas) or nil
        end
        if not Canvas or not Canvas:IsValid() then return end

        TopNavButtons = {}
        local WinX, WinY = 280, 96
        local BarW, BarH = 760, 38

        -- Draw Top Nav Bar
        if type(Canvas.K2_DrawBox) == "function" then
            Canvas:K2_DrawBox({ X = WinX, Y = WinY }, { X = BarW, Y = BarH }, 1.0, { R = 0.04, G = 0.07, B = 0.12, A = 0.98 })
            Canvas:K2_DrawBox({ X = WinX - 2, Y = WinY - 2 }, { X = BarW + 4, Y = BarH + 4 }, 2.0, { R = 0.0, G = 0.85, B = 1.0, A = 1.0 })
        end

        -- Draw Tab Buttons
        local curX = WinX + 10
        local font = GetFont()
        for i, tab in ipairs(UniPalUI.Tabs) do
            local tabW = 200
            local isActive = (i == UniPalUI.ActiveTab)
            local bgCol = isActive and { R = 0.0, G = 0.5, B = 0.8, A = 0.9 } or { R = 0.1, G = 0.15, B = 0.22, A = 0.8 }
            local borderCol = isActive and { R = 0.0, G = 0.9, B = 1.0, A = 1.0 } or { R = 0.3, G = 0.4, B = 0.5, A = 0.5 }
            local textCol = isActive and { R = 1.0, G = 1.0, B = 1.0, A = 1.0 } or { R = 0.7, G = 0.8, B = 0.9, A = 0.9 }

            if type(Canvas.K2_DrawBox) == "function" then
                Canvas:K2_DrawBox({ X = curX, Y = WinY + 4 }, { X = tabW, Y = BarH - 8 }, 1.0, bgCol)
                Canvas:K2_DrawBox({ X = curX, Y = WinY + 4 }, { X = tabW, Y = BarH - 8 }, 1.0, borderCol)
            end
            if type(Canvas.K2_DrawText) == "function" and font then
                Canvas:K2_DrawText(font, tab.Name, { X = curX + 12, Y = WinY + 8 }, { X = 0.95, Y = 0.95 }, textCol, 0.0, { R = 0, G = 0, B = 0, A = 1 }, { X = 0, Y = 0 }, false, false, false, { R = 0, G = 0, B = 0, A = 1 })
            end

            local tabIdx = i
            table.insert(TopNavButtons, {
                x1 = curX, y1 = WinY + 4, x2 = curX + tabW, y2 = WinY + BarH - 4,
                action = function() UniPalUI.ActiveTab = tabIdx end
            })
            curX = curX + tabW + 8
        end

        -- Close Button [✕ Close]
        local closeX = WinX + BarW - 90
        if type(Canvas.K2_DrawBox) == "function" then
            Canvas:K2_DrawBox({ X = closeX, Y = WinY + 4 }, { X = 80, Y = BarH - 8 }, 1.0, { R = 0.6, G = 0.1, B = 0.1, A = 0.9 })
        end
        if type(Canvas.K2_DrawText) == "function" and font then
            Canvas:K2_DrawText(font, "✕ Close", { X = closeX + 14, Y = WinY + 8 }, { X = 0.95, Y = 0.95 }, { R = 1, G = 1, B = 1, A = 1 }, 0.0, { R = 0, G = 0, B = 0, A = 1 }, { X = 0, Y = 0 }, false, false, false, { R = 0, G = 0, B = 0, A = 1 })
        end
        table.insert(TopNavButtons, {
            x1 = closeX, y1 = WinY + 4, x2 = closeX + 80, y2 = WinY + BarH - 4,
            action = function() UniPalUI.Close() end
        })

        -- Draw Content of Active Tab
        local activeTab = UniPalUI.Tabs[UniPalUI.ActiveTab]
        if activeTab and type(activeTab.OnDraw) == "function" then
            activeTab.OnDraw(Canvas)
        end
    end)
end

-- Multi-layer HUD hooks
pcall(RegisterHook, "/Script/Engine.HUD:ReceiveDrawHUD", DrawDashboard)
pcall(RegisterHook, "/Script/Pal.PalHUDInGame:ReceiveDrawHUD", DrawDashboard)
pcall(RegisterHook, "/Script/Pal.PalHUD:ReceiveDrawHUD", DrawDashboard)
pcall(RegisterHook, "/Script/Engine.GameViewportClient:PostRender", function(Context, Canvas)
    if Canvas and Canvas:IsValid() then DrawDashboard(Context, Canvas) end
end)
pcall(NotifyOnNewObject, "/Game/Pal/Blueprint/UI/BP_PalHUD_InGame.BP_PalHUD_InGame_C", function()
    pcall(RegisterHook, "/Game/Pal/Blueprint/UI/BP_PalHUD_InGame.BP_PalHUD_InGame_C:ReceiveDrawHUD", DrawDashboard)
end)

-- Register Framework Keybinds
pcall(function()
    local function BindKey(k, action)
        if not k then return end
        local wrapped = function()
            if type(ExecuteInGameThread) == "function" then
                ExecuteInGameThread(function() pcall(action) end)
            else
                pcall(action)
            end
        end
        if type(RegisterKeyBind) == "function" then
            pcall(RegisterKeyBind, k, wrapped)
        elseif type(RegisterKeyBindAsync) == "function" then
            pcall(RegisterKeyBindAsync, k, {}, wrapped)
        end
    end

    local f5Key = (Key and Key.F5) or 0x74
    local lmbKey = (Key and Key.LeftMouseButton) or 0x01

    BindKey(f5Key, UniPalUI.Toggle)
    BindKey(lmbKey, function()
        if UniPalUI.IsOpen then UniPalUI.DispatchPointerInput() end
    end)
    print("[UniPalUI] Hotkey registered: [F5] Toggle Dashboard.")
end)

print("[UniPalUI] UniPalUI Framework initialized successfully.")
