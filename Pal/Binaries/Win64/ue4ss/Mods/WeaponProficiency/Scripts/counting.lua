-- ============================================================================
--  counting.lua -- THE BRAIN: turns the local player's own hits into weapon XP
--  and levels, and owns the persistent store.
--
--  WHY THIS IS CORRECT CLIENT-SIDE (architecture decision 2026-07-20):
--    Damage/XP are client-computed (the client builds FPalDamageInfo and RPCs
--    the result). Per-instance weapon XP is fired ONLY by the owning player, so
--    counting your own hits locally is COMPLETE, not a partial view. The HUD
--    header's old "counts only your shots would diverge" warning was about a
--    shared DISPLAY BAR across 8 players -- it does not apply to per-instance
--    progression, which is yours alone.
--
--  Everything here mirrors the server maths EXACTLY (same progression.lua with
--  the target ladder, same config, same weapondata) so a weapon levels and
--  hits for the same numbers the server produced -- the store schema and the
--  baked st.hud are byte-compatible with what damage.lua / hud.lua expect.
--
--  SHADOW MODE: cfg.shadowCount (main sets it from SHADOW) logs XP intents
--  WITHOUT persisting, for one validation session.
-- ============================================================================

local M = {}

local cfg   = require("config")
local P     = require("progression")
local A     = require("adapters")

local Darn = require("darn")
local safe = Darn.safe
local log  = Darn.logger("[Arsenal]")

-- ---- store handle + world key (set by M.start) -----------------------------
local store, states, worldKey = nil, nil, "default"
-- Level-ups waiting to be announced; drained by main.lua's tick. See the push site.
M.levelUps = {}
-- HOISTED. The wielder level last seen on the hit path. Declared here rather than beside
-- its writer because dmgInfoFor reads it hundreds of lines earlier, and a local declared
-- below its reader is not an upvalue -- the read compiles to a nil global.
local lastWielderLv = nil
local SHADOW = false

-- ---- spec lookup (identical to server specFor) -----------------------------
-- The key-stripping and the rootless-family fallback both live in adapters now (A.staticOf /
-- A.wdLookup), because a SECOND caller over there -- the swarm router's emitsWt3 -- was doing
-- its own raw WEAPONS[m] read and losing every assault rifle under family scope. Two copies of
-- a lookup rule is how one call site keeps working and the other silently stops.
local staticOf = A.staticOf
M.staticOf = staticOf

local wdLookup = A.wdLookup
M.wdLookup = wdLookup

-- RARITY GRADE 1..5, parsed from the model key's suffix. weapondata uses TWO
-- conventions and both must be read, or a Legendary silently scores as a Common:
--   "_2".."_5"          -- the common case (WeakerBow .. WeakerBow_5), 215 rows
--   "_Default1".."_5"   -- AssaultRifle_Default1..5 (one family, no bare base key)
-- Everything else is grade 1. The patterns are END-ANCHORED and deliberately do
-- NOT match a bare trailing digit, because several keys end in one WITHOUT being
-- rarities -- Bat/Bat2/Bat3 are three different weapons (Wooden Club/Bat/Metal
-- Bat) and Spear_ForestBoss2 is "Enhanced Lily's Spear", a separate item. Nor do
-- they match two-digit tails (Axe_Tier_02, YakushimaBlade003).
local function gradeOf(id)
  -- modelFor, not staticOf: a family key has had its rarity stripped, so reading the grade
  -- off it made every family-scoped weapon a grade-1 Common -- which also moved its crossover
  -- threshold, not just its base damage.
  local k = tostring(A.modelFor(id))
  return tonumber(k:match("_Default([1-5])$")) or tonumber(k:match("_([2-5])$")) or 1
end
M.gradeOf = gradeOf

-- WHITELIST SAFETY (2026-07-24): apply ONLY to weapons whose damage rate was actually
-- MEASURED and a curve built (weapondata hpsSrc ~= "est"). An "est" weapon's rate is a
-- guess, so its target-DPS scaling can misfire and interact badly -- by default those
-- weapons are left fully VANILLA: specFor() returns nil, so no XP / damage / magazine /
-- durability / HUD, and damage.lua's restorePrev reverts any prior buff on the next
-- equip. A player can opt an untested weapon in (they have to go out of their way):
--   cfg.skipUntestedWeapons = false          -- apply to EVERY weapon in the library
--   cfg.untestedAllow       = { Model=true } -- enable specific model keys
--   cfg.untestedAllowTypes  = { Type=true }  -- enable a whole weapon type
-- Each skipped model is logged once so the player knows exactly what to opt in.
local UNTESTED_LOGGED = {}

-- UNSUPPORTED (2026-07-28, Mikey: "all terraria weapons are weird cases"). A DIFFERENT thing
-- from untested, and it needs its own answer. "Untested" means a vanilla weapon whose fire rate
-- we never measured -- fixable, go and measure it. "Unsupported" means the weapon is not vanilla
-- Palworld at all: it comes from another mod, it is on no data source we can check (paldb has
-- never heard of it), its stats can change when that mod updates, and most users do not even
-- have it. A curve EXISTS for it -- it sits in the library like every other weapon -- so opting in
-- does something coherent rather than erroring. That is ALL that can be claimed. This comment and
-- the option's help text both used to say the curve was "built and correct" (corrected
-- 2026-07-29), which contradicted the very reason the setting is off: as of
-- 2026-08-07 a MEASURED unsupported family (Excalibur, Nightglow, Vortex Beater) passes both
-- gates -- measurement + the boot validator IS verification (see isUnsupported); the est-rated
-- remainder still fails both at once -- unverifiable stats AND an estimated fire rate. It is OFF by default,
-- and the notice says why rather than pointing at the wrong setting.
local UNSUPPORTED_LOGGED = {}
local function isUnsupported(id, w)
  if not w.unsupported then return false end
  if cfg.applyUnsupported then return false end
  -- A MEASURED RATE LIFTS THE GATE (Maiq, 2026-08-07: "we measured vortex beater"). The
  -- flag's stated reason is "stats cannot be verified" -- but a measured family rate plus
  -- the boot validator (which reads the pack's LIVE static values every session; 308/308,
  -- 0 corrected) IS verification. Measured unsupported weapons are treated as supported;
  -- the flag stays in the data as provenance, and a pack update that shifts stats is the
  -- validator's job to catch. Estimated ("est") pack weapons still require the opt-in.
  if w.hpsSrc == "meas" or w.hpsSrc == "family" then return false end
  local sk = staticOf(id)
  if cfg.unsupportedAllow and cfg.unsupportedAllow[sk] then return false end
  return true
end
M.isUnsupported = isUnsupported

local function isApplicable(id, w)
  if isUnsupported(id, w) then
    local sk = staticOf(id)
    if not UNSUPPORTED_LOGGED[sk] then
      UNSUPPORTED_LOGGED[sk] = true
      log(string.format("UNSUPPORTED %s (%s) left vanilla -- not a vanilla Palworld weapon, so its "
        .. "stats cannot be verified. To enable it: cfg.applyUnsupported=true, or "
        .. "cfg.unsupportedAllow[%q]=true.", tostring(sk), tostring(w.name or w.t), tostring(sk)))
    end
    return false
  end
  if (w.hpsSrc or "est") ~= "est" then return true end       -- measured / curve built -> always
  if cfg.skipUntestedWeapons == false then return true end    -- safety explicitly off -> apply to all
  local sk = staticOf(id)
  -- SCOPE-PROOF ALLOW MATCH (2026-08-04): the key form changes with progressScope -- model
  -- scope checks "Musket_3", family scope checks "Musket" -- so an allow entry created from
  -- our own advice text stopped matching after a scope switch. An entry matches if it names
  -- the same FAMILY as the equipped weapon, whichever form either side is in.
  if cfg.untestedAllow then
    if cfg.untestedAllow[sk] or cfg.untestedAllow[string.lower(tostring(sk))] then return true end
    local fam = A.familyOf and A.familyOf(sk) or sk
    for entry, on in pairs(cfg.untestedAllow) do
      if on and (A.familyOf and A.familyOf(tostring(entry)) or tostring(entry)) == fam then return true end
    end
  end
  if cfg.untestedAllowTypes and cfg.untestedAllowTypes[w.t] then return true end
  if not UNTESTED_LOGGED[sk] then
    UNTESTED_LOGGED[sk] = true
    log(string.format("UNTESTED %s (%s) left vanilla -- damage curve not measured (hpsSrc=est). "
      .. "To enable it: cfg.untestedAllow[%q]=true, or cfg.untestedAllowTypes[%q]=true, or skipUntestedWeapons=false.",
      tostring(sk), tostring(w.name or w.t), tostring(sk), tostring(w.t)))
  end
  return false
end
M.isApplicable = isApplicable

