-- ============================================================================
--  ToastLib user config -- one place to control EVERY mod's toast pop-ups.
--  Edit and save; changes load on the next game launch.
--
--  Position them, restyle them, or turn them off -- globally or per mod.
-- ============================================================================
return {
  enabled = true,          -- false = NO toasts from any mod, period

  -- ---- position --------------------------------------------------------
  anchor  = "center",      -- "center" | "left" | "right"
  xOffset = 0,             -- px: nudge off center, or margin from the left/right edge
  yFrac   = 0.68,          -- vertical spot as a fraction of screen height (0 top .. 1 bottom)
  yOffset = 0,             -- extra px down (negative = up)

  -- ---- style -----------------------------------------------------------
  style   = "panel",       -- "panel" = the Darn glass surface (default since 2.7.0)
                           -- "pill"  = the pre-2.7 rounded pill with gradient
                           -- "native"= flat feed-like strip, no decoration
  scale   = 1.4,           -- text size; panel grows with it
  ttl     = 10,            -- how long a toast lives, in half-seconds (10 = ~5s)
  color   = { 0.55, 0.85, 1.0 },   -- default accent color {r,g,b} 0..1
  animMs  = 280,           -- entry/exit animation time in ms (0 = instant)
  unravel = "left",        -- "left" = panel wipes open from the left, text typing on (default)
                           -- "right" = mirrored, accent stripe and wipe from the right edge
                           -- false = classic slide-up + fade entry
  exit    = "wipe",        -- "wipe" = ravel closed into the accent edge when done (default)
                           -- "fade" = fade out and drift up instead
  shadow  = true,          -- soft drop shadow behind the panel
  lifebar = true,          -- accent bar along the bottom that drains with time left
  stack   = 4,             -- max toasts shown at once PER MOD (new ones unravel below,
                           -- the pile slides up as older ones finish; oldest dropped past 4)
  stackGap = 8,            -- px between stacked toasts

  -- ---- per-mod ---------------------------------------------------------
  -- Key = the name the mod registers with. Use:
  --   ModName = false,                       -- mute just that mod
  --   ModName = { enabled = false },         -- same thing
  --   ModName = { yOffset = 40 },            -- give it its own lane (px below the others)
  --   ModName = { anchor = "right", xOffset = 210, yFrac = 0.44 },  -- park one mod's
  --                                          -- toasts/panels in its own screen region
  --   ModName = { color = {1, 0.6, 0.2}, ttl = 10, scale = 1.0 },
  mods = {
    -- MedicineHotkeys   = { },
    -- OutdoorLootFilter = { },
  },

  -- BENCH TOOL, off by default. true binds a key that fires five test toasts and a sticky
  -- panel, for eyeballing your style/position/wrap settings all at once. Deliberately not in
  -- the options menu: it is a tool for building toasts, not a feature of having them.
  -- testParade    = true,
  -- testParadeKey = "F9",   -- any Key.* name; F-keys are heavily contested, pick a free one
}
