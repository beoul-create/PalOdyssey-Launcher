-- ============================================================================
-- UniPalUI - Unified Palworld User Interface Framework
-- Safe Viewport UMG & Canvas Menu Coordinator
-- ============================================================================

print("[UniPalUI] Initializing UniPalUI Framework v1.0.0...")

UniPalUI = UniPalUI or {}
UniPalUI.Tabs = UniPalUI.Tabs or {}
UniPalUI.ActiveTab = 1
UniPalUI.IsOpen = false

-- Public Registration API for other mods
function UniPalUI.RegisterTab(tabName, onDrawCallback, onInputCallback)
    table.insert(UniPalUI.Tabs, {
        Name = tabName,
        OnDraw = onDrawCallback,
        OnInput = onInputCallback
    })
    print(string.format("[UniPalUI] Registered tab '%s' (Total Tabs: %d)", tabName, #UniPalUI.Tabs))
end

function UniPalUI.Open()
    UniPalUI.IsOpen = true
    pcall(function()
        local controllers = FindAllOf("PalPlayerController") or {}
        if #controllers > 0 and controllers[1]:IsValid() then
            controllers[1].bShowMouseCursor = true
        end
    end)
end

function UniPalUI.Close()
    UniPalUI.IsOpen = false
    pcall(function()
        local controllers = FindAllOf("PalPlayerController") or {}
        if #controllers > 0 and controllers[1]:IsValid() then
            controllers[1].bShowMouseCursor = false
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

function UniPalUI.DispatchPointerInput()
    if not UniPalUI.IsOpen then return false end
    local tab = UniPalUI.Tabs[UniPalUI.ActiveTab]
    if not tab or type(tab.OnInput) ~= "function" then return false end

    local handled = false
    pcall(function()
        local controllers = FindAllOf("PalPlayerController") or {}
        local pc = controllers[1]
        if not pc or not pc:IsValid() or type(pc.GetMousePosition) ~= "function" then return end
        local a, b, c = pc:GetMousePosition()
        local x, y
        if type(a) == "boolean" then x, y = tonumber(b), tonumber(c)
        else x, y = tonumber(a), tonumber(b) end
        if x and y then handled = tab.OnInput(x, y) == true end
    end)
    return handled
end

-- Hook the native HUD event, which is already reflected when UE4SS starts.
-- The old Blueprint path was not loaded yet and silently registered nothing.
local function DrawDashboard(Context)
    if not UniPalUI.IsOpen then return end
    pcall(function()
        local hud = Context and Context.get and Context:get() or Context
        if hud and hud.Canvas and hud.Canvas:IsValid() then
            local Canvas = hud.Canvas
            local tab = UniPalUI.Tabs[UniPalUI.ActiveTab]
            if tab and type(tab.OnDraw) == "function" then
                tab.OnDraw(Canvas)
            end
        end
    end)
end

local hudOk, hudPreId = pcall(RegisterHook, "/Script/Engine.HUD:ReceiveDrawHUD", DrawDashboard)
if hudOk and hudPreId then
    print("[UniPalUI] Native HUD draw hook registered.")
else
    print("[UniPalUI] Native HUD hook unavailable; arming delayed Pal HUD hook.")
    pcall(NotifyOnNewObject, "/Game/Pal/Blueprint/UI/BP_PalHUD_InGame.BP_PalHUD_InGame_C", function()
        local ok, preId = pcall(RegisterHook,
            "/Game/Pal/Blueprint/UI/BP_PalHUD_InGame.BP_PalHUD_InGame_C:ReceiveDrawHUD", DrawDashboard)
        if ok and preId then print("[UniPalUI] Delayed Pal HUD draw hook registered.") end
    end)
end

-- Register Framework Keybinds (F5: Toggle UniPalUI Dashboard)
pcall(function()
    local function BindKey(k, action)
        if not k then return end
        if type(RegisterKeyBind) == "function" then
            pcall(RegisterKeyBind, k, action)
        elseif type(RegisterKeyBindAsync) == "function" then
            pcall(RegisterKeyBindAsync, k, {}, action)
        end
    end

    if Key and Key.F5 then
        BindKey(Key.F5, UniPalUI.Toggle)
        if Key.LeftMouseButton then BindKey(Key.LeftMouseButton, UniPalUI.DispatchPointerInput) end
        print("[UniPalUI] Hotkey registered: [F5] Toggle UniPalUI Dashboard.")
    end
end)

print("[UniPalUI] UniPalUI Framework initialized successfully.")
