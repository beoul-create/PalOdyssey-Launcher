-- ============================================================================
--  store.lua -- CLIENT-OWNED persistent proficiency store.
--
--  The client counts its own hits and owns the numbers, so it owns this file.
--  Schema:
--    return { __version="wpv2", __savedAt=<os.time of the last successful save>,
--             [worldKey] = { [key] = {
--               level, xp, hits, hud = { name, maxLv, xpNext, dmg={...}, mag={...} } } } }
--
--  PATHS: derived from THIS SCRIPT, never from the working directory. See the
--  long note below -- guessing at the cwd is what cost a player a level-68
--  weapon. Writes go to <shared>/<name>, via a .tmp + os.rename swap so a crash
--  mid-write cannot corrupt the store.
-- ============================================================================

local S = {}
local safe = require("darn").safe

-- ============================================================================
--  WHERE THE STORE LIVES -- DERIVED FROM THE SCRIPT (2026-08-03)
-- ============================================================================
-- WHAT THIS USED TO BE, and why it was worse than one wrong path:
--
--     local CAND_DIRS = {
--       "../../../Mods/NativeMods/UE4SS/Mods/shared/",   -- cwd=Win64 (Workshop)
--       "Mods/NativeMods/UE4SS/Mods/shared/",            -- cwd=Palworld root
--       "Mods/shared/",                                  -- cwd=UE4SS root
--       "ue4ss/Mods/shared/",                            -- classic hand-install
--       "",                                              -- cwd itself
--     }
--
-- Five guesses, all resolved against the PROCESS WORKING DIRECTORY, and resolveDir() took the
-- FIRST one that happened to hold a file. Every one of those entries names the same physical
-- shared/ folder on a machine with exactly one UE4SS install -- which is why it survived so long.
-- It stops being the same folder the moment a machine has two: the Workshop UE4SS under
-- Pal\Binaries\Win64\Mods\NativeMods\UE4SS\ and a classic hand-installed ue4ss\ beside the game
-- (the pair this family of mods runs into constantly -- client Workshop, server classic). Then
-- which candidate wins depends on HOW THE GAME WAS LAUNCHED, because that is what sets the cwd.
--
-- ATSURAELU (Nexus, 2026-08-02) hit the consequence and diagnosed it himself: the mod created a
-- SECOND WeaponProficiency-store.lua in the other shared/ folder, that one then won the
-- first-found race on every subsequent boot, and it SHADOWED his real store. His level-68 weapon
-- was still sitting on disk, in a file the mod had stopped looking at. Nothing was corrupted and
-- nothing was deleted -- the mod simply read the wrong file and reported itself healthy, which is
-- this project's signature failure and now its third occurrence in this one file.
--
-- So: one location, computed from where this file actually is. debug.getinfo(1,"S").source gives
-- the running script's own path, so the answer is identical no matter what launched the game.
-- Same idiom as ui.lua's CONFIG_PATH and PalsLearnOverTime's BASE; do not re-invent it.
--
-- The store stays in shared/ (2026-07-22, unchanged): a Workshop update re-copies the MOD folder
-- and would wipe a store kept beside the scripts. shared/ is a sibling of the mod folder, so it
-- survives. That is why this is Scripts/ -> ../ (mod folder) -> ../shared/ and not just ../.
local SRC_DIR = (debug.getinfo(1, "S").source or ""):gsub("^@", ""):gsub("[^/\\]+$", "")
local MOD_DIR = (SRC_DIR ~= "" and SRC_DIR or "ue4ss/Mods/WeaponProficiency/Scripts/") .. "../"
local SHARED_DIR = MOD_DIR .. "../shared/"

