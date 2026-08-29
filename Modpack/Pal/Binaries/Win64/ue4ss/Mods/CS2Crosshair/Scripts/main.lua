-- ============================================================================
-- CS2Crosshair: Counter-Strike 2 Style High-Precision Custom Crosshair Suite
-- Implements Classic Static/Dynamic, Center Dot, T-Style, High-Contrast Outlines,
-- Dynamic Recoil Spread Expansion, and Color Preset Cycling.
-- ============================================================================

local ok, Config = pcall(require, "config")
if not ok or type(Config) ~= "table" then
    Config = {
        enabled = true,
        style = "ClassicDynamic",
        colorPreset = "Green",
        size = 6.0,
        thickness = 2.0,
        gap = 3.0,
        dot = true,
        dotSize = 2.0,
        drawOutline = true,
        outlineThickness = 1.0,
        tStyle = false,
        dynamicSpread = true,
        dynamicSpreadAmount = 5.0,
        removeWatermark = true,
        cycleColorHotkey = "F7",
        log = true
    }
end

local function Log(msg)
    if Config.log then
        print(string.format("[CS2Crosshair] %s\n", tostring(msg)))
    end
end

if not Config.enabled then return end

print("==========================================================")
print("  CS2Crosshair: High-Precision CS2 Crosshair Suite Active ")
print("==========================================================")

-- Color Presets Table
local ColorPresets = {
    Green   = { R = 0.0, G = 1.0, B = 0.2, A = 1.0, name = "Classic Green" },
    Cyan    = { R = 0.0, G = 0.95, B = 1.0, A = 1.0, name = "Vibrant Cyan" },
    Yellow  = { R = 1.0, G = 0.9, B = 0.0, A = 1.0, name = "Bright Yellow" },
    Red     = { R = 1.0, G = 0.15, B = 0.15, A = 1.0, name = "Target Red" },
    Pink    = { R = 1.0, G = 0.1, B = 0.85, A = 1.0, name = "Neon Pink" },
    White   = { R = 1.0, G = 1.0, B = 1.0, A = 1.0, name = "Pure White" }
}

local PresetList = { "Green", "Cyan", "Yellow", "Red", "Pink", "White" }
local currentPresetIndex = 1

for idx, p in ipairs(PresetList) do
    if p == Config.colorPreset then currentPresetIndex = idx break end
end

-- State
local currentRecoilSpread = 0.0
local lastSpreadUpdate = os.clock()

-- Toast Helper
local function SendCrosshairToast(msg)
    pcall(function()
        local SDIR = (debug.getinfo(1, "S").source:gsub("^@", ""):gsub("[^/\\]+$", ""))
        package.path = SDIR .. "../../DarnToasts/Scripts/?.lua;" .. package.path
        local Toast = require("ToastLib").new("CS2Crosshair")
        if Toast and Toast.notify then
            local activeColor = ColorPresets[PresetList[currentPresetIndex]]
            Toast.notify(msg, activeColor.R, activeColor.G, activeColor.B)
        end
    end)
end

-- Remove screen development watermarks
if Config.removeWatermark then
    pcall(function()
        ExecuteConsoleCommand("r.Watermark 0")
        ExecuteConsoleCommand("t.MaxFPS 0")
    end)
end

-- Hook Recoil / Firing Event for Dynamic Spread
pcall(function()
    RegisterHook("/Script/Pal.PalShooterComponent:OnShootBullet", function(Context)
        if Config.dynamicSpread and Config.style == "ClassicDynamic" then
            currentRecoilSpread = currentRecoilSpread + (Config.dynamicSpreadAmount or 5.0)
            if currentRecoilSpread > 18.0 then currentRecoilSpread = 18.0 end
        end
    end)
end)

