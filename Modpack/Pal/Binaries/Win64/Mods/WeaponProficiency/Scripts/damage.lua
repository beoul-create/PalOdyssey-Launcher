-- ============================================================================
--  damage.lua -- CLIENT-COMPLETE damage + magazine + durability writer.
--
--  Ranged AND melee damage are client-computed (client builds FPalDamageInfo and
--  RPCs it), so writing the equipped weapon's CLIENT weapon data changes the real
--  damage/behaviour the server accepts. Proven live: Lv40 bow 65->1047 on screen,
--  restore->65 on swap.
--
--  FIELD MAP (verified against the SDK, 2026-07-20):
--    AttackValue    -> ownWeaponStaticData (per-MODEL DataAsset)   [damage]
--    MagazineSize   -> ownWeaponStaticData (per-MODEL, card value only)
--    MaxMagazineSize-> ownWeaponDynamicData (per-INSTANCE)  <-- reload reads THIS
--                       (ReloadWeaponImmediate_ToServer passes this dynamicData)
--    MaxDurability / Durability -> ownWeaponDynamicData (per-INSTANCE, float)
--                       (static weapon data has NO durability field)
--
--  MAGAZINE ROOT-CAUSE FIX: the previous build wrote MaxMagazineSize only when a
--  `dyn` handle happened to be alive and logged nothing when it wasn't, so a miss
--  was invisible. Now the magazine write is BREADCRUMBED every equip -- it resolves
--  the per-INSTANCE dynamic data explicitly and logs presence + old/new/readback,
--  so "no mag lines" can no longer hide a skipped write. Static MagazineSize is
--  still set (item card) but is NOT what a reload reads.
--
--  DURABILITY base = weapondata.dur OVERRIDE if present, else
--  ownWeaponStaticData.Durability -- the per-MODEL pak TEMPLATE field. Crucially
--  this is a field we NEVER write (we write AttackValue on static, MaxDurability on
--  the DYNAMIC per-instance data), so the static Durability stays the authoritative
--  vanilla base, readable at runtime, immune to our writes -- no pak extraction
--  needed. The per-instance DYNAMIC value is NEVER a base (persisted -> a prior
--  boost would re-multiply: the poison-cache we killed for damage). MaxDurability
--  scales by the level curve; Durability preserves the fill % (consumable).
--
--  THE INVARIANT: no weapon field is ever based on a value WE WROTE. Damage/mag/dur
--  bases all come from write-immune sources (weapondata library, or the static
--  Durability template we never touch); the poisonable per-instance dynamic value
--  is never a base. Live dynamic reads happen ONLY to preserve durability fill %
--  and to verify writes. Restore-on-swap uses those same bases, nothing stranded.
--
--  DRY_RUN=true logs "[Arsenal][DMG] WOULD ..." instead of writing (validation
--  mode). Validated + LIVE (false) since 2026-07-20.
-- ============================================================================

local DRY_RUN         = false   -- LIVE
local APPLY_MAG       = true    -- per-instance MaxMagazineSize (client-authoritative)
-- durability boost: cfg.applyDurability (menu-editable); base from the weapondata.dur library
local POLL_MS         = 500

local cfg      = require("config")
local Counting = require("counting")
local P = require("progression")   -- P.durabilityMult: the curve the server half shares
local A        = require("adapters")

local Darn  = require("darn")
local safe  = Darn.safe
local log   = Darn.logger("[Arsenal][DMG]")
local alive = Darn.alive
-- one implementation, in counting.lua (already required above; counting does not
-- require us back, so this is not circular). Two copies of an id-parsing rule is
-- exactly how a format change breaks one call site and not the other.
local staticOf = Counting.staticOf

local function dynOf(weapon)
  local d = safe(function() return weapon.ownWeaponDynamicData end)
         or safe(function() return weapon:TryGetDynamicWeaponData() end)
  return alive(d) and d or nil
end

