return {
  schemaVersion = 1,
  tab = "Visual Clarity",
  order = 15,
  target = "PalClearVision_user",
  note = "Removes atmospheric fog veil, chromatic aberration, and film grain for razor-sharp visuals.",
  live = true,
  defaults = {
    enabled = true,
    removeFogHaze = true,
    disableChromaticAberration = true,
    disableFilmGrain = true,
    crispDepthOfField = true,
    enhancedShadowDistance = true
  },
  sections = {
    {
      title = "Atmosphere & Post-Processing",
      options = {
        { path = "enabled", label = "Enable Visual Clarity Engine", kind = "bool", help = "Applies visual sharpness & clear atmosphere", live = true },
        { path = "removeFogHaze", label = "Remove Fog / Milky Veil", kind = "bool", help = "Eliminates washed-out grey fog layer across the realm", live = true },
        { path = "disableChromaticAberration", label = "Disable Chromatic Aberration", kind = "bool", help = "Removes color-fringe blur around screen edges", live = true },
        { path = "disableFilmGrain", label = "Disable Film Grain & Noise", kind = "bool", help = "Keeps dark areas clean and noise-free", live = true },
        { path = "crispDepthOfField", label = "Sharp Backgrounds (Disable DoF Blur)", kind = "bool", help = "Keeps distant vistas crystal clear", live = true },
        { path = "enhancedShadowDistance", label = "Enhanced Shadow Distance", kind = "bool", help = "Prevents shadow popping and flickering", live = true }
      }
    }
  }
}
