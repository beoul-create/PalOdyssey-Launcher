local BossMusic = {}

local ScriptDir = debug.getinfo(1, "S").source:gsub("^@", ""):gsub("[^/\\]+$", "")
local AudioDir = ScriptDir .. "../audio/"
local StateFile = AudioDir .. "music_state.json"
local JukeboxExe = AudioDir .. "PalBossJukebox.exe"

local IsMusicPlaying = false
local JukeboxStarted = false

local function EnsureJukeboxRunning()
    if JukeboxStarted then return end
    pcall(function()
        os.execute(string.format('start "" /B "%s"', JukeboxExe:gsub("/", "\\")))
        JukeboxStarted = true
    end)
end

function BossMusic.Play()
    if IsMusicPlaying then return end
    IsMusicPlaying = true
    EnsureJukeboxRunning()

    pcall(function()
        local f = io.open(StateFile, "w")
        if f then
            f:write('{"state":"play"}')
            f:close()
        end
    end)
    print("[WorldBossAuraSystem] 🎵 One Punch Man Boss Battle Theme started!")
end

function BossMusic.FadeOut()
    if not IsMusicPlaying then return end
    IsMusicPlaying = false

    pcall(function()
        local f = io.open(StateFile, "w")
        if f then
            f:write('{"state":"fade_out"}')
            f:close()
        end
    end)
    print("[WorldBossAuraSystem] 🎵 One Punch Man Boss Battle Theme fading out.")
end

function BossMusic.Init()
    -- 1. Hook Damage on Bosses to trigger combat music
    pcall(RegisterHook, "/Script/Pal.PalCharacter:OnDamage", function(Context, DamageInfo)
        pcall(function()
            local victim = Context and Context.get and Context:get() or Context
            if not victim or not victim:IsValid() then return end

            local isBoss = false
            if victim.IsBoss and type(victim.IsBoss) == "function" and victim:IsBoss() then isBoss = true end
            if not isBoss and victim.IsRarePal and type(victim.IsRarePal) == "function" and victim:IsRarePal() then isBoss = true end
            if not isBoss and victim.IsTowerBoss and type(victim.IsTowerBoss) == "function" and victim:IsTowerBoss() then isBoss = true end
            if not isBoss and victim.CharacterParameterComponent and victim.CharacterParameterComponent:IsValid() then
                local level = victim.CharacterParameterComponent:GetLevel() or 1
                if level >= 50 then isBoss = true end
            end

            if isBoss and not IsMusicPlaying then
                BossMusic.Play()
            end
        end)
    end)

    -- 2. Hook Boss HP UI display
    pcall(RegisterHook, "/Script/Pal.PalUIBossHP:Show", function(Context)
        BossMusic.Play()
    end)

    -- 3. Hook Boss Death -> Fade Out
    pcall(RegisterHook, "/Script/Pal.PalCharacter:OnDead", function(Context)
        pcall(function()
            local dead = Context and Context.get and Context:get() or Context
            if dead and dead:IsValid() then
                local isBoss = false
                if dead.IsBoss and type(dead.IsBoss) == "function" and dead:IsBoss() then isBoss = true end
                if not isBoss and dead.IsRarePal and type(dead.IsRarePal) == "function" and dead:IsRarePal() then isBoss = true end
                if not isBoss and dead.IsTowerBoss and type(dead.IsTowerBoss) == "function" and dead:IsTowerBoss() then isBoss = true end
                if isBoss then
                    BossMusic.FadeOut()
                end
            end
        end)
    end)

    -- 4. Hook Capture Success -> Fade Out
    pcall(RegisterHook, "/Script/Pal.PalCaptureSubsystem:OnCaptureSuccess", function(Context)
        BossMusic.FadeOut()
    end)

    -- 5. Hook Dungeon / Tower Battle End
    pcall(RegisterHook, "/Script/Pal.PalBossBattleSequencer:EndBattle", function(Context)
        BossMusic.FadeOut()
    end)

    print("[WorldBossAuraSystem] Boss Battle Music System initialized.")
end

return BossMusic