-- prev boosted state for restore-on-swap. All bases come from the STORE.
--   { model, key, st(static ref), dyn(dynamic ref), atkBase, magBase, durBase }
local prev = nil
-- RECOIL BASES, PER KEY. Damage/magazine/durability all take their bases from
-- write-immune sources; recoil is the one effect whose base can only be read off the
-- weapon actor, so it was carried in `prev` and re-read from the actor whenever prev
-- did not match. That was already a known hazard on a weapon-swap flap, and persisting
-- the boost turns it into the normal case: the actor keeps our scaled values across the
-- swap, prev has moved on, and the re-read would take a scaled number for vanilla and
-- compound it. Keyed by weapon key, captured once, never re-read while it holds -- the
-- same "never base a value on one we wrote" invariant the other three effects have.
-- Dropped with prev on world teardown: new world, new actors, genuinely vanilla again.
local grpBases = {}
-- LAST DURABILITY WE WROTE, PER KEY. External-repair detection compares the live
-- Durability against the number this file last put there: a rise to vanilla-full since
-- then is a workbench repair, and the fill is honoured rather than the ratio preserved
-- (a bench repairs to the VANILLA max whatever our boosted MaxDurability says, so
-- preserving the ratio is what made a repair land at ~40% of the bar and read as "it
-- repaired for one point"). This lived in `prev`, which meant detection only worked while
-- the repaired weapon was still the one being managed. Persisting the boost makes the
-- opposite the normal case -- you repair the blade while holding the gun -- so the
-- reference has to follow the WEAPON, not whatever is in hand.
local lastDurByKey = {}
-- what we last WROTE to MaxDurability per key, and whether we have already said it drifted
local durSeen, durDriftLogged = {}, {}
local announced = false
local lastSig = {}     -- key -> last applied signature (dedupe log/writes)
-- MAGAZINE REVERT BACKOFF ("Weird Magazine Scaling", reported 2026-08-05 on a dedicated
-- server). MaxMagazineSize is per-instance client data, so writing it is legitimate in
-- single-player -- but a dedicated server that enforces the vanilla size overwrites it
-- again immediately. The reconcile check below then fails on the magazine readback every
-- 500ms and the writer refights the server, silently, forever: two authorities toggling
-- the same field mid-fire is exactly the state where a reload can be resolved against the
-- smaller number and the ammo difference is lost. We cannot win that fight -- there is no
-- netmode probe in this mod, and a server's value is final by definition -- so after three
-- consecutive reverts of an UNCHANGED target we stop writing the field, say so once, and
-- leave the magazine vanilla for that weapon. Damage and durability are untouched by this:
-- they are not what the server is reverting, and they keep applying normally.
local magFail    = {}  -- key -> consecutive reverts observed at magStamp[key]
local magStamp   = {}  -- key -> the signature those reverts were counted against
local magBackoff = {}  -- key -> true: magazine writes suspended for this weapon
local magLogged  = {}  -- key -> true: the backoff has been announced once
local MAG_REVERT_LIMIT = 3
local warnedNoLibDur = {}   -- model -> true: logged "no durability base" once
local settledKey = nil -- key we've already seen equipped for a full tick (settle gate)
-- JOIN-SETTLE GATE (CTD patch 2026-08-03, crash UECC-...EC06DF9F, 61s into a fresh session;
-- folded to canonical after a publish wiped the installed copy). Third poisoned-pointer death
-- of that day, same shape as PLOT's and adoptTick's: a native walk over a getter-sourced object
-- during world STREAMING read 0xffffffffffffffff straight through alive() and every pcall. The
-- pawn passes alive() early in a join while its equipment is still streaming in, so gate on the
-- pawn's IDENTITY: any new pawn (join, respawn, world change) must be seen for
-- JOIN_SETTLE_TICKS consecutive ticks before this file touches a weapon natively.
local joinPawnKey, joinStable = nil, 0
local JOIN_SETTLE_TICKS = 12   -- x POLL_MS(500) = ~6s of proven-stable pawn before native reads

-- RESTORES ARE PARKED, NOT IMMEDIATE (2026-08-03 21:38 crash, 50 min into a stripped session).
-- Every restorePrev call site fires at the exact moment the held-weapon actor is being despawned
-- (holster, swap -- and a sphere THROW is an automatic swap, so capture combat is a swap storm).
-- alive() passes through the despawn linger and the write lands on freeing memory: AV at a
-- plausible heap address, the 07-28 signature, reproduced tonight one tick after
-- "restore ... (swapped)" ran twice in 1.5s. So restorePrev only PARKS the record; the write
-- runs RESTORE_DELAY_TICKS later, when the actor is either truly dead (alive() false -> skip,
-- the boost died with it) or stably lingering (write is safe). Teardown drops the queue whole.
local pendingRestores = {}
local RESTORE_DELAY_TICKS = 3   -- x POLL_MS(500) = ~1.5s clear of the despawn window
local tickN = 0

local function restoreNow(p, reason)
  -- THE WEAPON ITSELF MUST STILL EXIST BEFORE WE TOUCH ITS INNARDS.
  --
  -- st and dyn are stat structs living INSIDE a weapon object, and they keep passing alive()
  -- after that object is gone -- the "FindAllOf-lingering law" this file already warns about for
  -- world teardown is not limited to teardown. Writing into them afterwards touches freed memory,
  -- which shows up as an access violation on a PLAUSIBLE address rather than a null one
  -- (2026-07-28: "reading 0x14eb5823838", immediately after four ticks of
  -- "restore ... (holstered)").
  --
  -- WHAT FREES IT, honestly: not known. My first guess was the weapon breaking, and Mikey
  -- corrected that -- Palworld weapons are never destroyed by use, durability only lowers
  -- damage. The likelier candidate is the held weapon ACTOR being despawned on holster, which is
  -- exactly when this restore runs, but I have not proven it.
  --
  -- The guard stands regardless of the cause: actor destruction IS tracked, so the weapon is the
  -- honest thing to test, and if it is gone there is nothing to restore -- the boost died with
  -- the object it was applied to, and the next equip re-applies from scratch.
  -- 2026-07-29 -- THE GUARD USED TO SKIP ITSELF. It read
  --     if p.wep ~= nil and not alive(p.wep) then
  -- so a prev-cache with NO owner captured (`wep` nil) failed the first clause, fell
  -- straight past the return, and wrote into p.st/p.dyn exactly as if the guard had
  -- never been added -- the 07-28 crash, fully re-armed, in the one code path the
  -- 07-28 fix existed to close. A safety check whose precondition is "the thing I am
  -- checking for was recorded" is not a safety check. It now FAILS CLOSED: no live
  -- owner, no restore. alive(nil) is false (darn.lua:50), so this single test covers
  -- both "never captured" and "captured, since freed".
  if not alive(p.wep) then
    log(string.format("restore SKIPPED %s (%s) -- no live weapon to restore through, nothing to undo",
        tostring(p.model), reason))
    return
  end

  -- RE-RESOLVE the stat structs through the owner we JUST proved alive, rather than
  -- trusting the p.st/p.dyn captured at boost time. alive() on a child proves nothing
  -- about its parent, and UE recycles addresses -- so a cached struct pointer can keep
  -- passing IsValid() while the data it names is gone or has been rebuilt. The standing
  -- vault rule, now applied here for the 5th time in this codebase: CACHE THE OWNER,
  -- RE-READ THROUGH IT AT THE POINT OF USE. If either struct no longer resolves, the
  -- corresponding writes below simply skip -- the boost died with the data it was
  -- applied to, and the next equip re-applies from scratch.
  local st  = safe(function() return p.wep.ownWeaponStaticData end)
  local dyn = dynOf(p.wep)

  local msgs = {}
  if alive(st) and p.atkBase then
    if DRY_RUN then msgs[#msgs+1] = "AttackValue->" .. p.atkBase
    else pcall(function() st.AttackValue = p.atkBase end)
      local b = safe(function() return st.AttackValue end)
      msgs[#msgs+1] = "AttackValue->" .. p.atkBase .. (b == p.atkBase and "" or (" (readback "..tostring(b)..")")) end
  end
  if APPLY_MAG and p.magBase then
    if DRY_RUN then msgs[#msgs+1] = "MaxMagazineSize->" .. p.magBase
    else
      if alive(st)  then pcall(function() st.MagazineSize = p.magBase end) end
      if alive(dyn) then pcall(function() dyn.MaxMagazineSize = p.magBase end) end
      msgs[#msgs+1] = "MaxMagazineSize->" .. p.magBase
    end
  end
  -- DURABILITY restore: carry the fill % back down (consumable -- never cap-to-
  -- base, which would phantom-repair). Read pct off the CURRENTLY-BOOSTED pair
  -- BEFORE restoring, then MaxDurability=durBase, Durability=pct*durBase.
  if cfg.applyDurability ~= false and p.durBase and alive(dyn) then
    if DRY_RUN then msgs[#msgs+1] = "MaxDurability->" .. p.durBase
    else
      local curMax = safe(function() return dyn.MaxDurability end)
      local curDur = safe(function() return dyn.Durability end)
      if type(curMax) == "number" and curMax > 0 then
        local pct = (type(curDur) == "number") and (curDur / curMax) or 1
        -- repair-then-swap: same external-repair detection as the apply path -- a rise
        -- to vanilla-full since our last write is a repair, restored as FULL at base scale
        local lastWritten = p.key and lastDurByKey[p.key]
        if type(lastWritten) == "number" and type(curDur) == "number"
           and type(p.durBase) == "number"
           and curDur > lastWritten + 1 and curDur >= p.durBase - 1 then
          pct = 1
        end
        if pct < 0 then pct = 0 elseif pct > 1 then pct = 1 end
        local newDur = math.floor(pct * p.durBase + 0.5)
        pcall(function() dyn.MaxDurability = p.durBase end)
        pcall(function() dyn.Durability = newDur end)
        if p.key then lastDurByKey[p.key] = newDur end
        msgs[#msgs+1] = string.format("MaxDurability->%d Durability->%d (%.0f%%)", p.durBase, newDur, pct * 100)
      else
        msgs[#msgs+1] = "MaxDurability restore SKIP (curMax nil/<=0)"
      end
    end
  end
  -- GROUPING restore: recoil bases go back through the parked ACTOR (alive-gated; the
  -- fields live on the weapon itself, not static/dynamic data)
  if (p.grpYawBase or p.grpPitchBase) and alive(p.wep) and not DRY_RUN then
    if p.grpYawBase then pcall(function() p.wep.RecoilYawRange = p.grpYawBase end) end
    if p.grpPitchBase then pcall(function() p.wep.RecoilPitchTotalMax = p.grpPitchBase end) end
    msgs[#msgs+1] = "recoil restored"
  end
  log(string.format("%s %s  %s  (%s)", DRY_RUN and "WOULD RESTORE (dry-run)" or "restore",
    p.model, table.concat(msgs, "  "), reason))
end

local function restorePrev(reason)
  if not prev then return end
  local p = prev; prev = nil
  pendingRestores[#pendingRestores + 1] = { p = p, reason = reason, due = tickN + RESTORE_DELAY_TICKS }
end

local function runDueRestores()
  if #pendingRestores == 0 then return end
  local keep = {}
  for _, r in ipairs(pendingRestores) do
    if tickN >= r.due then
      pcall(restoreNow, r.p, r.reason)
    else
      keep[#keep + 1] = r
    end
  end
  pendingRestores = keep
end

-- RESTORE EVERY OWNED WEAPON TO STOCK (cfg.restoreToStock) -- the uninstall path.
--
-- Removing the mod leaves whatever it last wrote in place, and persistBoost makes that
-- normal rather than rare: nothing is tidied on swap any more. Turning this on makes the
-- writer stop boosting and instead walk the weapons the player owns, putting the vanilla
-- numbers back. Play for a few seconds, read the log, then uninstall.
--
-- It reaches weapons that are NOT in hand, which is the point, so it needs the sweep the
-- rest of this file avoids -- rate-limited to the same 3s the melee sweep uses, and behind
-- the same walkSafe/teardown gates as everything else here (the caller is inside tick()).
--
-- Bases come from the write-immune sources, never from a live read: spec.base for damage,
-- spec.mag for the magazine, and the static Durability template (or the library override)
-- for durability, whose fill % is preserved rather than topped up -- restoring must not
-- double as a free repair.
local restoreSweepAt, restoredKeys = -10, {}
local function restoreAllToStock()
  local now = os.clock()
  if (now - restoreSweepAt) < 3 then return end
  restoreSweepAt = now
  local list = A.ownedWeapons()
  for _, e in ipairs(list) do
    local w, key = e.weapon, e.key
    local spec = Counting.specFor(key)
    local st   = alive(w) and safe(function() return w.ownWeaponStaticData end) or nil
    if spec and alive(st) then
      local msgs = {}
      local aBase = tonumber(spec.base)
      if aBase and aBase > 0 and tonumber(safe(function() return st.AttackValue end)) ~= aBase then
        pcall(function() st.AttackValue = aBase end)
        msgs[#msgs + 1] = "AttackValue->" .. aBase
      end
      local dyn = dynOf(w)
      if alive(dyn) then
        local mBase = tonumber(spec.mag)
        if mBase and mBase > 0 and tonumber(safe(function() return dyn.MaxMagazineSize end)) ~= mBase then
          pcall(function() dyn.MaxMagazineSize = mBase end)
          pcall(function() st.MagazineSize = mBase end)
          msgs[#msgs + 1] = "MaxMagazineSize->" .. mBase
        end
        local libDur = tonumber(spec.dur)
        local statDur = tonumber(safe(function() return st.Durability end))
        local dBase = (libDur and libDur > 0) and libDur or ((statDur and statDur > 0) and statDur or nil)
        local curMax = tonumber(safe(function() return dyn.MaxDurability end))
        if dBase and curMax and curMax > 0 and math.abs(curMax - dBase) >= 1 then
          local curDur = tonumber(safe(function() return dyn.Durability end))
          local pct = curDur and (curDur / curMax) or 1
          if pct < 0 then pct = 0 elseif pct > 1 then pct = 1 end
          local nd = math.floor(pct * dBase + 0.5)
          pcall(function() dyn.MaxDurability = dBase end)
          pcall(function() dyn.Durability = nd end)
          lastDurByKey[key] = nd
          msgs[#msgs + 1] = string.format("MaxDurability->%d Durability->%d (%.0f%%)", dBase, nd, pct * 100)
        end
      end
      if #msgs > 0 then
        restoredKeys[key] = true
        log(string.format("RESTORE-TO-STOCK %s  %s", staticOf(key), table.concat(msgs, "  ")))
      elseif not restoredKeys[key] then
        restoredKeys[key] = true
        log(string.format("RESTORE-TO-STOCK %s  already stock", staticOf(key)))
      end
    end
  end
end

local tickErrSeen = {}
local function tick()
  local tickOk, tickErr = pcall(function()
    -- BOOT/JOIN STAND-DOWN comes FIRST (2026-08-03 launch-CTD family): A.localPawn() is
    -- itself a native read, so even the teardown guard below is unsafe mid-streaming.
    do
      local okUI, UIk = pcall(Darn.requireUI)
      if okUI and type(UIk) == "table" and UIk.walkSafe and not UIk.walkSafe() then return end
    end
    -- TEARDOWN GUARD (2026-07-22, the standing TODO finally closed): during a
    -- quit/disconnect the world tears down while this tick keeps firing, and
    -- lingering weapon objects pass alive() (FindAllOf-lingering law) -- a
    -- restore-write then lands on dying memory. The local pawn dies EARLY in
    -- teardown: no pawn -> no reads, no writes, and DROP the prev-cache
    -- (those objects are gone; next world re-applies fresh).
    tickN = tickN + 1
    local pawn = A.localPawn()
    if not alive(pawn) then
      -- teardown also DROPS the parked restores: their targets are gone with the world
      prev = nil; pendingRestores = {}; grpBases = {}; lastDurByKey = {}; durSeen = {}
      joinPawnKey, joinStable = nil, 0; return
    end
    -- identity, not address: a recycled address must not inherit the old pawn's settle credit
    local pk = safe(function() return pawn:GetFullName() end)
    if pk == nil or pk ~= joinPawnKey then joinPawnKey, joinStable = pk, 0; return end
    joinStable = joinStable + 1
    if joinStable < JOIN_SETTLE_TICKS then return end
    runDueRestores()   -- parked writes run here, well clear of the despawn window
    -- UNINSTALL MODE: put everything back and apply nothing. Checked before the equipped
    -- weapon is resolved, so it holds even with nothing in hand.
    if cfg.restoreToStock then
      prev = nil; pendingRestores = {}
      restoreAllToStock()
      return
    end
    local weapon, key = A.getEquippedWeapon()
    -- family and model keys carry no @GUID; only instance keys must have one
    local keyless = (cfg.progressScope == "model" or cfg.progressScope == "family")
    -- PERSIST THE BOOST PAST THE SWAP (cfg.persistBoost).
    --
    -- AttackValue lives on ownWeaponStaticData, which is a per-MODEL DataAsset -- one
    -- object shared by every copy of that model. So the write was ALWAYS global; the
    -- only thing that ever made it look equipped-only was restore-on-swap putting the
    -- vanilla number back. Under a keyless scope every copy of a model shares one
    -- career by construction, so there is no second instance the shared write could
    -- pay wrongly, and the restore buys nothing.
    --
    -- Under "instance" scope it buys a great deal: two of the same model can sit at
    -- different levels against ONE shared AttackValue, and a persistent write would
    -- hand your spare the veteran's damage. Persist is therefore gated on keyless and
    -- cannot be forced on from config.
    --
    -- Durability rides along for free. MaxDurability is per-INSTANCE dynamic data on
    -- the weapon ACTOR, and the actor outlives the swap (the Terraprisma's stays alive
    -- the whole time its summons are out) -- so not restoring is all it takes for a
    -- stowed weapon to keep its enlarged bar while something else is in hand.
    --
    -- CONSEQUENCE, stated plainly: boosts are no longer cleaned up on swap, so a
    -- weapon keeps its boosted values after the mod is removed until something else
    -- rewrites them. Restores still run for the cases that mean "this weapon should
    -- not be boosted at all" (unskilled, no active effect) and world teardown still
    -- drops the whole prev-cache without writing.
    local persist = keyless and (cfg.persistBoost ~= false)
    local keyOk = key and (keyless or key:find("@", 1, true))
    if not (alive(weapon) and keyOk) then
      settledKey = nil                 -- nothing equipped -> next equip re-settles
      if not persist then restorePrev("holstered") end
      return
    end
    local model = A.modelFor(key)   -- the weapon in hand, not the family root (log + per-model caches)
    -- CANCEL OBSOLETE PARKED RESTORES (2026-08-07; two crash buckets in one day, each within
    -- seconds of a "(swapped)" restore). Every pal-sphere THROW mid-combat flaps the equipped
    -- id (88 flap events in the 14:58 session): blade -> sphere parks a restore, the blade
    -- returns ~1s later and re-applies fresh -- then the parked restore fires anyway, writing
    -- BASE values over the new boost through an actor in exactly the despawn-uncertain window
    -- this file fears most. A parked restore for the key we are managing again is a stale
    -- write, not protection: the re-apply supersedes it. (A re-equip landing on the restore's
    -- exact due tick can still lose the race to runDueRestores at tick top -- one 500ms tick
    -- of exposure instead of every sphere throw. GROUPING NOTE for when grp points exist:
    -- prev dies at park, so the fresh apply re-reads recoil bases from the actor -- if that
    -- actor persisted through the flap with our scaled values, the re-read is poisoned; the
    -- grouping rollout must carry bases in the store row, not only in prev.)
    if #pendingRestores > 0 then
      local keep2 = {}
      for _, r in ipairs(pendingRestores) do
        if not (r.p and r.p.key == key) then keep2[#keep2 + 1] = r end
      end
      pendingRestores = keep2
    end
    if prev and prev.key ~= key and not persist then restorePrev("swapped") end

    -- SETTLE GATE (2026-07-24): never READ or WRITE a weapon instance on the same
    -- tick we first see it equipped. A swap driven by ANOTHER mod's native
    -- re-equip (e.g. a Pal-throw mod restoring the loadout weapon after the throw
    -- montage) can leave the freshly-equipped instance's dynamic data still under
    -- construction for a frame; our property write then lands in native engine
    -- code that no Lua pcall can catch (the tick pcall and the per-write pcalls
    -- below do NOT catch a C++ access violation). Deferring exactly one tick keeps
    -- us out of that frame -- imperceptible in play (one extra poll at vanilla
    -- stats), and it self-clears the moment the equip settles. prev was PARKED
    -- above (restores are deferred now); we simply apply next tick.
    if key ~= settledKey then
      settledKey = key
      return
    end

    local row = Counting.rowFor(key)
    local h = row and row.hud
    local dmg = h and h.dmg
    -- A valid store row bakes hud.dmg for any leveled weapon; no row/hud = unskilled.
    if not (h and dmg and type(dmg.cur) == "number" and type(dmg.base) == "number" and dmg.base > 0) then
      -- Under persist, prev is usually a DIFFERENT weapon we deliberately left
      -- boosted. Restoring it because the thing now IN HAND is unskilled would undo
      -- the persistence every time you draw a stock club. Only the weapon actually
      -- being judged gets restored; anything else is simply forgotten, boost intact.
      if persist and prev and prev.key ~= key then prev = nil
      else restorePrev("unskilled/unknown instance") end
      return
    end

    local st  = safe(function() return weapon.ownWeaponStaticData end)
    if not alive(st) then return end
    local dyn = dynOf(weapon)


    -- TARGETS FROM THE STORE ONLY (never read-back). The three effects are
    -- INDEPENDENT: damage is back-loaded, so a weapon earns magazine growth and
    -- (level-scaled) durability LONG before damage moves. A flat-damage weapon
    -- must still get its magazine + durability -- gating all three on a damage
    -- boost was the "HUD says 53, reload 19" bug (MakeshiftAR Lv34: dmg flat,
    -- mag 19->53). AttackValue is written ONLY when damage actually boosted.
    local atkBase   = dmg.base
    -- cfg.applyDamage: the menu/config kill-switch for damage scaling (mag +
    -- durability keep applying -- they are independent effects by design)
    local atkTarget = (cfg.applyDamage ~= false and dmg.cur > dmg.base) and dmg.cur or nil   -- nil = leave base
    local mult      = atkTarget and (atkTarget / atkBase) or 1.0

    local mag = h.mag
    local magBase, magTarget = nil, nil
    if APPLY_MAG and mag and type(mag.now) == "number" and type(mag.base) == "number"
       and mag.now > mag.base then
      magBase, magTarget = mag.base, mag.now
    end

    -- Durability CURVES with proficiency (like damage/magazine), not a flat jump.
    -- durMult = 1 + (level/maxLv) * (cap - 1)  -- linear, monotonic, reaches the
    -- cap (cfg.durabilityMaxMult) at max level. Uses row.level / row.hud.maxLv.
    --
    -- BASE (never the dynamic/observed value):
    --   1. weapondata.dur OVERRIDE if present (a dumped/authored library value), else
    --   2. ownWeaponStaticData.Durability -- the per-MODEL pak template field we
    --      NEVER write (we write AttackValue on static, MaxDurability on DYNAMIC),
    --      so it is the authoritative vanilla base, immune to our writes. This is
    --      the DUR-PROBE-validated source; it avoids pak extraction entirely.
    -- The per-instance dyn value is NEVER a base (persisted -> a prior boost would
    -- re-multiply: the poison-cache we killed for damage). Writing MaxDurability =
    -- base*mult self-heals the inflated dynamic value on this same equip.
    local durBase, durTarget, durMultVal = nil, nil, nil
    local durCap = (type(cfg.durabilityMaxMult) == "number" and cfg.durabilityMaxMult)
                or (type(cfg.durabilityMult) == "number" and cfg.durabilityMult) or 1
    if cfg.applyDurability ~= false and alive(dyn) and durCap > 1 then
      -- SELF-HEAL: discard any row.durBase left by the retired store-cache path.
      if row.durBase ~= nil then
        row.durBase = nil; Counting.markDirty()
        log(string.format("durability self-heal: discarded stale row.durBase for %s", model))
      end
      local spec = Counting.specFor(key)
      local libDur = spec and tonumber(spec.dur)                       -- (1) override
      local staticDur = safe(function() return st.Durability end)      -- (2) authoritative static
      local base = (type(libDur) == "number" and libDur > 0) and libDur
                or ((type(staticDur) == "number" and staticDur > 0) and staticDur or nil)
      if base then
        durBase = base
        -- P.durabilityMult owns this curve, and the server half calls the same function.
        -- The two used to compute it separately and divided by different max levels.
        durMultVal = P.durabilityMult(cfg, tonumber(row.level) or 0, tonumber(h.maxLv) or 80,
                                      row.prestige and row.prestige.dur)
        if durMultVal > 1.0001 then
          durTarget = math.floor(durBase * durMultVal + 0.5)
        end
      elseif not warnedNoLibDur[model] then
        warnedNoLibDur[model] = true
        log(string.format("durability SKIP %s: no override + static.Durability unreadable/<=0 (see [DUR-PROBE])", model))
      end
    end

    -- +GROUPING prestige (2026-08-07, design in roadmap): scale the weapon ACTOR's recoil
    -- fields down -- RecoilYawRange (wander) + RecoilPitchTotalMax (climb) -- by
    -- (1-perPt)^pts, floored at 0.4x vanilla. Same mutation class as AttackValue: plain
    -- persistent floats, written on equip, restored on swap. BASE comes from the parked
    -- record when re-applying on the same weapon (the actor already carries our scaled
    -- values; re-reading would compound -- the poison-cache law), else from the fresh
    -- actor, which spawns vanilla per equip. UNMEASURED until the first dogfood session:
    -- the [GRP] readback line is the probe.
    local grpYawBase, grpYawTarget, grpPitchBase, grpPitchTarget
    local grpPts = (row.prestige and tonumber(row.prestige.grp)) or 0
    if cfg.applyGrouping ~= false and grpPts > 0 then
      local m = (1 - (tonumber(cfg.prestigeGroupingPerPt) or 0.05)) ^ grpPts
      if m < 0.4 then m = 0.4 end
      local gb = grpBases[key]
      if not gb then
        gb = { yaw = safe(function() return weapon.RecoilYawRange end),
               pitch = safe(function() return weapon.RecoilPitchTotalMax end) }
        grpBases[key] = gb
      end
      local y, pt = gb.yaw, gb.pitch
      if type(y) == "number" and y > 0 then grpYawBase, grpYawTarget = y, y * m end
      if type(pt) == "number" and pt > 0 then grpPitchBase, grpPitchTarget = pt, pt * m end
    end

    -- INDEPENDENT GATE: proceed if ANY of the effects applies; otherwise
    -- this weapon is unskilled for effects -> restore whatever was active + bail.
    if not (atkTarget or magTarget or durTarget or grpYawTarget or grpPitchTarget) then
      if persist and prev and prev.key ~= key then prev = nil
      else restorePrev("no active effect (unskilled for damage/mag/durability)") end
      return
    end

    if not announced then
      announced = true
      log(string.format("armed (%s) APPLY_MAG=%s APPLY_DUR=%s -- first: %s%s%s%s",
        DRY_RUN and "DRY-RUN" or "LIVE", tostring(APPLY_MAG), tostring(cfg.applyDurability ~= false), model,
        atkTarget and string.format(" AttackValue %d->%d (x%.2f)", atkBase, atkTarget, mult) or " AttackValue flat",
        magTarget and (" Mag "..magBase.."->"..magTarget) or "",
        durTarget and (" Dur "..string.format("%.0f", durBase).."->"..durTarget) or ""))
    end

    local sig = table.concat({ tostring(atkTarget), tostring(magTarget), tostring(durTarget), tostring(grpYawTarget), tostring(grpPitchTarget) }, "|")
    -- RECONCILE MUST CHECK THE MAGAZINE TOO (2026-08-08, "magazine extension doesn't
    -- work while riding a flying mount"). MOUNTING hands the gun a FRESH per-instance
    -- dynamic-data object (vanilla MaxMagazineSize) while the per-model static keeps
    -- the boosted AttackValue -- so same key, same sig, attack readback passes, and
    -- this skip left the mounted gun's magazine at vanilla until the next real change.
    -- Verifying the mag readback makes the fresh dyn fail reconciliation and fall
    -- through to the LIVE WRITES below. Durability deliberately NOT checked here: the
    -- repair-detection logic owns that field and reconciling it would fight repairs.
    --
    -- A NEW TARGET IS A NEW ARGUMENT (see the backoff note at the top of the file). The revert
    -- tally is counted against ONE signature; a level-up or a settings change that moves the
    -- magazine target clears the tally and the backoff, so the writer tries the new value
    -- rather than staying quiet forever because of a fight it had at a lower level.
    if magStamp[key] ~= sig then
      magStamp[key], magFail[key], magBackoff[key] = sig, 0, nil
    end
    local magBack = alive(dyn) and safe(function() return dyn.MaxMagazineSize end) or nil
    -- backed off = treat the magazine as settled, so the tick reconciles and stops refighting
    local magHeld = (magTarget == nil) or magBackoff[key] or (magBack == magTarget)
    local reconciled = prev and prev.key == key and lastSig[key] == sig
                       and (atkTarget == nil or safe(function() return st.AttackValue end) == atkTarget)
                       and magHeld
    -- A REVERT COUNTS ONLY WHERE IT MEANS SOMETHING: this exact target was already written for
    -- this same weapon, the dynamic data is still there, and the value came back different.
    -- A missing dyn is the separate MAG-SKIP case and must not accumulate here.
    if prev and prev.key == key and lastSig[key] == sig and magTarget ~= nil
       and not magBackoff[key] and alive(dyn) and magBack ~= nil and magBack ~= magTarget then
      magFail[key] = (magFail[key] or 0) + 1
      if magFail[key] >= MAG_REVERT_LIMIT then
        magBackoff[key] = true
        -- once per weapon, not once per target: a levelling weapon re-arms the backoff on
        -- every new magazine target and the player does not need the same news each time
        if not magLogged[key] then
          magLogged[key] = true
          log(string.format("magazine reverted by an external authority -- backing off; likely a "
            .. "dedicated server enforcing vanilla size. %s keeps its vanilla magazine (%s, not "
            .. "%d); damage and durability are unaffected. key=%s",
            model, tostring(magBack), magTarget, key))
        end
      end
    end
    if reconciled then return end

    if DRY_RUN then
      if lastSig[key] ~= sig then
        lastSig[key] = sig
        local obs = safe(function() return st.AttackValue end)
        local dynHas = alive(dyn) and "dyn=ok" or "dyn=MISSING"
        local dynMag = alive(dyn) and tostring(safe(function() return dyn.MaxMagazineSize end)) or "n/a"
        log(string.format("WOULD WRITE (dry-run) %s%s%s%s  [%s curMaxMag=%s] key=%s",
          model,
          atkTarget and string.format(" AttackValue %s->%d (x%.2f)", tostring(obs), atkTarget, mult) or " AttackValue flat(leave base)",
          magTarget and (" MaxMagazineSize->"..magTarget) or "",
          durTarget and string.format(" MaxDurability->%d (x%.2f Lv%s)", durTarget, durMultVal or 1, tostring(row.level)) or "",
          dynHas, dynMag, key))
      end
      prev = { model = model, key = key, st = st, dyn = dyn, wep = weapon,
               atkBase = atkTarget and atkBase or nil, magBase = magBase, durBase = durTarget and durBase or nil,
               grpYawBase = grpYawTarget and grpYawBase or nil, grpPitchBase = grpPitchTarget and grpPitchBase or nil }
      return
    end

    -- LIVE WRITES. AttackValue ONLY when damage actually boosted (a flat-damage
    -- weapon is left at its base -- never rewritten to base each poll).
    local atkmsg, atkOk = "", true
    if atkTarget then
      local ok = pcall(function() st.AttackValue = atkTarget end)
      local backA = safe(function() return st.AttackValue end)
      atkOk = ok and backA == atkTarget
      atkmsg = atkOk and string.format(" AttackValue %d (x%.2f)", atkTarget, mult)
        or string.format(" AttackValue->%d [ATK-FAILED readback %s]", atkTarget, tostring(backA))
    end

    -- MAGAZINE: dyn.MaxMagazineSize is what a reload reads -- breadcrumb always
    local magmsg = ""
    if APPLY_MAG and magTarget and magBackoff[key] then
      magmsg = " [MAG-BACKOFF: reverted externally, left vanilla]"
    elseif APPLY_MAG and magTarget then
      if not alive(dyn) then
        magmsg = " [MAG-SKIP: no dynamic data on instance]"
      else
        local oldMax = safe(function() return dyn.MaxMagazineSize end)
        pcall(function() dyn.MaxMagazineSize = magTarget end)   -- PRIMARY (reload reads this)
        pcall(function() st.MagazineSize = magTarget end)       -- card value only
        local backMax = safe(function() return dyn.MaxMagazineSize end)
        magmsg = string.format(" MaxMagazineSize %s->%d (readback %s)%s",
          tostring(oldMax), magTarget, tostring(backMax),
          (backMax == magTarget) and "" or " [MAG-FAILED]")
      end
    end

    -- DURABILITY: resize the bar, PRESERVE THE FILL %. Durability is a CONSUMABLE
    -- (unlike AttackValue/magazine) -- topping it to full on equip would be free
    -- infinite repair. Read pct off the LIVE pair BEFORE writing, then set
    -- MaxDurability = durTarget and Durability = pct * durTarget.
    local durmsg = ""
    local durNewWritten = nil   -- the Durability value this pass wrote (repair-detect reference)
    if cfg.applyDurability ~= false and durTarget and alive(dyn) then
      local oldMax = safe(function() return dyn.MaxDurability end)
      local oldDur = safe(function() return dyn.Durability end)
      if type(oldMax) ~= "number" or oldMax <= 0 then
        durmsg = " [DUR-SKIP: MaxDurability nil/<=0]"    -- never divide by zero
      else
        local pct = (type(oldDur) == "number") and (oldDur / oldMax) or 1
        -- EXTERNAL REPAIR DETECTION (the "repair twice" report, 2026-08-07): the bench
        -- repairs to the VANILLA max (2400) no matter what our boosted MaxDurability says
        -- (4600), so a repair taken while boosted landed at ~52% of the bar -- "about
        -- half" -- and only a repair taken in the restored window ever stuck. Durability
        -- that ROSE since our last write and sits at (or above) vanilla-full is a player
        -- repairing: honor the intent -- fill the boosted bar, never preserve the ratio.
        local lastWritten = lastDurByKey[key]
        if type(lastWritten) == "number"
           and type(oldDur) == "number" and oldDur > lastWritten + 1
           and durBase and oldDur >= durBase - 1 then
          pct = 1
        end
        if pct < 0 then pct = 0 elseif pct > 1 then pct = 1 end
        local newDur = math.floor(pct * durTarget + 0.5)
        pcall(function() dyn.MaxDurability = durTarget end)
        pcall(function() dyn.Durability = newDur end)
        durNewWritten = newDur
        lastDurByKey[key] = newDur   -- the reference the next repair check compares against
        -- DRIFT WATCH. The apply is logged only when its SIGNATURE changes, so a value that
        -- is written every poll and reverted between polls produces exactly one boost line
        -- and then silence -- indistinguishable in the log from a boost that stuck. The
        -- magazine already has a named backoff for precisely this ("a dedicated server
        -- enforcing vanilla size"); durability had no equivalent and no way to see it.
        -- Reports the first time a bar we wrote comes back changed, once per weapon.
        if type(oldMax) == "number" and math.abs(oldMax - durTarget) >= 1
           and durSeen[key] and math.abs(durSeen[key] - durTarget) < 1 then
          if not durDriftLogged[key] then
            durDriftLogged[key] = true
            log(string.format("durability REVERTED externally on %s: we wrote MaxDurability %d, "
              .. "it came back %s. The boost is being re-applied every poll and undone between "
              .. "them -- an outside authority owns this field here.",
              model, durTarget, tostring(oldMax)))
          end
        end
        durSeen[key] = durTarget
        local backMax = safe(function() return dyn.MaxDurability end)
        durmsg = string.format(" MaxDurability %s->%d (x%.2f Lv%s) Durability %s->%d (%.0f%%, readback %s)%s",
          tostring(oldMax), durTarget, durMultVal or 1, tostring(row.level),
          tostring(oldDur), newDur, pct * 100, tostring(backMax),
          (type(backMax) == "number" and math.abs(backMax - durTarget) < 1) and "" or " [DUR-FAILED]")
      end
    end

    -- GROUPING live write + probe readback ([GRP] proves the write took on this build)
    local grpmsg = ""
    if grpYawTarget or grpPitchTarget then
      if grpYawTarget then pcall(function() weapon.RecoilYawRange = grpYawTarget end) end
      if grpPitchTarget then pcall(function() weapon.RecoilPitchTotalMax = grpPitchTarget end) end
      local by = safe(function() return weapon.RecoilYawRange end)
      grpmsg = string.format(" [GRP] yaw %s->%s pitch %s->%s (readback yaw %s)%s",
        tostring(grpYawBase), tostring(grpYawTarget), tostring(grpPitchBase), tostring(grpPitchTarget),
        tostring(by), (grpYawTarget == nil or by == grpYawTarget) and "" or " [GRP-FAILED]")
    end

    if atkOk then
      if lastSig[key] ~= sig then
        lastSig[key] = sig
        log(string.format("boost %s%s%s%s%s key=%s", model,
          (atkmsg ~= "") and atkmsg or " (damage flat, base left)", magmsg, durmsg, grpmsg, key))
      end
      prev = { model = model, key = key, st = st, dyn = dyn, wep = weapon,
               atkBase = atkTarget and atkBase or nil, magBase = magBase, durBase = durTarget and durBase or nil,
               grpYawBase = grpYawTarget and grpYawBase or nil, grpPitchBase = grpPitchTarget and grpPitchBase or nil,
               -- what we LAST wrote to Durability: the reference the repair detection
               -- compares a rise against (durTarget writes carry newDur; flat passes nil)
               lastDur = durNewWritten }
    else
      log(string.format("[CDMG-FAILED] boost %s%s%s%s", model, atkmsg, magmsg, durmsg))
    end
  end)
  -- name each distinct error once -- a discarded pcall here is a silent freeze that presents
  -- as "no boosts, no restores" over a healthy boot banner (same 2026-08-04 lesson as main.lua)
  if not tickOk and tickErr ~= nil then
    local key = tostring(tickErr)
    if not tickErrSeen[key] then tickErrSeen[key] = true; log("DMG TICK ERROR (contained, logged once): " .. key) end
  end
  -- GAME THREAD, for the SECOND crash family (2026-08-12). main.lua's census tick was moved
  -- for the Slate shaping-cache race; this tick is the OTHER async caller and it reaches the
  -- SAME hazard by a different road: tick -> A.localPawn() -> adapters.lua:272 ->
  -- PalUtility:GetPlayerCharacterByPlayerIndex -> UPalUtility::GetAllPlayerCharacters, which
  -- calls GetGameState and dereferences PlayerArray at GameState+0x2a8 WITH NO NULL CHECK.
  -- Off-thread during streaming churn that getter returns NULL and the game AVs instantly.
  -- Two dumps tonight, byte-identical 38-frame stacks, every frame below ProcessEvent inside
  -- UE4SS's Lua VM -- mod-driven, on an UNNAMED thread, while mounted (the gate above only
  -- reaches this path when the pawn is not BP_Player_*).
  -- safe()/pcall DOES NOT HELP: pcall catches Lua errors, never a native access violation.
  -- The comment at adapters.lua:269 assumes otherwise and is wrong.
  if type(_G.ExecuteInGameThreadWithDelay) == "function" then
    local okSched = pcall(_G.ExecuteInGameThreadWithDelay, POLL_MS, tick)
    if okSched then return end
  end
  ExecuteWithDelay(POLL_MS, tick)   -- timer-check: allow last-resort fallback if the loader lacks the game-thread scheduler
end

local M = {}
function M.start()
  log(string.format("damage writer starting  DRY_RUN=%s mag=%s durability=%s durCap=%s",
    tostring(DRY_RUN), tostring(APPLY_MAG), tostring(cfg.applyDurability ~= false), tostring(cfg.durabilityMaxMult)))
  -- first arm goes on the game thread too -- see the tail of tick() for why
  if type(_G.ExecuteInGameThreadWithDelay) == "function"
     and pcall(_G.ExecuteInGameThreadWithDelay, POLL_MS + 250, tick) then
    return true
  end
  ExecuteWithDelay(POLL_MS + 250, tick)   -- timer-check: allow  let counting.start() prime the store first
  return true
end
return M
