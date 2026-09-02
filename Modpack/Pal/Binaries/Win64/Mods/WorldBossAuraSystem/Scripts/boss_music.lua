local BossMusic = {}

local ScriptDir = debug.getinfo(1, "S").source:gsub("^@", ""):gsub("[^/\\]+$", "")
local AudioDir = ScriptDir .. "../audio/"
local StateFile = AudioDir .. "music_state.json"
local JukeboxExe = AudioDir .. "PalBossJukebox.exe"

local CurrentTrack = ""
local CurrentState = "idle"
local JukeboxStarted = false
local VictoryTimer = 0

-- State tracking
local IsInTitle = true
local IsConnecting = false
local ActiveMajorBossCombat = false
local ActiveFieldBossCombat = false
local ActiveNearBoss = false

local function EnsureJukeboxRunning()
    if JukeboxStarted then return end
    -- Verify executable exists before invoking Windows shell
    local f = io.open(JukeboxExe, "rb")
    if not f then return end
    f:close()

    pcall(function()
        os.execute(string.format('start "" /B "%s"', JukeboxExe:gsub("/", "\\")))
        JukeboxStarted = true
    end)
end

local CurrentMasterVolume = 0.15
local CurrentBaseVolume = 0.60
local CurrentLoop = true
local LastUnmutedVolume = 0.15

local function GetMasterVolume()
    local vol = CurrentMasterVolume
    pcall(function()
        local f = io.open(ScriptDir .. "../config.json", "r")
        if f then
            local txt = f:read("*all")
            f:close()
            local m = txt:match('"MusicMasterVolume"%s*:%s*([%d%.]+)')
            if m then
                vol = tonumber(m) or vol
                CurrentMasterVolume = vol
            end
        end
    end)
    return math.max(0.0, math.min(1.0, vol))
end

function BossMusic.SetMasterVolume(vol)
    vol = math.max(0.0, math.min(1.0, vol))
    CurrentMasterVolume = vol
    if vol > 0.01 then LastUnmutedVolume = vol end

    -- 1. Save to config.json
    pcall(function()
        local cfgPath = ScriptDir .. "../config.json"
        local f = io.open(cfgPath, "r")
        local content = f and f:read("*all") or ""
        if f then f:close() end

        if content:find('"MusicMasterVolume"') then
            content = content:gsub('"MusicMasterVolume"%s*:%s*[%d%.]+', string.format('"MusicMasterVolume": %.2f', vol))
        else
            content = content:gsub("^{", string.format('{\n  "MusicMasterVolume": %.2f,', vol))
        end
        local wf = io.open(cfgPath, "w")
        if wf then wf:write(content); wf:close() end
    end)

    -- 2. Immediately update playing volume in music_state.json
    pcall(function()
        if CurrentTrack ~= "" and CurrentState == "play" then
            local finalVol = math.max(0.0, math.min(1.0, CurrentBaseVolume * vol))
            local f = io.open(StateFile, "w")
            if f then
                f:write(string.format('{"state":"play","track":"%s","loop":%s,"volume":%.2f}', CurrentTrack, CurrentLoop and "true" or "false", finalVol))
                f:close()
            end
        end
    end)

    print(string.format("[WorldBossAuraSystem] 🎵 Master Volume set to: %d%%", math.floor(vol * 100 + 0.5)))
end

function BossMusic.ToggleMute()
    if CurrentMasterVolume > 0.01 then
        BossMusic.SetMasterVolume(0.0)
    else
        BossMusic.SetMasterVolume(LastUnmutedVolume > 0.05 and LastUnmutedVolume or 0.15)
    end
end

function BossMusic.SetTrack(trackName, loop, volume)
    if CurrentTrack == trackName and CurrentState == "play" then return end
    EnsureJukeboxRunning()
    CurrentTrack = trackName
    CurrentState = "play"
    CurrentBaseVolume = volume or 0.65
    CurrentLoop = loop and true or false

    local master = GetMasterVolume()
    local finalVol = math.max(0.0, math.min(1.0, CurrentBaseVolume * master))

    pcall(function()
        local f = io.open(StateFile, "w")
        if f then
            f:write(string.format('{"state":"play","track":"%s","loop":%s,"volume":%.2f}', trackName, loop and "true" or "false", finalVol))
            f:close()
        end
    end)
    print(string.format("[WorldBossAuraSystem] 🎵 Jukebox playing: %s (Loop: %s, Vol: %.2f [Master: %.2f])", trackName, tostring(loop), finalVol, master))
