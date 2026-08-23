return {
  schemaVersion = 1,
  tab = "Visual Clarity",
  order = 15,
  target = "PalClearVision_user",
  note = "Synthesized rendering suite: Crystal clear visuals, better night lighting, enhanced LOD, ultra-wide fixes, and frame pacing.",
  live = true,
  defaults = {
    enabled = true,
    removeFogHaze = true,
    disableChromaticAberration = true,
    disableFilmGrain = true,
    crispDepthOfField = true,
    betterNightLight = true,
    enhancedLODDistance = true,
    ultraWideSupport = true,
    asyncTextureStreaming = true,
    framePacingReflex = true,
    enhancedUpscaling = true
  },
  sections = {
    {
      title = "Atmosphere & Visual Sharpness",
      options = {
        { path = "enabled", label = "Enable Visual Clarity Engine", kind = "bool", help = "Applies visual sharpness & clear atmosphere", live = true },
        { path = "removeFogHaze", label = "Remove Fog / Milky Veil", kind = "bool", help = "Eliminates washed-out grey fog layer across the realm", live = true },
        { path = "disableChromaticAberration", label = "Disable Chromatic Aberration", kind = "bool", help = "Removes color-fringe blur around screen edges", live = true },
        { path = "disableFilmGrain", label = "Disable Film Grain & Noise", kind = "bool", help = "Keeps dark areas clean and noise-free", live = true },
        { path = "crispDepthOfField", label = "Sharp Backgrounds (Disable DoF Blur)", kind = "bool", help = "Keeps distant vistas crystal clear", live = true }
      }
    },
    {
      title = "Lighting, LOD & Ultra-Wide",
      options = {
        { path = "betterNightLight", label = "Better Night Light & Atmosphere", kind = "bool", help = "Atmospheric, luminous moonlight without washed-out grays", live = true },
        { path = "enhancedLODDistance", label = "Enhanced LOD & Draw Distance", kind = "bool", help = "Pushes out object and foliage draw distance", live = true },
        { path = "ultraWideSupport", label = "Ultra-Wide 21:9 & 32:9 HUD Fix", kind = "bool", help = "Fixes aspect ratio distortion on ultrawide monitors", live = true }
      }
    },
    {
      title = "Engine Smoothness & Latency",
      options = {
        { path = "asyncTextureStreaming", label = "Async Texture Streaming (Stutter Fix)", kind = "bool", help = "Pre-allocates textures to eliminate transition micro-stutters", live = true },
        { path = "framePacingReflex", label = "Frame Pacing & Reflex Low Latency", kind = "bool", help = "Aligns CPU/GPU queues to minimize input lag", live = true },
        { path = "enhancedUpscaling", label = "Enhanced Temporal Upscaling (FSR/XeSS/TSR)", kind = "bool", help = "Sharpened anti-flicker temporal reconstruction", live = true }
      }
    }
  }
}
