return {
  schemaVersion = 1,
  tab = "Palworld Tuner",
  order = 25,
  target = "PalworldTuner_user",
  note = "Gameplay multipliers for inventory weight and technology points.",
  live = false,
  defaults = {
    carry_weight_mult = 1.0,
    tech_point_mult = 1.0
  },
  sections = {
    {
      title = "Progression & Multipliers",
      options = {
        { path = "carry_weight_mult", label = "Carry Weight Multiplier", kind = "number", min = 0.5, max = 50.0, step = 0.5, help = "Scales base max weight and stat point gains", live = false },
        { path = "tech_point_mult", label = "Tech Point Multiplier", kind = "number", min = 0.5, max = 10.0, step = 0.5, help = "Scales tech points gained from level ups, fast travel, and bosses", live = false }
      }
    }
  }
}
