-- server_durability.lua -- the MaxDurability write that only the server can make.
--
-- WHY THIS FILE EXISTS. Measured 2026-08-18 with a read-only census running on the
-- dedicated server while the client wrote to the same two weapons:
--     server  YakushimaBlade003_2  MaxDurability 6000   client wrote 15015
--     server  YakushimaGun001_4    MaxDurability 5000   client wrote 12250
-- Two seconds apart, both readbacks clean on their own side. Durability (the
-- consumable) matched across the wire; MaxDurability (the bar) did not. The field
-- replicates DOWN and never travels UP, so every durability boost this mod has ever
-- applied on a dedicated server has been a number on the client and nothing else.
--
-- STAGE 1 IS AN ACCEPTANCE TEST AND IS DELIBERATELY NOT THE FEATURE. The open
-- question is not what number to write -- it is whether a server-side write is kept
-- at all, or re-derived from the item save data on the next equip or world load. A
-- progression system feeding the wrong side of that answer is wasted work, so the
-- level source here is a flat multiplier from config and nothing reads a store.
-- If the bar holds in play, the level source becomes the next problem. If it does
-- not, there was never a durability feature to build on a dedicated server.
--
-- OFF BY DEFAULT, AND IT APPLIES TO EVERY WEAPON ON THE SERVER. There is no owner
-- filter yet: identifying the holder of each weapon actor is work that only matters
-- once the write is known to stick. On a shared server that means every player gets
-- the same bar, which is a real gameplay change for people who did not ask for it --
-- hence the default, and hence keeping the test window short.

local M = {}

local ok, cfg = pcall(require, "config")
local P = require("progression")
if not ok or type(cfg) ~= "table" then cfg = {} end

local function log(s) print("[LA/server-dur] " .. tostring(s) .. "\n") end

local function safe(fn)
  local good, v = pcall(fn)
  if good then return v end
  return nil
end

local function alive(o)
  if o == nil then return false end
  local good, v = pcall(function() return o:IsValid() end)
  return good and v == true
end

-- Per-weapon memory of what we last wrote. Two jobs, both learned on the client side:
--   lastWritten -- the reference an external bench repair is detected against
--   seenTarget  -- lets the drift watch tell a write that STUCK from a write that is
--                  re-applied every pass and undone between them. Without it both
--                  produce one log line and then silence, which is exactly the
--                  ambiguity this file exists to remove.
local lastWritten, seenTarget, driftLogged, lastSeenDur = {}, {}, {}, {}

-- LEVELS REPORTED OVER THE CHANNEL, keyed by weapon key. Empty until a client sends,
-- and a weapon with no entry falls back to the flat multiplier -- so an unmodded or
-- older client keeps exactly the stage-1 behaviour instead of losing its boost.
local reported = {}

-- The identity of a weapon ACTOR across passes. Only ever a short-lived bookkeeping
-- key: addresses get recycled, so this is never persisted and never a store key.
local function keyOf(w)
  local n = safe(function() return w:GetFullName() end)
  return n and tostring(n) or nil
end

-- THE WEAPON MODEL, which is the keyspace the channel speaks. keyOf() identifies an
-- ACTOR and is useless for this: a reported level is about a weapon kind, not about one
-- spawned copy of it. BP_YakushimaGun001_C -> YakushimaGun001.
local function modelOf(w)
  local cls = safe(function() return w:GetClass():GetFName():ToString() end)
  if type(cls) ~= "string" or cls == "" then return nil end
  return (cls:gsub("^BP_", ""):gsub("_C$", ""))
end

-- THE CURVE IS P.durabilityMult, and the client calls the same function.
--
-- This comment used to say the curve here matched the client "exactly ... both halves in
-- agreement", beside a second implementation of it. They differed: this side divided by
-- cfg.durabilityMaxLevel, the client by the weapon's own maxLv. Equal in practice only
-- because the xp model rewrites every maxLv to 80 -- so the claim was true by accident and
-- would have stopped being true the moment one weapon kept its own ceiling.
--
-- A comment asserting two things agree is worth less than one function they both call.
local function multFor(key, flat)
  local r = key and reported[key]
  if not r then return flat, false end
  -- THE SAME FUNCTION THE CLIENT CALLS. This used to be a second copy of the curve, and the
  -- comment above claimed it matched "exactly" -- it divided by cfg.durabilityMaxLevel where
  -- the client divided by the weapon's own maxLv. Equal today, only because the xp model
  -- rewrites every maxLv to 80.
  return P.durabilityMult(cfg, r.level, nil, r.prestige), true
