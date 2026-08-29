return {
  schemaVersion = 1,
  tab = "Fast Loading",
  order = 18,
  target = "FastConnect_user",
  note = "Automated high-speed server connection handshake and instant loading pipeline.",
  live = true,
  defaults = {
    enabled = true,
    ultraFastNetworkRates = true,
    bypassIntroMovies = true,
    accelerateLoadingScreens = true,
    bypassFastTravelWait = true,
    prewarmShaderPipelines = true
  },
  sections = {
    {
      title = "Automatic Server Handshake & Network Speed",
      options = {
        { path = "enabled", label = "Enable Fast Loading Engine", kind = "bool", help = "Enables automatic high-speed server sync and load acceleration", live = true },
        { path = "ultraFastNetworkRates", label = "10x Network Replication Bandwidth", kind = "bool", help = "Multiplies client packet rates to connect and download world state instantly", live = true }
      }
    },
    {
      title = "Loading Time & Transition Bypass",
      options = {
        { path = "bypassIntroMovies", label = "Bypass Intro Movies & Logos", kind = "bool", help = "Automatically skips opening splash screens and intro cinematics", live = true },
        { path = "accelerateLoadingScreens", label = "Accelerate Async Loading Frame Budget", kind = "bool", help = "Allocates maximum frame time to async level streaming for 3x faster loading", live = true },
        { path = "bypassFastTravelWait", label = "Instant Fast-Travel Unfreeze", kind = "bool", help = "Cuts out black-screen fade delays when teleporting", live = true },
        { path = "prewarmShaderPipelines", label = "Pre-Warm Shaders on Load", kind = "bool", help = "Eliminates post-loading shader compilation stutters", live = true }
      }
    }
  }
}
