return {
  schemaVersion = 1,
  tab = "Performance & RAM",
  order = 35,
  target = "PalOdysseyOptimizer_user",
  note = "Automated RAM trimming, garbage collection, and actor tick optimizations.",
  live = true,
  defaults = {
    enabled = true,
    trimIntervalSeconds = 60,
    gcIntervalSeconds = 120,
    optimizeParticles = true
  },
  sections = {
    {
      title = "Memory & Engine Tuning",
      options = {
        { path = "enabled", label = "Enable Performance Optimizer", kind = "bool", help = "Active memory manager and tick throttler", live = true },
        { path = "trimIntervalSeconds", label = "RAM Trim Interval (Seconds)", kind = "number", min = 15, max = 300, integer = true, step = 15, help = "How often to trim working set memory", live = true },
        { path = "gcIntervalSeconds", label = "Garbage Collection Interval", kind = "number", min = 30, max = 600, integer = true, step = 30, help = "UE5 GC frequency", live = true },
        { path = "optimizeParticles", label = "Optimize Ambient Particles", kind = "bool", help = "Culls distant particle emitters to boost FPS", live = true }
      }
    }
  }
}
