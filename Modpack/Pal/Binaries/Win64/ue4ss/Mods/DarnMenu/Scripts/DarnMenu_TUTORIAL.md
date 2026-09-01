# DarnMenu — 5-minute tutorial: your first config

**Goal:** put *your* mod in **ESC → Mod Options** with two working controls — an on/off toggle and a
number — and have your mod **read those values** at startup. That's the fundamental unit; everything
else is just more controls (see `DarnMenu_API.md` for all of them).

The flow you're building:

```
schema (path = "greetOn")  →  player edits it in ESC > Mod Options
                           →  DarnMenu writes Mods/shared/MyFirstConfig_user.lua
                           →  your mod loads that file at startup  →  cfg.greetOn
```

`path` is the **config key**. `target` is the **file**. Keep the `path` names identical to the keys
your mod already reads, and the menu edits your config for free.

---

## Before you start

- **Your mod is a UE4SS Lua mod** — a folder with `Scripts/main.lua` and a 0-byte `enabled.txt`,
  visible in `UE4SS.log` at launch. *Pak-only or PalSchema-only mod (no Lua)?* Registration is Lua
  that runs at startup, so ship a tiny companion Lua mod (same two files) to host the page — but
  note baked-in pak/data content can't read a config file at runtime; a menu only helps if your Lua
  half acts on the values.
- **Two kinds of "dependencies" — set both.** Listing `"DarnMenu"` / `"DarnToasts"` in your
  `Info.json` `Dependencies` is loader metadata — it does **not** install anything by itself.
  Auto-install for your subscribers comes from marking them as **Required Items on your Workshop
  page** (Workshop UI). With that set, your users don't have to install anything by hand. Still
  write your mod to **survive a missing dep** (the code below does — a user can unsubscribe one,
  and the worst case should be no menu page/toasts, with your defaults still applying).

---

## Step 1 — your settings and their defaults

Top of your `Scripts/main.lua`:

```lua
-- baseline values, used until the player changes them in the menu
local cfg = { greetOn = true, greetN = 3 }
```

## Step 2 — overlay the player's saved choices

DarnMenu saves edits to `Mods/shared/<target>.lua`. Load it and let it win over your defaults.
(The file doesn't exist until the player saves once — that's fine, `loadfile` returns nil.)

```lua
local dir    = (debug.getinfo(1, "S").source:gsub("^@", ""):gsub("[^/\\]+$", ""))
local shared = dir .. "../../shared/"

local chunk = loadfile(shared .. "MyFirstConfig_user.lua")
if chunk then
  local ok, user = pcall(chunk)
  if ok and type(user) == "table" then
    for k, v in pairs(user) do cfg[k] = v end   -- player's choice wins
  end
end
```

## Step 3 — register your menu page

The one-call helper lives in DarnToasts. Since it may not be installed, look it up defensively —
if it's missing, your mod logs a line and runs fine on defaults:

```lua
package.path = dir .. "../../DarnToasts/Scripts/?.lua;" .. package.path
local haveToasts, ToastLib = pcall(require, "ToastLib")

if haveToasts then
  ToastLib.registerMenuSchema("MyFirstConfig", 1, [[
    return {
      schemaVersion = 1,
      tab    = "My First Config",       -- your entry in the mod list
      target = "MyFirstConfig_user",    -- MUST end in _user; the file Step 2 reads
      defaults = { greetOn = true, greetN = 3 },
      sections = {
        { title = "Greeting", options = {
          { path = "greetOn", label = "Say hello on load", kind = "bool" },
          { path = "greetN",  label = "How many times",    kind = "number",
            min = 1, max = 10, integer = true },   -- bad input rejected on Apply; "(1-10, whole)" auto-shows
        }},
      },
    }
  ]])
else
  print("[MyFirstConfig] DarnToasts not found -- no menu page (mod still works)\n")
  -- no DarnToasts? You can register with plain io instead -- see the appendix.
end
```

(If DarnMenu itself is missing, the schema files just sit unread — also harmless.)

## Step 4 — use the values

```lua
if cfg.greetOn then
  for i = 1, cfg.greetN do print("[MyFirstConfig] hello " .. i .. "\n") end
end
```

---

## The whole `main.lua`

