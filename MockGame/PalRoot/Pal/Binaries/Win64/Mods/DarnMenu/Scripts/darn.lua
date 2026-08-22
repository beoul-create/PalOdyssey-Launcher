-- ============================================================================
--  darn.lua -- Darn-family boot utilities, VENDORED into every mod.
--
--  SINGLE SOURCE: workshop-publish/shared-src/darn.lua
--  Copies in each mod's Scripts/ are written by tools/sync-shared.js -- edit the
--  source and re-run the sync; never edit a mod's copy directly.
--
--  Why vendored instead of living in DarnToasts: this file holds BOOT logic
--  (user-config overlay, version report). A missing library may only ever cost
--  its FEATURE (toasts), never change behavior -- so boot logic must ship inside
--  every mod, from one maintained source.
-- ============================================================================
local M = {}

-- This mod's Scripts/ dir (darn.lua always sits next to the mod's own modules).
local DIR = (debug.getinfo(1, "S").source:gsub("^@", ""):gsub("[^/\\]+$", ""))
M.dir = DIR

-- True RUNNING version. Reads the Info.json sitting beside the code that is actually
-- loaded, then falls back to the Workshop loader's ManagedMods record. "dev" = neither.
--
-- The order matters and used to be the other way round. ManagedMods is what Steam served,
-- which is NOT what is executing whenever a build has been pushed straight into
-- NativeMods -- i.e. during every dogfood test. Measured 2026-07-26: the boot line read
-- "DarnMenu v1.6.0 loaded" while 1.6.2 code ran, because ManagedMods still held 1.6.0.
-- A version string that describes a build other than the running one is worse than none:
-- it makes a crash log confidently wrong about which code produced it.
function M.version()
  local function read(path)
    local f = io.open(path, "r")
    if not f then return nil end
    local s = f:read("*a") or ""
    f:close()
    return s:match('"Version"%s*:%s*"([^"]*)"')
  end
  local name = DIR:match("[/\\]([^/\\]+)[/\\]Scripts[/\\]$")
  return read(DIR .. "../Info.json")
    or (name and read(DIR .. "../../../../../ManagedMods/" .. name .. "/Info.json"))
    or "dev"
end

function M.safe(f)
  -- RETURNS AN EXPLICIT nil ON FAILURE. Falling off the end returns ZERO VALUES, not nil,
  -- so `tonumber(safe(...))` / `tostring(safe(...))` raise "value expected" the moment the
  -- pcall fails -- i.e. exactly when an object has died, which is when these are load-bearing.
  -- Caught 2026-07-29 by a test, in a helper this codebase had copied four times.
  local ok, v = pcall(f)
  if ok then return v end
  return nil
end

-- The ONLY trustworthy stale-UObject gate: pcall does NOT catch native access
-- violations on freed pointers; check IsValid() before ANY member read.
function M.alive(o)
  if o == nil then return false end
  local ok, v = pcall(function() return o:IsValid() end)
  return ok and v == true
end

-- FGuid -> 32-hex string (UE canonical, no dashes), the key format the game and
-- our mods use for a per-instance item id. nil on a zero/unreadable guid.
-- (Shared, vendored: was duplicated in WeaponProficiency + DarnMenu.)
function M.guidStr(g)
  if not g then return nil end
  local a = M.safe(function() return g.A end); local b = M.safe(function() return g.B end)
  local c = M.safe(function() return g.C end); local d = M.safe(function() return g.D end)
  if not (a and b and c and d) then return nil end
  local ok, s = pcall(function()
    return string.format("%08X%08X%08X%08X", a & 0xFFFFFFFF, b & 0xFFFFFFFF, c & 0xFFFFFFFF, d & 0xFFFFFFFF)
  end)
  if not ok or s == "00000000000000000000000000000000" then return nil end
  return s
end

