return {
  schemaVersion = 1,
  tab = "CS2 Crosshair",
  order = 18,
  target = "CS2Crosshair_user",
  note = "Counter-Strike 2 inspired high-precision reticle suite with recoil bloom and dynamic coloring.",
  live = true,
  defaults = {
    enabled = true,
    style = "ClassicDynamic",
    colorPreset = "Green",
    size = 6.0,
    thickness = 2.0,
    gap = 3.0,
    dot = true,
    drawOutline = true,
    tStyle = false,
    dynamicSpread = true,
    cycleColorHotkey = "F7"
  },
  sections = {
    {
      title = "🎯 Quick Actions",
      options = {
        { path = "enabled", label = "Enable CS2 Crosshair", kind = "bool", help = "Shows high-precision custom reticle", live = true },
        { subtitle = "Use the settings below for live customization, or cycle colors instantly." },
        { path = "_action_cycle_color", label = "Cycle Crosshair Color", kind = "bool",
          help = "Click to cycle the active color preset (same as the F7 hotkey)",
          live = true,
          customValidate = function(v)
            if v == true then
              pcall(function()
                if _G.CS2Crosshair and _G.CS2Crosshair.CycleColorPreset then
                  _G.CS2Crosshair.CycleColorPreset()
                end
              end)
            end
            return true
          end
        }
      }
    },
    {
      title = "General & Presets",
      options = {
        { path = "colorPreset", label = "Color Preset", kind = "enum", values = { "Green", "Cyan", "Yellow", "Red", "Pink", "White" }, labels = { Green = "Classic Green", Cyan = "Vibrant Cyan", Yellow = "Bright Yellow", Red = "Target Red", Pink = "Neon Pink", White = "Pure White" }, help = "Active reticle color profile", live = true },
        { path = "cycleColorHotkey", label = "Cycle Color Hotkey", kind = "keycapture", help = "Press to cycle color presets while in-game", live = true }
      }
    },
    {
      title = "Geometry & Sizing",
      options = {
        { path = "size", label = "Length / Size", kind = "number", min = 2.0, max = 20.0, step = 0.5, help = "Length of each crosshair line", live = true },
        { path = "thickness", label = "Thickness", kind = "number", min = 1.0, max = 8.0, step = 0.5, help = "Width/thickness of crosshair bars", live = true },
        { path = "gap", label = "Center Gap", kind = "number", min = 0.0, max = 20.0, step = 0.5, help = "Distance from screen center to inner line edge", live = true },
        { path = "dot", label = "Center Dot", kind = "bool", help = "Renders a centered aiming dot", live = true },
        { path = "drawOutline", label = "High-Contrast Outline", kind = "bool", help = "Adds black outline borders for maximum visibility against bright scenery", live = true },
        { path = "tStyle", label = "T-Style (No Top Bar)", kind = "bool", help = "Removes top vertical bar for clearer headshot visibility", live = true },
        { path = "dynamicSpread", label = "Dynamic Recoil Spread", kind = "bool", help = "Expands crosshair bars during sustained weapon firing", live = true }
      }
    }
  }
}