-- Is this weapon being left vanilla SPECIFICALLY because its damage rate was never
-- measured (and the safety is on)? Returns { key=, name=, type= } if so, else nil.
-- specFor() returns nil for several unrelated reasons (not in the library at all,
-- ignoreTypes), and telling a player "turn off Tested weapons only" would be wrong
-- advice for those -- it would not help and would look like the mod is broken. So
-- the UI asks THIS, not "is spec nil".
function M.untestedInfo(id)
  local w = wdLookup(id); if not w then return nil end        -- unknown weapon: different problem
  -- IGNORED TYPES FIRST -- the case the comment above already promised and the code did
  -- not deliver. Pickaxes and Axes are TOOLS: cfg.ignoreTypes leaves all 11 of them alone
  -- by design, and every one carries hpsSrc="est", so chopping a tree or mining a rock
  -- fired the untuned-weapon notice. Worse than noise, the advice was WRONG -- setting
  -- untestedAllowTypes.Pickaxe changes nothing, because specFor() bails at the ignoreTypes
  -- gate before the whitelist is ever consulted. Reported by Mikey 2026-07-26.
  -- Placed BEFORE isApplicable so its once-per-model "UNTESTED ... left vanilla" log line
  -- does not fire for tools either; that log carries the same wrong advice.
  if cfg.ignoreTypes and cfg.ignoreTypes[w.t] then return nil end
  -- Unsupported first: it is also hpsSrc="est", so without this it would be reported as
  -- "untested" and the notice would name a setting that does not enable it.
  if isUnsupported(id, w) then
    return { key = staticOf(id), name = w.name or w.t, type = w.t, reason = "unsupported" }
  end
  if (w.hpsSrc or "est") ~= "est" then return nil end          -- measured: not this case
  if isApplicable(id, w) then return nil end                   -- opted in already (allow list / safety off)
  return { key = staticOf(id), name = w.name or w.t, type = w.t, reason = "untested" }
end

-- WHY A WEAPON WAS NOT RECOGNISED AT ALL (2026-07-31). Every other rejection path here logs
-- its reason and names the setting that changes it -- but "not in the library" returned
-- SILENTLY, so a player whose weapon stopped being tracked had nothing to send and we had
-- nothing to read (reported: a 1.9.3 player's Old Bow "isn't recognized as a weapon anymore").
-- WeakerBow is in the library and measured, so an unrecognised one means the ID REACHING US
-- is not the model key we expect -- and that is only diagnosable if the id is printed.
-- Once per distinct key: this runs on the boot scan over every owned weapon.
local UNKNOWN_LOGGED, IGNORED_LOGGED = {}, {}
-- and the third silent path: "Cap to player level" discarding a hit's XP (see grantXp).
-- Cleared when the weapon drops back under the cap, so a re-cap after a level-up says so again.
local CAPPED_LOGGED = {}

-- A weapon's BIRTH LEVEL: its tech unlock, never later than cfg.startCapLevel.
-- nil in, nil out, so a weapon with no recorded unlock is unaffected.
local function startOf(techLv)
  local v = tonumber(techLv)
  if not v then return techLv end
  local capL = tonumber(cfg.startCapLevel)
  if capL and v > capL then return capL end
  return v
end

local function specFor(id)
  local w = wdLookup(id)
  if not w then
    local sk = staticOf(id)
    if not UNKNOWN_LOGGED[sk] then
      UNKNOWN_LOGGED[sk] = true
      log(string.format("UNKNOWN WEAPON %q (raw id %q) -- not in the library, so it is left "
        .. "vanilla and earns nothing. If this is a normal Palworld weapon, that id is the bug: "
        .. "please report it with this line.", tostring(sk), tostring(id)))
    end
    return nil
  end
  -- THE SECOND SILENT PATH (2026-07-31). ignoreTypes is meant for TOOLS (Pickaxe, Axe), and
  -- skipping those quietly is right -- but if a real weapon type ends up in this list, by a
  -- hand edit or a bad settings write, every weapon of that type vanishes from the mod with
  -- NOTHING said. That is indistinguishable from "unrecognised" to a player, and it was the
  -- other half of why a 1.9.3 report could not be diagnosed from a log. Says it once per type.
  if cfg.ignoreTypes and cfg.ignoreTypes[w.t] then
    if not IGNORED_LOGGED[w.t] then
      IGNORED_LOGGED[w.t] = true
      log(string.format("IGNORED TYPE %q -- every %s is left vanilla because cfg.ignoreTypes[%q] "
        .. "is set. That is correct for tools (Pickaxe, Axe); if %q is a real weapon type you "
        .. "want tracked, remove it from ignoreTypes.",
        tostring(w.t), tostring(w.name or w.t), tostring(w.t), tostring(w.t)))
    end
    return nil
  end
  if not isApplicable(id, w) then return nil end            -- whitelist: untested weapon -> not applied
  local tinfo = cfg.types[w.t] or cfg.defaultType
  local spec = { base = w.base, cap = w.cap, maxLv = w.maxLv, g = tinfo.g, type = w.t, tier = w.tier,
           hps = w.hps, proj = w.proj, grade = gradeOf(id), xpTune = w.xpTune,
           -- CLAMPED to cfg.startCapLevel: see the config note. A weapon born at its raw
           -- tech level of 77 has no runway under capToPlayerLevel and earns nothing at all.
           start = (cfg.useStartLevel and startOf(w.start)) or nil,
           -- tech = the RAW tech level, ungated. `start` above is switched off by
           -- cfg.useStartLevel, and the tech TIER must not silently vanish with it.
           tech = w.start, tierAdj = w.tierAdj,
           name = w.name, src = tinfo.src, mode = w.mode, mag = w.mag, magMax = w.magMax,
           -- dur = authoritative per-MODEL durability base from the weapondata LIBRARY
           -- (DT_ItemData Durability). nil = not in the library -> NO durability boost.
           -- NEVER observed at runtime; see damage.lua / weapondata.lua header.
           dur = w.dur,
           xpModel = tinfo.xp,
           xpStep = tinfo.xpStep, grindPower = tinfo.grindPower, hoursByTier = tinfo.hoursByTier }
  if w.mode == "single" and cfg.singleShot then
    spec.xpModel = "timed"; spec.hoursByTier = cfg.singleShot.hoursByTier
  end
  -- The drop curve wins when it is available; it needs no per-tier budget and no maxLv
  -- rescale, because the cost of a level is simply what that level's enemies are worth.
  if cfg.useDropCurve then
    spec.xpModel = "dropcurve"
    if cfg._playerCurve then spec.maxLv = cfg._playerCurve.maxLv or spec.maxLv end
  elseif cfg.usePlayerCurve then
    if cfg._playerCurve then
      if not spec.hoursByTier then spec.hoursByTier = (cfg.singleShot and cfg.singleShot.hoursByTier) or nil end
      spec.xpModel = "playercurve"; spec.maxLv = cfg._playerCurve.maxLv or 80
    else
      spec.maxLv = 80
    end
  end
  -- PRESTIGE: attach this weapon's banked per-category points (states hold them;
  -- specFor is called before getExisting is defined, so read the store directly).
  spec.prestige = (states[worldKey] and states[worldKey][id] and states[worldKey][id].prestige) or nil
  -- +Level Cap %: each cap point raises the reachable ceiling by pct of base maxLv.
  -- capExtra is also added to the player-level clamp in grantRangedXp, so the weapon
  -- climbs that many levels past wherever it would otherwise have capped.
  local capPts = (spec.prestige and tonumber(spec.prestige.cap)) or 0
  if capPts > 0 then
    local baseMax = spec.maxLv or 80
    spec.capExtra = math.floor(baseMax * (tonumber(cfg.prestigeCapStepPct) or 0) * capPts + 0.5)
    spec.maxLv = baseMax + spec.capExtra
  end
  local mm = cfg.magMaxMultiplier
  if spec.magMax and type(mm) == "number" and mm > 1 then
    local m = math.floor(spec.magMax * mm + 0.5); if m > (spec.mag or 0) then spec.magMax = m end
  end
  local ma = cfg.magMaxAbsolute
  if type(ma) == "number" and ma > 0 and spec.magMax and spec.magMax > (spec.mag or 0) and ma > spec.magMax then
    spec.magMax = ma
  end
  return spec
end
M.specFor = specFor

local function getExisting(id) local w = states[worldKey]; return w and w[id] or nil end