end

function M.report(key, level, prestige)
  if not key then return end
  reported[key] = { level = level, prestige = prestige }
end

local function applyOne(w, flatMult)
  if not alive(w) then return end
  local dyn = safe(function() return w.ownWeaponDynamicData end)
  local st  = safe(function() return w.ownWeaponStaticData end)
  if not alive(dyn) or not alive(st) then return end

  -- BASE IS THE STATIC TEMPLATE, NEVER THE LIVE DYNAMIC VALUE. The per-model static
  -- Durability is a field this mod never writes, so it stays vanilla and cannot
  -- compound. Reading the dynamic value as a base would re-multiply our own boost on
  -- every pass -- the poison-cache mistake already paid for once on the damage path.
  local base = tonumber(safe(function() return st.Durability end))
  if type(base) ~= "number" or base <= 0 then return end

  -- A weapon the channel has told us about gets its real curve; everything else keeps
  -- the flat stage-1 multiplier, so an unmodded client is never made worse off.
  local model = modelOf(w)
  local mult, fromReport = multFor(model, flatMult)
  local target = math.floor(base * mult + 0.5)
  if target <= base then return end

  local k = keyOf(w)
  local oldMax = tonumber(safe(function() return dyn.MaxDurability end))
  local oldDur = tonumber(safe(function() return dyn.Durability end))
  if type(oldMax) ~= "number" or oldMax <= 0 then return end

  if math.abs(oldMax - target) < 1 then
    if k then seenTarget[k] = target end

    -- REPAIR TOP-UP, and the reason this branch is not just a return.
    --
    -- A bench repairs to the VANILLA max, not to ours: a repair on a boosted weapon
    -- lands at base out of target -- 6000 of 18000, a third of a bar that reads full
    -- at the bench. Returning early here meant that state was never corrected, so the
    -- fill only arrived by accident on the next re-equip, when the actor respawns
    -- vanilla and the write below recomputes the ratio at 100%. That is the "it takes
    -- two repairs" report: the first repair did nothing until something else happened.
    --
    -- ROSE, not merely EQUALS. Durability passes through the vanilla base on the way
    -- DOWN during normal use as well, and topping up there would be a free repair on
    -- every trip past 6000. Only a rise since the previous pass is a repair.
    local prevSeen = k and lastSeenDur[k]
    if type(oldDur) == "number" and type(prevSeen) == "number"
       and oldDur > prevSeen + 1 and oldDur <= base + 1 and target > base then
      pcall(function() dyn.Durability = target end)
      local backDur = tonumber(safe(function() return dyn.Durability end))
      if k then lastWritten[k] = target; lastSeenDur[k] = backDur or target end
      log(string.format("%s repaired to the vanilla max (%s of %d) -- filled to %d, readback=%s",
        tostring(k or "?"), tostring(oldDur), target, target, tostring(backDur)))
      return
    end

    if k then lastSeenDur[k] = oldDur end
    return   -- already ours and no repair to complete: do not rewrite, do not re-log
  end

  -- DRIFT WATCH. A bar we had already set correctly that comes back changed means an
  -- authority outside this file owns the field, and the answer to stage 1 is no.
  if k and seenTarget[k] and math.abs(seenTarget[k] - target) < 1 and not driftLogged[k] then
    driftLogged[k] = true
    log(string.format("REVERTED: wrote MaxDurability %d, it came back %s -- the server is "
      .. "not keeping this write", target, tostring(oldMax)))
  end

  -- Resize the bar, preserve the fill %. Durability is a consumable; topping it up on
  -- every pass would be free infinite repair.
  local pct = (type(oldDur) == "number") and (oldDur / oldMax) or 1
  local last = k and lastWritten[k]
  if type(last) == "number" and type(oldDur) == "number"
     and oldDur > last + 1 and oldDur >= base - 1 then
    pct = 1   -- rose to vanilla-full since our last write: a bench repair, honor it
  end
  if pct < 0 then pct = 0 elseif pct > 1 then pct = 1 end
  local newDur = math.floor(pct * target + 0.5)

  pcall(function() dyn.MaxDurability = target end)
  pcall(function() dyn.Durability = newDur end)

  local backMax = tonumber(safe(function() return dyn.MaxDurability end))
  if k then lastWritten[k] = newDur; seenTarget[k] = target; lastSeenDur[k] = newDur end
  log(string.format("%s MaxDurability %s->%d (x%.2f %s) Durability->%d (%.0f%%) readback=%s",
    tostring(model or k or "?"), tostring(oldMax), target, mult,
    fromReport and "reported" or "flat", newDur, pct * 100, tostring(backMax)))
