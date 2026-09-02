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

local function GetMasterVolume()
    local vol = 0.40
    pcall(function()
        local f = io.open(ScriptDir .. "../config.json", "r")
        if f then
            local txt = f:read("*all")
            f:close()
            local m = txt:match('"MusicMasterVolume"%s*:%s*([%d%.]+)')
            if m then vol = tonumber(m) or 0.40 end
        end
    end)
    return math.max(0.0, math.min(1.0, vol))
end

function BossMusic.SetTrack(trackName, loop, volume)
    if CurrentTrack == trackName and CurrentState == "play" then return end
    EnsureJukeboxRunning()
    CurrentTrack = trackName
    CurrentState = "play"

    local master = GetMasterVolume()
    local finalVol = math.max(0.01, math.min(1.0, (volume or 0.65) * master))

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

local function DetermineRegionTrack(playerLoc, player)
    -- 1. Check if inside Dungeon / Underground Cave instance
    if playerLoc.Z < -30000.0 then
        return "dungeon_weird_place.mp3", 0.65
    end

    -- 2. Check if in Player Base Camp (multi-method detection)
    local inBase = false

    -- Method A: Palbox / Base Camp Point Actors
    pcall(function()
        local boxClasses = { "BP_PalBox_C", "PalMapObjectBaseCampPoint", "BP_BaseCampPoint_C" }
        for _, cls in ipairs(boxClasses) do
            local boxes = FindAllOf and FindAllOf(cls)
            if boxes and #boxes > 0 then
                for _, b in ipairs(boxes) do
                    if b and b:IsValid() then
                        local bLoc = b:K2_GetActorLocation()
                        if bLoc then
                            local dx = playerLoc.X - bLoc.X
                            local dy = playerLoc.Y - bLoc.Y
                            if (dx*dx + dy*dy) <= (4800.0 * 4800.0) then
                                inBase = true
                                return
                            end
                        end
                    end
                end
            end
        end
    end)

    -- Method B: Check Nearby Base Camp Worker Pals
    if not inBase then
        pcall(function()
            local pals = FindAllOf and (FindAllOf("PalCharacter") or FindAllOf("Character"))
            if pals then
                for _, p in ipairs(pals) do
                    if p and p:IsValid() and p ~= player then
                        local isBasePal = false
                        if p.CharacterParameterComponent and p.CharacterParameterComponent:IsValid() then
                            local param = p.CharacterParameterComponent
                            if type(param.IsBaseCampPal) == "function" and param:IsBaseCampPal() then
                                isBasePal = true
                            elseif type(param.GetAssignedBaseCamp) == "function" and param:GetAssignedBaseCamp() then
                                isBasePal = true
                            end
                        end
                        if isBasePal then
                            local loc = p:K2_GetActorLocation()
                            if loc then
                                local dx = playerLoc.X - loc.X
                                local dy = playerLoc.Y - loc.Y
                                if (dx*dx + dy*dy) <= (3800.0 * 3800.0) then
                                    inBase = true
                                    return
                                end
                            end
                        end
                    end
                end
            end
        end)
    end

    -- Method C: Check Player-Built Structures Cluster (PalBuildObject)
    if not inBase then
        pcall(function()
            local builds = FindAllOf and FindAllOf("PalBuildObject")
            if builds and #builds >= 2 then
                local nearCount = 0
                for _, b in ipairs(builds) do
                    if b and b:IsValid() then
                        local loc = b:K2_GetActorLocation()
                        if loc then
                            local dx = playerLoc.X - loc.X
                            local dy = playerLoc.Y - loc.Y
                            if (dx*dx + dy*dy) <= (3800.0 * 3800.0) then
                                nearCount = nearCount + 1
                                if nearCount >= 2 then
                                    inBase = true
                                    return
                                end
                            end
                        end
                    end
                end
            end
        end)
    end

    -- Method D: PalBaseCampModel centers
    if not inBase then
        pcall(function()
            local camps = FindAllOf and FindAllOf("PalBaseCampModel")
            if camps then
                for _, camp in ipairs(camps) do
                    if camp and camp:IsValid() then
                        local cLoc = (type(camp.GetLocation) == "function" and camp:GetLocation())
                            or (type(camp.GetRawLocation) == "function" and camp:GetRawLocation())
                            or camp.CenterLocation
                        if cLoc then
                            local dx = playerLoc.X - cLoc.X
                            local dy = playerLoc.Y - cLoc.Y
                            if (dx*dx + dy*dy) <= (4500.0 * 4500.0) then
                                inBase = true
                                return
                            end
                        end
                    end
                end
            end
        end)
    end

    if inBase then
        return "base_the_first_town.mp3", 0.60
    end

    -- 3. Biome Coordinates Mapping
    local X = playerLoc.X
    local Y = playerLoc.Y

    -- Astral Mountains (Northwest Snow Biome)
    if X < -50000 and Y > 80000 then
        return "region_snow.mp3", 0.60
    end

    -- Mount Obsidian (Southwest Volcano Biome)
    if X < -60000 and Y < -160000 then
        return "region_volcano.mp3", 0.65
    end

    -- Desolate Dunes (Northeast Desert Biome)
    if X > 120000 and Y > 40000 then
        return "region_desert.mp3", 0.60
    end

    -- Windswept Hills / Grassy Plains / Bamboo Forests (Central & Starting Islands)
    return "region_aincrad.mp3", 0.60
end

local function UpdateMusicState()
    local now = os.time()
    if now < VictoryTimer then
        return -- Fanfare is currently playing
    end

    -- Priority 0: Title Screen
    if IsInTitle then
        BossMusic.SetTrack("title_perfect_time.mp3", true, 0.70)
        return
    end

    -- Priority 0.5: Connecting to server (silence / faded out)
    if IsConnecting then
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

    -- 1. Title Screen & Connection Hooks
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

                    -- Ensure capsule collision wireframe is never rendered on player
                    local cap = player.CapsuleComponent or (type(player.GetRootComponent) == "function" and player:GetRootComponent())
                    if cap and cap:IsValid() and type(cap.SetHiddenInGame) == "function" then
                        pcall(function() cap:SetHiddenInGame(true, false) end)
                    end

                    local pLoc = player:K2_GetActorLocation()
                    if pLoc then
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
            delayFunc(2500, MusicLoop)
        end
        delayFunc(3000, MusicLoop)
    end

    print("[WorldBossAuraSystem] Universal Title, Regional, Dungeon & Boss Music System initialized.")
end

return BossMusic
