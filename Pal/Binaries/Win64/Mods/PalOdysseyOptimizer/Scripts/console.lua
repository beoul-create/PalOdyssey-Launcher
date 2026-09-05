-- Dispatch through the first available UE4SS route. Sending every command
-- through every route can execute the same CVar three times.
return function(command)
    if type(_G.ExecuteConsoleCommand) == "function" then
        local ok = pcall(_G.ExecuteConsoleCommand, command)
        if ok then return true end
    end

    if type(UEHelpers) == "table" then
        local ok, executed = pcall(function()
            local controller = UEHelpers.GetPlayerController()
            if controller and controller:IsValid() and controller.ConsoleCommand then
                controller:ConsoleCommand(command, true)
                return true
            end
            return false
        end)
        if ok and executed then return true end
    end

    local ok, executed = pcall(function()
        if type(UEHelpers) ~= "table" then return false end
        local library = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
        local world = UEHelpers.GetWorld() or UEHelpers.GetWorldContextObject()
        if library and library:IsValid() and world and world:IsValid() then
            library:ExecuteConsoleCommand(world, command, nil)
            return true
        end
        return false
    end)
    return ok and executed
end