-- ---- baked HUD display (dmgInfoFor / magInfoFor) ---------------------------
local function dmgInfoFor(spec, level)
  -- CLAMP THE PAYOUT, NOT THE CAREER (cfg.capBonusToPlayerLevel). capToPlayerLevel stops a
  -- weapon EARNING past its wielder, which does nothing about one that is already past --
  -- carried in from another world, or held by a fresh character. That weapon keeps paying
  -- its full bonus to someone who never earned it. Clamping here instead of at the store
  -- leaves the earned level intact: the weapon still reads Lv80, and the bonus it reports
  -- is the bonus it actually delivers, because the HUD is baked from this same call.
  -- capExtra rides along so +Level Cap % raises this clamp exactly as it raises the other.
  if cfg.capBonusToPlayerLevel then
    local wlv = tonumber(lastWielderLv)
    if wlv and wlv > 0 then
      local lim = wlv + (spec.capExtra or 0)
      if (tonumber(level) or 0) > lim then level = lim end
    end
  end
  local mult = P.multiplier(spec, level, cfg.dmgCurve, cfg.dmgPower)
  -- cfg.dmgMult scales the BONUS portion only: base damage is never reduced,
  -- and the crossover level (where a bonus first exists) is unchanged.
  mult = 1 + (mult - 1) * (tonumber(cfg.dmgMult) or 1)
  if mult < 1 then mult = 1 end
  local base = spec.base or 0
  -- Two damage prestige categories:
  --   pct (+% Damage)   -- multiplies the TOTAL scaled damage by (1+pctPerPt) per point
  --                        (x1.01 each), so it compounds with the level curve.
  --   dmg (+Base Damage) -- adds a FLAT ceil(basePerPt * base) per point, i.e. "1% more
  --                        base damage", level-independent. Rounded up so it's never lost.
  local pctPts  = (spec.prestige and tonumber(spec.prestige.pct)) or 0
  local basePts = (spec.prestige and tonumber(spec.prestige.dmg)) or 0
  -- +Base Damage RAISES THE BASE, and the curve scales the base -- so the points ride the
  -- curve like every other point of base damage does. It used to be added after the
  -- multiplier, which made it a flat +N at every level: worth the same at Lv45 as at Lv80,
  -- and shrinking as a share of the total the whole way up. That contradicted the track's
  -- own name and the reason to spend on it.
  --
  -- `base` below stays VANILLA. It is what the bonus is measured against and what
  -- damage.lua restores to; only the number the curve multiplies moves.
  local effBase = base
  if basePts > 0 and base > 0 then
    effBase = base + basePts * math.ceil(base * (tonumber(cfg.prestigeDamagePerPt) or 0))
  end
  local cur
  if pctPts > 0 and base > 0 then
    cur = math.ceil(effBase * mult * ((1 + (tonumber(cfg.prestigePctPerPt) or 0)) ^ pctPts) - 1e-9)
  else
    cur = math.floor(effBase * mult + 0.5)
  end
  local info = { base = base, cur = cur, bonus = cur - base,
           pct = (base > 0) and math.floor((cur - base) / base * 100 + 0.5) or 0 }
  -- CURVE-PHASE FLAGS. Neither is shown on the HUD any more -- the damage line reads the
  -- number, and the bonus only when there is one, rather than explaining an absence. They
  -- stay because the boot report and crossover-report.txt are built from the same call and
  -- that IS the right place to explain why a weapon is flat.
  --   startsLv   the ladder has not passed this weapon's natural DPS yet; +0% until then
  --   atCeiling  it never will -- natural DPS is at or above the ladder's destination, so
  --              the weapon holds at stock instead of being nerfed down onto the curve.
  -- Both mean "the CURVE pays nothing". Prestige is added afterwards and is indifferent to
  -- either, so atCeiling is gated on there being no bonus at all.
  if cfg.dmgCurve == "target" then
    local x = P.crossover(spec)
    if x and math.ceil(x) > (level or 0) then info.startsLv = math.ceil(x) end
    -- x == false is a DIFFERENT +0%: natural DPS already meets or beats the ladder's
    -- destination, so the weapon holds at stock forever rather than being nerfed down
    -- onto the curve. There is no waypoint to name -- +0% is the final answer at every
    -- level, cap prestige included. Without this flag the HUD is identical to a weapon
    -- that simply has not crossed yet, and the only explanation lives in the boot log's
    -- XOVER line, where nobody reads it.
    -- Only when the +0% is the WHOLE story. Prestige is added after the curve and does
    -- not care that the curve is done with this weapon: +Base Damage and +% Damage both
    -- pay a ceiling weapon exactly as they pay any other, and damage.lua writes
    -- AttackValue on `cur > base` alone. So a prestiged weapon at the ceiling has a real
    -- bonus, and calling it "stock" would be a lie told by its own HUD.
    if x == false and info.bonus <= 0 then info.atCeiling = true end
  end
  return info
end
M.dmgInfoFor = dmgInfoFor

local function magInfoFor(spec, level)
  if not cfg.applyMagazine then return nil end
  if spec.mode ~= "auto" or (spec.magMax or 0) <= (spec.mag or 0) then return nil end
  local now = P.magazine(spec, level, cfg.magFraction, cfg.magStep)
  local nextTarget = math.min(spec.magMax, now + (cfg.magStep or 2))
  local nextIn = (now < spec.magMax) and math.max(0, P.levelForMag(spec, nextTarget, cfg.magFraction) - level) or nil
  -- +Magazine prestige: a flat extra magazine per point, on top of the curve value.
  local pMag = math.floor(((spec.prestige and tonumber(spec.prestige.mag)) or 0) * (tonumber(cfg.prestigeMagPerPt) or 0) + 0.5)
  return { now = now + pMag, base = spec.mag, max = spec.magMax + pMag, bonus = (now + pMag) - spec.mag,
           nextIn = nextIn, nextStep = nextTarget - now }
end
M.magInfoFor = magInfoFor

-- ---- persistence throttle (time-based, like server) ------------------------
local dirty = false
local function persistThrottled() dirty = true end

-- ---- WORLD KEY, RESOLVED LAZILY (1.4.4) ------------------------------------
-- M.start() runs when the mod boots -- at the MAIN MENU, before any world
-- exists -- so A.getWorldId() could only ever return nil there and the key was
-- permanently "default". Two consequences, one cosmetic and one severe:
--   * every world and every server shared ONE progress bucket; and
--   * if the id ever DID resolve at start (late init, a UE4SS reload, joining a
--     server whose save object already exists) the player landed in an EMPTY
--     bucket -- "all my progress reset" -- with the real data stranded under
--     "default". Intermittent and environment-dependent, which is exactly how
--     it was reported (Steam, 2026-07-23).
-- So: resolve once a world is actually loaded, then MIGRATE the legacy
-- "default" bucket into it so no existing progress is stranded. Entries already
-- present under the real id always win (we only fill gaps).
local DEFAULT_KEY = "default"
local function ensureWorldKey()
  if not states then return end
  if not cfg.scopeToServer then return end
  local id = safe(function() return A.getWorldId() end)
  if not id or id == "" or id == DEFAULT_KEY then return end
  if id == worldKey then return end                  -- steady state: cheap no-op
  states[id] = states[id] or {}
  -- Server isolation: do NOT copy legacy default progress into dedicated servers
  worldKey = id
  persistThrottled()
  log(string.format("world -> %s (scoped to server)", id))
end
M.ensureWorldKey = ensureWorldKey

local function refreshDisplay()
  if not (states and worldKey) then return end
  local w = states[worldKey]; if not w then return end
  for id, st in pairs(w) do
    if type(st) == "table" and st.level ~= nil then
      local spec = specFor(id)
      if spec then
        -- NEVER PUT A NON-FINITE NUMBER IN THE HUD -- IT IS PERSISTED (2026-07-28).
        --
        -- P.xpForNext returns math.huge at max level. That is the right SENTINEL in memory: no
        -- xp total ever reaches it, so a maxed weapon can never level again. It is fatal on
        -- disk. store.lua emits an integral number with string.format("%d", v), and
        -- math.floor(inf) == inf, so the guard passes and the call RAISES. serialize() was
        -- wrapped in safe(), which swallowed it and returned nil, and save() treated that as a
        -- silent failure.
        --
        -- Consequence, measured: ONE weapon reaching max level stopped the ENTIRE store saving,
        -- for every weapon in every world, permanently. Mikey's Old Bow hit 80/80 and the store
        -- froze at 2026-07-27 11:53; a day and a half of levelling on every other weapon was
        -- lost, silently, while a 1s flush loop reported success. Found 2026-07-28 from the
        -- STORE SAVE FAILED line the loud-failure rewrite added.
        --
        -- Both HUD consumers already read this as `(h and h.xpNext) or 0` and gate on `> 0`
        -- (main.lua:668, 692), so nil is exactly the value they already handle for "no next
        -- level". tools/test-store.js locks this down at both ends.
        local xpNext = P.xpForNext(spec, st.level, cfg)
        -- the SAME grind addXp charges (P.grindFor), or a prestiged weapon's bar fills at the
        -- raw price and pegs at 100% while the real (grinded) requirement is still unmet
        if type(xpNext) == "number" then xpNext = xpNext * P.grindFor(st.prestige) end
        if type(xpNext) ~= "number" or xpNext ~= xpNext
           or xpNext == math.huge or xpNext == -math.huge then xpNext = nil end
        st.hud = { name = spec.name or id, maxLv = spec.maxLv,
                   xpNext = xpNext,
                   dmg = dmgInfoFor(spec, st.level),
                   mag = magInfoFor(spec, st.level),
                   stars = P.prestigeTotal(st.prestige), prestige = st.prestige }
      end
    end
  end