-- ============================================================================
--  MIGRATION READS -- THESE ARE READ-ONLY. DO NOT WRITE THROUGH THEM.
-- ============================================================================
-- The old guesses cannot simply be deleted: players have real stores sitting at whichever of them
-- won on their machine, and some of those locations are NOT derivable from the script (the cwd
-- itself, and a classic ue4ss\ tree that this Workshop copy knows nothing about). So the list
-- survives as a list of places to LOOK, consulted once and never written to.
--
-- If you are here because datapath-check.js's rule says cwd-relative literals are forbidden: it
-- is satisfied because this file derives its real path above, and these are deliberately the
-- exception. A cwd-relative READ that loses a race picks the wrong file; a cwd-relative WRITE
-- creates the second file that starts the race. Only the second one is the bug. Keep them read-only.
local MIGRATION_DIRS = {
  SHARED_DIR,                                                -- the real one, first
  "../../../Mods/NativeMods/UE4SS/Mods/shared/",             -- cwd=Win64 (Workshop)
  "Mods/NativeMods/UE4SS/Mods/shared/",                      -- cwd=Palworld root
  "Mods/shared/",                                            -- cwd=UE4SS root
  "ue4ss/Mods/shared/",                                      -- classic hand-install
  "",                                                        -- cwd itself
}
-- pre-2026-07-22 store location (beside the scripts), under its historical name too
local LEGACY_DIRS = {
  MOD_DIR,                                                   -- script-derived: always right
  "../../../Mods/NativeMods/UE4SS/Mods/WeaponProficiency/",
  "Mods/NativeMods/UE4SS/Mods/WeaponProficiency/",
  "Mods/WeaponProficiency/",
  "ue4ss/Mods/WeaponProficiency/",
}