end

function BossMusic.FadeOut()
    if CurrentState == "fade_out" then return end
    CurrentTrack = ""
    CurrentState = "fade_out"

    pcall(function()
        local f = io.open(StateFile, "w")
        if f then
            f:write('{"state":"fade_out"}')
            f:close()
        end
    end)
    print("[WorldBossAuraSystem] 🎵 Jukebox fading out.")
end

function BossMusic.PlayVictoryFanfare()
    ActiveMajorBossCombat = false
    ActiveFieldBossCombat = false
    VictoryTimer = os.time() + 6 -- 6 seconds fanfare
    BossMusic.SetTrack("victory_fanfare.mp3", false, 0.75)
end

function BossMusic.PlayHeadshotSFX()
    pcall(function()
        EnsureJukeboxRunning()
        local pipe = io.open([[\.\pipe\PalHeadshotPipe]], "w")
        if pipe then
            pipe:write("1")
            pipe:flush()
            pipe:close()
        end
    end)
end

local function OnTitleScreen()
    IsInTitle = true
    IsConnecting = false
    ActiveMajorBossCombat = false
    ActiveFieldBossCombat = false
    BossMusic.SetTrack("title_perfect_time.mp3", true, 0.70)
end

local function OnConnectingToServer()
    if IsConnecting then return end
    IsConnecting = true
    IsInTitle = false
    print("[WorldBossAuraSystem] 🌐 Connecting to server... fading title music.")
    BossMusic.FadeOut()
end

local function OnJoinedWorld()
    IsConnecting = false
    IsInTitle = false
end

local function GetLocalPlayer()
    local player = nil
    pcall(function()
        if UEHelpers and UEHelpers.GetPlayerController then
            local pc = UEHelpers.GetPlayerController()
            if pc and pc:IsValid() and pc.Pawn and pc.Pawn:IsValid() then
                player = pc.Pawn
                return
            end
        end
        local p = FindFirstOf("PalPlayerCharacter")
        if p and p:IsValid() then player = p end
    end)
    return player
end

local CachedBases = {}
local LastBaseScan = 0

local function RefreshBaseCaches()
    pcall(function()
        local list = {}
        local boxClasses = { "BP_PalBox_C", "PalMapObjectBaseCampPoint", "BP_BaseCampPoint_C" }
        for _, cls in ipairs(boxClasses) do
            local boxes = FindAllOf and FindAllOf(cls)
            if boxes then
                for _, b in ipairs(boxes) do
                    if b and b:IsValid() then
                if c and c:IsValid() and type(c.GetLocation) == "function" then
                    local loc = c:GetLocation()
                    if loc then table.insert(list, { X = loc.X, Y = loc.Y }) end
                end
            end
        end
        if #list > 0 then
            CachedBases = list
        end
    end)
end

local function DetermineRegionTrack(playerLoc, player)
    end

    -- 2. Base Camp Detection (Checks cached coordinates without hitching)
    local inBase = false
    local nowClock = os.clock()
    if #CachedBases == 0 then
        if (nowClock - LastBaseScan > 2.0) then
            LastBaseScan = nowClock
            RefreshBaseCaches()
        end
    elseif (nowClock - LastBaseScan > 30.0) then
        LastBaseScan = nowClock
        RefreshBaseCaches()
            inBase = true
            break
        end
    end

    if inBase then
        return "base_the_first_town.mp3", 0.60
    end
    -- 3. Biome Coordinates Mapping (Based on verified Palworld world grid)
    local X = playerLoc.X
    local Y = playerLoc.Y

    -- Astral Mountains (Frozen North / Arctic Tundra - Far Northwest only)
    if X < -280000 and Y > 200000 then
        return "region_snow.mp3", 0.60
    end

    -- Mount Obsidian (Volcano: Far Southwest)
    if X < -80000 and Y < -160000 then
        return "region_volcano.mp3", 0.65
    end

    -- Desolate Dunes (Far Northeast Desert)
    if X > 100000 and Y > 60000 then
        return "region_desert.mp3", 0.60
    end

    -- Windswept Hills / Grassy Plains / Starting Plateau / Central Islands
    return "region_aincrad.mp3", 0.60
end

