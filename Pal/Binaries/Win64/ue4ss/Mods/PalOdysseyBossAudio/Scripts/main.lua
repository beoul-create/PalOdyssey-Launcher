-- PalOdysseyBossAudio - Complete Adaptive Music & Audio System for PalOdyssey
-- Plays Title, Exploration, Night, Dungeon, Weather, Boss, Victory & SFX audio
-- Native in-process C++ DLL (dlls/main.dll) with MCI & atomic state synchronization
-- Live volume adjustment via Keyboard shortcuts ([, ], \), Chat commands (/vol, /mute), and Toast visual display

local ModName = "PalOdysseyBossAudio"
local ScriptDir = debug.getinfo(1, "S").source:gsub("^@", ""):gsub("[^/\\]+$", "")
local ModDir = (ScriptDir:gsub("[Ss][Cc][Rr][Ii][Pp][Tt][Ss][\\/]+$", ""))
local AudioDir = ModDir .. "audio/"
local StateFile = ModDir .. "audio_state.json"
local ConfigFile = ModDir .. "config.json"
local AdaptiveStateFile = ModDir .. "../AdaptiveBGM/runtime_state.json"

local function Log(msg)
    print(string.format("[%s] %s", ModName, tostring(msg)))
end

-- 1. Dedicated Server Gate (Dedicated servers do not render audio)
local isDedicated = false
pcall(function()
    local kismet = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
    local world = UEHelpers and UEHelpers.GetWorldContextObject and UEHelpers.GetWorldContextObject()
    if kismet and kismet:IsValid() and world and world:IsValid() and type(kismet.IsDedicatedServer) == "function" then
        isDedicated = kismet:IsDedicatedServer(world)
    end
end)
if isDedicated then
    Log("Dedicated server detected; companion audio disabled on server.")
    return
end

-- Suppress legacy AdaptiveBGM native playback so it does not conflict or play double audio
_G.PalOdysseyBossAudio_Active = true

-- 2. State & Volume Management
local CurrentBgmState = "play"
local CurrentBgmTrack = ""
local CurrentBgmLoop = true
local CurrentVolume = 0.08 -- Balanced default (8%), comfortably sits behind native game audio
local CurrentFadeSec = 1.0
local SfxSequence = 0
local CurrentSfxTrack = ""
local CurrentSfxVolume = 0.75
local IsMuted = false

local function LoadConfig()
    pcall(function()
        local f = io.open(ConfigFile, "r")
        if f then
            local str = f:read("*all")
            f:close()
            local vol = str:match('"Volume"%s*:%s*([%d%.]+)')
            if vol then CurrentVolume = tonumber(vol) or CurrentVolume end
            local muted = str:match('"Muted"%s*:%s*(%a+)')
            if muted then IsMuted = (muted == "true") end
        end
    end)
end

local function SaveConfig()
    pcall(function()
        local f = io.open(ConfigFile, "w")
        if f then
            f:write(string.format('{\n  "Volume": %.2f,\n  "Muted": %s\n}\n', CurrentVolume, IsMuted and "true" or "false"))
            f:close()
        end
    end)
end

LoadConfig()

local function WriteAudioState()
    pcall(function()
        local effectiveVol = IsMuted and 0.0 or CurrentVolume
        local json = string.format(
            '{\n  "bgm_state": "%s",\n  "bgm_track": "%s",\n  "bgm_loop": %s,\n  "bgm_volume": %.2f,\n  "fade_seconds": %.2f,\n  "sfx_track": "%s",\n  "sfx_volume": %.2f,\n  "sfx_sequence": %d\n}\n',
            CurrentBgmState,
            CurrentBgmTrack,
            CurrentBgmLoop and "true" or "false",
            effectiveVol,
            CurrentFadeSec,
            CurrentSfxTrack,
            effectiveVol,
            SfxSequence
        )
        local tmpFile = StateFile .. ".tmp"
        local f = io.open(tmpFile, "w")
        if f then
            f:write(json)
            f:close()
            os.remove(StateFile)
            os.rename(tmpFile, StateFile)
        end
    end)
end

local function PlayTrack(fileName, loop, fadeSeconds)
    if not fileName or fileName == "" then return end
    if CurrentBgmTrack == fileName and CurrentBgmState == "play" then
        return
    end

    CurrentBgmState = "play"
    CurrentBgmTrack = fileName
    CurrentBgmLoop = (loop ~= false)
    CurrentFadeSec = fadeSeconds or 1.0
    WriteAudioState()

    Log(string.format("Playing Audio: %s (Volume: %.0f%%)", fileName, CurrentVolume * 100))
