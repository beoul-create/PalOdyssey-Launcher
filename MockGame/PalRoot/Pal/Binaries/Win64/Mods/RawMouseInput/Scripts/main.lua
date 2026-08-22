-- =========================================================================
-- PalOdyssey - 1:1 Raw Mouse Input & Linear Sensitivity Fix
-- Disables Unreal Engine 5.1 mouse smoothing, mouse acceleration, and
-- equalizes horizontal (X) and vertical (Y) aim sensitivity to true 1:1.
-- =========================================================================

local MOD_NAME = "RawMouseInput"
local MOD_VERSION = "1.0.0"

local function ApplyRawMouseInput(controller)
    if not controller or not controller:IsValid() then return end

    local playerInput = controller.PlayerInput
    if playerInput and playerInput:IsValid() then
        -- 1. Disable UE5 Mouse Smoothing and Acceleration
        if playerInput.bEnableMouseSmoothing ~= nil then
            playerInput.bEnableMouseSmoothing = false
        end
        if playerInput.bViewAccelerationEnabled ~= nil then
            playerInput.bViewAccelerationEnabled = false
        end

        -- 2. Equalize AxisConfig for 1:1 X/Y Sensitivity
        if playerInput.AxisConfig then
            local count = playerInput.AxisConfig:GetArrayNum() or 0
            for i = 1, count do
                local cfg = playerInput.AxisConfig[i]
                if cfg then
                    local axisName = cfg.AxisKeyName and cfg.AxisKeyName:ToString() or ""
                    if axisName == "MouseX" or axisName == "MouseY" or axisName == "Mouse2D" then
                        cfg.Sensitivity = 1.0
                        cfg.DeadZone = 0.0
                        cfg.Exponent = 1.0
                    end
                end
            end
        end
    end

    -- 3. Execute Engine CVars
    local kismet = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
    if kismet and kismet:IsValid() then
        kismet:ExecuteConsoleCommand(controller, "r.Input.RawMouse 1", controller)
        kismet:ExecuteConsoleCommand(controller, "m.bEnableMouseSmoothing 0", controller)
    end
end

-- Hook Player Controller on spawn, possession, and world load
RegisterHook("/Script/Engine.PlayerController:ClientRestart", function(self)
    local controller = self:get()
    ApplyRawMouseInput(controller)
end)

RegisterHook("/Script/Engine.PlayerController:ServerAcknowledgePossession", function(self)
    local controller = self:get()
    ApplyRawMouseInput(controller)
end)

-- Background loop to maintain 1:1 raw input across mount transitions & aim states
LoopAsync(2500, function()
    local playerController = FindFirstOf("PalPlayerController") or FindFirstOf("PlayerController")
    if playerController and playerController:IsValid() then
        ApplyRawMouseInput(playerController)
    end
    return false -- keep looping
end)

print(string.format("[%s] v%s - 1:1 Raw Mouse Input & Linear Sensitivity successfully armed.", MOD_NAME, MOD_VERSION))