-- Load DarnUI's shared widget kit (ui.lua). Each UE4SS mod has its OWN
-- package.path, so DarnUI merely being loaded does NOT put "ui" on yours -- you
-- must add its sibling Scripts dir first. darn.lua is vendored into every mod's
-- Scripts, so debug.getinfo(1) resolves THIS mod's dir and ../../DarnUI/Scripts is
-- always the sibling. Consumers: `local UI = require("darn").requireUI()` -- never
-- hand-roll the path dance (forgetting it = "DarnUI not available"; a hard lesson).
-- Errors if DarnUI isn't installed, so pcall it when the dep is optional.
--
-- LOAD BY PATH, NOT BY SHORT NAME (VirtualBjorn, 2026-07-27 -- his mod would not load
-- at all). `require("ui")` resolves a NAME, and a mod that shipped its own ui.lua
-- before the DarnUI split can still have that obsolete file sitting in its own Scripts
-- dir: a mod update does not necessarily delete files the new version dropped. Then
-- either package.path order or an already-populated package.loaded["ui"] (UE4SS
-- hot-reload preserves it across a reinstall) binds "ui" to the stale kit, the modern
-- API is missing, and the mod dies with nothing in the log naming the cause. Loading
-- the sibling FILE makes the source and the load order explicit, and the API assertion
-- turns "mysteriously broken" into one sentence.
--
-- VENDORED FIRST (2026-07-27). The kit now ships INSIDE each mod that draws with it, exactly
-- as this file does, so the SIBLING copy is preferred: it is the one that matches this mod's
-- code. That is what retires the mismatch class entirely -- a mod can no longer meet a kit
-- from a different release, because it loads the file it shipped with. The cross-mod path
-- remains as a fallback for anyone still running a build that expects the separate DarnUI
-- item, and (usefully) it is also what makes the leftover pre-1.6.0 ui.lua a non-event: that
-- file is now simply where the kit is meant to live.
function M.requireUI()
  local dir = (debug.getinfo(1, "S").source:gsub("^@", ""):gsub("[^/\\]+$", ""))
  -- `package.loaded` is guarded rather than assumed: this function is the FIRST thing
  -- a consumer calls, so an indexing error here reads to a user as "the mod is broken"
  -- with no further output. Caught by lint.js's stubbed-environment load.
  local loaded = package and package.loaded
  local cached = loaded and loaded["ui"]
  if type(cached) == "table" and type(cached.insertChildAt) == "function" then
    return cached
  end
  local from = "vendored"
  local chunk, loadErr = loadfile(dir .. "ui.lua")
  if not chunk then
    from = "DarnUI mod"
    chunk, loadErr = loadfile(dir .. "../../DarnUI/Scripts/ui.lua")
  end
  if not chunk then
    error("could not load the DarnUI kit (no vendored copy, no DarnUI mod): " .. tostring(loadErr))
  end
  local ok, ui = pcall(chunk)
  if not ok then error("could not initialize the DarnUI kit: " .. tostring(ui)) end
  if type(ui) ~= "table" or type(ui.insertChildAt) ~= "function" then
    error("the DarnUI kit loaded from the " .. from .. " copy is missing UI.insertChildAt")
  end
  -- Name the version AND where it came from. Two vendored copies at different versions
  -- cannot corrupt each other -- separate Lua states, and each mod only ever touches widgets
  -- it created (UI.isOurs) -- but they can hold different opinions about genuinely shared
  -- state: the shared/ config files and the game's own UI. This makes that a glance at the
  -- log rather than an inference. "dev" = an unsynced working copy.
  M.uiKit = { version = tostring(ui.KIT_VERSION or "dev"), from = from }
  -- SAY WHETHER THE JOB DRIVER ARMED. This is how the next launch tells us, without another
  -- forensics pass, whether the per-frame scheduler is live or whether the kit fell back to the
  -- legacy timers. A component that fails closed and says nothing is the same class of problem
  -- as a flag-gated log: silent in exactly the case that needs the evidence.
  print(string.format("[Darn] ui kit %s (%s)  jobs=%s driver=%s\n", M.uiKit.version, from,
    tostring(ui._jobsEnabled == true), tostring(ui._jobDriver or "none")))
  if loaded then loaded["ui"] = ui end
  return ui
end

-- tag prints verbatim: M.logger("[Arsenal][DMG]") -> "[Arsenal][DMG] <msg>"
-- Write a file so a crash mid-write cannot destroy what was already there.
-- `io.open(path, "w")` TRUNCATES immediately: if the process dies between that and
-- the last write, the file is gone or half-written. Living Arsenal shipped exactly
-- that bug and wiped every player's weapon progress ("logged back in, everything
-- reset"), so: write a .tmp, move the current file aside to .bak, then rename the
-- .tmp into place. A crash at any point leaves either the old file or the .bak.
-- Use this for anything the PLAYER would be upset to lose (blacklists, progress,
-- ledgers). Derived files that regenerate themselves do not need it.
-- Returns true on success; false (and leaves the existing file alone) on any failure.
function M.writeAtomic(path, text)
  if type(path) ~= "string" or type(text) ~= "string" then return false end
  local tmp, bak = path .. ".tmp", path .. ".bak"
  local f = M.safe(function() return io.open(tmp, "w") end)
  if not f then return false end
  local okW = pcall(function() f:write(text) end)
  pcall(function() f:close() end)
  if not okW then pcall(function() os.remove(tmp) end); return false end
  -- keep ONE previous generation: os.rename cannot overwrite on Windows, so the
  -- current file has to move out of the way first -- but it is moved, never deleted.
  local exists = M.safe(function() local h = io.open(path, "r"); if h then h:close(); return true end end)
  if exists then
    pcall(function() os.remove(bak) end)
    if not pcall(function() assert(os.rename(path, bak)) end) then
      pcall(function() os.remove(tmp) end)          -- could not park it: leave reality alone
      return false
    end
  end
  if not pcall(function() assert(os.rename(tmp, path)) end) then
    if exists then pcall(function() os.rename(bak, path) end) end   -- put it back
    pcall(function() os.remove(tmp) end)
    return false
  end
  return true
end

