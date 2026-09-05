-- Level Lock - tower-gated level cap for Palworld
-- Host/server side only, clients don't need it

local Config = require("config")

local MOD = "LevelLock"
local VERSION = "2.3.3"

local scriptDir = debug.getinfo(1, "S").source:sub(2):match("^(.*[/\\])")
local LEGACY_PROGRESS_FILE = scriptDir .. "progress.txt"
local LEGACY_SENTINEL_FILE = scriptDir .. "sentinel.txt"

-- Progress lives next to the game's own saves, NOT in the mod folder: a Steam
-- Workshop update replaces that folder wholesale and would wipe a world's tower
-- clears. But "next to the game's own saves" is a different place per build, so
-- it is resolved rather than assumed:
--
--   dedicated server -> <server>\Pal\Saved, the folder that holds SaveGames.
--                       Derived from this script's own path, which always sits
--                       at <server>\Pal\Binaries\Win64\ue4ss\Mods\LevelLock.
--                       That folder is one an admin can actually reach - on a
--                       Linux host or a rented panel, the Windows account's
--                       AppData is somewhere between hidden and unreachable.
--   client / co-op   -> %LOCALAPPDATA%\Pal\Saved, where a client build keeps
--                       SaveGames. A client install has no Pal\Saved at all,
--                       which is exactly what makes the order below safe.
--
-- First candidate whose folder can actually be written to wins, and
-- Config.ProgressDir jumps the queue for anyone who would rather say it
-- outright. Nothing here is created: every candidate is a folder the game or
-- the admin already made. The mod folder stays last as a guard, not a config.
local PROGRESS_FILE, SENTINEL_FILE
local PROGRESS_FALLBACKS, SENTINEL_FALLBACKS = {}, {}
local progressLocationNote
do
    local candidates = {}
    local function add(progress, sentinel, why)
        candidates[#candidates + 1] = { progress = progress, sentinel = sentinel, why = why }
    end

    local configured = type(Config.ProgressDir) == "string" and Config.ProgressDir or ""
    configured = configured:gsub("[/\\]+$", "")
    if configured ~= "" then
        -- follow whichever separator they typed, so the logged path reads back
        -- the way they wrote it
        local sep = configured:find("/") and "/" or "\\"
        add(configured .. sep .. "LevelLock-progress.txt",
            configured .. sep .. "LevelLock-sentinel.txt",
            "Config.ProgressDir")
    end

    local palDir, sep = scriptDir:match("^(.*[/\\]Pal)([/\\])Binaries[/\\]")
    if palDir then
        local saved = palDir .. sep .. "Saved" .. sep
        add(saved .. "LevelLock-progress.txt", saved .. "LevelLock-sentinel.txt",
            "the game's own Saved folder")
    end

    local appData = os.getenv("LOCALAPPDATA")
    if appData and appData ~= "" then
        add(appData .. "\\Pal\\Saved\\LevelLock-progress.txt",
            appData .. "\\Pal\\Saved\\LevelLock-sentinel.txt",
            "%LOCALAPPDATA%")
    end

    add(LEGACY_PROGRESS_FILE, LEGACY_SENTINEL_FILE, "the mod folder")

    -- The test has to be a real write. A client's install folder has no Saved
    -- directory and io.open will not make one, which is how a client falls
    -- through to AppData; a rented server's folder can be read-only, which is
    -- how it falls through the other way. Probe under a throwaway name: a
    -- candidate we do not pick must not be left holding an empty progress file,
    -- since the next launch would find it and prefer it.
    local function writable(path)
        local probe = path .. ".probe"
        local f = io.open(probe, "w")
        if not f then return false end
        f:close()
        os.remove(probe)
        return true
    end

    local pick = candidates[#candidates]
    for _, c in ipairs(candidates) do
        if writable(c.progress) then pick = c break end
    end
    PROGRESS_FILE, SENTINEL_FILE = pick.progress, pick.sentinel
    progressLocationNote = string.format("Progress file: %s (%s)", PROGRESS_FILE, pick.why)

    -- Everything we did not pick stays READABLE, in the same order. That is what
    -- carries an existing player across the move: a 2.1.7-and-later install
    -- upgrading, and a server whose clears are currently stranded in the service
    -- account's AppData, both find their old file and migrate it on first load.
    for _, c in ipairs(candidates) do
        if c ~= pick then
            PROGRESS_FALLBACKS[#PROGRESS_FALLBACKS + 1] = c.progress
            SENTINEL_FALLBACKS[#SENTINEL_FALLBACKS + 1] = c.sentinel
        end
    end
end

-- The staging file for the write-then-swap in saveAllProgress. Also the recovery
-- source when a crash lands between the remove and the rename.
local PROGRESS_TMP_FILE = PROGRESS_FILE .. ".tmp"

------- crash sentinel -------
-- A native crash in our Lua appears in crash logs as anonymous UE4SS frames,
-- naming nothing. So risky sections write their name to sentinel.txt and clear it
-- on the way out: a leftover crumb on the next launch names the section that died,
-- and a clean file says the crash was not in these paths. Only rare events are
-- wrapped - never the per-tick XP path.

-- Sections can nest (the base sweep runs enforceCap, which can hit a controller
-- sweep), so keep a stack: clear pops back to the enclosing section instead of
-- wiping the file while the outer section is still running.
local sentinelStack = {}

local function sentinelWrite()
    local f = io.open(SENTINEL_FILE, "w")
    if not f then return end
    local top = sentinelStack[#sentinelStack]
    if top then f:write(top) end
    f:close()
end

local function sentinelEnter(what)
    sentinelStack[#sentinelStack + 1] = what
    sentinelWrite()
end

local function sentinelClear()
    sentinelStack[#sentinelStack] = nil
    sentinelWrite()
end

-- refine the CURRENT section's crumb (e.g. add the boss id once known)
-- without unbalancing the enter/clear pairing
local function sentinelReplace(what)
    if #sentinelStack == 0 then return end
    sentinelStack[#sentinelStack] = what
    sentinelWrite()
end

local function sentinelCheckStartup()
    local path = SENTINEL_FILE
    local f = io.open(path, "r")
    -- On the first launch after the file moves, a crash recorded by the previous
    -- version is still at the old location - read it once, wherever it landed,
    -- so it is not lost.
    if not f then
        for _, alt in ipairs(SENTINEL_FALLBACKS) do
            f = io.open(alt, "r")
            if f then path = alt break end
        end
    end
    if not f then return end
    local last = f:read("*a")
    f:close()
    if path ~= SENTINEL_FILE then os.remove(path) end
    if last and last ~= "" then
        print(string.format(
            "[%s] WARNING: the previous session ended while %s was executing '%s'. " ..
            "If the game crashed, %s may be the cause - please include this line in a bug report.\n",
            MOD, MOD, last, MOD))
    end
    sentinelClear()
end

-- gymIds: a tower matches if the dying boss's GetCharacterID() equals any of
-- them. Each boss has a base id and a "_2" rematch; both credit the same tower.
-- Community id tables were wrong - these come from the game's own data.
-- bossType: the MP fallback hook's enum. Unknown for towers 6-9, and that hook
-- does not fire on a host, so nil is fine.
-- id: the gate's stable name, and the only thing written to the progress file.
-- Positions cannot be persisted - gate 4 is Marcus normally and Bellanoir in hard
-- mode - so a saved index would change meaning the moment HardMode is toggled.
local TOWERS = {
    { id = "T1", bossType = 2, gymIds = { "GYM_ElecPanda",        "GYM_ElecPanda_2"        }, cap = Config.Tower1_Cap, name = "Zoe & Grizzbolt"     },
    { id = "T2", bossType = 1, gymIds = { "GYM_LilyQueen",        "GYM_LilyQueen_2"        }, cap = Config.Tower2_Cap, name = "Lily & Lyleen"       },
    { id = "T3", bossType = 3, gymIds = { "GYM_ThunderDragonMan", "GYM_ThunderDragonMan_2" }, cap = Config.Tower3_Cap, name = "Axel & Orserk"       },
    { id = "T4", bossType = 5, gymIds = { "GYM_Horus",            "GYM_Horus_2"            }, cap = Config.Tower4_Cap, name = "Marcus & Faleris"    },
    { id = "T5", bossType = 4, gymIds = { "GYM_BlackGriffon",     "GYM_BlackGriffon_2"     }, cap = Config.Tower5_Cap, name = "Victor & Shadowbeak" },
    { id = "T6", gymIds = { "GYM_MoonQueen",         "GYM_MoonQueen_2"         }, cap = Config.Tower6_Cap, name = "Saya & Selyne"       },
    { id = "T7", gymIds = { "GYM_SnowTigerBeastman", "GYM_SnowTigerBeastman_2" }, cap = Config.Tower7_Cap, name = "Bjorn & Bastigor"    },
    { id = "T8", gymIds = { "GYM_BlueSkyDragon",     "GYM_BlueSkyDragon_2"     }, cap = Config.Tower8_Cap, name = "Auri & Shaolong"     },
    { id = "T9", gymIds = { "GYM_WorldTreeDragon",   "GYM_WorldTreeDragon_2"   }, cap = Config.Tower9_Cap, name = "Zenara & Astralym"   },
}

-- raidIds: the boss's CharacterID, read from the game rather than a wiki - the
-- public tables disagree with it on three of these. The "_2" ultra variants alias
-- to the same gate. Match EXACTLY, never by "RAID_" prefix: the same fight spawns
-- an add and Moon Lord's separately killable head and hands.
local RAIDS = {
    R1 = { raidIds = { "RAID_NightLady"                                     }, name = "Bellanoir",         level = 35 },
    R2 = { raidIds = { "RAID_NightLady_Dark",       "RAID_NightLady_Dark_2" }, name = "Bellanoir Libero",  level = 45 },
    R3 = { raidIds = { "RAID_YakushimaBoss002",     "RAID_YakushimaBoss002_2" }, name = "Moon Lord",       level = 50 },
    R4 = { raidIds = { "RAID_KingBahamut_Dragon",   "RAID_KingBahamut_Dragon_2" }, name = "Blazamut Ryu",  level = 55 },
    R5 = { raidIds = { "RAID_DarkMechaDragon",      "RAID_DarkMechaDragon_2" }, name = "Xenolord",         level = 65 },
    R6 = { raidIds = { "RAID_LegendDeer",           "RAID_LegendDeer_2"      }, name = "Hartalis",         level = 70 },
}

-- The hard-mode ladder: the same nine towers with the six raids interleaved,
-- ordered so every gate is attempted with headroom over its own level. Built
-- from the tables above so a tower's ids and bossType are never duplicated.
local function towerById(id)
    for _, t in ipairs(TOWERS) do
        if t.id == id then return t end
    end
end

local function hardGate(id, cap)
    local raid = RAIDS[id]
    if raid then
        return { id = id, raidIds = raid.raidIds, cap = cap, name = raid.name }
    end
    local t = towerById(id)
    return { id = id, bossType = t.bossType, gymIds = t.gymIds, cap = cap, name = t.name }
end

local HARD_LADDER = {
    hardGate("T1", Config.Hard1_Cap),   hardGate("T2", Config.Hard2_Cap),
    hardGate("T3", Config.Hard3_Cap),   hardGate("R1", Config.Hard4_Cap),
    hardGate("T4", Config.Hard5_Cap),   hardGate("R2", Config.Hard6_Cap),
    hardGate("T5", Config.Hard7_Cap),   hardGate("R3", Config.Hard8_Cap),
    hardGate("T6", Config.Hard9_Cap),   hardGate("R4", Config.Hard10_Cap),
    hardGate("T7", Config.Hard11_Cap),  hardGate("R5", Config.Hard12_Cap),
    hardGate("T8", Config.Hard13_Cap),  hardGate("R6", Config.Hard14_Cap),
    hardGate("T9", Config.Hard15_Cap),
}

-- Everything downstream walks LADDER, never TOWERS, so normal and hard mode are
-- the same code path with a different table.
local LADDER = (Config.HardMode == true) and HARD_LADDER or TOWERS

local BOSS_TO_GATE = {}   -- CharacterID -> ladder index, towers and raids alike
local LADDER_HAS = {}     -- gate id -> true, for the ACTIVE ladder only
for i, gate in ipairs(LADDER) do
    LADDER_HAS[gate.id] = true
    for _, id in ipairs(gate.gymIds or gate.raidIds or {}) do
        BOSS_TO_GATE[id] = i
    end
end

-- Gate ids a record carries that the active ladder has no position for. In
-- normal mode that is every raid gate, so without this, running with HardMode
-- off for one session would quietly erase six raid clears on the next save.
-- Unrecognised ids from a future version ride along the same way.
local carriedGates = {}
local ppCarriedGates = {}

local function splitCarried(ids)
    local carried = {}
    for id in pairs(ids or {}) do
        if not LADDER_HAS[id] then carried[id] = true end
    end
    return carried
end

-- "tower" is wrong the moment a raid gate can be the thing you just cleared, and
-- these strings end up in bug reports. GATE_WORD keeps every message honest
-- without branching at each call site.
local GATE_WORD  = Config.HardMode and "gate" or "tower"
local GATE_WORDS = Config.HardMode and "gates" or "towers"

local defeated = {}
local levelCap = LADDER[1].cap
local initialized = false
local capNotified = {}
local bossJustKilled = false
local frozenExp = {}
local progressLoaded = false

-- rested XP (see the section further down): banked per progress key, spent back
-- on later gains. Declared here because the save points below reference them.
local restPool = {}      -- progress key -> banked XP
local restDirty = false  -- set on change, cleared by a flush
local lastExp = {}       -- character address -> last Exp seen, for gain detection

-- Session running totals, for the F9 cross-check only. If the game's own
-- "XP to next level" disagrees with ours by exactly restPaidSession, then the
-- UI is reading a number our writes never reached.
local restPaidSession = 0
local restBankedSession = 0

local function log(msg)
    print(string.format("[%s] %s\n", MOD, msg))
end

local function dbg(msg)
    if Config.Debug then log(msg) end
end

local function fmtGuid(g)
    if g == nil then return nil end
    local ok, str = pcall(function()
        return string.format("%s-%s-%s-%s", tostring(g.A), tostring(g.B), tostring(g.C), tostring(g.D))
    end)
    return ok and str or nil
end

-- pulls the IndividualParameter off a controller, nil if anything in the chain is
-- missing. IsValid-gate EVERY step: right after world join / repossession the pawn
-- or component can be mid-construction or mid-teardown, and dereferencing a stale
-- object is a native access violation pcall can't catch (see the v2.1.2 crash).
local function getParamFromController(controller)
    local ok, param = pcall(function()
        if not (controller and controller:IsValid()) then return end
        local pawn = controller:GetControlPalCharacter()
        if not (pawn and pawn:IsValid()) then return end
        local comp = pawn:GetCharacterParameterComponent()
        if not (comp and comp:IsValid()) then return end
        return comp:GetIndividualParameter()
    end)
    if ok and param and param:IsValid() then return param end
    return nil
end

------- notifications -------

-- Palworld 1.0 rewrote PalPlayerController:SendLog_ToClient to take a localization
-- key (EPalLocalizeTextCategory + FName TextId), so it can no longer display an
-- arbitrary runtime string. PalUtility's SendSystemAnnounce / SendSystemToPlayerChat
-- take a raw FString instead, so we route notifications through those.
local palUtilCache = nil
local function getPalUtility()
    if palUtilCache and palUtilCache:IsValid() then return palUtilCache end
    palUtilCache = StaticFindObject("/Script/Pal.Default__PalUtility")
    return palUtilCache
end

local function worldContext()
    return FindFirstOf("PalPlayerController")
end

-- global system announce (world events: cap raised, all cleared)
local function notifyAll(text)
    if not Config.EnableNotifications then return end
    local ok, err = pcall(function()
        getPalUtility():SendSystemAnnounce(worldContext(), text)
    end)
    if not ok then dbg("notifyAll: SendSystemAnnounce failed: " .. tostring(err)) end
end

-- targeted chat to one player (per-player events); safe from TArray reflection crashes
local function notifyController(controller, text)
    if not Config.EnableNotifications then return end
    if not controller or not controller:IsValid() then return end
    pcall(function()
        local chatSub = FindFirstOf("PalChatSubsystem")
        if chatSub and chatSub:IsValid() then
            chatSub:SendSystemChatMessage(controller, FText(text))
            return
        end
        local palUtil = getPalUtility()
        local world = worldContext()
        if palUtil and palUtil:IsValid() and world and world:IsValid() then
            palUtil:SendSystemAnnounce(world, FText(text))
        end
    end)
end

-- ServerAcknowledgePossession fires on every repossession (mount/dismount,
-- respawn, fast travel), not just on join - send the status line only the
-- first time we see each player, or the chat gets spammed.
local statusNotified = {}
local function notifyStatusOnce(controller, text)
    if not controller or not controller:IsValid() then return end
    local key = fmtGuid(controller:GetPlayerUId())
    if not key then
        local ok, addr = pcall(function() return controller:GetAddress() end)
        key = ok and addr or nil
    end
    if key then
        if statusNotified[key] then return end
        statusNotified[key] = true
    end
    notifyController(controller, text)
end

local function findControllerForParamInner(paramAddr)
    local ok, controllers = pcall(FindAllOf, "PalPlayerController")
    if not ok or not controllers then return nil end
    for _, c in ipairs(controllers) do
        local p = getParamFromController(c)
        if p then
            local okA, a = pcall(function() return p:GetAddress() end)
            if okA and a == paramAddr then return c end
        end
    end
    return nil
end

-- sentinel-wrapped: this sweep walks every controller's pawn chain, the most
-- stale-deref-prone thing we do (rare: cache misses and first cap notice only)
local function findControllerForParam(paramAddr)
    sentinelEnter("controller sweep (findControllerForParam)")
    local ok, c = pcall(findControllerForParamInner, paramAddr)
    sentinelClear()
    return ok and c or nil
end

-- Mounting a pal REPOSSESSES the controller onto the ridden pal (mount-probe,
-- 2026-07-14): the player pawn's GetController() and GetCachedPlayerState()
-- both come back invalid mid-ride, so any identity lookup routed through the
-- possession chain fails for a mounted player. PalUtility.GetPlayerUIDByActor
-- resolves by actor instead and works while mounted (live-confirmed).
-- All-zero guid = the lookup failed (not a player actor).
local function uidByActor(actor)
    local ok, uid = pcall(function()
        if not (actor and actor:IsValid()) then return nil end
        return fmtGuid(getPalUtility():GetPlayerUIDByActor(actor))
    end)
    if not ok or not uid or uid == "0-0-0-0" then return nil end
    return uid
end

-- On a LOCAL HOST the two uid APIs disagree about the same player: the
-- controller's GetPlayerUId returns the fixed host guid, GetPlayerUIDByActor the
-- save-data uid. Left alone, one player's progress splits across both. The
-- controller uid is the root identity, the by-actor uid is registered as an alias
-- at load, and every path maps through canonUid first.
local uidAlias = {}

-- all-zero = "not populated yet" (GetPlayerUId right after join), never a
-- valid identity: loading or crediting it forks the player's progress
local function realUid(uid)
    if not uid or uid == "0-0-0-0" then return nil end
    return uid
end

local function canonUid(uid)
    if not uid then return nil end
    return uidAlias[uid] or uid
end

-- controller lookup that survives mounting: GetPlayerUId lives on the
-- controller itself, so matching by uid works no matter what it possesses
local function findControllerByUidInner(uidStr)
    local ok, controllers = pcall(FindAllOf, "PalPlayerController")
    if not ok or not controllers then return nil end
    for _, c in ipairs(controllers) do
        local okU, u = pcall(function()
            if not (c and c:IsValid()) then return nil end
            return fmtGuid(c:GetPlayerUId())
        end)
        -- canonUid on BOTH sides: callers pass canonical uids, and on a local
        -- host the controller's raw uid may be an alias of the canonical one
        if okU and u and canonUid(u) == canonUid(uidStr) then return c end
    end
    return nil
end

local function findControllerByUid(uidStr)
    if not uidStr then return nil end
    sentinelEnter("controller sweep (findControllerByUid)")
    local ok, c = pcall(findControllerByUidInner, uidStr)
    sentinelClear()
    return ok and c or nil
end

------- cap logic -------

local function recomputeCap()
    for i, tower in ipairs(LADDER) do
        if not defeated[i] then
            levelCap = tower.cap
            dbg(string.format("Cap: %d (next %s: %s)", levelCap, GATE_WORD, tower.name))
            return
        end
    end
    levelCap = math.huge
    dbg("All " .. GATE_WORDS .. " cleared - no cap")
end

local function getPlayerLevel()
    local ok, controller = pcall(FindFirstOf, "PalPlayerController")
    if not ok or not controller or not controller:IsValid() then return nil end
    local param = getParamFromController(controller)
    if not param then return nil end
    local ok2, level = pcall(function() return param:GetLevel() end)
    return ok2 and level or nil
end

-- players have an empty or "None" CharacterID, pals have a real one
local function isPlayerCharacter(individualParam)
    if not individualParam or not individualParam:IsValid() then return false end
    local ok, charID = pcall(function()
        return individualParam:GetCharacterID():ToString()
    end)
    if not ok or not charID then return false end
    return charID == "" or charID == "None" or charID == "Player" or string.find(charID, "Player", 1, true) ~= nil
end

------- world identity -------
-- SelectedWorldSaveDirectoryName has the save GUID. Can be briefly empty
-- in MP right after load, so we retry in onPossession. Dedicated servers
-- sometimes never populate it - "default_world" fallback is fine since
-- they only host one world anyway.

local worldIdCache = nil

local function getWorldId()
    return worldIdCache or "default_world"
end

local function readWorldId()
    -- Two sources, GameState first (probe 2026-07-16): GameStateInGame's
    -- replicated WorldSaveDirectoryName is live from world start INCLUDING
    -- world-creation sessions, where GameInstance's SelectedWorldSaveDirectoryName
    -- (set only by the world-select menu) stays empty until a relog - that gap
    -- was the default_world cross-save leak. GI kept as fallback for any moment
    -- the GameState isn't up yet.
    local ok, id = pcall(function()
        local gs = FindFirstOf("PalGameStateInGame")
        if gs and gs:IsValid() then
            local s = gs.WorldSaveDirectoryName:ToString()
            -- "None" is a REAL directory name here, not "unset": stock dedicated
            -- servers ship DedicatedServerName=None and save the world under
            -- SaveGames/0/None (the field is an FString - unset reads "", never
            -- "None"). Rejecting it stranded every such server on 'default_world'
            -- with the heal poll re-arming forever (found 2026-07-22).
            if s and s ~= "" then return s end
        end
        local gi = FindFirstOf("PalGameInstance") or FindFirstOf("GameInstance")
        local s = gi and gi.SelectedWorldSaveDirectoryName:ToString() or nil
        -- menu-populated fallback: KEEP the "None" guard here - unset can read
        -- as "None" on this path, and no client save dir is actually named None
        if s and s ~= "" and s ~= "None" then return s end
        return nil
    end)
    if not ok or not id then return nil end
    id = id:gsub("[^%w_]", "")
    if id == "" then return nil end
    return id
end

------- progress save/load -------

-- A record is "<key>=<count>" plus optional " name=value" fields. Anything
-- unrecognised is ignored, so older and hand-edited files stay readable.
--
-- The count alone cannot express hard-mode progress, whose gates are cleared out
-- of order; " gates=" carries the actual set by stable id. The count stays first
-- and still means towers, so older versions read these files unchanged.
--
-- Returns counts, rested-XP pools and gate sets, keyed the same way.
local function readProgressFrom(path)
    local worlds, pools, gateSets = {}, {}, {}
    local file = io.open(path, "r")
    if not file then return nil end
    for line in file:lines() do
        line = line:gsub("^%s+", ""):gsub("%s+$", "")
        if line ~= "" and line:sub(1, 1) ~= "#" then
            -- the remainder must be empty or start with whitespace, so "3.9"
            -- stays garbage rather than being truncated to a 3
            local key, count, rest = line:match("^(.-)=(%d+)(.*)$")
            if key and count and (rest == "" or rest:match("^%s")) then
                worlds[key] = tonumber(count)
                local pool = rest and rest:match("pool=(%d+)")
                if pool then pools[key] = tonumber(pool) end
                local gates = rest and rest:match("gates=([%w_,]+)")
                if gates then
                    local set = {}
                    for id in gates:gmatch("[^,]+") do set[id] = true end
                    gateSets[key] = set
                end
            end
        end
    end
    file:close()
    return worlds, pools, gateSets
end

-- Canonical serialisation order, so a rewritten file does not reshuffle its own
-- gate lists. Unknown ids are kept and appended rather than dropped - a record
-- written by a future version has to survive a round trip through this one.
local GATE_ORDER = { "T1", "T2", "T3", "T4", "T5", "T6", "T7", "T8", "T9",
                     "R1", "R2", "R3", "R4", "R5", "R6" }

local function serializeGates(set)
    local seen, out = {}, {}
    for _, id in ipairs(GATE_ORDER) do
        if set[id] then out[#out + 1] = id ; seen[id] = true end
    end
    local extra = {}
    for id in pairs(set) do
        if not seen[id] then extra[#extra + 1] = id end
    end
    table.sort(extra)
    for _, id in ipairs(extra) do out[#out + 1] = id end
    return table.concat(out, ",")
end

-- True when the set is exactly the first `count` towers, which is what the
-- count already says. Normal-mode records stay byte-identical to before.
local function gatesMatchCount(set, count)
    local n = 0
    for _, id in ipairs(GATE_ORDER) do
        if set[id] then n = n + 1 end
    end
    if n ~= count then return false end
    for i = 1, count do
        if not set["T" .. i] then return false end
    end
    return true
end

local function writeProgressTo(path, worlds, pools, gateSets)
    local file = io.open(path, "w")
    if not file then return false end
    file:write("# LevelLock progress - <worldId>=<towersCleared>\n")
    for key, count in pairs(worlds) do
        local line = string.format("%s=%d", key, count)
        local pool = pools and pools[key]
        -- each field is only written when there is something to carry, so an
        -- ordinary file looks exactly as it always has
        if pool and pool > 0 then
            line = line .. string.format(" pool=%d", pool)
        end
        local set = gateSets and gateSets[key]
        if set and not gatesMatchCount(set, count) then
            local gates = serializeGates(set)
            if gates ~= "" then line = line .. " gates=" .. gates end
        end
        file:write(line .. "\n")
    end
    file:close()
    return true
end

-- falls back to every location we did not pick - the pre-2.1.7 in-folder file,
-- and AppData for a server that has just moved off it - so an upgrade keeps its
-- clears even before the next write lands
local function loadAllProgress()
    local worlds, pools, gates = readProgressFrom(PROGRESS_FILE)
    if worlds then return worlds, pools, gates end

    -- No live file, but a staging one: the game died inside the swap below,
    -- after the old file was removed and before the new one was renamed into
    -- place. The staging file holds the complete last write, so adopt it rather
    -- than starting every world from zero - and put it back immediately, since
    -- a world that loads without ever saving would otherwise leave the only
    -- copy sitting at a path nothing else looks at.
    worlds, pools, gates = readProgressFrom(PROGRESS_TMP_FILE)
    if worlds then
        log("Recovered progress from an interrupted write")
        if writeProgressTo(PROGRESS_FILE, worlds, pools, gates) then
            os.remove(PROGRESS_TMP_FILE)
        end
        return worlds, pools, gates
    end

    for _, alt in ipairs(PROGRESS_FALLBACKS) do
        worlds, pools, gates = readProgressFrom(alt)
        if worlds then return worlds, pools, gates end
    end
    return {}, {}, {}
end

-- Every world's clears live in this one file, so a truncating write is a bad
-- trade: opening the real file with "w" empties it instantly, and a crash a
-- moment later loses every save's progress rather than one. Write the new copy
-- beside it and swap, which narrows the window where nothing complete exists on
-- disk down to two syscalls. Lua on Windows cannot rename onto an existing
-- file, hence remove-then-rename.
local function saveAllProgress(worlds, pools, gateSets)
    if not writeProgressTo(PROGRESS_TMP_FILE, worlds, pools, gateSets) then
        log("ERROR: could not write progress file")
        return
    end
    os.remove(PROGRESS_FILE)
    if not os.rename(PROGRESS_TMP_FILE, PROGRESS_FILE) then
        -- The swap failed (file locked, permissions, a stray reader). Writing in
        -- place is what every version before this did, so it is no worse - and
        -- losing the data entirely because the rename failed would be.
        if not writeProgressTo(PROGRESS_FILE, worlds, pools, gateSets) then
            log("ERROR: could not write progress file")
            return
        end
        os.remove(PROGRESS_TMP_FILE)
    end

    -- A client and a dedicated server running under the same Windows account
    -- resolve to the same path and can overwrite each other. Read back what
    -- actually landed; if a record of ours is missing or wrong, someone else
    -- wrote between our swap and this read. Merge rather than clobber in turn:
    -- their file may hold worlds we have never seen, and ours holds the ones
    -- they just dropped. One extra write, no lock file, no retry loop.
    local onDisk, onDiskPools, onDiskGates = readProgressFrom(PROGRESS_FILE)
    if not onDisk then return end
    for key, count in pairs(worlds) do
        if onDisk[key] ~= count then
            for k, v in pairs(worlds) do onDisk[k] = v end
            for k, v in pairs(pools or {}) do onDiskPools[k] = v end
            for k, v in pairs(gateSets or {}) do onDiskGates[k] = v end
            log("Progress file changed underneath us - merged and rewrote")
            writeProgressTo(PROGRESS_FILE, onDisk, onDiskPools, onDiskGates)
            return
        end
    end
end

-- One-time copy of a file left at a location we no longer write to. The old file
-- is left alone as a backup - it costs nothing, and a server admin who has just
-- watched their progress move wants to see the old copy still sitting there.
local function migrateProgress()
    if readProgressFrom(PROGRESS_FILE) then return end
    for _, alt in ipairs(PROGRESS_FALLBACKS) do
        -- pass everything through: a pre-2.1.7 file has no pools or gates, but a
        -- partial write here is how the flush bug above started
        local old, oldPools, oldGates = readProgressFrom(alt)
        if old then
            saveAllProgress(old, oldPools, oldGates)
            log(string.format("migrated progress from %s to %s", alt, PROGRESS_FILE))
            return
        end
    end
end

-- counts from gate 1 up, stops at first gap. This is the cap's own measure:
-- a gate cleared out of order banks until the gap before it is filled.
local function clearedCount()
    local n = 0
    for i = 1, #LADDER do
        if defeated[i] then n = n + 1 else break end
    end
    return n
end

-- ladder positions -> stable ids, and back. These two are the only places that
-- know a gate has a position at all; everything persisted is by id.
local function idsFrom(indexSet, carried)
    local ids = {}
    for id in pairs(carried or {}) do ids[id] = true end
    for i, gate in ipairs(LADDER) do
        if indexSet[i] then ids[gate.id] = true end
    end
    return ids
end

local function indexSetFrom(ids)
    local set = {}
    for i, gate in ipairs(LADDER) do
        if ids[gate.id] then set[i] = true end
    end
    return set
end

-- The count field is still the towers, cleared in order, for every reader that
-- predates gate sets - including this mod running in normal mode.
local function towerCountFrom(ids)
    local n = 0
    for i = 1, #TOWERS do
        if ids[TOWERS[i].id] then n = n + 1 else break end
    end
    return n
end

local function idsFromCount(count)
    local ids = {}
    for i = 1, math.min(count, #TOWERS) do ids[TOWERS[i].id] = true end
    return ids
end

-- A record's gate set is authoritative when present; a record that has only a
-- count is a pre-hard-mode one, and means "the first N towers".
local function idsForRecord(gateSets, key, count)
    local ids = gateSets and gateSets[key]
    if ids then return ids end
    return idsFromCount(count or 0)
end

local function saveCurrentProgress()
    local worlds, pools, gates = loadAllProgress()
    local key = getWorldId()
    local ids = idsFrom(defeated, carriedGates)
    worlds[key] = towerCountFrom(ids)
    gates[key] = ids
    for k, v in pairs(restPool) do pools[k] = v end
    restDirty = false
    saveAllProgress(worlds, pools, gates)
    dbg(string.format("Saved progress: %d/%d gates for world %s",
        clearedCount(), #LADDER, key))
end

-- Takes either form: a gate set when the record had one, or a bare count from a
-- pre-hard-mode record. Both end up as ladder positions for the active mode,
-- which is what makes toggling HardMode a remap of the same history.
local function applyClearedCount(count, ids)
    carriedGates = splitCarried(ids)
    defeated = indexSetFrom(ids or idsFromCount(count))
end

------- per-player progression -------

local playerDefeated = {}
local paramUidCache = {}

local function getUidSweep(addr)
    local ok, controllers = pcall(FindAllOf, "PalPlayerController")
    if ok and controllers then
        for _, c in ipairs(controllers) do
            local p = getParamFromController(c)
            if p then
                local okA, a = pcall(function() return p:GetAddress() end)
                if okA and a == addr then
                    local uid = canonUid(realUid(fmtGuid(c:GetPlayerUId())))
                    if uid then
                        paramUidCache[addr] = uid
                        return uid
                    end
                    break  -- controller matched but uid not populated: try by-actor
                end
            end
        end
    end

    -- A MOUNTED player is invisible to the controller sweep: the controller
    -- possesses the ridden pal, so no controller's pawn param matches the
    -- player's. Match against the player pawns directly and resolve the uid
    -- by actor - otherwise a mounted player's XP enforcement silently pauses
    -- on every cache miss (ppLoadPlayer wipes the cache on each repossession).
    local okP, pawns = pcall(FindAllOf, "PalPlayerCharacter")
    if not okP or not pawns then return nil end
    for _, pawn in ipairs(pawns) do
        local okA, a = pcall(function()
            if not (pawn and pawn:IsValid()) then return nil end
            local comp = pawn:GetCharacterParameterComponent()
            if not (comp and comp:IsValid()) then return nil end
            local p = comp:GetIndividualParameter()
            if not (p and p:IsValid()) then return nil end
            return p:GetAddress()
        end)
        if okA and a == addr then
            local uid = canonUid(uidByActor(pawn))
            if uid then paramUidCache[addr] = uid end
            return uid
        end
    end
    return nil
end

local function getUidForParam(selfObj)
    local okK, addr = pcall(function() return selfObj:GetAddress() end)
    if not okK then return nil end
    -- cache hit is the per-tick hot path: no file I/O here
    if paramUidCache[addr] then return paramUidCache[addr] end

    -- cache miss = rare controller sweep; sentinel it (stale-deref-prone)
    sentinelEnter("controller sweep (getUidForParam)")
    local ok, uid = pcall(getUidSweep, addr)
    sentinelClear()
    return ok and uid or nil
end

local function playerCount(uid)
    local set = playerDefeated[uid]
    if not set then return 0 end
    local n = 0
    for i = 1, #LADDER do
        if set[i] then n = n + 1 else break end
    end
    return n
end

local function savePlayerProgress(uid)
    local worlds, pools, gates = loadAllProgress()
    local key = getWorldId() .. "|" .. uid
    local ids = idsFrom(playerDefeated[uid] or {}, ppCarriedGates[uid])
    worlds[key] = towerCountFrom(ids)
    gates[key] = ids
    for k, v in pairs(restPool) do pools[k] = v end
    restDirty = false
    saveAllProgress(worlds, pools, gates)
    dbg(string.format("pp: saved %s -> %d/%d gates", uid, playerCount(uid), #LADDER))
end

-- Load a (canonical) uid's record from file if not already in memory. Reads
-- the canonical key AND any alias keys mapping to it, takes the max: heals
-- progress files already split across a player's identities by <= v2.1.4.
-- Progress only ever grows, so max is always the player's true count.
local function ppEnsureLoaded(uid)
    if playerDefeated[uid] then return end
    local worlds, _, gates = loadAllProgress()
    -- world "None" also reads default_world keys: <= v2.1.5 rejected the
    -- literal "None" save-dir name (stock dedicated servers), so records
    -- landed under default_world - merge them forward like alias keys
    local wids = { getWorldId() }
    if wids[1] == "None" then wids[2] = "default_world" end

    -- The old rule was "take the highest count". With gates the generalisation
    -- is a union, which is the same thing for a tower prefix and the right thing
    -- for a hard-mode set: progress only ever grows, and two split identities
    -- may each hold gates the other does not.
    local found, ids = false, {}
    local function absorb(key)
        local c = worlds[key]
        if c == nil then return end
        found = true
        for id in pairs(idsForRecord(gates, key, c)) do ids[id] = true end
    end
    for _, wid in ipairs(wids) do
        absorb(wid .. "|" .. uid)
        for alias, root in pairs(uidAlias) do
            if root == uid and alias ~= uid then absorb(wid .. "|" .. alias) end
        end
    end

    if not found then ids = idsFromCount(Config.TowersAlreadyCleared or 0) end
    ppCarriedGates[uid] = splitCarried(ids)
    playerDefeated[uid] = indexSetFrom(ids)
end

local function ppStatusText(controller)
    local uid = canonUid(realUid(fmtGuid(controller:GetPlayerUId())))
    local n = uid and playerCount(uid) or 0
    if n >= #LADDER then
        return "Level Lock active. All " .. GATE_WORDS .. " cleared - no cap."
    end
    return string.format("Level Lock active. Cap: %d (defeat %s to raise).",
        LADDER[n + 1].cap, LADDER[n + 1].name)
end

local PP_LOAD_RETRY_MS = 2000

local function ppLoadPlayer(controller, retries)
    -- repossession swaps the controlled pawn, so param-address -> uid mappings
    -- go stale; always rebuild the cache even when the player is already loaded
    paramUidCache = {}
    local uid = realUid(fmtGuid(controller:GetPlayerUId()))
    if not uid then
        -- GetPlayerUId isn't populated yet (join burst). Do NOT register the
        -- zero guid as a player (v2.1.4 bug: "player 0-0-0-0 active" with a
        -- fresh 0-tower record shadowing the real one) - retry until it is.
        retries = retries == nil and 10 or retries
        if retries > 0 then
            ExecuteWithDelay(PP_LOAD_RETRY_MS, function()
                pcall(function()
                    if controller and controller:IsValid() then
                        ppLoadPlayer(controller, retries - 1)
                    end
                end)
            end)
        else
            log("WARNING: a player's uid never resolved - their progress is not " ..
                "loaded and their cap is NOT enforced this session")
        end
        return
    end

    -- register the by-actor identity as an alias of the controller identity
    -- (unresolvable while mounted/pawnless - fine, a later load retries it)
    local okA, aliasUid = pcall(function()
        local pawn = controller:GetControlPalCharacter()
        if pawn and pawn:IsValid() then return uidByActor(pawn) end
    end)
    if okA and aliasUid and aliasUid ~= uid then
        uidAlias[aliasUid] = uid
    end

    -- don't clobber in-memory credit when already loaded (out-of-order clears
    -- aren't representable in the sequential-count progress file) and don't
    -- re-read/re-log on every mount/dismount/respawn
    if not playerDefeated[uid] then
        ppEnsureLoaded(uid)
        log(string.format("pp: player %s active - %d/%d %s cleared", uid, playerCount(uid), #LADDER, GATE_WORDS))
    end
    progressLoaded = true
    -- send the status line only after the record is loaded: sending at join
    -- time reported "cap = tower 1" to players with real progress
    notifyStatusOnce(controller, ppStatusText(controller))
end

-- A base camp is guild-owned (base pals have no individual owner), so a shared
-- base pal's cap comes from Config.BaseCapPolicy across all tracked members.
-- Returns a cap, or nil for "no cap".
local function resolveBaseCap()
    local policy = Config.BaseCapPolicy or "highest"
    if policy == "off" then return nil end

    local best
    for uid in pairs(playerDefeated) do
        local n = playerCount(uid)
        if best == nil then best = n
        elseif policy == "lowest" then best = math.min(best, n)
        else best = math.max(best, n) end
    end
    if best == nil or best >= #LADDER then return nil end
    return LADDER[best + 1].cap
end

------- xp clamp -------
-- GetTotalExp(level, isPlayer) = cumulative exp to BE that level. At the cap we
-- hold Exp at the cap level's entry value (deterministic, no captured state).
-- Over-cap characters freeze in place, never reduced: lowering Exp wouldn't
-- refresh the sticky Level, so the UI would desync.

local expDbCache = nil
local function getExpDatabase()
    if expDbCache and expDbCache:IsValid() then return expDbCache end
    expDbCache = nil
    pcall(function()
        local db = FindFirstOf("PalExpDatabase")
        if db and db:IsValid() then expDbCache = db end
    end)
    if not expDbCache then
        pcall(function()
            local util = StaticFindObject("/Script/Pal.Default__PalUtility")
            local db = util:GetExpDatabase(FindFirstOf("PalPlayerController"))
            if db and db:IsValid() then expDbCache = db end
        end)
    end
    return expDbCache
end

local entryExpMemo = {}  -- "level|isPlayer" -> total exp (the table is static at runtime)
local function entryExpForLevel(level, isPlayer)
    local mk = level .. "|" .. tostring(isPlayer)
    if entryExpMemo[mk] ~= nil then return entryExpMemo[mk] end
    local db = getExpDatabase()
    if not db then return nil end
    local ok, v = pcall(function() return db:GetTotalExp(level, isPlayer) end)
    if ok and v then entryExpMemo[mk] = v end
    return entryExpMemo[mk]
end

-- Clamp selfObj's Exp for the given cap (a level). Returns the character's level
-- (or nil). Never lowers a level: at-cap characters hold at the level's entry exp
-- (deterministic); over-cap characters freeze in place (captured, never reduced).
------- rested XP -------
-- XP destroyed at the cap is banked and paid back as a top-up once below it.
-- Accrual is 1:1 and the payout only sets the drain rate, so the bank can never
-- return more than the cap took. Pools are per progress record, which is why they
-- ride in the progress file.

local function restEnabled()
    return Config.RestedXp == true
end

local function restPayout()
    local pct = tonumber(Config.RestXpPayout) or 100
    if pct < 10 then return 10 end
    if pct > 200 then return 200 end
    return pct
end

-- Players only. Party and base pals are deliberately out of scope: the pool is a
-- player-progression feature, and per-pal pools would need a key per pal.
local function restKeyFor(selfObj)
    if not Config.PerPlayerProgress then return getWorldId() end
    local uid = getUidForParam(selfObj)
    if not uid then return nil end
    return getWorldId() .. "|" .. uid
end

local function restBank(selfObj, amount)
    if not restEnabled() or amount <= 0 then return end
    local key = restKeyFor(selfObj)
    if not key then return end
    restPool[key] = (restPool[key] or 0) + amount
    restDirty = true
    restBankedSession = restBankedSession + amount
    dbg(string.format("rested: banked %d (pool %d)", amount, restPool[key]))
end

-- Called on every enforcement pass for a below-cap player. Detects a gain by
-- comparing against the last Exp seen for this character, then tops it up from
-- the pool. The top-up is itself written to Exp, which re-triggers the XP hooks -
-- harmless, because enforceCap's re-entrancy guard bails, and lastExp is updated
-- to the post-bonus value so the bonus is never mistaken for a fresh gain.
local function restSpend(selfObj, sp, addr, cap, isPlayer)
    local exp = sp.Exp
    local prev = lastExp[addr]
    lastExp[addr] = exp
    if not restEnabled() or prev == nil then return end

    -- Below the cap nothing of ours lowers Exp, so a drop means someone else
    -- wrote over us - most likely a payout being reverted by the game's own
    -- value. Worth a line, because the pool would drain for nothing.
    if exp < prev then
        dbg(string.format("rested: exp fell %d -> %d below cap (a write was overwritten)", prev, exp))
        return
    end
    if exp <= prev then return end

    local key = restKeyFor(selfObj)
    if not key then return end
    local pool = restPool[key] or 0
    if pool <= 0 then return end

    local bonus = math.floor((exp - prev) * restPayout() / 100)
    if bonus <= 0 then return end
    if bonus > pool then bonus = pool end

    -- never let a bonus push past the cap: that XP would only be clamped away
    -- again, and with accrual on it would land straight back in the pool
    local entry = entryExpForLevel(cap, isPlayer)
    if entry then
        local room = entry - exp
        if room <= 0 then return end
        if bonus > room then bonus = room end
    end

    -- Read the write back rather than trusting it: a property write that returns
    -- cleanly and does nothing is the standard failure on this build, and a
    -- payout that does not land drains the pool while the player gains nothing.
    sp.Exp = exp + bonus
    local after = sp.Exp
    lastExp[addr] = after

    if after ~= exp + bonus then
        dbg(string.format("rested: WRITE REJECTED - wanted %d, read back %d - keeping the %d in the pool",
            exp + bonus, after, bonus))
        return
    end

    restPool[key] = pool - bonus
    restDirty = true
    restPaidSession = restPaidSession + bonus
    -- Spelled out end to end: where you started, what the game gave you, what the
    -- bank added on top, where you ended. The game's award is already in Exp by
    -- the time this runs, so the first number is pre-kill and the last is final.
    dbg(string.format("rested: paid out %d (exp %d +%d game +%d rested -> %d, pool %d)",
        bonus, prev, exp - prev, bonus, after, restPool[key]))
end

local function clampToCap(selfObj, cap, isPlayer, source)
    local okL, level = pcall(function() return selfObj:GetLevel() end)
    if not okL or not level then return nil end
    local key = selfObj:GetAddress()

    local sp = selfObj.SaveParameter

    -- Transmigrator Pals are exempt from all level caps (Unlimited level cap!)
    if not isPlayer and sp then
        local isTransmigrator = false
        pcall(function()
            if sp.PassiveSkillList then
                for _, s in ipairs(sp.PassiveSkillList) do
                    local str = tostring(s)
                    if str:find("Transmigrator") then isTransmigrator = true break end
                end
            end
        end)
        if isTransmigrator then
            return level
        end
    end
        frozenExp[key] = nil
        -- below the cap is where the bank pays out
        if isPlayer and sp then restSpend(selfObj, sp, key, cap, isPlayer) end
        return level
    end

    if not sp then return level end

    -- AT OR OVER CAP: enforce cap strictly!
    local entry = entryExpForLevel(cap, isPlayer)
    if entry then
        frozenExp[key] = nil
        if sp.Exp > entry then
            -- bank excess EXP
            if isPlayer then restBank(selfObj, sp.Exp - entry) end
            sp.Exp = entry
        end
        if level > cap then
            pcall(function()
                if sp.Level ~= nil and sp.Level > cap then
                    sp.Level = cap
                end
                if selfObj.SetLevel then
                    selfObj:SetLevel(cap)
                end
            end)
            level = cap
        end
        lastExp[key] = sp.Exp
        return level
    end

    -- exp table unavailable fallback: freeze in place
    if frozenExp[key] == nil then
        frozenExp[key] = sp.Exp
        dbg(string.format("[%s] froze in place at %d (level %d, cap %d)", source, frozenExp[key], level, cap))
    end
    if sp.Exp > frozenExp[key] then
        if isPlayer then restBank(selfObj, sp.Exp - frozenExp[key]) end
        sp.Exp = frozenExp[key]
    end
    lastExp[key] = sp.Exp
    return level
end

local function ppEnforce(selfObj, source)
    -- Resolve which cap applies:
    --   player    -> their own tower progress
    --   base pal  -> shared base, resolved by Config.BaseCapPolicy
    --   party pal -> owner's tower progress (SaveParameter.OwnerPlayerUId)
    local cap, n, uid
    if source == "base" and not isPlayerCharacter(selfObj) then
        cap = resolveBaseCap()
    else
        if isPlayerCharacter(selfObj) then
            uid = getUidForParam(selfObj)  -- already canonical (the sweep maps it)
        else
            local ok, owner = pcall(function() return selfObj.SaveParameter.OwnerPlayerUId end)
            if ok then uid = canonUid(realUid(fmtGuid(owner))) end
        end
        if not uid then return end

        -- Attempt immediate load if unseeded
        if not playerDefeated[uid] then
            pcall(function() ppEnsureLoaded(uid) end)
        end

        if playerDefeated[uid] then
            n = playerCount(uid)
            if n < #LADDER then cap = LADDER[n + 1].cap end
        else
            -- Safety baseline: enforce first tower cap while record initializes
            cap = LADDER[1].cap
            n = 0
        end
    end
    if not cap then return end  -- all cleared / policy "off" / unresolved

    local isP = isPlayerCharacter(selfObj)
    local level = clampToCap(selfObj, cap, isP, source)

    if isP and n and n < #LADDER and level and level >= cap then
        local key = selfObj:GetAddress()
        if not capNotified[key] then
            capNotified[key] = true
            -- by-uid, not by-param: the param->controller sweep can't see a
            -- mounted player (their controller possesses the ridden pal)
            local c = findControllerByUid(uid)
            if c then
                notifyController(c, string.format(
                    "You've reached the level cap (%d). Defeat %s to continue leveling.",
                    cap, LADDER[n + 1].name))
            end
        end
    end
end

------- xp enforcement -------

local function enforceCapInner(selfObj, source)
    if not progressLoaded then return end
    if bossJustKilled then return end
    if not selfObj or not selfObj:IsValid() then return end

    -- Pal locking is two opt-in flags; which applies depends on how we got here:
    --   source "base" = base-roster sweep  -> Config.LockBasePals
    --   source "tick"/"rep" = XP hooks (party/combat XP) -> Config.LockPartyPals
    -- Players are always capped.
    if not isPlayerCharacter(selfObj) then
        if source == "base" then
            if not Config.LockBasePals then return end
        elseif not Config.LockPartyPals then
            return
        end
    end

    if Config.PerPlayerProgress then return ppEnforce(selfObj, source) end

    if levelCap == math.huge then return end

    local isP = isPlayerCharacter(selfObj)
    local level = clampToCap(selfObj, levelCap, isP, source)

    if isP and level and level >= levelCap then
        local key = selfObj:GetAddress()
        if not capNotified[key] then
            capNotified[key] = true
            local nextTower = nil
            for i, t in ipairs(LADDER) do
                if not defeated[i] then nextTower = t break end
            end
            if nextTower then
                local msg = string.format("You've reached the level cap (%d). Defeat %s to continue leveling.", levelCap, nextTower.name)
                local controller = findControllerForParam(key)
                if controller then
                    notifyController(controller, msg)
                else
                    notifyAll(msg)
                end
            end
        end
    end
end

-- Re-entrancy guard. clampToCap WRITES SaveParameter.Exp, and that write can
-- re-trigger the very hooks (OnRep_SaveParameter / NaturalUpdateSaveParameter)
-- that call us - re-entering our Lua from inside a Blueprint ProcessInternal frame.
-- That self-re-entry is what the reporter's crash stack shows (two nested Lua VM
-- blocks ending in a stale-UObject deref). Bail immediately if we're already
-- enforcing on this thread; the pcall guarantees the flag resets even on error.
local enforcing = false
local function enforceCap(selfObj, source)
    if enforcing then return end
    enforcing = true
    local ok, err = pcall(enforceCapInner, selfObj, source)
    enforcing = false
    if not ok then dbg("enforceCap error: " .. tostring(err)) end
end

local function onSaveParameterUpdate(self)
    local selfObj = self
    pcall(function() selfObj = self:get() end)
    enforceCap(selfObj, "tick")
end

local function onRepSaveParameter(self)
    local selfObj = self
    pcall(function() selfObj = self:get() end)
    enforceCap(selfObj, "rep")
end

------- default_world credit carryover -------
-- A world-creation session keys progress to default_world until the real id
-- resolves. These credits carry into the real world when it does; without that, a
-- reload would drop them and re-lock a cap the player earned. Assumes the session
-- continues into the SAME world - a cross-world relog would misattribute, which is
-- rare against a guaranteed re-lock otherwise.

local defaultWorldCredits = { shared = {}, pp = {} }

local function carryDefaultWorldCredits()
    for idx in pairs(defaultWorldCredits.shared) do
        if not defeated[idx] then
            defeated[idx] = true
            log(string.format("Carried tower credit earned under default_world: %s", LADDER[idx].name))
        end
    end
    if next(defaultWorldCredits.shared) then
        recomputeCap()
        saveCurrentProgress()
    end

    for uid, set in pairs(defaultWorldCredits.pp) do
        -- player not re-seeded yet (e.g. disconnected before the heal): load
        -- their real-world count from file so the union can't clobber progress
        ppEnsureLoaded(uid)
        local any = false
        for idx in pairs(set) do
            if not playerDefeated[uid][idx] then
                playerDefeated[uid][idx] = true
                any = true
                log(string.format("Carried tower credit earned under default_world: %s (player %s)", LADDER[idx].name, uid))
            end
        end
        if any then savePlayerProgress(uid) end
    end

    defaultWorldCredits = { shared = {}, pp = {} }
end

------- sphere tier lock -------
-- Stops a player using a sphere their level has not unlocked: the throw bounces
-- with the game's own "too weak" message.
--
-- Vetoing the capture does not work on this build - marking the target, writing
-- the judge's out array and re-marking across the wobble all land near 40%,
-- because the outcome is fixed before any of them fire. Changing the SPHERE does
-- work: SetCaptureLevelForSphere carries capture power as a writable parameter.
--
-- A large negative rather than a low positive, because bonuses are ADDITIVE on top
-- of this value - sneak +2, Statue of Power +7.5 - and together they exceed a
-- basic sphere's whole power of 7. Negatives keep their sign here; that was
-- tested, not assumed.
local DENY_POWER = -100

-- Nothing on the ladder reads above 64, so a value far outside that range is not
-- a capture power and the slot holding it is not the slot we mean. Reading the
-- wrong parameter costs nothing; writing one is how a mod breaks something
-- quietly, so an unrecognisable number is logged and left alone. The bound is
-- above Ancient rather than at it, to leave room for a modded tier.
local MAX_PLAUSIBLE_POWER = 100

-- Capture power per sphere and the level that unlocks it, read out of the game
-- rather than from published tables - those are wrong about Exotic and omit the
-- Sol Sphere entirely. Sorted by unlock level. Not exposed in config: these are
-- measurements of the game, not preferences.
local SPHERE_TIERS = {
    { level = 2,  power = 7,  name = "Pal Sphere"       },
    { level = 14, power = 14, name = "Mega Sphere"      },
    { level = 20, power = 20, name = "Giga Sphere"      },
    { level = 27, power = 27, name = "Hyper Sphere"     },
    { level = 35, power = 33, name = "Ultra Sphere"     },
    { level = 44, power = 38, name = "Legendary Sphere" },
    { level = 51, power = 44, name = "Ultimate Sphere"  },
    { level = 58, power = 50, name = "Exotic Sphere"    },
    { level = 67, power = 58, name = "Sol Sphere"       },
    { level = 74, power = 64, name = "Ancient Sphere"   },
}

-- The strongest sphere this level has unlocked. Below the first tier a player
-- still gets the basic sphere: the alternative is denying every throw at level 1,
-- which would read as the mod being broken.
local function allowedSpherePower(level)
    local power = SPHERE_TIERS[1].power
    for _, tier in ipairs(SPHERE_TIERS) do
        if level >= tier.level then power = tier.power end
    end
    return power
end

-- Which sphere a thrown power belongs to, for the message. Exact match only: an
-- unrecognised power (a modded sphere, or a tier added by a patch) returns nil and
-- is reported without a name rather than guessed at.
local function sphereTierByPower(power)
    for _, tier in ipairs(SPHERE_TIERS) do
        if tier.power == power then return tier end
    end
end

-- The two ends of the same call. The plain function runs in the process that
-- threw the sphere; the RPC is what that process sends to the host. So a
-- dedicated server sees only the RPC - the plain call happened inside the
-- client, where the mod is not installed - and hooking only the plain name is a
-- lock that registers cleanly and never runs.
--
-- Both are hooked rather than choosing by role. A listen host fires both for its
-- own throw, where the second pass reads the power the first already clamped and
-- returns at the "no valid tier" guard, so no dedupe is needed.
local HOOK_SPHERE_LOCAL  = "/Script/Pal.PalPlayerController:SetCaptureLevelForSphere"
local HOOK_SPHERE_SERVER = "/Script/Pal.PalPlayerController:SetCaptureLevelForSphere_ToServer"

-- Rate-limited, because a player can throw several spheres in a couple of seconds
-- and the game already shows its own "too weak" bounce. This only explains WHY.
-- Keyed per player: with the server hook live this runs for everyone connected,
-- and a single shared timestamp would let one player's denial swallow the notice
-- another player is owed.
local lastSphereNotice = {}
local SPHERE_NOTICE_GAP = 10

-- Every exit logs under Debug, so a bug report answers which end fired, for whom,
-- with what power, and whether the write took. A throw is not a hot path - a
-- player throws a handful and then walks - so this costs nothing worth saving.
local function onSphereThrowInner(source, self, ...)
    if not Config.LockSphereTier then return end

    local controller = self
    pcall(function() controller = self:get() end)
    local param = getParamFromController(controller)
    if not param then
        dbg(string.format("sphere lock: %s fired, no parameter off the controller - throw allowed", source))
        return
    end
    local okL, level = pcall(function() return param:GetLevel() end)
    if not okL or not level then
        dbg(string.format("sphere lock: %s fired, could not read level - throw allowed", source))
        return
    end

    -- Walk the arguments rather than indexing them, and walk them BACKWARD. The
    -- two ends of this call do not have the same arity:
    --
    --   local call  (SphereBody, Level)
    --   RPC         (<int>, SphereBody, Level)
    --
    -- The RPC's leading integer is measured, not guessed - it reads 256 on every
    -- throw - and it is not the capture power. Taking the first number therefore
    -- clamps the right value on one end and that integer on the other, which
    -- reads back cleanly and changes no catch. Level is last on both ends, which
    -- is what the header declares.
    --
    -- The leading integer stays unidentified. It needs no name to be left alone.
    local slot, power
    for i = select("#", ...), 1, -1 do
        local arg = select(i, ...)
        local raw = arg
        pcall(function() raw = arg:get() end)
        if type(raw) == "number" then
            slot, power = arg, raw
            break
        end
    end
    if not slot or not power then
        -- the argument count is logged because a signature change shows up here first
        dbg(string.format("sphere lock: %s fired at level %d, no numeric parameter among %d args - throw allowed",
            source, level, select("#", ...)))
        return
    end

    -- 1 is what the game returns for "no valid sphere tier", including for indices
    -- past the end of the enum. Never treat it as a very weak sphere.
    if power <= 1 then
        dbg(string.format("sphere lock: %s fired at level %d with power %d (no valid tier) - throw allowed",
            source, level, power))
        return
    end

    local allowed = allowedSpherePower(level)
    if power <= allowed then
        dbg(string.format("sphere lock: %s allowed power %d at level %d (allowance %d)",
            source, power, level, allowed))
        return
    end

    -- read it, log it, but never write a slot we cannot recognise
    if power > MAX_PLAUSIBLE_POWER then
        dbg(string.format("sphere lock: %s read %d at level %d - not a capture power, not writing",
            source, power, level))
        return
    end

    local okW = pcall(function() slot:set(DENY_POWER) end)
    local after
    pcall(function() after = slot:get() end)
    if not okW or after ~= DENY_POWER then
        -- a write that returns cleanly and does nothing is this build's signature
        -- failure, so say so rather than reporting a block that did not happen
        dbg(string.format("sphere lock: %s write REJECTED (wanted %d, read back %s) - throw allowed",
            source, DENY_POWER, tostring(after)))
        return
    end

    local tier = sphereTierByPower(power)
    dbg(string.format("sphere lock: %s denied %s (power %d) at level %d - allowed power is %d, slot now %s",
        source, tier and tier.name or "an unknown sphere", power, level, allowed, tostring(after)))

    -- Deliberately not gated on the tier resolving. A sphere we cannot name is
    -- still a sphere we just blocked, and a throw that fails for no stated reason
    -- reads as the mod being broken.
    if Config.EnableNotifications then
        local now = os.time()
        -- one bucket per player, with a shared fallback when the uid is not
        -- readable - a missing uid must not mean an unthrottled message
        local okU, uid = pcall(function() return fmtGuid(controller:GetPlayerUId()) end)
        local key = (okU and canonUid(realUid(uid))) or "*"
        if now - (lastSphereNotice[key] or 0) >= SPHERE_NOTICE_GAP then
            lastSphereNotice[key] = now
            -- deferred out of the hook frame, like every other notification here
            ExecuteWithDelay(250, function()
                pcall(function()
                    -- Has to mention the catch chance. The game computes that
                    -- preview BEFORE this hook runs, so it shows the sphere's true
                    -- power and can happily promise 100% on a throw we are about
                    -- to block - which reads as the game lying rather than as a
                    -- rule being enforced. Live report 2026-07-28.
                    local text
                    if tier then
                        text = string.format(
                            "%s needs level %d. Level Lock blocked the throw - the catch chance shown does not apply.",
                            tier.name, tier.level)
                    else
                        -- no name and no unlock level to quote, so say the one
                        -- thing that is certainly true and still actionable
                        text = "Level Lock blocked that throw - your level has not unlocked this sphere. The catch chance shown does not apply."
                    end
                    notifyController(controller, text)
                end)
            end)
        end
    end
end

-- `source` is a log label, not a role decision - the handler behaves identically
-- either way.
local function onSphereThrow(source, self, ...)
    sentinelEnter("sphere tier check")
    local ok, err = pcall(onSphereThrowInner, source, self, ...)
    sentinelClear()
    if not ok then dbg("onSphereThrow error: " .. tostring(err)) end
end

------- boss kill detection -------

-- Shared-mode tower credit, callable from BOTH detection paths (onCharacterDeath
-- and onTowerBossExp). defeated[towerIdx] dedupes, so double-firing is harmless.
local function creditSharedTower(towerIdx, via)
    if defeated[towerIdx] then return end

    local tower = LADDER[towerIdx]
    log(string.format("%s: %s (via %s)", Config.HardMode and "Gate cleared" or "Tower boss defeated", tower.name, via))

    local oldCap = levelCap
    bossJustKilled = true
    defeated[towerIdx] = true
    if getWorldId() == "default_world" then defaultWorldCredits.shared[towerIdx] = true end
    recomputeCap()
    capNotified = {}
    frozenExp = {}
    saveCurrentProgress()

    ExecuteWithDelay(10000, function()
        bossJustKilled = false
        dbg("Boss kill grace period ended")
    end)

    if levelCap == oldCap then
        dbg("Boss defeated out of order - cap unchanged")
    elseif levelCap == math.huge then
        notifyAll(Config.HardMode and "All gates cleared! No level cap." or "All tower bosses defeated! No level cap.")
    else
        local nextTower = nil
        for i, t in ipairs(LADDER) do
            if not defeated[i] then nextTower = t break end
        end
        notifyAll(string.format("Level cap raised to %d. Next: %s.", levelCap, nextTower.name))
    end
end

-- Credit for a gate that may be a raid. AddExp_forPlayerParty_TowerBoss does not
-- fire for raids, so per-player mode has no participant list for one. Crediting
-- nobody would softlock a per-player world at its first raid gate, so a raid
-- credits every loaded player - which over-credits anyone idling in a base.
-- FindInRangePlayers is the basis for a precise version, untested for credit.
local function creditGate(idx, via)
    if not Config.PerPlayerProgress then
        creditSharedTower(idx, via)
        return
    end

    local gate = LADDER[idx]
    local credited = {}   -- { uid, before } - the count before crediting
    for uid, set in pairs(playerDefeated) do
        if not set[idx] then
            local before = playerCount(uid)
            set[idx] = true
            if getWorldId() == "default_world" then
                defaultWorldCredits.pp[uid] = defaultWorldCredits.pp[uid] or {}
                defaultWorldCredits.pp[uid][idx] = true
            end
            savePlayerProgress(uid)
            credited[#credited + 1] = { uid = uid, before = before }
            log(string.format(
                "pp: credited %s for %s (via %s, all loaded players - raids have no participant list)",
                uid, gate.name, via))
        end
    end
    if #credited == 0 then return end

    frozenExp = {}
    capNotified = {}
    bossJustKilled = true
    ExecuteWithDelay(10000, function() bossJustKilled = false end)

    -- deferred for the same reason as the tower path: notifying inside the
    -- boss's own frame is the re-entrancy that leads to a crash
    ExecuteWithDelay(250, function()
        for _, p in ipairs(credited) do
            pcall(function()
                local n = playerCount(p.uid)
                local text
                if n == p.before then
                    text = string.format(
                        "%s cleared - cap unchanged. Clear the earlier gates to raise it.", gate.name)
                elseif n >= #LADDER then
                    text = "Final gate cleared! No more level cap."
                else
                    text = string.format("Level cap raised to %d.", LADDER[n + 1].cap)
                end
                local c = findControllerByUid(p.uid)
                if c then notifyController(c, text) end
            end)
        end
    end)
end

local function onCharacterDeathInner(self, deadInfo)
    if not progressLoaded then return end
    local selfObj = self
    pcall(function() selfObj = self:get() end)
    if not selfObj or not selfObj:IsValid() then return end

    -- IsValid-gate the whole chain: a dying character can be mid-teardown, so a raw
    -- deref here is a native access violation pcall can't catch (see reporter crash).
    local ok, charID = pcall(function()
        local comp = selfObj.CharacterParameterComponent
        if not (comp and comp:IsValid()) then return end
        local ip = comp:GetIndividualParameter()
        if not (ip and ip:IsValid()) then return end
        return ip:GetCharacterID():ToString()
    end)
    if not ok or not charID then return end
    if not (charID:find("GYM_", 1, true) or charID:find("RAID_", 1, true)) then return end
    -- exact dying-boss CharacterID: the ground truth for which gym-ID scheme the
    -- 1.0 binary emits. Read this with Config.Debug=true to trim the gymIds aliases.
    dbg(string.format("Boss death, CharacterID = %s", charID))

    local towerIdx = BOSS_TO_GATE[charID]
    if not towerIdx then
        dbg(string.format("Boss death, but not a tracked gate: %s", charID))
        return
    end

    if LADDER[towerIdx].raidIds then
        -- a raid seen through the character hook; OnDeadPal is the reliable
        -- path, and creditGate dedupes whichever arrives second
        creditGate(towerIdx, "OnDeadCharacter")
        return
    end

    if Config.PerPlayerProgress then
        -- Per-player credit is handled precisely by onTowerBossExp
        -- (AddExp_forPlayerParty_TowerBoss), which has the exact participant list.
        return
    end

    creditSharedTower(towerIdx, "OnDeadCharacter")
end

-- Raid gates. OnDeadPal is the primary signal and OnDeadCharacter unreliable - it
-- fired for Bellanoir and not for Bellanoir Libero across live raids. Both routes
-- call creditGate, which dedupes, so a double-fire is harmless.
--
-- CallOnEnd_ToAll is deliberately not hooked: it fires on a forfeit as well as a
-- win, and reading its finish-type parameter crashes the game.
local function onRaidBossDeathInner(self, deadInfo)
    if not progressLoaded then return end
    local info = deadInfo
    pcall(function() info = deadInfo:get() end)
    if not info then return end

    -- same IsValid-gated chain as the character hook: a raid boss pawn
    -- mid-teardown is exactly the object that crashes on a raw deref
    local ok, charID = pcall(function()
        local actor = info.SelfActor
        if not (actor and actor:IsValid()) then return end
        local comp = actor.CharacterParameterComponent
        if not (comp and comp:IsValid()) then return end
        local ip = comp:GetIndividualParameter()
        if not (ip and ip:IsValid()) then return end
        return ip:GetCharacterID():ToString()
    end)
    if not ok or not charID then return end
    dbg(string.format("Raid death, CharacterID = %s", charID))

    -- EXACT match only. The same fight spawns RAID_YakushimaBoss001_Green (an
    -- add, not a boss) and Moon Lord's separately killable _Head / _Hand_Left /
    -- _Hand_Right parts, each of which fires this hook. A prefix match would
    -- credit the gate for destroying a hand.
    local idx = BOSS_TO_GATE[charID]
    if not idx or not LADDER[idx].raidIds then
        dbg(string.format("Raid death, but not a tracked raid gate: %s", charID))
        return
    end
    creditGate(idx, "OnDeadPal")
end

local function onRaidBossDeath(self, deadInfo)
    sentinelEnter("raid boss death check")
    local ok, err = pcall(onRaidBossDeathInner, self, deadInfo)
    sentinelClear()
    if not ok then dbg("onRaidBossDeath error: " .. tostring(err)) end
end

-- sentinel-wrapped: fires for EVERY character death; the risky part is reading
-- the dying character's parameter chain while it may be mid-teardown
local function onCharacterDeath(self, deadInfo)
    sentinelEnter("character death check")
    local ok, err = pcall(onCharacterDeathInner, self, deadInfo)
    sentinelClear()
    if not ok then dbg("onCharacterDeath error: " .. tostring(err)) end
end

-- MP fallback. Doesn't actually fire on the host in current Palworld
-- but doesn't hurt to have it wired up.
local function onBossBattleSuccess(self, LocalPlayer, BossType)
    if Config.PerPlayerProgress then return end

    local bossType = BossType:get()
    for i, tower in ipairs(LADDER) do
        if tower.bossType == bossType and not defeated[i] then
            log(string.format("Tower boss defeated (MP): %s", tower.name))
            local oldCap = levelCap
            defeated[i] = true
            recomputeCap()
            capNotified = {}
            frozenExp = {}
            saveCurrentProgress()
            if levelCap ~= oldCap then
                notifyAll(string.format("Level cap raised to %d.", levelCap))
            end
            return
        end
    end
end

------- base-camp / catch-all sweep -------
-- The XP hooks (NaturalUpdateSaveParameter / OnRep_SaveParameter) catch players
-- and party pals, but base-camp WORK xp is applied through a different path the
-- hooks never see (OnFinishWorkInServer across many work-object types). A periodic
-- sweep re-runs enforceCap over every OWNED pal so base workers - and anything
-- else the hooks miss - get capped too. Base xp trickles in (~1 per tick), so the
-- interval is imperceptible. Reuses enforceCap, so shared + per-player both work.

-- The pool changes on the per-tick XP path, which must never touch the disk, so
-- changes are flushed on a slow timer instead. Tower clears already save, but
-- they are rare - without this a session's banked XP would evaporate on exit,
-- which is most of the feature's value gone.
local REST_FLUSH_MS = 30000

local function restFlushTick()
    if restDirty and progressLoaded then
        -- Read the gate sets back and hand them straight to the write. This
        -- flush only cares about pools, but saveAllProgress rewrites the WHOLE
        -- file, and omitting the third argument means every " gates=" field on
        -- every record is dropped. That erased four live raid clears in testing
        -- 30 seconds after the pool changed: hard-mode progress deleted by a
        -- rested XP timer that has nothing to do with it.
        local worlds, pools, gates = loadAllProgress()
        for k, v in pairs(restPool) do pools[k] = v end
        restDirty = false
        saveAllProgress(worlds, pools, gates)
        dbg("rested: flushed pools to disk")
    end
    ExecuteWithDelay(REST_FLUSH_MS, function() pcall(restFlushTick) end)
end

local SWEEP_INTERVAL_MS = 5000

-- Base workers don't show up in FindAllOf and don't fire the XP hooks, so walk
-- each camp's roster directly: PalBaseCampModel -> WorkerDirector ->
-- CharacterContainer -> Get(i):GetHandle():TryGetIndividualParameter(). The
-- reschedule is outside the pcall so a bad object can't kill the loop.
local function sweepBaseWorkers()
    sentinelEnter("base worker sweep")
    local okPass = pcall(function()
        if not progressLoaded then return end
        local found, camps = pcall(FindAllOf, "PalBaseCampModel")
        if not found or not camps then return end
        local n = 0
        for _, camp in ipairs(camps) do
            pcall(function()
                if not (camp and camp:IsValid()) then return end
                local container = camp.WorkerDirector and camp.WorkerDirector.CharacterContainer
                if not container then return end
                for i = 0, container:Num() - 1 do
                    local slot = container:Get(i)
                    local handle = slot and slot:GetHandle()
                    local param = handle and handle:TryGetIndividualParameter()
                    if param and param:IsValid() and not isPlayerCharacter(param) then
                        n = n + 1
                        enforceCap(param, "base")
                    end
                end
            end)
        end
        dbg(string.format("[base] swept %d workers", n))
    end)
    if not okPass then dbg("[base] sweep errored") end
    sentinelClear()
    ExecuteWithDelay(SWEEP_INTERVAL_MS, sweepBaseWorkers)
end

------- world load / possession -------

local loadedWorldId = nil

local function statusText()
    for i, t in ipairs(LADDER) do
        if not defeated[i] then
            return string.format("Level Lock active. Cap: %d (defeat %s to raise).", levelCap, t.name)
        end
    end
    return "Level Lock active. All " .. GATE_WORDS .. " cleared - no cap."
end

local function loadProgressForWorld()
    local worldId = getWorldId()
    -- always-on (not dbg): the one line that lets a "wrong cap on this save"
    -- report self-diagnose from UE4SS.log - shows exactly which progress key
    -- this world reads/writes
    log("World ID: " .. worldId)

    local worlds, pools, gates = loadAllProgress()
    local saved = worlds[worldId]
    local savedIds = gates and gates[worldId]
    restPool = {}
    for k, v in pairs(pools or {}) do restPool[k] = v end
    restDirty = false
    if saved == nil and worldId == "None" then
        -- migrate: <= v2.1.5 rejected the literal "None" save-dir name, so a
        -- stock dedicated server's progress was recorded under 'default_world'
        saved = worlds["default_world"]
        savedIds = gates and gates["default_world"]
        if saved ~= nil then
            worlds[worldId] = saved
            if savedIds then gates[worldId] = savedIds end
            saveAllProgress(worlds, pools, gates)
            log(string.format("Migrated shared progress (%d towers) from 'default_world' to world 'None'", saved))
        end
    end

    if saved ~= nil then
        applyClearedCount(saved, savedIds)
        dbg(string.format("Loaded saved progress: %d towers cleared (%d/%d %s on this ladder)", saved, clearedCount(), #LADDER, GATE_WORDS))
    else
        local override = Config.TowersAlreadyCleared or 0
        applyClearedCount(override)
        dbg(string.format("No saved progress - using config override: %d towers", override))
        saveCurrentProgress()
    end

    recomputeCap()
    progressLoaded = true
    log(string.format("Active%s - cap %s, %d/%d %s cleared",
        Config.HardMode and " (HARD MODE)" or "",
        levelCap == math.huge and "none" or tostring(levelCap),
        clearedCount(), #LADDER, Config.HardMode and "gates" or "towers"))
end

-- Everything keyed by character address or player uid is per-world state.
-- UE recycles freed memory, so a stale frozenExp entry from a previous world
-- could clamp the wrong character's Exp - wipe it all when the world changes.
local function resetSessionState()
    frozenExp = {}
    capNotified = {}
    -- the pool is per progress key and the gain tracker is per character address,
    -- both of which belong to the world being left; loadProgressForWorld refills
    -- the pool from the file for the new one
    restPool = {}
    restDirty = false
    lastExp = {}
    paramUidCache = {}
    statusNotified = {}
    playerDefeated = {}
    uidAlias = {}
    -- pause enforcement until the new world's progress is loaded
    -- (loadProgressForWorld / ppLoadPlayer set it back)
    progressLoaded = false
end

-- default_world is a timing artifact on clients too, not only a dedicated-server
-- one: a session's first world load can leave SelectedWorldSaveDirectoryName empty
-- past the retry window, and anything read or written meanwhile lands on the
-- SHARED default_world line. So keep polling after falling back, and swap to the
-- real id like a world switch when it appears.
local WORLD_ID_HEAL_MS = 5000

local function healWorldId()
    if loadedWorldId ~= "default_world" then return end  -- healed, or a real world loaded
    local id = readWorldId()
    if not id then
        ExecuteWithDelay(WORLD_ID_HEAL_MS, function() pcall(healWorldId) end)
        return
    end
    sentinelEnter("world-id heal (default_world -> real id)")
    local ok, err = pcall(function()
        log(string.format("World save ID resolved late: %s - switching progress off 'default_world'", id))
        worldIdCache = id
        loadedWorldId = id
        resetSessionState()
        if Config.PerPlayerProgress then
            -- re-seed every connected player under the real world key (they
            -- were loaded under default_world|uid)
            local okC, controllers = pcall(FindAllOf, "PalPlayerController")
            if okC and controllers then
                for _, c in ipairs(controllers) do
                    pcall(function() if c and c:IsValid() then ppLoadPlayer(c) end end)
                end
            end
        else
            loadProgressForWorld()
        end
        carryDefaultWorldCredits()
    end)
    sentinelClear()
    if not ok then log("ERROR in world-id heal: " .. tostring(err)) end
end

local warnedDefaultWorld = false

local function onPossession(joiningController)
    local attempts = 10

    local function tryResolve()
        local id = readWorldId()
        if not id and attempts > 0 then
            attempts = attempts - 1
            -- re-wrap: ExecuteWithDelay callbacks run outside the hook's pcall
            ExecuteWithDelay(1000, function()
                local ok, err = pcall(tryResolve)
                if not ok then log("ERROR: " .. tostring(err)) end
            end)
            return
        end

        if not id then
            id = "default_world"
            -- once per session: repossessions re-run tryResolve, and on a server
            -- that never populates the field this would fire on every mount/respawn
            if not warnedDefaultWorld then
                warnedDefaultWorld = true
                log("WARNING: could not resolve a world save ID yet - tracking progress under 'default_world' " ..
                    "for now and polling for the real ID. If this machine hosts MULTIPLE worlds under an ID " ..
                    "that never resolves (some dedicated servers), they will SHARE tower progress.")
                -- start the heal poll (once per session; it self-terminates once
                -- loadedWorldId is anything but default_world)
                ExecuteWithDelay(WORLD_ID_HEAL_MS, function() pcall(healWorldId) end)
            end
        end
        worldIdCache = id

        -- the controller was captured up to 13s ago (3s init delay + retries);
        -- a player who disconnected during load leaves it stale, and calling
        -- UFunctions on a stale controller is an uncatchable native crash
        if not (joiningController and joiningController:IsValid()) then return end

        -- sentinel: the join burst is when controllers/pawns churn the most.
        -- pcall so a Lua error still clears the crumb (only a NATIVE crash,
        -- which kills the process, should leave it behind)
        sentinelEnter("possession handling (world load / player join)")
        local okP, errP = pcall(function()
            -- resolving off default_world (relog path; the heal poll may not have
            -- caught it first) must carry credits earned during the default window
            local wasDefault = (loadedWorldId == "default_world")

            if id ~= loadedWorldId then
                loadedWorldId = id
                resetSessionState()
                if Config.PerPlayerProgress then
                    -- shared mode logs this inside loadProgressForWorld; pp
                    -- mode must log it too - it's the one line that lets a
                    -- "wrong cap on this save" report self-diagnose
                    log("World ID: " .. id)
                else
                    loadProgressForWorld()
                end
            end

            if Config.PerPlayerProgress then
                -- ppLoadPlayer sends the status notice itself once the
                -- player's uid resolves and their record is loaded
                ppLoadPlayer(joiningController)
            else
                notifyStatusOnce(joiningController, statusText())
            end

            if wasDefault and id ~= "default_world" then
                carryDefaultWorldCredits()
            end
        end)
        sentinelClear()
        if not okP then log("ERROR: " .. tostring(errP)) end
    end

    tryResolve()
end

------- hooks -------

local function tryHook(path, callback)
    local ok, err = pcall(RegisterHook, path, callback)
    if ok then
        dbg("Hooked: " .. path)
    else
        log("FAILED to hook: " .. path .. " - " .. tostring(err))
    end
end

-- Per-player tower credit. PRE-hook on the boss XP grant: fires before the XP is
-- awarded with the exact participant list (GiftPlayerList) + boss (DeadEnemyHandle),
-- so credit is precise and the cap rises before the XP lands (no grace needed).
-- Shared mode uses onCharacterDeath.
local function onTowerBossExpInner(self, deadHandle, giftList)
    if not progressLoaded then return end

    -- IsValid-gate the dead boss handle: it can already be torn down when the XP
    -- grant fires, and a raw deref is a native crash pcall can't catch.
    local boss
    pcall(function()
        local h = deadHandle:get()
        if not (h and h:IsValid()) then return end
        local ip = h:TryGetIndividualParameter()
        if not (ip and ip:IsValid()) then return end
        boss = ip:GetCharacterID():ToString()
    end)
    if not boss then return end
    local towerIdx = BOSS_TO_GATE[boss]
    if not towerIdx then return end
    -- pre-dedupe, so re-kills of a cleared tower still log: lets a tester verify
    -- this hook fires (e.g. while mounted) without resetting progress
    dbg(string.format("tower-boss XP grant, boss = %s", boss))

    -- refine the crumb now that we know which boss (rare: tracked kills only)
    sentinelReplace("tower credit (boss=" .. boss .. ")")

    if not Config.PerPlayerProgress then
        -- Shared mode: redundant credit path alongside onCharacterDeath. The boss
        -- id comes from deadHandle alone - no player identity needed - and this
        -- hook is live-confirmed to fire on mounted kills, so it catches a clear
        -- even if the death hook's teardown-sensitive param chain bails. As a
        -- PRE-hook it also raises the cap before the boss XP lands.
        creditSharedTower(towerIdx, "TowerBossExp")
        return
    end

    local anyNew = false
    local pending = {}  -- {controller, text} - sent AFTER this hook frame unwinds
    pcall(function()
        giftList:get():ForEach(function(_, elem)
            pcall(function()
                local pc = elem:get()
                if not (pc and pc:IsValid()) then return end
                -- Resolve identity BY ACTOR, not through the controller: a MOUNTED
                -- player's pawn has no valid controller (the controller possesses
                -- the ridden pal), which silently dropped credit for mounted kills
                -- (bug report 2026-07-14, root cause probe-confirmed). The old
                -- controller path stays as fallback for uidByActor misses.
                local uid = uidByActor(pc)
                local controller
                pcall(function()
                    local c = pc:GetController()
                    if c and c:IsValid() then controller = c end
                end)
                if not uid and controller then
                    uid = realUid(fmtGuid(controller:GetPlayerUId()))
                end
                if not uid then
                    dbg("pp: gift player uid unresolved (by-actor AND controller) - skipped")
                    return
                end
                -- canonicalize (by-actor and controller uids differ on a local
                -- host) and pull the file record before crediting: crediting
                -- into a fresh empty record could SAVE a lower count than the
                -- file already holds
                uid = canonUid(uid)
                ppEnsureLoaded(uid)
                if playerDefeated[uid][towerIdx] then return end
                local nBefore = playerCount(uid)
                playerDefeated[uid][towerIdx] = true
                if getWorldId() == "default_world" then
                    defaultWorldCredits.pp[uid] = defaultWorldCredits.pp[uid] or {}
                    defaultWorldCredits.pp[uid][towerIdx] = true
                end
                anyNew = true
                savePlayerProgress(uid)
                local n = playerCount(uid)
                local text
                if n == nBefore then
                    -- out-of-order clear: the sequential count didn't advance
                    text = string.format(
                        "%s cleared - cap unchanged. Clear the earlier towers to raise it.",
                        LADDER[towerIdx].name)
                elseif n >= #LADDER then
                    text = string.format("Final %s cleared! No more level cap.", GATE_WORD)
                else
                    text = string.format("Level cap raised to %d.", LADDER[n + 1].cap)
                end
                pending[#pending + 1] = { controller = controller, uid = uid, text = text }
                log(string.format("pp: credited %s for %s (tower-boss hook)", uid, LADDER[towerIdx].name))
            end)
        end)
    end)

    if anyNew then
        frozenExp = {}
        capNotified = {}
    end

    -- Defer notifications out of this hook frame. SendSystem* are UFunction calls,
    -- and firing them synchronously here runs inside the boss Blueprint's
    -- ProcessInternal frame - the re-entrancy that leads to the crash. Let the
    -- sequence unwind first; notifyController re-checks IsValid before sending.
    -- A mounted killer has no captured controller - look theirs up by uid at
    -- send time (also heals a controller that went stale during the delay).
    if #pending > 0 then
        ExecuteWithDelay(250, function()
            for _, p in ipairs(pending) do
                pcall(function()
                    local c = p.controller
                    if not (c and c:IsValid()) then c = findControllerByUid(p.uid) end
                    if c then
                        notifyController(c, p.text)
                    else
                        dbg("pp: no controller for " .. tostring(p.uid) .. " - notification dropped")
                    end
                end)
            end
        end)
    end
end

-- sentinel-wrapped: the per-player boss credit path the crash report implicated
local function onTowerBossExp(self, deadHandle, giftList)
    sentinelEnter("tower boss XP grant")
    local ok, err = pcall(onTowerBossExpInner, self, deadHandle, giftList)
    sentinelClear()
    if not ok then dbg("onTowerBossExp error: " .. tostring(err)) end
end

local function registerHooks()
    if initialized then return end
    initialized = true

    tryHook("/Script/Pal.PalIndividualCharacterParameter:NaturalUpdateSaveParameter", onSaveParameterUpdate)
    tryHook("/Script/Pal.PalIndividualCharacterParameter:OnRep_SaveParameter", onRepSaveParameter)
    tryHook("/Script/Pal.PalCharacter:OnDeadCharacter", onCharacterDeath)
    tryHook("/Script/Pal.PalRecordTrigger_BossBattle:OnLocalPlayerBossBattleSuccessed", onBossBattleSuccess)
    tryHook("/Script/Pal.PalExpDatabase:AddExp_forPlayerParty_TowerBoss", onTowerBossExp)
    -- Raid gates only exist in hard mode, so in normal mode this is a hook that
    -- can only cost something. PalRaidBossComponent is confirmed to drive the
    -- instanced area raids, which is how raids are actually run.
    if Config.HardMode then
        tryHook("/Script/Pal.PalRaidBossComponent:OnDeadPal", onRaidBossDeath)
    end
    -- Only when the feature is on: these fire on every sphere throw, and an
    -- unnecessary hook on a hot-ish path is a cost with no benefit. Both ends of
    -- the call are registered - see the sphere section for why neither alone
    -- covers single-player, a listen host and a dedicated server together.
    if Config.LockSphereTier then
        tryHook(HOOK_SPHERE_LOCAL, function(self, ...) onSphereThrow("local", self, ...) end)
        tryHook(HOOK_SPHERE_SERVER, function(self, ...) onSphereThrow("server", self, ...) end)
    end

    -- start the base-worker sweep only when base-pal locking is on (guarded by
    -- `initialized`, so a hot reload won't spawn duplicate loops)
    if Config.LockBasePals then
        ExecuteWithDelay(SWEEP_INTERVAL_MS, sweepBaseWorkers)
    end

    -- same guard, same reason: one flush loop per session
    if Config.RestedXp then
        ExecuteWithDelay(REST_FLUSH_MS, function() pcall(restFlushTick) end)
    end

    dbg("Hooks registered")
end

-- The player's Exp as the mod sees it, plus the distance to the next level
-- computed off the game's own exp table. Read this with the character menu open
-- and compare: the game's "to next level" should match "to go" exactly.
local function logExpCrossCheck()
    local ok, controller = pcall(FindFirstOf, "PalPlayerController")
    if not ok or not controller or not controller:IsValid() then return end
    local param = getParamFromController(controller)
    if not param then return end

    local okE, exp = pcall(function() return param.SaveParameter.Exp end)
    local okL, level = pcall(function() return param:GetLevel() end)
    if not okE or not exp or not okL or not level then return end

    local nextEntry = entryExpForLevel(level + 1, true)
    if nextEntry then
        log(string.format("Exp: %d | level %d ends at %d | %d to go | this session: +%d rested, %d banked",
            exp, level, nextEntry, nextEntry - exp, restPaidSession, restBankedSession))
    else
        log(string.format("Exp: %d | exp table unavailable | this session: +%d rested, %d banked",
            exp, restPaidSession, restBankedSession))
    end
end

local function registerDebugKeys()
    if not Config.Debug then return end

    RegisterKeyBind(Key.F9, function()
        local level = getPlayerLevel()
        local cleared = {}
        for i, t in ipairs(LADDER) do
            if defeated[i] then cleared[#cleared + 1] = t.name end
        end
        log(string.format("Level: %s | Cap: %s | Cleared: %s",
            tostring(level),
            levelCap == math.huge and "none" or tostring(levelCap),
            #cleared > 0 and table.concat(cleared, ", ") or "none"
        ))
        pcall(logExpCrossCheck)
    end)

end

------- init -------

local initializedControllers = setmetatable({}, { __mode = "k" })

local cachedHasAuthority = nil
local function hasServerAuthority()
    if cachedHasAuthority ~= nil then return cachedHasAuthority end
    local auth = false
    pcall(function()
        local gm = FindFirstOf("PalGameMode")
        if gm and gm:IsValid() then auth = true end
    end)
    cachedHasAuthority = auth
    return auth
end

RegisterHook("/Script/Engine.PlayerController:ServerAcknowledgePossession",
    function(self, Pawn)
        local controller = self
        pcall(function() controller = self:get() end)
        if not (controller and controller:IsValid()) then return end

        -- If not server authority (multiplayer client), server drives LevelLock; client never touches save files
        if not hasServerAuthority() then
            return
        end

        -- Once a controller is initialized, never re-run possession on mount/dismount
        if initializedControllers[controller] then
            return
        end

        local pawnObj = Pawn and (Pawn.get and Pawn:get() or Pawn)
        if pawnObj and pawnObj.IsA then
            local isPlayerPawn = false
            pcall(function()
                local cls = pawnObj:GetClass():GetFName():ToString()
                if cls:find("^BP_Player_") or cls:find("PalPlayerCharacter") then
                    isPlayerPawn = true
                end
            end)
            if not isPlayerPawn then
                -- Mounting a Pal: controller repossesses the mount, ignore completely!
                return
            end
        end

        initializedControllers[controller] = true

        ExecuteWithDelay(3000, function()
            local ok, err = pcall(function() onPossession(controller) end)
            if not ok then
                log("ERROR: " .. tostring(err))
            end
        end)
    end
)

-- Logged every launch, not just when it changes: "where did my progress go" is
-- the first question a server admin asks, and this is the answer.
log(progressLocationNote)
sentinelCheckStartup()
migrateProgress()
registerHooks()
registerDebugKeys()

log(string.format("v%s loaded. Waiting for world...", VERSION))