end
M.refreshDisplay = refreshDisplay

-- The watchdog only complains this often, so a genuinely broken save is loud without a
-- once-a-second flush loop turning the log into noise.
local WATCHDOG_AFTER_SEC, WATCHDOG_REPEAT_SEC = 120, 300
local lastWatchdogWarn = 0

-- Forward-declared: scheduleFlush calls this 270 lines before it is defined, and without this
-- the name would resolve to a nil global and the fold would silently never run.
local migrateScope

local function scheduleFlush()
  ExecuteWithDelay(cfg.saveIntervalMs or 1000, function()
    ensureWorldKey()      -- cheap no-op once resolved; catches the world loading
    -- AND FOLD THE SCOPE HERE TOO. At M.start the bucket is still the pending "default" one, so
    -- a migration run then would re-key the wrong table; the real world only arrives on this
    -- path. Self-guarding (__scope), so it is a table lookup on every flush after the first.
    if migrateScope then pcall(migrateScope) end
    if dirty and not SHADOW then
      refreshDisplay()
      -- CLEAR `dirty` ONLY ON A SUCCESSFUL SAVE (2026-07-28).
      --
      -- This used to set dirty = false BEFORE calling save(), and discard save()'s return value
      -- entirely. So a failed save also forgot that anything needed saving -- the change was
      -- dropped on the floor and the next tick had nothing to retry. Combined with a serializer
      -- that failed silently, that is how 36 hours of levelling disappeared while the loop
      -- "saved" about 130,000 times. Staying dirty means every subsequent tick retries, so a
      -- transient failure (a file lock, an antivirus scan) now heals itself.
      local ok, saved = pcall(function() return store:save() end)
      if ok and saved then dirty = false end
    end
    -- Ride the store's own flush rather than adding a timer. adapters keeps its own
    -- dirty flag, so this is a no-op on every tick that saw no new species+level --
    -- which is nearly all of them once a session has warmed up.
    -- retries until the exp database resolves, then never again (it self-latches)
    pcall(function() A.sweepDropCurve() end)
    pcall(function() A.flushDropExp() end)
    -- WATCHDOG. The failure this exists for wrote nothing at all, so the only evidence was a
    -- file mtime that stopped moving. Nothing was watching it.
    if dirty and not SHADOW then
      local stale = 0
      pcall(function() stale = store:secondsSinceSave() end)
      if stale >= WATCHDOG_AFTER_SEC and (stale - lastWatchdogWarn) >= WATCHDOG_REPEAT_SEC then
        lastWatchdogWarn = stale
        log(string.format("WARNING: nothing has saved for %d seconds and there ARE unsaved "
          .. "changes. Your weapon levels are being written to the recovery journal and will be "
          .. "restored on the next launch, but something is wrong with the save file -- please "
          .. "report this with your UE4SS.log.", stale))
      end
    end
    scheduleFlush()
  end)
end

-- ---- XP grant (grantRangedXp) ----------------------------------------------
-- EARN ON FIRE, NOT ON HIT -- for weapons whose projectile hits could not be attributed.
--
-- DroneLauncher LEFT THIS LIST 2026-08-19. It was here for the usual reason: a launcher's
-- damage arrives from something that is not the weapon, and until AttackStaticItemID was read
-- there was no way to tell those hits from the held gun's. So hits were discarded and the
-- trigger pull was supposed to pay instead -- except the fire hook never caught a drone DEPLOY
-- either, so both paths were dead and the weapon earned nothing at all, ever.
--
-- Attribution now names the source outright: 251 drone hits in one engagement, every one read
-- asid=DroneLauncher while a Vortex Beater was held. A drone launcher's damage IS its drones,
-- so hits are the honest basis and they are finally countable. The rest of the list stays --
-- nothing has measured whether a rocket's blast carries its launcher's id.
local FIRE_XP_TYPES = { RocketLauncher = true, MissileLauncher = true, GrenadeLauncher = true,
                        Grenade = true }

local function targetScale(target)
  local ts = cfg.targetScaling
  if not (ts and ts.enabled) then return 1, nil end
  if not target then return 1, nil end
  local drop = A.targetDropExp(target)
  if not drop then return (ts.nonPalXp or 0), nil end
  local m = drop / (ts.refDropExp or 60)      -- fallbacks match the calibrated config defaults so a
  if m < (ts.min or 0.02) then m = ts.min or 0.02 end   -- PARTIAL user override can't silently restore the
  if m > (ts.max or 8.0)  then m = ts.max or 8.0 end    -- old mercy-farming values (300 / 0.25)
  return m, drop
end

-- MULTI-PELLET DEDUPE. MakeDamageInfo fires per landed hit; a shotgun blast is
-- several pellet-hits in the SAME engine frame. cfg.pelletDedupeMs collapses
-- same-instance events inside that window to ONE counted hit, and multiplies the
-- grant by spec.proj so the TOTAL xp still equals the server's per-pellet model
-- (per-pellet 1/hps summed over proj == one shot at proj/hps). Only weapons with
-- proj>1 dedupe; proj==1 (bows, autos, snipers) are per-event, so a fast AR --
-- rounds ~113ms apart -- is never merged. Default 60ms catches a pellet spread
-- (<16ms) with wide margin.
local lastHitMs = {}
local function nowMs() return (safe(function() return os.clock() end) or 0) * 1000 end