function S.new(fileName, version)
  local self = { path = nil, data = nil, version = version or "wpv2", fileName = fileName or "prof-store.lua" }

  -- ==========================================================================
  --  WRITE-AHEAD JOURNAL + SELF-HEAL (2026-07-28)
  -- ==========================================================================
  -- WHY THIS EXISTS. On 2026-07-27 the store stopped saving and nobody knew for 36 hours. What
  -- eventually recovered the lost levels was the UE4SS log -- an ACCIDENTAL journal, never
  -- designed as one, and one that ships to nobody. Players hitting the same failure had no such
  -- luck, and several reported it.
  --
  -- The important property of that failure: NOTHING WAS WRITTEN AT ALL. So a backup scheme that
  -- rotates on successful save is worthless against it -- .bak froze at the same instant as the
  -- primary, because .bak IS the previous primary. The defence has to be a write path that does
  -- not share the failure mode of the one it protects.
  --
  -- Hence an APPEND-ONLY journal. One short line per level-up. It cannot be killed the way
  -- serialize() was, because there is no document to walk: a bad value can corrupt at most its
  -- own line, and load() skips lines that do not parse.
  --
  -- THE INVARIANT that makes healing trivially correct:
  --     the journal contains ONLY records not yet known to be in the store.
  -- Appended on every level-up; TRUNCATED after a successful save. So on boot, anything still in
  -- the journal is by definition unpersisted, and replaying it is exactly the repair. If the
  -- truncate itself fails, the journal merely replays records the store already has -- and the
  -- heal is idempotent (it only ever raises a level, never lowers one), so that is harmless.
  local function nowSec()
    local ok, t = pcall(os.time)
    return (ok and type(t) == "number") and t or 0
  end
  self.lastSaveOk = nowSec()
  self.healed = nil

  function self:journalAppend(worldKey, key, level, xp, hits)
    if not self.path or type(key) ~= "string" or type(level) ~= "number" then return false end
    if level ~= level or level == math.huge or level == -math.huge then return false end
    local f = io.open(self.path .. ".journal", "a")     -- APPEND: never truncates, never rewrites
    if not f then return false end
    local line = string.format("{w=%q,k=%q,lv=%d,xp=%d,hits=%d,t=%d}\n",
      tostring(worldKey or "?"), key, math.floor(level),
      math.floor(tonumber(xp) or 0), math.floor(tonumber(hits) or 0), nowSec())
    local ok = pcall(function() f:write(line); f:flush() end)
    pcall(function() f:close() end)
    return ok
  end

  local function journalRead()
    local f = io.open(self.path .. ".journal", "r")
    if not f then return {} end
    local body = nil
    local ok = pcall(function() body = f:read("*a") end)
    pcall(function() f:close() end)
    if not ok or type(body) ~= "string" then return {} end
    local recs = {}
    for line in body:gmatch("[^\r\n]+") do
      -- EACH LINE PARSED ALONE. One truncated line -- a crash mid-append -- must not cost the
      -- other records, which is the whole reason this is not one big table.
      local chunk = load("return " .. line, "@journal", "t", {})
      if chunk then
        local okr, rec = pcall(chunk)
        if okr and type(rec) == "table" and type(rec.k) == "string" and type(rec.lv) == "number" then
          recs[#recs + 1] = rec
        end
      end
    end
    return recs
  end

  function self:journalClear()
    local f = io.open(self.path .. ".journal", "w")
    if not f then return false end
    pcall(function() f:close() end)
    return true
  end

  -- ROLLING GENERATIONS. This would NOT have caught the 2026-07-27 freeze -- nothing was being
  -- written -- but it is the defence against the store's OTHER proven failure: the pre-1.4.4
  -- remove-then-rename that wiped every weapon in every world. Taken once per session, from a
  -- store we have just confirmed parses and holds worlds, so a generation is never a copy of
  -- something already broken.
  local GENERATIONS = 3
  local function rotateBackups(body)
    if type(body) ~= "string" or body == "" then return end
    for i = GENERATIONS - 1, 1, -1 do
      local from, to = self.path .. ".gen" .. i, self.path .. ".gen" .. (i + 1)
      local fh = io.open(from, "rb")
      if fh then
        local b = nil
        pcall(function() b = fh:read("*a") end); pcall(function() fh:close() end)
        if b then
          local w = io.open(to, "wb")
          if w then pcall(function() w:write(b) end); pcall(function() w:close() end) end
        end
      end
    end
    local w = io.open(self.path .. ".gen1", "wb")
    if w then pcall(function() w:write(body) end); pcall(function() w:close() end) end
  end

  -- ONE ANSWER, NOT A RACE. This used to return whichever of five cwd-relative guesses happened
  -- to hold a file first (see the header). Now there are exactly two possible answers and both
  -- come from the script's own location, so the same machine gives the same one every launch
  -- however the game was started.
  --
  -- The fallback exists because shared/ is a SIBLING of the mod folder and nothing guarantees it
  -- has been created: the Nexus zip ships one, a Workshop subscription does not, and Lua 5.1 has
  -- no portable mkdir (os.execute is not an option in a game process). If we cannot open a file
  -- there we write beside the mod instead -- still script-derived, still a single deterministic
  -- location, but a Workshop update re-copies that folder, so say so out loud. The next boot after
  -- anything creates shared/ will find that file via LEGACY_DIRS[1] and migrate it in.
  local warnedFallback = false
  local function resolveDir()
    local f = io.open(SHARED_DIR .. self.fileName, "r")
    if f then f:close(); return SHARED_DIR end
    -- NOTE: "a" does not truncate, and on a missing file it CREATES an empty one -- which is why
    -- load() gates the migration on how many worlds actually loaded rather than on loadfile
    -- succeeding. An empty file parses perfectly and carries nothing.
    local w = io.open(SHARED_DIR .. self.fileName, "a")
    if w then w:close(); return SHARED_DIR end
    if not warnedFallback then
      warnedFallback = true
      print("[Arsenal] cannot write to " .. SHARED_DIR .. " (the folder may not exist) -- keeping "
        .. "the store beside the mod instead. NOTE: a Workshop update re-copies the mod folder, so "
        .. "create a 'shared' folder next to the WeaponProficiency folder to make this permanent.\n")
    end
    return MOD_DIR
  end

  -- A SERIALIZER THAT CANNOT FAIL (2026-07-28). This is the last thing standing between a
  -- player's progress and losing it, and for a day and a half it was the thing that lost it.
  --
  -- The number branch was:
  --     (v == math.floor(v)) and string.format("%d", v) or string.format("%.10g", v)
  -- In Lua 5.4 string.format("%d", v) RAISES "number has no integer representation" for a float
  -- with no exact integer form -- and math.floor(inf) == inf, so infinity passes the guard and
  -- goes straight into the raising call. NaN fails the guard and takes the %.10g branch, which
  -- emits the literal text `nan`: not valid Lua, so the file would load-fail on the next boot
  -- and read as "no data". Either way one bad value anywhere in the tree destroyed the whole
  -- save, and the caller wrapped this in safe() so nobody heard about it.
  --
  -- Rules now:
  --   * every number is checked before formatting, and a non-finite one is written as nil (the
  --     key simply goes absent) rather than raising or emitting unparseable text
  --   * the KEY PATH of anything dropped is recorded, so the producer can be found instead of
  --     guessed at -- that is what took a day and a half here
  --   * %.17g for floats: %.10g silently rounds, so a value did not survive a round trip
  local function serialize(t)
    local out, dropped, path = {}, {}, {}
    local function finite(v) return v == v and v ~= math.huge and v ~= -math.huge end
    local function emit(v)
      local tv = type(v)
      if tv == "number" then
        if not finite(v) then
          dropped[#dropped+1] = table.concat(path, ".") .. "=" .. tostring(v)
          out[#out+1] = "nil"
        elseif math.type and math.type(v) == "integer" then
          out[#out+1] = string.format("%d", v)
        else
          -- An integral FLOAT still has to round-trip as a number; %.17g is exact for a double.
          local ok, s = pcall(string.format, "%.17g", v)
          if not ok then
            dropped[#dropped+1] = table.concat(path, ".") .. "=<unformattable>"
            out[#out+1] = "nil"
          else out[#out+1] = s end
        end
      elseif tv == "boolean" then out[#out+1] = tostring(v)
      elseif tv == "string" then out[#out+1] = string.format("%q", v)
      elseif tv == "table" then
        out[#out+1] = "{"
        for k, val in pairs(v) do
          local kt = type(k)
          if kt == "string" then out[#out+1] = "[" .. string.format("%q", k) .. "]="
          elseif kt == "number" and finite(k) then out[#out+1] = "[" .. tostring(k) .. "]="
          else out[#out+1] = nil end                 -- an unusable key: skip the pair entirely
          if out[#out] ~= nil then
            path[#path+1] = tostring(k)
            emit(val)
            path[#path] = nil
            out[#out+1] = ","
          end
        end
        out[#out+1] = "}"
      else out[#out+1] = "nil" end                   -- functions, userdata: not our data
    end
    emit(t)
    return "return " .. table.concat(out), dropped
  end

  function self:load()
    local dir = resolveDir()
    self.path = dir .. self.fileName
    -- NOTE: gate the legacy migration on loaded DATA, not on loadfile success --
    -- resolveDir's writability probe can leave an EMPTY file at the new path,
    -- which loadfiles fine but carries nothing.
    -- how many WORLD buckets a loaded store carries (ignore the version stamp).
    -- An "empty but valid" table is the signature of the wipe described in
    -- save(): the store file vanished and something wrote {} back over it.
    local function entries(t)
      if type(t) ~= "table" then return -1 end
      local n = 0
      for k, v in pairs(t) do if k ~= "__version" and type(v) == "table" then n = n + 1 end end
      return n
    end

    local function safe_loadfile(path)
      if not path or type(path) ~= "string" then return nil end
      local f = io.open(path, "rb")
      if not f then return nil end
      local content = f:read("*a")
      f:close()
      if not content or content == "" then return nil end
      local chunk, err = load(content, "@" .. path, "t")
      return chunk, err
    end

    -- REPAIR A FILE THE OLD SERIALIZER ALREADY DAMAGED (2026-07-28). Before the serializer was
    -- made total, a NaN was written as the bare word `nan` and an infinity as `inf`. Neither is
    -- valid Lua, so the whole file failed to load and read as "no data" -- total loss of every
    -- weapon in every world, not one lost field. Those files are already on players' disks and
    -- no future fix reaches them, so try a textual repair before giving up on the primary:
    -- swap the bare tokens for nil and re-parse. Purely additive -- if it does not parse after
    -- repair we fall through to the same .recovery/.bak chain as before.
    local function loadMaybeRepairing(p)
      local chunk = safe(function() return safe_loadfile(p) end)
      if chunk then
        local ok, t = pcall(chunk)
        if ok and type(t) == "table" then return t, false end
      end
      local f = io.open(p, "rb"); if not f then return nil end
      local body = nil
      pcall(function() body = f:read("*a") end); pcall(function() f:close() end)
      if type(body) ~= "string" or body == "" then return nil end
      -- %f[%w] is a frontier pattern: match `nan` only as a whole word, never inside a string
      -- like ["Banana"]. Signs are handled by matching an optional leading -.
      local repaired, n = body:gsub("%-?%f[%w]inf%f[%W]", "nil")
      local r2, n2 = repaired:gsub("%-?%f[%w]nan%f[%W]", "nil")
      repaired, n = r2, n + n2
      if n == 0 then return nil end
      local c = load(repaired, "@" .. p, "t")
      if not c then return nil end
      local ok, t = pcall(c)
      if ok and type(t) == "table" then return t, true, n end
      return nil
    end

    local loaded = false
    local t, wasRepaired, repairedCount = loadMaybeRepairing(self.path)
    if type(t) == "table" then
      self.data = t; loaded = true
      if wasRepaired then
        print(string.format("[Arsenal] REPAIRED a damaged store: %d unreadable value(s) in %s "
          .. "were written by an older version and could not be parsed. Your weapons are intact; "
          .. "only those values were dropped.\n", repairedCount or 0, tostring(self.path)))
      end
    end
    -- RECOVERY (1.4.4): fall back to the .bak that save() always leaves behind.
    -- Taken when the main file is missing/corrupt, AND when it loaded but is
    -- EMPTY while the .bak still holds worlds -- that is precisely a store that
    -- was just wiped, and reading it as "no data" is what made the loss permanent.
    -- RECOVERY FILE FIRST (2026-07-28). save() writes one when the atomic rename dance cannot
    -- complete, so it is by definition NEWER than the primary -- it exists precisely because the
    -- primary could not be replaced. Prefer it whenever it holds more than what loaded, then
    -- fold it in so the next successful save consolidates and it stops being consulted.
    do
      local c = safe(function() return safe_loadfile(self.path .. ".recovery") end)
      if c then
        local ok, t = pcall(c)
        if ok and type(t) == "table" and entries(t) >= entries(self.data) then
          self.data = t; loaded = true
          print("[Arsenal] recovered progress from " .. self.path .. ".recovery"
            .. " (a previous save could not replace the main file)\n")
        end
      end
    end
    if (not loaded) or entries(self.data) == 0 then
      local c = safe(function() return safe_loadfile(self.path .. ".bak") end)
      if c then
        local ok, t = pcall(c)
        if ok and type(t) == "table" and entries(t) > entries(self.data) then
          self.data = t; loaded = true
        end
      end
    end
    -- ========================================================================
    --  MIGRATION: LOOK EVERYWHERE, THEN ADOPT THE BEST -- NEVER THE FIRST
    -- ========================================================================
    -- THE RULE THIS REPLACES was "walk the legacy dirs, take the first file that loads". That is
    -- the exact rule that shadowed Atsuraelu's store (header): with two shared/ folders on one
    -- machine, first-found means first-in-a-list-of-guesses, and the guess that wins has nothing
    -- to do with which file holds the player's weapons. His level-68 weapon was in the file the
    -- loop never reached.
    --
    -- So every known location is now read -- all of them, every boot -- and the BEST is adopted.
    --
    -- HOW "BEST" IS DECIDED, and why it is not modification time. Lua 5.1 under UE4SS has no way
    -- to stat a file: no lfs, and shelling out is not acceptable in a game process. So there is
    -- no mtime to sort by, and inventing one from the OS is off the table. Instead:
    --
    --   1. A store that holds NOTHING never wins over one that holds something. First, and
    --      absolutely -- otherwise the empty file resolveDir() can create by probing writability
    --      would beat the real data, which is a new way to lose everything, in the fix for a
    --      data-loss bug.
    --   2. __savedAt (written by save() from this version on) is a real recency signal, so a
    --      STAMPED store beats an unstamped one, and a newer stamp beats an older one. This is
    --      also what makes the migration settle: after the first boot the canonical file carries a
    --      stamp and the abandoned copies never will, so it wins from then on without needing a
    --      "migration done" flag that could itself be lost.
    --   3. Failing that, MOST RECORDS -- total weapon entries across all worlds. Not world
    --      buckets: a shadow store gets a bucket the moment it is created, so counting buckets
    --      would have called Atsuraelu's two files a tie. Counting weapons calls it 14 to 1.
    --   4. Ties keep the earlier scan position, and the canonical path is first.
    --
    -- THE ONE CASE RULE 2 GETS WRONG, known and accepted (review, 2026-08-03): a player who runs
    -- this fixed version (store gets stamped), then REVERTS to an old release -- which real users
    -- do; Atsuraelu is running old versions by choice right now -- and plays on. The old code
    -- writes unstamped, possibly at a different cwd-guessed path on a two-layout machine. Come
    -- back to the fixed version and the stale STAMPED file outranks the newer UNSTAMPED one that
    -- holds the revert-era progress. Why rule 2 keeps its place anyway: among files this version
    -- has touched, the stamp is the only true recency signal, records-first has its own inverse
    -- failure (a fat pre-worldKey relic outranking a lean real store), and this store only ever
    -- ADDS records -- so the loud log below, which names every candidate with its counts, is the
    -- backstop either way. If this case is ever reported, the answer is the log, not a new rule.
    --
    -- NOTHING IS EVER DELETED. The losers stay exactly where they are -- if this picks wrong, the
    -- player's data is still on disk and the log below names the file it is in. That log is the
    -- deliverable as much as the rule is: Atsuraelu found his own duplicate by looking, and he
    -- should not have had to.
    local function records(t)
      if type(t) ~= "table" then return -1 end
      local n = 0
      for k, w in pairs(t) do
        if k ~= "__version" and type(w) == "table" then
          for _, st in pairs(w) do if type(st) == "table" then n = n + 1 end end
        end
      end
      return n
    end
    local function stampOf(t)
      local v = type(t) == "table" and t.__savedAt or nil
      if type(v) == "number" and v == v and v > 0 and v ~= math.huge then return v end
      return nil
    end
    local function betterThan(a, b)                    -- strictly better; ties keep b
      if (a.recs > 0) ~= (b.recs > 0) then return a.recs > 0 end          -- rule 1
      if (a.stamp ~= nil) ~= (b.stamp ~= nil) then return a.stamp ~= nil end -- rule 2
      if a.stamp and b.stamp and a.stamp ~= b.stamp then return a.stamp > b.stamp end
      if a.recs ~= b.recs then return a.recs > b.recs end                 -- rule 3
      if a.worlds ~= b.worlds then return a.worlds > b.worlds end
      return false                                                        -- rule 4
    end

    -- THE SAME FILE UNDER TWO SPELLINGS IS NOT TWO FILES. On an ordinary single-install machine
    -- most of the list above resolves to the identical file -- that is the whole reason the old
    -- guesswork survived so long -- so without this every boot would report a pile of "duplicate
    -- stores" and teach the player to ignore the one warning that matters. There is no way to ask
    -- this Lua whether two paths are the same inode, so identity is decided on CONTENT: byte-equal
    -- files are treated as one. Two genuinely distinct files with identical bytes carry identical
    -- data, so collapsing them cannot change what gets adopted either.
    local found, seen, bySeenBody = {}, {}, {}
    local function rawBody(p)
      local f = io.open(p, "rb"); if not f then return nil end
      local b = nil
      pcall(function() b = f:read("*a") end); pcall(function() f:close() end)
      if type(b) ~= "string" or b == "" then return nil end
      return b
    end
    local function consider(p, data)
      if seen[p] then return end
      seen[p] = true
      local body = rawBody(p)
      if body and bySeenBody[body] then return end
      if data == nil then
        local t2 = loadMaybeRepairing(p)               -- repairs an inf/nan file on the way past
        if type(t2) ~= "table" then return end
        data = t2
      end
      if body then bySeenBody[body] = true end
      found[#found + 1] = { path = p, data = data, recs = records(data),
                            worlds = entries(data), stamp = stampOf(data) }
    end
    -- the file we already accepted (primary, or whatever .recovery/.bak upgraded it to) goes in
    -- FIRST, so a tie leaves it in place and this whole block is a no-op on a healthy install
    consider(self.path, type(self.data) == "table" and self.data or nil)
    for _, d in ipairs(MIGRATION_DIRS) do consider(d .. self.fileName) end
    for _, d in ipairs(LEGACY_DIRS) do
      consider(d .. self.fileName)
      consider(d .. "prof-store.lua")                  -- its name before 2026-07-22
    end

    if #found > 0 then
      local best = found[1]
      for i = 2, #found do if betterThan(found[i], best) then best = found[i] end end
      if best.data ~= self.data and best.recs > 0 then
        self.data = best.data
        loaded = true
      end
      -- Speak up only when there is genuinely more than one store on disk. On a healthy install
      -- this is one line's worth of nothing, every boot, forever -- but the day it matters it is
      -- the difference between a player finding his weapons and being told they are gone.
      if #found > 1 then
        print(string.format("[Arsenal] %d store files found on disk. Adopting the fullest/newest; "
          .. "the others are LEFT IN PLACE, untouched:\n", #found))
        for _, c in ipairs(found) do
          print(string.format("[Arsenal]   %s  %s  worlds=%d weapons=%d saved=%s\n",
            (c == best) and "ADOPTED " or "left    ", tostring(c.path), c.worlds, c.recs,
            c.stamp and tostring(c.stamp) or "unknown (written before save stamps)"))
        end
        print(string.format("[Arsenal]   reason: %s. Future saves go to %s only.\n",
          best.stamp and "it carries the newest save stamp" or "it holds the most weapons",
          tostring(self.path)))
      end
    end
    if type(self.data) ~= "table" then self.data = { __version = self.version } end
    if self.data.__version == nil then self.data.__version = self.version end

    -- KEEP A GENERATION of the store we just accepted, before anything writes over it.
    if entries(self.data) > 0 then
      local body = safe(function() return (serialize(self.data)) end)
      rotateBackups(body)
    end

    -- SELF-HEAL. Anything still in the journal is by the invariant unpersisted, so replay it.
    -- ONLY EVER RAISES A LEVEL. A heal that could lower one would turn a stale journal into a
    -- second way to lose progress, and the whole point here is to have no such way.
    local recs = journalRead()
    if #recs > 0 then
      local applied, byWorld = 0, {}
      for _, r in ipairs(recs) do
        local wk = r.w or "?"
        local bucket = self.data[wk]
        if type(bucket) ~= "table" then bucket = {}; self.data[wk] = bucket end
        local st = bucket[r.k]
        if type(st) ~= "table" then
          bucket[r.k] = { level = r.lv, xp = r.xp or 0, hits = r.hits or 0 }
          applied = applied + 1; byWorld[#byWorld+1] = r.k .. " -> Lv" .. r.lv .. " (restored)"
        elseif type(st.level) ~= "number" or r.lv > st.level then
          st.level = r.lv
          st.xp = r.xp or st.xp or 0
          if type(r.hits) == "number" and r.hits > (st.hits or 0) then st.hits = r.hits end
          applied = applied + 1; byWorld[#byWorld+1] = r.k .. " -> Lv" .. r.lv
        end
      end
      if applied > 0 then
        self.healed = byWorld
        print(string.format("[Arsenal] RECOVERED %d weapon level(s) that had not reached disk. "
          .. "A previous session could not save; the write-ahead journal had them. Restored: %s\n",
          applied, table.concat(byWorld, ", ")))
      end
      -- Consumed either way: applied records are now in self.data, and unapplied ones were
      -- already there. The next successful save consolidates and clears it.
    end
    return self.data
  end

  -- SWAP SAFELY (1.4.4). The old path was:
  --     os.remove(self.path); os.rename(tmp, self.path)
  -- which DELETED the only good copy first. Anything failing in that window --
  -- process kill, alt-F4, crash on exit, an AV or game handle making the rename
  -- fail -- left NO store file at all. load() reads a missing file as "no data",
  -- and the next save (1s later) wrote that empty table back: permanent, total
  -- loss of every weapon in every world. Reported on Steam 2026-07-23
  -- ("logged out and logged back in, everything reset"). The .tmp dance only
  -- ever protected against a TORN WRITE -- never against that gap.
  --
  -- Now the previous good file is moved ASIDE to .bak (never deleted) and kept
  -- as a one-generation recovery point, so a readable store ALWAYS exists on
  -- disk. Every failure path restores it and reports false.
  -- EVERY FAILURE IS NOW LOUD, AND THE LAST RESORT NEVER LOSES DATA (2026-07-28).
  --
  -- This function had FIVE silent `return false` paths. On 2026-07-27 it started failing and
  -- nobody knew for over a day: weapons levelled all session and reset to their start level on
  -- every reload, because the store on disk was frozen at 11:53 while the flush loop cheerfully
  -- "saved" every second. The mod was writing its OTHER files to the same directory the whole
  -- time, so nothing looked wrong. A silent failure in a save path is the worst kind of bug this
  -- project produces, and it has now produced it twice (see the 1.4.4 note above).
  --
  -- Two changes:
  --   1. Every exit reports WHICH step failed and the OS error, once per distinct reason (a
  --      per-second flush loop must not spam). `saveFailures` is readable for a HUD/boot report.
  --   2. If the atomic rename dance cannot complete, fall back to writing the body straight to
  --      a RECOVERY file. That gives up atomicity for that one write -- but the alternative,
  --      demonstrated, is losing a day of progress silently. The recovery file is picked up by
  --      load() on the next boot.
  self.saveFailures = self.saveFailures or {}
  local reported = {}
  local function fail(step, detail)
    self.saveFailures[step] = (self.saveFailures[step] or 0) + 1
    if not reported[step] then
      reported[step] = true
      print(string.format("[Arsenal] STORE SAVE FAILED at '%s': %s | path=%s\n",
        step, tostring(detail), tostring(self.path)))
    end
    return false
  end

  function self:save()
    if type(self.data) ~= "table" then return fail("no-data", type(self.data)) end
    if not self.path then self.path = resolveDir() .. self.fileName end
    -- STAMP EVERY SAVE (2026-08-03). There is no way to stat a file from here, so a store that
    -- does not carry its own save time cannot be compared with another one on recency -- and
    -- "which of these two files is the current one" is precisely the question that went wrong for
    -- Atsuraelu. load()'s migration reads this. It is deliberately a top-level scalar: every
    -- consumer of self.data indexes it by world key, and entries()/records() only count tables,
    -- so a number here is invisible to all of them.
    self.data.__savedAt = nowSec()
    -- pcall, NOT safe(): safe() swallows the message, and "serializer returned nil" is exactly
    -- what this failure reported for a day and a half while telling us nothing about the cause.
    local okS, body, dropped = pcall(serialize, self.data)
    if not okS or type(body) ~= "string" then
      return fail("serialize", okS and "serializer returned a " .. type(body) or tostring(body))
    end
    -- Report anything the serializer had to drop ONCE per distinct path. A dropped value is a
    -- bug upstream -- non-finite numbers should never reach the store -- and naming the key is
    -- the difference between finding it in minutes and losing days to it.
    if dropped and #dropped > 0 then
      self.droppedKeys = self.droppedKeys or {}
      for _, d in ipairs(dropped) do
        if not self.droppedKeys[d] then
          self.droppedKeys[d] = true
          print("[Arsenal] STORE dropped an unserialisable value: " .. d
            .. " (saved as nil; the rest of the store is intact)\n")
        end
      end
    end
    local tmp, bak = self.path .. ".tmp", self.path .. ".bak"
    local f, openErr = io.open(tmp, "w")
    if not f then return fail("open-tmp", openErr) end
    local okW, wErr = pcall(function() f:write(body .. "\n") end)
    pcall(function() f:close() end)
    if not okW then pcall(function() os.remove(tmp) end); return fail("write-tmp", wErr) end

    local hadOld = false
    do local h = io.open(self.path, "r"); if h then h:close(); hadOld = true end end
    if hadOld then
      pcall(function() os.remove(bak) end)              -- drop the older generation
      local okR, rErr = os.rename(self.path, bak)
      if not okR then
        -- Could not park the live file. Do NOT abandon the write: the whole point of the
        -- 1.4.4 rewrite is that a readable store always exists, and silently dropping the
        -- save is how a day of progress disappeared.
        pcall(function() os.remove(tmp) end)
        return self:_recover(body, "park-live", rErr)
      end
    end
    local okI, iErr = os.rename(tmp, self.path)
    if not okI then
      if hadOld then pcall(function() os.rename(bak, self.path) end) end   -- put it back
      pcall(function() os.remove(tmp) end)
      return self:_recover(body, "install-tmp", iErr)
    end
    -- THE STORE NOW HOLDS EVERYTHING THE JOURNAL DID, so the journal's invariant ("only records
    -- not yet known to be in the store") is restored by emptying it. Only ever after a fully
    -- successful install -- clearing it on any earlier path would throw away the one record of
    -- work that did not make it to disk, which is precisely the accident this exists to prevent.
    self.lastSaveOk = nowSec()
    self:journalClear()
    return true
  end

  -- WATCHDOG SUPPORT. 36 hours passed before anyone noticed the store had stopped saving, and
  -- the reason is that nothing was watching: the flush loop discarded save()'s return value.
  -- The caller polls this and complains when it grows while there are unsaved changes.
  function self:secondsSinceSave() return nowSec() - (self.lastSaveOk or 0) end

  -- Last resort: write the serialized body somewhere it cannot be lost, and say so loudly.
  -- load() reads this back on the next boot if it is newer/larger than the primary.
  function self:_recover(body, step, detail)
    fail(step, detail)
    local rec = self.path .. ".recovery"
    local f = io.open(rec, "w")
    if not f then return fail("recovery-open", "cannot write " .. rec) end
    local ok = pcall(function() f:write(body .. "\n") end)
    pcall(function() f:close() end)
    if ok then
      print(string.format("[Arsenal] progress written to %s instead -- it will be picked up "
        .. "on the next launch. Your levels are NOT lost.\n", rec))
    end
    return false
  end

  return self
end

return S
