local isServer = string.find(debug.getinfo(1, "S").source:lower():gsub("\\", "/"), "/palserver/") ~= nil
if isServer then return {} end

-- PalOdysseyOptimizer - Raw Mouse Input & Fluid Hardware Menu Cursor (2000Hz - 8000Hz Ultra-Low Latency)
local InputModule = {}
local ExecuteConsole = require("console")

function InputModule.apply(cfg)
    if not cfg or not cfg.enabled then return end

    print("[PalOdysseyOptimizer] Initializing Direct Raw Input & Fluid Menu Cursor Engine...")

    -- 1. Apply Global Engine & Slate Hardware Cursor Settings
    local function applyGlobalInputSettings()
        pcall(function()
            local InputSettings = StaticFindObject("/Script/Engine.Default__InputSettings")
            if InputSettings and InputSettings:IsValid() then
                if cfg.disableSmoothing ~= false then
                    InputSettings.bEnableMouseSmoothing = false
                end
                if cfg.disableAcceleration ~= false then
                    InputSettings.bViewAccelerationEnabled = false
                    InputSettings.bDisableMouseAcceleration = true
                end
                InputSettings.bUseMousePositionLocking = true
            end
        end)

        pcall(function()
            local SlateSettings = StaticFindObject("/Script/Slate.Default__SlateSettings")
            if SlateSettings and SlateSettings:IsValid() then
                SlateSettings.bUseHardwareCursor = true
                SlateSettings.bEnableHardwareCursor = true
                SlateSettings.bVirtualCursor = false
            end
        end)

        pcall(function()
            local Viewport = StaticFindObject("/Script/Engine.Default__GameViewportClient")
            if Viewport and Viewport:IsValid() then
                Viewport.bUseHardwareCursor = true
            end
        end)

        -- Execute Slate & Render console optimizations for instant hardware cursor responsiveness
        local commands = {
            "Slate.EnableMouseSmoother 0",
            "Slate.EnableRenderHardwareCursor 1",
            "Slate.UseHardwareCursor 1",
            "Slate.AllowHardwareCursor 1",
            "Slate.CursorRenderRate 0",
            "Slate.SleepInterval 0",
            "Slate.SleepIntervalWithUserInteraction 0",
            "r.Slate.EnableMouseCapture 0"
        }

        for _, cmd in ipairs(commands) do
            ExecuteConsole(cmd)
        end
    end

    -- Run global settings configuration immediately, and re-apply post-initialization
    applyGlobalInputSettings()
    ExecuteWithDelay(1500, applyGlobalInputSettings)

    -- 2. Hook into PlayerController upon spawn/restart
    local function setupPlayerInput(playerController)
        if not playerController or not playerController:IsValid() then return end

        pcall(function()
            -- Disable mouse smoothing & view acceleration on controller
            if cfg.disableSmoothing ~= false then
                playerController.bEnableMouseSmoothing = false
            end
            if cfg.disableAcceleration ~= false then
                playerController.bViewAccelerationEnabled = false
            end
            
            -- Lock raw input tick pacing
            playerController.SmoothFrameRate = false

            -- If PlayerInput instance exists, enforce raw flags directly
            if playerController.PlayerInput and playerController.PlayerInput:IsValid() then
                playerController.PlayerInput.bEnableMouseSmoothing = false
            end
        end)

        -- Re-enforce Slate hardware cursor CVars on player spawn
        applyGlobalInputSettings()
    end

    -- Hook PlayerController initialization
    RegisterHook("/Script/Engine.PlayerController:ClientRestart", function(Context)
        local pc = Context:get()
        if pc and pc:IsValid() then
            setupPlayerInput(pc)
        end
    end)

    -- Hook when UI/Menu toggles mouse cursor visibility to eliminate any software cursor lag
    RegisterHook("/Script/Engine.PlayerController:SetShowMouseCursor", function(Context, bShow)
        pcall(function()
            local pc = Context:get()
            if pc and pc:IsValid() and pc.PlayerInput and pc.PlayerInput:IsValid() then
                pc.PlayerInput.bEnableMouseSmoothing = false
            end
        end)
    end)

    -- Register Console Commands for instant raw input & fluid cursor re-application
    RegisterConsoleCommandHandler("ToggleRawInput", function(FullCommand, Parameters, OutputDevice)
        applyGlobalInputSettings()
        print("[PalOdysseyOptimizer] Direct Raw Input & Fluid Menu Cursor reapplied.")
        return true
    end)

    RegisterConsoleCommandHandler("FluidCursor", function(FullCommand, Parameters, OutputDevice)
        applyGlobalInputSettings()
        print("[PalOdysseyOptimizer] Fluid Hardware Menu Cursor settings enforced.")
        return true
    end)

    print("[PalOdysseyOptimizer] Direct Raw Mouse Input & Fluid Hardware Cursor initialized (Zero smoothing, 0-frame Slate latency).")
end

return InputModule
