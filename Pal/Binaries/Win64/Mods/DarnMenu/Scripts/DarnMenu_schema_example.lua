-- ============================================================================
--  DarnMenu_schema_example.lua -- an annotated, end-to-end example for mod authors.
--  Documentation only; the game never loads this file. Copy the parts you need.
--  Tutorial: DarnMenu_TUTORIAL.md  ·  Full reference: DarnMenu_API.md
--
--  THE ROUND TRIP -- how a menu control reaches YOUR mod's code:
--
--    1. Your mod REGISTERS this schema at startup (see "REGISTER" below).
--    2. The player opens ESC > Mod Options and edits your controls.
--    3. DarnMenu writes the changed keys to  Mods/shared/<target>.lua  as
--       `return { key = value, ... }`  (only what they changed).
--    4. Your mod READS that <target>.lua at startup and merges it over your
--       defaults -- and, for live settings, re-reads it via Darn.watchConfig.
--
--    KEY IDEA: `path` IS the config key. `target` IS the file your mod reads.
--    Name each `path` exactly like the key your mod already uses, and the menu
--    edits your config for free.
--
--  REGISTER (once, at your mod's startup):
--    -- easiest, if DarnToasts is installed (writes both files, idempotent):
--         local haveToasts, ToastLib = pcall(require, "ToastLib")
--         if haveToasts then ToastLib.registerMenuSchema("MyMod", 1, [[ <this file's return>]]) end
--    -- no DarnToasts? Write the two files with plain io -- worked example in
--    -- the tutorial's appendix.
-- ============================================================================

return {
  schemaVersion = 1,                 -- bump this whenever you edit the schema, to re-register
  tab   = "My Mod",                  -- your entry in the left-hand mod list
  order = 100,                       -- sort key among mods (lower = higher up)

  -- WHERE choices are saved. DarnMenu MERGES the player's edits into
  -- Mods/shared/<target>.lua -- the file your mod reads. MUST end in "_user".
  target = "MyMod_user",

  note = "Combat tweaks apply live; display hooks need a relaunch.",  -- top of your page

  -- Fallback Apply message. Usually you never see it: when every saved option
  -- carries a `live` flag, DarnMenu COMPUTES the message from exactly what was
  -- saved ("applied live" / "after relaunch" / "2 applied live, 1 after a
  -- relaunch"). This string shows only for saves that touch flag-less options.
  applyNote = "Saved. See the dots for what applied live.",

  -- Page-wide default for the live/relaunch dots: every option gets an amber
  -- "needs relaunch" dot unless it overrides with its own `live`. (true = green
  -- "applies now" -- only claim it for keys your mod hot-applies via
  -- Darn.watchConfig; the dots are a promise to the player, not decoration.)
  live = false,

  -- Baselines. Used for a control until the player changes it. THESE KEYS ARE
  -- THE KEYS YOUR MOD READS (cfg.enabled, cfg.strength, ...).
  defaults = {
    enabled   = true,
    strength  = 1.0,
    count     = 3,
    mode      = "balanced",
    label     = "",
    port      = 8211,
    toggleKey = "F8",
  },

  sections = {
    { title = "General", options = {
        -- bool + a live override: this key is hot-applied by our watchConfig,
        -- so it earns the green dot even though the page default is amber
        { path = "enabled", label = "Enable mod", kind = "bool", live = true,
          help = "Master on/off switch." },

        -- number with bounds + stepper: min/max validated on Apply (rejected
        -- with a message, never clamped); step renders -/+ buttons that move by
        -- 0.1 within the bounds; "(0-2)" shows on the label automatically
        { path = "strength", label = "Effect strength", kind = "number",
          min = 0, max = 2, step = 0.1, live = true,
          help = "0 = off, 2 = double." },                        -- -> cfg.strength

        -- integer stepper: whole numbers only (2.5 is rejected, steps stay whole)
        { path = "count", label = "Pulse count", kind = "number",
          min = 1, max = 10, step = 1, integer = true, live = true },

        -- enum with DISPLAY LABELS: the player reads the label, your mod gets
        -- the value ("gentle"/"balanced"/"aggressive"), always
        { path = "mode", label = "Mode", kind = "enum", live = true,
          values = { { value = "gentle",     label = "Gentle (-50%)" },
                     { value = "balanced",   label = "Balanced" },
                     { value = "aggressive", label = "Aggressive (+50%)" } },
          help = "How hard the effect leans." },                  -- -> cfg.mode
    }},

    { title = "Advanced", options = {
        { subtitle = "Only used when the mod is enabled:",
          help = "subtitle rows structure a section; dividers draw a line" },

        -- text with a length bound (BYTES -- non-ASCII counts >1; leave headroom)
        { path = "label", label = "Overlay label", kind = "text", maxLen = 24,
          dependsOn = "enabled" },   -- greys out while cfg.enabled is false

        -- custom validation: runs AFTER the built-ins pass; return true to
        -- accept, or false + a message that lands on the player's status line
        { path = "port", label = "Listen port", kind = "number", integer = true,
          dependsOn = "enabled",
          validate = function(v) return v >= 1024 and v <= 65535, "must be 1024-65535" end,
          note = "relaunch to rebind" },   -- your note replaces the auto-bounds hint

        { divider = true },

        -- keycapture: click, then press a key. Stores the UE4SS key NAME
        -- ("F8", "K", "NUM_FIVE"); resolve with Key[cfg.toggleKey]. Amber dot:
        -- UE4SS keybinds can't rebind live, don't pretend otherwise.
        { path = "toggleKey", label = "Toggle hotkey", kind = "keycapture",
          help = "F1-F12, letters, digits, numpad, Ins/Del/Home/End/PgUp/PgDn only." },
    }},

    -- A managed add/remove text list, backed by a plain .txt in shared/. NOT
    -- part of `target`; your mod reads the file itself, one entry per line.
    { title = "Watch list", custom = {
        type  = "listfile",
        file  = "MyMod_watchlist.txt",    -- lives in Mods/shared/
        empty = "No entries yet -- add one below.",
    }},
  },
}

--[==[  ---- HOW YOUR MOD READS IT  (put this in YOUR mod, not in this file) ----

  -- 1) your baseline (mirror the schema's `defaults`)
  local cfg = { enabled = true, strength = 1.0, count = 3, mode = "balanced",
                label = "", port = 8211, toggleKey = "F8" }

  -- 2) overlay the player's saved choices at startup
  local shared = (debug.getinfo(1,"S").source:gsub("^@",""):gsub("[^/\\]+$","")) .. "../../shared/"
  local chunk = loadfile(shared .. "MyMod_user.lua")   -- nil until they save once
  if chunk then
    local ok, user = pcall(chunk)
    if ok and type(user) == "table" then
      for k, v in pairs(user) do cfg[k] = v end        -- player's choice wins
    end
  end

  -- 3) LIVE SETTINGS -- honor the green dots you promised. Only overlay keys
  --    you can truly hot-apply; boot-bound things (keybinds, hooks) stay put.
  local LIVE = { enabled = true, strength = true, count = true, mode = true }
  Darn.watchConfig("MyMod_user", function(user)
    for k, v in pairs(user) do
      if LIVE[k] and type(cfg[k]) == type(v) then cfg[k] = v end
    end
  end)

  -- 4) use it -- cfg.strength is exactly what the "Effect strength" control set
  if cfg.enabled then applyStrength(cfg.strength) end

  -- the list control's file is separate -- read it directly, one entry per line:
  --   for line in io.lines(shared .. "MyMod_watchlist.txt") do handle(line) end
]==]