local CachedTimeManager = nil
local function IsNightTime()
    local isNight = false
    pcall(function()
        if not CachedTimeManager or not CachedTimeManager:IsValid() then
            CachedTimeManager = FindFirstOf("PalTimeManager") or FindFirstOf("PalWorldTimeManager")
        end
        if CachedTimeManager and CachedTimeManager:IsValid() then
            if type(CachedTimeManager.IsNight) == "function" then
                isNight = CachedTimeManager:IsNight()
                return
            end
            if type(CachedTimeManager.IsDay) == "function" then
                isNight = not CachedTimeManager:IsDay()
                return
            end
        end

        local gs = FindFirstOf("PalGameStateInGame")
        if gs and gs:IsValid() then
            if type(gs.IsNight) == "function" then
                isNight = gs:IsNight()
                return
            end
            local tm = gs.TimeManager or gs.WorldTimeManager
            if tm and tm:IsValid() then
                if type(tm.IsNight) == "function" then
                    isNight = tm:IsNight()
                    return
                end
                if type(tm.IsDay) == "function" then
                    isNight = not tm:IsDay()
                    return
                end
            end
        end
    end)
    return isNight
end

local function UpdateMusicState()
    local now = os.time()
    if now < VictoryTimer then
        return -- Fanfare is currently playing
    end

    if IsInTitle then
        BossMusic.SetTrack("title_perfect_time.mp3", true, 0.70)
        return
    end

    -- Priority 0.5: Connecting to server (silence / faded out)
    if IsConnecting then
        return
    end

    -- Priority 0.8: Night Time Theme (Overrides all boss, base, and regional songs)
    if IsNightTime() then
        BossMusic.SetTrack("night_theme.mp3", true, 0.65)
        return
    end

    -- Priority 1: 5-Minute Aura World Boss / Tower Boss / Raid Boss Combat
    if ActiveMajorBossCombat then
        BossMusic.SetTrack("boss_theme_opm.mp3", true, 0.80)
        return
    end

    -- Priority 2: Field Boss Combat or Proximity (< 6000 units)
    if ActiveFieldBossCombat or ActiveNearBoss then
        BossMusic.SetTrack("boss_luminous_sword.mp3", true, 0.75)
        return
    end

    -- Priority 3: Regional / Dungeon / Base Camp Music
    local player = GetLocalPlayer()
    if player and player:IsValid() then
        local pLoc = player:K2_GetActorLocation()
        if pLoc then
            local track, vol = DetermineRegionTrack(pLoc, player)
            BossMusic.SetTrack(track, true, vol)
            return
        end
    end
end

