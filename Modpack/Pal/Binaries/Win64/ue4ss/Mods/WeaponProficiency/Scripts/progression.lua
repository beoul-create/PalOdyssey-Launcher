local P = {}

local function frac(level, maxLv)
  local f = level / (maxLv or 50)
  if f < 0 then return 0 elseif f > 1 then return 1 end
  return f
end

-- power: BACK-LOADS the damage. The level fraction is raised to `power` before the
-- curve is applied, so the ceiling is unchanged but the shape moves.
--   1.0 = stock. A shotgun (ratio 15.2x) is already +84% at Lv18 -- 22% of the
--         grind buying most of the useful power. Compounds at +3.45%/level from
--         level 1, so it is strong immediately.
--   2.0 = +15% at Lv18, +47% at Lv30, +97% at Lv40, +1417% at Lv80.
--   3.0 = +3% at Lv18 -- nearly flat until the 40s.
-- Pairs with capToPlayerLevel: a weapon cannot pass its wielder, so the cap and
-- the curve pull the same direction instead of racing.
-- ============================================================================
-- PER-LADDER "power by level" ("target" mode). Each weapon CATEGORY rides a ladder:
-- a DPS-by-level line from that ladder's weapons at their real tech unlock levels
-- (DPS = natural = hps*base). A weapon is 0% at its OWN unlock (its natural == the
-- ladder there) and rides UP to the current-best weapon on its ladder as it levels;
-- never nerfed below its own natural. Types with no ladder yet get NO scaling (stock).
-- Ladders are ANCHORED on the ~14 confirmed tech-level weapons (0% at unlock holds for
-- them); high-tier endgame points are APPROXIMATE until we get real levels/measurements.
-- "Odd ones" (a later weapon weaker than an earlier one; the rapid Semi-Auto Rifle) just
-- ride at their natural until the ladder catches up -- refine as data comes in.
-- MODEL (2026-07-17, Mikey): archery is the DATA SPINE -- 6 confirmed real anchors, Lv3->67.
-- Every OTHER ladder is a clean 2-point line from its earliest tech unlock (0% bonus there,
-- at that weapon's natural DPS) up to the SAME endpoint: the Mechanical Bow, {67, 11600}.
-- Same destination for all; each starts where its tech unlocks. That holds every slope near
-- ~8-10%/level instead of the old 3%..21% flats-and-cliffs. The guessed mid/endgame anchors
-- were deleted ON PURPOSE -- they were the lopsidedness. Re-add a mid anchor for a category
-- ONLY from a real measurement; run P.lintCurves() (a dev sanity tool) and it will shout if it diverges.
-- SHARED TOP (2026-07-24): the peak (the confirmed Mechanical-Bow DPS, 11600) now sits
-- at the true max level {80,CURVE_TOP} instead of at Lv67, so the old 67->80 plateau
-- becomes one gentle climb to the top (each ladder reaches full power at Lv80, not 67).
-- The Mechanical Bow itself is unchanged -- it rides its own natural DPS (0% bonus) from
-- 67 up. With curveDPS extrapolating past the last anchor, +Level Cap % prestige levels
-- (beyond 80) keep adding damage past 11600.
local CURVE_TOP = 11600                 -- Lv80 peak = the confirmed Mechanical-Bow DPS. Max damage unchanged; just reached at 80.
P.CURVES = {
  archery  = { {3,35}, {10,70}, {13,110}, {42,638}, {57,3364}, {80,CURVE_TOP} }, -- 3..57 CONFIRMED; top now at Lv80
  pistols  = { {24,301}, {80,CURVE_TOP} },   -- start Mk Handgun 0.94*320
  shotguns = { {30,565}, {80,CURVE_TOP} },   -- start Mk Shotgun  2.63*215
  rifles   = { {26,421}, {80,CURVE_TOP} },   -- start Mk SMG      4.21*100
  snipers  = { {21,160}, {80,CURVE_TOP} },   -- start Musket      0.16*1000
  melee    = { {1,14},   {80,CURVE_TOP} },   -- ALL melee (Sword/Katana/Melee) share one ladder; anchored on
                                         -- the weakest melee weapon (Hand-Held Torch 1.4*10) so nothing
                                         -- below it over-buffs. Each melee weapon is 0% where the curve
                                         -- crosses its own natural (~Lv30 for a Meowmere, nat 280).
}
P.LADDER = {   -- weapon type (w.t) -> ladder. Unmapped (launchers/gatling/laser) = stock for now.
  Bow="archery", BowGun="archery", Handgun="pistols", Shotgun="shotguns",
  AssaultRifle="rifles", SubmachineGun="rifles", SniperRifle="snipers",
  Sword="melee", Katana="melee", Melee="melee",   -- all melee ride one shared ladder (Axe/Pickaxe are tools, ignored)
}

local function curveDPS(curve, level)
  if level <= curve[1][1] then return curve[1][2] end
  for i = 2, #curve do
    if level <= curve[i][1] then
      local l0,d0 = curve[i-1][1], curve[i-1][2]
      local l1,d1 = curve[i][1], curve[i][2]
      return d0 * (d1/d0) ^ ((level-l0)/(l1-l0))
    end
  end
  -- ABOVE THE TOP ANCHOR: keep climbing at the final segment's slope instead of
  -- plateauing, so +Level Cap % prestige (levels past the normal max) keeps earning.
  local n = #curve
  local l0,d0 = curve[n-1][1], curve[n-1][2]
  local l1,d1 = curve[n][1], curve[n][2]
  if l1 > l0 and d0 > 0 then return d1 * (d1/d0) ^ ((level-l1)/(l1-l0)) end
  return d1
end
P.curveDPS = curveDPS

-- AUTO-HPS-RECALC: the level where this weapon's ladder passes its natural DPS
-- (hps*base) -- below it target mode returns exactly 1.0 (+0% damage). Derived
-- from spec.hps at call time, so editing hps in weapondata reprices it with no
-- other change. Returns: nil = no ladder / no usable nat (stock, never boosted);
-- the first anchor level = boosted from birth; false = nat sits above the
-- ladder's plateau, the curve never catches it. May be fractional; ceil to the
-- first level that actually shows a bonus.
function P.crossover(spec)
  local nat = (spec.hps or 0) * (spec.base or 0)
  if nat <= 0 then return nil end
  local ln = spec.type and P.LADDER[spec.type]
  if not ln then return nil end
  local c = P.CURVES[ln]
  -- Unlock-anchored (2026-07-28): a weapon is boosted from its OWN tech level, so the answer
  -- is simply that level. The only "never boosted" case left is a weapon whose natural DPS
  -- already meets or beats its grade's destination -- it holds at stock rather than being nerfed.
  local ge   = tonumber(P.gradeEdge) or 0.06
  local edge = (1 + ge) ^ ((tonumber(spec.grade) or 1) - 5)
  if c[#c][2] * edge * P.tierFactor(spec) <= nat then return false end
  local st = tonumber(spec.start) or c[1][1]
  if st >= c[#c][1] then return false end            -- unlocks at/after the top: no room to climb
  return st
end

-- GUARDRAIL against lopsided ladders. Every segment of every ladder must climb within a
-- sane per-level band; anything flatter or steeper is logged loudly at boot so a bad anchor
-- can NEVER ship silently again (this is exactly how the 3%..21%/level mess went unnoticed).
-- It only warns -- a genuinely real anchor (e.g. archery Lv10->13, the Crossbow, at ~16%)
-- is allowed to stay; the warning just makes you look and confirm it is real, not a guess.
P.SLOPE_LO, P.SLOPE_HI = 0.05, 0.15    -- 5%..15% per level = sane
P.SLOPE_RATIO_MAX      = 2.0           -- steepest/flattest across all ladders
function P.lintCurves(logfn)
  logfn = logfn or print
  local slopes, worst = {}, nil
  for name, c in pairs(P.CURVES) do
    for i = 2, #c do
      local l0, d0 = c[i-1][1], c[i-1][2]
      local l1, d1 = c[i][1], c[i][2]
      if l1 > l0 and d0 > 0 then
        local s = (d1 / d0) ^ (1 / (l1 - l0)) - 1
        slopes[#slopes + 1] = s
        if s < P.SLOPE_LO or s > P.SLOPE_HI then
          logfn(string.format("[CURVE WARN] %s Lv%d->Lv%d climbs %.1f%%/lvl (%s; sane %d-%d%%) -- confirm it is REAL data, not a guess",
            name, l0, l1, s * 100, (s < P.SLOPE_LO) and "too flat" or "cliff",
            P.SLOPE_LO * 100, P.SLOPE_HI * 100))
        end
      end
    end
  end
  if #slopes > 0 then
    local mn, mx = slopes[1], slopes[1]
    for _, s in ipairs(slopes) do if s < mn then mn = s end; if s > mx then mx = s end end
    if mn > 0 and (mx / mn) > P.SLOPE_RATIO_MAX then
      logfn(string.format("[CURVE WARN] steepest/flattest slope = %.1fx across ladders (want < %.1fx)",
        mx / mn, P.SLOPE_RATIO_MAX))
    end
  end
end

-- TECH TIERS (2026-07-28, Mikey: "lets bake tiers into levels"). A weapon's tier is the DECADE
-- of its tech level -- 0-9 = T1, 10-19 = T2, ... 70-80 = T8 -- and every tier aims 5% lower than
-- the tier above it. So WHERE A WEAPON UNLOCKS decides how high it can ever climb.
--
-- This is what makes tier mean anything. Before it, every weapon in a category converged on the
-- SAME ceiling no matter how late it unlocked, which is why a Makeshift Handgun and a Beam
-- Launcher finished on identical DPS. The old `tier` field in weapondata could not do this job:
-- it is unreliable (T5 spans tech 11..55, T4 spans 24..45, and the Handgun and Makeshift Handgun
-- are BOTH T5), and it is already spoken for -- it drives XP pacing via hoursByTier.
--
-- Compounding (0.95^n), not linear: the debuff is always "5% less than the tier above", it can
-- never reach zero however many tiers are added, and it matches how gradeEdge already works.
P.tierEdge  = 0.05
P.TIER_BAND = 10
P.TOP_TIER  = 8

-- `adj` = weapondata's optional `tierAdj`: GRADUATE (+1) or DEMOTE (-1) a weapon whose decade
-- puts it in the wrong band. Decades are a good default and a bad absolute: a clear upgrade can
-- share a decade with the thing it replaces (the Handgun, tech 28, and the Makeshift Handgun,
-- tech 24, are both 20-29). Mikey's rule: "when there's a clear upgrade and the tiers line up,
-- just graduate or demote one." The adjustment is relative, so it survives a later correction to
-- the tech level itself.
function P.tierOf(tech, adj)
  local t = tonumber(tech)
  if not t then return P.TOP_TIER end   -- unknown tech: never debuff on missing data
  local n = math.floor(t / P.TIER_BAND) + 1 + (tonumber(adj) or 0)
  if n < 1 then n = 1 elseif n > P.TOP_TIER then n = P.TOP_TIER end
  return n
end

-- Reads spec.tech, NOT spec.start: `start` is gated by cfg.useStartLevel and goes nil when that
-- is off, which would silently un-tier every weapon in the game.
function P.tierFactor(spec)
  local te = tonumber(P.tierEdge) or 0.05
  return (1 - te) ^ (P.TOP_TIER - P.tierOf(spec and spec.tech, spec and spec.tierAdj))
end

function P.multiplier(spec, level, mode, power)
  -- TARGET mode: scale EACH weapon from its own natural DPS (hps*base) up to the
  -- plateau, using the bow curve only as the SHAPE (timing) of the climb. Every
  -- weapon scales visibly and they all converge at the plateau by the last anchor's
  -- level; a weapon already at/above the plateau (top-tier gear) just holds. This
  -- replaced "boost up to the absolute curve", which left every weapon whose natural
  -- DPS already exceeded the (low, bow-derived) curve showing +0 until ~Lv50.
  if mode == "target" then
    local nat = (spec.hps or 0) * (spec.base or 0)
    if nat <= 0 then return 1.0 end
    local ln = spec.type and P.LADDER[spec.type]
    if not ln then return 1.0 end                    -- category not walked out yet: stock DPS (prestige applied by dmgInfoFor)
    -- GRADE EDGE (1.4.4). The ladder is a shared DPS DESTINATION, so `nat` divides
    -- straight back out of the result: final damage = curveDPS / hps, and `base`
    -- cancels COMPLETELY. Every rarity of a weapon therefore landed on the exact
    -- same number, and where hps had been (wrongly) estimated to rise with rarity
    -- the better weapon came out WEAKER -- reported on Nexus 2026-07-23:
    -- Common SMG 2755 vs Epic 2367, Common Old Bow 21481 vs Legendary 20000.
    --
    -- Fix: each grade aims at its OWN fraction of the shared ladder, ANCHORED AT
    -- GRADE 5 -- the Legendary sits exactly ON the ladder (its endpoint is the damage
    -- the endgame weapon was authored to reach) and every lesser grade falls short
    -- of it. Nothing is inflated past the authored ceiling; rarity now costs the
    -- lower grades instead of paying them.
    --   grade 5 = x1.00   4 = x0.943   3 = x0.890   2 = x0.840   1 = x0.792
    -- gradeEdge = 0 restores exact parity across rarities.
    local ge = tonumber(P.gradeEdge) or 0.06
    local edge = (1 + ge) ^ ((tonumber(spec.grade) or 1) - 5)
    local c    = P.CURVES[ln]
    local top  = c[#c][1]            -- the ladder's top anchor LEVEL (80)
    local dest = c[#c][2] * edge * P.tierFactor(spec)  -- grade AND tech tier set the ceiling
    --
    -- UNLOCK-ANCHORED (2026-07-28, Mikey: "I want them to start at their tech levels").
    -- The old form was `max(nat, curveDPS(level) * edge)`: a single ABSOLUTE ladder, and a
    -- weapon sat at +0% until that ladder climbed past its own natural DPS. Because the
    -- pistols anchor was 301 = the COMMON Makeshift Handgun (the weakest pistol in the game),
    -- every better pistol was dead for many levels -- a legendary Handgun (nat 1219, 4x the
    -- anchor) earned nothing until Lv46. It also got the ordering backwards: HIGHER rarity has
    -- higher nat, so it waited LONGER. Legendary Makeshift Lv39 vs its Common Lv28.
    --
    -- Now each weapon runs its OWN exponential from (its tech level, its natural DPS) to
    -- (the ladder's top level, its grade's destination). So: exactly +0% at unlock, a bonus
    -- on the very next level, and every weapon still converges on the shared destination at
    -- the top -- which was the point of the ladder in the first place. The ladder's lower
    -- anchors now only shape the OTHER modes; target mode reads just its endpoint.
    --
    -- f is deliberately NOT clamped at 1: past the top level it keeps climbing at the same
    -- rate, so +Level Cap prestige still earns (same intent as curveDPS's extrapolation).
    local st = tonumber(spec.start) or c[1][1]
    if level <= st then return 1.0 end               -- at or below unlock: exactly stock
    if top <= st then return 1.0 end                 -- unlocks at/after the top anchor: no room
    if dest <= nat then return 1.0 end               -- already at/above its destination: hold, never nerf
    local f = (level - st) / (top - st)
    return (dest / nat) ^ f                          -- prestige applied by the caller (dmgInfoFor)
  end
  local base = spec.base
  if not base or base <= 0 then return 1.0 end
  local cap = spec.cap or base
  if cap < base then cap = base end
  local ratio = cap / base
  -- START LEVEL: a weapon is "born" at its unlock level with 0% bonus, and its full
  -- ratio is spread across the levels REMAINING (start..maxLv). So crafting a weapon
  -- is never a downgrade, and a late-game weapon does not hand you its power for free.
  local st = tonumber(spec.start) or 0
  local mx = spec.maxLv or 80
  local f
  if st > 0 and mx > st then
    f = (level - st) / (mx - st)
    if f < 0 then f = 0 elseif f > 1 then f = 1 end
  else
    f = frac(level, mx)
  end
  local pw = tonumber(power)
  if pw and pw > 0 and pw ~= 1 then f = f ^ pw end
  local m = (mode == "linear") and (1 + (ratio - 1) * f) or (ratio ^ f)
  if m < 1 then m = 1 end
  return m                                            -- prestige (pct/dmg) applied by dmgInfoFor, not here -- see counting.lua
end

P.xpModels = {

  -- THE GAME'S OWN CURVE ON BOTH SIDES (2026-08-20, Maiq's calibration).
  --
  -- Earning is dropExp / hps, so one second of fire on a target pays what that target is
  -- worth. A level therefore costs a NUMBER OF SECONDS of that, which is the only free
  -- constant left: cfg.xpSecondsPerLevel, set to 60 because Maiq asked for "level 40, enemy
  -- level 40, one level per minute of combat".
  --
  -- Both sides being the same curve is the point. dropExpBase grows ~7% per level, so cost
  -- and income grow together and the pacing is flat BY CONSTRUCTION -- one minute per level
  -- against same-level enemies at ANY level, without a per-tier hours budget, a curvePower
  -- to soften the player curve, or a refDropExp constant pretending to scale for a career.
  -- Boss Rush pays x10 because that is its real species multiplier, not a tuned number.
  dropcurve = function(spec, level, cfg)
    local A = cfg._adapters
    local base = A and A.dropBaseFor and A.dropBaseFor(level)
    if type(base) ~= "number" or base <= 0 then
      return P.xpModels.playercurve(spec, level, cfg)   -- curve not swept yet: old behaviour
    end
    local secs = tonumber(cfg.xpSecondsPerLevel) or 60
    local n = math.floor(base * secs + 0.5)
    return (n < 1) and 1 or n
  end,

  firearm = function(spec, level, cfg)
    local base = spec.base or 1
    local cap = spec.cap or base
    local gain = (base > 0) and (cap / base) or 1
    if gain < 1 then gain = 1 end

    local xpStep = spec.xpStep or cfg.xpStep or 0.13
    local gp = spec.grindPower or cfg.grindPower or 0.4
    local h = 100 * xpStep * (spec.g or 1) * (gain ^ gp)
    h = math.floor(h + 0.5)
    return (h < 1) and 1 or h
  end,

  timed = function(spec, level, cfg)
    local hrs = spec.hoursByTier and spec.hoursByTier[spec.tier]
    if not hrs then return P.xpModels.firearm(spec, level, cfg) end
    -- XP is now rate-normalised at the grant site (xp/hit = enemyMult / hps), so
    -- one second of sustained fire == one xp at enemyMult 1.0. hoursByTier therefore
    -- converts straight to seconds; the old `rate` term double-counted the weapon's
    -- cadence and was a hand-guess besides (config fireRate was ~1.85x optimistic
    -- against measurement: Bow 1.0 vs 0.58 actual, BowGun 0.8 vs 0.43, Shotgun 0.9 vs 0.45).
    local total = math.floor(hrs * 3600 + 0.5)
    local mx = spec.maxLv or 100
    local n = math.floor(total * (level + 1) / mx + 0.5) - math.floor(total * level / mx + 0.5)
    return (n < 1) and 1 or n
  end,

  -- MIRROR THE PLAYER CURVE. Same shape as character levelling (~86,000x from
  -- first level to last), rescaled so a weapon's TOTAL still lands on its
  -- hoursByTier budget -- otherwise a weapon would need the player's 45.8M xp
  -- (= 12,700 hours at 1 xp/sec). Weapon level L maps to player level L+1, so
  -- L=0->1 costs what a player pays for Lv1->2.
  playercurve = function(spec, level, cfg)
    local c = cfg._playerCurve
    if not (c and c.total and c.total > 0) then
      return P.xpModels.timed(spec, level, cfg)      -- curve unreadable -> old behaviour
    end
    local hrs = (spec.hoursByTier and spec.hoursByTier[spec.tier]) or 8
    local budget = hrs * 3600                        -- xp/sec == 1 at enemyMult 1.0
    local pw = cfg.curvePower or 0.5

    -- The raw player curve spans ~86,000x, and compressed into a 15h budget the
    -- first ~15 levels round to 1 xp each -- Lv20 (and 4.5x damage, via dmgCurve
    -- geo) arrives after ~80 SECONDS of shooting. curvePower flattens the shape:
    --   1.00 = exact mirror     -> Lv20 in ~1.3 min, 4,626x backoff
    --   0.50 = default          -> Lv20 in ~21 min,   282x backoff
    --   0.35                    -> Lv20 in ~46 min,    53x backoff
    -- Cache the rescaled total per (power, maxLv) -- it is the same for every weapon.
    -- The hours budget is spread over the levels this weapon ACTUALLY has: from its
    -- start level to max. A weapon starting at Lv50 gets its whole budget across 30
    -- levels, not 80 -- so late-game weapons are not cheaper per level, just shorter.
    local st = tonumber(spec.start) or 0
    local mx = c.maxLv or 80
    local key = tostring(pw) .. "@" .. tostring(st)
    c._key = c._key or {}
    if c._key[key] == nil then
      local t = 0
      for L = st, mx - 1 do
        local i = L + 2; if i > mx then i = mx end
        t = t + ((c[i] or 0) ^ pw)
      end
      c._key[key] = t
    end
    local total = c._key[key]
    if not total or total <= 0 then return 1 end

    local idx = (level or 0) + 2
    if idx > c.maxLv then idx = c.maxLv end
    local n = math.floor(((c[idx] or 0) ^ pw) * (budget / total) + 0.5)
    return (n < 1) and 1 or n
  end,
}

function P.xpForNext(spec, level, cfg)
  if level >= (spec.maxLv or 50) then return math.huge end
  local model = P.xpModels[spec.xpModel] or P.xpModels.firearm
  return model(spec, level, cfg)
end

-- MAGAZINE GROWTH SPREAD OVER THE FULL LEVEL CURVE (2026-07-20). Was
-- maxLv*magFraction (0.35) -- so an 80-level auto hit its rarity cap by ~Lv28
-- and sat flat for the rest of the grind. Now the growth is anchored the SAME
-- way damage is: 0 bonus at the weapon's start level, reaching the rarity cap
-- at its OWN maxLv (spec.maxLv, not a hardcoded 80). Steady, monotonic, and it
-- still PLATEAUS at magMax (never exceeds -- the stock 600-round bug stays dead).
-- magFraction is retained in the signatures for compatibility but no longer sets
-- the span; the span is the weapon's real level range (start..maxLv).
local function magSpan(spec)
  local st = tonumber(spec.start) or 0
  local mx = spec.maxLv or 50
  local span = mx - st
  if span < 1 then span = 1 end
  return st, span
end

function P.magazine(spec, level, magFraction, step)
  local mag = spec.mag or 0
  local magMax = spec.magMax or mag
  if magMax <= mag then return mag end
  step = step or 2
  if step < 1 then step = 1 end
  local st, span = magSpan(spec)
  local f = ((level or 0) - st) / span
  if f < 0 then f = 0 elseif f > 1 then f = 1 end
  if f >= 1 then return magMax end
  local bonus = (magMax - mag) * f
  local m = mag + math.floor(bonus / step) * step
  if m > magMax then m = magMax end
  return m
end

function P.levelForMag(spec, targetMag, magFraction)
  local mag = spec.mag or 0
  local magMax = spec.magMax or mag
  if magMax <= mag then return 0 end
  local st, span = magSpan(spec)
  local L = st + (targetMag - mag) * span / (magMax - mag)
  L = math.ceil(L)
  if L < st then L = st elseif L > (st + span) then L = st + span end
  return L
end

-- A weapon is created at its unlock level (0% bonus there), not at 0. Levels below
-- `start` are meaningless: you cannot own the weapon before you can craft it.
-- THE DURABILITY CURVE, in one place.
--
-- It was written twice: damage.lua computes it for the client, server_durability.lua for the
-- server, and the latter's comment claimed they were "matching the client exactly ... both
-- halves in agreement". They were not quite. The client divided by the WEAPON's maxLv; the
-- server by cfg.durabilityMaxLevel, a fixed 80. Those agree today only because the xp model
-- rewrites every spec.maxLv to 80 -- change that, or give one weapon its own ceiling, and the
-- two halves disagree about a durability bar with nothing to catch it.
--
-- Living Wings had the same shape in its two halves and it WAS live: three specialists were
-- corrected down inside their own element. This one is not live -- the server half is off by
-- default -- which makes it the right time to fix rather than a reason to leave it.
--
-- Pure arithmetic, no engine contact, so both callers can use it and a test can exercise it.
function P.durabilityMult(cfg, level, maxLv, prestigeDurPoints)
  local cap = (type(cfg.durabilityMaxMult) == "number" and cfg.durabilityMaxMult)
           or (type(cfg.durabilityMult) == "number" and cfg.durabilityMult) or 1
  if cap <= 1 then return 1 end
  local mx = tonumber(maxLv) or tonumber(cfg.durabilityMaxLevel) or 80
  local frac = (mx > 0) and ((tonumber(level) or 0) / mx) or 0
  if frac < 0 then frac = 0 elseif frac > 1 then frac = 1 end
  local m = 1 + frac * (cap - 1)
  local pts = tonumber(prestigeDurPoints) or 0
  if pts > 0 then m = m * (1 + (tonumber(cfg.prestigeDurPerPt) or 0) * pts) end
  return m
end

-- total prestige points across all categories (drives the escalating grind)
function P.prestigeTotal(t)
  t = t or {}
  return (tonumber(t.dmg) or 0) + (tonumber(t.pct) or 0) + (tonumber(t.mag) or 0)
       + (tonumber(t.dur) or 0) + (tonumber(t.cap) or 0)
end

function P.newState(spec)
  local st = (spec and tonumber(spec.start)) or 0
  -- prestige: per-category points a player has banked into this weapon (see the
  -- Prestige panel). dmg = +Base Damage (flat % of base); pct = +% Damage (x total
  -- multiplier). Persisted automatically; older saves without it default here.
  return { level = st, xp = 0, hits = 0, prestige = { dmg = 0, pct = 0, mag = 0, dur = 0, cap = 0 } }
end

-- ONE formula for the escalating-prestige grind, shared by addXp and the HUD snapshot.
-- It lived only inside addXp, so the hud's xpNext was the UN-grinded price: a 2-star weapon
-- showed a bar that filled at the raw price and PEGGED at 100% while the real requirement was
-- unmet -- read in play as "capped at 43, not ticking over" (Maiq, 2026-08-04).
--
-- LINEAR, NOT EXPONENTIAL (Maiq's design call, same day): each star adds (grindMult - 1) of
-- the BASE price -- "+0.5 each time" at his 1.5 setting -- so stars stack additively
-- (x1.0, x1.5, x2.0, x2.5 ...) instead of compounding (1.5^n). The knob keeps its meaning:
-- prestigeGrindMult 1.5 = +50% per star, the shipped 1.2 = +20% per star.
function P.grindFor(prestige)
  local step = (tonumber(P.prestigeGrindMult) or 1) - 1
  if step < 0 then step = 0 end
  return 1 + step * P.prestigeTotal(prestige)
end

function P.addXp(state, amount, spec, cfg, capLv)
  local ups = {}
  local maxLv = spec.maxLv or 50
  -- capLv: a weapon may not exceed its wielder's level (see cfg.capToPlayerLevel)
  if type(capLv) == "number" and capLv < maxLv then maxLv = capLv end
  if not state or state.level >= maxLv then return ups end
  state.xp = (state.xp or 0) + (amount or 0)
  -- ESCALATING GRIND: each prestige point stretches every level's cost by
  -- prestigeGrindMult (default 1.5), so climbing back to cap gets progressively
  -- longer -- the self-limiting brake on an otherwise unbounded prestige count.
  local grind = P.grindFor(state.prestige)
  local guard = 0
  while state.level < maxLv and guard <= maxLv do
    guard = guard + 1
    local need = P.xpForNext(spec, state.level, cfg) * grind
    if state.xp >= need then
      state.xp = state.xp - need
      state.level = state.level + 1
      ups[#ups + 1] = state.level
    else
      break
    end
  end
  if state.level >= maxLv then state.xp = 0 end
  return ups
end

return P
