return {
  schemaVersion = 1,
  tab = "Stuck Pal Rescuer",
  order = 10,
  target = "StuckPalRescuer_user",
  note = "Monitors base camp worker Pals and safely unstucks/teleports them to the Palbox.",
  live = true,
  defaults = {
    enabled = true,
    checkIntervalSeconds = 8,
    stuckThresholdSeconds = 18,
    minMovementDistance = 30.0,
    notifyOnRescue = true
  },
  sections = {
    {
      title = "Rescue Settings",
      options = {
        { path = "enabled", label = "Enable Stuck Pal Rescuer", kind = "bool", help = "Automatically teleports stuck base Pals back to safety", live = true },
        { path = "checkIntervalSeconds", label = "Scan Interval (Seconds)", kind = "number", min = 3, max = 60, integer = true, step = 1, help = "How often to scan base Pals", live = true },
        { path = "stuckThresholdSeconds", label = "Stuck Timeout (Seconds)", kind = "number", min = 5, max = 120, integer = true, step = 1, help = "Seconds stationary before teleporting", live = true },
        { path = "notifyOnRescue", label = "Log Notifications", kind = "bool", help = "Prints a toast/log when a Pal is rescued", live = true }
      }
    }
  }
}
