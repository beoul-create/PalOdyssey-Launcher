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

-- Hook Canvas Drawing safely without touching Escape Menu
pcall(RegisterHook, "/Game/Pal/Blueprint/UI/BP_PalHUD_InGame.BP_PalHUD_InGame_C:ReceiveDrawHUD", function(Context)
    if not UniPalUI.IsOpen then return end
    pcall(function()
        local hud = Context:get()
        if hud and hud.Canvas and hud.Canvas:IsValid() then
            local Canvas = hud.Canvas
            local tab = UniPalUI.Tabs[UniPalUI.ActiveTab]
            if tab and type(tab.OnDraw) == "function" then
                tab.OnDraw(Canvas)
            end
        end
    end)
end)

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
        print("[UniPalUI] Hotkey registered: [F5] Toggle UniPalUI Dashboard.")
    end
end)

print("[UniPalUI] UniPalUI Framework initialized successfully.")