end

-- The bookkeeping tables are keyed on actor names, and actors are recycled constantly --
-- every equip mints a new one. Left alone on a server that runs for weeks those tables
-- only grow. Dropping anything not seen this pass bounds them to the weapons currently
-- in the world, which is the only set any of them is ever consulted for.
local function prune(seen)
  for _, t in ipairs({ lastWritten, seenTarget, driftLogged, lastSeenDur }) do
    local dead
    for k in pairs(t) do
      if not seen[k] then dead = dead or {}; dead[#dead + 1] = k end
    end
    -- Collected first: adding or removing keys while iterating with pairs is undefined.
    if dead then for _, k in ipairs(dead) do t[k] = nil end end
  end
end

local function pass(mult)
  local all = safe(function() return FindAllOf("PalWeaponBase") end)
  if type(all) ~= "table" then return end
  local seen = {}
  for _, w in ipairs(all) do
    local k = alive(w) and keyOf(w)
    if k then seen[k] = true end
    applyOne(w, mult)
  end
  prune(seen)
end

function M.start()
  if cfg.serverDurability ~= true then
    log("idle -- set serverDurability = true in config.lua to run the acceptance test")
    return
  end

  local mult = tonumber(cfg.serverDurabilityMult)
            or tonumber(cfg.durabilityMaxMult)
            or tonumber(cfg.durabilityMult) or 1
  if mult <= 1 then
    log(string.format("idle -- multiplier %.2f is not a boost", mult))
    return
  end

  local firstMs = tonumber(cfg.serverDurabilityFirstMs) or 20000
  local everyMs = tonumber(cfg.serverDurabilityEveryMs) or 5000

  log(string.format("armed -- x%.2f flat, first pass in %dms then every %dms", mult, firstMs, everyMs))

  -- THE CHANNEL. A weapon it reports gets its real curve; anything it never mentions
  -- keeps the flat multiplier, so a failed hook degrades to stage 1 rather than to
  -- nothing. listen() returning false is that failure and it says so in the log --
  -- silence on this channel is otherwise indistinguishable from nobody having sent yet.
  local okRpc, RPC = pcall(require, "rpc")
  if okRpc and type(RPC) == "table" then
    RPC.listen(cfg, function(key, lv, pr) M.report(key, lv, pr) end)
  else
    log("rpc module unavailable -- every weapon stays on the flat multiplier")
  end

  -- The first pass waits out world streaming. A FindAllOf walk from a timer while the
  -- world streams reads a garbage pointer through every pcall and IsValid gate -- the
  -- 2026-08-03 crash family. On a dedicated server the client kit's epoch-settle seam
  -- does not exist, so this delay is the whole mitigation.
  pcall(function()
    -- timer-check: allow dedicated server has no UI seam, and the walk IS the feature
    ExecuteWithDelay(firstMs, function()
      pcall(function() pass(mult) end)
      -- timer-check: allow see above -- a single LoopAsync, never one timer per pass
      pcall(function()
        LoopAsync(everyMs, function()
          pcall(function() pass(mult) end)
          return false
        end)
      end)
    end)
  end)
end

return M