-- Comprehensive Universal Vanilla Reticle Suppression (Guns, Spears, Bows, Spheres, Melee)
local function HideVanillaCrosshair()
    pcall(function()
        local reticleClassNames = {
            "WBP_Ingame_Reticle_C",
            "WBP_Reticle_C",
            "WBP_AimReticle_C",
            "WBP_PlayerReticle_C",
            "WBP_ReticleCrosshair_C",
            "WBP_Ingame_Crosshair_C",
            "WBP_Reticle_Spear_C",
            "WBP_Reticle_Melee_C",
            "WBP_Reticle_Bow_C",
            "WBP_Reticle_Gun_C",
            "WBP_Reticle_Sphere_C",
            "WBP_Throw_Reticle_C",
            "WBP_SphereAim_C",
            "WBP_PalAimReticle_C",
            "WBP_PalReticle_C",
            "WBP_Reticle_Sniper_C",
            "WBP_Reticle_Shotgun_C",
            "WBP_Reticle_Missile_C",
            "WBP_Reticle_LockOn_C",
            "WBP_Reticle_Throw_C"
        }
        for _, className in ipairs(reticleClassNames) do
            local widgets = FindAllOf(className)
            if widgets then
                for _, w in ipairs(widgets) do
                    if w and w:IsValid() and w.SetVisibility then
                        w:SetVisibility(2) -- ESlateVisibility::Collapsed
                    end
                end
            end
        end
    end)
end

-- Hook all native reticle construction & tick events to keep them suppressed
pcall(function()
    local hooks = {
        "/Script/Pal.PalUserWidget:Construct",
        "/Game/Pal/Blueprint/UI/InGame/Reticle/WBP_Ingame_Reticle.WBP_Ingame_Reticle_C:Construct",
        "/Game/Pal/Blueprint/UI/InGame/Reticle/WBP_Ingame_Reticle.WBP_Ingame_Reticle_C:Tick",
        "/Game/Pal/Blueprint/UI/InGame/Reticle/WBP_ReticleCrosshair.WBP_ReticleCrosshair_C:Construct",
        "/Game/Pal/Blueprint/UI/InGame/Reticle/WBP_ReticleCrosshair.WBP_ReticleCrosshair_C:Tick",
        "/Script/Pal.PalPlayerController:ReceiveTick"
    }
    for _, hk in ipairs(hooks) do
        pcall(RegisterHook, hk, function(Context)
            HideVanillaCrosshair()
        end)
    end
end)

-- Crosshair HUD Renderer
local function DrawCS2Crosshair(hud)
    if not Config.enabled then return end

    local now = os.clock()
    local elapsed = math.max(0.0, now - lastSpreadUpdate)
    lastSpreadUpdate = now
    currentRecoilSpread = math.max(0.0, currentRecoilSpread - (elapsed * 14.0))
    
    local sx = hud.SizeX
    local sy = hud.SizeY
    if not sx or not sy or sx <= 0 or sy <= 0 then return end
    
    local cx = sx / 2.0
    local cy = sy / 2.0
    
    local presetName = Config.colorPreset or PresetList[currentPresetIndex] or "Green"
    local colorData = ColorPresets[presetName] or ColorPresets["Green"]
    local col = { R = colorData.R, G = colorData.G, B = colorData.B, A = colorData.A or 1.0 }
    local black = { R = 0.0, G = 0.0, B = 0.0, A = 1.0 }
    
    local style = Config.style or "ClassicDynamic"
    local spread = (style == "ClassicDynamic" and Config.dynamicSpread) and currentRecoilSpread or 0.0
    local gap = (tonumber(Config.gap) or 3.0) + spread
    local size = tonumber(Config.size) or 6.0
    local thick = tonumber(Config.thickness) or 2.0
    local outline = Config.drawOutline == true
    local outThick = tonumber(Config.outlineThickness) or 1.0
    local isTStyle = Config.tStyle == true or style == "TStyle"
    local dotOnly = style == "DotOnly"
    
    local function FillRect(x, y, w, h, c)
        pcall(function()
            hud:DrawRect(c, x, y, w, h)
        end)
    end
    
    if not dotOnly then
        -- 1. Left Bar
        if outline then
            FillRect(cx - gap - size - outThick, cy - (thick / 2.0) - outThick, size + (outThick * 2), thick + (outThick * 2), black)
        end
        FillRect(cx - gap - size, cy - (thick / 2.0), size, thick, col)

        -- 2. Right Bar
        if outline then
            FillRect(cx + gap - outThick, cy - (thick / 2.0) - outThick, size + (outThick * 2), thick + (outThick * 2), black)
        end
        FillRect(cx + gap, cy - (thick / 2.0), size, thick, col)

        -- 3. Bottom Bar
        if outline then
            FillRect(cx - (thick / 2.0) - outThick, cy + gap - outThick, thick + (outThick * 2), size + (outThick * 2), black)
        end
        FillRect(cx - (thick / 2.0), cy + gap, thick, size, col)

        -- 4. Top Bar (skipped if T-Style)
        if not isTStyle then
            if outline then
                FillRect(cx - (thick / 2.0) - outThick, cy - gap - size - outThick, thick + (outThick * 2), size + (outThick * 2), black)
            end
            FillRect(cx - (thick / 2.0), cy - gap - size, thick, size, col)
        end
    end
    
    -- 5. Center Dot
    if Config.dot then
        local dSize = tonumber(Config.dotSize) or 2.0
        if outline then
            FillRect(cx - (dSize / 2.0) - outThick, cy - (dSize / 2.0) - outThick, dSize + (outThick * 2), dSize + (outThick * 2), black)
        end
        FillRect(cx - (dSize / 2.0), cy - (dSize / 2.0), dSize, dSize, col)
    end