end

local function StopBGM(fadeSeconds)
    CurrentBgmState = "stop"
    CurrentFadeSec = fadeSeconds or 1.2
    WriteAudioState()
end

local function PlayOneShotSFX(fileName, volumeFraction)
    if IsMuted then return end
    SfxSequence = SfxSequence + 1
    CurrentSfxTrack = fileName
    CurrentSfxVolume = (volumeFraction or 1.0) * CurrentVolume
    WriteAudioState()
end

-- Show visual notification on screen
local function NotifyVolumeChange()
    local pct = math.floor(CurrentVolume * 100 + 0.5)
    local msg = IsMuted and "Custom Music: MUTED" or string.format("Music Volume: %d%% ([ / ] to adjust)", pct)

    -- 1. Try ToastLib (DarnToasts UI toast)
    pcall(function()
        local okT, ToastLib = pcall(require, "ToastLib")
        if okT and ToastLib and type(ToastLib.new) == "function" then
            if not _G.PalOdysseyVolumeToast then
                _G.PalOdysseyVolumeToast = ToastLib.new("PalOdysseyBossAudio")
            end
            if _G.PalOdysseyVolumeToast and type(_G.PalOdysseyVolumeToast.show) == "function" then
                _G.PalOdysseyVolumeToast:show(msg)
                return
            end
        end
    end)

    -- 2. System chat notification
    pcall(function()
        local chatSub = FindFirstOf("PalChatSubsystem")
        if chatSub and chatSub:IsValid() and type(chatSub.SendSystemChatMessage) == "function" then
            local pc = UEHelpers and UEHelpers.GetPlayerController and UEHelpers.GetPlayerController()
            if pc and pc:IsValid() then
                chatSub:SendSystemChatMessage(pc, FText(msg))
                return
            end
        end
        local PalUtil = StaticFindObject("/Script/Pal.Default__PalUtility")
        if PalUtil and PalUtil:IsValid() and type(PalUtil.SendSystemToChat) == "function" then
            PalUtil:SendSystemToChat(msg)
        end
    end)
end

local function SetMasterVolume(newVol)
    CurrentVolume = math.max(0.0, math.min(1.0, math.floor((newVol * 100) + 0.5) / 100.0))
    SaveConfig()
    CurrentFadeSec = 0.05 -- Snappy volume adjustment (50ms)
    WriteAudioState()

    Log(string.format("Master Volume set to: %.0f%%", CurrentVolume * 100))
    NotifyVolumeChange()
end

local function ToggleMute()
    IsMuted = not IsMuted
    SaveConfig()
    CurrentFadeSec = 0.05
    WriteAudioState()
    if IsMuted then
        Log("Custom Music MUTED")
    else
        Log("Custom Music UNMUTED")
    end
    NotifyVolumeChange()
end

-- 3. In-Game Chat Commands & Hotkeys for Volume Adjustment
local function ProcessVolumeChat(Context, Param1)
    local function TryGetStr(val)
        if not val then return "" end
        local s = ""
        pcall(function()
            local obj = val
            if type(val.get) == "function" then obj = val:get() end
            if type(obj) == "string" then s = obj
            elseif type(obj.ToString) == "function" then s = obj:ToString()
            elseif obj.Message and type(obj.Message.ToString) == "function" then s = obj.Message:ToString() end
        end)
        return s
    end

    local text = TryGetStr(Param1):lower():gsub("^%s+", ""):gsub("%s+$", "")
    local volArg = text:match("^/vol%s+(%d+)") or text:match("^!vol%s+(%d+)") or text:match("^/volume%s+(%d+)")
    if volArg then
        local pct = tonumber(volArg)
        if pct then
            SetMasterVolume(pct / 100.0)
        end
    elseif text == "/mute" or text == "!mute" or text == "/unmute" then
        ToggleMute()
    end
end

pcall(RegisterHook, "/Script/Pal.PalPlayerState:EnterChat", ProcessVolumeChat)
pcall(RegisterHook, "/Script/Pal.PalGameStateInGame:BroadcastChatMessage", ProcessVolumeChat)

-- Keyboard shortcuts:
-- [ / - / Numpad- : Volume Down 1%
-- ] / = / Numpad+ : Volume Up 1%
-- \ / VolumeMute   : Toggle Mute
local function BindKey(k, cb)
    if not k then return end
    if type(RegisterKeyBind) == "function" then
        pcall(RegisterKeyBind, k, cb)
    end
    if type(RegisterKeyBindAsync) == "function" then
        pcall(RegisterKeyBindAsync, k, {}, cb)
    end
end

