return {
  schemaVersion = 1,
  tab = "Palbox Search",
  order = 18,
  target = "PalboxSearchPlus_user",
  note = "Adds real-time text searching, element filtering, and passive skill queries to the Palbox grid.",
  live = true,
  defaults = {
    enabled = true,
    highlightMatches = true,
    searchByPassives = true,
    searchByElement = true,
    enableQuickSort = true
  },
  sections = {
    {
      title = "Search & Filter Features",
      options = {
        { path = "enabled", label = "Enable Palbox Search Plus", kind = "bool", help = "Enables search bar & filtering inside Palbox", live = true },
        { path = "highlightMatches", label = "Highlight Matching Pals", kind = "bool", help = "Visually glows Pals matching your active query", live = true },
        { path = "searchByPassives", label = "Search by Passive Skills", kind = "bool", help = "Matches terms like 'Legend', 'Runner', 'Ferocious'", live = true },
        { path = "searchByElement", label = "Search by Element Type", kind = "bool", help = "Filter by 'Dragon', 'Fire', 'Electric', etc.", live = true },
        { path = "enableQuickSort", label = "Enable Quick Sort Bar", kind = "bool", help = "Adds 1-click sorting by Level, Alphabetical, or Suitability", live = true }
      }
    }
  }
}
