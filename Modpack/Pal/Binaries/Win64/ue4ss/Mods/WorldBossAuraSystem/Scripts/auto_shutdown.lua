local AutoShutdown = {}

local IDLE_TIMEOUT_SECONDS = 900 -- 15 minutes (900 seconds)
local IdleAccumulator = 0
local IsShuttingDown = false

function AutoShutdown.Init()
    print("[AutoShutdown] 15-minute inactivity watchdog started.")

    RegisterHook("/Script/Engine.World:Tick", function(Context, DeltaSeconds)
        if IsShuttingDown then return end

        local Delta = DeltaSeconds:get()
        local World = GetWorldContext()

        local GameplayStatics = StaticFindObject("/Script/Engine.GameplayStatics")
        local PlayerStateClass = StaticFindObject("/Script/Pal.PalPlayerState")
        
        local PlayerCount = 0
        if GameplayStatics:IsValid() and PlayerStateClass:IsValid() then
            local PlayerStates = GameplayStatics:GetAllActorsOfClass(World, PlayerStateClass)
            if PlayerStates:IsValid() then
                PlayerCount = PlayerStates:Num()
            end
        end

        if PlayerCount == 0 then
            IdleAccumulator = IdleAccumulator + Delta

            if math.floor(IdleAccumulator) % 180 == 0 and math.floor(IdleAccumulator) > 0 then
                print(string.format("[AutoShutdown] Server empty. Idle: %ds / %ds", math.floor(IdleAccumulator), IDLE_TIMEOUT_SECONDS))
            end

            if IdleAccumulator >= IDLE_TIMEOUT_SECONDS then
                IsShuttingDown = true
                AutoShutdown.ExecuteGracefulShutdown()
            end
        else
            if IdleAccumulator > 0 then
                print("[AutoShutdown] Player detected online. Resetting idle watchdog.")
                IdleAccumulator = 0
            end
        end
    end)
end

function AutoShutdown.ExecuteGracefulShutdown()
    print("[AutoShutdown] 15 minutes of zero player activity reached. Initiating graceful shutdown...")

    local File = io.open("Pal/Saved/liveboard_state.json", "w")
    if File then
        File:write('{"ServerOnline":false,"PlayerCount":0,"MaxPlayers":32,"Players":[],"ActiveBosses":[],"Timestamp":' .. os.time() .. '}')
        File:close()
    end

    local SaveSubsystem = StaticFindObject("/Script/Pal.PalSaveSubsystem")
    if SaveSubsystem:IsValid() then
        SaveSubsystem:SaveWorld()
        print("[AutoShutdown] World save completed.")
    end

    ExecuteWithDelay(3000, function()
        local KismetSystem = StaticFindObject("/Script/Engine.KismetSystemLibrary")
        if KismetSystem:IsValid() then
            KismetSystem:QuitGame(GetWorldContext(), nil, 0, false)
        else
            os.exit(0)
        end
    end)
end

return AutoShutdown
