-- ============================================================================
-- PalCinematicStudio: Main Engine
-- Full 360° FreeCam, Time Freeze, Clean HUD & Super-Res Screenshot Engine
-- ============================================================================

local ok, Config = pcall(require, "config")
if not ok or type(Config) ~= "table" then
    Config = {
        enabled = true,
        freeCamKey = "F8",
        timeFreezeKey = "F9",
        toggleHudKey = "F10",
        highResShotKey = "F11",
        highResMultiplier = 2,
        defaultFov = 90.0,
        portraitFov = 45.0,
        fovStep = 5.0,
        log = true
    }
end

local function Log(msg)
    if Config.log then
        print(string.format("[PalCinematicStudio] %s\n", tostring(msg)))
    end
end

if not Config.enabled then
    Log("PalCinematicStudio disabled in config.")
    return
end

print("=================================================================")
print("  PalOdyssey Cinematic FreeCam & Super-Res Photo Studio Active   ")
print("=================================================================")

-- State management
local isFreeCamActive = false
local isTimeFrozen = false
local isHudHidden = false
local currentFov = Config.defaultFov or 90.0

-- Helper for DarnToasts notifications
local function SendToast(title, subtitle, accentR, accentG, accentB)
    pcall(function()
        local SDIR = (debug.getinfo(1, "S").source:gsub("^@", ""):gsub("[^/\\]+$", ""))
        package.path = SDIR .. "../../DarnToasts/Scripts/?.lua;" .. package.path
        local Toast = require("ToastLib").new("CinematicStudio")
        if Toast and Toast.notify then
            Toast.notify(string.format("%s: %s", title, subtitle), accentR or 0.45, accentG or 0.85, accentB or 1.0)
        end
    end)
end

-- 1. Toggle 360° Detached FreeCam
local function ToggleFreeCam()
    pcall(function()
        isFreeCamActive = not isFreeCamActive
        if isFreeCamActive then
            ExecuteConsoleCommand("ToggleDebugCamera")
            Log("FreeCam ENABLED (360° Free Floating Camera active).")
            SendToast("📸 FreeCam", "Active (Fly freely with WASD + Mouse)", 0.3, 1.0, 0.5)
        else
            ExecuteConsoleCommand("ToggleDebugCamera")
            Log("FreeCam DISABLED (Returned to Player Pawn).")
            SendToast("📸 FreeCam", "Returned to Player", 0.7, 0.7, 0.7)
        end
    end)
end

-- 2. Toggle Time Freeze / Slomo
local function ToggleTimeFreeze()
    pcall(function()
        isTimeFrozen = not isTimeFrozen
        if isTimeFrozen then
            ExecuteConsoleCommand("Slomo 0.0001")
            Log("World Time FROZEN (Slomo 0.0001).")
            SendToast("⏸️ Time Freeze", "World Action Paused", 1.0, 0.85, 0.2)
        else
            ExecuteConsoleCommand("Slomo 1.0")
            Log("World Time RESUMED (Normal 1.0x speed).")
            SendToast("▶️ Time Resumed", "Normal Game Speed", 0.3, 1.0, 0.5)
        end
    end)
end

-- 3. Toggle Clean HUD
local function ToggleCleanHud()
    pcall(function()
        isHudHidden = not isHudHidden
        if isHudHidden then
            ExecuteConsoleCommand("ShowHUD")
            Log("HUD Hidden for clean framing.")
            SendToast("🖼️ Clean Viewport", "HUD Hidden", 0.8, 0.6, 1.0)
        else
            ExecuteConsoleCommand("ShowHUD")
            Log("HUD Restored.")
            SendToast("🖼️ Clean Viewport", "HUD Restored", 0.7, 0.7, 0.7)
        end
    end)
end

-- 4. Capture Super-Resolution Screenshot
local function CaptureHighResScreenshot()
    pcall(function()
        local mult = Config.highResMultiplier or 2
        ExecuteConsoleCommand(string.format("HighResShot %d", mult))
        Log(string.format("Captured HighResShot (%dx Supersampled) -> Saved to Pal/Saved/Screenshots/Windows/", mult))
        SendToast("💎 High-Res Capture", string.format("Saved %dx Supersampled Shot!", mult), 0.2, 1.0, 0.9)
    end)
end

-- 5. Register Hotkeys Safely
local function BindKey(keyName, actionName, callback)
    if not keyName or keyName == "" then return end
    pcall(function()
        local k = Key[tostring(keyName):upper()]
        if k then
            RegisterKeyBind(k, callback)
            Log(string.format("Bound [%s] -> %s", keyName, actionName))
        else
            Log(string.format("Warning: Key '%s' not recognized for %s", keyName, actionName))
        end
    end)
end

BindKey(Config.freeCamKey or "F8", "Toggle FreeCam", ToggleFreeCam)
BindKey(Config.timeFreezeKey or "F9", "Toggle Time Freeze", ToggleTimeFreeze)
BindKey(Config.toggleHudKey or "F10", "Toggle Clean HUD", ToggleCleanHud)
BindKey(Config.highResShotKey or "F11", "Capture High-Res Shot", CaptureHighResScreenshot)

-- 6. Register with DarnMenu for In-Game Options
local function RegisterDarnMenu()
    local okDarn, DarnMenu = pcall(require, "DarnMenu")
    if okDarn and DarnMenu and type(DarnMenu.registerCategory) == "function" then
        DarnMenu.registerCategory({
            id = "cinematic_studio",
            title = "Cinematic Studio & FreeCam",
            description = "360° Detached FreeCam, Time Freeze, Clean HUD & High-Res Capture Controls"
        })
        Log("Registered with DarnMenu in-game UI suite.")
    end
end

ExecuteWithDelay(5000, RegisterDarnMenu)

Log("PalCinematicStudio initialization complete.")
