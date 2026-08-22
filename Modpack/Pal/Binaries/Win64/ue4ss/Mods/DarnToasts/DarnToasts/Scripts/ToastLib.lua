-- ============================================================================
--  ToastLib -- the DarnToasts toast library (Steam Workshop package "DarnToasts").
--
--  Extracted 2026-07-21 from the proven MedicineHotkeys machinery; prettified
--  same day: per-frame animation via os.clock (500ms tick clock kept for hook
--  health only), soft drop shadow, rounded pill body, accent stripe with glow,
--  text shadow, draining life bar. Entry = UNRAVEL: the panel wipes open from
--  its accent edge with the text substring-typed behind the reveal ("left"
--  default, "right" mirrored, false = classic slide+fade).
--
--  STACKING: each notify() gets its OWN toast. New toasts unravel BELOW the
--  existing pile (up to 4; oldest dropped beyond that), and when one expires
--  the rest slide up into the gap (frame-smooth exponential ease).
--
--  USER CONFIG: Mods/shared/ToastLib_config.lua -- position, size, duration,
--  colors, unravel/animation/shadow/lifebar switches, and off switches
--  (global or per-mod). Missing/broken config = the defaults below.
--
--  THE CHANNEL MODEL (2.0): a hard authority boundary.
--    * DEFAULT CHANNEL -- `ToastLib.new("MyMod")`, NO opts. DarnToasts manages
--      everything: style, position, stacking, auto-lanes, and the per-mod mute
--      list -- all on the Toasts options page. Channel mods ship ZERO toast
--      config of their own.
--    * CUSTOM SURFACE -- `ToastLib.custom("MyMod", { anchor=..., ... })`.
--      Drawing machinery only: DarnToasts touches NOTHING (no global style, no
--      config, not even the mute list). The owning mod manages it all on its
--      own options page and pushes changes with `T.configure{ ... }`.
--    A write is either in the channel (fully DarnToasts') or out of it (fully
--    the mod's). No precedence chain, no half-managed anything.
--
--  USAGE:
--      local Toast = require("ToastLib").new("MyModName")   -- default channel
--      Toast.notify("hello")                      -- default color
--      Toast.notify("saved!", 0.45, 1.0, 0.55)    -- custom accent color
--      if Toast.muted() then ... end              -- Toasts page muted this mod
--
--      local Panel = require("ToastLib").custom("MyModName",  -- custom surface
--                      { anchor = "right", xOffset = 16, yFrac = 0.5 })
--      Panel.progress("bow", { text = "Old Bow  Lv 41",   -- persistent panel;
--                              sub = "Dmg 1047 (+1510%)", frac = 0.62 })
--      Panel.progress("board", { text = "Standing Orders: 31, 8 low",   -- ROW LIST (2.3):
--                     sub = "top up from the board",
--                     lines = { { text = "Polymer 29/50", frac = 0.58 },
--                               { text = "Charcoal 3/200", frac = 0.015, r=1,g=.4,b=.3 } },
--                     maxLines = 6 })         -- default 6; extra rows are dropped, so the
--                                             -- CALLER decides what "+N more" should say
--      Panel.dismiss("bow")                       -- ravel it shut
--      Panel.configure({ opacity = 60, scale = 1.5 })  -- YOUR config, applied
--                                                 -- live whenever you call it
--
--  NOTE: UE4SS gives every mod its own Lua state, so each consumer runs its own
--  ToastLib instance and draw hook. They all hook the same ReceiveDrawHUD and so
--  draw back-to-back within a frame, which is what lets a SHARED ROW CURSOR give
--  the default channel ONE stack in registration order (2.2.0). Before that each
--  consumer owned a fixed 110px lane, so the fourth mod to register drew 330px
--  below the configured spot -- halfway down a 1080p screen. mods.<Name>.yOffset
--  still nudges an individual mod from the Toasts side.
--  LEGACY: `new(name, {opts})` (1.x author positioning) is auto-promoted to a
--  CUSTOM surface with a deprecation log -- update callers to .custom().
-- ============================================================================

local M = {}

-- provenance breadcrumb: which copy of the library actually served (shared/ vs DarnToasts)
print("[ToastLib] serving from " .. tostring(debug.getinfo(1, "S").source) .. "\n")

-- ============================================================================
-- DarnMenu registration (optional platform glue). UE4SS mods live in separate
-- Lua states, so registration is FILE-BASED: write the schema to
--   Mods/shared/DarnMenu_schema_<Name>.lua
-- and merge <Name> into
--   Mods/shared/DarnMenu_schema_index.lua
-- DarnMenu reads the index with loadfile -- no shell, no console flash, and a
-- freshly registered mod's page appears at the next menu open. Sequential mod
-- loading makes the index merge safe. Idempotent: skipped when the existing
-- schema file already carries schemaVersion >= version.
-- ============================================================================
local SRC_DIR = (debug.getinfo(1, "S").source:gsub("^@", ""):gsub("[^/\\]+$", ""))
local SHARED_DIR = SRC_DIR:match("[/\\]shared[/\\]$") and SRC_DIR or (SRC_DIR .. "../../shared/")

function M.registerMenuSchema(name, version, sourceText)
  if type(name) ~= "string" or not name:match("^[%w_%-]+$") then return false end
  local ok, err = pcall(function()
    local path = SHARED_DIR .. "DarnMenu_schema_" .. name .. ".lua"
    local existing = io.open(path, "r")
    if existing then
      local txt = existing:read("*a") or ""
      existing:close()
      local v = tonumber(txt:match("schemaVersion%s*=%s*(%d+)"))
      if v and v >= version then return end
    end
    local f = assert(io.open(path, "w"))
    f:write(sourceText)
    f:close()
    local ipath = SHARED_DIR .. "DarnMenu_schema_index.lua"
    local list = {}
    local chunk = loadfile(ipath)
    if chunk then
      local okc, t = pcall(chunk)
      if okc and type(t) == "table" then list = t end
    end
    local present = false
    for _, n in ipairs(list) do if n == name then present = true break end end
    if not present then list[#list + 1] = name end
    local fi = assert(io.open(ipath, "w"))
    fi:write("-- DarnMenu schema index (maintained by registering mods; safe to delete --\n")
    fi:write("-- every registered mod rebuilds its entry on the next launch)\n")
    fi:write("return {\n")
    for _, n in ipairs(list) do fi:write("  " .. string.format("%q", n) .. ",\n") end
    fi:write("}\n")
    fi:close()
  end)
  if not ok then print("[ToastLib] menu-schema registration failed for " .. name .. ": " .. tostring(err) .. "\n") end
  return ok
end

-- DarnToasts registers its OWN options page like any other mod -- DarnMenu has
-- no built-in knowledge of the family (it is a pure platform).
-- The Toasts page TEMPLATE. Mute toggles are GENERATED from the consumer
-- registry (one bool per known channel mod -- no typing names into a list);
-- registerToastsSchema() below fills %MUTE_ROWS% / %MUTE_DEFAULTS% and
-- registers with version 8000 + consumer count, so the page re-registers
-- whenever a new mod appears (visible from its next launch).
local TOASTS_SCHEMA = [==[
-- DarnToasts options page (registered by ToastLib; regenerated on version bump)
return {
  schemaVersion = 8,
  tab = "Toasts", order = 10, target = "ToastLib_config",
  live = true,
  note = "The DEFAULT toast channel: styles every mod's plain toasts. Custom panels (e.g. the Living Arsenal weapon panel) are managed on their own mod's page. Changes apply LIVE.",
  applyNote = "Saved -- applied live (give it a second or two).",
  defaults = { enabled = true, style = "panel", useGameFeed = false, anchor = "left", xOffset = 300, yFrac = 0.20, yOffset = 0,
               scale = 1.4, ttl = 10, animMs = 280, unravel = "left", exit = "wipe",
               shadow = true, lifebar = true, stack = 4, stackGap = 8, opacity = 100,%MUTE_DEFAULTS% },
  sections = {
    { title = "Master", options = {
        { path = "enabled", label = "Toasts enabled", kind = "bool",
          help = "OFF silences every mod's toasts" },
    }},
    { title = "Position", options = {
        { path = "useGameFeed", label = "Use the game's feed", kind = "bool", live = true,
          help = "ON sends toasts through the game's own notification feed -- the game decides where and how they appear, so the settings on this page stop applying. OFF (default) draws them at the position set below." },
        { path = "anchor", label = "Anchor", kind = "enum", values = {
            { value = "center", label = "Center" },
            { value = "left",   label = "Left edge" },
            { value = "right",  label = "Right edge" } } },
        { path = "xOffset", label = "X offset (px)", kind = "number",
          min = -2000, max = 2000, step = 10, integer = true },
        { path = "yFrac", label = "Vertical spot", kind = "number",
          min = 0, max = 1, step = 0.05,
          help = "0 = top of screen, 1 = bottom" },
        { path = "yOffset", label = "Y offset (px)", kind = "number",
          min = -2000, max = 2000, step = 10, integer = true },
    }},
    { title = "Style", options = {
        { path = "style", label = "Toast style", kind = "enum", live = true, values = {
            { value = "panel",  label = "Darn glass (default)" },
            { value = "pill",   label = "Classic pill" },
            { value = "native", label = "Native look (flat strip)" } },
          help = "Look only -- every style draws at YOUR position from the Position section. Darn glass is the family surface look (flat glass, hairline outline, solid edge accent); Classic pill is the pre-2.7 rounded look; Native is a flat strip like the game's feed rows: no accent, no typing animation. To use the game's actual feed, see 'Use the game's feed' under Position." },
        { path = "opacity", label = "Opacity %", kind = "number",
          min = 10, max = 100, step = 5, integer = true,
          help = "how solid every toast and panel draws. 100 = default" },
        { path = "scale", label = "Text scale", kind = "number",
          min = 0.5, max = 3, step = 0.05 },
        { path = "wrapCols", label = "Wrap text at (characters)", kind = "number", min = 40, max = 160, step = 5, live = true,
          help = "Long toasts wrap onto extra lines at this width instead of stretching across the screen." },
        { path = "ttl", label = "Lifetime (half-seconds)", kind = "number",
          min = 1, max = 120, step = 1, integer = true,
          help = "10 = ~5s on screen" },
        { path = "unravel", label = "Unravel from", kind = "enum", values = {
            { value = "left",  label = "Left edge" },
            { value = "right", label = "Right edge" } },
          help = "which edge the toast wipes open from" },
        { path = "exit", label = "Exit", kind = "enum", values = {
            { value = "wipe", label = "Wipe shut" },
            { value = "fade", label = "Fade out" } },
          help = "wipe = ravel shut; fade = classic fade-out" },
        { path = "animMs", label = "Animation (ms)", kind = "number",
          min = 0, max = 2000, step = 20, integer = true },
        { path = "shadow", label = "Drop shadow", kind = "bool" },
        { path = "lifebar", label = "Time bar", kind = "bool" },
    }},
    { title = "Stacking", options = {
        { path = "stack", label = "Max toasts per mod", kind = "number",
          min = 1, max = 10, step = 1, integer = true },
        { path = "stackGap", label = "Gap between toasts (px)", kind = "number",
          min = 0, max = 100, step = 2, integer = true },
    }},
    { title = "Muted mods", options = {
%MUTE_ROWS%
    }},
  },
}
]==]

local DEFAULTS = {
  enabled = true,          -- master switch: false = no toasts from ANY mod
  style   = "panel",       -- LOOK only: "panel" = Darn pill | "native" = flat feed-like strip.
                           -- Both draw at the user's position (style and position are
                           -- independent settings -- Maiq 2026-08-08).
  useGameFeed = false,     -- true = hand toasts to the game's own notification feed
                           -- (game position AND game look; see nativeNotify)
  anchor  = "center",      -- "center" | "left" | "right"
  xOffset = 0,             -- px: center = nudge off middle; left/right = margin from that edge
  yFrac   = 0.68,          -- vertical position, fraction of screen height (0 top .. 1 bottom)
  yOffset = 0,             -- px added after yFrac
  scale   = 1.4,           -- text scale; the panel sizes with it (raised from 1.25 -- default text read small)
  ttl     = 10,            -- lifetime in 500ms ticks (10 = ~5s; readable, not lingering)
  wrapCols = 40,           -- wrap width in characters (Maiq 2026-08-07: 80 still read as
                           -- strips; 40. Long toasts also LINGER longer -- see lingerBonusS)
  color   = { 0.55, 0.85, 1.0 },  -- default accent when the mod doesn't pass one
  animMs  = 280,           -- entry animation duration (0 = appear instantly)
  unravel = "left",        -- "left" = wipe open from the left edge (default),
                           -- "right" = mirrored (accent/spool on the right),
                           -- false = classic slide-up + fade entry
  exit    = "wipe",        -- "wipe" = ravel closed back into the accent edge (default),
                           -- "fade" = fade out + drift up
                           -- (unravel=false always exits with fade)
  shadow  = true,          -- soft drop shadow behind the panel
  lifebar = true,          -- thin accent bar that drains with remaining time
  stack   = 4,             -- max simultaneous toasts per mod (oldest dropped beyond)
  stackGap = 8,            -- px between stacked toasts
  mods    = {},            -- per-mod: false=mute, or {enabled=, yOffset=, color=, ttl=, scale=}
}

-- loadfile, NOT require: require caches, and live re-apply (below) must see the
-- rewritten file. Falls back to require for exotic layouts.
local function loadConfig()
  local cfg = {}
  for k, v in pairs(DEFAULTS) do cfg[k] = v end
  local user
  local okL, chunk = pcall(loadfile, SHARED_DIR .. "ToastLib_config.lua")
  if okL and chunk then
    local okC, t = pcall(chunk)
    if okC then user = t end
  end
  if user == nil then
    local okR, t = pcall(require, "ToastLib_config")
    if okR then user = t end
  end
  if type(user) == "table" then
    for k, v in pairs(user) do cfg[k] = v end
  end
  return cfg
end

-- WORD-WRAP AT wrapCols (Maiq, 2026-08-07: "character limit on toasts and text wrapping,
-- start with 80"). Long single-line toasts draw as screen-wide strips on the HUD canvas
-- (the SO board's 1900px lesson, transient edition -- OLF's new warnings hit ~110 chars).
-- Word-boundary wrap; a single word longer than the limit hard-splits. Applied at notify
-- time so the draw path stays dumb.
local function wrapText(msg, cols)
  msg = tostring(msg or "")
  cols = math.max(20, math.floor(tonumber(cols) or 40))
  if #msg <= cols then return { msg } end
  local lines, line = {}, ""
  for word in msg:gmatch("%S+") do
    if line == "" then line = word
    elseif #line + 1 + #word <= cols then line = line .. " " .. word
    else lines[#lines + 1] = line; line = word end
    while #line > cols do lines[#lines + 1] = line:sub(1, cols); line = line:sub(cols + 1) end
  end
  if line ~= "" then lines[#lines + 1] = line end
  if #lines == 0 then lines[1] = "" end
  return lines
end

-- LONG TOASTS LINGER (Maiq, 2026-08-07: "if a message is longer, we should let it set a bit
-- longer"). +1.5s per wrapped line beyond the first, capped at +6s -- a one-liner keeps the
-- snappy default; a merged blacklist burst holds long enough to actually read.
local function lingerBonusS(nLines)
  return math.min(math.max((nLines or 1) - 1, 0), 4) * 1.5
end

-- DEDUPE + BURST-MERGE (Maiq, 2026-08-07: OLF's "X is on your blacklist ..." arriving for
-- Ore, Slab AND Wood painted three near-identical strips). Two rules, applied at notify:
--   exact repeat  -> the matching LINE of the live toast gains a "(xN)" badge and the
--                    clock restarts (2026-08-08: per-line, not per-toast -- a repeat of
--                    one line of a merged panel used to re-join as a fresh line, so the
--                    same message could sit in the panel twice);
--   same-mod burst -> a different message from the SAME mod within MERGE_S of the panel's
--                     FIRST message joins it as extra lines. Anchored to the first birth
--                     (2026-08-08): anchoring to the latest let a steady drip chain the
--                     window forever, accreting unrelated messages minutes apart into
--                     what reads as one moment.
local MERGE_S = 2.5          -- burst window, seconds since the joined toast was BORN
local MERGE_MAX_LINES = 8    -- a merged toast never grows past this; overflow starts a new one

-- TEMPLATE COLLAPSE (Maiq, 2026-08-08, from a screenshot of four OLF warnings: "there's
-- gotta be a more economical way ... n toasts with mostly the same information, but just
-- different subjects"). When burst-merged messages share a long common SUFFIX (the
-- template), display the differing heads as one subject list followed by the template
-- once: "Reindrix Venison, Ore, Slab Fragment is on your loot filter -- ...". Messages
-- that differ throughout (Standing Orders' per-item queue reports carry distinct
-- numbers in the body) never qualify and merge as ordinary lines.
local COLLAPSE_MIN = 24      -- chars of shared suffix required...
local COLLAPSE_FRAC = 0.5    -- ...and at least this fraction of the shorter message
-- Longest common suffix that starts at a WORD BOUNDARY (a space stays with the
-- template). The boundary rule stops "CopperOre"/"IronOre" from splitting into
-- subjects "Copper"/"Iron" with a template that eats the shared "Ore".
local function templateOf(a, b)
  local n, la, lb = 0, #a, #b
  while n < la and n < lb and a:byte(la - n) == b:byte(lb - n) do n = n + 1 end
  if n == 0 then return nil end
  local sp = a:find(" ", la - n + 1, true)   -- first space inside the shared suffix
  if not sp then return nil end
  local tpl = a:sub(sp)                       -- keeps its leading space
  if #tpl < COLLAPSE_MIN then return nil end
  if #tpl < COLLAPSE_FRAC * math.min(la, lb) then return nil end
  return tpl
end

-- GAME FEED SURFACE (Maiq, 2026-08-08: "look up how the graphics mod does their toast
-- styles"). cfg.useGameFeed hands each toast to the game's own notification feed --
-- PalPlayerController:AddKillLog_Client with LogType 2 (EPalKillLogDisplayType), the
-- mod name as AttackerName and the message as KilledCharacterName. The same game API
-- UltraGraphics announces through (technique studied, implementation ours; struct
-- verified against CXXHeaderDump FPalKillLogDisplayData). The GAME styles, stacks and
-- expires feed rows, so position/wrap/lifebar and the merge rules do not apply there;
-- exact repeats are dropped for one toast-lifetime instead (no badge is possible).
-- Stickies and custom surfaces (weapon panel, orders board) always stay drawn panels:
-- a progress bar cannot ride a transient feed row.
local nativePC = nil
local function nativeNotify(title, msg)
  local ok, sent = pcall(function()
    local pc = nativePC
    if not (pc and pc:IsValid()) then pc = FindFirstOf("PalPlayerController"); nativePC = pc end
    if not (pc and pc:IsValid()) then return false end
    pc:AddKillLog_Client({ LogType = 2, AttackerName = tostring(title),
                           KilledCharacterName = tostring(msg) })
    return true
  end)
  return ok and sent == true
end

-- ---- channel bookkeeping (module level) ------------------------------------
-- muting lives IN ToastLib_config as generated flat keys (mute_<Name> = true),
-- written by the Toasts page's per-mod toggles -- see registerToastsSchema.
-- The mute key reaches EVERY surface, channel and custom alike (2026-08-06);
-- styling of a custom surface remains its owner's business.

-- consumer registry: Mods/shared/DarnToasts_consumers.lua -> { Name = "channel"|"custom" }.
-- Feeds the Toasts page (who exists, who's in the channel) and the auto-lanes.
local CONSUMERS_PATH = SHARED_DIR .. "DarnToasts_consumers.lua"
local function readConsumers()
  local t = {}
  local chunk = loadfile(CONSUMERS_PATH)
  if chunk then
    local ok, v = pcall(chunk)
    if ok and type(v) == "table" then t = v end
  end
  return t
end
local function registerConsumer(name, mode)
  pcall(function()
    local t = readConsumers()
    if t[name] == mode or t[name] == "both" then return end
    -- one mod may run BOTH: channel toasts + a custom panel (Living Arsenal)
    if t[name] ~= nil and t[name] ~= mode then mode = "both" end
    t[name] = mode
    local f = assert(io.open(CONSUMERS_PATH, "w"))
    f:write("-- written by ToastLib at consumer startup; safe to delete (rebuilds)\n")
    f:write("return {\n")
    for n, m in pairs(t) do f:write(string.format("  [%q] = %q,\n", n, m)) end
    f:write("}\n")
    f:close()
  end)
end

-- auto-lane: channel consumers get a stable vertical slot from the SORTED
-- registry, so two mods toasting at once never overlap -- no author opts, no
-- user config needed. (config mods.<Name>.yOffset still overrides, Toasts-side.)
local LANE_PX = 110
-- ONE STACK FOR THE DEFAULT CHANNEL (2026-07-31, Mikey: "I hate this thing where some of my
-- toasts are showing at basically the bottom of the screen. They should all share the same
-- channel and stack together regardless of the source").
--
-- WHAT IT USED TO DO: give every channel consumer its own permanent vertical LANE, alphabetical,
-- (i-1) * 110px. With four consumers registered that put WeaponProficiency 330px below the
-- configured spot -- at the default yFrac 0.20 on a 1080p screen, halfway down the display --
-- and every new mod pushed the next one further. Lanes existed for a real reason: each consumer
-- keeps its OWN toast list and its OWN HUD hook, so without separation two mods' toasts would
-- draw on top of each other.
--
-- THE FIX IS A SHARED ROW CURSOR, not a shared list. Every instance hooks the same
-- ReceiveDrawHUD, so they all draw back-to-back inside one frame: if each starts its rows where
-- the previous instance finished, the result is ONE stack in registration order, at the one
-- configured position, with no lanes and no per-mod list surgery. A mod that draws nothing
-- simply does not advance the cursor.
--
-- New frame detected by a time gap: hooks within a frame run sub-millisecond apart, while
-- frames are >8ms even at 120fps. A missed reset costs one frame of stacking, never a crash.
local SHARED_STACK = { y = 0, at = -1e9 }
-- 2ms, NOT 8ms (2026-07-31 -- the "shiver", measured).
--
-- This threshold separates "another consumer drawing inside the SAME frame" from "a new frame
-- started". Consumers within a frame are microseconds apart; frames are milliseconds. 8ms was
-- picked as "shorter than a frame at 120fps" -- but Maiq's machine runs right there, and the
-- probe caught frame gaps of 8.4, 8.7, 8.2, 9.0, 7.5, 8.9ms. Every gap under 8ms failed to reset
-- the cursor, so the first toast was told to sit at row 0 on some frames and row 42 on others,
-- and the easing chased the flip: rowPos 28.8 -> 25.7 -> 27.2 -> 32.7 -> 29.2 ... a sawtooth,
-- on screen a vertical shiver. It needed MULTIPLE toasts to show (with one, both targets are 0)
-- which is why a single-toast mod looked fine while Outdoor Loot Filter shook.
--
-- 2ms sits an order of magnitude above the within-frame spacing and below any real frame, so it
-- degrades safely in both directions: it would take a 500fps frame to false-negative, and a
-- pathologically slow Lua hook chain to false-positive.
local FRAME_GAP = 0.002
-- TRULY SHARED (2026-08-08, Maiq's screenshot: an Arsenal toast buried UNDER a Standing
-- Orders one). UE4SS gives every mod its OWN Lua state, so this "shared" table was
-- per-mod: each mod's pile started at row 0 and different mods overdrew each other --
-- latent since lanes were retired in 2.2.0, unmasked when 2.6.0 made separate toasts
-- stack again. ModRef:SetSharedVariable is UE4SS's real cross-state storage; the cursor
-- lives there now, same protocol (all states draw back-to-back within a frame, so
-- read-continue-write per state composes one column). The local table remains as the
-- fallback wherever shared variables are unavailable -- same behavior as before there.
local SV_OK = (function()
  local ok = pcall(function() ModRef:SetSharedVariable("darntoasts_sv_probe", 1) end)
  return ok and pcall(function() return ModRef:GetSharedVariable("darntoasts_sv_probe") end)
end)()
local function sharedRowStart(now)
  if SV_OK then
    local at = tonumber((function() local ok, v = pcall(function() return ModRef:GetSharedVariable("darntoasts_stack_at") end); if ok then return v end end)()) or -1e9
    local y = 0
    if (now - at) <= FRAME_GAP then
      y = tonumber((function() local ok, v = pcall(function() return ModRef:GetSharedVariable("darntoasts_stack_y") end); if ok then return v end end)()) or 0
    end
    pcall(function() ModRef:SetSharedVariable("darntoasts_stack_at", now) end)
    return y
  end
  if (now - SHARED_STACK.at) > FRAME_GAP then SHARED_STACK.y = 0 end
  SHARED_STACK.at = now
  return SHARED_STACK.y
end
local function sharedRowEnd(y)
  if SV_OK then
    pcall(function() ModRef:SetSharedVariable("darntoasts_stack_y", y) end)
    return
  end
  SHARED_STACK.y = y
end

-- Lanes are retired. Kept as a stub returning 0 so any external caller (and the config key
-- some users may still carry) degrades to "no offset" rather than erroring.
local function channelLane(name) return 0 end

-- build + register the Toasts page: one mute toggle per known consumer.
-- ALL consumers, not just channel ones (2026-08-06): a custom surface's mute row used to be
-- filtered out here while a "both" consumer (Standing Orders, Living Arsenal) DID get a row --
-- which silenced only its channel toasts and left its panel drawing. A Nexus user muted
-- Standing Orders and could not understand why the board stayed. The mute key now reaches
-- custom surfaces too (see refreshStyle), so every consumer gets a row and the row means
-- "the whole mod's surfaces".
local function registerToastsSchema()
  local names = {}
  for n in pairs(readConsumers()) do
    names[#names + 1] = n
  end
  table.sort(names)
  local rows, defs = {}, {}
  if #names == 0 then
    rows[1] = '        { subtitle = "Mods appear here after their first launch with DarnToasts 2.0." },'
  end
  for _, n in ipairs(names) do
    rows[#rows + 1] = string.format(
      '        { path = %q, label = %q, kind = "bool", live = true },', "mute_" .. n, "Mute " .. n)
    defs[#defs + 1] = string.format(' [%q] = false,', "mute_" .. n)
  end
  local src = TOASTS_SCHEMA
    :gsub("%%MUTE_ROWS%%", function() return table.concat(rows, "\n") end)
    :gsub("%%MUTE_DEFAULTS%%", function() return table.concat(defs, "") end)
  M.registerMenuSchema("DarnToasts", 8400 + #names, src)   -- 8400: the pill/bare style values (2.7.0); a schema EDIT without a version bump never reaches installs -- Maiq could not see Integrated
end
registerToastsSchema()

local function makeInstance(modName, opts, isCustom)
  modName = tostring(modName or "mod")
  local o, cfg
  if isCustom then
    -- CUSTOM SURFACE: a PRIVATE config table -- defaults + the author's opts,
    -- never the shared file, never watched, never muted from the Toasts side.
    -- o == cfg so position keys and style keys live in one place, and
    -- T.configure() merges into it live. The draw code below is identical for
    -- both modes; only where cfg COMES FROM differs.
    cfg = {}
    for k, v in pairs(DEFAULTS) do cfg[k] = v end
    cfg.mods = {}
    if type(opts) == "table" then
      for k, v in pairs(opts) do if k ~= "mods" then cfg[k] = v end end
    end
    o = cfg
  else
    o = {}                 -- the channel takes NO author opts: that's what makes it a channel
    cfg = loadConfig()
  end
  registerConsumer(modName, isCustom and "custom" or "channel")

  -- Everything derived from cfg lives in these upvalues, (re)computed by
  -- refreshStyle -- so a live config change restyles by rerunning it.
  local mine, muted, myColor, myTtl, myScale, myYOff, myAnchor, myXOff, myYFrac
  -- CUSTOM SURFACES HONOR THE USER'S MUTE (2026-08-06). A custom surface's cfg is private by
  -- design -- but that privacy also swallowed the user's mute: the Toasts page wrote
  -- mute_<Name> into the SHARED config, which a custom instance never read, so "Mute
  -- StandingOrders" silenced the channel toasts and left the board panel up (the "can't hide
  -- the notification even muted" Nexus report). The mute key -- and ONLY the mute key -- now
  -- crosses the boundary: styling, position and everything else stay the owner's business.
  local sharedMuted = false
  local function readSharedMute()
    local ok, v = pcall(function()
      local fresh = loadConfig()
      local m = fresh.mods and fresh.mods[modName]
      return (fresh["mute_" .. modName] == true) or (m == false)
        or (type(m) == "table" and m.enabled == false)
    end)
    return ok and v == true
  end
  if isCustom then sharedMuted = readSharedMute() end
  -- Engine UI multiplier ([/Script/Engine.UserInterfaceSettings] ApplicationScale,
  -- set in Engine.ini). Slate applies it to ALL UMG automatically -- so the ESC
  -- menu (DarnMenu) and the weapon nameplate already scale with it -- but our
  -- toasts/panels draw on the RAW HUD canvas (ReceiveDrawHUD), which bypasses
  -- Slate scaling. So we read the value and fold it into our own scale to shrink
  -- in step with the rest of the UI. Re-read by refreshStyle (applies next launch;
  -- ApplicationScale is an ini value, static within a session).
  local appScaleLogged = false
  local function appUIScale()
    local ok, s = pcall(function()
      return StaticFindObject("/Script/Engine.Default__UserInterfaceSettings").ApplicationScale
    end)
    if not (ok and type(s) == "number" and s > 0.1 and s <= 4) then s = 1.0 end
    if not appScaleLogged then
      appScaleLogged = true
      print("[DarnToasts] " .. tostring(modName) .. ": UI ApplicationScale = " .. tostring(s) .. " (folded into toast scale)\n")
    end
    return s
  end
  local function refreshStyle()
    mine = cfg.mods and cfg.mods[modName]
    muted = (cfg.enabled == false) or (mine == false)
      or (type(mine) == "table" and mine.enabled == false)
      or (not isCustom and cfg["mute_" .. modName] == true)   -- Toasts-page mute toggle (channel: cfg IS the shared file)
      or (isCustom and sharedMuted)                           -- Toasts-page mute toggle (custom: read across the boundary)
    if type(mine) ~= "table" then mine = {} end
    myColor = mine.color or cfg.color or DEFAULTS.color
    myTtl   = tonumber(mine.ttl or cfg.ttl) or DEFAULTS.ttl
    myScale = (tonumber(mine.scale or cfg.scale) or DEFAULTS.scale) * appUIScale()
    -- lane: user config wins; custom surfaces use their own o.yOffset; channel
    -- consumers get a stable AUTO-lane from the sorted registry (no collisions)
    local lane = 0
    if mine.yOffset ~= nil then lane = tonumber(mine.yOffset) or 0
    elseif isCustom and o.yOffset ~= nil then lane = tonumber(o.yOffset) or 0
    elseif not isCustom then lane = channelLane(modName) end
    myYOff = (tonumber(cfg.yOffset) or 0) + lane
    -- POSITION is per-mod too (2026-07-22): a mod may default its toasts/stickies
    -- to a screen region (e.g. WeaponProficiency's panel beside the weapon
    -- scroll); the user's config mods.<Name>.anchor/xOffset/yFrac always wins.
    myAnchor = mine.anchor or o.anchor or nil
    myXOff = (mine.xOffset ~= nil and tonumber(mine.xOffset)) or (o.xOffset ~= nil and tonumber(o.xOffset)) or nil
    myYFrac = (mine.yFrac ~= nil and tonumber(mine.yFrac)) or (o.yFrac ~= nil and tonumber(o.yFrac)) or nil
  end
  refreshStyle()

  local T = {}
  local safe = function(f) local ok2, v = pcall(f); if ok2 then return v end end
  local alive = function(o)
    if o == nil then return false end
    local ok2, v = pcall(function() return o:IsValid() end)
    return ok2 and v == true
  end

  local HUDHOOK = "/Game/Pal/Blueprint/UI/BP_PalHUD_InGame.BP_PalHUD_InGame_C:ReceiveDrawHUD"
  local toasts = {}                       -- oldest first; {msg, bornS, r, g, b, rowPos}
  local stickies = {}                     -- ordered; persistent progress panels (see T.progress)
  local stickyById = {}                   -- [id] = entry
  local MAXSTACK = math.max(1, math.floor(tonumber(cfg.stack) or 4))
  local GAP = tonumber(cfg.stackGap) or 8
  local ticks, hookBeat = 0, -1000
  local hudFont, hudMath, colorCache = nil, nil, {}
  local hudPre, hudPost = nil, nil
  local screenW, screenH = 0, 0
  local prevFrameS = nil

  -- frame-smooth clock; falls back to the 500ms tick clock if os.clock is out
  local function nowS() return safe(function() return os.clock() end) or (ticks * 0.5) end

  local function getFont()
    if hudFont then return hudFont end
    for _, p in ipairs({ "/Engine/EngineFonts/Roboto.Roboto", "/Game/Pal/Font/Ft_PalDefaultFont.Ft_PalDefaultFont" }) do
      local c = safe(function() return StaticFindObject(p) end); if c then hudFont = c; return c end
    end
  end
  local function col(r, g, b, a)
    a = a or 1
    local k = string.format("%.2f_%.2f_%.2f_%.2f", r, g, b, a)
    if colorCache[k] ~= nil then return colorCache[k] end
    if not hudMath then hudMath = safe(function() return StaticFindObject("/Script/Engine.Default__KismetMathLibrary") end) end
    local c = hudMath and safe(function() return hudMath:MakeColor(r, g, b, a) end) or false
    colorCache[k] = c
    return c or nil
  end
  local function rect(hud, c, x, y, w, h) if c and w > 0 and h > 0 then safe(function() hud:DrawRect(c, x, y, w, h) end) end end
  local function textAt(hud, s, c, x, y, sc)
    local ft = getFont(); if c and ft then safe(function() hud:DrawText(tostring(s), c, x, y, ft, sc, false) end) end
  end

  -- ONE GEOMETRY FUNCTION, TWO CALLERS (2026-07-31). The panel box was measured in two
  -- places -- renderOne computed w/h, and drawToast's heightOf recomputed h from the same
  -- literals -- so any change to the box had to be made twice and identically or the stack
  -- spacing silently drifted from what was drawn. Adding LINES would have made that three
  -- copies. It is now derived once, here, and both callers read it.
  --
  -- ROWS (`lines`): a sticky may carry a list of {text=, frac=, r=,g=,b=} rows, drawn as a
  -- compact column under the sub with an optional fill bar per row. Text on the HUD canvas
  -- cannot be clipped, so the box has to be sized to the widest string up front -- that is
  -- what BAR_FRAC and the char-width estimate below are for.
  local LINE_BAR_FRAC = 0.34         -- share of the panel width reserved for row bars
  local function geom(item, sc)
    local g = { scT = sc, scS = sc * 0.9, scL = sc * 0.85 }
    if not item.sticky then
      local ls = item.msgLines or { item.msg }
      local longest = 0
      for i = 1, #ls do if #ls[i] > longest then longest = #ls[i] end end
      g.tlines, g.lineStep = ls, 18 * sc + 2
      g.w = longest * 10 * sc + 30
      g.h = 24 + 8 * sc + (#ls - 1) * g.lineStep
      return g
    end
    g.scT = sc * 1.15
    local wChars = #item.msg
    -- an empty sub is ABSENT: it must not reserve a text row's height (bare
    -- surfaces pass "" to clear a previous sub without leaving a gap)
    local hasSub = item.sub ~= nil and item.sub ~= ""
    if hasSub then wChars = math.max(wChars, math.floor(#item.sub * 0.9)) end
    g.w = math.max(wChars * 10 * g.scT + 32, 300 * sc)
    -- a custom surface may pin its width (the integrated weapon bar must match
    -- the game's weapon card, not the text-derived minimum)
    local fw = tonumber(cfg.width)
    if fw and fw > 60 then g.w = fw end
    g.h = 14 + 18 * g.scT + (hasSub and (15 * g.scS + 6) or 0)
    local rows = item.lines
    if type(rows) == "table" and #rows > 0 then
      g.rowH = 15 * g.scL + 3
      g.anyBar = false
      local longest = 0
      for i = 1, #rows do
        local r = rows[i]
        local n = #tostring(r.text or "")
        if n > longest then longest = n end
        if r.frac ~= nil then g.anyBar = true end
      end
      -- the text column is (1 - BAR_FRAC) of the box when bars are present, so the box has
      -- to be that much wider than the text itself or the longest label runs under its bar
      local need = longest * 10 * g.scL + 32
      if g.anyBar then need = need / (1 - LINE_BAR_FRAC) end
      if need > g.w then g.w = need end
      g.h = g.h + 4 + #rows * g.rowH
    end
    g.h = g.h + 9                    -- bottom pad + bar: everything CONTAINED
    return g
  end

  -- draw ONE toast at its (animated) row. All the styling lives here.
  -- STYLE vs POSITION are independent (Maiq, 2026-08-08): cfg.style picks the SKIN
  -- ("panel" = the Darn pill with accent + unravel; "native" = a flat game-feed-like
  -- strip, instant text, no decoration) and BOTH honor the Position/Stacking settings.
  -- Only style "feed" (handled in notify, never here) cedes position to the game.
  local function renderOne(hud, t, age, ttlS, now)
    -- "panel" (default) wears the Darn family SURFACE language since 2.7.0
    -- (Maiq: "spruce up the default toasts") -- the same glass slab + hairline
    -- outline + solid edge accent Standing Orders' cards settled on. The old
    -- pill look stays one setting away as style = "pill".
    local skin = (cfg.style == "native") and "native"
                 or (cfg.style == "pill") and "pill"
                 or (cfg.style == "bare") and "bare" or "panel"
    local mode = cfg.unravel
    if mode == nil then mode = "left" end
    if skin == "native" then mode = false end   -- feed rows appear; they do not type
    local animS = math.max(0, (tonumber(cfg.animMs) or 280) / 1000)
    local ein = (animS > 0) and math.min(1, age / animS) or 1
    ein = 1 - (1 - ein) ^ 3
    local alpha, yShift
    if mode then alpha, yShift = 0.7 + 0.3 * ein, 0
    else alpha, yShift = ein, (1 - ein) * 14 end
    -- EXIT: "wipe" ravels the panel closed into its accent edge over the last
    -- animMs (mirror of the entry); "fade" is the classic fade + drift-up.
    -- STICKIES have no ttl: they stay until dismissed, then always wipe shut.
    local exitStyle = cfg.exit
    if exitStyle == nil then exitStyle = "wipe" end
    local eout = 1
    if t.sticky then
      if t.dismissAt and animS > 0 then
        eout = math.max(0, math.min(1, 1 - (now - t.dismissAt) / animS))
        eout = 1 - (1 - eout) ^ 3
      end
    elseif mode and exitStyle ~= "fade" then
      if animS > 0 then
        eout = math.max(0, math.min(1, (ttlS - age) / animS))
        eout = 1 - (1 - eout) ^ 3
      end
    else
      local fadeAt = ttlS * 0.65
      if age > fadeAt then
        local f = (age - fadeAt) / (ttlS - fadeAt)
        alpha = alpha * (1 - f)
        yShift = yShift - 6 * f
      end
    end
    -- master opacity (Mod Options slider, 10-100): multiplies every layer
    local opac = tonumber(cfg.opacity)
    if opac then alpha = alpha * math.max(0.1, math.min(1, opac / 100)) end
    if alpha <= 0.01 then return end
    local reveal = math.min(ein, eout)

    local msg, sc = t.msg, myScale
    -- `gm`, NOT `g`: thirty lines below, `local r, g, b = t.r, t.g, t.b` takes the accent
    -- colour, and a geometry table named `g` would be shadowed out from under the row code.
    local gm = geom(t, sc)
    local scT, scS, scL = gm.scT, gm.scS, gm.scL               -- sticky: bigger title, readable sub, small rows
    local w, h = gm.w, gm.h
    local anchor = myAnchor or cfg.anchor
    local xo = myXOff or tonumber(cfg.xOffset) or 0
    local x
    if anchor == "left" then x = xo
    elseif anchor == "right" then x = ((screenW > 0) and screenW or 1920) - w - xo
    else x = ((screenW > 0) and (screenW / 2) or 960) - w / 2 + xo end
    local y = (((screenH > 0) and screenH or 1080) * (myYFrac or tonumber(cfg.yFrac) or 0.68)) + myYOff
      + t.rowPos + yShift
    if screenH > 0 then y = math.max(0, math.min(y, screenH - h)) end

    -- UNRAVEL: during entry the drawn panel is a growing slice of the full
    -- rect, anchored at the accent edge; the text is substring-clipped to the
    -- open width (HUD text can't be clipped, so the reveal IS the substring).
    local px, pw = x, w
    if mode and reveal < 1 then
      pw = math.max(14, w * reveal)
      if mode == "right" then px = x + w - pw end
    end

    local r, g, b = t.r, t.g, t.b
    if skin == "bare" then
      -- BARE (custom surfaces only -- Maiq's integrated weapon display): no
      -- background at all. The content -- bars, shadowed small text -- draws
      -- straight over the game's own HUD, positioned by the owner's sliders.
    elseif skin == "native" then
      -- NATIVE LOOK: flat translucent strips like the game's own feed rows -- no pill,
      -- no accent, no gradient, no shadow. A multi-line toast draws ONE STRIP PER LINE
      -- (Maiq 2026-08-08: the feed look is row-per-entry, not one merged box), in the
      -- text loop below; a single-line toast is one strip here.
      if not (gm.tlines and #gm.tlines > 1) then
        rect(hud, col(0.03, 0.035, 0.05, 0.82 * alpha), px, y, pw, h)
      end
    elseif skin == "pill" then
      -- THE 2.x PILL, kept verbatim for anyone who prefers it (style = "pill"):
      -- soft drop shadow (two layers, offset down-right)
      if cfg.shadow ~= false then
        rect(hud, col(0, 0, 0, 0.18 * alpha), px + 2, y + 3, pw, h)
        rect(hud, col(0, 0, 0, 0.12 * alpha), px + 4, y + 5, pw, h)
      end
      -- body: two crossed rects = 2px rounded-corner pill
      local bg = col(0.015, 0.028, 0.045, 0.90 * alpha)
      rect(hud, bg, px + 2, y, pw - 4, h)
      rect(hud, bg, px, y + 2, pw, h - 4)
      -- subtle top-half highlight (fake gradient)
      rect(hud, col(1, 1, 1, 0.045 * alpha), px + 2, y + 1, pw - 4, math.floor(h * 0.42))
      -- accent stripe with glow, on the unravel edge; + top hairline
      if mode == "right" then
        rect(hud, col(r, g, b, 0.20 * alpha), px + pw - 8, y + 2, 8, h - 4)  -- glow
        rect(hud, col(r, g, b, 0.95 * alpha), px + pw - 3, y + 2, 3, h - 4)  -- stripe
      else
        rect(hud, col(r, g, b, 0.20 * alpha), px, y + 2, 8, h - 4)           -- glow
        rect(hud, col(r, g, b, 0.95 * alpha), px, y + 2, 3, h - 4)           -- stripe
      end
      rect(hud, col(r, g, b, 0.35 * alpha), px + 2, y, pw - 4, 1)            -- top hairline
    else
      -- THE DARN GLASS LOOK, v3 -- copied from the game's OWN HUD this time
      -- (Maiq's 16:11 screenshot settled the argument; v1 was a squared pill,
      -- v2 borrowed MENU language the HUD never uses). Two real anchors:
      --   * a one-shot toast = the weapon-pickup TILE (right edge): a flat
      --     teal-navy slab, ONE bright hairline on the top edge, square
      --     corners, no side bar. The hairline wears the toast's accent.
      --   * a STICKY = the quest tracker (top right): a SOLID accent header
      --     band with DARK text on it, over the dark translucent body.
      if cfg.shadow ~= false then
        rect(hud, col(0, 0, 0, 0.16 * alpha), px + 2, y + 3, pw, h)
      end
      rect(hud, col(0.045, 0.075, 0.10, 0.86 * alpha), px, y, pw, h)  -- the slab
      local ceA = 0.30 * alpha
      rect(hud, col(0.60, 0.68, 0.75, ceA), px, y + h - 1, pw, 1)     -- faint frame
      rect(hud, col(0.60, 0.68, 0.75, ceA), px, y, 1, h)
      rect(hud, col(0.60, 0.68, 0.75, ceA), px + pw - 1, y, 1, h)
      -- the weapon tile's bright top edge, in this toast's accent -- ONE
      -- anatomy for toasts and stickies alike (Maiq on the solid accent
      -- header band: "these solid bg headers are hideous" -- the quest
      -- tracker's band did not survive contact at panel scale)
      rect(hud, col(r, g, b, 0.9 * alpha), px, y, pw, 2)
    end
    -- text with 1px shadow; substring-revealed while unravelling
    -- MULTI-LINE TOASTS (wrapCols): each wrapped line drawn on its own row, each with the
    -- same substring-reveal so the unravel still types. Stickies keep the single-line path.
local ty   -- declared above both text paths: the sticky ROWS block below reads it
    local tlines = (not t.sticky) and gm.tlines or nil
    if tlines and #tlines > 1 then
      local ly = y + (h - (18 * sc + (#tlines - 1) * gm.lineStep)) / 2 + 2
      for i = 1, #tlines do
        if skin == "native" then   -- one feed-like strip behind each line, 2px gap
          rect(hud, col(0.03, 0.035, 0.05, 0.82 * alpha), px, ly - 2, pw, gm.lineStep - 2)
        end
        local lmsg = tlines[i]
        local lch = #lmsg
        if mode and reveal < 1 then
          lch = math.floor((pw - 30) / (10 * scT))
          if lch < 0 then lch = 0 elseif lch > #lmsg then lch = #lmsg end
        end
        if lch > 0 then
          local ls2 = (lch == #lmsg) and lmsg
            or ((mode == "right") and lmsg:sub(#lmsg - lch + 1) or lmsg:sub(1, lch))
          local ltx = (mode == "right") and (px + pw - 16 - lch * 10 * scT) or (px + 16)
          textAt(hud, ls2, col(0, 0, 0, 0.65 * alpha), ltx + 1, ly + 1, scT)
          textAt(hud, ls2, col(0.95, 0.97, 1.0, alpha), ltx, ly, scT)
        end
        ly = ly + gm.lineStep
      end
    end
    -- single-line path (stickies always; toasts that fit one line)
    if not (tlines and #tlines > 1) then
    ty = t.sticky and (y + 7) or (y + (h - 18 * sc) / 2 + 2)
    local nch = #msg
    if mode and reveal < 1 then
      nch = math.floor((pw - 30) / (10 * scT))
      if nch < 0 then nch = 0 elseif nch > #msg then nch = #msg end
    end
    if nch > 0 then
      local s = (nch == #msg) and msg
        or ((mode == "right") and msg:sub(#msg - nch + 1) or msg:sub(1, nch))
      local tx = (mode == "right") and (px + pw - 16 - nch * 10 * scT) or (px + 16)
      textAt(hud, s, col(0, 0, 0, 0.65 * alpha), tx + 1, ty + 1, scT)
      textAt(hud, s, col(0.95, 0.97, 1.0, alpha), tx, ty, scT)
      if t.sub and t.sub ~= "" and reveal >= 1 then
        local sy = ty + 19 * scT
        textAt(hud, t.sub, col(0, 0, 0, 0.55 * alpha), px + 17, sy + 1, scS)
        textAt(hud, t.sub, col(0.85, 0.90, 1.0, 0.85 * alpha), px + 16, sy, scS)
      end
    end
    end   -- single-line path
    -- ROWS: the compact column under the sub. Only once the panel is fully open -- the
    -- unravel reveals by substring, and a half-width row would draw its bar past the edge.
    if gm.rowH and reveal >= 1 then
      local ry = ty + 19 * scT + (t.sub and (15 * scS + 6) or 0) + 4
      local barW = gm.anyBar and (w * LINE_BAR_FRAC - 22) or 0
      for i = 1, #t.lines do
        local ln = t.lines[i]
        local lr = ln.r or r; local lg = ln.g or g; local lb = ln.b or b
        local txt = tostring(ln.text or "")
        textAt(hud, txt, col(0, 0, 0, 0.55 * alpha), px + 17, ry + 1, scL)
        textAt(hud, txt, col(0.88, 0.92, 1.0, 0.92 * alpha), px + 16, ry, scL)
        if ln.frac ~= nil and barW > 8 then
          local fr = math.max(0, math.min(1, tonumber(ln.frac) or 0))
          local bx = px + w - 16 - barW
          local by = ry + (13 * scL - 4) / 2
          rect(hud, col(lr, lg, lb, 0.20 * alpha), bx, by, barW, 4)
          rect(hud, col(lr, lg, lb, 0.90 * alpha), bx, by, barW * fr, 4)
        end
        ry = ry + gm.rowH
      end
    end
    -- bottom bar: PROGRESS (t.frac) for stickies, remaining-life for toasts.
    -- The native skin draws none of it -- the game's feed rows carry no bars.
    if skin == "native" and t.frac == nil then return end
    if t.frac ~= nil then
      local fr = math.max(0, math.min(1, t.frac))
      rect(hud, col(r, g, b, 0.22 * alpha), px + 2, y + h - 5, pw - 4, 5)
      rect(hud, col(r, g, b, 0.92 * alpha), px + 2, y + h - 5, (pw - 4) * fr, 5)
    elseif cfg.lifebar ~= false and ttlS then
      -- ttlS IS NIL FOR STICKIES. It never bit before only because T.progress defaulted frac
      -- to 0, so the branch above always won; now that a row-list panel may carry no frac at
      -- all, an unguarded `age / ttlS` here would be an arithmetic-on-nil inside a HUD hook.
      local rem = 1 - (age / ttlS)
      local bw = (pw - 4) * rem
      if mode == "right" then rect(hud, col(r, g, b, 0.55 * alpha), px + pw - 2 - bw, y + h - 2, bw, 2)
      else rect(hud, col(r, g, b, 0.55 * alpha), px + 2, y + h - 2, bw, 2) end
    else
      rect(hud, col(r, g, b, 0.25 * alpha), px + 2, y + h - 1, pw - 4, 1)
    end
  end

  local function drawToast(self, SizeX, SizeY)
    hookBeat = ticks
    -- MUTE STOPS THE DRAW, not just new posts (2026-08-06). muted used to gate only
    -- notify/progress, so a sticky posted BEFORE the user muted kept drawing forever --
    -- the un-hidable board. Nothing is discarded: toasts age out unseen on unmute, and
    -- stickies (the board) come straight back, which is what a mute toggle should do.
    if muted then return end
    pcall(function()
      local sx = SizeX and SizeX:get(); local sy = SizeY and SizeY:get()
      if type(sx) == "number" and sx > 0 then screenW, screenH = sx, sy end
    end)
    if #toasts == 0 and #stickies == 0 then prevFrameS = nil; return end
    local hud = self and self:get(); if not alive(hud) then return end
    local now = nowS()
    -- ONE DRAW PER FRAME (2026-07-31 -- the "shiver").
    --
    -- RegisterHook on a Blueprint function returns TWO ids (the log prints "(121, 121)") and
    -- UE4SS invokes this callback for BOTH the pre and post hook. So drawToast runs TWICE per
    -- frame, microseconds apart.
    --
    -- That was harmless until 2.2.0 made the row position STATEFUL. The shared cursor resets on
    -- a frame gap, so the first call reset it to 0 and left it at h+GAP, and the second call --
    -- inside the same frame, no reset -- handed the SAME toast the next row down. Every frame the
    -- toast was eased toward 0 and then toward h+GAP, which on screen is a few pixels of vertical
    -- jitter. Maiq: "our toasts now shiver in their frame up and down", and it reproduced with a
    -- single mod toasting alone, which ruled out mods overlapping each other.
    --
    -- 2ms, not FRAME_GAP's 8ms: pre and post are microseconds apart, while a real frame at 144Hz
    -- is 6.9ms and would be wrongly skipped by an 8ms window.
    if prevFrameS and (now - prevFrameS) < 0.002 then return end
    local dt = 0.016
    if prevFrameS then dt = math.max(0, math.min(now - prevFrameS, 0.1)) end
    prevFrameS = now
    local ttlS = myTtl * 0.5
    -- expire finished toasts + fully-closed stickies
    local i = 1
    while i <= #toasts do
      local t = toasts[i]
      local age = now - t.bornS
      if age < 0 then t.bornS = now; age = 0 end               -- clock hiccup guard
      if age > ttlS + (t.bonusS or 0) then table.remove(toasts, i) else i = i + 1 end
    end
    local animS = math.max(0.05, (tonumber(cfg.animMs) or 280) / 1000)
    i = 1
    while i <= #stickies do
      local s = stickies[i]
      if s.dismissAt and (now - s.dismissAt) > animS then
        stickyById[s.id] = nil
        table.remove(stickies, i)
      else i = i + 1 end
    end
    if #toasts == 0 and #stickies == 0 then return end
    -- one combined column: stickies first (top), then the transient pile --
    -- everything shares the same row-easing so dismissals glide closed
    local ease = math.min(1, dt * 12)
    local sc = myScale
    local function heightOf(item) return geom(item, sc).h end
    -- SHARED CURSOR for the default channel: continue the stack the previous consumer left
    -- this frame, so every mod's toasts form ONE column instead of each owning a lane.
    -- A CUSTOM surface is deliberately placed by its own mod and keeps its own origin.
    local rowY = isCustom and 0 or sharedRowStart(now)
    for _, s in ipairs(stickies) do
      if s.rowPos == nil then s.rowPos = rowY end
      s.rowPos = s.rowPos + (rowY - s.rowPos) * ease
      renderOne(hud, s, now - s.bornS, nil, now)
      rowY = rowY + heightOf(s) + GAP
    end
    for _, t in ipairs(toasts) do
      if not t.feedPending then   -- feed-bound toasts wait for feedPump, never draw
        if t.rowPos == nil then t.rowPos = rowY end
        t.rowPos = t.rowPos + (rowY - t.rowPos) * ease
        -- bonusS: long/merged toasts linger past the base ttl (see lingerBonusS)
        renderOne(hud, t, now - t.bornS, ttlS + (t.bonusS or 0), now)
        rowY = rowY + heightOf(t) + GAP
      end
    end
    if not isCustom then sharedRowEnd(rowY) end
  end

  -- HOOK RE-REGISTRATION IS RATE-LIMITED (2026-07-31). The health check below re-registers when
  -- it has not seen a draw for 4 ticks -- but re-registering did not update hookBeat, so the
  -- condition stayed true and it tore the hook down and rebuilt it EVERY tick.
  --
  -- Measured in the log of the 14:04:13 CTD: 49 register/unregister pairs on
  -- BP_PalHUD_InGame_C:ReceiveDrawHUD in 68 seconds, roughly two per second, continuing right up
  -- to the crash. It happens whenever a STICKY is open (the Standing Orders board is one, and it
  -- persists per world) while the HUD is not drawing -- i.e. every loading screen, indefinitely.
  -- Swapping an engine hook's trampoline twice a second while the engine may be walking it is
  -- not something to leave running, whatever it turns out to have caused.
  --
  -- Backoff: 4 ticks (2s), doubling to a 60-tick (30s) ceiling, reset the moment a real draw
  -- arrives. A HUD that genuinely comes back is picked up within one interval; a HUD that is
  -- never coming (loading, menus, dedicated server) costs two attempts a minute instead of 120.
  local hookBackoff, hookLastTry = 4, -1000
  local function registerHUD()
    hookLastTry = ticks
    if hudPre then pcall(function() UnregisterHook(HUDHOOK, hudPre, hudPost) end); hudPre, hudPost = nil, nil end
    local ok2, a, b = pcall(function() return RegisterHook(HUDHOOK, drawToast) end)
    if ok2 then hudPre, hudPost = a, b end
  end

  -- Rebuild a toast's display lines from its parts. Two part shapes:
  --   plain:     { msg = "...", n = 1 }                      -> "msg  (xN)"
  --   templated: { template = " is on ...", subjects = { { s = "Ore", n = 1 }, ... } }
  --              -> "SubjA, SubjB (x2), SubjC<template>" (one template, many subjects)
  -- t.msg stays the join of full reconstructed messages so anything reading it holds.
  local function rebuildLines(t)
    local lines, msgs, flats = {}, {}, {}
    for _, p in ipairs(t.parts) do
      local s
      if p.template then
        local subj = {}
        for _, u in ipairs(p.subjects) do
          subj[#subj + 1] = (u.n or 1) > 1 and (u.s .. " (x" .. u.n .. ")") or u.s
          msgs[#msgs + 1] = u.s .. p.template
        end
        s = table.concat(subj, ", ") .. p.template
      else
        msgs[#msgs + 1] = p.msg
        s = (p.n or 1) > 1 and (p.msg .. "  (x" .. p.n .. ")") or p.msg
      end
      for _, ln in ipairs(wrapText(s, cfg.wrapCols)) do lines[#lines + 1] = ln end
      flats[#flats + 1] = s
    end
    t.msgLines, t.msg, t.bonusS = lines, table.concat(msgs, "\n"), lingerBonusS(#lines)
    t.flat = table.concat(flats, " | ")   -- unwrapped, for the game feed (one row)
  end

  -- GAME FEED AGGREGATION (Maiq, 2026-08-08: "Our toasts seem to write over those").
  -- The feed is a SHARED surface with a handful of rows: every entry we add displaces a
  -- game notification. Sending each notify() as its own row let one OLF burst wipe the
  -- feed clean. Feed-bound toasts now ride the SAME merge/collapse pipeline as drawn
  -- ones, and this pump sends each toast as ONE combined row once its burst settles
  -- (0.8s of quiet). If the controller is gone (title/loading), the toast falls back to
  -- being drawn -- nothing is dropped.
  local nativeLast = {}   -- msg -> last time sent to the feed (repeat suppression)
  local feedPumpArmed = false
  local armFeedPump
  local function feedPump()
    feedPumpArmed = false
    local now = nowS()
    local pending = false
    for i = #toasts, 1, -1 do
      local t = toasts[i]
      if t.feedPending then
        if (now - t.bornS) >= 0.8 then
          if nativeNotify(modName, t.flat or t.msg) then
            if t.parts and #t.parts == 1 and t.parts[1].msg then
              local n = 0; for _ in pairs(nativeLast) do n = n + 1 end
              if n > 64 then nativeLast = {} end
              nativeLast[t.parts[1].msg] = now
            end
            table.remove(toasts, i)
          else
            t.feedPending = nil                      -- controller gone: draw it instead
            if not hudPre then registerHUD() end
          end
        else
          pending = true
        end
      end
    end
    if pending then armFeedPump() end
  end
  armFeedPump = function()
    if feedPumpArmed then return end
    feedPumpArmed = true
    pcall(function() ExecuteWithDelay(400, function() pcall(feedPump) end) end)
  end

  function T.notify(msg, r, g, b)
    if muted then return end
    msg = tostring(msg)
    local now = nowS()
    -- GAME FEED (separate from style: the game decides position and look). Repeats of a
    -- row already SENT within one toast-lifetime are dropped here; everything else runs
    -- through the normal merge/collapse below and is sent by feedPump when it settles.
    local feed = (cfg.useGameFeed == true)
    if feed then
      local ttlS = (tonumber(cfg.ttl) or 10) * 0.5
      if nativeLast[msg] and (now - nativeLast[msg]) < ttlS then return end
    end
    -- EXACT REPEAT -> per-LINE badge + clock restart, never a second panel and never a
    -- duplicate line inside a merged one (templated parts badge per SUBJECT). Newest
    -- toast wins so a long-lived stack cannot resurrect an old copy further up the pile.
    for i = #toasts, 1, -1 do
      local t = toasts[i]
      for _, p in ipairs(t.parts or {}) do
        if p.template then
          for _, u in ipairs(p.subjects) do
            if u.s .. p.template == msg then
              u.n = (u.n or 1) + 1
              rebuildLines(t); t.bornS = now
              if t.feedPending then armFeedPump() end
              return
            end
          end
        elseif p.msg == msg then
          p.n = (p.n or 1) + 1
          rebuildLines(t); t.bornS = now
          if t.feedPending then armFeedPump() end
          return
        end
      end
    end
    -- TEMPLATE COLLAPSE ONLY (2026-08-08, Maiq: "toasts are ... over-writing and not
    -- stacking like they used to"). The generic same-mod burst-join used to fold ANY
    -- two messages from one mod into a single panel -- which meant a message you were
    -- reading got rewritten in place by the next unrelated one, and nothing stacked.
    -- Now only SAME-SENTENCE messages (shared template, different subjects -- the
    -- economy Maiq asked for) collapse into one toast; genuinely different messages
    -- are separate toasts that stack, as before the merge era.
    local last = toasts[#toasts]
    if last and last.src == modName and last.parts
       and (now - (last.firstBornS or last.bornS)) < MERGE_S then
      local joined = false
      for _, p in ipairs(last.parts) do
        if p.template and #msg > #p.template and msg:sub(-#p.template) == p.template then
          p.subjects[#p.subjects + 1] = { s = msg:sub(1, #msg - #p.template), n = 1 }
          joined = true
          break
        elseif p.msg then
          local tpl = templateOf(p.msg, msg)
          if tpl and #tpl < #p.msg and #tpl < #msg then   -- both heads must be non-empty
            p.template = tpl
            p.subjects = { { s = p.msg:sub(1, #p.msg - #tpl), n = p.n or 1 },
                           { s = msg:sub(1, #msg - #tpl), n = 1 } }
            p.msg, p.n = nil, nil
            joined = true
            break
          end
        end
      end
      if joined then
        rebuildLines(last)
        last.bornS = now
        if last.feedPending then armFeedPump() end
        return
      end
    end
    local lines = wrapText(msg, cfg.wrapCols)
    toasts[#toasts + 1] = { msg = msg, msgLines = lines, flat = msg,
      parts = { { msg = msg, n = 1 } },
      bornS = now, firstBornS = now, src = modName, feedPending = feed or nil,
      bonusS = lingerBonusS(#lines),
      r = r or myColor[1], g = g or myColor[2], b = b or myColor[3] }
    if #toasts > MAXSTACK then table.remove(toasts, 1) end
    if feed then armFeedPump()
    elseif not hudPre then registerHUD() end
  end
  function T.muted() return muted end
  T._toasts = toasts   -- TEST SEAM (tools/test-toastlib.js drives the merge rules); not API

  -- STICKY PROGRESS PANEL: a persistent toast with a progress bar. Same look,
  -- lanes and config as regular toasts; renders ABOVE the transient pile.
  -- info = { text = "Old Bow  Lv 41", sub = "Dmg 1047 (+1510%)", frac = 0.62,
  --          r,g,b (optional accent) }. Call again with the same id to update
  -- in place; T.dismiss(id) ravels it shut.
  function T.progress(id, info)
    if muted or type(info) ~= "table" then return end
    id = tostring(id or "default")
    local s = stickyById[id]
    if not s then
      s = { sticky = true, id = id, bornS = nowS() }
      stickyById[id] = s
      stickies[#stickies + 1] = s
      if #stickies > 3 then                                    -- cap: dismiss the oldest
        local old = stickies[1]
        if old and not old.dismissAt then old.dismissAt = nowS() end
      end
    end
    s.msg = tostring(info.text or s.msg or "")
    s.sub = info.sub and tostring(info.sub) or nil
    -- ROWS. Copied, not referenced: the caller rebuilds its list every refresh, and holding
    -- its table would let a half-built list be drawn mid-frame. Anything malformed is dropped
    -- rather than erroring -- this runs on the way to a HUD hook.
    if info.lines ~= nil then
      local out = nil
      if type(info.lines) == "table" and #info.lines > 0 then
        local cap = math.max(1, math.floor(tonumber(info.maxLines) or 6))
        out = {}
        for i = 1, math.min(#info.lines, cap) do
          local ln = info.lines[i]
          if type(ln) == "table" and ln.text ~= nil then
            out[#out + 1] = { text = tostring(ln.text), frac = tonumber(ln.frac),
                              r = tonumber(ln.r), g = tonumber(ln.g), b = tonumber(ln.b) }
          end
        end
        if #out == 0 then out = nil end
      end
      s.lines = out
    end
    -- frac stays NIL unless the caller asked for one: a row-list panel wants no bottom bar,
    -- and defaulting to 0 drew an empty 5px trough under every board.
    s.frac = tonumber(info.frac) or s.frac
    s.r = info.r or s.r or myColor[1]
    s.g = info.g or s.g or myColor[2]
    s.b = info.b or s.b or myColor[3]
    if s.dismissAt then s.dismissAt = nil; s.bornS = nowS() end -- resurrect mid-close
    if not hudPre then registerHUD() end
  end

  function T.dismiss(id)
    local s = stickyById[tostring(id or "default")]
    if s and not s.dismissAt then s.dismissAt = nowS() end
  end

  -- 500ms clock: hook health only (re-register if the game recreated the HUD
  -- blueprint while toasts are live) + the tick fallback for nowS().
  local function clock()
    ticks = ticks + 1
    -- Custom surfaces re-read the SHARED config's mute key every 20 ticks (10s -- the same
    -- cadence as the channel watcher, chosen for the same shared-heap-race reason). Ridden on
    -- THIS clock rather than a new ExecuteWithDelay chain: every extra async timer fire is
    -- one more race window (see the watcher note below), and this timer already exists.
    if isCustom and ticks % 20 == 0 then
      local prev = sharedMuted
      sharedMuted = readSharedMute()
      if sharedMuted ~= prev then refreshStyle() end
    end
    -- A real draw resets the backoff: the HUD is alive, so the next outage retries promptly.
    if (ticks - hookBeat) <= 4 then hookBackoff = 4 end
    if not muted and (#toasts > 0 or #stickies > 0)
        and (ticks - hookBeat) > 4                        -- no draw seen recently
        and (ticks - hookLastTry) >= hookBackoff then     -- ...and we are due another attempt
      registerHUD()
      hookBackoff = math.min(hookBackoff * 2, 60)
    end
    ExecuteWithDelay(500, clock)
  end
  ExecuteWithDelay(500, clock)

  -- YOUR config, applied live: merge any style/position keys into this
  -- instance's private table and restyle. The heart of a CUSTOM surface --
  -- call it at boot and from your own watchConfig callback. On a channel
  -- instance it is a logged no-op (the Toasts page owns channel style).
  function T.configure(tbl)
    if not isCustom then
      print("[ToastLib] configure() ignored for '" .. modName
        .. "' -- default-channel toasts are managed on the Toasts page\n")
      return false
    end
    if type(tbl) ~= "table" then return false end
    for k, v in pairs(tbl) do
      if k ~= "mods" then cfg[k] = v end
    end
    refreshStyle()
    MAXSTACK = math.max(1, math.floor(tonumber(cfg.stack) or 4))
    GAP = tonumber(cfg.stackGap) or 8
    return true
  end

  -- LIVE SETTINGS (channel only): when DarnMenu Apply (or a hand edit)
  -- rewrites ToastLib_config.lua OR the mute list, restyle within ~2s --
  -- display-only, so hot application is safe. Text-compare; loadConfig is
  -- loadfile-based so the reload actually sees the new file (require caches).
  -- Custom surfaces get NO watcher: their owner pushes changes via configure().
  if not isCustom then
    local function watchText()
      local f = io.open(SHARED_DIR .. "ToastLib_config.lua", "r")
      if not f then return "" end
      local s = f:read("*a") or ""
      f:close()
      return s
    end
    local lastWatch = watchText()
    local function cfgWatch()
      pcall(function()
        local txt = watchText()
        if txt ~= lastWatch then
          lastWatch = txt
          local wasStyle = cfg.style
          local fresh = loadConfig()
          for k in pairs(cfg) do cfg[k] = nil end
          for k, v in pairs(fresh) do cfg[k] = v end
          refreshStyle()
          MAXSTACK = math.max(1, math.floor(tonumber(cfg.stack) or 4))
          GAP = tonumber(cfg.stackGap) or 8
          -- STYLE PREVIEW (Maiq, 2026-08-10: "when you toggle toast style,
          -- send up a toast so people can preview what it looks like").
          -- Gated to the DarnToasts instance so eight consumers' watchers
          -- don't fire eight previews. Toasts draw on the HUD: if the menu
          -- covers it, the preview greets the player as the menu closes.
          if modName == "DarnToasts" and cfg.style ~= wasStyle then
            local lbl = (cfg.style == "native") and "Native look"
                        or (cfg.style == "pill") and "Classic pill"
                        or "Darn glass"
            T.notify("Toast style: " .. lbl .. " -- this is how it looks")
          end
        end
      end)
      ExecuteWithDelay(10000, cfgWatch)
    end
    -- 10s, not 2s (2026-08-03). Every mod that requires this file runs its own copy of this
    -- watcher, and EVERY async-thread timer fire is one more window in the UE4SS shared-heap
    -- race (two OS threads, one Lua heap -- see the crash-breadcrumb prelude). The 19:38 CTD
    -- died mid-allocation in this very body while eight watchers polled at 2s each. Config
    -- edits land within 10s of an Apply; nobody is watching that closely.
    -- 2026-08-10, RE-LEARNED THE HARD WAY: a "just one fast watcher" 2.5s
    -- exception for the style preview shipped at 16:05 and the very first
    -- server join ABORTED inside UE4SS's Lua machinery (CTD #23, ucrtbase
    -- abort through process_lua_function). Unprovable from offsets, but the
    -- ledger law stands: the lever is FEWER async timer fires, never more,
    -- and no cosmetic feature buys one back. The preview simply arrives
    -- within ten seconds now.
    ExecuteWithDelay(10000, cfgWatch)
  end

  return T
end

-- DEFAULT CHANNEL: fully DarnToasts-managed. Takes NO opts by design; 1.x
-- callers that pass author positioning are promoted to a CUSTOM surface with a
-- deprecation log (identical runtime behavior to 1.x minus global styling).
function M.new(modName, opts)
  if type(opts) == "table" and next(opts) ~= nil then
    print("[ToastLib] DEPRECATED: new('" .. tostring(modName) .. "', {opts}) -- author "
      .. "positioning means a CUSTOM surface now; use ToastLib.custom(). Promoting.\n")
    return makeInstance(modName, opts, true)
  end
  return makeInstance(modName, nil, false)
end

-- CUSTOM SURFACE: drawing machinery only. DarnToasts applies no global style
-- and no config -- the owning mod manages everything (configure()) -- EXCEPT
-- the user's mute toggle, which reaches every surface (2026-08-06).
function M.custom(modName, opts)
  return makeInstance(modName, opts, true)
end

return M
