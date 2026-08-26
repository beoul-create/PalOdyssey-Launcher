return {
  schemaVersion = 1,
  tab = "Toast Notifications",
  order = 20,
  target = "ToastLib_config",
  note = "Global notification toast styles, screen position, animations, and on-screen stacking.",
  live = true,
  defaults = {
    enabled = true,
    style = "panel",
    scale = 1.4,
    ttl = 10,
    anchor = "center",
    xOffset = 0,
    yFrac = 0.68,
    shadow = true,
    lifebar = true,
    stack = 4
  },
  sections = {
    {
      title = "Appearance & Sizing",
      options = {
        { path = "enabled", label = "Enable Notification Toasts", kind = "bool", help = "Shows animated in-game notifications for mod events", live = true },
        { path = "style", label = "Visual Glass Style", kind = "enum", values = { "panel", "pill", "native" }, labels = { panel = "Glass Panel", pill = "Rounded Pill", native = "Minimal Strip" }, help = "Surface presentation of toast pop-ups", live = true },
        { path = "scale", label = "Text & Surface Scale", kind = "number", min = 0.8, max = 2.5, step = 0.1, help = "Font size and notification panel scaling", live = true },
        { path = "ttl", label = "Display Duration (Half-Seconds)", kind = "number", min = 2, max = 30, integer = true, step = 1, help = "How long toasts remain on screen before auto-closing (10 = 5 seconds)", live = true },
        { path = "shadow", label = "Soft Drop Shadow", kind = "bool", help = "Renders soft ambient shadow behind toast surface", live = true },
        { path = "lifebar", label = "Bottom Expiry Lifebar", kind = "bool", help = "Displays animated draining timer bar at the bottom edge", live = true }
      }
    },
    {
      title = "Screen Placement & Stacking",
      options = {
        { path = "anchor", label = "Screen Horizontal Anchor", kind = "enum", values = { "center", "left", "right" }, labels = { center = "Center Screen", left = "Left Edge", right = "Right Edge" }, help = "Base alignment across the monitor", live = true },
        { path = "xOffset", label = "Horizontal Offset (Pixels)", kind = "number", min = -500, max = 500, integer = true, step = 10, help = "Nudge horizontally off anchor point", live = true },
        { path = "yFrac", label = "Vertical Screen Fraction", kind = "number", min = 0.1, max = 0.95, step = 0.05, help = "Vertical position (0.0 = top of screen, 1.0 = bottom of screen)", live = true },
        { path = "stack", label = "Max Concurrent Toasts", kind = "number", min = 1, max = 10, integer = true, step = 1, help = "Maximum active notification stack depth before dropping oldest", live = true }
      }
    }
  }
}
