local A = {}
local cfg = require("config")
local Darn = require("darn")
local safe = Darn.safe

-- Guard against use-after-free: pcall catches Lua errors but NOT a native access violation from
-- dereferencing a freed UObject. Darn.alive checks IsValid() against UE4SS's registry -- call it
-- before touching any object we got from a hook / FindFirstOf / a getter. This is the fix for the
-- intermittent GameThread ACCESS_VIOLATION crashes (a stale weapon/bullet object being written to).
local alive = Darn.alive

local function isPlayerWeapon(id)
  if not id or id == "" or id == "None" then return false end
  return not (id:find("NPC") or id:find("Otomo") or id:find("Debug") or id:find("Dummy"))
end
A.isPlayerWeapon = isPlayerWeapon

-- ---------------------------------------------------------------------------
-- TARGET VALUE (added 2026-07-16). Scale per-hit XP by WHAT you shot, so a Lamball
-- does not pay like an Alpha boss. OnHitToActor already hands us the target -- the
-- stock mod registers function(self) and throws the parameters away.
--
-- Why per-hit-x-target rather than per-kill: FPalDeadInfo.LastAttacker names only
-- the FINISHER, so a Pal-assisted kill would pay the weapon nothing, and swapping
-- weapons mid-fight would award everything to whatever landed the last shot.
-- Scaling each hit keeps contribution-based credit AND makes the enemy matter.
--
-- GetDropExp(Level, RowName) is a data-table lookup: the answer never changes for
-- a species+level, so cache forever. No TTL, no staleness. (THIS is the lookup
-- worth caching -- the weapon one never was, since the bullet names its own.)
-- ---------------------------------------------------------------------------
local expDb = nil
local dropCache = {}   -- "Species@Level" -> exp, or false = known to have none

local function getExpDb()
  if alive(expDb) then return expDb end
  expDb = safe(function() return FindFirstOf("PalExpDatabase") end)
  return alive(expDb) and expDb or nil
end

-- Returns the target's drop-exp, or nil when it has none (rock, tree, building, player).
function A.targetDropExp(actor)
  if not alive(actor) then return nil end
  local comp = safe(function() return actor.CharacterParameterComponent end)
            or safe(function() return actor:GetCharacterParameterComponent() end)
  if not alive(comp) then return nil end
  local ip = safe(function() return comp.IndividualParameter end)
  if not alive(ip) then return nil end   -- CRASH GUARD: non-nil but freed ip => native AV in GetLevel()

  local lvl = safe(function() return ip:GetLevel() end)
  if type(lvl) ~= "number" then return nil end
  local fn = safe(function() return ip:GetCharacterID() end)
  if fn == nil then return nil end
  local sp = safe(function() return fn:ToString() end)
  if type(sp) ~= "string" or sp == "" or sp == "None" then return nil end

  local key = sp .. "@" .. tostring(lvl)
  local c = dropCache[key]
  if c ~= nil then return (c ~= false) and c or nil end

  local e, db = nil, getExpDb()
  if db then
    e = safe(function() return db:GetDropExp(lvl, fn) end)
    if type(e) ~= "number" or e <= 0 then
      e = safe(function() return db:GetDropExpBase(lvl) end)
    end
  end
  if type(e) ~= "number" or e <= 0 then e = nil end
  dropCache[key] = (e ~= nil) and e or false
  A.noteDropExp(sp, lvl, e)
  return e
end

-- WHAT A TARGET IS ACTUALLY WORTH, RECORDED FROM PLAY.
--
-- refDropExp has carried the whole target-scaling model since 2026-07-16 on two
-- observations of unknown level (chicken 11-15, dragon 595), and the config says the
-- mod "logs the first 30 observed dropExp values as [DROPEXP] lines". It did not. The
-- logger described there was never written, which is why no archived log has ever
-- contained one and why the number was never checked.
--
-- It matters now because worth-by-LEVEL decides whether a late weapon levels in a
-- minute or in forty-five: if a level-70 pal is worth proportionally more than a
-- level-40 one, per-level time stays flat; if worth is roughly constant, the late game
-- stalls. Those are the same calibration with opposite outcomes, and only measurement
-- separates them.
--
-- Recorded on the cache MISS, so it fires exactly once per species+level however many
-- times that pal is hit -- no throttle needed and no per-hit cost. Ordinary play across
-- a level spread produces the curve; nobody has to go and farm data.
local dropSeen, dropCount, dropDirty = {}, 0, false
local DROP_LOG_MAX = 30

function A.noteDropExp(species, level, exp)
  if cfg.dropExpReport == false then return end
  local key = tostring(species) .. "@" .. tostring(level)
  if dropSeen[key] then return end
  dropSeen[key] = { sp = species, lv = level, xp = exp }
  dropCount = dropCount + 1
  dropDirty = true
  -- The log is the fast path (visible without leaving the game); the file below is the
  -- durable one, because UE4SS.log truncates on the next launch.
  if dropCount <= DROP_LOG_MAX then
    print(string.format("[Arsenal][DROPEXP] %s lv%s -> %s exp\n",
      tostring(species), tostring(level), exp and tostring(exp) or "none"))
  end
end

-- Flushed by the caller's own tick rather than a timer of its own: this file has no
-- scheduler, and a new timer is the one thing this codebase's crash history says not to
-- add casually.
-- Its OWN path, the same way side.lua and store.lua find theirs. Taking it as an
-- argument meant the caller had to know where shared/ is, and counting.lua does not.
local DROP_DIR = (debug.getinfo(1, "S").source or ""):gsub("^@", "")
                   :gsub("[^/\\]+$", "") .. "../../shared/"

