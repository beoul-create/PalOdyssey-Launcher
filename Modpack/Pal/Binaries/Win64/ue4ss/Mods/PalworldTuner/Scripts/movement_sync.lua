-- PalworldTuner - optional sprint-to-walk synchronization.
-- Disabled by default because forcing movement speed on every player can
-- conflict with server authority, buffs, mounts, and other movement mods.
local SprintSync = {
    states = {},
    started = false
}

local function Log(msg)
    print(string.format("[PalworldTuner:SprintSync] %s\n", tostring(msg)))
end

local function IsSprinting(pawn)
    local sprinting = false
    pcall(function()
        if not pawn or not pawn:IsValid() then return end
        if pawn.IsSprinting then
            sprinting = pawn:IsSprinting() == true
        elseif pawn.bIsSprinting ~= nil then
            sprinting = pawn.bIsSprinting == true
        end
    end)
    return sprinting
end

function SprintSync.UpdatePlayerSpeeds()
    local pcs = {}
    pcall(function() pcs = FindAllOf("PalPlayerController") or {} end)

    for _, pc in ipairs(pcs) do
        pcall(function()
            if not pc or not pc:IsValid() then return end
            local pawn = pc.Pawn or pc.Character or (pc.K2_GetPawn and pc:K2_GetPawn())
            if not pawn or not pawn:IsValid() then return end

            local moveComp = pawn.CharacterMovement
            if not moveComp or not moveComp:IsValid() then return end

            local pawnKey = tostring(pawn:get_address())
            local state = SprintSync.states[pawnKey] or { wasSprinting = false, walkSpeed = nil }
            local sprinting = IsSprinting(pawn)
            local liveSpeed = tonumber(moveComp.MaxWalkSpeed) or 0

            if not sprinting then
                if state.wasSprinting and state.walkSpeed and state.walkSpeed > 0 then
                    moveComp.MaxWalkSpeed = state.walkSpeed
                    liveSpeed = state.walkSpeed
                end
                if liveSpeed > 0 and liveSpeed < 2500 then
                    state.walkSpeed = liveSpeed
                end
            elseif state.walkSpeed and state.walkSpeed > 0 then
                moveComp.MaxWalkSpeed = state.walkSpeed * SprintSync.sprintMultiplier
            end

            state.wasSprinting = sprinting
            SprintSync.states[pawnKey] = state
        end)
    end
end

function SprintSync.apply(cfg)
    if SprintSync.started or not cfg or cfg.sprint_speed_sync ~= true then return end
    SprintSync.started = true
    SprintSync.sprintMultiplier = math.max(1.0, tonumber(cfg.sprint_multiplier) or 1.65)

    local sprintHooks = {
        "/Script/Pal.PalActionSprint:OnBeginAction",
        "/Script/Pal.PalActionSprint:OnEndAction",
        "/Script/Pal.PalPlayerCharacter:OnStartSprint",
        "/Script/Pal.PalPlayerCharacter:OnEndSprint"
    }
    for _, hookName in ipairs(sprintHooks) do
        pcall(RegisterHook, hookName, function()
            SprintSync.UpdatePlayerSpeeds()
        end)
    end

    LoopAsync(200, function()
        SprintSync.UpdatePlayerSpeeds()
        return false
    end)

    Log(string.format("enabled (Sprint = Walk x %.2f)", SprintSync.sprintMultiplier))
end

return SprintSync
