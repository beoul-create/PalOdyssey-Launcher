return {
  schemaVersion = 1,
  tab = "HUD & Reticles",
  order = 19,
  target = "CleanHUD_user",
  note = "Removes version watermarks, cleans up screen clutter, and provides high-visibility aim reticles.",
  live = true,
  defaults = {
    enabled = true,
    removeWatermark = true,
    removeBuildVersion = true,
    hideCompassClutter = false,
    reticleStyle = "Dot",
    reticleColor = "PureWhite"
  },
  sections = {
    {
      title = "Screen Elements & Watermark",
      options = {
        { path = "enabled", label = "Enable Clean HUD Suite", kind = "bool", help = "Toggles Clean HUD & Reticle system", live = true },
        { path = "removeWatermark", label = "Remove Early Access Watermark", kind = "bool", help = "Hides bottom-right EA string", live = true },
        { path = "removeBuildVersion", label = "Remove Build Number on HUD", kind = "bool", help = "Hides build hash numbers", live = true },
        { path = "hideCompassClutter", label = "Minimalist Compass Bar", kind = "bool", help = "Simplifies icons on the upper compass", live = true }
      }
    },
    {
      title = "Pristine Aim Reticles & Crosshair",
      options = {
        {
          path = "reticleStyle",
          label = "Aim Reticle Style",
          kind = "enum",
          help = "Select custom aiming reticle",
          live = true,
          choices = {
            { value = "Default", label = "Default Palworld Crosshair" },
            { value = "Dot", label = "Crisp Precision Dot (Minimalist)" },
            { value = "MinimalCrosshair", label = "Tight Tactical Crosshair" },
            { value = "CircleDot", label = "Circle & Center Dot" }
          }
        },
        {
          path = "reticleColor",
          label = "Reticle Contrast Tint",
          kind = "enum",
          help = "Crosshair color for visibility against skies and biomes",
          live = true,
          choices = {
            { value = "PureWhite", label = "Pure White (High Contrast)" },
            { value = "CyanGlow", label = "Cyan Glow" },
            { value = "AmberGold", label = "Amber Gold" },
            { value = "NeonGreen", label = "Neon Green" }
          }
        }
      }
    }
  }
}
