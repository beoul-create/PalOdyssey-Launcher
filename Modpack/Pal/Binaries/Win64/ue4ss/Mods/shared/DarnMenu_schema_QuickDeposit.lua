return {
  schemaVersion = 1,
  tab = "Quick Deposit",
  order = 20,
  target = "QuickDeposit_user",
  note = "Instantly deposits matching inventory stacks into nearby chests with one keypress.",
  live = true,
  defaults = {
    enabled = true,
    depositKey = "G",
    depositRadius = 1500.0,
    notifyOnDeposit = true
  },
  sections = {
    {
      title = "Auto-Stack Chest Settings",
      options = {
        { path = "enabled", label = "Enable Quick Deposit", kind = "bool", help = "Enables hotkey deposit to nearby containers", live = true },
        { path = "depositKey", label = "Deposit Hotkey", kind = "keycapture", help = "Key to press when in base to deposit", live = true },
        { path = "depositRadius", label = "Chest Search Radius (Units)", kind = "number", min = 500, max = 5000, integer = true, step = 100, help = "Max distance to search for chests", live = true },
        { path = "notifyOnDeposit", label = "Show Notification On Deposit", kind = "bool", help = "Displays summary when items are stored", live = true }
      }
    }
  }
}