```lua
-- Mods/MyFirstConfig/Scripts/main.lua   (+ a 0-byte Mods/MyFirstConfig/enabled.txt)
local cfg = { greetOn = true, greetN = 3 }

local dir    = (debug.getinfo(1, "S").source:gsub("^@", ""):gsub("[^/\\]+$", ""))
local shared = dir .. "../../shared/"

local chunk = loadfile(shared .. "MyFirstConfig_user.lua")
if chunk then
  local ok, user = pcall(chunk)
  if ok and type(user) == "table" then
    for k, v in pairs(user) do cfg[k] = v end
  end
end

package.path = dir .. "../../DarnToasts/Scripts/?.lua;" .. package.path
local haveToasts, ToastLib = pcall(require, "ToastLib")
if haveToasts then
  ToastLib.registerMenuSchema("MyFirstConfig", 1, [[
    return {
      schemaVersion = 1,
      tab    = "My First Config",
      target = "MyFirstConfig_user",
      defaults = { greetOn = true, greetN = 3 },
      sections = {
        { title = "Greeting", options = {
          { path = "greetOn", label = "Say hello on load", kind = "bool" },
          { path = "greetN",  label = "How many times",    kind = "number",
            min = 1, max = 10, integer = true },   -- bad input rejected on Apply; "(1-10, whole)" auto-shows
        }},
      },
    }
  ]])
else
  print("[MyFirstConfig] DarnToasts not found -- no menu page (mod still works)\n")
end

if cfg.greetOn then
  for i = 1, cfg.greetN do print("[MyFirstConfig] hello " .. i .. "\n") end
end
```

## Try it

1. Drop the folder into `Mods/`, with the empty `enabled.txt`.
2. Launch. `UE4SS.log` shows `[MyFirstConfig] hello 1..3`.
3. In game: **ESC → Mod Options → "My First Config"** — your toggle and number are there.
4. Turn the greeting off (or change the count) → **Apply** → relaunch.
5. `UE4SS.log` now reflects your choice. You've seen the whole loop:
   menu → `MyFirstConfig_user.lua` → `cfg`.

Worth knowing:
- The `min = 1, max = 10, integer = true` on `greetN` is **input validation**: DarnMenu rejects
  out-of-range input on Apply with a clear message, and shows the bounds on the label. Text fields
  can bound length the same way (`maxLen`/`minLen`). Details in `DarnMenu_API.md`.
- Settings apply on the **next launch** — your mod reads the file at startup.
- Until the player saves once, there is no `_user` file and your `defaults` are it.
- If you change the schema later, **bump `schemaVersion`** so it re-registers.

## Recipe — nested lists (a list of entries, each with its own list)

Sometimes a setting isn't one value but a **table of entries**, where each entry has fields *and its own
list*. Classic example — per-NPC skill overrides:

```lua
NPCS = {
  ["Zoe & Grizzbolt"] = { mode = "append", mastered = { "AirBlade", "BeamSlicer", 68 } },
}
```

A **`records`** section exposes exactly that — a dynamic map you add/remove entries in, where a field can
itself be a dynamic list — so your users edit it in-menu instead of hand-writing Lua:

```lua
-- A schema is Lua source, so you can define big lists as locals above the return.
local SKILLS = { "AirBlade", "AquaGun", "BeamSlicer", "HydroSlicer", "IceMissile", --[[ ...40+ ]] }
local NPCS   = { "Anubis", "Chikipi", "Grizzbolt", "Jetragon", "Zoe & Grizzbolt", --[[ ... ]] }
return {
  schemaVersion = 1,
  tab = "Skill Overrides", target = "MyMod_user",
  sections = {
    { title = "NPC skill overrides", custom = {
        type      = "records",
        target    = "NPCS",            -- writes cfg.NPCS = { [name] = {...} }
        keyLabel  = "NPC name",
        addLabel  = "Add NPC",
        empty     = "No NPCs yet -- add one below.",
        keyValues = NPCS,              -- optional: predictive dropdown on the add box
        keyMaxLen = 40,                -- optional key validation (see below)
        fields = {
          { path = "mode", label = "Mode", kind = "enum",
            values = { "append", "merge", "replace" }, default = "append" },
          { path = "mastered", label = "Mastered Skills", kind = "list",
            addLabel = "Add skill",
            values   = SKILLS,         -- a big set -> type-to-search dropdown
            unique   = true },         -- no duplicates
        },
    }},
  },
}
```