if Key then
    pcall(function()
        -- Volume Down (1%)
        BindKey(Key.OEM_FOUR, function() SetMasterVolume(CurrentVolume - 0.01) end)
        BindKey(Key.OEM_MINUS, function() SetMasterVolume(CurrentVolume - 0.01) end)
        BindKey(Key.SUBTRACT, function() SetMasterVolume(CurrentVolume - 0.01) end)

        -- Volume Up (1%)
        BindKey(Key.OEM_SIX, function() SetMasterVolume(CurrentVolume + 0.01) end)
        BindKey(Key.OEM_PLUS, function() SetMasterVolume(CurrentVolume + 0.01) end)
        BindKey(Key.ADD, function() SetMasterVolume(CurrentVolume + 0.01) end)

        -- Mute
        BindKey(Key.OEM_FIVE, function() ToggleMute() end)
        BindKey(Key.VOLUME_MUTE, function() ToggleMute() end)
    end)
end

-- 4. Environment & Combat Music Resolver (Zero-Hitch Cached Architecture)
local cachedTimeMgr = nil
local lastTimeMgrScan = 0
local cachedPlayerChar = nil
local lastPlayerCharScan = 0
local cachedStageMgr = nil
local lastStageMgrScan = 0

local function GetCachedTimeMgr()
    if cachedTimeMgr and cachedTimeMgr:IsValid() then return cachedTimeMgr end
    local now = os.clock()
    if now - lastTimeMgrScan > 10.0 then
        lastTimeMgrScan = now
        pcall(function() cachedTimeMgr = FindFirstOf("PalTimeManager") end)
    end
    return (cachedTimeMgr and cachedTimeMgr:IsValid()) and cachedTimeMgr or nil
end

local function GetCachedPlayerChar()
    if cachedPlayerChar and cachedPlayerChar:IsValid() then return cachedPlayerChar end
    local pc = UEHelpers and UEHelpers.GetPlayerController and UEHelpers.GetPlayerController()
    if pc and pc:IsValid() then
        local pawn = pc.Pawn or pc.AcknowledgedPawn or pc.Character
        if pawn and pawn:IsValid() then
            cachedPlayerChar = pawn
            return pawn
        end
    end
    local now = os.clock()
    if now - lastPlayerCharScan > 10.0 then
        lastPlayerCharScan = now
        pcall(function() cachedPlayerChar = FindFirstOf("PalPlayerCharacter") end)
    end
    return (cachedPlayerChar and cachedPlayerChar:IsValid()) and cachedPlayerChar or nil
end

local function GetCachedStageMgr()
    if cachedStageMgr and cachedStageMgr:IsValid() then return cachedStageMgr end
    local now = os.clock()
    if now - lastStageMgrScan > 10.0 then
        lastStageMgrScan = now
        pcall(function() cachedStageMgr = FindFirstOf("PalStageManager") end)
    end
    return (cachedStageMgr and cachedStageMgr:IsValid()) and cachedStageMgr or nil
end

local function GetDirectDayNight()
    local time = "Day"
    pcall(function()
        local timeMgr = GetCachedTimeMgr()
        if timeMgr and timeMgr:IsValid() then
            if type(timeMgr.IsNight) == "function" and timeMgr:IsNight() then
                time = "Night"
            elseif type(timeMgr.IsDay) == "function" and timeMgr:IsDay() then
                time = "Day"
            else
                local t = timeMgr.CurrentDayTimeType or timeMgr.NowDayTimeType or timeMgr.DayTimeType
                if t == 2 or (t and tostring(t):lower():find("night")) then
                    time = "Night"
                end
            end
        end
    end)
    return time
end

local function GetDirectIsDungeon()
    local inDungeon = false
    pcall(function()
        local char = GetCachedPlayerChar()
        if char and char:IsValid() and type(char.IsInStage) == "function" then
            inDungeon = char:IsInStage()
            return
        end
        local sm = GetCachedStageMgr()
        if sm and sm:IsValid() and type(sm.IsInStage) == "function" then
            local pc = UEHelpers and UEHelpers.GetPlayerController and UEHelpers.GetPlayerController()
            if pc and pc:IsValid() then
                inDungeon = sm:IsInStage(pc)
            end
        end
    end)
    return inDungeon
end

local function GetDirectTemperature()
    local temp = "Normal"
    pcall(function()
        local char = GetCachedPlayerChar()
        if char and char:IsValid() then
            local param = char.CharacterParameterComponent
            if param and param:IsValid() and type(param.GetBodyTemperature) == "function" then
                local t = param:GetBodyTemperature() or 0
                if t >= 1.25 then temp = "Hot"
                elseif t <= -1.25 then temp = "Cold"
                end
            end
        end
    end)
    return temp