-- THE SERVER'S XP RATE, because GetDropExp returns the RAW table value.
--
-- The rate is applied by the game when exp is GRANTED (AddExp_forPlayerParty_ByExpCalcType
-- takes a BaseExpRate), never by the lookup -- so a 0.2x server hands the player a fifth of
-- what the table says while this mod was paying full. Weapons were levelling five times
-- faster than their wielder, which is the opposite of the pacing the drop curve exists to
-- give. Maiq spotted it before it reached anyone else.
--
-- Same three sources ExpeditionXP uses, in the same order; the first that answers wins and
-- the value is then fixed for the session (it cannot change without a world reload).
local RATE_SOURCES = {
  { cls = "PalOptionSubsystem",   holder = "OptionWorldSettings" },
  { cls = "PalOptionReplicator",  holder = "OptionWorldSettings" },
  { cls = "PalGameWorldSettings", holder = "OptionSettings" },
}
-- LATCHED, and latched on FAILURE too. This is called from the damage hook, once per
-- landed hit -- so a client that cannot read the rate was doing three FindFirstOf walks of
-- the object graph PER HIT, forever, for an answer that was never going to change. The
-- world can legitimately be missing on the first hits after a load, hence a few retries,
-- but after that it settles and stops asking. A world reload restarts the mod, so there is
-- no case where this needs re-reading mid-session.
local expRate, rateLogged, rateLastTry = nil, false, nil
local rateDelay = 0
local RATE_BACKOFF_START = 0.5   -- first retry gap
local RATE_BACKOFF_MAX   = 60    -- and never slower than this
function A.serverExpRate()
  if cfg.respectServerExpRate == false then return 1 end
  -- MANUAL ESCAPE HATCH. The three sources below are replicated to clients -- that is what
  -- PalOptionReplicator is for -- but "should replicate" is not proof, and a client that
  -- cannot read the rate pays full and levels weapons too fast without ever saying why.
  -- Setting this pins it; the boot line reports which of the two happened.
  local manual = tonumber(cfg.expRateOverride)
  if manual and manual > 0 then
    if not rateLogged then
      rateLogged = true
      print(string.format("[Arsenal] ExpRate %s (from cfg.expRateOverride) -- weapon xp scaled by it\n",
        tostring(manual)))
    end
    return manual
  end
  if expRate then return expRate end
  -- EXPONENTIAL BACKOFF, and NO give-up. Two earlier shapes were both wrong. A try COUNT
  -- alone spent every retry inside one second of shooting, before the world could come up. A
  -- fixed 1/sec cap fixed that but still LATCHED after eight tries -- so a world that appears
  -- late (a slow join, a map transition) would be answered wrong for the entire session, with
  -- no way back. Giving up is the expensive mistake here, not retrying.
  --
  -- Doubling from 0.5s to a 60s ceiling costs about a dozen walks in the first minute and one
  -- a minute thereafter, which is nothing -- and it stays able to notice the answer arriving
  -- at any point. Success latches; failure never does.
  local now = os.clock()
  if rateLastTry and (now - rateLastTry) < rateDelay then return 1 end
  rateLastTry = now
  for _, src in ipairs(RATE_SOURCES) do
    local o = safe(function() return FindFirstOf(src.cls) end)
    if alive(o) then
      local v = safe(function() return o[src.holder].ExpRate end)
      if type(v) == "number" and v == v and v > 0 then
        expRate = v
        if not rateLogged then
          rateLogged = true
          print(string.format("[Arsenal] server ExpRate = %s (via %s) -- weapon xp scaled by it\n",
            tostring(v), tostring(src.cls)))
        end
        return v
      end
    end
  end
  -- Not readable THIS time. Retry a few hits -- the world may still be coming up -- then
  -- latch at 1 so the walk stops. Paying FULL is the deliberate failure direction: too
  -- much xp is visible and complainable, too little is invisible and reads as a dead mod.
  -- Not this time. Widen the gap and keep watching -- the object may simply not exist yet.
  rateDelay = math.min((rateDelay > 0) and (rateDelay * 2) or RATE_BACKOFF_START, RATE_BACKOFF_MAX)
  -- Said ONCE, when the backoff first reaches its ceiling: by then it has been trying for
  -- about a minute, which is long enough to mean something is genuinely wrong rather than
  -- slow. It keeps retrying afterwards regardless, so this is a notice and not a verdict.
  if rateDelay >= RATE_BACKOFF_MAX and not rateLogged then
    rateLogged = true
    print("[Arsenal] still cannot read the world's ExpRate after ~1 minute -- weapon xp is "
      .. "UNSCALED for now. It keeps checking; set expRateOverride in the config if your "
      .. "server changes the XP rate and this never resolves.\n")
  end
  return 1
end

-- WHAT AN ORDINARY PAL OF THIS LEVEL IS WORTH, from the swept curve.
--
-- Measured 2026-08-20: every ordinary pal at a given level pays EXACTLY this, whatever its
-- species -- GrassGolem_Dark, Kirin_Ice, SnowTigerBeastman and ThunderBird_Ice all paid
-- 12,744 at level 75. The species term is 1.0 for normal play; the only multiplier observed
-- anywhere was Boss Rush at x10. So this curve is both what a target is worth AND the
-- natural yardstick for what a level should cost.
--
-- nil until the sweep succeeds, which is the caller's cue to keep its old behaviour.
A.dropCurve = nil
function A.dropBaseFor(level)
  local c = A.dropCurve
  if not c then return nil end
  local lv = math.floor(tonumber(level) or 0)
  if lv < 1 then lv = 1 end
  local v = c[lv]
  if v then return v end
  -- above the swept range: extend at the curve's own measured 7%/level
  local top, tl = nil, 0
  for k, x in pairs(c) do if k > tl then tl, top = k, x end end
  if not top then return nil end
  local out = top
  for _ = tl, lv - 1 do out = out * 1.07 end
  return out
end

