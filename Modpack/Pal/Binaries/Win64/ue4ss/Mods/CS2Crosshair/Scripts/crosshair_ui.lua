-- ============================================================================
-- CS2Crosshair: Interactive In-Game CS2 Crosshair Studio GUI
-- Inspired by Counter-Strike 2 Crosshair Settings Menu with Live Preview,
-- Pro Presets, Sliders, Colors, T-Style, Outlines, and Center Dot Adjusters.
-- ============================================================================

local CrosshairUI = {
    isOpen = false,
    activePC = nil,
    previewWidget = nil
}

local ProPresets = {
    ["S1mple"] = { size = 5.0, thick = 1.5, gap = 2.0, dot = true, dotSize = 1.5, outline = true, outThick = 1.0, tStyle = false, color = "Cyan" },
    ["NiKo"]   = { size = 6.0, thick = 2.0, gap = 3.0, dot = false, dotSize = 2.0, outline = true, outThick = 1.0, tStyle = false, color = "Green" },
    ["TenZ"]   = { size = 4.0, thick = 2.0, gap = 1.0, dot = true, dotSize = 2.0, outline = false, outThick = 1.0, tStyle = false, color = "Yellow" },
    ["Shroud"] = { size = 7.0, thick = 2.5, gap = 4.0, dot = false, dotSize = 2.0, outline = true, outThick = 1.0, tStyle = false, color = "Cyan" },
    ["ZywOo"]  = { size = 6.0, thick = 2.0, gap = 2.0, dot = false, dotSize = 2.0, outline = true, outThick = 1.0, tStyle = false, color = "Green" }
}

local function GetLocalPC()
    local pc = nil
    pcall(function()
        pc = UEHelpers.GetPlayerController() or FindFirstOf("PalPlayerController")
    end)
    return pc
end

function CrosshairUI.ApplyPreset(presetName)
    local p = ProPresets[presetName]
    if not p then return end
    
    local main = _G.CS2Crosshair
    if main and main.GetConfig then
        local cfg = main.GetConfig()
        cfg.size = p.size
        cfg.thickness = p.thick
        cfg.gap = p.gap
        cfg.dot = p.dot
        cfg.dotSize = p.dotSize
        cfg.drawOutline = p.outline
        cfg.outlineThickness = p.outThick
        cfg.tStyle = p.tStyle
        cfg.colorPreset = p.color
        
        if main.NotifyToast then
            main.NotifyToast(string.format("🎯 Applied Pro Preset: %s", presetName), 0.0, 0.95, 1.0)
        end
    end
end

function CrosshairUI.Show()
    if CrosshairUI.isOpen then return end
    
    local pc = GetLocalPC()
    if not pc or not pc:IsValid() then return end
    CrosshairUI.activePC = pc

    pcall(function()
        pc.bShowMouseCursor = true
        if pc.SetShowMouseCursor then pc:SetShowMouseCursor(true) end
        if pc.SetInputMode_GameAndUI then pc:SetInputMode_GameAndUI() end
    end)

    CrosshairUI.isOpen = true
    
    local main = _G.CS2Crosshair
    if main and main.NotifyToast then
        main.NotifyToast("🎯 CS2 Crosshair Studio Opened (Press F7 or ESC to Close)", 0.0, 0.95, 1.0)
    end
end

function CrosshairUI.Hide()
    if not CrosshairUI.isOpen then return end
    CrosshairUI.isOpen = false

    pcall(function()
        local pc = CrosshairUI.activePC or GetLocalPC()
        if pc and pc:IsValid() then
            pc.bShowMouseCursor = false
            if pc.SetShowMouseCursor then pc:SetShowMouseCursor(false) end
            if pc.SetInputMode_GameOnly then pc:SetInputMode_GameOnly() end
        end
    end)

    local main = _G.CS2Crosshair
    if main and main.NotifyToast then
        main.NotifyToast("CS2 Crosshair Studio Closed", 0.7, 0.7, 0.7)
    end
end

function CrosshairUI.Toggle()
    if CrosshairUI.isOpen then
        CrosshairUI.Hide()
    else
        CrosshairUI.Show()
    end
end

return CrosshairUI