end

local cachedAmbientTrack = "region_aincrad.mp3"
local lastAmbientCheckTime = 0

local function ResolveAmbientTrack()
    local now = os.clock()
    if now - lastAmbientCheckTime < 6.0 and cachedAmbientTrack then
        return cachedAmbientTrack
    end
    lastAmbientCheckTime = now

    local dungeon = GetDirectIsDungeon()
    local time = GetDirectDayNight()
    local temp = GetDirectTemperature()

    -- Fallback to state file if present
    pcall(function()
        local f = io.open(AdaptiveStateFile, "r")
        if f then
            local content = f:read("*all")
            f:close()
            if content:find('"dungeon_active":%s*true') then dungeon = true end
            local t = content:match('"time":%s*"([^"]+)"')
            if t then time = t end
            local tp = content:match('"temperature":%s*"([^"]+)"')
            if tp then temp = tp end
        end
    end)

    local track = "region_aincrad.mp3"
    if dungeon then
        track = "dungeon_weird_place.mp3"
    elseif temp == "Hot" then
        track = "region_desert.mp3"
    elseif temp == "Cold" then
        track = "region_snow.mp3"
    elseif time == "Night" then
        track = "night_theme.mp3"
    end
    cachedAmbientTrack = track
    return track
end

-- 5. Game State & Combat Detection
local ActiveMajorBossCombat = false
local ActiveFieldBossCombat = false
local LastCombatHitTime = 0
local IsInTitle = true

local function UpdateMusicState()
    _G.PalOdysseyBossAudio_Active = true

    if IsInTitle then
        PlayTrack("title_perfect_time.mp3", true, 1.0)
        return
    end

    if ActiveMajorBossCombat then
        PlayTrack("boss_theme_opm.mp3", true, 0.8)
        return
    end

    if ActiveFieldBossCombat then
        PlayTrack("boss_luminous_sword.mp3", true, 0.8)
        return
    end

    -- Normal exploration
    local ambient = ResolveAmbientTrack()
    PlayTrack(ambient, true, 1.5)
end

local function CheckHeadshotBone(bone)
    if not bone then return false end
    local str = ""
    pcall(function()
        if type(bone.ToString) == "function" then str = bone:ToString():lower()
        else str = tostring(bone):lower() end
    end)
    return str:find("head") or str:find("neck") or str:find("face") or str:find("jaw") or str:find("skull") or str:find("horn")
end

-- Headshot / Weak-Point Hit SFX
pcall(RegisterHook, "/Script/Engine.Actor:ReceivePointDamage", function(Context, Damage, DamageType, HitLocation, HitNormal, HitComponent, BoneName)
    pcall(function()
        local b = BoneName and BoneName.get and BoneName:get() or BoneName
        if CheckHeadshotBone(b) then
            PlayOneShotSFX("rust_headshot.wav", 0.85)
        end
    end)
end)

pcall(RegisterHook, "/Script/Pal.PalUIDamageText:Setup", function(Context, Damage, bCritical, bWeakPoint)
    pcall(function()
        local crit = bCritical and (bCritical.get and bCritical:get() or bCritical == true)
        local weak = bWeakPoint and (bWeakPoint.get and bWeakPoint:get() or bWeakPoint == true)
        if crit or weak then
            PlayOneShotSFX("rust_headshot.wav", 0.85)
        end
    end)
end)

-- Combat & Boss Damage Hooks
local function OnDamageProcessed(Context, DamageInfo)
    pcall(function()
        local victim = Context and Context.get and Context:get() or Context
        if not victim or not victim:IsValid() then return end

        local isMajor = false
        local isField = false

        if victim.IsTowerBoss and type(victim.IsTowerBoss) == "function" and victim:IsTowerBoss() then isMajor = true end
        if not isMajor and victim.IsBoss and type(victim.IsBoss) == "function" and victim:IsBoss() then
            local level = 1
            if victim.CharacterParameterComponent and victim.CharacterParameterComponent:IsValid() then
                level = victim.CharacterParameterComponent:GetLevel() or 1
            end
            if level >= 50 then isMajor = true else isField = true end
        end
        if not isMajor and not isField and victim.IsRarePal and type(victim.IsRarePal) == "function" and victim:IsRarePal() then
            isField = true
        end

        if isMajor or isField then
            LastCombatHitTime = os.time()
            if isMajor then
                ActiveMajorBossCombat = true
                ActiveFieldBossCombat = false
            elseif isField and not ActiveMajorBossCombat then
                ActiveFieldBossCombat = true
            end
            UpdateMusicState()
        end
    end)
