-- StuckPalRescuer: Monitors base camp worker Pals and automatically rescues them when stuck in pathfinding loops
local ok, Config = pcall(require, "config")
if not ok or type(Config) ~= "table" then
    Config = {
        enabled = true,
        checkIntervalSeconds = 8,
        stuckThresholdSeconds = 18,
        minMovementDistance = 30.0,
        teleportToPalbox = true,
        notifyOnRescue = true,
        log = true
    }
end

local function Log(msg)
    if Config.log then
        print(string.format("[StuckPalRescuer] %s\n", tostring(msg)))
    end
end

if not Config.enabled then
    Log("Mod is disabled in config.")
    return
end

local palTrackMap = {}
local lastScanTime = 0

local function GetDistance(v1, v2)
    if not v1 or not v2 then return 0 end
    local dx = (v1.X or 0) - (v2.X or 0)
    local dy = (v1.Y or 0) - (v2.Y or 0)
    local dz = (v1.Z or 0) - (v2.Z or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

local function RescuePal(palActor, baseLocation)
    if not palActor or not palActor:IsValid() then return end

    pcall(function()
        local name = palActor:GetFullName()
        local targetLoc = nil

        if baseLocation then
            targetLoc = {
                X = baseLocation.X,
                Y = baseLocation.Y,
                Z = baseLocation.Z + 50.0
            }
        else
            local curLoc = palActor:K2_GetActorLocation()
            targetLoc = {
                X = curLoc.X,
                Y = curLoc.Y,
                Z = curLoc.Z + 120.0
            }
        end

        local rot = palActor:K2_GetActorRotation()
        palActor:K2_SetActorLocationAndRotation(targetLoc, rot, false, {}, true)

        -- Reset velocity & navigation state
        local moveComp = palActor.CharacterMovement
        if moveComp and moveComp:IsValid() then
            moveComp:StopMovementImmediately()
        end

        Log(string.format("Rescued stuck Pal '%s' -> Teleported to safe coordinate (X:%.1f, Y:%.1f, Z:%.1f)", name, targetLoc.X, targetLoc.Y, targetLoc.Z))
    end)
end

local registeredPals = {}

local function RegisterPal(pal)
    if not pal or not pal:IsValid() then return end
    local ptrKey = tostring(pal:GetAddress())
    registeredPals[ptrKey] = pal
end

pcall(function()
    NotifyOnNewObject("/Script/Pal.PalCharacter", function(pal)
        RegisterPal(pal)
    end)
end)

local function ScanAndRescue()
    local now = os.time()
    if now - lastScanTime < (Config.checkIntervalSeconds or 10) then return end
    lastScanTime = now

    pcall(function()
        for ptrKey, pal in pairs(registeredPals) do
            if not pal or not pal:IsValid() then
                registeredPals[ptrKey] = nil
                palTrackMap[ptrKey] = nil
            else
                local isBasePal = false
                pcall(function()
                    local param = pal.CharacterParameterComponent
                    if param and param:IsValid() then
                        local assignedBase = param:GetAssignedBaseCamp()
                        if assignedBase and assignedBase:IsValid() then
                            isBasePal = true
                        end
                    end
                end)

                local curLoc = pal:K2_GetActorLocation()

                if isBasePal and curLoc then
                    local entry = palTrackMap[ptrKey]
                    if not entry then
                        palTrackMap[ptrKey] = {
                            lastLoc = { X = curLoc.X, Y = curLoc.Y, Z = curLoc.Z },
                            stuckDuration = 0,
                            lastTime = now
                        }
                    else
                        local dist = GetDistance(curLoc, entry.lastLoc)
                        local dt = now - entry.lastTime
                        entry.lastTime = now

                        if dist < (Config.minMovementDistance or 30.0) then
                            entry.stuckDuration = entry.stuckDuration + dt
                            if entry.stuckDuration >= (Config.stuckThresholdSeconds or 18) then
                                RescuePal(pal, nil)
                                entry.stuckDuration = 0
                                entry.lastLoc = { X = curLoc.X, Y = curLoc.Y, Z = curLoc.Z + 120.0 }
                            end
                        else
                            entry.stuckDuration = 0
                            entry.lastLoc = { X = curLoc.X, Y = curLoc.Y, Z = curLoc.Z }
                        end
                    end
                else
                    palTrackMap[ptrKey] = nil
                end
            end
        end
    end)
end

-- Register recurring lightweight scan hook (Interval: 10s)
local function ScheduleNextScan()
    ExecuteWithDelay(10000, function()
        ScanAndRescue()
        ScheduleNextScan()
    end)
end

ScheduleNextScan()

Log("StuckPalRescuer loaded successfully (Event-Registered Zero-Stutter Mode).")
