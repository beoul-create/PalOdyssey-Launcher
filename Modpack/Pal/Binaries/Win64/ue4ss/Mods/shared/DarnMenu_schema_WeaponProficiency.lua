return {
  schemaVersion = 1,
  tab = "Weapon Proficiency",
  order = 30,
  target = "WeaponProficiency_user",
  note = "Weapon mastery leveling, damage scaling, and durability preservation.",
  live = true,
  defaults = {
    enableDamageBonus = true,
    enableDurabilityBonus = true,
    serverDurability = true
  },
  sections = {
    {
      title = "Weapon Mastery System",
      options = {
        { path = "enableDamageBonus", label = "Enable Damage Scaling", kind = "bool", help = "Increases weapon damage as weapon proficiency level rises", live = true },
        { path = "enableDurabilityBonus", label = "Enable Max Durability Scaling", kind = "bool", help = "Increases weapon durability with mastery", live = true },
        { path = "serverDurability", label = "Network Durability Sync", kind = "bool", help = "Synchronizes max durability between server and client", live = true }
      }
    }
  }
}