What your users get, for free:

- **Add / remove** entries at the top level, and **add / remove** items in each inner list — any number.
- **Collapsible entries** — each shows as `[+] Name`; click to expand to its fields, `[-]` to collapse.
- **Right control per field size** — a **small enum** (`mode`, ≤ 8 values) is a **click-to-cycle** button;
  a **big enum, or a list with `values`,** is a **type-to-search dropdown** (click to open and scroll it,
  or type to filter — only listed values are accepted). Force either with `input = "cycle" | "text"`.
- **Validation** — key: `keyMaxLen`, `keyPattern` (+ `keyPatternMsg`), `keyValidate(name) -> ok, why`.
  List items: `values` membership, `unique`, `min`/`max`, `maxLen`/`minLen`, `validate(v) -> ok, why`.
  Bad input shows a message on the status line and keeps your text so it can be fixed.
- **Numbers vs names** — put `numeric = "auto"` on a list and `68` stores as the number 68 (skill IDs)
  while names stay strings; `numeric = "only"` rejects non-numbers.

**Scale — what's cheap and what isn't.** A big `values` or `keyValues` list is fine: the
type-to-search dropdown shows at most 60 matches at a time (it filters as you type and
scrolls), so handing it every Pal or every skill costs you a slightly larger schema file, not
a wall of widgets. What actually grows a page is the number of **saved entries** — each one is
a header (plus its fields, when expanded) laid out on a single canvas. A page a player might
fill with hundreds of entries is the case to think about; a full predictive `values` list is
not. (If you ever see a records page mis-size on first open, update to DarnMenu 1.4.1+ — it
estimates records height up front.)

Reading it back is the same round trip — the whole `NPCS` table lands in your `_user.lua`:

```lua
local cfg = { NPCS = {} }
local chunk = loadfile(shared .. "MyMod_user.lua")
if chunk then local ok, u = pcall(chunk)
  if ok and type(u) == "table" then for k, v in pairs(u) do cfg[k] = v end end end
-- now: cfg.NPCS["Zoe & Grizzbolt"].mode  and  cfg.NPCS["Zoe & Grizzbolt"].mastered
```

Press **Apply** to save; it lands in the file for your next launch, same as any setting. A `records`
section can sit alongside your normal `options` sections on the same page.

## Where to go next

- **Every control kind** — enum, text, hotkey capture (and which keys it can actually grab),
  dividers, managed lists — with limits and usage: `DarnMenu_API.md`.
- **Live settings + the dots** — apply changes without a relaunch (`Darn.watchConfig`), tell
  players what's live (`live` dots, `applyNote`): the "Live settings" section of `DarnMenu_API.md`.
- **Annotated template** to copy from: `DarnMenu_schema_example.lua`.
- **Schema quick-ref** in code: the header of `schemas.lua`.

---

## Appendix — register without DarnToasts

`registerMenuSchema` just writes two files; you can write them yourself at startup:

```lua
-- 1) your schema file
local f = io.open(shared .. "DarnMenu_schema_MyFirstConfig.lua", "w")
f:write([[return { schemaVersion = 1, tab = "My First Config", target = "MyFirstConfig_user",
  defaults = { greetOn = true, greetN = 3 },
  sections = { { title = "Greeting", options = {
    { path = "greetOn", label = "Say hello on load", kind = "bool" },
    { path = "greetN",  label = "How many times",    kind = "number",
      min = 1, max = 10, integer = true },
  }}}}]])
f:close()

-- 2) merge your name into the index
local list = {}
local ic = loadfile(shared .. "DarnMenu_schema_index.lua")
if ic then local ok, t = pcall(ic); if ok and type(t) == "table" then list = t end end
local seen = false
for _, n in ipairs(list) do if n == "MyFirstConfig" then seen = true end end
if not seen then list[#list + 1] = "MyFirstConfig" end
local fi = io.open(shared .. "DarnMenu_schema_index.lua", "w")
fi:write("return {\n")
for _, n in ipairs(list) do fi:write(string.format("  %q,\n", n)) end
fi:write("}\n")
fi:close()
```

DarnMenu re-reads the index every time the menu opens, so your tab appears at the next menu open.
