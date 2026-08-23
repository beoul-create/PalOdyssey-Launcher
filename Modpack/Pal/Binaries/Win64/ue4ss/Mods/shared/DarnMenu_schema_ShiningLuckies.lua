return {
  schemaVersion = 1,
  tab = "Shining Luckies",
  order = 20,
  target = "ShiningLuckies_user",
  note = "Adds a magical shimmer and star-glint particle aura to Lucky / Rare Pals for clear visibility.",
  live = true,
  defaults = {
    enabled = true,
    glowIntensity = "Moderate",
    starGlintParticles = true,
    beaconBeamDistance = 100.0
  },
  sections = {
    {
      title = "Lucky Pal Visual Indicator",
      options = {
        { path = "enabled", label = "Enable Shining Luckies Glow", kind = "bool", help = "Visually illuminates Lucky Pals", live = true },
        {
          path = "glowIntensity",
          label = "Shimmer Intensity",
          kind = "enum",
          help = "Aura glow brightness level",
          live = true,
          choices = {
            { value = "Subtle", label = "Subtle Glow" },
            { value = "Moderate", label = "Moderate Radiance" },
            { value = "Vibrant", label = "Vibrant Starburst" }
          }
        },
        { path = "starGlintParticles", label = "Star-Glint Particle Trail", kind = "bool", help = "Adds sparkling star glints around Lucky Pals", live = true }
      }
    }
  }
}