end

-- Hook Root Engine HUD & In-Game Pal HUD Draw Loop
pcall(function()
    RegisterHook("/Script/Engine.HUD:ReceiveDrawHUD", function(Context)
        local hud = Context:get()
        if hud and hud:IsValid() then
            DrawCS2Crosshair(hud)
            HideVanillaCrosshair()
        end
    end)
    RegisterHook("/Script/Pal.BP_PalHUD_InGame_C:ReceiveDrawHUD", function(Context)
        local hud = Context:get()
        if hud and hud:IsValid() then
            DrawCS2Crosshair(hud)
            HideVanillaCrosshair()
        end
    end)
end)

local function CycleColorPreset()
    currentPresetIndex = (currentPresetIndex % #PresetList) + 1
    Config.colorPreset = PresetList[currentPresetIndex]
    local activeColor = ColorPresets[Config.colorPreset]
    SendCrosshairToast(string.format("Crosshair color: %s", activeColor.name))
end

pcall(function()
    local keyName = tostring(Config.cycleColorHotkey or "F7"):upper()
    local k = nil
    if type(Key) == "table" then
        k = Key[keyName] or Key.F7
    end

    if k then
        RegisterKeyBind(k, function()
            if type(_G.ExecuteInGameThread) == "function" then
                pcall(_G.ExecuteInGameThread, CycleColorPreset)
            else
                pcall(CycleColorPreset)
            end
        end)
        Log(string.format("Registered hotkey [%s] for crosshair color cycling.", keyName))
    end
end)

-- Public API
_G.CS2Crosshair = {
    Toggle = CycleColorPreset,
    CycleColorPreset = CycleColorPreset,
    GetColor = function() return ColorPresets[PresetList[currentPresetIndex]] end,
    GetConfig = function() return Config end,
    SetStyle = function(st) Config.style = st end,
    SetColorPreset = function(name)
        if not ColorPresets[name] then return false end
        Config.colorPreset = name
        for index, preset in ipairs(PresetList) do
            if preset == name then currentPresetIndex = index break end
        end
        return true
    end,
    SetGap = function(g) Config.gap = g end,
    SetSize = function(s) Config.size = s end,
    SetThickness = function(t) Config.thickness = t end,
    NotifyToast = function(msg, r, g, b) SendCrosshairToast(msg) end
}

Log("CS2Crosshair mod fully loaded & active (F7 cycles colors).")
