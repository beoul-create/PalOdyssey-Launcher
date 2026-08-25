-- ============================================================================
--  Expedition XP -- pals earn XP from completed expeditions.
--  (No version here on purpose: Info.json is the single source and Darn.version() reads it.
--   A number in this comment goes stale silently, and a header that lied about the version is
--   exactly what made the 2026-07-23 release nearly ship the wrong lineage.)
--
--  Capture is solved (RepInfoArray at State 2 = the full crew, persisted to
--  crews.txt as InstanceId strings). The write kept failing because prior builds
--  HELD the live IndividualId userdata from State 2 until collection (~44 min) --
--  by then it was STALE and GetIndividualHandle resolved nothing.
--
--  v1.1.3: never hold handles. The crew lives in crews.txt as stable InstanceId
--  strings. To pay, walk the containers (FindAllOf PalIndividualCharacterContainer
--  -> slot.Handle -> TryGetIndividualParameter -- the XpProbe-proven write path
--  for boxed pals) and match each pal's OWN InstanceId against the file. Because
--  the crew is in the box after collection, a finished run pays with NO stale
--  refs -- and a run whose crew is already in crews.txt pays at boot.
--
--  palIID(): a container pal's own InstanceId. The accessor wasn't nailed before,
--  so this tries several and logs the winner once. PROVEN LIVE 2026-07-23 on the
--  G-Portal server: a 99-pal DUNGEON_SNOW run captured at State 2, held crew=99
--  across ~60 min of snapshots, and paid want=99 paid=99 with every write
--  reading back verified (51 pals levelled, 48 banked).
--
--  CFG.dryRun (default FALSE = LIVE): set true to log "WOULD GRANT ..." and
--  write NOTHING -- the validation mode used to prove the pay path.
--
--  HOST-AUTHORITATIVE: grants only run on the machine that owns the world
--  (dedicated server, or the local host in single-player/co-op). On a pure
--  multiplayer CLIENT this mod is passive -- subscribe-safe; the server needs
--  its own install (see the Workshop description).
--
--  Design (Mikey): rewards anchor to the LEVEL THE EXPEDITION UNLOCKS AT
--  (the LevelLock tower ladder), with the level-delta nursery curve. Mass
--  expeditions (~100 pals) are the intended use.
--
--  EXP LAWS (verified 2026-07-22): SaveParameter.Exp is CUMULATIVE lifetime.
--  GetTotalExp(L,false) = level L's floor (GetTotalExp(20)=9555 verified);
--  GetNextExp(L,false) = cost of the next level. The game floor-normalizes
--  exp up to the level on save/load and never re-derives levels itself.
--  Grants therefore ADD to the total and walk the level with GetTotalExp --
--  never subtract (the comp-accident bug).
--
--  Rate: base = xpPerAnchorLevel * anchor * underMult (babies leap, mid-levels
--  gain 1-2), with a FLOOR of minPctOfLevel * next-level cost so high-level
--  crews feel every run (flat exp at Lv55 was 0.1% of a level). Over-anchor
--  decays toward zero (~7 levels over = nothing), so pals age out of a tier.
--
--  v1.2.0 -- THE MISSING ANCHORS. CFG.anchors held exactly one id (DUNGEON_SNOW),
--  and no real mission id contains a digit, so the ladder[] parse never fired and
--  EVERY other expedition fell to anchorFallback = 20. At anchor 20 the over-decay
--  zeroes any pal past ~Lv26 -- so Forest/Volcano/Sky/Dark runs granted nothing at
--  all, on this dev's own server included (07-26 and 07-27: DUNGEON_FOREST, crews
--  of 74/83/100, anchor=20 FALLBACK). It read as healthy because grantToParam
--  returned true for a 0-XP pal, so the log said "want=83 paid=83".
--  Reported by Meabh_Wolf, who diagnosed it from the config and supplied the
--  DARKISLAND=68 / SKYISLAND=74 anchors. Fixed three ways: the known ids are in
--  the table; an UNKNOWN id no longer decays anyone to zero (it anchors to the pal
--  and pays the floor) and says so loudly; and the pay log breaks out
--  paid/zero-xp/maxed instead of one flattering number.
--
--  1.4.1 -> THIS BUILD -- THE ANTI-EXPLOIT FIX BECAME THE WORSE BUG.
--  1.4.1 stopped cancelled expeditions paying (a real exploit) by demanding that a
--  mission be SEEN in state 3 (Reward) before it could ever pay. State 3 is a
--  TRANSIENT window, and the only thing that reliably looks inside it is the +1.5s
--  sweep fired by the state-change hook -- which lives on a STREAMED ACTOR that does
--  not exist while nobody is stood at the base. Miss the window and a genuinely
--  completed run took the "canceled" branch: crew dropped, zero XP, and a log line
--  that said "canceled" about an expedition the player had just watched finish.
--  Multiple 1.4.1/1.4.2 reports are exactly this ("My pals are not getting any xp
--  with this latest update. Even when I complete the expedition..."), one with a log
--  showing `state 1 -> 2` and no `2 -> 3` line ever following.
--  The default now flips -- an unobserved run PAYS -- and a cancel has to be PROVED,
--  by the game's own cancel RPC or by the run being too short to have finished. The
--  full reasoning, and what of it is measured vs assumed, is at the sweep.
-- ============================================================================

-- ---------------------------------------------------------------------------
-- SETTINGS. Every run, each pal is granted:
--     xp = max(base, floor) * overMult
--     base  = xpPerAnchorLevel * anchor * underMult   (the main grant)
--     floor = minPctOfLevel * (cost of the pal's next level)  (a minimum)
-- where `anchor` is the level the expedition unlocks at, and the mults bend
-- the grant by how far the pal is under/over that anchor.
--
-- WANT LESS XP OVERALL?  Lower the two rate knobs below (they're the ones to
-- touch): xpPerAnchorLevel affects mostly LOW/MID-level pals; minPctOfLevel is
-- the floor that mostly affects HIGH-level pals (near the anchor, base goes
-- tiny, so the floor is all they get). Turn both down for an across-the-board
-- cut; turn one down to target just that group. Everything below the rate
-- knobs shapes the curve and rarely needs touching.
-- ---------------------------------------------------------------------------
local CFG = {
  enabled = true,          -- master on/off for the whole mod
  dryRun  = false,         -- true = log what WOULD be granted, write nothing (safe test)

  -- SERVER XP RATE. false (default) = expedition XP ignores the world's ExpRate, which is what
  -- this mod has always done: it writes Exp directly and never goes through the game's XP
  -- pipeline, so the server setting has never applied to expedition grants. true = multiply
  -- every grant by the world's ExpRate, so a 0.25x server pays 0.25x for expeditions too.
  -- Left OFF by default because switching it on is a balance change for an existing world, not
  -- a bug fix -- an owner running 0.1x would find expeditions worth a tenth overnight.
  respectServerExpRate = false,

  -- RATE KNOBS -- turn these DOWN for less XP, UP for more:
  xpPerAnchorLevel = 120,  -- base XP per anchor level. Main grant scaler; biggest
                           --   effect on lower-level pals. Higher = more XP.
  minPctOfLevel    = 0.15, -- minimum grant = this fraction of the pal's next-level
                           --   cost (0.15 = 15%). The floor high-level pals live on;
                           --   higher = more XP for them, lower = they crawl.
  -- BANDED WAGES (2026-08-10 -- the surviving payout design; see grantToParam for the
  -- one-night history of its two dead predecessors). An in-band run pays about one level
  -- AT THE DUNGEON'S TIER, every run, forever -- no asymptote, no wall.
  bandPct        = 1.0,    -- pay = this x (cost of one level at the anchor). The main knob:
                           --   1.0 = a level-at-tier per run; 0 = off (old flat lump).
  bandWidth      = 10,     -- the band: full wages from (anchor-bandWidth is where the baby
                           --   bonus stops) to anchor+bandWidth; past the top, nothing --
                           --   move up to the next expedition.
  bandUnderBonus = 1.5,    -- multiplier for pals MORE than bandWidth under the anchor
                           --   (babies being carried learn fastest).

  -- CURVE SHAPE (advanced -- how the grant bends with the level gap; defaults are tuned):
  underBonus = 0.08,       -- bonus per level a pal is UNDER the anchor (babies leap):
                           --   underMult = 1 + min(gap, underCap) * underBonus
  underCap   = 10,         -- cap on that under-anchor bonus (max underMult = 1 + underCap*underBonus)
  overDecay  = 0.15,       -- decay per level a pal is OVER the anchor; ~1/overDecay levels
                           --   over (~7) earns nothing, so pals age out of a tier
  maxLevel   = 80,         -- never push a pal past this level

  -- STRUCTURAL (which level each expedition anchors to -- not a rate knob):
  ladder    = { 15, 30, 45, 50, 55, 62, 68, 74, 80 },  -- the LevelLock tower ladder
  -- Per-mission anchors, keyed by the id the game reports (it shows up in the log
  -- and in missions.txt). Values are rungs of the tower ladder above.
  -- THE RULE (Mikey): each expedition anchors to ITS TOWER, at that tower's cap in the
  -- LevelLock ladder above. Name the tower, not just the number -- a bare number rests on
  -- someone's memory, and taking these literally instead of deriving them is exactly how
  -- Forest shipped at tower 1's cap (15) when it belongs to tower 2 (30).
  anchors   = {
    DUNGEON_FOREST     = 30,  -- tower 2, Lily & Lyleen              (Mikey, 2026-07-27)
    -- CORRECTED 2026-07-30, 45 not 50. This was attributed to "tower 4, Marcus & Faleris" --
    -- but Marcus & Faleris are the DESERT boss (confirmed by Mikey), and the mission export says
    -- Volcano gates on EPalBossType::ElectricBoss, i.e. tower 3. So it anchored one rung too
    -- high, against the mod's own rule. Exactly the Forest bug the v1.2.0 note describes, and it
    -- survived because the tower NAME in the comment was never checked against the boss the game
    -- actually requires.
    DUNGEON_VOLCANO    = 45,  -- tower 3 (ElectricBoss, 144,000)   -- was 50 via a misattribution
    DUNGEON_SNOW       = 55,  -- tower 5, Victor & Shadowbeak (Astral Frost Cavern)
    DUNGEON_DARKISLAND = 68,  -- tower 7, Bjorn & Bastigor (Feybreak) -- Meabh_Wolf, play-tested
    DUNGEON_SKYISLAND  = 74,  -- tower 8, Auri & Shaolong (Sunreach)  -- Meabh_Wolf, play-tested
    -- END-GAME, added 1.3.0 (LordAnorak on Nexus, 2026-07-28). "World tree subterranean city
    -- ruins unlocks after you beat the final story boss" -- so it sits at the TOP of the
    -- ladder, tower 9's cap, not on some rung part-way up. The id is confirmed; the anchor is
    -- derived from the rule, as always.
    DUNGEON_WORLDTREE  = 80,  -- tower 9 cap, post-final-boss          (LordAnorak, id confirmed)
    -- HARD MODE. Unlocked by defeating the HARD-mode bosses, which come after the world tree,
    -- so every hard expedition is end-game content REGARDLESS of which tower it re-skins.
    -- DUNGEON_GRASSHARD is tower 1's hard mode -- and anchoring it to tower 1's cap (15) would
    -- be the Forest bug all over again, only worse: an anchor that low pays nothing at all to
    -- the level-80 pals who are the only ones who can run it. Hard mode anchors to the top.
    DUNGEON_GRASSHARD  = 80,  -- tower 1 HARD                          (LordAnorak, id confirmed)

    -- ============================================================================
    -- COMPLETED FROM THE GAME'S OWN DATA, 2026-07-30.
    --
    -- Source: DT_CharacterTeamMissionDataTable + DT_CharacterTeamMissionChallengeCondition
    -- (FModel JSON, in modding\gamedata). Eighteen missions exist; this table held seven, so
    -- ELEVEN were falling to anchorFallback -- the exact v1.2.0 failure, still live for them.
    --
    -- The export settles the tower ORDER, which is what the rule needs. RecommendedStrength is
    -- strictly ascending across the nine normal missions, and each one's ChallengeCondition names
    -- the tower boss that unlocks it:
    --   Grass 25k/GrassBoss . Forest 56k/ForestBoss . Volcano 144k/ElectricBoss
    --   Desert 209k/DesertBoss . Snow 286k/SnowBoss . Sakurajima 375k/SakurajimaBoss
    --   DarkIsland 476k/VikingBoss . SkyIsland 589k/SorajimaBoss . WorldTree 851k/WorldTreeBoss
    -- Three of those names do not match their dungeon (Volcano is the ELECTRIC tower, DarkIsland
    -- the VIKING one, SkyIsland the SORAJIMA one) -- unguessable, and the reason this needed data.
    DUNGEON_GRASS      = 15,  -- tower 1, Zoe & Grizzbolt          (GrassBoss, 25,000)
    DUNGEON_DESERT     = 50,  -- tower 4, Marcus & Faleris         (DesertBoss, 209,000)
    DUNGEON_SAKURAJIMA = 62,  -- tower 6                           (SakurajimaBoss, 375,000)

    -- HARD MODE: ALL 80, and that is structural rather than a guess. Every hard variant shares
    -- RecommendedStrength 1,600,000, difficulty VeryHard, 7200s, and gates on its tower boss at
    -- Hard difficulty -- so they are one tier, not a ladder, and 80 is the level cap. LordAnorak's
    -- suffix theory is confirmed by the export: every hard id IS the normal id with HARD appended.
    -- Override any of these in the user config if you want them staggered.
    DUNGEON_FORESTHARD     = 80,
    DUNGEON_VOLCANOHARD    = 80,
    DUNGEON_DESERTHARD     = 80,
    DUNGEON_SNOWHARD       = 80,
    DUNGEON_SAKURAJIMAHARD = 80,
    DUNGEON_DARKISLANDHARD = 80,
    DUNGEON_SKYISLANDHARD  = 80,
    DUNGEON_WORLDTREEHARD  = 80,
  },
  -- SUFFIX RULE, not a list of guesses (1.3.0). LordAnorak's theory is that every hard-mode id
  -- is the normal id with HARD appended -- he has DUNGEON_GRASSHARD confirmed and said plainly
  -- he cannot verify the rest yet ("I suspect it would be lol"). Enumerating DUNGEON_VOLCANOHARD,
  -- DUNGEON_SNOWHARD and friends here would be writing guesses into a table whose entire purpose
  -- is to hold facts, and this mod has already shipped one wrong anchor that paid nobody.
  --
  -- So the theory lives as a PATTERN instead: any unknown id ending in HARD anchors to the top
  -- of the ladder. If the theory holds, every hard expedition is rated correctly the day it is
  -- discovered, with no release needed. If it is wrong, the id simply misses the pattern and
  -- takes the unknown-id path, which pays the floor and logs the name -- exactly as today.
  -- Nobody can earn zero either way.
  hardSuffix     = "HARD",
  -- Anchor for a mission id that isn't in the table above. This used to be a flat
  -- 20, which was a silent trap: over-anchor decay zeroed EVERY pal above ~Lv26, so
  -- an unrecognized expedition paid literally nothing and only said so in the log.
  -- Now the fallback also disables the decay (see anchorFor/grantToParam), so an
  -- unknown mission pays the floor instead of nothing. Add the real anchor when the
  -- id turns up in the log; until then nobody silently earns zero.
  anchorFallback = 20,

  -- ---- THE ANTI-CANCEL GUARD (see the sweep for the whole argument) ---------
  -- How long a run we WATCHED START must have been in progress before we are willing to
  -- believe it finished. Below this it is treated as a cancel and earns nothing.
  --
  -- 1200s (20 min) rests on two legs. The datatable leg: DT_CharacterTeamMissionDataTable
  -- gives every normal expedition RequiredSeconds 1800-3600 and every hard one 7200, so 1200
  -- sits under the SHORTEST unscaled run. The observed leg, which is what moved it up from a
  -- timid 300 (Maiq, 2026-08-03): the game scales duration down by team strength through
  -- CalculateRequiredSecondsRateByTeamStrength -- an unknown curve -- and in daily play scaled
  -- runs "don't get any shorter than that". So no genuine completion lands under the guard,
  -- while a cancel has to eat twenty real minutes of expedition time to collect anything --
  -- at which point it is not an exploit, it is slower than doing the expedition.
  --
  -- Why not just under 1800: the scaling curve is real and unmeasured, and denying an honest
  -- fast completion is THE failure this rewrite exists to end. 1200 is the highest value the
  -- in-play observation actually supports.
  --
  -- SINCE 1.5.2 THIS IS THE FALLBACK ONLY: the sweep reads each run's OWN scheduled
  -- duration from the game (already scaled by expedition-timer mods) and guards at 80%
  -- of that; this flat value applies only when that schedule is unreadable. You should
  -- no longer need to lower it for timer mods. 0 disables the fallback guard entirely.
  minInProgressSeconds = 1200,

  -- BOOT STAND-DOWN (1.5.1, the crash-on-load reports: carpesangrea, redcakis, mushyman's
  -- bug #1111303). Loading a save is a streaming window; a FindAllOf walk during it reads
  -- poisoned memory and no pcall catches the AV. The sweep waits until the world has been
  -- v2 (2026-08-08): the wall-clock fallback and the GameState settle timer are GONE --
  -- the gate now waits for the walked populations themselves to hold still (see the
  -- WORLD-SETTLE GATE v2 block). worldQuietSec is how long they must be quiet.
  -- whichever happens FIRST (a belt for installs where even the presence probe misbehaves).
  worldQuietSec    = 10,

  -- ---- LEVEL-EXTENDER SUPPORT (1.3.0) --------------------------------------
  -- Asked for on Nexus by maiqthecurious, who runs a max-level extender. Supporting a
  -- SPECIFIC extender was the wrong shape -- 200 is arbitrary, and the next person wants 1000 --
  -- so this is the general version: the player states their cap and the whole curve moves.
  --
  -- THREE things clamp a modded server today, and all three had to move together:
  --   1. maxLevel (80) -- a hard stop. Every pal at or above it is skipped entirely ("max").
  --   2. the anchors -- an expedition rated 80 pays nothing to a level-140 pal, because...
  --   3. overDecay -- ~1/0.15 = 7 levels past the anchor and the grant is already zero.
  -- Raising only maxLevel would have looked like support and delivered nothing: pals would be
  -- eligible and still earn 0. That is the same silent-zero shape as the pre-1.2.0 anchor bug.
  scaleAnchorsToMaxLevel = false,  -- true = stretch ladder+anchors proportionally to maxLevel.
                                   --   One knob for "I have an extender": set maxLevel and this,
                                   --   and every anchor moves with it, keeping their spacing.
  uncapped   = {},                 -- mission ids that NEVER decay, however far over the anchor
                                   --   a pal is (Mikey's "last expedition pays everyone").
                                   --   e.g. { DUNGEON_WORLDTREE = true }
}

-- WHERE OUR FILES LIVE -- derived from THIS SCRIPT, not from the working directory.
--
-- This used to be the bare relative path "ue4ss/Mods/ExpeditionXP/", which only resolves when the
-- game process happens to be running from the directory above ue4ss/. Reported by Jarol on the
-- Workshop (2026-07-31): every expedition snapshot logged "WARN: cannot write crews", repeating
-- every few seconds for the whole expedition. XP still worked -- that is in memory -- but NOTHING
-- persisted, so a restart mid-expedition would silently lose who was owed, and the log filled up.
--
-- debug.getinfo gives this file's own path, so the mod finds its folder wherever UE4SS was
-- installed and whatever the cwd is. The old relative path is kept as a fallback for any layout
-- where the source path is unavailable.
local SRC_DIR = (debug.getinfo(1, "S").source or ""):gsub("^@", ""):gsub("[^/\\]+$", "")
local BASE     = (SRC_DIR ~= "" and SRC_DIR or "ue4ss/Mods/ExpeditionXP/Scripts/") .. "../"
local LEDGER   = BASE .. "granted.txt"
local MISSIONS = BASE .. "missions.txt"
local CREWS    = BASE .. "crews.txt"

local function log(m) print("[ExpXP] " .. tostring(m) .. "\n") end

-- READ, don't restate. The boot line used to hardcode "v1.1.3" while Info.json said 1.1.4,
-- so the log named a build that did not exist -- the same drift that had DarnUI reporting
-- 1.1.0 two releases late. A version string that describes the wrong build is worse than no
-- version at all: it makes a crash log confidently wrong. ExpeditionXP is a single file with
-- no vendored darn.lua, so it reads its own Info.json directly. "dev" = running from a folder
-- with no Info.json, which is itself worth seeing in the log.
local VERSION = (function()
  local dir = (debug.getinfo(1, "S").source:gsub("^@", ""):gsub("[^/\\]+$", ""))
  local f = io.open(dir .. "../Info.json", "r")
  if not f then return "dev" end
  local s = f:read("*a") or ""
  f:close()
  return s:match('"Version"%s*:%s*"([^"]*)"') or "dev"
end)()
local function safe(f) local ok, v = pcall(f); if ok then return v end end
local function alive(o)
  if o == nil then return false end
  local ok, v = pcall(function() return o:IsValid() end)
  return ok and v == true
end
local function fname(x) local s = safe(function() return x:ToString() end) return s and tostring(s) or tostring(x) end
local function guid(g)
  -- MASK TO 32 BITS (2026-08-10, Maiq's level-1 crew paid nothing). A guid component with
  -- the high bit set can arrive as a NEGATIVE integer from one engine read path and as a
  -- positive one from another; %08X on a negative Lua integer prints SIXTEEN digits
  -- ("FFFFFFFF95464ADF"), so the same expedition tracked under two different keys: the
  -- snapshot poll knew "FFFFFFFF95464ADF-...", the completion hook announced
  -- "95464ADF-..." -- no match, completion "unobserved", the 23:58 DUNGEON run judged
  -- CANCELED with zero XP. Masking makes every read path print the same 8 digits.
  local ok, s = pcall(function()
    return string.format("%08X-%08X-%08X-%08X",
      g.A & 0xFFFFFFFF, g.B & 0xFFFFFFFF, g.C & 0xFFFFFFFF, g.D & 0xFFFFFFFF)
  end)
  return ok and s or nil
end

-- ---- USER CONFIG -----------------------------------------------------------
-- ExpeditionXP is server-side and Steam-only: no DarnMenu, no settings page, no shared/ kit.
-- So the config is a plain Lua file the server owner edits, loaded over the defaults above.
--
-- WHY A SEPARATE FILE rather than "edit main.lua": every update overwrites main.lua, and a
-- server owner who tuned their curve loses it silently. This file is never shipped -- only
-- config.lua.example is -- so an update cannot clobber it.
--
-- VALIDATION IS LOUD. A typo in a config that silently reverts to defaults is how someone
-- spends a week wondering why their setting does nothing. Every rejection names the key and
-- the reason.
local function loadUserConfig()
  local dir = (debug.getinfo(1, "S").source:gsub("^@", ""):gsub("[^/\\]+$", ""))
  local candidates = { dir .. "../config.lua", dir .. "config.lua", BASE .. "config.lua" }

  local function safe_loadfile(path)
    if not path or type(path) ~= "string" then return nil end
    local f = io.open(path, "r")
    if not f then return nil end
    local content = f:read("*a")
    f:close()
    if not content or content == "" then return nil end
    local c, err = load(content, "@" .. path)
    return c, err
  end

  local chunk, used
  for _, p in ipairs(candidates) do
    local c, err = safe_loadfile(p)
    if c then chunk, used = c, p; break end
    if type(err) == "string" then
      log("config.lua at " .. p .. " HAS A SYNTAX ERROR and was NOT loaded: " .. err
        .. " -- running on defaults until it is fixed.")
      return
    end
  end
  if not chunk then return end
  local ok, user = pcall(chunk)
  if not ok or type(user) ~= "table" then
    log("config.lua found at " .. tostring(used) .. " but it did not load ("
      .. tostring(user) .. ") -- USING DEFAULTS. Fix the file or delete it.")
    return
  end

  local applied = {}
  local function num(key, lo, hi)
    local v = user[key]
    if v == nil then return end
    if type(v) ~= "number" or v ~= v then
      log("config: '" .. key .. "' must be a number, got " .. type(v) .. " -- ignored"); return
    end
    if lo and v < lo or hi and v > hi then
      log(string.format("config: '%s' = %s is outside %s..%s -- ignored", key, tostring(v),
        tostring(lo), tostring(hi))); return
    end
    CFG[key] = v; applied[#applied + 1] = key .. "=" .. tostring(v)
  end
  -- 255 is the ceiling because the GAME crashes above it, player and pals alike (LordAnorak,
  -- Nexus 2026-07-28). Refusing 256+ here is kinder than letting someone set 1000 and crash.
  num("maxLevel", 1, 255)
  num("worldQuietSec", 1, 600)
  num("xpPerAnchorLevel", 0)
  num("minPctOfLevel", 0, 10)
  num("underBonus", 0, 10)
  num("underCap", 0, 1000)
  num("overDecay", 0, 10)        -- 0 = never decay: nobody ages out of any expedition
  num("bandPct", 0, 10)          -- 0 = flat-lump mode (pre-band behaviour)
  num("bandWidth", 0, 100)
  num("bandUnderBonus", 0, 10)
  num("anchorFallback", 1, 255)
  -- 0 = trust the cancel RPC alone. The upper bound is a day, well past the 7200s hard tier:
  -- a guard longer than the expedition denies every completion, which is the bug this replaces.
  num("minInProgressSeconds", 0, 86400)

  if type(user.ladder) == "table" then
    local L, bad = {}, nil
    for i, v in ipairs(user.ladder) do
      if type(v) ~= "number" or v < 1 or v > 255 then bad = i else L[#L + 1] = v end
    end
    if bad then log("config: ladder[" .. bad .. "] is not a level 1..255 -- ladder ignored")
    elseif #L == 0 then log("config: ladder is empty -- ignored")
    else table.sort(L); CFG.ladder = L; applied[#applied + 1] = "ladder(" .. #L .. " rungs)" end
  end

  -- PER-MISSION ANCHORS: merged, not replaced. A player who wants to move one dungeon should
  -- not have to restate the other six, and restating them is how a future id silently vanishes.
  if type(user.anchors) == "table" then
    local n = 0
    for id, v in pairs(user.anchors) do
      if type(id) ~= "string" then log("config: anchors key must be a mission id string -- skipped")
      elseif type(v) ~= "number" or v < 1 or v > 255 then
        log("config: anchors['" .. tostring(id) .. "'] must be a level 1..255 -- skipped")
      else CFG.anchors[id] = v; n = n + 1 end
    end
    if n > 0 then applied[#applied + 1] = "anchors(" .. n .. " overridden)" end
  end

  if type(user.uncapped) == "table" then
    CFG.uncapped = {}
    local n = 0
    for k, v in pairs(user.uncapped) do
      -- accept BOTH { DUNGEON_X = true } and { "DUNGEON_X" } -- guessing which one someone
      -- wrote is cheaper than a support thread about it
      local id = (type(k) == "string") and k or (type(v) == "string" and v or nil)
      if id then CFG.uncapped[id] = true; n = n + 1 end
    end
    if n > 0 then applied[#applied + 1] = "uncapped(" .. n .. ")" end
  end

  -- Honour an explicit false too: a boolean knob that can only ever be turned ON is a trap
  -- for anyone who sets it, sees the effect, and tries to undo it.
  if type(user.scaleAnchorsToMaxLevel) == "boolean" then
    CFG.scaleAnchorsToMaxLevel = user.scaleAnchorsToMaxLevel
  end
  if type(user.enabled) == "boolean" then CFG.enabled = user.enabled; applied[#applied+1] = "enabled=" .. tostring(user.enabled) end
  if type(user.dryRun)  == "boolean" then CFG.dryRun  = user.dryRun;  applied[#applied+1] = "dryRun=" .. tostring(user.dryRun) end
  if type(user.respectServerExpRate) == "boolean" then
    CFG.respectServerExpRate = user.respectServerExpRate
    applied[#applied+1] = "respectServerExpRate=" .. tostring(user.respectServerExpRate)
  end

  -- THE STRETCH. Applied AFTER explicit values so an explicit anchor always wins -- someone who
  -- sets both is telling us exactly where they want that dungeon, and scaling it afterwards
  -- would silently overrule them.
  -- Idempotent: scaling a second time would compound (x2.5 then x2.5 = x6.25). Only ever
  -- relevant if something calls this twice, but a silently-compounding curve is a nasty
  -- thing to leave lying around.
  if CFG.scaleAnchorsToMaxLevel and not CFG._scaled then
    local DEFAULT_TOP = 80                   -- the vanilla ladder top this curve was tuned for
    local scale = CFG.maxLevel / DEFAULT_TOP
    if scale > 1.0001 then
      local seen = {}
      if type(user.anchors) == "table" then for id in pairs(user.anchors) do seen[id] = true end end
      for i, v in ipairs(CFG.ladder) do CFG.ladder[i] = math.floor(v * scale + 0.5) end
      for id, v in pairs(CFG.anchors) do
        if not seen[id] then CFG.anchors[id] = math.min(CFG.maxLevel, math.floor(v * scale + 0.5)) end
      end
      CFG.anchorFallback = math.min(CFG.maxLevel, math.floor(CFG.anchorFallback * scale + 0.5))
      CFG._scaled = true
      applied[#applied + 1] = string.format("scaled x%.2f to maxLevel %d", scale, CFG.maxLevel)
    end
  end

  if #applied > 0 then
    log("config.lua loaded from " .. tostring(used) .. " -- " .. table.concat(applied, ", "))
  else
    log("config.lua at " .. tostring(used) .. " applied NOTHING -- every key was unknown or "
      .. "rejected. Check the log lines above and config.lua.example for the key names.")
  end
end

-- Returns anchor, how, unknown. `unknown` = we do not know this expedition's tier,
-- which is the caller's signal to skip over-anchor decay rather than pay zero.
local warnedUnknown = {}
local function anchorFor(mid)
  local a = CFG.anchors[mid]; if a then return a, "explicit", false end
  local n = tonumber(tostring(mid):match("(%d+)%s*$") or tostring(mid):match("_(%d+)"))
  if n and CFG.ladder[n] then return CFG.ladder[n], "ladder[" .. n .. "]", false end
  -- HARD-MODE PATTERN (1.3.0). Checked BEFORE the unknown-id fallback and AFTER the explicit
  -- table, so a hard id we later confirm can still be given its own row and win. Hard mode is
  -- gated behind the hard bosses, which are gated behind the world tree, which is gated behind
  -- the final story boss -- so it is top-of-ladder content whatever tower it re-skins. Treated
  -- as KNOWN (unknown = false): we are confident about the tier even without the exact id, and
  -- marking it unknown would disable over-anchor decay for genuine end-game content.
  local suffix = CFG.hardSuffix
  if type(suffix) == "string" and suffix ~= "" then
    local s = tostring(mid)
    if s:sub(-#suffix) == suffix and s:match("^DUNGEON_") then
      local top = CFG.ladder[#CFG.ladder]
      if top then
        if not warnedUnknown[mid] then
          warnedUnknown[mid] = true
          log("HARD-MODE id '" .. s .. "' not in CFG.anchors -- matched the '" .. suffix
            .. "' pattern, anchoring to the top of the ladder (" .. top .. "). If this is wrong, "
            .. "add an explicit row. Please report the id either way.")
        end
        return top, "hard-suffix", false
      end
    end
  end
  if not warnedUnknown[mid] then
    warnedUnknown[mid] = true
    log("UNKNOWN MISSION ID '" .. tostring(mid) .. "' -- not in CFG.anchors. Paying the "
      .. "minimum (no over-anchor decay) so nobody earns zero. Please report this id.")
  end
  return CFG.anchorFallback, "FALLBACK (unknown id)", true
end

-- ---- persistence -----------------------------------------------------------
local granted = {}
do local f = safe(function() return io.open(LEDGER, "r") end)
   if f then for line in f:lines() do local id = line:match("^(%S+)"); if id then granted[id] = true end end f:close() end end
local function ledgerSave()
  local f = safe(function() return io.open(LEDGER, "w") end); if not f then log("WARN: cannot write ledger"); return end
  for id in pairs(granted) do f:write(id .. "\n") end f:close()
end
local function ledgerAdd(id) if id and not granted[id] then granted[id] = true; ledgerSave() end end
local function ledgerClear(id) if id and granted[id] then granted[id] = nil; ledgerSave() end end

local missionSeen = {}
do local f = safe(function() return io.open(MISSIONS, "r") end)
   if f then for line in f:lines() do local g, m = line:match("^(%S+)%s+(%S+)"); if g and m then missionSeen[g] = m end end f:close() end end
local function missionsSave()
  local f = safe(function() return io.open(MISSIONS, "w") end); if not f then return end
  for g, m in pairs(missionSeen) do f:write(g .. " " .. m .. "\n") end f:close()
end
local function missionNote(g, m)
  if g and m and m ~= "None" and missionSeen[g] ~= m then missionSeen[g] = m; missionsSave() end
end

-- WHAT WE KNOW ABOUT EACH BENCH'S CURRENT RUN. One table rather than five file-scope locals,
-- because it is one fact with five faces and they must be cleared together -- a stale
-- `completed` or `since` leaking into the NEXT run on the same bench would decide that run.
--   lastState -- the state we saw last sweep. `1 -> 2` across two sweeps is how we know we
--                watched a run START, which is the only case the elapsed-time guard may deny.
--   since     -- os.time() when this run was first seen in progress.
--   witnessed -- true only if `since` really is the run's start (we saw state 1 before it),
--                not merely the first time we happened to look.
--   completed -- state 3 (Reward) was seen. Positive proof of completion.
--   canceled  -- the game's cancel RPC named this bench. Positive proof of cancellation.
--   said      -- one-shot flag so the "paying anyway" explanation is logged once per run and
--                not every 120s while payMission retries.
-- Declared HERE, above crewsSave/snapshotCrew/sweep, because all three touch it and a
-- forward reference in Lua is a nil global, not an error.
-- STATE AS A RAW BYTE (2026-08-08). A third-party patch of 1.5.1 (onlynovice's gist,
-- surfaced on Nexus by yassuo666666) claims reading model.State through the property
-- system can die INSIDE UE4SS's enum conversion -- a native AV no pcall catches.
-- Unverified here (their testing was single-player), but the mitigation costs nothing:
-- alias the same bytes as a ByteProperty, offset resolved FROM the reflected State
-- property (no hardcoded numbers -- survives layout changes), and read that instead.
-- Falls back to the enum read wherever registration is unavailable.
-- API: docs.ue4ss.com RegisterCustomProperty (verified 2026-08-08). Technique credit:
-- onlynovice's gist 832bcb69.
local STATE_RAW_OK = pcall(function()
  RegisterCustomProperty({
    Name = "ExpXP_StateRaw",
    Type = PropertyTypes.ByteProperty,
    BelongsToClass = "/Script/Pal.PalMapObjectCharacterTeamMissionModel",
    OffsetInternal = { Property = "State", RelativeOffset = 0 },
  })
end)
local function stateOf(model)
  if STATE_RAW_OK then
    local v = safe(function() return model.ExpXP_StateRaw end)
    if type(v) == "number" then return v end
  end
  return safe(function() return model.State end)
end

local RUN = { lastState = {}, since = {}, witnessed = {}, completed = {}, canceled = {}, said = {},
              reqSec = {} }   -- gid -> the run's own required seconds (see the sweep)
local function clearRun(gid)
  RUN.since[gid], RUN.witnessed[gid] = nil, nil
  RUN.completed[gid], RUN.canceled[gid], RUN.said[gid] = nil, nil, nil
  RUN.reqSec[gid] = nil
end

-- crews.txt: "gid [t=<epoch>] iid iid iid ..." per line. THE source of truth for who is owed.
-- `t=` is written ONLY when we watched the run start, and it means exactly that: "this run
-- began at this wall-clock time, on our own evidence". It rides in the file so a server restart
-- mid-expedition does not hand out a free cancel -- without it, every restart would reset the
-- elapsed-time guard to "unknown", which pays. Unknown `key=value` tokens are skipped rather
-- than mistaken for pal ids, so an older crews.txt (which has none) loads unchanged and a newer
-- one can grow another field without breaking this build.
local crewSets = {}   -- gid -> { iid = true, ... }
local function crewsLoad()
  crewSets = {}
  local f = safe(function() return io.open(CREWS, "r") end); if not f then return end
  for line in f:lines() do
    local gid = line:match("^(%S+)")
    if gid then
      local set = {}
      for tok in line:gmatch("%S+") do
        if tok ~= gid then
          local t = tonumber(tok:match("^t=(%d+)$"))
          if t then RUN.since[gid], RUN.witnessed[gid] = t, true
          elseif not tok:find("=", 1, true) then set[tok] = true end
        end
      end
      crewSets[gid] = set
    end
  end
  f:close()
end
-- WARN ONCE PER SESSION, AND NAME THE PATH. Jarol's report was this line every few seconds for a
-- whole expedition (Workshop, 2026-07-31). Repeating an unactionable warning is how a log becomes
-- unreadable, and the message did not even say which path had failed -- so nobody could tell that
-- the real fault was a relative path resolving against the wrong working directory.
local crewsWarned = false
local function crewsSave()
  local f = safe(function() return io.open(CREWS, "w") end)
  if not f then
    if not crewsWarned then
      crewsWarned = true
      log("WARN: cannot write " .. tostring(CREWS) .. " -- expedition XP still works, but nothing "
          .. "is saved, so a restart mid-expedition loses who is owed. Check the folder exists "
          .. "and is writable. (This warning is shown once per session.)")
    end
    return
  end
  for gid, set in pairs(crewSets) do
    local ids = {}; for iid in pairs(set) do ids[#ids + 1] = iid end
    if #ids > 0 then
      -- only a WITNESSED start is worth persisting: the timestamp's whole job is to let the
      -- guard deny a run, and it may only deny one whose beginning we actually saw.
      local stamp = (RUN.witnessed[gid] and type(RUN.since[gid]) == "number")
        and string.format(" t=%d", RUN.since[gid]) or ""
      f:write(gid .. stamp .. " " .. table.concat(ids, " ") .. "\n")
    end
  end
  f:close()
end
crewsLoad()

-- ---- world singletons ------------------------------------------------------
-- (The 1.5.1 gate that stood here -- GameState-settle-20s OR wall-clock-75s -- only DELAYED
-- the crash family; see the v2 block below for why both arms were the wrong signal. Nothing
-- owed is lost under v2 either: a pending crews.txt pays on the first post-quiet sweep.)
local SCRIPT_T0 = os.time()
-- WORLD-SETTLE GATE v2 (2026-08-08; ported from PalsLearnOverTime 1.1.9, play-validated
-- since 08-07). The old gate opened on wall-clock 75s ("world-ready: wall-clo..." -- the
-- exact line belaslav found as the LAST line of every crash log: the timer opened the gate
-- mid-stream and the very next walk killed the process) or on GameStateInGame stability (a
-- world-init singleton, the wrong proxy) -- and once t+75 passed it could NEVER re-close.
-- v2 watches the populations the sweeps actually walk:
--   floor    -- GameStateInGame valid at all (title/travel closes the gate);
--   primary  -- FindAllOf COUNTS quiet for worldQuietSec: PalIndividualCharacterContainer
--               (nonzero required -- a loaded world always has containers) and
--               PalMapObjectCharacterTeamMissionModel (zero allowed -- no bench built);
--   events   -- pure NotifyOnNewObject stamps on those two PLUS PalCharacterParameterComponent
--               (the proven spawn-in-draining indicator), and the cancel/state hooks stamp the
--               same clock -- a cancel is the game ANNOUNCING tear-down churn no construction
--               notification can see.
-- The verdict LATCHES (zero steady-state cost) and re-arms on any burst. There is NO time
-- fallback: the fallback WAS the bug -- it converted "slow load" into "crash on schedule".
local settleCount, settleCountAt = nil, 0
local lastConstructAt = 0
local settledLatch = false
local settledLogged = false
-- HOT PATH -- this body runs on EVERY construction of three classes, which during a streaming
-- window means every pal arriving. The first version called os.time() each time and wrote the
-- same one-second value over and over. It is now a single integer increment; worldReady()
-- converts ticks back into the same "when did construction last happen" answer, at worst one
-- poll late against a worldQuietSec of 10. Same semantics, a fraction of the work.
-- The counter is also the MEASUREMENT: how busy this path actually is, printed at settle. That
-- number did not exist when the 2026-08-13 19:45 access violation made this code a suspect, and
-- guessing at callback volume is slower than counting it.
local constructTicks, seenTicks = 0, 0
local function stampChurn() constructTicks = constructTicks + 1 end
-- NotifyOnNewObject WANTS A FULL OBJECT PATH; FindAllOf wants the SHORT name. These three were
-- registered with the short name, which ERRORS -- so from the day this gate shipped the event arm
-- never existed at all (armed=0 FAILED=3 in every archived boot log). The count check carried the
-- gate alone, and a count is blind to pals streaming into containers that ALREADY EXIST: the total
-- never moves, which is precisely the spawn-in drain this gate refuses to walk during.
-- The short name is kept as a fallback because the accepted form belongs to the loader, not to
-- this mod, and the log names whichever one actually armed rather than assuming.
for _, cls in ipairs({ "PalIndividualCharacterContainer", "PalMapObjectCharacterTeamMissionModel",
                       "PalCharacterParameterComponent" }) do
  local how, okN                                                         -- body PURE: stamp only
  for _, form in ipairs({ { "/Script/Pal." .. cls, "full path" }, { cls, "short name" } }) do
    if not okN then
      okN = pcall(function() NotifyOnNewObject(form[1], stampChurn) end)
      if okN then how = form[2] end
    end
  end
  log("world-settle: construct stamp on " .. cls ..
      (okN and (" armed (" .. how .. ")") or " FAILED both forms (count check still guards)"))
end
local function worldReady()
  -- TEST-ONLY BYPASS (underscore = internal, never documented in the schema): the verdict/
  -- payout suite exercises sweeps against a mock world that has no populations to settle;
  -- the gate itself gets its own dedicated check in the suite with this flag OFF.
  if CFG._testForceSettled then return true end
  local now = safe(function() return os.time() end)
  if type(now) ~= "number" then now = SCRIPT_T0 end   -- no clock: degrade to floor-only, never to true
  -- Convert the hot path's tick counter into the timestamp the rest of this function reads. The
  -- clock lives HERE, on a poll, instead of inside a callback that fires per constructed object.
  if constructTicks ~= seenTicks then seenTicks, lastConstructAt = constructTicks, now end
  local gs = safe(function() return FindFirstOf("PalGameStateInGame") end)
  if not alive(gs) then settleCount, settledLatch = nil, false; return false end
  local quiet = tonumber(CFG.worldQuietSec) or 10
  if settledLatch then
    if (now - lastConstructAt) < quiet then          -- burst: close and re-verify
      settledLatch, settleCount = false, nil
      return false
    end
    return true
  end
  local conts = safe(function() return FindAllOf("PalIndividualCharacterContainer") end)
  local nc = conts and #conts or 0
  local models = safe(function() return FindAllOf("PalMapObjectCharacterTeamMissionModel") end)
  local nm = models and #models or 0
  local sig = nc * 100000 + nm
  if sig ~= settleCount then settleCount, settleCountAt = sig, now; return false end
  if nc == 0 then return false end                   -- empty containers = still streaming, never settled
  if (now - settleCountAt) < quiet then return false end
  if (now - lastConstructAt) < quiet then return false end
  settledLatch = true
  if not settledLogged then settledLogged = true
    log("world-settled: populations quiet -- sweeps armed (containers=" .. nc .. " missionModels="
        .. nm .. " constructTicks=" .. constructTicks .. ")")
  end
  return true
end

local authLogged = false
local function isAuthority()
  local gm = safe(function() return FindFirstOf("GameModeBase") end)
  local a = alive(gm)
  if not a and not authLogged then authLogged = true; log("client detected -- passive (grants run on the host)") end
  return a
end
local function worldCtx()
  return safe(function() return FindFirstOf("GameModeBase") end) or safe(function() return FindFirstOf("PalGameStateInGame") end)
end
local function expDatabase(ctx)
  local u = safe(function() return StaticFindObject("/Script/Pal.Default__PalUtility") end); if not alive(u) then return nil end
  local db = safe(function() return u:GetExpDatabase(ctx) end); return alive(db) and db or nil
end

-- a container pal's OWN InstanceId. Try several accessors; remember the winner.
local iidAccessor = nil
local function palIID(h, p, slot)
  local tries = {
    { "handle.IndividualId.InstanceId", function() return h.IndividualId.InstanceId end },
    { "handle:GetIndividualId().InstanceId", function() return h:GetIndividualId().InstanceId end },
    { "param.IndividualId.InstanceId", function() return p.IndividualId.InstanceId end },
    { "param:GetIndividualId().InstanceId", function() return p:GetIndividualId().InstanceId end },
    { "slot.InstanceId", function() return slot.InstanceId end },
    { "param.SaveParameter.IndividualId.InstanceId", function() return p.SaveParameter.IndividualId.InstanceId end },
  }
  if iidAccessor then local g = guid(safe(tries[iidAccessor][2])); if g then return g end end
  for i, t in ipairs(tries) do
    local g = guid(safe(t[2]))
    if g then
      if iidAccessor ~= i then iidAccessor = i; log("palIID accessor = " .. t[1]) end
      return g
    end
  end
  return nil
end

-- ---- per-pal grant (cumulative-correct); DRY logs, writes nothing ----------
-- Returns "paid" | "zero" (matched but the curve gave it nothing) | "max" (already at
-- maxLevel) | false (couldn't read this pal -- not a match, don't count it).
-- `mid` (1.3.0) is passed so CFG.uncapped can be consulted here: it is the only place
-- over-anchor decay is applied, and "this expedition pays everyone" has to act exactly here.
-- ---- SERVER XP RATE --------------------------------------------------------
-- This mod writes SaveParameter.Exp directly and never goes through the game's XP pipeline, so
-- the world's ExpRate has never touched an expedition grant. With respectServerExpRate on,
-- every grant is multiplied by it.
--
-- TWO SOURCES, in this order, because neither alone covers every world:
--   1. the LIVE option settings -- authoritative, and the only source that knows the value on a
--      co-op/single-player world or when the owner never wrote the key (Palworld reads its own
--      defaults internally, so a MISSING line does not mean 1.0);
--   2. PalWorldSettings.ini on disk -- dedicated servers only, but simple, and exactly the
--      number the owner typed.
--
-- A NESTED STRUCT FIELD IS THE SHAPE UE4SS SOMETIMES REFUSES TO MARSHAL, and nothing else in
-- this codebase reads the option subsystem, so source 1 is unproven by definition. That is why
-- there are two, why the value is validated (finite, > 0), and why an unreadable rate degrades
-- to 1.0 and NEVER to 0 -- a silent zero would pay every pal nothing and look exactly like the
-- mod being broken. Which source answered is logged, so a no-op is visible instead of assumed.
local RATE_SOURCES = {
  { cls = "PalOptionSubsystem",   holder = "OptionWorldSettings" },
  { cls = "PalOptionReplicator",  holder = "OptionWorldSettings" },
  { cls = "PalGameWorldSettings", holder = "OptionSettings" },
}
local function rateFromWorld()
  for _, s in ipairs(RATE_SOURCES) do
    local o = safe(function() return FindFirstOf(s.cls) end)
    if alive(o) then
      local v = safe(function() return o[s.holder].ExpRate end)
      if type(v) == "number" and v == v and v > 0 then return v, s.cls end
    end
  end
end
local function rateFromIni()
  -- Mods/ExpeditionXP/ -> Mods -> ue4ss -> Win64 -> Binaries -> Pal, then Saved/Config/...
  local f = safe(function()
    return io.open(BASE .. "../../../../../Saved/Config/WindowsServer/PalWorldSettings.ini", "r")
  end)
  if not f then return nil end
  local s = f:read("*a") or ""
  f:close()
  local v = tonumber(tostring(s):match("ExpRate%s*=%s*([%d%.]+)") or "")
  if type(v) == "number" and v == v and v > 0 then return v, "PalWorldSettings.ini" end
end
local expRate, rateOkLogged, rateFailLogged = nil, false, false
local function expRateMult()
  if not CFG.respectServerExpRate then return 1 end
  if expRate then return expRate end                 -- retried until it answers, then fixed
  local v, src = rateFromWorld()
  if not v then v, src = rateFromIni() end
  if v then
    expRate = v
    if not rateOkLogged then
      rateOkLogged = true
      log(string.format("server ExpRate = %s (via %s) -- expedition XP scaled by it", tostring(v), tostring(src)))
    end
    return v
  end
  if not rateFailLogged then
    rateFailLogged = true
    log("respectServerExpRate is ON but the world's ExpRate could not be read, from the option "
      .. "settings or from PalWorldSettings.ini -- grants are NOT scaled (running at 1.0). That "
      .. "is a no-op, not a zero.")
  end
  return 1
end

local function grantToParam(p, anchor, ctx, dry, unknown, mid)
  local cid = safe(function() return p.SaveParameter.CharacterID:ToString() end) or ""
  if cid == "" or cid == "None" then return false end
  local lvl = safe(function() return p.SaveParameter.Level end)
  local exp = safe(function() return p.SaveParameter.Exp end)
  if type(lvl) ~= "number" or type(exp) ~= "number" then return false end
  if lvl >= CFG.maxLevel then return "max" end
  local db = expDatabase(ctx); if not db then log("  SKIP: ExpDatabase unresolved"); return false end
  -- An unknown expedition has no known tier, so decaying a pal to nothing would be a
  -- guess in the harshest possible direction. Anchor it to the pal instead: no bonus,
  -- no decay, so the floor (minPctOfLevel) is what it earns.
  if unknown and lvl > anchor then anchor = lvl end
  -- UNCAPPED MISSIONS never age a pal out, however far past the anchor it is. This is the
  -- "make the last expedition give full xp to all pals regardless of level" option, and it is
  -- what makes a level-extender server work without retuning every anchor by hand.
  local noDecay = (mid ~= nil) and (CFG.uncapped and CFG.uncapped[mid] == true) or false
  local d = anchor - lvl
  local underMult = (d >= 0) and (1 + math.min(d, CFG.underCap) * CFG.underBonus) or 1
  local overMult  = (d < 0 and not noDecay) and math.max(0, 1 + d * CFG.overDecay) or 1
  local base = CFG.xpPerAnchorLevel * anchor * underMult
  -- BANDED WAGES (2026-08-10, the design Maiq argued this into over one long night, v3 of 3):
  --   pay = (cost of ONE LEVEL at the anchor) x bandPct x band
  --   band: 10+ levels UNDER the anchor -> x bandUnderBonus (babies leap);
  --         within +-bandWidth        -> x 1  (full honest wages, every run, forever);
  --         more than bandWidth OVER  -> handled by the existing overDecay/uncapped path.
  -- WHY THIS SHAPE, briefly, because two designs died to get here: the original flat lump's
  -- magnitude answered to nothing (felt random because it was); convergence (v2) halved the
  -- remaining gap per run -- rapid leap, then an asymptote players hit like a WALL at
  -- anchor-3 ("hard stop at 65, where's the progression?", Maiq, in play, 08-10). A fixed
  -- quantum has no asymptote: a pal walks THROUGH the anchor at ~a level per run and out the
  -- top of the band, where the next expedition tier takes over -- the tower ladder becomes a
  -- staircase. The quantum is game-sourced (live PalExpDatabase, the API this file has used
  -- in production for weeks) so the magnitude finally answers to something: one run in-band
  -- pays about one level AT THE DUNGEON'S TIER. No time axis (durations are not a player
  -- lever, and tech unlocks REDUCE them -- paying by time would tax a reward). KNOWN
  -- missions only (an unknown mission keeps the flat lump); the minPctOfLevel floor and all
  -- cancel guards unchanged; unreadable curve degrades to the flat lump, never to zero.
  local bp = tonumber(CFG.bandPct) or 0
  if bp > 0 and not unknown and d >= -(tonumber(CFG.bandWidth) or 10) then
    local aL = math.min(anchor, CFG.maxLevel - 1)
    local quantum = safe(function() return db:GetNextExp(aL, false) end)
    if type(quantum) == "number" and quantum > 0 then
      local bonus = (d > (tonumber(CFG.bandWidth) or 10)) and (tonumber(CFG.bandUnderBonus) or 1.5) or 1
      base = quantum * bp * bonus
      -- the band OWNS the over-anchor range it covers: full wages to bandWidth over, and
      -- the old overDecay (which zeroes at ~7 over) must not eat the band's promise.
      -- Past the band the old decay path still applies and is already zero there.
      overMult = 1
    end
  end
  local nextCost = safe(function() return db:GetNextExp(lvl, false) end)
  local floorXp  = (type(nextCost) == "number" and nextCost > 0) and (CFG.minPctOfLevel * nextCost) or 0
  -- The server rate applies LAST, to the finished grant, so it scales the band, the floor and
  -- the flat lump alike. The MAKE-GOOD path is deliberately NOT scaled: it repays XP that was
  -- already owed at the rate in force when it was earned, and re-pricing an old debt at today's
  -- rate would be wrong in whichever direction the owner had since moved the dial.
  local xp = math.floor(math.max(base, floorXp) * overMult * expRateMult() + 0.5)
  if xp <= 0 then return "zero" end
  local newTotal, newLvl = exp + xp, lvl
  while newLvl < CFG.maxLevel do
    local nxt = safe(function() return db:GetTotalExp(newLvl + 1, false) end)
    if type(nxt) ~= "number" or nxt > newTotal then break end
    newLvl = newLvl + 1
  end
  if dry then
    log(string.format("  WOULD GRANT %-22s Lv%d->%d  total %d->%d (+%d, d=%+d)", cid, lvl, newLvl, exp, newTotal, xp, d))
    return "paid"
  end
  local okL = pcall(function() p.SaveParameter.Level = newLvl end)
  local okE = pcall(function() p.SaveParameter.Exp   = newTotal end)
  log(string.format("  GRANT %-22s Lv%d->%d  total %d->%d (+%d, d=%+d)  L=%s E=%s", cid, lvl, newLvl, exp, newTotal, xp, d, tostring(okL), tostring(okE)))
  return "paid"
end

-- ---- pay a finished mission by matching container pals to the crews.txt set --
local zeroLogged, dryDone = {}, {}
local function payMission(gid)
  if granted[gid] then return end
  local set = crewSets[gid]; if not set or not next(set) then return end
  local dry = (CFG.dryRun == true)
  if dry and dryDone[gid] then return end
  local ctx = worldCtx()
  -- BOUND, not read out of thin air. grantToParam takes the mission id so CFG.uncapped can be
  -- consulted where over-anchor decay is applied -- but the call below passed `mid`, which was
  -- never a local here, so it resolved to a nil GLOBAL. Every grant therefore ran as though no
  -- expedition was ever uncapped: the parameter existed, the plumbing existed, and the value was
  -- always nil. Caught by global-check.js, which is exactly the class of bug it was written for.
  local mid = missionSeen[gid] or "None"
  local anchor, how, unknown = anchorFor(mid)
  -- matched = crew pals found in the containers. paid/zero/maxed break that down; a pal
  -- the curve gave nothing to is NOT "paid". Counting those as paid is what let a whole
  -- 83-pal DUNGEON_FOREST run report "want=83 paid=83" while granting zero XP.
  local want, matched, paid, zeroXp, maxed, seen = 0, 0, 0, 0, 0, {}
  for _ in pairs(set) do want = want + 1 end
  for _, cont in ipairs(safe(function() return FindAllOf("PalIndividualCharacterContainer") end) or {}) do
    if alive(cont) then
      local slots = safe(function() return cont.SlotArray end)
      -- NOTHING INSIDE A ForEach CALLBACK MAY RAISE. UE4SS runs these closures from C++
      -- (TArray::ForEach); a Lua error longjmps out of the C++ frame without unwinding,
      -- trips the /GS stack cookie and __fastfails the PROCESS with 0xC0000409 (faulting
      -- module UE4SS.dll, and no crash dump -- UE's handler never runs). The OUTER pcall
      -- does not help: by then the C++ stack is already corrupt. Enforced by
      -- tools/foreach-check.js, which is what found this site.
      if slots then pcall(function() slots:ForEach(function(_, se)
        pcall(function()
          local slot = se:get()
          local h = alive(slot) and safe(function() return slot.Handle end)
          local p = alive(h) and safe(function() return h:TryGetIndividualParameter() end)
          if alive(p) then
            local iid = palIID(h, p, slot)
            if iid and set[iid] and not seen[iid] then
              seen[iid] = true
              local st = grantToParam(p, anchor, ctx, dry, unknown, mid)
              if st then
                matched = matched + 1
                if st == "paid" then paid = paid + 1
                elseif st == "zero" then zeroXp = zeroXp + 1
                elseif st == "max" then maxed = maxed + 1 end
              end
            end
          end
        end)
      end) end) end
    end
  end
  -- The retry gate is MATCHED, not paid: a crew that is all at maxLevel legitimately
  -- earns nothing and must still close out, or the mission is re-swept forever.
  if matched == 0 then
    if not zeroLogged[gid] then zeroLogged[gid] = true
      log(string.format("pay gid=%s mission=%s want=%d: 0 matched in containers (accessor? or crew not spawned/in-box yet)", gid, tostring(missionSeen[gid]), want)) end
    return
  end
  zeroLogged[gid] = nil
  log(string.format("pay gid=%s mission=%s anchor=%d (%s) want=%d matched=%d paid=%d zero-xp=%d maxed=%d %s",
    gid, tostring(missionSeen[gid]), anchor, how, want, matched, paid, zeroXp, maxed, dry and "== DRY RUN ==" or "== ARMED =="))
  if paid == 0 and zeroXp > 0 then
    log(string.format("  NOTE: %d pal(s) earned 0 -- they are more than ~%d levels over the anchor (%d). "
      .. "If that's wrong, this expedition's anchor is too low.", zeroXp, math.floor(1 / CFG.overDecay), anchor))
  end
  if dry then dryDone[gid] = true
  else ledgerAdd(gid); crewSets[gid] = nil; crewsSave() end
end

-- ---- capture in-progress crew from RepInfoArray (State 2) -------------------
local function snapshotCrew(model, gid)
  local mid = fname(safe(function() return model.TargetMissionId end))
  missionNote(gid, mid); ledgerClear(gid)
  local items = safe(function() return model.AssignedInfo.RepInfoArray.Items end); if not items then return end
  local set, n = {}, 0
  -- same rule as the pay loop above: the body must never raise into UE4SS's C++ frame.
  pcall(function() items:ForEach(function(_, elem)
    pcall(function()
      local rep = elem:get()
      local id  = rep and safe(function() return rep.IndividualId end)
      local s = id and guid(safe(function() return id.InstanceId end))
      if s then set[s] = true; n = n + 1 end
    end)
  end) end)
  if n > 0 then crewSets[gid] = set; crewsSave(); log(string.format("snapshot IN-PROGRESS gid=%s mission=%s crew=%d", gid, tostring(mid), n)) end
end

-- ---- sweep -----------------------------------------------------------------
-- COMPLETION IS THE DEFAULT; A CANCEL HAS TO BE PROVED (2026-08-03).
--
-- THE LIFECYCLE (measured on the live server, 2026-07-31, and matching the game's own enum
-- EPalMapObjectCharacterTeamMissionState { None=0, Ready=1, InProgress=2, Reward=3 }):
-- 1 -> 2 -> 3 -> 1, and a cancel goes 2 -> 1 WITHOUT visiting 3.
--
-- WHAT 1.4.1 DID, AND WHY IT WAS WORSE THAN THE BUG IT FIXED. Players reported XP being paid
-- for CANCELLED expeditions, which was real. 1.4.1 fixed it by requiring a gid to be SEEN in
-- state 3 before it could ever pay. But state 3 is TRANSIENT -- 3 to 24 seconds observed --
-- while the periodic sweep is 120s apart, so the only thing that reliably looks inside that
-- window is the +1.5s sweep fired by the state-change hook. That hook is on
-- APalBuildObjectCharacterTeamMission: a STREAMED ACTOR, which does not exist while nobody is
-- at the base. On a dedicated server that is the normal condition, not an edge case. Miss the
-- window and the model is back at state 1 with no mark, so a genuinely completed run took the
-- "canceled" branch: crew dropped, zero XP, log line lying about it. Multiple 1.4.1/1.4.2
-- reports are exactly this; one quoted log shows `state 1 -> 2` and no `2 -> 3` ever following.
-- Absence of evidence was being read as evidence of a cancel, and it is the commoner event by
-- far -- which is precisely backwards, because a cancel is the rare, deliberate one.
--
-- SO THE DEFAULT FLIPS: a run that leaves state 2 with nothing known against it is PAID. What
-- keeps the exploit shut is that a cancel is now established POSITIVELY, by two independent
-- signals, and EITHER ONE ALONE refuses payment:
--
--   1. THE GAME'S OWN CANCEL RPC.
--      UPalMapObjectCharacterTeamMissionModel::RequestCancelInProgressMission_ServerInternal
--      (CXXHeaderDump/Pal.hpp) -- and note WHERE it lives: on the PERSISTENT model object, not
--      on the streamed actor whose hook is the thing that failed. Exact, names the bench, and
--      catches a cancel at any point in the run, including hours in.
--      *** UNPROVEN. *** Read from the header dump, never measured firing. It is not the only
--      guard for that reason, and if it never fires nothing gets worse than guard 2 alone.
--   2. TIME IN PROGRESS. From the game's own DT_CharacterTeamMissionDataTable, every normal
--      expedition is RequiredSeconds 1800-3600 and every hard one 7200. A run we watched START
--      and that left state 2 after less than CFG.minInProgressSeconds (1200) cannot have
--      finished. This is what actually kills the exploit, because the exploit only has one
--      shape -- start it, cancel it at once, collect, repeat. Costing it a real half-hour of
--      expedition time makes it not an exploit but the feature.
--
-- THE GUARD MAY ONLY DENY A RUN WHOSE START WE WITNESSED (state 1 seen, then state 2). A run
-- already under way the first time we look has no honest elapsed time, so it is paid and the
-- log says which reason applied. crews.txt carries `t=<epoch>` across a restart so that window
-- is not a standing free pass. WHAT REMAINS OPEN, stated rather than hidden: a bench this
-- session has never seen in state 1 -- built and used inside one 120s sweep gap, or first seen
-- mid-run -- can be cancelled once for XP if guard 1 also fails to fire. One grant per bench
-- per server start is not a farm, and erring here is deliberate: withholding from a player who
-- finished the run is the failure that got reported, twice.
local function sweep(why)
  pcall(function()
    if not CFG.enabled then return end
    -- world-ready FIRST: it must run before isAuthority's own FindFirstOf, because during a
    -- save load even that lookup walks a churning object table
    if not worldReady() then return end
    if not isAuthority() then return end
    -- Resolve the server ExpRate on the first settled sweep rather than lazily at the first
    -- PAYOUT. Same call, same one-time logging -- but a crew can be an hour from coming home,
    -- and a feature whose only proof arrives an hour after boot is a feature nobody can check.
    -- Memoised, so this is a table read on every later sweep. Called HERE and not from
    -- worldReady() because expRateMult is defined below it: a forward reference would resolve
    -- to a nil global and take the whole sweep down.
    expRateMult()
    -- os.time() through `safe`: if the sandbox has no os library this comes back nil, every
    -- elapsed test is then unanswerable, and unanswerable means PAY. Degrading toward paying
    -- is the whole point of this rewrite.
    local now = safe(function() return os.time() end)
    if type(now) ~= "number" then now = nil end
    local inProgress, otherState = {}, {}
    for _, model in ipairs(safe(function() return FindAllOf("PalMapObjectCharacterTeamMissionModel") end) or {}) do
      if alive(model) then
        local st = stateOf(model)   -- byte-alias read; enum fallback (see STATE AS A RAW BYTE)
        local gid = guid(safe(function() return model.InstanceId end))
        if gid then
          local prev = RUN.lastState[gid]
          if st == 2 then
            inProgress[gid] = true
            -- A CANCEL MARK CANNOT GO STALE ONTO THE NEXT RUN, and it is worth saying why,
            -- because a stale DENY is the one direction this rewrite exists to stop. The
            -- cancel hook schedules its own sweep 1.5s later, which drops the crew and clears
            -- the mark; and any run we watch begin clears it again on the branch below
            -- (state 1 -> 2). The only gap is a player cancelling and re-starting a full
            -- expedition inside 1.5 seconds, through a UI that requires re-picking the crew.
            if prev ~= nil and prev ~= 2 then
              -- we watched this bench leave Ready: a brand-new run begins HERE. Restart the
              -- clock, and drop the previous run's verdicts -- a stale `completed` would pay
              -- this crew for the LAST expedition's success.
              RUN.since[gid], RUN.witnessed[gid] = now, (prev == 1)
              RUN.completed[gid], RUN.canceled[gid], RUN.said[gid] = nil, nil, nil
            elseif RUN.since[gid] == nil then
              -- first sight of a run already under way (mod just loaded, or a restart with no
              -- t= on record). We do not know when it started, so it can never be denied.
              RUN.since[gid], RUN.witnessed[gid] = now, false
            end
            snapshotCrew(model, gid)
            -- THE RUN'S OWN DURATION (2026-08-08: Nihe + kfx123, "Faster Expedition Time"
            -- breaks the elapsed guard). MissionStart/CompleteDateTime are the game's own
            -- schedule for THIS run -- already scaled by any expedition-timer mod, per
            -- mission tier, no DataTable read. Their difference is the run's true required
            -- seconds; the guard below prefers it (x0.8 slack) over the flat
            -- minInProgressSeconds, which stays as the fallback when these fields are
            -- unreadable. FDateTime is 100ns ticks; the difference is /1e7. Re-read every
            -- sweep while in progress: harmless, and a mid-run reschedule follows.
            local ds = safe(function() return model.MissionStartDateTime end)
            local dc = safe(function() return model.MissionCompleteDateTime end)
            local sn = tonumber(ds) or tonumber(safe(function() return ds and ds.Ticks end))
            local cn = tonumber(dc) or tonumber(safe(function() return dc and dc.Ticks end))
            if sn and cn and cn > sn then
              local reqS = (cn - sn) / 1e7
              if reqS > 60 and reqS < 86400 * 7 then RUN.reqSec[gid] = reqS end
            end
          elseif st == 3 then RUN.completed[gid] = true
          elseif st ~= nil then otherState[gid] = true end
          if st ~= nil then RUN.lastState[gid] = st end
        end
      end
    end
    for gid in pairs(crewSets) do
      if not granted[gid] and not inProgress[gid] then
        local dwell = (type(RUN.since[gid]) == "number" and now) and (now - RUN.since[gid]) or nil
        local function drop(reason)
          crewSets[gid] = nil; clearRun(gid); crewsSave()
          log(string.format("gid=%s CANCELED -- %s -- no XP, crew dropped", gid, reason))
        end
        -- CLEAR THE MARK ONLY WHEN THE PAY ACTUALLY CLOSED OUT. 1.4.1 wiped completedEver
        -- unconditionally right after payMission, so a pay that returned "0 matched in
        -- containers" -- the normal state for the seconds before the crew is back in the box
        -- -- lost its only proof of completion, and the next sweep dropped that crew as a
        -- cancel. The retry has to keep its evidence.
        local function payAndSettle()
          payMission(gid)
          if crewSets[gid] == nil then clearRun(gid) end
        end
        if RUN.canceled[gid] then
          drop("the game's cancel request named this bench")
        elseif RUN.completed[gid] then
          payAndSettle()
        elseif otherState[gid] then
          -- PER-RUN GUARD (2026-08-08): prefer the run's OWN duration (read from the
          -- game's schedule while it ran, x0.8 slack) over the flat threshold. With a
          -- timer mod a 300s expedition is judged against ~240s, not vanilla's 1200 --
          -- that flat guard was denying every legitimate fast completion (Nihe, kfx123).
          -- It also STRENGTHENS the exploit guard for hard tiers: a 40-min cancel of a
          -- 2h expedition used to pay at 1200s; now it is judged against ~5760s.
          local req = RUN.reqSec[gid]
          local limit, basis
          if type(req) == "number" then
            limit, basis = math.floor(req * 0.8),
              string.format("80%% of this run's own %ds duration", math.floor(req))
          else
            limit, basis = tonumber(CFG.minInProgressSeconds) or 0,
              "minInProgressSeconds (run duration unreadable)"
          end
          if RUN.witnessed[gid] and dwell and limit > 0 and dwell < limit then
            drop(string.format("watched it start, and it left in-progress after only %ds "
              .. "(under %ds = %s)", dwell, limit, basis))
          else
            if not RUN.said[gid] then
              RUN.said[gid] = true
              log(string.format("gid=%s back at the bench with no state-3 sighting -- PAYING ANYWAY (%s). "
                .. "1.4.1 dropped these as cancels; that misread is the bug this replaces.", gid,
                (RUN.witnessed[gid] and dwell) and string.format("watched it run %ds, at or over the %ds guard", dwell, limit)
                  or "no witnessed start time, so it cannot be judged on elapsed time"))
            end
            payAndSettle()
          end
        end
        -- model not observed at all (demolished / not streamed): hold the crew, decide
        -- when it is seen again -- the pre-1.4.1 rule paid on mere disappearance, which was
        -- the second half of the original exploit and is NOT what is being relaxed here.
      end
    end
  end)
end

-- BOTH REGISTRATIONS BELOW LOG THEIR RESULT. They used to be bare pcalls that discarded it --
-- which for the cancel hook meant the one guard the pay-by-default rewrite leans on could fail
-- to arm and NOTHING anywhere would say so. The boot log has to carry the answer, because the
-- in-game verification ("cancel a run, look for the CANCEL line") only works if you already
-- know the hook armed; a silent registration failure turns that test into a mystery. Same rule
-- as StandingOrders' StartProduction bridge: silence must be impossible on the failure path.
local okState = pcall(function()
  RegisterHook("/Script/Pal.PalBuildObjectCharacterTeamMission:OnChangedState_ServerInternal",
    function(_, lastP, curP)
      pcall(function()
        if not CFG.enabled then return end
        -- BODY GOES PURE DURING LOAD (1.5.1): this hook lives on a STREAMED actor, and a save
        -- with an active expedition initializes it MID-LOAD -- the old body's isAuthority
        -- (FindFirstOf) ran right there. Now: nothing native before the gate; the scheduled
        -- sweep re-checks authority and world-readiness itself, so a mid-load fire costs a
        -- no-op timer at worst. Param reads (lastP/curP:get()) are hook OUT-params handed to
        -- us by the engine, not walks -- kept for the log, still pcall'd.
        if not worldReady() then return end
        local last = safe(function() return lastP:get() end)
        local cur  = safe(function() return curP:get() end)
        stampChurn()   -- a state change IS churn (crew returning, bench updating): close the gate
        log("state " .. tostring(last) .. " -> " .. tostring(cur) .. " -- sweep in 1.5s")
        ExecuteWithDelay(1500, function() sweep("transition") end)
      end)
    end)
end)
log(okState and "hooked OnChangedState (transition sweeps armed)"
             or "could NOT hook OnChangedState -- completions rely on the 120s sweep alone")

-- THE POSITIVE CANCEL SIGNAL. This is the whole reason the sweep is allowed to default to
-- paying: the game tells us, by name, which bench was cancelled.
--
-- WHY THIS FUNCTION AND NOT THE STATE CHANGE. The state hook above is on
-- APalBuildObjectCharacterTeamMission -- an ACTOR, present only while the base is loaded, which
-- is exactly why completions were being missed. RequestCancelInProgressMission_ServerInternal
-- is on UPalMapObjectCharacterTeamMissionModel, the PERSISTENT model, so it does not depend on
-- anyone standing at the base. `self` is that model, so model.InstanceId is the same gid the
-- sweep and crews.txt key on -- no correlation guesswork.
--
-- HONEST STATUS: sourced from CXXHeaderDump/Pal.hpp, NOT measured firing. If it never fires,
-- the elapsed-time guard in the sweep still refuses the instant-cancel exploit; nothing is
-- worse than it would be without this hook. If it DOES fire, a cancel is refused at any point
-- in a run, including one cancelled hours in, which no time guard can catch. Registration is
-- pcall'd because a path that does not resolve raises, and the callback opens with pcall
-- because a Lua error escaping a RegisterHook callback __fastfails the whole process.
local okCancel = pcall(function()
  RegisterHook("/Script/Pal.PalMapObjectCharacterTeamMissionModel:RequestCancelInProgressMission_ServerInternal",
    function(selfP)
      pcall(function()
        if not CFG.enabled then return end
        -- v2 (2026-08-08): isAuthority() dropped from THIS body -- it did a FindFirstOf with
        -- no world gate at all (the one ungated native lookup in the file; belaslav's cancel
        -- crash). The sweep re-checks authority itself; a canceled-mark on a client is
        -- harmless. And a cancel IS tear-down churn the construction stamps cannot see, so
        -- it stamps the churn clock: the +1.5s sweep finds the gate closed and the verdict
        -- (which LATCHES in RUN.canceled) is settled by the next quiet pass instead.
        stampChurn()
        -- hook params arrive wrapped; `self` is handed over the same way, so :get() first and
        -- fall back to the raw value rather than assuming either shape.
        local model = safe(function() return selfP:get() end) or selfP
        local gid = alive(model) and guid(safe(function() return model.InstanceId end))
        if not gid then
          log("cancel request seen but the bench id was unreadable -- that run will fall back to "
            .. "the elapsed-time guard")
          return
        end
        RUN.canceled[gid] = true
        log("CANCEL requested for gid=" .. gid .. " -- that crew will not be paid; sweep in 1.5s")
        ExecuteWithDelay(1500, function() sweep("cancel") end)
      end)
    end)
end)
-- THIS LINE IS THE ARMING REPORT FOR THE EXPLOIT GUARD. With pay-by-default, a cancel past
-- minInProgressSeconds is refused ONLY by this hook. If the boot log shows the failure arm,
-- the guard is running on the time check alone and a >5-minute cancel WILL pay -- that state
-- must be visible on day one, not discovered from an abuse report.
log(okCancel and "hooked RequestCancelInProgressMission (positive cancel signal armed)"
              or "could NOT hook RequestCancelInProgressMission -- cancels past the elapsed-time "
                 .. "guard will PAY; report this log line")

local function loop() sweep("periodic"); ExecuteWithDelay(120000, loop) end
ExecuteWithDelay(30000, loop)

local nc = 0; for _ in pairs(crewSets) do nc = nc + 1 end
-- Load the server owner's overrides BEFORE the boot line, so the log reports the numbers
-- actually in force rather than the shipped defaults.
pcall(loadUserConfig)

-- ---- ONE-SHOT MAKE-GOOD SWEEP (2026-08-10, Maiq: "heal that crew") -------------------
-- The guid() sign-extension bug (fixed above, same day) silently cost this server's main
-- guild EVERY completion pay -- most recently 100 level-1 pals on DUNGEON_DARKISLAND
-- (08-09 23:16, judged CANCELED, zero XP). Restitution: `makegood.txt` beside crews.txt --
-- first token a FLAT XP amount, remaining tokens InstanceIds -- swept once the world
-- settles; each listed pal gains the flat amount with the same level-recompute
-- grantToParam uses. FLAT, not formula: the owed value is what the lost run would have
-- paid AT LEVEL 1 (14688 = xpPerAnchorLevel 120 x anchor 68 x underMult 1.8, the same
-- arithmetic that produced the observed 13392 at anchor 62); recomputing at the crew's
-- higher post-restitution level would underpay them. The file is REWRITTEN with the
-- remaining ids after every pass that paid anyone -- the progress latch, so a crash
-- mid-campaign cannot double-pay -- and renamed makegood.done when every id is settled or
-- MAKEGOOD_DRY_LIMIT consecutive passes matched nothing (leftovers logged loudly).
do
  local MG, MG_DONE = BASE .. "makegood.txt", BASE .. "makegood.done"
  local mgAmount, mgSet, mgWant = nil, {}, 0
  local f = io.open(MG, "r")
  if f then
    local body = f:read("*a") or ""; f:close()
    for tok in body:gmatch("%S+") do
      if not mgAmount then mgAmount = tonumber(tok)
      else mgSet[tok] = true; mgWant = mgWant + 1 end
    end
  end
  local function mgPersist()
    local out = { tostring(mgAmount) }
    for k in pairs(mgSet) do out[#out + 1] = k end
    local w = io.open(MG, "w")
    if w then w:write(table.concat(out, " ")); w:close() end
  end
  if mgAmount and mgAmount > 0 and mgWant > 0 then
    log(string.format("MAKE-GOOD armed: +%d XP to %d pals (latch: %s)", mgAmount, mgWant, MG_DONE))
    local mgDry, MAKEGOOD_DRY_LIMIT = 0, 40
    LoopAsync(20000, function()
      if not worldReady() then return false end
      local ctx = worldCtx()
      local db = expDatabase(ctx)
      if not db then return false end
      local matchedNow = 0
      for _, cont in ipairs(safe(function() return FindAllOf("PalIndividualCharacterContainer") end) or {}) do
        if alive(cont) then
          local slots = safe(function() return cont.SlotArray end)
          -- ForEach discipline: nothing inside may raise (see payMission above)
          if slots then pcall(function() slots:ForEach(function(_, se)
            pcall(function()
              local slot = se:get()
              local h = alive(slot) and safe(function() return slot.Handle end)
              local p = alive(h) and safe(function() return h:TryGetIndividualParameter() end)
              if alive(p) then
                local iid = palIID(h, p, slot)
                if iid and mgSet[iid] then
                  local lvl = safe(function() return p.SaveParameter.Level end)
                  local exp = safe(function() return p.SaveParameter.Exp end)
                  if type(lvl) == "number" and type(exp) == "number" and lvl < CFG.maxLevel then
                    local newTotal, newLvl = exp + mgAmount, lvl
                    while newLvl < CFG.maxLevel do
                      local nxt = safe(function() return db:GetTotalExp(newLvl + 1, false) end)
                      if type(nxt) ~= "number" or nxt > newTotal then break end
                      newLvl = newLvl + 1
                    end
                    local okL = pcall(function() p.SaveParameter.Level = newLvl end)
                    local okE = pcall(function() p.SaveParameter.Exp   = newTotal end)
                    log(string.format("  MAKE-GOOD %s Lv%d->%d (+%d) L=%s E=%s",
                        iid, lvl, newLvl, mgAmount, tostring(okL), tostring(okE)))
                    mgSet[iid] = nil; mgWant = mgWant - 1; matchedNow = matchedNow + 1
                  end
                end
              end
            end)
          end) end) end
        end
      end
      if matchedNow > 0 then mgDry = 0; mgPersist() else mgDry = mgDry + 1 end
      if mgWant <= 0 or mgDry >= MAKEGOOD_DRY_LIMIT then
        if mgWant > 0 then
          local left = {}; for k in pairs(mgSet) do left[#left + 1] = k end
          log("MAKE-GOOD closing with " .. mgWant .. " UNMATCHED: " .. table.concat(left, " "))
        else
          log("MAKE-GOOD complete: every pal paid")
        end
        pcall(function() os.rename(MG, MG_DONE) end)
        return true
      end
      return false
    end)
  end
end

-- SAY WHERE THE FILES ARE, EVERY BOOT. Jarol's "cannot write crews" report (2026-07-31) was
-- impossible to action from the log alone, because nothing ever printed the path the mod had
-- resolved. One line at boot turns "it warns forever" into "it is looking in the wrong folder".
do
  -- Probe with append so an existing file is not truncated, and CLOSE it -- the first version of
  -- this line leaked the handle every boot.
  local probe = safe(function() return io.open(CREWS, "a") end)
  if probe then probe:close() end
  log("data folder: " .. tostring(BASE) .. (probe and " (writable)" or " (NOT WRITABLE -- nothing will persist)"))
end
log(string.format("v%s armed -- pay from crews.txt via container match | mode=%s | pending crews=%d",
  VERSION, (CFG.dryRun == true) and "DRY-RUN (no writes)" or "LIVE (writing XP)", nc))