-- THE LEVEL CURVE, IN ONE SWEEP.
--
-- GetDropExpBase(Level) is the level half of drop exp -- the species half is a per-row base
-- in DT_PalExpTable (the raw table shows small per-species values: 5, 11, 23, 25, 50, which
-- is consistent with the chicken=11-15 recorded in July). So the whole level curve can be
-- read in eighty calls at boot instead of inferred from whatever happens to get shot.
--
-- This is the number the weapon-xp calibration turns on: if worth grows with level, a
-- level-79 weapon levels in about a minute like a level-40 one; if it is flat, the same
-- calibration stalls at forty-five minutes. Guessing between those is not worth doing when
-- the game will simply answer.
--
-- Eighty pure data-table lookups, once, on a database object we already hold. No actors, no
-- world state, nothing that cares whether the world has streamed in.
local sweptCurve = false
function A.sweepDropCurve()
  if sweptCurve or cfg.dropExpReport == false then return false end
  local db = getExpDb()
  if not db then return false end          -- not up yet; the caller retries
  sweptCurve = true
  local rows, prev = {}, nil
  A.dropCurve = {}
  for lv = 1, 80 do
    local v = safe(function() return db:GetDropExpBase(lv) end)
    if type(v) == "number" then
      A.dropCurve[lv] = v
      local ratio = (prev and prev > 0) and (v / prev) or nil
      rows[#rows + 1] = string.format("%d\t%s%s", lv, tostring(v),
        ratio and string.format("\tx%.3f vs previous level", ratio) or "")
      prev = v
    end
  end
  if #rows == 0 then return false end
  local out = { "# Living Arsenal -- GetDropExpBase(level), the LEVEL half of drop exp.",
                "# The species half is a per-row base in DT_PalExpTable; this is what",
                "# multiplies it. Read once at boot, straight from the game.",
                "# level\tbase\tgrowth", "" }
  for _, r in ipairs(rows) do out[#out + 1] = r end
  print(string.format("[Arsenal][DROPEXP] level curve swept: %d levels, lv1=%s lv80=%s\n",
    #rows, tostring(safe(function() return db:GetDropExpBase(1) end)),
    tostring(safe(function() return db:GetDropExpBase(80) end))))
  return Darn.writeAtomic(DROP_DIR .. "WeaponProficiency-dropcurve.txt",
                          table.concat(out, "\n"))
end

function A.flushDropExp()
  if not dropDirty or cfg.dropExpReport == false then return false end
  dropDirty = false
  local rows = {}
  for _, r in pairs(dropSeen) do rows[#rows + 1] = r end
  table.sort(rows, function(a, b)
    if a.lv ~= b.lv then return (tonumber(a.lv) or 0) < (tonumber(b.lv) or 0) end
    return tostring(a.sp) < tostring(b.sp)
  end)
  local out = { "# Living Arsenal -- observed drop exp, one line per species+level.",
                "# Written from play; used to calibrate targetScaling.refDropExp and to",
                "# answer whether a target's worth grows with its level.",
                "# level\tdropExp\tspecies", "" }
  for _, r in ipairs(rows) do
    out[#out + 1] = string.format("%s\t%s\t%s", tostring(r.lv),
                                  r.xp and tostring(r.xp) or "none", tostring(r.sp))
  end
  out[#out + 1] = ""
  out[#out + 1] = string.format("# %d distinct species+level combinations seen", #rows)
  return Darn.writeAtomic(DROP_DIR .. "WeaponProficiency-dropexp.txt",
                          table.concat(out, "\n"))
end

-- The PLAYER's own exp curve, straight from the game. Weapon levels mirror its
-- SHAPE so a weapon backs off like a character does, instead of the stock flat
-- cost (65 xp at Lv1 and at Lv399 alike -- neither stock model has a `level` term).
-- Measured 2026-07-16: Lv2 next=50 ... Lv80 next=4,296,550, total=45,859,908.
-- That is an ~86,000x spread from first level to last.
-- curve[L] = exp required to REACH level L (so curve[1]=0). Read once, cached.
-- The level of a CHARACTER: comp -> IndividualParameter -> GetLevel, alive-gated
-- at each hop (a non-nil-but-freed IndividualParameter would native-AV in
-- GetLevel). Melee hands the character directly; ranged reaches it via the
-- attacker actor. Used for cfg.capToPlayerLevel.
function A.levelOfChar(holder)
  if not alive(holder) then return nil end
  local comp = safe(function() return holder.CharacterParameterComponent end)
            or safe(function() return holder:GetCharacterParameterComponent() end)
  if not alive(comp) then return nil end
  local ip = safe(function() return comp.IndividualParameter end)
  if not alive(ip) then return nil end   -- CRASH GUARD: non-nil but freed ip => native AV in GetLevel()
  local lv = safe(function() return ip:GetLevel() end)
  return (type(lv) == "number" and lv > 0) and lv or nil
end

function A.playerCurve()
  local db = getExpDb()
  if not db then return nil end
  local t, total = {}, 0
  for lv = 1, 80 do
    local n = safe(function() return db:GetNextExp(lv, true) end)
    if type(n) ~= "number" then return nil end
    t[lv] = n
    total = total + n
  end
  if total <= 0 then return nil end
  t.total, t.maxLv = total, 80
  return t
end


function A.getWorldId()
  local gs = safe(function() return FindFirstOf("PalGameStateInGame") end)
  if gs then
    local raw = safe(function() return gs:GetWorldSaveDirectoryName() end)
    if raw then
      local ss = safe(function() return raw:ToString() end)
      if ss == nil and type(raw) == "string" then ss = raw end
      if ss and ss ~= "" and ss ~= "None" then return ss end
    end
  end
  local ws = safe(function() return FindFirstOf("PalWorldSaveGame") end)
  if ws then
    local id = safe(function() return ws.WorldSaveId end) or safe(function() return ws.WorldId end)
    if id then local s = safe(function() return id:ToString() end); if s and s ~= "" and s ~= "None" then return s end end
  end
  local world = type(UEHelpers) == "table" and (UEHelpers.GetWorld() or UEHelpers.GetWorldContextObject())
  if world and world:IsValid() and world.NetDriver and world.NetDriver:IsValid() then
    local serverConn = safe(function() return world.NetDriver.ServerConnection end)
    if serverConn and serverConn:IsValid() then
      local host = safe(function() return serverConn.URL.Host:ToString() end) or safe(function() return tostring(serverConn.URL.Host) end)
      local port = safe(function() return tostring(serverConn.URL.Port) end)
      if host and host ~= "" and host ~= "nil" and host ~= "None" then
        return "srv_" .. host:gsub("[^%w_%-%.]", "_") .. "_" .. (port or "8211")
      end
    end
  end
  return "default"
end

-- ---------------------------------------------------------------------------
--  PER-INSTANCE IDENTITY  --  "this blue shotgun", not "every shotgun of this model"
--
--  GetOwnerStaticItemId() names the item KIND: every MakeshiftShotgun_3 in the
--  world answers "MakeshiftShotgun_3". Keying the store on that means your gun,
--  your friend's gun, and the spare in your chest are one shared entry.
--
--  bullet:GetOwner() is NOT the pawn -- it is the WEAPON ACTOR (BP_MakeshiftShotgun_C),
--  which carries ownItemID directly. Its DynamicId.LocalIdInCreatedWorld is a GUID
--  identifying the physical item. MEASURED 2026-07-17 (BulletProbe, 120 samples):
--    8A1B5E364E7008C6B1991DB88C713B68  MakeshiftAssaultRifle_2   x53
--    724B4A9F4E9AB6831424A1AF3939408D  MakeshiftShotgun_3        x24
--    94137F034B5EBCEA046FA6AB99F26C0B  Bow_triple                x20
--    00000000000000000000000000000000  Handgun_NPC / PalSphere   x23
--  One stable GUID per physical gun, distinct between guns, and the SAME either
--  side of the 00:12 server restart -- so it persists in the save, which is the
--  whole reason this is viable as a store key.
--
--  Zeros mean "never crafted" (NPC weapons, thrown spheres). Those fall back to
--  the model id, and are filtered out a step earlier anyway: weapondata has no
--  NPC entries, so specFor() returns nil and they never reach the store.
--
--  Key format is "StaticId@GUID" rather than the bare GUID so that data.lua stays
--  readable, and so the spec lookup can recover the model from the key alone
--  without a second table.
-- ---------------------------------------------------------------------------
local ZERO_GUID = string.rep("0", 32)
local RAWID_SEEN = {}   -- dedupe for the RAWID probe: OnShootBullet fires per trigger pull

-- guidStr now lives in the vendored darn.lua (Darn.guidStr) -- one source, shared
-- with DarnMenu. Behavior-identical (same %08X format + zero-guid -> nil).
local guidStr = Darn.guidStr

-- NO GUID => NO KEY. Returns nil rather than degrading to the model id.
--
-- Falling back to model-wide would silently rebuild the exact thing this replaced:
-- one shared row for every gun of a pattern, across every player. It would look
-- like it was working. A weapon that reads Lv0 because we refused to guess is
-- honest; a weapon showing someone else's grind is not. So: shout once per model
-- and drop the hit.
--
-- Deduped by model id -- this sits inside a per-BULLET hook, so an undeduped print
-- would be ~4 lines/sec per shotgun trigger pull and would bury itself.
local warnedNoGuid = {}
local function warnNoGuid(staticId)
  local k = tostring(staticId)
  if warnedNoGuid[k] then return end
  warnedNoGuid[k] = true
  pcall(function()
    print(string.format(
      "[Arsenal] ERROR: no per-instance GUID for %s -- cannot tell WHICH %s this is. "
      .. "Ignoring its hits rather than crediting every %s on the server. "
      .. "(measured working 2026-07-17; if you see this, something changed)\n", k, k, k))
  end)
end

-- FAMILY = the model with its RARITY SUFFIX removed, so every grade of one weapon shares a
-- career. Uses the SAME end-anchored patterns as counting.gradeOf, deliberately: those already
-- encode which trailing digits are rarities and which are different weapons -- Bat/Bat2/Bat3 are
-- a Wooden Club, a Bat and a Metal Bat, and Spear_ForestBoss2 and Axe_Tier_02 are not grades of
-- anything. Reusing the reviewed rule beats inventing a second one that can disagree with it.
function A.familyOf(staticId)
  local k = tostring(staticId or ""):gsub("^fam:", "")
  return k:match("^(.*)_Default[1-5]$") or k:match("^(.*)_[2-5]$") or k
end

function A.instanceKey(weapon, staticId)
  if not staticId then return nil end
  -- "family": one career across every rarity of the weapon.
  if cfg.progressScope == "family" then
    local fk = "fam:" .. A.familyOf(staticId)
    A.noteModel(fk, staticId)
    return fk
  end
  -- "model": every copy of a weapon shares one career
  if cfg.progressScope == "model" then return staticId end
  
  -- "instance": physical weapon with its own GUID
  if not alive(weapon) then return staticId end
  local dyn = safe(function() return weapon.ownItemID.DynamicId end)
  local g = dyn and guidStr(safe(function() return dyn.LocalIdInCreatedWorld end))
  -- DEDICATED SERVER ROBUSTNESS: If GUID replication is absent/empty on the server,
  -- fall back gracefully to model career rather than discarding all hits and breaking the mod.
  if not g or g == "00000000000000000000000000000000" then
    return staticId
  end
  return staticId .. "@" .. g
end

-- ---------------------------------------------------------------------------
--  CLIENT-COMPLETE ADDITIONS (2026-07-20). The mod now runs entirely on the
--  CLIENT; there is exactly one local player and every hit we may count is
--  ITS hit. Two helpers make that precise instead of "the first player object\n--  FindFirstOf happens to return" (which, with other players streamed in, is
--  not guaranteed to be you).
-- ---------------------------------------------------------------------------

-- The LOCAL player's pawn: the PalPlayerCharacter possessed by the locally
-- controlled PlayerController. Cached (revalidated via alive()). Falls back to
-- FindFirstOf only if no local controller is resolvable yet.
--
-- THE CACHE IS LOAD-BEARING -- it is not just an optimisation. The question this
-- answers is "who is the LOCAL PLAYER CHARACTER", not "what is the controller\n-- possessing right now", and those differ exactly when you MOUNT. Observed
-- 2026-07-23 in OutdoorLootFilter, which had the same hazard: while riding,
-- K2_GetPawn() returns the RIDE PAL (BP_Garm_C) while your character
-- (BP_Player_Female_C) is still alive and still carrying its components.
-- A ride pal has no ShooterComponent, so re-resolving per call would make
-- getEquippedWeapon() return nil while mounted -- and damage.lua would then
-- restorePrev("holstered"), silently dropping your weapon to base damage and
-- stopping XP. Asking ONCE and re-resolving only when the cached character DIES
-- is what prevents that: the cases where the character genuinely changes
-- (death/respawn, level travel) are exactly the cases where alive() goes false.
-- OLF re-resolved on every call, faithfully answered the wrong question, and
-- broke while mounted. DO NOT "simplify" this into a fresh lookup per call.
-- CACHE THE CONTROLLER, NOT THE PAWN (2026-08-04, reproduced live on Maiq's client and it is
-- V3NM's published "turns off randomly, relog fixes it"). The old pawn cache was guarded only
-- by alive() -- and lingering objects PASS alive() (the FindAllOf-lingering law), so after any
-- pawn REPLACEMENT (death respawn, boss-arena transition) every call kept returning the corpse:
-- sameActor()=false on every hit, no XP, no panel, silently, until relaunch rebuilt the cache.
-- The CONTROLLER is the identity that survives repossession; the pawn is fetched through it
-- fresh on every call (one native getter, cheap), so a new pawn is picked up the same frame.
local localPCCache, localPCAt = nil, 0
function A.localPawn()
  -- TTL ON THE CONTROLLER TOO (2026-08-04 22:21, live repro #2): the controller-cache fix
  -- assumed controllers survive repossession -- and 48 minutes in, sphere-capture swaps left
  -- a LINGERING controller that passed alive() and kept answering with the dead pawn
  -- (same=false, mod dark, relog fixes). The lingering law spares nothing. A 5s TTL turns
  -- "stale forever" into "stale for at most 5s": the walk is one FindAllOf every 5s, cheap.
  local now = os.clock()
  local pc = localPCCache
  if not alive(pc) or (now - localPCAt) > 5 then
    pc = nil
    for _, c in ipairs(safe(function() return FindAllOf("PalPlayerController") end) or {}) do
      if alive(c) and safe(function() return c:IsLocalController() end) == true then pc = c; break end
    end
    localPCCache, localPCAt = pc, now
  end
  if pc then
    local pawn = safe(function() return pc:K2_GetPawn() end)
              or safe(function() return pc:GetPawn() end)
    if alive(pawn) then
      local cls = safe(function() return pawn:GetClass():GetFName():ToString() end) or ""
      if cls:find("^BP_Player_") then return pawn end
      -- MOUNTED (2026-08-05, the 18:04 dark session): riding REPOSSESSES the controller to
      -- the mount, so K2_GetPawn answers with the bird while every damage event names the
      -- rider -- same=false, XP dead, the tick restoring 'holstered' mid-firefight. Resolve
      -- the CHARACTER instead: PalUtility:GetPlayerCharacterByPlayerIndex(ctx, 0) asks the
      -- game who player 0's character IS, possession be damned (Pal.hpp:37914).
      -- NATIVE-CALL RULE NOTE: this getter is new to the codebase, so it is CONTAINED -- it
      -- only runs when the possessed pawn is not a player character, a state in which the
      -- old code's answer was already guaranteed wrong. Read-only, live-ctx, pcall'd, with
      -- the old degraded answer as fallback.
      local util = safe(function() return StaticFindObject("/Script/Pal.Default__PalUtility") end)
      local ch = alive(util) and safe(function() return util:GetPlayerCharacterByPlayerIndex(pc, 0) end)
      if alive(ch) then return ch end
      return pawn
    end
  end
  local fp = safe(function() return FindFirstOf("PalPlayerCharacter") end)
  return alive(fp) and fp or nil
end

-- Robust "same actor" test. UE4SS UObject wrappers usually compare with ==, but
-- one side here comes from a STRUCT FIELD read (FPalMakeDamageInfo.Attacker) and
-- the other from GetPawn(); identity is safest via GetFullName().
function A.sameActor(a, b)
  if a == nil or b == nil then return false end
  if a == b then return true end
  local an = safe(function() return a:GetFullName() end)
  local bn = safe(function() return b:GetFullName() end)
  if an ~= nil and an == bn then return true end
  
  -- Cross-check Controller vs Pawn equivalence on multiplayer servers
  local aPawn = safe(function() return a:GetPawn() end) or safe(function() return a.Pawn end)
  local bPawn = safe(function() return b:GetPawn() end) or safe(function() return b.Pawn end)
  if alive(aPawn) and (aPawn == b or (bn and safe(function() return aPawn:GetFullName() end) == bn)) then return true end
  if alive(bPawn) and (bPawn == a or (an and safe(function() return bPawn:GetFullName() end) == an)) then return true end
  return false
end

-- CLIENT COUNTING HOOK (2026-07-20 repoint). UPalUtility:MakeDamageInfo is where
-- the CLIENT builds the outgoing FPalMakeDamageInfo before RPCing damage to the
-- server -- it fired 40-93x/session client-side in the damage probes, once per
-- outgoing hit. Its param (FPalMakeDamageInfo, PalMakeDamageInfo.h) carries
-- Attacker(:25), Defender(:28), Power(:34). Filter Attacker==local pawn, resolve
-- MKDBG/MELDBG: raw-event debug counters, only while cfg.measureHps. Uncapped while opted in
-- (see the sites below); the counters remain only to number the lines.
-- Declared HERE (above installMakeDamageLocal) so its closure binds this LOCAL,
-- not a nil global -- the scope miss that made `nil < 12` throw and silently
-- stopped ranged XP whenever HPS measurement was on.
local MKDBG_N, MELDBG_N = 0, 0
local WDA = require("weapondata")

-- ---- THE LIBRARY LOOKUP FUNNEL (one implementation, used everywhere) --------
-- Store keys come in three shapes -- "Model@GUID" (instance), "Model" (model) and
-- "fam:Family" (family) -- and every library lookup needs the MODEL out of them.
-- Both decorations are stripped here rather than at each caller.
function A.staticOf(id)
  local s = tostring(id or ""):gsub("^fam:", "")
  return s:match("^([^@]+)") or s
end

-- WHICH MODEL A KEY IS ACTUALLY ABOUT.
--
-- staticOf answers "what career is this", and for a family key that is deliberately the
-- rarity-less root: "fam:YakushimaGun001". Feeding that to the weapon LIBRARY asks a
-- different question and gets the wrong answer -- the root row is the COMMON, so a family-
-- scoped Legendary was priced off base 300 instead of its own 390 and lost 104 damage the
-- moment the scope was switched (measured on the Legendary Vortex Beater, 2026-08-18).
-- Sharing a LEVEL across rarities is the entire point of family scope; sharing STATS was
-- never the intent, and the comment on instanceKey already promised it did not.
--
-- So: the key identifies the career, this identifies the physical weapon. instanceKey sees
-- the real StaticId every time it builds a family key and records it here. Falls back to
-- staticOf only for a career nothing has ever been equipped for. That fallback was once
-- described here as harmless "boot report only" -- it was not: the report's numbers were
-- cached onto the record and spent the session as the weapon's real base.
-- WHERE THE RARITY LIVES, AND THE RULE THAT KEEPS IT THERE.
--
-- A family career key is deliberately rarity-less, so it cannot answer "which weapon is this".
-- Two contexts ask, and neither reconstructs the answer from the key:
--
--   weapon in hand   the caller was HANDED the real StaticId (instanceKey's own argument), so
--                    it records it and passes it on. Nothing is looked up.
--   record only      the boot report and the HUD of a stowed weapon have no actor to ask, so
--                    the model is read off the career RECORD, where the in-hand path wrote it.
--
-- There is deliberately NO in-memory cache between the two. The previous version kept one and
-- it started EMPTY every boot: a career was priced from the family root -- the grade-1 Common --
-- until the weapon was next equipped, and that figure was then cached into the record's hud
-- block and spent for the whole session. A Legendary Vortex Beater scaled from 300 instead of
-- 390. The record already IS the durable answer; a second copy of it could only go stale.
--
-- Both hooks are installed by counting, which owns the store. They are nil until it starts, and
-- both call sites tolerate that: a lookup before the store is up falls back to the root, which
-- is the same answer it would have given anyway.
A.modelSink     = nil   -- (careerKey, staticId) -> record it on the career row
A.modelResolver = nil   -- (careerKey) -> the recorded model, or nil

function A.noteModel(key, staticId)
  local k, m = tostring(key or ""), tostring(staticId or "")
  if k == "" or m == "" then return end
  if A.modelSink then pcall(A.modelSink, k, m) end
end

function A.modelFor(id)
  if A.modelResolver then
    local ok, m = pcall(A.modelResolver, tostring(id or ""))
    if ok and type(m) == "string" and m ~= "" then return m end
  end
  return A.staticOf(id)
end

local WD_LOWER
-- ROOTLESS FAMILY FALLBACK (Fenrir, 2026-08-04): family scope keys "fam:AssaultRifle" ->
-- staticOf "AssaultRifle", and the AR is the ONLY multi-grade family in the library with no
-- bare root row (AssaultRifle_Default1..5). Without the fallback a raw WEAPONS[m] read misses
-- the whole family. Grade-1 is the family spec by convention already.
--
-- IT LIVES HERE, NOT IN counting.lua, BECAUSE THE RAW READ CAME BACK (2026-08-11). counting's
-- copy of this fallback fixed the XP gate; emitsWt3 below still did a bare WEAPONS[m] and so
-- read nil for every assault rifle under family scope -- which made the swarm router treat the
-- rifle as a non-wt=3 weapon and hand EVERY assault-rifle hit to the Terraprisma record.
-- Silent, total XP loss on a whole family, from one lookup that skipped the funnel. adapters is
-- the lowest module both callers already require, so this is the one copy: counting takes it
-- from here, and nothing needs its own.
function A.wdLookup(id)
  id = A.modelFor(id)
  local w = WDA.WEAPONS[id]; if w then return w end
  if not WD_LOWER then WD_LOWER = {}; for k, v in pairs(WDA.WEAPONS) do WD_LOWER[string.lower(k)] = v end end
  w = WD_LOWER[string.lower(tostring(id))]; if w then return w end
  return WDA.WEAPONS[id .. "_Default1"] or WD_LOWER[string.lower(tostring(id)) .. "_default1"]
end

-- WHICH CAREER A HIT BELONGS TO, taken from the attack's own source item.
--
-- This replaces the 2026-08-08 swarm router wholesale. That one INFERRED the source: it armed
-- on equipping a Terraprisma, matched WeaponType 3, and used a 50ms flurry window to guess
-- which of two wt=3 emitters had fired. wt=3 means "AssaultRifle" and never meant "summon", so
-- the guess was wrong by construction -- documented as conceding the first hit of every flurry
-- to the held gun -- and it collapsed completely on 2026-08-11, when one bad library read gave
-- every assault-rifle hit to the Terraprisma.
--
-- AttackStaticItemID names the source outright. Measured 2026-08-19 across 252 events with
-- drones firing while a Vortex Beater was held: 181 read DroneLauncher, 14 read
-- YakushimaGun001_4, same WeaponType throughout. It also arrives RARITY-QUALIFIED, which is
-- the same question modelFor exists to answer -- so a family-scoped hit records its own rarity
-- on the way past, from the one place that cannot be wrong about it.
function A.careerKeyForItem(staticId, equippedKey)
  local s = tostring(staticId or "")
  if s == "" or s == "None" or s == "nil" then return nil end
  local scope = cfg.progressScope
  if scope == "family" then
    local fk = "fam:" .. A.familyOf(s)
    A.noteModel(fk, s)
    return fk
  end
  if scope == "model" then return s end
  -- INSTANCE SCOPE cannot be answered by an item id alone: its key carries the physical actor's
  -- GUID and a source item supplies none. Where the source IS the weapon in hand its own key is
  -- already right; otherwise fall back to the model keyspace so a summon's damage lands on a
  -- coherent career of its own instead of silently on whatever is being held.
  if equippedKey and A.staticOf(equippedKey) == s then return equippedKey end
  return s
end

local ATTRPROBE_N = 0   -- probeAttribution line number (uncapped; the FLAG is the budget)
local SWARMDMG_N  = 0   -- probeSwarmDamage line number, same contract

-- THIS client's equipped weapon instance for the key (same "currently equipped"
-- basis the server damage layer used), hand (key, defender, holderLevel) to the
-- SAME onDamage the server counting used.
function A.installMakeDamageLocal(onDamage)
  return (pcall(function()
    RegisterHook("/Script/Pal.PalUtility:MakeDamageInfo", function(self, p1)
      pcall(function()
        local mk = p1 and safe(function() return p1:get() end)
        if mk == nil then return end
        local atk = safe(function() return mk.Attacker end)
        if not alive(atk) then return end
        local me = A.localPawn()
        local same = alive(me) and A.sameActor(atk, me)
        -- MKDBG (melee mystery, 2026-07-22): raw events while the measurement toggle is on --
        -- does melee even come through here, and as WHAT attacker?
        -- WeaponType: 7=Melee 16=Katana 18=Club
        --
        -- UNCAPPED while opted in (2026-08-14), matching what ATTRPROBE below was changed to on
        -- 2026-08-07 for the same reason -- the fix was applied to one probe and not its sibling.
        -- The 12-event budget was spent on swarm hits three minutes before the weapon under
        -- investigation was even drawn, so the probe answered "what happened first" when the
        -- question was "what did I just do". Every real use of this is the second one. An explicit
        -- opt-in diagnostic logs until it is switched off; the counter stays for line numbering.
        if cfg.measureHps then
          MKDBG_N = MKDBG_N + 1
          local acls = safe(function() return atk:GetClass():GetFName():ToString() end)
          local wt = safe(function() return mk.WeaponType end)
          print(string.format("[Arsenal][MKDBG] %d atk=%s wt=%s same=%s\n",
            MKDBG_N, tostring(acls), tostring(wt), tostring(same)))
        end
        -- ATTRIBUTION PROBE (Maiq's experiment, 2026-08-07): the Terraprisma swarm's
        -- hits pass the same-actor gate below (the game credits summon damage to the OWNER),
        -- so they currently earn XP for whatever is EQUIPPED. To split them we need the field
        -- that differs between a swarm hit and a held-weapon hit -- candidates: WeaponType,
        -- HitComponent, Category. Log-only, capped, pure reads of fields this hook already
        -- receives; off unless cfg.probeAttribution.
        -- UNCAPPED while opted in (Maiq, 2026-08-07: the 400-event budget was spent
        -- before the thing he wanted measured -- first-N answers "what happened first",
        -- every real use is "what did I JUST do". Same contract as measureHps: an
        -- explicit opt-in diagnostic logs everything until switched off; the counter
        -- stays for line numbering only.
        if cfg.probeAttribution then
          ATTRPROBE_N = ATTRPROBE_N + 1
          local acls = safe(function() return atk:GetClass():GetFName():ToString() end)
          local wt = safe(function() return mk.WeaponType end)
          local cat = safe(function() return mk.Category end)
          local hc = safe(function() return mk.HitComponent end)
          local hcn = alive(hc) and safe(function() return hc:GetFName():ToString() end) or "nil"
          local dcls = "?"
          do local d = safe(function() return mk.Defender end)
             if alive(d) then dcls = safe(function() return d:GetClass():GetFName():ToString() end) or "?" end end
          local _, ek = A.getEquippedWeapon()
          -- THE FIELDS THAT MIGHT ACTUALLY NAME THE SOURCE (2026-08-19). The first probe run
          -- proved wt/cat/atk/HitComponent carry NO discriminator: 987 drone hits all read
          -- wt=3 cat=1 atk=BP_Player_Female_C, identical to the player's own, and HitComponent
          -- describes the DEFENDER's body part. Every one of those kills was credited to the
          -- held weapon. FPalMakeDamageInfo carries four more fields nothing has ever read --
          -- AttackStaticItemID is an FName for the attack's SOURCE ITEM, which is the exact
          -- question, and bIsPartnerSkillAttackBullet marks partner-skill bullets. If either
          -- separates a summon hit from a held-weapon hit, the sub-50ms flurry GUESS retires
          -- and both the Drone Launcher and the Terraprisma get exact attribution.
          local asid = safe(function() return mk.AttackStaticItemID:ToString() end)
                    or safe(function() return tostring(mk.AttackStaticItemID) end)
          local atype = safe(function() return mk.AttackType end)
          local psb   = safe(function() return mk.bIsPartnerSkillAttackBullet end)
          local ono   = "nil"
          do local o = safe(function() return mk.OverrideNetworkOwner end)
             if alive(o) then ono = safe(function() return o:GetClass():GetFName():ToString() end) or "?" end end
          print(string.format("[Arsenal][ATTR] %d wt=%s cat=%s atk=%s hit=%s def=%s equipped=%s same=%s "
            .. "asid=%s atype=%s psb=%s netowner=%s\n",
            ATTRPROBE_N, tostring(wt), tostring(cat), tostring(acls), tostring(hcn), dcls, tostring(ek), tostring(same),
            tostring(asid), tostring(atype), tostring(psb), tostring(ono)))
        end
        if not same then return end   -- LOCAL PLAYER ONLY
        local def = safe(function() return mk.Defender end)
        local _, key = A.getEquippedWeapon()
        -- THE SOURCE NAMES ITSELF (2026-08-19). AttackStaticItemID is the attack's own item id,
        -- so attribution is a LOOKUP, not a guess. Measured on 252 live events, drones firing
        -- while a Vortex Beater was held:
        --     181  wt=3  equipped=fam:YakushimaGun001  asid=DroneLauncher
        --      14  wt=3  equipped=fam:YakushimaGun001  asid=YakushimaGun001_4
        -- Same WeaponType, same weapon in hand, cleanly separated. Everything this replaces --
        -- arm-on-equip, the wt=3 test, the 50ms flurry window, the emitsWt3 whitelist -- existed
        -- only because wt=3 means "AssaultRifle" and never meant "summon". It routed by holding
        -- the first hit of every flurry wrong on purpose, and collapsed entirely on 2026-08-11
        -- when one bad lookup gave every rifle hit to the Terraprisma.
        --
        -- Falls back to the equipped weapon when the field is empty, so a path that does not
        -- populate it behaves exactly as before rather than losing the hit.
        local srcKey = A.careerKeyForItem(safe(function() return mk.AttackStaticItemID:ToString() end), key)
        local target = srcKey or key
        if not target then return end
        if cfg.probeAttribution and srcKey and srcKey ~= key then
          print(string.format("[Arsenal][SWARM] %s -> %s (held %s)\n",
            tostring(safe(function() return mk.AttackStaticItemID:ToString() end)), tostring(target), tostring(key)))
        end
        onDamage(target, alive(def) and def or nil, A.levelOfChar(atk), nil)
      end)
    end)
  end))
end

-- MELEE RESOLUTION v3 (final form after the dead ends: GetHasWeapon returns a
-- dummy for melee; every wheel/gauge UI function is native-dispatched and our
-- hooks never fire; soft-ptr polling crashes). Sweep the pawn-OWNED weapon
-- ACTORS -- ordinary UObjects, ordinary alive-gates -- and pick the one whose
-- weapondata row is melee-mode. Cached 2s either way so damage events and
-- ticks don't re-sweep.

-- MELEE COUNTER via the damage-REACTION multicast (resurrected from the git
-- baseline 2026-07-22): MakeDamageInfo measurably NEVER fires for melee on a
-- living target; the reaction layer is the Musket lesson's "sees everything"
-- layer, and _ToAll = multicast, so the client should receive it. Counts ONLY
-- melee-resolved keys -- ranged stays on MakeDamageInfo (both on one key
-- would double-count; that retirement lesson still stands).
function A.installMeleeDamage(onDamage, isMeleeKey)
  return (pcall(function()
    RegisterHook("/Script/Pal.PalDamageReactionComponent:CallOnActualDamageProcessed_ToAll",
      function(self, a1, a2, a3)
        pcall(function()
          local atk = a1 and safe(function() return a1:get() end)
          if not alive(atk) then return end
          local me = A.localPawn()
          local same = alive(me) and A.sameActor(atk, me)
          -- Uncapped for the same reason as MKDBG above: a melee question is always about the
          -- swing just taken, never the first twelve of the session.
          if cfg.measureHps then
            MELDBG_N = MELDBG_N + 1
            local acls = safe(function() return atk:GetClass():GetFName():ToString() end)
            print(string.format("[Arsenal][MELDBG] %d atk=%s same=%s\n",
              MELDBG_N, tostring(acls), tostring(same)))
          end
          if not same then return end
          -- SWARM DAMAGE PROBE (2026-08-18). Open question: a Terraprisma summon outlives the
          -- weapon swap, but the LA boost does not -- restorePrev("swapped") puts the vanilla
          -- AttackValue back the moment you change weapons. So does the swarm read AttackValue
          -- per hit (boost lost the instant you swap) or snapshot it when summoned (boost kept
          -- for the life of the summons)? Nothing in the code answers it and neither should a
          -- guess. This logs the ACTUAL applied damage, which is what the two cases disagree
          -- about.
          --
          -- PROTOCOL, and why the probe needs no wt filter: summon, swap to a gun, and do not
          -- attack. Every damage event the local player then deals is a swarm hit, so the log
          -- needs no way to tell them apart. Run it once with a leveled Terraprisma and once
          -- with a low one; if dmg differs, the boost survived the swap.
          --
          -- Sits ABOVE the melee gate on purpose: isMeleeKey filters by what is HELD, and the
          -- whole point is that the thing dealing damage is not what is held.
          if cfg.probeSwarmDamage then
            SWARMDMG_N = SWARMDMG_N + 1
            local d  = a3 and safe(function() return a3:get() end)
            local dv = a2 and safe(function() return a2:get() end)
            local dc = alive(dv) and safe(function() return dv:GetClass():GetFName():ToString() end) or "nil"
            local _, ek = A.getEquippedWeapon()
            print(string.format("[Arsenal][SWARMDMG] %d dmg=%s def=%s equipped=%s\n",
              SWARMDMG_N, tostring(d), tostring(dc), tostring(ek)))
          end
          local def = a2 and safe(function() return a2:get() end)
          if alive(def) and atk == def then return end
          local _, key = A.getEquippedWeapon()
          if not key or not isMeleeKey(key) then return end
          local dmg = a3 and safe(function() return a3:get() end)
          onDamage(key, alive(def) and def or nil, A.levelOfChar(atk), dmg)
        end)
      end)
  end))
end

-- SPLIT DESIGN (2nd CTD lesson, 2026-07-22): the SWEEP (touches many world
-- actors, some mid-destruction -- the lingering-object exposure) runs ONLY
-- from the slow tick, only when there is no LIVE pick, min 3s apart. The hot
-- paths (damage hook, every getEquippedWeapon call) do a pure cache read:
-- one alive() on OUR OWN stable weapon actor, zero foreign-object reads.
local meleeRes = { sweepAt = -10, weapon = nil, key = nil, lastLogged = nil }

function A.meleeKeyCached()
  if meleeRes.key and alive(meleeRes.weapon) then return meleeRes.weapon, meleeRes.key end
  return nil
end

-- EVERY WEAPON THE LOCAL PLAYER OWNS RIGHT NOW, as { weapon, key } pairs.
-- Same shape as the melee sweep -- one bounded FindAllOf, owner-filtered -- but it keeps
-- ranged weapons too and does not pick a winner. Only the restore-to-stock pass uses it:
-- that pass has to reach weapons the player is NOT holding, which is the whole point of it,
-- and it is a mode the player turns on deliberately rather than something running in normal
-- play. Callers own the rate limiting; this walks foreign actors and must not run per frame.
function A.ownedWeapons()
  local out = {}
  local me = A.localPawn(); if not alive(me) then return out end
  for _, w in ipairs(safe(function() return FindAllOf("PalWeaponBase") end) or {}) do
    if alive(w) then
      local own = safe(function() return w:GetOwner() end)
      if alive(own) and A.sameActor(own, me) then
        local id = safe(function() return w.ownItemID.StaticId:ToString() end)
             or safe(function() return w:GetItemId().StaticId:ToString() end)
        if isPlayerWeapon(id) then
          local key = A.instanceKey(w, id)
          if key then out[#out + 1] = { weapon = w, key = key } end
        end
      end
    end
  end
  return out
end

function A.meleeSweep()
  local now = os.clock()
  if (now - meleeRes.sweepAt) < 15 then return end
  -- If currently cached weapon is valid and actively held, skip sweeping GUObjectArray
  if alive(meleeRes.weapon) and meleeRes.key then
    local hidden = safe(function() return meleeRes.weapon:IsHidden() end)
    if hidden == false then
      meleeRes.sweepAt = now
      return
    end
  end
  meleeRes.sweepAt = now
  meleeRes.weapon, meleeRes.key = nil, nil
  local me = A.localPawn(); if not alive(me) then return end
  local seen, owned, picked = 0, 0, nil
  for _, w in ipairs(safe(function() return FindAllOf("PalWeaponBase") end) or {}) do
    if alive(w) then
      seen = seen + 1
      local own = safe(function() return w:GetOwner() end)
      if alive(own) and A.sameActor(own, me) then
        owned = owned + 1
        local id = safe(function() return w.ownItemID.StaticId:ToString() end)
             or safe(function() return w:GetItemId().StaticId:ToString() end)
        if isPlayerWeapon(id) then
          local row = A.wdLookup(id)   -- the funnel, never a raw WEAPONS index (see A.wdLookup)
          if row and row.mode == "melee" then
            local key = A.instanceKey(w, id)
            if key then
              -- PREFER THE WEAPON IN HAND (2026-08-08): with Terraprisma summons out,
              -- the player owns TWO live melee actors -- the blade (stowed, hidden)
              -- and whatever is actually held (visible). A hidden pick only stands
              -- until a visible one appears; a visible pick wins outright.
              local hidden = safe(function() return w:IsHidden() end)
              if hidden ~= true then
                meleeRes.weapon, meleeRes.key = w, key; picked = id; break
              elseif meleeRes.key == nil then
                meleeRes.weapon, meleeRes.key = w, key; picked = id  -- fallback, keep looking
              end
            end
          end
        end
      end
    end
  end
  if picked ~= meleeRes.lastLogged then
    meleeRes.lastLogged = picked
    print(string.format("[Arsenal][MELEE] sweep: %d weapon actors, %d owned, picked=%s\n",
      seen, owned, tostring(picked)))
  end
end

-- ---------------------------------------------------------------------------
-- A.isAiming() -- is the player currently aiming down sights?
--
-- Returns true / false / nil. NIL IS LOAD-BEARING: "cannot tell on this build", which the caller
-- must treat as "leave the panel alone" rather than "not aiming".
--
-- READ THE HEADER DUMP, DO NOT GUESS PROPERTY NAMES (learned the hard way, 2026-07-28).
-- The first cut of this function probed eight plausible BOOLEAN PROPERTIES -- shooter.IsAiming,
-- pawn.bIsAiming, and friends -- and shipped in 1.9.1. It reported UNAVAILABLE in game, because
-- none of them exist. UPalShooterComponent has no aiming bool at all:
--     TMap<EPalShooterFlagContainerPriority, bool> IsAimingFlags;   // 0x04D8
-- a MAP of priority -> flag, with the answer exposed through a UFunction:
--     bool IsAiming();
-- Reading `shooter.IsAiming` as a property therefore yields a function object, never a boolean,
-- so every candidate failed the type check and the feature was inert.
--
-- The answer was sitting in ue4ss/CXXHeaderDump/Pal.hpp the whole time. Thirty seconds of
-- grepping it beat two rounds of guessing, and the vault already says so about UPanelWidget.
-- WHEN AN ACCESSOR IS UNKNOWN, DUMP THE CLASS -- do not ship a candidate list.
--
-- SAFETY: IsAiming() and IsRequestAiming() take no arguments and return a plain bool -- no
-- struct out-param, which is the shape on the crash list. Calls are pcall'd behind alive()
-- gates. IsAiming_Layered(Priority) is deliberately NOT used: it needs an enum argument and
-- guessing enum values is the same mistake in a different costume.
local aimAccessor, aimReported = nil, false
function A.isAiming()
  local pawn = A.localPawn()
  if not alive(pawn) then return nil end
  local shooter = safe(function() return pawn.ShooterComponent end)
  if not alive(shooter) then
    -- No ShooterComponent means MOUNTED (a ride pal has none) or no weapon context. Unknown,
    -- NOT false -- see the localPawn note above; OutdoorLootFilter broke on exactly this.
    return nil
  end
  local tries = {
    { "shooter:IsAiming()",        function() return shooter:IsAiming() end },
    { "shooter:IsRequestAiming()", function() return shooter:IsRequestAiming() end },
  }
  if aimAccessor then
    local v = safe(tries[aimAccessor][2])
    if type(v) == "boolean" then return v end
    aimAccessor = nil                     -- stopped answering (respawn/remount): re-probe
  end
  for i, t in ipairs(tries) do
    local v = safe(t[2])
    if type(v) == "boolean" then
      if aimAccessor ~= i then
        aimAccessor = i
        if not aimReported then
          aimReported = true
          pcall(function() print("[Arsenal] aim detection using " .. t[1] .. "\n") end)
        end
      end
      return v
    end
  end
  if not aimReported then
    aimReported = true
    pcall(function()
      print("[Arsenal] aim detection UNAVAILABLE -- PalShooterComponent:IsAiming() did not "
        .. "answer. The zoom-to-show-panel option will do nothing; everything else is "
        .. "unaffected. Please report this with your game version.\n")
    end)
  end
  return nil
end

function A.getEquippedWeapon()
  local pawn = A.localPawn() or safe(function() return FindFirstOf("PalPlayerCharacter") end)
  if not alive(pawn) then return nil end
  local shooter = safe(function() return pawn.ShooterComponent end)
              or safe(function() return pawn:GetShooterComponent() end)
  if not alive(shooter) then
    -- Mounted Pals have no ShooterComponent; early exit immediately without scanning world UObjects
    return nil
  end
  if not alive(shooter) then return nil end
  local weapon = safe(function() return shooter:GetHasWeapon() end)
  if not alive(weapon) then return nil end
  local id = safe(function() return weapon.ownItemID.StaticId:ToString() end)
          or safe(function() return weapon:GetItemId().StaticId:ToString() end)
  -- per-instance, so the HUD reads THIS gun's row rather than the model's
  if not isPlayerWeapon(id) then
    -- MELEE FALLBACK v2 (the Katana lesson + the soft-ptr CRASH lesson,
    -- 2026-07-22): melee weapons are NOT ShooterComponent weapons (GetHasWeapon
    -- hands back a BP_ThrowWeapon_Dummy, id None). v1 polled the gauge's
    -- nowHasWeapon soft pointer and CRASHED (0xffffffffffffffff: a soft-ptr
    -- deref on a freed actor is a native AV nothing catches). v2 is EVENT-FED:
    -- A.noteCurrentWeapon() caches the actor+id when the game hands it to its
    -- own UI functions as a live parameter. Here we only READ the cache.
    local w2, key2 = A.meleeKeyCached()   -- PURE cache read: hot-path safe
    if key2 then return w2, key2 end
    -- RAWID, equipped-side: one line per unknown shooter-side id
    local k = "eq|" .. tostring(id)
    if not RAWID_SEEN[k] then
      RAWID_SEEN[k] = true
      local cls = safe(function() return weapon:GetClass():GetFName():ToString() end)
      print(string.format("[Arsenal][RAWID] equipped: staticId=%s  class=%s  known=false -- not in weapondata: no XP/panel until its id is added\n",
        tostring(id), tostring(cls)))
    end
    return weapon, nil  -- fists/None/NPC: no key, no ERROR spam at spawn-in
  end
  return weapon, A.instanceKey(weapon, id)
end

-- Weapon-FIRE hook (independent of the projectile). Needed for explosive launchers whose projectile is not
-- a PalBullet (Meteor Launcher etc.), so they never hit an actor and earn no XP on the bullet hooks above.
-- OnShootBullet fires on the shooter each time it shoots a round; we resolve the equipped weapon id and
-- hand it to onFire (which only actually grants XP for launcher types). IsValid-guarded.
function A.installFire(onFire)
  return (pcall(function()
    RegisterHook("/Script/Pal.PalShooterComponent:OnShootBullet", function(self)
      pcall(function()
        local sc = self:get()
        if not alive(sc) then return end
        local weapon = safe(function() return sc:GetHasWeapon() end)
        if not alive(weapon) then return end
        local id = safe(function() return weapon.ownItemID.StaticId:ToString() end)
            or safe(function() return weapon:GetItemId().StaticId:ToString() end)

        -- RAW ID PROBE. Every gate in this mod keys off `id`, so a weapon whose id
        -- we cannot read is invisible EVERYWHERE -- no XP, no damage, no magazine --
        -- and silently, because isPlayerWeapon() just returns false.
        -- The Musket is exactly that: AR and shotgun log FIRE+RATE perfectly, the
        -- Musket logs NOTHING, and something reported the FName "None".
        -- I have theorised twice about which id it "should" be. Instead: print what
        -- the game ACTUALLY says, before any gate can drop it. Deduped by id+class.
        do
          local cls = safe(function() return weapon:GetClass():GetFName():ToString() end)
          local k = tostring(id) .. "|" .. tostring(cls)
          if not RAWID_SEEN[k] then
            RAWID_SEEN[k] = true
            print(string.format(
              "[Arsenal][RAWID] fired: staticId=%s  weaponClass=%s  known=%s  dynIdReadable=%s\n",
              tostring(id), tostring(cls), tostring(isPlayerWeapon(id) and true or false),
              tostring(A.instanceKey(weapon, id) ~= nil)))
          end
        end

        if isPlayerWeapon(id) then
          if cfg.measureHps then print("[Arsenal][SHOT] " .. tostring(id) .. "\n") end  -- HPS measure: one line/shot (log ts = shot time)
          local key = A.instanceKey(weapon, id)
          if key then onFire(key) end      -- unidentifiable gun: earn nothing
        end
      end)
    end)
  end))
end

return A