-- SANITY CAP (Maiq, 2026-08-08: "measured weapons aren't earning xp far beyond what
-- they're normally capable of according to their HPS"). A MEASURED rate is a capability
-- ceiling: hit credits arriving far above it are misattribution, not skill -- the swarm
-- poured rifle-typed hits into the Vortex Beater's record for days before routing
-- existed, and nothing noticed. Token bucket per key: refills at hps x sanityHpsFactor
-- (default 3 -- burst legitimately outruns the reload-averaged sustained rate), holds
-- 10 seconds of burst. Hits beyond the budget are OBSERVED but not EARNED. Only a
-- measured claim caps ("meas"/"family"); estimates prove nothing and pass free. Dedupe
-- runs FIRST (it removes event duplication; this removes attribution excess).
local SANITY = {}   -- id -> { tk, at, dropped }
local function sanityAllows(id, spec, cost)
  if cfg.sanityHps == false then return true end
  local hps = tonumber(spec.hps)
  if not hps or hps <= 0 then return true end
  local mw = wdLookup(id)
  local src = mw and mw.hpsSrc
  if src ~= "meas" and src ~= "family" then return true end
  local rate = hps * (tonumber(cfg.sanityHpsFactor) or 3)
  local cap = rate * 10
  local now = safe(function() return os.clock() end) or 0
  local s = SANITY[id]
  if not s then s = { tk = cap, at = now, dropped = 0 }; SANITY[id] = s end
  s.tk = math.min(cap, s.tk + (now - s.at) * rate); s.at = now
  if s.tk >= cost then s.tk = s.tk - cost; return true end
  s.dropped = s.dropped + cost
  if s.dropped == cost or s.dropped % 500 < cost then
    -- OBSERVE, DO NOT CONFISCATE (2026-08-19). This cap was built for one thing: the swarm
    -- pouring rifle-typed hits into the Vortex Beater's record before routing existed. In every
    -- archived session it ever fired -- 4 times, all on YakushimaGun001_4, all 2026-08-18 -- that
    -- IS what it caught. Attribution now reads the attack's own source item, so that cause is
    -- gone and the false positives with it.
    --
    -- Which inverts what a firing MEANS, and therefore what to do about it. It used to be routine
    -- and the right response was to discard. Now it can only be a real anomaly -- a double-count
    -- regression, a wrong measurement, or a damage source nothing has attributed yet -- and
    -- silently eating a player's progress is the wrong answer to all three. So it reports and
    -- lets the xp through. sanityHpsEnforce = true restores confiscation.
    print(string.format("[Arsenal][SANITY] %s credited beyond its measured rate "
      .. "(%.2f hps x%d headroom) -- %d excess hit(s)%s. Attribution is by source item now, so "
      .. "this is NOT swarm misattribution: suspect a double-count or a stale hps measurement.\n",
      staticOf(id), hps, tonumber(cfg.sanityHpsFactor) or 3, s.dropped,
      (cfg.sanityHpsEnforce == true) and " not earned" or " still earned (reporting only)"))
  end
  return cfg.sanityHpsEnforce ~= true
end

-- The newest wielder level seen (hit path or the tick's explicit pass) -- feeds prestigeGate.
-- DECLARED ABOVE ITS WRITER: first landed below grantRangedXp, where the assignment silently
-- compiled as a GLOBAL write and the local the gate reads stayed nil forever (the deleted-local
-- trap's forward-declaration cousin; fwdref-check only sees calls, not writes).

local function grantRangedXp(id, spec, tag, target, holderLevel, via)
  -- remember the wielder's level for the prestige gate (see prestigeGate) -- the hit path
  -- is the one place a fresh, already-read level flows through with no extra native reads
  if type(holderLevel) == "number" and holderLevel > 0 then lastWielderLv = holderLevel end
  local w = states[worldKey]
  local st = w[id]; if not st then st = P.newState(spec); w[id] = st end

  local proj = tonumber(spec.proj) or 1
  local dedMs = tonumber(cfg.pelletDedupeMs) or 0
  local pelletMult = 1
  if proj > 1 and dedMs > 0 then
    local t = nowMs()
    local prevT = lastHitMs[id]
    if prevT and (t - prevT) < dedMs then
      if SHADOW then log(string.format("SHADOW %s pellet within %.0fms -> DEDUPED (proj=%d)", staticOf(id), t - prevT, proj)) end
      return
    end
    lastHitMs[id] = t
    pelletMult = proj
  elseif spec.mode == "melee" and dedMs > 0 and via ~= "mk" then
    -- MELEE EVENT DEDUPE (2026-08-05, Maiq's Nightglow catch: "it only releases 3 at a time").
    -- The reaction path delivers DUPLICATED events -- measured clusters of up to 43 arrivals
    -- inside 40ms from a 3-bolt volley, and the pellet dedupe deliberately skipped melee
    -- (proj==1), so every duplicate EARNED. Same window, same mechanism, no multiplier:
    -- one grant per <dedMs cluster is one real hit. This is why Nightglow read 36.7 hits/s
    -- when physics says 3-6 -- the instrument and the earner shared the same blindness.
    --
    -- via ~= "mk" (2026-08-08, the Terraprisma "3 bosses, no level" report): events from
    -- the MakeDamageInfo hook are REAL DISTINCT hits -- that hook does not duplicate --
    -- and the swarm's routed hits arrive there at the same measured rate its 103.4 hps
    -- divisor is built from. Cluster-deduping them was a DOUBLE correction: the divisor
    -- assumed hits are counted at the measured rate while the dedupe collapsed them to
    -- at most one per 60ms, so the blade earned ~1% of a gun's per-second rate. Only
    -- the reaction path ("rx") dedupes; measured basis and counted basis now match.
    local t = nowMs()
    local prevT = lastHitMs[id]
    if prevT and (t - prevT) < dedMs then
      if SHADOW then log(string.format("SHADOW %s melee dup within %.0fms -> DEDUPED", staticOf(id), t - prevT)) end
      return
    end
    lastHitMs[id] = t
  end

  -- sanity cap: hits beyond the measured-rate budget are observed, not earned.
  -- cost = pelletMult, because hps already folds proj in (one shotgun grant = proj hits).
  if not sanityAllows(id, spec, pelletMult) then return end

  st.hits = (st.hits or 0) + 1

  local xpMult = 1
  local hps = spec.hps
  if type(hps) == "number" and hps > 0 then xpMult = 1 / hps
  elseif spec.type == "Shotgun" then xpMult = cfg.shotgunXpMult or 1 end
  if FIRE_XP_TYPES[spec.type] then xpMult = cfg.launcherXpMult or 1 end
  -- xpTune: per-weapon pacing correction (2026-08-09, the Terraprisma). Its 103.4 hps
  -- divisor is the DUMMY-PARKED peak (nine swords all connecting); real combat lands
  -- about a third of that (measured 3.7 hits/s across boss-fight windows, 08-08 logs),
  -- so per-second earnings ran ~1/3 of a gun's. xpTune=3 on its rows compensates the
  -- divisor's overstatement -- a throughput correction, not a buff -- while hps itself
  -- stays the true peak (the sanity cap's basis must remain the measured ceiling).
  xpMult = xpMult * (tonumber(spec.xpTune) or 1)
  xpMult = xpMult * pelletMult

  -- only the legacy path uses this, and it costs a second cached drop-exp lookup
  local tScale = (not (cfg.useDropCurve and A.dropCurve)) and targetScale(target) or 1

  local capLv = nil
  if cfg.capToPlayerLevel and type(holderLevel) == "number" then
    capLv = holderLevel + (spec.capExtra or 0)   -- +Level Cap % lets a weapon climb past the wielder clamp
    if st.level >= capLv then
      -- SAY SO (2026-08-11). This return threw the hit's XP away in silence, and it is the
      -- most common way a weapon legitimately "stops levelling" -- indistinguishable from the
      -- mod being broken unless the log names the setting that did it. Once per key, the same
      -- pattern as UNKNOWN WEAPON above: the discard repeats on every hit forever.
      if not CAPPED_LOGGED[id] then
        CAPPED_LOGGED[id] = true
        log(string.format("CAPPED %s is Lv%d and \"Cap to player level\" holds it at your level "
          .. "(%d%s) -- XP from these hits is discarded. Level up, or turn that setting off.",
          staticOf(id), st.level, capLv,
          ((spec.capExtra or 0) > 0) and string.format(" = %d + %d from +Level Cap",
            holderLevel, spec.capExtra) or ""))
      end
      return
    end
    CAPPED_LOGGED[id] = nil   -- back under the cap: earning again, and worth saying again
  end

  local before = st.level
  -- THE GRANT. Under the drop curve, xp is the target's OWN exp divided by fire rate, so a
  -- second of fire pays what the thing is worth -- no reference constant, no clamp. tScale
  -- keeps its old meaning on the legacy path, and still carries the "no exp value -> no xp"
  -- rule (scenery, buildings, dummies) that stops free grinding either way.
  local grant
  if cfg.useDropCurve and A.dropCurve then
    local raw = A.targetDropExp(target)
    -- x the world's ExpRate: the table value is RAW, and the game applies the rate at the
    -- grant. Without this a 0.2x server levels weapons five times faster than their wielder.
    grant = (type(raw) == "number" and raw > 0) and (raw * xpMult * A.serverExpRate()) or 0
  else
    grant = cfg.xpPerHit * xpMult * tScale
  end
  local ups = P.addXp(st, grant * (tonumber(cfg.xpMult) or 1), spec, cfg, capLv)
  for _, lvl in ipairs(ups) do
    log(string.format("LEVELUP %s (%s) -> Lv%d/%d [%s] hits=%d", staticOf(id), spec.type, lvl, spec.maxLv, tag, st.hits))
    -- QUEUED, NOT TOASTED HERE. This is the damage hook; drawing from it is the 2026-08-12
    -- CTD family (native UI work off the game thread). main.lua drains this on its own tick,
    -- which is already the game-thread-safe place, and toasts whatever it finds.
    --
    -- It exists at all because the toast used to be driven from the EQUIPPED weapon's row:
    -- a Drone Launcher does its damage while you are holding something else, so its career
    -- levelled in silence. Announcing the weapon that LEVELLED rather than the one in hand
    -- is the same correction the attribution work made in 2.0.3.
    M.levelUps[#M.levelUps + 1] = { name = spec.name or staticOf(id), level = lvl,
                                    maxLv = spec.maxLv, key = id }
  end
  -- WRITE-AHEAD: a level exists on disk BEFORE the store is asked to hold it.
  --
  -- The recovery that worked on 2026-07-28 came from the UE4SS log -- an accidental journal that
  -- ships to nobody and does not even carry the per-instance GUID, so two of the same model are
  -- indistinguishable in it (`staticOf(id)`, not `id`). This appends the FULL key, so a heal can
  -- name the exact weapon. One line, append-only: it cannot fail the way serialize() did.
  if #ups > 0 and not SHADOW then
    pcall(function() store:journalAppend(worldKey, id, st.level, st.xp, st.hits) end)
  end
  if SHADOW then
    -- one validation session: prove the hook fires once per hit and levels track.
    -- The in-memory mutation is fine; scheduleFlush never SAVES in shadow, so
    -- nothing reaches disk and going live later starts from the real stored file.
    log(string.format("SHADOW %s %s hit -> xp+%.3f (x%.2f/hps) lvl=%d%s hits=%d (NOT persisted)",
      staticOf(id), tag, cfg.xpPerHit * xpMult * tScale, xpMult, st.level,
      (#ups > 0) and (" was Lv"..before) or "", st.hits))
  end
  persistThrottled()
end

-- weapon-activity clock: EVERY shot (installFire fires per trigger pull for any
-- resolvable gun) and every landed hit bumps it, BEFORE the xp-type early-outs.
-- main.lua's panel idle-fade reads it.
local lastActivityClock = 0

local function onDamage(id, target, holderLevel, dmg, via)
  if not id then return end
  lastActivityClock = os.clock()
  -- MEASUREMENT RUNS BEFORE THE APPLICABILITY GATE (2026-07-29). This sat AFTER
  --     local spec = specFor(id); if not spec then return end
  -- and specFor() returns nil for any weapon skipUntestedWeapons is holding back -- which is
  -- every weapon with hpsSrc="est". So the mod refused to measure a weapon BECAUSE it was
  -- unmeasured: the only way out of "est" was blocked by being in "est". Mikey hit this trying
  -- to time the Primitive Sword -- 12 MELDBG hits landed on Univolts, hooks confirmed
  -- installed, and not one SWING line.
  --
  -- Ranged never had the problem because [SHOT] is logged in adapters.lua's fire hook, which
  -- runs before any spec lookup. That asymmetry is why the Three Shot Bow measured fine on the
  -- same evening the sword could not.
  --
  -- isApplicable answers "should we APPLY the damage curve" -- a safety gate, and correct. It
  -- must not also answer "should we OBSERVE this weapon". Observation is read-only and changes
  -- nothing about the player's damage.
  if cfg.measureHps then
    local mw = wdLookup(id)
    -- mode, not spec.src: spec may legitimately not exist here. weapondata's own field is what
    -- decides which hook counted this hit (see tools/pathway-check.js).
    if mw and mw.mode == "melee" then
      print("[Arsenal][SWING] " .. tostring(id) .. "\n")
    end
  end
  local spec = specFor(id); if not spec then return end
  if FIRE_XP_TYPES[spec.type] then return end   -- launchers earn on fire, not hit
  grantRangedXp(id, spec, (spec.src == "ranged") and "hit" or "melee", target, holderLevel, via)
end

-- launchers: XP on trigger pull (onFire), local player only via installFire's
-- own equipped-weapon resolution (already this client's shooter)
local function onFire(id)
  if not id then return end
  lastActivityClock = os.clock()
  local spec = specFor(id); if not spec then return end
  if spec.src ~= "ranged" or not FIRE_XP_TYPES[spec.type] then return end
  grantRangedXp(id, spec, "fire")
end

-- ---- public: HUD/damage read the store through these -----------------------
function M.rowFor(key)
  if not (states and key) then return nil end
  local w = states[worldKey]; return w and w[key] or nil
end
function M.worldKey() return worldKey end
function M.states() return states end
function M.lastActivity() return lastActivityClock end

-- ---- PRESTIGE --------------------------------------------------------------
-- Which prestige categories a weapon's FAMILY can bank into. Auto-derived
-- (magazine only where the weapon actually grows one -- same gate as magInfoFor,
-- so bows/melee never offer it), then masked by cfg.prestigeByFamily[spec.type].
function M.prestigeAllowed(key, spec)
  spec = spec or specFor(key)
  local a = { dmg = true, pct = true, dur = true, cap = true, mag = false, grp = false }
  if spec then
    if spec.mode == "auto" and (spec.magMax or 0) > (spec.mag or 0) then a.mag = true end
    -- +Grouping: recoil scaling -- any non-melee weapon. Weapons whose actor carries zero
    -- recoil (some bows) accept the point but the write skips harmlessly; damage.lua only
    -- scales fields that read back as positive numbers.
    if spec.mode ~= "melee" then a.grp = true end
    local fam = cfg.prestigeByFamily and cfg.prestigeByFamily[spec.type]
    if type(fam) == "table" then
      for k, v in pairs(fam) do a[k] = v and true or false end
    end
  end
  return a
end

-- The level a weapon must REACH to be eligible to prestige. Either the weapon's
-- true max (prestigeRequireMaxLevel), or prestigeMinClimb levels above its base --
-- clamped to the max so it is always reachable.
--
-- AND AT LEAST THE WIELDER'S LEVEL (Maiq's design call, 2026-08-04): his handgun flagged
-- "ready" at 43 while he was 49 -- start(28)+15 alone is too early once the player outlevels
-- the climb. The gun must catch up to its wielder first. Reachable by construction:
-- capToPlayerLevel lets a weapon earn to wielder level (+capExtra). The wielder level comes
-- from the caller when it has one (the tick passes it explicitly); otherwise the newest level
-- seen on the hit path is used (lastWielderLv, declared at file scope above both its writer and its readers);
-- with neither, the old gate stands rather than bricking prestige on a failed read.
local function prestigeGate(spec, wielderLv)
  local maxLv = spec.maxLv or 80
  local base
  if cfg.prestigeRequireMaxLevel then base = maxLv
  else base = math.min(maxLv, (tonumber(spec.start) or 0) + (tonumber(cfg.prestigeMinClimb) or 15)) end
  local wlv = tonumber(wielderLv) or lastWielderLv
  if type(wlv) == "number" and wlv > 0 then
    base = math.min(maxLv, math.max(base, math.floor(wlv)))
  end
  return base
end

-- Bank one prestige point of `stat` (dmg/mag/dur/cap) into `key`, if it is at its
-- effective cap and the stat is allowed for its family. Resets level to start;
-- points are permanent (see progression.lua). Returns (ok, starsOrWhy, name).
function M.prestige(key, stat, wielderLv)
  if not (states and worldKey and key and stat) then return false, "no weapon" end
  local st = states[worldKey] and states[worldKey][key]
  if not (type(st) == "table" and st.level ~= nil) then return false, "no progress on this weapon" end
  local spec = specFor(key); if not spec then return false, "weapon not tracked" end
  if not M.prestigeAllowed(key, spec)[stat] then return false, stat .. " not available for this weapon" end
  if st.level < prestigeGate(spec, wielderLv) then return false, "not leveled enough yet" end
  st.prestige = st.prestige or { dmg = 0, mag = 0, dur = 0, cap = 0 }
  st.prestige[stat] = (tonumber(st.prestige[stat]) or 0) + 1
  st.level = tonumber(spec.start) or 0
  st.xp = 0
  M.markDirty()
  local total = P.prestigeTotal(st.prestige)
  log(string.format("PRESTIGE %s +%s -> stars=%d, level reset to %d", staticOf(key), stat, total, st.level))
  return true, total, spec.name or key
end

-- One-call snapshot for the Prestige panel (published to the shared bridge file
-- by main.lua). nil if the weapon isn't tracked.
function M.prestigeStatus(key, wielderLv)
  local spec = specFor(key); if not spec then return nil end
  local st = states[worldKey] and states[worldKey][key]
  local level = (st and st.level) or (tonumber(spec.start) or 0)
  local need = prestigeGate(spec, wielderLv)
  local a, allowed = M.prestigeAllowed(key, spec), {}
  for _, k in ipairs({ "dmg", "pct", "mag", "dur", "cap" }) do if a[k] then allowed[#allowed + 1] = k end end
  return { eligible = level >= need, weapon = key, name = spec.name or key,
           stars = P.prestigeTotal(st and st.prestige), level = level, need = need, allowed = allowed,
           summary = M.prestigeSummary(key), previews = M.prestigePreview(key) }
end

-- CUMULATIVE PRESTIGE BENEFITS, one compact line (Maiq, 2026-08-07: "show what the benefits
-- of your prestige levels are" -- on the aim tile and at the top of the menu panel). Computed
-- HERE, beside the apply math above, with the same per-point config values and the same
-- rounding -- never from the hud snapshot (the documented stale-after-retune trap). Only
-- tracks with banked points appear; a weapon with no prestige returns nil and costs nothing.
--   dmg -- flat, pts * ceil(base * perPt), exactly the dmgInfoFor addition
--   pct -- compounding, ((1+perPt)^pts - 1) shown as a rounded percent
--   mag -- flat rounds, the magInfoFor addition
--   dur -- linear percent of MaxDurability (damage.lua's application)
--   cap -- extra LEVELS, read from spec.capExtra (specFor already computed the exact value)
function M.prestigeSummary(key)
  local spec = specFor(key); if not spec then return nil end
  local st = states[worldKey] and states[worldKey][key]
  local p = st and st.prestige
  if type(p) ~= "table" then return nil end
  local total = P.prestigeTotal(p)
  if (tonumber(total) or 0) <= 0 then return nil end
  local base = tonumber(spec.base) or 0
  local parts = {}
  local dmgPts = tonumber(p.dmg) or 0
  if dmgPts > 0 and base > 0 then
    parts[#parts + 1] = string.format("+%d dmg", dmgPts * math.ceil(base * (tonumber(cfg.prestigeDamagePerPt) or 0)))
  end
  local pctPts = tonumber(p.pct) or 0
  if pctPts > 0 then
    local mult = (1 + (tonumber(cfg.prestigePctPerPt) or 0)) ^ pctPts
    parts[#parts + 1] = string.format("+%d%% dmg", math.floor((mult - 1) * 100 + 0.5))
  end
  local magPts = tonumber(p.mag) or 0
  if magPts > 0 then
    local rounds = math.floor(magPts * (tonumber(cfg.prestigeMagPerPt) or 0) + 0.5)
    if rounds > 0 then parts[#parts + 1] = string.format("+%d mag", rounds) end
  end
  local durPts = tonumber(p.dur) or 0
  if durPts > 0 then
    parts[#parts + 1] = string.format("+%d%% dur", math.floor(durPts * (tonumber(cfg.prestigeDurPerPt) or 0) * 100 + 0.5))
  end
  if (tonumber(p.cap) or 0) > 0 and (tonumber(spec.capExtra) or 0) > 0 then
    parts[#parts + 1] = string.format("+%d cap", spec.capExtra)
  end
  local grpPts = tonumber(p.grp) or 0
  if grpPts > 0 then
    local m = (1 - (tonumber(cfg.prestigeGroupingPerPt) or 0.05)) ^ grpPts
    if m < 0.4 then m = 0.4 end
    parts[#parts + 1] = string.format("-%d%% recoil", math.floor((1 - m) * 100 + 0.5))
  end
  if #parts == 0 then return nil end
  return string.format("\226\152\133%d   %s", total, table.concat(parts, "   "))
end

-- PER-STAT PREVIEW for the Prestige panel (Maiq, 2026-08-07: "going from what currently,
-- to what if this option is selected"). One short "cur -> next" string per ALLOWED stat,
-- from the same cfg per-point values the apply paths use. Deliberately shows the CUMULATIVE
-- track value moving, not the post-reset damage number -- prestige resets the level, so a
-- raw before/after damage figure would honestly read as a LOSS and bury the permanent gain.
function M.prestigePreview(key)
  local spec = specFor(key); if not spec then return nil end
  local st = states[worldKey] and states[worldKey][key]
  local p = (st and type(st.prestige) == "table") and st.prestige or {}
  local base = tonumber(spec.base) or 0
  local out = {}
  local dmgPer = math.ceil(base * (tonumber(cfg.prestigeDamagePerPt) or 0))
  if base > 0 and dmgPer > 0 then
    -- scaled by the same curve multiplier the points actually get, so the preview and
    -- the damage number the player then sees agree. A raw +N would understate both.
    local m = P.multiplier(spec, (st and st.level) or spec.start or 0, cfg.dmgCurve, cfg.dmgPower)
    if type(m) ~= "number" or m < 1 then m = 1 end
    local pts = tonumber(p.dmg) or 0
    out.dmg = string.format("+%d \226\134\146 +%d",
      math.floor(pts * dmgPer * m + 0.5), math.floor((pts + 1) * dmgPer * m + 0.5))
  end
  local pctPer = tonumber(cfg.prestigePctPerPt) or 0
  if pctPer > 0 then
    local pts = tonumber(p.pct) or 0
    local curM, nxtM = (1 + pctPer) ^ pts, (1 + pctPer) ^ (pts + 1)
    out.pct = string.format("+%d%% \226\134\146 +%d%%",
      math.floor((curM - 1) * 100 + 0.5), math.floor((nxtM - 1) * 100 + 0.5))
  end
  local magPer = tonumber(cfg.prestigeMagPerPt) or 0
  if magPer > 0 and spec.mode == "auto" then
    local pts = tonumber(p.mag) or 0
    out.mag = string.format("+%d \226\134\146 +%d",
      math.floor(pts * magPer + 0.5), math.floor((pts + 1) * magPer + 0.5))
  end
  local durPer = tonumber(cfg.prestigeDurPerPt) or 0
  if durPer > 0 then
    local pts = tonumber(p.dur) or 0
    out.dur = string.format("+%d%% \226\134\146 +%d%%",
      math.floor(pts * durPer * 100 + 0.5), math.floor((pts + 1) * durPer * 100 + 0.5))
  end
  local capStep = tonumber(cfg.prestigeCapStepPct) or 0
  if capStep > 0 then
    -- spec.maxLv already carries capExtra for banked points (specFor adds it), so recover
    -- the ORIGINAL ceiling first -- previewing from the raised value would double-count.
    local pts = tonumber(p.cap) or 0
    local baseMax = (tonumber(spec.maxLv) or 80) - (tonumber(spec.capExtra) or 0)
    -- same rounding as specFor's capExtra: floor(baseMax * step * pts + 0.5)
    out.cap = string.format("+%d \226\134\146 +%d lv",
      math.floor(baseMax * capStep * pts + 0.5), math.floor(baseMax * capStep * (pts + 1) + 0.5))
  end
  local grpPer = tonumber(cfg.prestigeGroupingPerPt) or 0.05
  if grpPer > 0 then
    local pts = tonumber(p.grp) or 0
    local cm, nm = (1 - grpPer) ^ pts, (1 - grpPer) ^ (pts + 1)
    if cm < 0.4 then cm = 0.4 end
    if nm < 0.4 then nm = 0.4 end
    out.grp = string.format("-%d%% \226\134\146 -%d%% recoil",
      math.floor((1 - cm) * 100 + 0.5), math.floor((1 - nm) * 100 + 0.5))
  end
  return out
end
-- damage.lua stashes its persisted durability base into the store row and marks
-- dirty so the flush loop saves it (poison-free base source; see damage.lua).
function M.markDirty() persistThrottled() end

-- SWARM KEY (2026-08-08): the swarm-attribution router's Terraprisma key, persisted as
-- a top-level meta field so an arm survives relaunch (the summons outlive the session
-- from the router's point of view -- an unarmed relaunch sent 731 swarm hits to the
-- M.swarmKey is GONE (2026-08-19). It persisted the swarm router's armed key so an arm survived
-- a relaunch. There is no armed state any more: attribution reads AttackStaticItemID off the
-- damage itself. Existing stores keep a stale __swarmKey at top level; it is inert and costs a
-- few bytes, so it is left alone rather than migrated.

-- ---- SCOPE MIGRATION -------------------------------------------------------
-- Switching "Progression scope" RE-KEYS the store: instance records are "Model@GUID", model
-- records are bare "Model". Nothing carried the old career across, so flipping to "All copies
-- share" made every weapon read as brand new and fall back to its tech start level -- a Legendary
-- handgun at Lv40 with 363 hits showed up as Lv28 (reported 2026-07-29).
--
-- The switch IS the migration now: this runs at load, sees that the store is keyed for the other
-- scope, and folds the records forward. Highest wins on every field, per Mikey's rule -- "if there
-- are two records for two different weapons, pick the higher of the two".
--
-- THE OLD RECORDS ARE KEPT, never deleted. That is what makes this reversible: switching back to
-- "Each weapon its own" finds the per-instance careers exactly where they were. It also means the
-- merge can safely run again -- max() cannot lower anything it has already raised.
local function mergeInto(dst, src)
  if type(src) ~= "table" then return dst end
  if type(dst) ~= "table" then return src end
  for _, f in ipairs({ "level", "xp", "hits" }) do
    local a, b = tonumber(dst[f]) or 0, tonumber(src[f]) or 0
    if b > a then dst[f] = b end
  end
  -- prestige is per STAT: a family that banked dmg on one copy and mag on another keeps both,
  -- which is what "higher of the two" means applied field by field.
  if type(src.prestige) == "table" then
    dst.prestige = dst.prestige or {}
    for stat, v in pairs(src.prestige) do
      local cur = tonumber(dst.prestige[stat]) or 0
      if (tonumber(v) or 0) > cur then dst.prestige[stat] = v end
    end
  end
  -- the HUD block is a cache of the winning record; take it from whichever ended up on top
  if src.hud and (tonumber(src.level) or 0) >= (tonumber(dst.level) or 0) then dst.hud = src.hud end
  return dst
end

-- Bump when the fold logic itself changes, so a store stamped by an older (buggier) fold is
-- re-folded rather than trusted.
local FOLD_REV = 2

migrateScope = function()
  local w = states and states[worldKey]
  if type(w) ~= "table" then return end
  local want = cfg.progressScope
  if want ~= "model" and want ~= "family" then want = "instance" end
  -- REVISIONED, not just scoped. The first fold shipped a loop that added keys to `w` while
  -- iterating it with pairs -- undefined in Lua -- so it folded some records and skipped others,
  -- then stamped __scope and permanently blocked itself from ever running again. A Legendary
  -- handgun sat at 28 with its 40 still sitting in the @GUID record beside it. Bumping FOLD_REV
  -- re-runs the corrected fold exactly once; max() means a re-run can never lower anything.
  if w.__scope == want and w.__scopeRev == FOLD_REV then return end
  -- TELL THE PLAYER, AT THE MOMENT IT HAPPENS (2026-08-13). The setting's help already explains
  -- that a switch is non-destructive -- but help is read before a decision, and this reads like
  -- data loss AFTER one: levels and stars appear to drop the next time you look at a weapon.
  -- Nightcodex reported it as "scope-switch resets prestige without warning" (Steam, 2026-08-02).
  -- He was not wrong about the experience; only about the cause.
  -- `prev` is nil on a first run and equal to `want` on a FOLD_REV re-run, so only a REAL switch
  -- is announced -- a re-fold is bookkeeping and says nothing.
  local prev = w.__scope
  local realSwitch = (type(prev) == "string" and prev ~= want)
  local moved, folded = 0, 0
  if want == "model" or want == "family" then
    -- Collect first, THEN write: adding keys to `w` while iterating it is undefined in Lua.
    local todo = {}
    for key, st in pairs(w) do
      if type(st) == "table" and st.level ~= nil then
        local target = (want == "family") and ("fam:" .. A.familyOf(staticOf(key)))
                                          or staticOf(key)
        -- a record already living under its own target key has nothing to fold
        if target ~= key then todo[#todo + 1] = { target = target, st = st } end
      end
    end
    for _, item in ipairs(todo) do
      if w[item.target] then folded = folded + 1 else w[item.target] = { level = 0 } end
      w[item.target] = mergeInto(w[item.target], item.st)
      moved = moved + 1
    end
  end
  -- instance <- model needs no work: the per-instance records were never removed, so flipping
  -- back simply starts reading them again.
  w.__scope, w.__scopeRev = want, FOLD_REV
  -- THE FOLD NEVER MARKED THE STORE DIRTY (found 2026-08-11, and it is the whole reason
  -- switching scope "loses" prestige in reports). Everything above happens in memory, so
  -- without this the folded rows sat unsaved AND -- because the flush loop only calls
  -- refreshDisplay() when dirty -- every st.hud stayed the pre-fold cache: the panel showed
  -- level 0 and zero stars for a career that had in fact been carried forward, until the
  -- first hit on that weapon marked the store dirty and repaired the display. A player
  -- reading a HUD that says his prestige is gone reports that his prestige is gone.
  persistThrottled()
  if moved > 0 then
    log(string.format("SCOPE MIGRATION -> %s: folded %d per-instance record(s) into %d model "
      .. "key(s) (highest level/xp/hits/prestige wins; the originals are kept, so switching "
      .. "back restores them)", want, moved, folded))
  else
    log(string.format("scope = %s (nothing to migrate)", want))
  end
  -- HAND THE NOTICE UP. This module has no toast channel (Toast lives in main.lua), so the
  -- switch is parked here and main.lua raises it once the boot stand-down is over and a toast
  -- can actually be seen. A notice nobody can see is the same failure as the silent fold above.
  if realSwitch then
    local NAMES = { instance = "Each weapon its own", model = "All copies share",
                    family = "All rarities share" }
    M.scopeNotice = {
      from = prev, to = want, moved = moved, folded = folded,
      text = string.format(
        "Progression scope is now \"%s\". %s Nothing was deleted -- your old records are kept, "
        .. "and switching back restores them. Where copies merged, the HIGHEST value wins each "
        .. "stat, so stars do not add up.",
        NAMES[want] or want,
        (moved > 0)
          and string.format("%d weapon record(s) merged into %d.", moved, folded)
          or "No records needed merging."),
    }
  end
end
M.migrateScope = migrateScope

function M.start(opts)
  -- progression needs the drop curve, and it only has cfg. Hand it the adapters table
  -- rather than duplicating the lookup: one owner of the curve, one place it can be wrong.
  cfg._adapters = A
  store = opts.store
  SHADOW = opts.shadow and true or false
  cfg.shadowCount = SHADOW
  pcall(function() store:load() end)
  states = store.data or { __version = "wpv2" }
  store.data = states
  -- worldKey stays the PENDING "default" bucket until a world actually exists.
  -- At mod boot that is always the case (main menu), so resolving here could only
  -- ever yield "default" -- see ensureWorldKey, which adopts the real id and
  -- migrates this bucket into it on the first flush after the world loads.
  worldKey = DEFAULT_KEY
  if not states[worldKey] then states[worldKey] = {} end
  ensureWorldKey()   -- covers a UE4SS reload, where a world may already be up
  pcall(migrateScope)   -- the scope switch folds the old careers forward, right here

  -- THE RARITY'S HOME IS THE CAREER RECORD (2026-08-19). counting owns the store, so it owns
  -- both directions: the in-hand path records the model here, and every record-only reader --
  -- the boot report, the HUD of a stowed weapon -- reads it back from the same place. There is
  -- no cache between them and nothing to seed, so there is no window at boot where the answer
  -- is missing: the store was loaded above, which is earlier than anything can ask.
  --
  -- The version this replaces kept an in-memory map that started empty every boot, priced the
  -- career from the family root -- the grade-1 Common -- until the weapon was next equipped, and
  -- cached that figure into st.hud for the session.
  A.modelSink = function(key, model)
    local w = states[worldKey]
    local st = w and w[key]
    if type(st) ~= "table" or st.model == model then return end
    st.model = model
    -- The cached display block was priced off the previous model. Marking the store dirty is
    -- what makes the flush loop call refreshDisplay and rebuild it.
    persistThrottled()
  end
  A.modelResolver = function(key)
    local w = states[worldKey]
    local st = w and w[key]
    if type(st) == "table" and type(st.model) == "string" then return st.model end
    -- WORLD NOT ADOPTED YET. With scopeToServer on, worldKey is still the pending "default"
    -- until a world exists, while the real records sit under a world id -- and the boot report
    -- runs inside that window. Reading the other buckets there keeps the rarity right instead
    -- of pricing the whole report as Commons.
    for wk, bucket in pairs(states) do
      if wk ~= worldKey and type(bucket) == "table" then
        local r = bucket[key]
        if type(r) == "table" and type(r.model) == "string" then return r.model end
      end
    end
    return nil
  end

  local n = 0; for _ in pairs(states[worldKey]) do n = n + 1 end
  log(string.format("counting started  world=%s known=%d  SHADOW=%s (hits %s)",
    worldKey, n, tostring(SHADOW), SHADOW and "logged, NOT saved" or "counted + saved"))

  -- CLIENT hook: MakeDamageInfo (fires client-side per outgoing hit). The old
  -- CallOnActualDamageProcessed_ToAll ran server-side and never fired on a pure
  -- client -- that was the "counting fires zero times" bug (2026-07-20).
  -- SOURCE-TAGGED (2026-08-08): the melee cluster dedupe must know which hook delivered
  -- an event -- MakeDamageInfo ("mk") hands real distinct hits, the reaction multicast
  -- ("rx") duplicates. See the via guard in grantRangedXp.
  local dh = A.installMakeDamageLocal(function(id, tgt, lv, dmg) onDamage(id, tgt, lv, dmg, "mk") end)
  local fh = A.installFire(onFire)            -- launcher trigger XP
  -- Melee + projectile bows ride the damage-REACTION multicast: MakeDamageInfo
  -- never fires for melee, NOR for projectile arrows on a dedicated server
  -- (server-side hit resolution) -- proven 2026-07-22: bow hits log [MELDBG]
  -- but never [MKDBG]. Hitscan guns DO fire MakeDamageInfo, so they stay on
  -- that path only; gating this hook to melee + Bow/BowGun keeps the two paths
  -- mutually exclusive (no double-earn).
  -- THE SECOND CATCH-22 DOOR (2026-07-29). This predicate decides whether a melee hit is even
  -- HANDED to onDamage, and it asked specFor() -- which returns nil for every weapon
  -- skipUntestedWeapons is holding back, i.e. every hpsSrc="est" weapon. So an untested weapon
  -- was rejected INSIDE the hook and onDamage never ran. Moving the SWING log earlier in
  -- onDamage could not help: control never reached it. One catch-22, two doors -- I fixed one
  -- and left the other shut, and the log looked identical either way (MELDBG firing, no SWING).
  --
  -- The predicate only needs to answer "is this a melee-pathway weapon", which is weapondata's
  -- `mode` -- a fact about the weapon, not about whether we are allowed to buff it. Bows and
  -- BowGuns stay included because their reaction events are wanted too (the original intent,
  -- preserved). Applicability is still enforced downstream in onDamage via specFor(), so an
  -- untested weapon is OBSERVED but never BUFFED.
  local mh = A.installMeleeDamage(function(id, tgt, lv, dmg) onDamage(id, tgt, lv, dmg, "rx") end, function(key)
    local w = wdLookup(key)
    if not w then return false end                 -- genuinely unknown weapon: not ours
    if cfg.ignoreTypes and cfg.ignoreTypes[w.t] then return false end   -- tools stay excluded
    return w.mode == "melee" or w.t == "Bow" or w.t == "BowGun"
  end)
  log("hooks: makeDamage(local)=" .. tostring(dh) .. "  fire=" .. tostring(fh) .. "  meleeReaction=" .. tostring(mh)
    .. "  pelletDedupeMs=" .. tostring(cfg.pelletDedupeMs))
  if not dh then log("FATAL: MakeDamageInfo hook failed -- no weapon will earn XP") end

  -- prime baked display for already-known weapons, then flush loop
  ExecuteWithDelay(6000, function() pcall(function() refreshDisplay(); persistThrottled() end) end)
  scheduleFlush()
  return dh
end

return M
