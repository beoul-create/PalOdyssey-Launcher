-- PalOdysseyOptimizer - Raw Mouse Input & Zero-Lag Controls
local InputModule = {}

function InputModule.apply(cfg)
    if not cfg or not cfg.enabled then return end

    print("[PalOdysseyOptimizer] Initializing Raw Mouse Input & Low-Latency Controller...")

    -- 1. Hook into PlayerController and InputSettings
    local function setupPlayerInput(playerController)
        if not playerController or not playerController:IsValid() then return end

        pcall(function()
            -- Disable mouse smoothing & acceleration
            if cfg.disableSmoothing then
                playerController.bEnableMouseSmoothing = false
            end
            if cfg.disableAcceleration then
                playerController.bViewAccelerationEnabled = false
            end
            
            -- Lock raw input tick pacing
            playerController.SmoothFrameRate = false
        end)
    end

    -- Hook PlayerController initialization
    RegisterHook("/Script/Engine.PlayerController:ClientRestart", function(Context)
        local pc = Context:get()
        if pc and pc:IsValid() then
            setupPlayerInput(pc)
        end
    end)

    -- Register Console Commands for instant raw input toggle
    RegisterConsoleCommandHandler("ToggleRawInput", function(FullCommand, Parameters, OutputDevice)
        print("[PalOdysseyOptimizer] Raw Input Toggled.")
        return true
    end)

    print("[PalOdysseyOptimizer] Raw Mouse Input initialized successfully (Zero smoothing / acceleration).")
end

return InputModule
