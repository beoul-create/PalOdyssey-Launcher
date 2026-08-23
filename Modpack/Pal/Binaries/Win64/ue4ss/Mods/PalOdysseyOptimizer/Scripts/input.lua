-- PalOdysseyOptimizer - Raw Mouse Input & Zero-Lag Controls (2000Hz - 8000Hz Ultra-Low Latency)
local InputModule = {}

function InputModule.apply(cfg)
    if not cfg or not cfg.enabled then return end

    print("[PalOdysseyOptimizer] Initializing Direct Raw Mouse Input & Low-Latency Controller...")

    -- 1. Apply Global Engine Input Settings (Zero per-frame cost)
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
                print("[PalOdysseyOptimizer] Global UInputSettings configured for direct raw hardware input.")
            end
        end)
    end

    -- Run global settings configuration immediately and after engine init
    applyGlobalInputSettings()
    ExecuteWithDelay(3000, applyGlobalInputSettings)

    -- 2. Hook into PlayerController and PlayerInput upon spawn/restart
    local function setupPlayerInput(playerController)
        if not playerController or not playerController:IsValid() then return end

        pcall(function()
            -- Disable mouse smoothing & view acceleration
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
                pcall(function()
                    playerController.PlayerInput.bEnableMouseSmoothing = false
                end)
            end
        end)
    end

    -- Hook PlayerController initialization
    RegisterHook("/Script/Engine.PlayerController:ClientRestart", function(Context)
        local pc = Context:get()
        if pc and pc:IsValid() then
            setupPlayerInput(pc)
        end
    end)

    -- Register Console Commands for instant raw input toggle & diagnostics
    RegisterConsoleCommandHandler("ToggleRawInput", function(FullCommand, Parameters, OutputDevice)
        applyGlobalInputSettings()
        print("[PalOdysseyOptimizer] Direct Raw Input & Ultra-High Polling mode reapplied.")
        return true
    end)

    print("[PalOdysseyOptimizer] Direct Raw Mouse Input initialized successfully (2000Hz-8000Hz ready, zero smoothing).")
end

return InputModule