function BossMusic.Init()
    -- Dedicated servers do not have audio devices or local players!
    local src = (debug.getinfo(1, "S").source or ""):lower()
    if src:find("palserver") then
        print("[WorldBossAuraSystem] Dedicated server detected. Audio Jukebox disabled on server.")
        return
    end

    local isDedicated = false
    pcall(function()
        local kismet = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
        local world = UEHelpers and UEHelpers.GetWorldContextObject and UEHelpers.GetWorldContextObject()
        if kismet and kismet:IsValid() and world and world:IsValid() and type(kismet.IsDedicatedServer) == "function" then
            isDedicated = kismet:IsDedicatedServer(world)
        end
    end)
    if isDedicated then
        print("[WorldBossAuraSystem] Dedicated server detected via Kismet. Audio Jukebox disabled on server.")
        return
    end

    -- 1. In-Game Volume Chat Commands: /vol <0-100>, /mute, /unmute
    local function ProcessVolumeChat(Context, Param1, Param2)
        local function TryGetStr(val)
            if not val then return "" end
            local s = ""
            pcall(function()
                if type(val.ToString) == "function" then s = val:ToString()
                else s = tostring(val) end
            end)
            return s
        end

        local text = TryGetStr(Param1)
        if text == "" then text = TryGetStr(Param2) end
        if text == "" and Context and Context.Message then text = TryGetStr(Context.Message) end
        text = text:lower():match("^%s*(.-)%s*$") or ""

        local volNum = text:match("^/[vV][oO][lL]%s+(%d+)") or text:match("^/[vV][oO][lL][uU][mM][eE]%s+(%d+)") or text:match("^/[mM][uU][sS][iI][cC]%s+(%d+)")
        if volNum then
            local n = tonumber(volNum)
            if n then
                BossMusic.SetMasterVolume(n / 100.0)
            end
        elseif text == "/mute" then
            BossMusic.SetMasterVolume(0.0)
        elseif text == "/unmute" then
            BossMusic.ToggleMute()
        end
    end

    pcall(RegisterHook, "/Script/Pal.PalPlayerState:EnterChat", ProcessVolumeChat)
    pcall(RegisterHook, "/Script/Pal.PalGameStateInGame:BroadcastChatMessage", ProcessVolumeChat)

    -- In-Game Volume Hotkeys: [ (Vol Down), ] (Vol Up), \ (Mute)
    if type(RegisterKeyBindAsync) == "function" and Key then
        pcall(function()
            if Key.OPEN_BRACKET then
                RegisterKeyBindAsync(Key.OPEN_BRACKET, {}, function()
                    BossMusic.SetMasterVolume(CurrentMasterVolume - 0.03)
                end)
            end
            if Key.CLOSE_BRACKET then
                RegisterKeyBindAsync(Key.CLOSE_BRACKET, {}, function()
                    BossMusic.SetMasterVolume(CurrentMasterVolume + 0.03)
                end)
            end
            if Key.BACKSLASH then
                RegisterKeyBindAsync(Key.BACKSLASH, {}, function()
                    BossMusic.ToggleMute()
                end)
            end
        end)
    end

    -- 2. Title Screen & Connection Hooks
    pcall(function()
        NotifyOnNewObject("/Script/Pal.PalGameStateInTitle", function()
            OnTitleScreen()
        end)
    end)

    pcall(function()
        NotifyOnNewObject("/Script/Engine.NetConnection", function()
            OnConnectingToServer()
        end)
    end)

    pcall(RegisterHook, "/Script/Engine.PlayerController:ClientTravel", function(Context)
        OnConnectingToServer()
    end)

    pcall(RegisterHook, "/Script/Engine.PlayerController:ClientRestart", function(Context)
        OnJoinedWorld()
    end)

    -- 2. Headshot / Weak-Point Detection Helpers
    local function CheckHeadshotBone(bone)
        if not bone then return false end
        local str = ""
        pcall(function()
            if type(bone.ToString) == "function" then str = bone:ToString():lower()
            else str = tostring(bone):lower() end
        end)
        return str:find("head") or str:find("neck") or str:find("face") or str:find("jaw") or str:find("skull") or str:find("horn")
    end

    -- Hook Point Damage (e.g. projectile headshots)
    pcall(RegisterHook, "/Script/Engine.Actor:ReceivePointDamage", function(Context, Damage, DamageType, HitLocation, HitNormal, HitComponent, BoneName, ShotFromDirection, InstigatedBy, DamageCauser, HitInfo)
        pcall(function()
            local b = BoneName and BoneName.get and BoneName:get() or BoneName
            if CheckHeadshotBone(b) then
                BossMusic.PlayHeadshotSFX()
            end
        end)
    end)

    -- Hook PalUIDamageText:Setup (triggers when critical/weakpoint damage numbers appear)
    pcall(RegisterHook, "/Script/Pal.PalUIDamageText:Setup", function(Context, Damage, bCritical, bWeakPoint)
        pcall(function()
            local crit = bCritical and (bCritical.get and bCritical:get() or bCritical == true)
            local weak = bWeakPoint and (bWeakPoint.get and bWeakPoint:get() or bWeakPoint == true)
            if crit or weak then
                BossMusic.PlayHeadshotSFX()
            end
        end)
    end)

    -- Hook PalCharacter:OnDamage for combat music & headshot detection
    pcall(RegisterHook, "/Script/Pal.PalCharacter:OnDamage", function(Context, DamageInfo)
        pcall(function()
            local victim = Context and Context.get and Context:get() or Context
            if not victim or not victim:IsValid() then return end

            local di = DamageInfo and DamageInfo.get and DamageInfo:get() or DamageInfo
            if di then
                local isCrit = false
                if di.bWeakPoint == true or di.bIsWeakPoint == true or di.bCritical == true then
                    isCrit = true
                end
                if not isCrit and di.HitInfo and di.HitInfo.BoneName then
                    if CheckHeadshotBone(di.HitInfo.BoneName) then isCrit = true end
                end
                if isCrit then
                    BossMusic.PlayHeadshotSFX()
                end
            end

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

            if isMajor then
                ActiveMajorBossCombat = true
                ActiveFieldBossCombat = false
                BossMusic.SetTrack("boss_theme_opm.mp3", true, 0.80)
            elseif isField then
                ActiveFieldBossCombat = true
                BossMusic.SetTrack("boss_luminous_sword.mp3", true, 0.75)
            end
        end)
    end)

    -- 3. Boss HP UI Show
    pcall(RegisterHook, "/Script/Pal.PalUIBossHP:Show", function(Context)
        ActiveFieldBossCombat = true
        BossMusic.SetTrack("boss_luminous_sword.mp3", true, 0.75)
    end)

    -- 4. Capture Success -> Victory Fanfare
    pcall(RegisterHook, "/Script/Pal.PalCaptureSubsystem:OnCaptureSuccess", function(Context)
        BossMusic.PlayVictoryFanfare()
    end)

    -- 5. Boss Death -> Victory Fanfare
    pcall(RegisterHook, "/Script/Pal.PalCharacter:OnDead", function(Context)
        pcall(function()
            local dead = Context and Context.get and Context:get() or Context
            if dead and dead:IsValid() then
                local isBoss = false
                if dead.IsBoss and type(dead.IsBoss) == "function" and dead:IsBoss() then isBoss = true end
                if not isBoss and dead.IsRarePal and type(dead.IsRarePal) == "function" and dead:IsRarePal() then isBoss = true end
                if not isBoss and dead.IsTowerBoss and type(dead.IsTowerBoss) == "function" and dead:IsTowerBoss() then isBoss = true end
                if isBoss then
                    BossMusic.PlayVictoryFanfare()
                end
            end
        end)
    end)

    -- Initial startup: Check if player exists or at title
    local initP = GetLocalPlayer()
    if not initP then
        OnTitleScreen()
    else
        IsInTitle = false
    end

    -- 6. Periodic Background Loop
    local delayFunc = ExecuteInGameThreadWithDelay or ExecuteWithDelay
    if delayFunc then
        local function MusicLoop()
            pcall(function()
                local player = GetLocalPlayer()
                ActiveNearBoss = false
                if player and player:IsValid() then
                    IsInTitle = false

                    local pLoc = player:K2_GetActorLocation()
                    if pLoc then
                        -- Check expiry of combat music (15s after last combat hit)
                        local now = os.time()
                        if ActiveFieldBossCombat and (now - (LastFieldBossCombatTime or 0) > 15) then
                            ActiveFieldBossCombat = false
                        end

                        -- Aura World Boss proximity (static coordinate math, 0% CPU)
                        local wb = package.loaded["world_boss"]
                        if wb and wb.GetActiveBosses then
                            for _, data in pairs(wb.GetActiveBosses()) do
                                if data.Coords then
                                    local dx = pLoc.X - data.Coords.X
                                    local dy = pLoc.Y - data.Coords.Y
                                    if (dx*dx + dy*dy) < (8000.0 * 8000.0) then
                                        ActiveNearBoss = true
                                        break
                                    end
                                end
                            end
                        end
                    end
                end

                UpdateMusicState()
            end)
            delayFunc(5000, MusicLoop)
        end
        delayFunc(4000, MusicLoop)
    end

    -- Event-Driven Combat Music: Fires instantly when attacking or taking damage from a Boss
    pcall(RegisterHook, "/Script/Pal.PalCharacter:OnDamage", function(Context, DamageResult)
        pcall(function()
            local target = Context and Context.get and Context:get() or Context
            if target and target:IsValid() then
                local isBoss = false
                if type(target.IsBoss) == "function" and target:IsBoss() then isBoss = true end
                if not isBoss and type(target.IsRarePal) == "function" and target:IsRarePal() then isBoss = true end
                if not isBoss and type(target.IsTowerBoss) == "function" and target:IsTowerBoss() then isBoss = true end
                if isBoss then
                    LastFieldBossCombatTime = os.time()
                    if not ActiveFieldBossCombat then
                        ActiveFieldBossCombat = true
                        UpdateMusicState()
                    end
                end
            end
        end)
    end)

    -- Fast-Travel & Teleport Hooks: Instantly re-evaluate music upon arriving
    pcall(RegisterHook, "/Script/Engine.PlayerController:ClientRestart", function(Context)
        local delay = ExecuteInGameThreadWithDelay or ExecuteWithDelay
        if delay then
            delay(500, UpdateMusicState)
            delay(1500, UpdateMusicState)
        else
            UpdateMusicState()
        end
    end)

    print("[WorldBossAuraSystem] Universal Title, Regional, Dungeon & Boss Music System initialized.")
end

return BossMusic