-- Read a file that M.writeAtomic wrote, falling back to the .bak if the main file is
-- missing or empty -- which is what a crash during an OLD-STYLE truncating write left.
function M.readWithBackup(path)
  local function slurp(p)
    local h = M.safe(function() return io.open(p, "r") end)
    if not h then return nil end
    local t = M.safe(function() return h:read("*a") end)
    pcall(function() h:close() end)
    if t and t ~= "" then return t end
    return nil
  end
  return slurp(path) or slurp(path .. ".bak")
end

function M.logger(tag)
  return function(m) print(tag .. " " .. tostring(m) .. "\n") end
end

-- Type-guarded user overlay: merge Mods/shared/<name>.lua (a table of overrides)
-- onto cfg. A key that exists in cfg must keep its type, so a corrupted or
-- hand-mangled user file can never break boot; unknown keys pass through
-- (DarnMenu's flat keys like bind1Key rely on that).
function M.overlay(cfg, name, logf)
  local ok, u = pcall(require, name)
  if not ok or type(u) ~= "table" then return cfg end
  for k, v in pairs(u) do
    if cfg[k] ~= nil and type(cfg[k]) ~= type(v) then
      if logf then
        logf("user config ignored: '" .. tostring(k) .. "' should be "
          .. type(cfg[k]) .. ", got " .. type(v) .. " -- fix Mods/shared/" .. name .. ".lua")
      end
    else
      cfg[k] = v
    end
  end
  return cfg
end

-- ToastLib with graceful degradation: missing DarnToasts costs the user TOASTS
-- (and the menu page), never the mod. The stub covers the full consumer API.
-- Returns (lib, real): real=false means the no-op stub is in play.
-- LIVE SETTINGS: poll a Mods/shared config file (e.g. "MyMod_user") and call
-- fn(newTable) when its content changes -- the consumer half of "DarnMenu Apply
-- without relaunch". Text-compare against a startup baseline, so it works with
-- ANY DarnMenu version (or hand edits) and costs one small file read per tick.
-- fn runs inside pcall; interval defaults to 2000ms. The state at startup does
-- NOT fire (your mod already loaded it at boot).
function M.watchConfig(name, fn, intervalMs)
  local path = DIR .. "../../shared/" .. name .. ".lua"
  local function readAll()
    local f = io.open(path, "r")
    if not f then return "" end
    local s = f:read("*a") or ""
    f:close()
    return s
  end
  local last = readAll()
  local ms = tonumber(intervalMs) or 2000
  local function tick()
    local txt = readAll()
    if txt ~= last then
      last = txt
      if txt ~= "" then
        local chunk = load(txt, "@" .. name)
        if chunk then
          local ok, t = pcall(chunk)
          if ok and type(t) == "table" then pcall(fn, t) end
        end
      end
    end
    ExecuteWithDelay(ms, tick)
  end
  ExecuteWithDelay(ms, tick)
end

-- WATCH A PLAIN FILE IN shared/ AND REACT WHEN SOMEONE ELSE CHANGES IT.
--
-- watchConfig above does this for a mod's own <name>.lua settings file. This is the same poll for
-- an arbitrary file, because settings are not the only thing two processes both hold: DarnMenu
-- edits a mod's managed LIST on disk while the mod itself is holding that list in memory, and
-- whichever writes last wins. Reported by a player (Jarol, Steam 2026-07-29): removing an item in
-- the options menu appeared to do nothing, because the owning mod never re-read the file and its
-- next save put the item straight back.
--
-- `fn` receives the raw TEXT. Called only when the content actually changes, never on the first
-- read, so a mod does not get a spurious reload at boot for a file it just loaded itself.
function M.watchFile(relPath, fn, intervalMs)
  local path = DIR .. "../../shared/" .. relPath
  local function readAll()
    local f = io.open(path, "r")
    if not f then return "" end
    local s = f:read("*a") or ""
    f:close()
    return s
  end
  local last = readAll()
  local ms = tonumber(intervalMs) or 2000
  local function tick()
    local txt = readAll()
    if txt ~= last then
      last = txt
      pcall(fn, txt)
    end
    ExecuteWithDelay(ms, tick)
  end
  ExecuteWithDelay(ms, tick)
  -- so the owner can tell the watcher "this change was mine" and not bounce it back
  return { seen = function(txt) last = txt end }
end

function M.toastlib(logf, msg)
  package.path = DIR .. "../../DarnToasts/Scripts/?.lua;" .. package.path
  local ok, tl = pcall(require, "ToastLib")
  if ok and type(tl) == "table" and tl.new then return tl, true end
  if logf then logf(msg or "DarnToasts not found -- toasts disabled (subscribe to DarnToasts to restore them)") end
  local function stubInstance()
    return { notify = function() end, muted = function() return true end,
             progress = function() end, dismiss = function() end,
             configure = function() return false end }
  end
  return {
    new = stubInstance,
    custom = stubInstance,     -- 2.0 custom surfaces degrade the same way
    registerMenuSchema = function() return false end,
  }, false
end

return M