end

pcall(RegisterHook, "/Script/Pal.PalCharacter:OnDamage", OnDamageProcessed)

-- Boss HP Bar UI Display
pcall(RegisterHook, "/Script/Pal.PalUIBossHP:Show", function()
    LastCombatHitTime = os.time()
    if not ActiveMajorBossCombat then
        ActiveFieldBossCombat = true
        UpdateMusicState()
    end
end)

-- Capture & Victory Fanfares
pcall(RegisterHook, "/Script/Pal.PalCaptureSubsystem:OnCaptureSuccess", function()
    if ActiveMajorBossCombat or ActiveFieldBossCombat then
        ActiveMajorBossCombat = false
        ActiveFieldBossCombat = false
        PlayOneShotSFX("victory_fanfare.mp3", 0.85)
        UpdateMusicState()
    end
end)

pcall(RegisterHook, "/Script/Pal.PalCharacter:OnDead", function(Context)
    pcall(function()
        local dead = Context and Context.get and Context:get() or Context
        if not dead or not dead:IsValid() then return end

        local isBoss = false
        if dead.IsBoss and type(dead.IsBoss) == "function" and dead:IsBoss() then isBoss = true end
        if not isBoss and dead.IsRarePal and type(dead.IsRarePal) == "function" and dead:IsRarePal() then isBoss = true end
        if not isBoss and dead.IsTowerBoss and type(dead.IsTowerBoss) == "function" and dead:IsTowerBoss() then isBoss = true end

        if isBoss and (ActiveMajorBossCombat or ActiveFieldBossCombat) then
            ActiveMajorBossCombat = false
            ActiveFieldBossCombat = false
            PlayOneShotSFX("victory_fanfare.mp3", 0.85)
            UpdateMusicState()
        end
    end)
end)

-- Title Screen & Transitions
local function CheckIsInWorld()
    local char = GetCachedPlayerChar()
    if char and char:IsValid() then return true end
    local inWorld = false
    pcall(function()
        local gs = FindFirstOf("PalGameStateInGame")
        if gs and gs:IsValid() then inWorld = true end
    end)
    if inWorld then return true end
    pcall(function()
        local f = io.open(AdaptiveStateFile, "r")
        if f then
            local str = f:read("*all")
            f:close()
            if str:find('"world_active":%s*true') then
                inWorld = true
            end
        end
    end)
    return inWorld
end

local function OnTitleScreen()
    IsInTitle = true
    ActiveMajorBossCombat = false
    ActiveFieldBossCombat = false
    UpdateMusicState()
end

local function OnJoinedWorld()
    IsInTitle = false
    Log("Player joined world -> Starting exploration music with full volume controls.")
    UpdateMusicState()
end

pcall(function()
    NotifyOnNewObject("/Script/Pal.PalGameStateInTitle", function()
        OnTitleScreen()
    end)
end)

pcall(function()
    NotifyOnNewObject("/Script/Pal.PalGameStateInGame", function()
        OnJoinedWorld()
    end)
end)

-- Removed ClientRestart hook: mounting/dismounting does not need audio reset
pcall(RegisterHook, "/Script/Pal.PalPlayerController:ClientTravel", function()
    OnJoinedWorld()
end)

-- Background Proximity & Combat Expiry Loop
local delayFunc = ExecuteInGameThreadWithDelay or ExecuteWithDelay
if delayFunc then
    local function MonitorLoop()
        pcall(function()
            local now = os.time()
            if (ActiveMajorBossCombat or ActiveFieldBossCombat) and (now - LastCombatHitTime > 18) then
                ActiveMajorBossCombat = false
                ActiveFieldBossCombat = false
                Log("Boss combat timeout -> Resumed exploration audio.")
            end

            local inWorld = CheckIsInWorld()
            if inWorld and IsInTitle then
                IsInTitle = false
                Log("Player detected in world -> Transitioning from title music to exploration BGM.")
            elseif not inWorld and not IsInTitle then
                IsInTitle = true
                Log("Player left world -> Transitioning to title music.")
            end

            UpdateMusicState()
        end)
        delayFunc(5000, MonitorLoop)
    end
    delayFunc(3500, MonitorLoop)
end

-- Initial Check on Mod Load
local okInit, inWorld = pcall(CheckIsInWorld)
if not okInit or not inWorld then
    OnTitleScreen()
else
    IsInTitle = false
    UpdateMusicState()
end

Log("PalOdysseyBossAudio initialized with unified ambient/boss music engine and live volume controls.")
