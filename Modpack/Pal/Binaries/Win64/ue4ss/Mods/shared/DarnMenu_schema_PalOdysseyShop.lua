return {
  schemaVersion = 1,
  tab = "Tech Shop Emporium",
  order = 15,
  target = "PalOdysseyShop_user",
  note = "In-game Technology Points Emporium, Gacha banner, and recycling station.",
  live = true,
  defaults = {
    enabled = true,
    gachaSingleCost = 3,
    gachaTenCost = 25,
    enableSoundEffects = true,
    notifyToasts = true
  },
  sections = {
    {
      title = "🛒 Quick Actions",
      options = {
        { path = "enabled", label = "Enable Tech Shop Mod", kind = "bool", help = "Enables in-game Tech Point transactions", live = true },
        { subtitle = "Open the native shop window from the Tech Shop Emporium entry. Transactions are serialized by player on the server." }
      }
    },
    {
      title = "Emporium Settings",
      options = {
        { path = "notifyToasts", label = "Show Toast Notifications", kind = "bool", help = "Displays animated toasts on purchase, gacha, or recycle", live = true },
        { path = "enableSoundEffects", label = "Play Sound Effects", kind = "bool", help = "Plays audio cues on shop actions", live = true }
      }
    },
    {
      title = "Gacha Banner Economy",
      options = {
        { path = "gachaSingleCost", label = "Single Pull Cost (TP)", kind = "number", min = 1, max = 20, integer = true, step = 1, help = "Tech point cost for 1 gacha roll (Drop rates: Common 60%, Rare 25%, Epic 12%, Legendary 3%)", live = true },
        { path = "gachaTenCost", label = "10-Pull Cost (TP)", kind = "number", min = 5, max = 100, integer = true, step = 1, help = "Tech point cost for 10-pull with guaranteed Epic or Legendary", live = true }
      }
    },
    {
      title = "Catalog Valuation Reference",
      options = {
        { subtitle = "Ancient Tech: Parts (5 TP), Cores (8 TP), Bronze Key (2 TP), Silver Key (4 TP), Gold Key (6 TP)" },
        { subtitle = "Elixirs & Fruits: Power ATK (6 TP), Health HP (6 TP), Stamina (6 TP), Memory Reset (8 TP)" },
        { subtitle = "Schematics: Legendary Assault Rifle (20 TP), Rocket Launcher (25 TP), Pump Shotgun (18 TP)" },
        { subtitle = "Materials: Pal Metal Ingot (5 TP), Carbon Fiber (4 TP), Polymer (3 TP), Breeding Cake (5 TP)" },
        { subtitle = "Recycling: Overburdened junk automatically converts to TP (Rough Stone, Wood, Bones, Horns, Organs)" }
      }
    }
  }
}
