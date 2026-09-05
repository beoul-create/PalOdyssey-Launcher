local AutoShutdown = {}
local ScriptDir = debug.getinfo(1, "S").source:gsub("^@", ""):gsub("[^/\\]+$", "")
local StatePath = ScriptDir .. "../../../../../../Saved/liveboard_state.json"

local IDLE_TIMEOUT_SECONDS = 900 -- 15 minutes (900 seconds)
local IdleAccumulator = 0
local ScanAccumulator = 0
local LastLoggedMilestone = 0
local IsShuttingDown = false

local function is_dedicated_server_process()
    local command = string.lower(tostring(os.getenv("CMDCMDLINE") or ""))
    if string.find(command, "dedicated", 1, true)
        or string.find(command, "palserver", 1, true) then
        return true
    end
    local source = debug.getinfo(1, "S").source:lower():gsub("\\", "/")
    if string.find(source, "/palserver/") ~= nil then
        return true
    end
    local ok, engine = pcall(function()
        return FindFirstOf("GameEngine")
    end)
    if ok and engine ~= nil then
        local ok_net, net_mode = pcall(function()
            return engine.NetMode
        end)
        -- NM_DedicatedServer == 3 in Unreal
        if ok_net and type(net_mode) == "number" and net_mode == 3 then
            return true
        end
    end
    local ok_geo, is_ded = pcall(function()
        local GameplayStatics = StaticFindObject("/Script/Engine.Default__GameplayStatics")
        local world = (UEHelpers and UEHelpers.GetWorldContextObject and UEHelpers.GetWorldContextObject()) or (GetWorldContext and GetWorldContext())
        if GameplayStatics and GameplayStatics:IsValid() and world and world:IsValid() and type(GameplayStatics.IsDedicatedServer) == "function" then
            return GameplayStatics:IsDedicatedServer(world)
        end
        return false
    end)
    if ok_geo and is_ded then return true end
    return false
end

function AutoShutdown.Init()
    if not is_dedicated_server_process() then
        print("[AutoShutdown] Client environment detected; auto-shutdown watchdog disabled.")
        return
    end

    print("[AutoShutdown] 15-minute inactivity watchdog started (async timer).")

    local function Tick()
        if IsShuttingDown then return true end
        if not is_dedicated_server_process() then return true end

        local World = (UEHelpers and UEHelpers.GetWorldContextObject and UEHelpers.GetWorldContextObject())
            or (GetWorldContext and GetWorldContext()) or nil
        if not World then return false end

        local GameplayStatics = StaticFindObject("/Script/Engine.Default__GameplayStatics")
        local PlayerStateClass = StaticFindObject("/Script/Pal.PalPlayerState")
        
        local PlayerCount = 0
        local PlayerQuerySucceeded = false
        if GameplayStatics and GameplayStatics:IsValid() and PlayerStateClass and PlayerStateClass:IsValid() then
            local PlayerStates = GameplayStatics:GetAllActorsOfClass(World, PlayerStateClass)
            if PlayerStates and type(PlayerStates.GetArrayNum) == "function" then
                PlayerCount = PlayerStates:GetArrayNum()
                PlayerQuerySucceeded = true
            end
        end

        if not PlayerQuerySucceeded then return false end

        if PlayerCount == 0 then
            IdleAccumulator = IdleAccumulator + 15

            local Milestone = math.floor(IdleAccumulator / 180)
            if Milestone > LastLoggedMilestone then
                LastLoggedMilestone = Milestone
                print(string.format("[AutoShutdown] Server empty. Idle: %ds / %ds", math.floor(IdleAccumulator), IDLE_TIMEOUT_SECONDS))
            end

            if IdleAccumulator >= IDLE_TIMEOUT_SECONDS then
                IsShuttingDown = true
                AutoShutdown.ExecuteGracefulShutdown()
                return true -- stop looping
            end
        else
            if IdleAccumulator > 0 then
                print("[AutoShutdown] Player detected online. Resetting idle watchdog.")
                IdleAccumulator = 0
                LastLoggedMilestone = 0
            end
        end

        return false -- continue looping
    end

    if type(LoopInGameThreadWithDelay) == "function" then
        LoopInGameThreadWithDelay(15000, function() pcall(Tick) end)
    else
        LoopAsync(15000, function()
            if type(ExecuteInGameThread) == "function" then ExecuteInGameThread(function() pcall(Tick) end)
            else pcall(Tick) end
            return IsShuttingDown
        end)
    end
end

function AutoShutdown.ExecuteGracefulShutdown()
    print("[AutoShutdown] 15 minutes of zero player activity reached. Initiating graceful shutdown...")

    local tempPath = StatePath .. ".tmp"
    local File = io.open(tempPath, "w")
    if File then
        File:write('{"ServerOnline":false,"PlayerCount":0,"MaxPlayers":32,"Players":[],"ActiveBosses":[],"Timestamp":' .. os.time() .. '}')
        File:flush()
        File:close()
        os.remove(StatePath .. ".bak")
        local hadOriginal = os.rename(StatePath, StatePath .. ".bak")
        if os.rename(tempPath, StatePath) then os.remove(StatePath .. ".bak")
        elseif hadOriginal then os.rename(StatePath .. ".bak", StatePath) end
    end

    local SaveSubsystem = FindFirstOf("PalSaveSubsystem")
    if SaveSubsystem and SaveSubsystem:IsValid() then
        SaveSubsystem:SaveWorld()
        print("[AutoShutdown] World save completed.")
    end

    local delay = ExecuteInGameThreadWithDelay or ExecuteWithDelay
    delay(3000, function()
        local KismetSystem = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
        if KismetSystem and KismetSystem:IsValid() then
            KismetSystem:QuitGame(GetWorldContext(), nil, 0, false)
        else
            os.exit(0)
        end
    end)
end

return AutoShutdown
