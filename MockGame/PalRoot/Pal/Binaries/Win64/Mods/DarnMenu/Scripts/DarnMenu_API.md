# DarnMenu — schema API reference

Everything a mod can put in a DarnMenu options page. For a hands-on start, read
`DarnMenu_TUTORIAL.md` first; for a copy-paste template, see `DarnMenu_schema_example.lua`.

A schema is a plain Lua table you register once at startup. DarnMenu renders it into a page under
**ESC → Mod Options**, saves the player's edits to a file, and your mod reads that file.

---

## Registering

Write two files into `Mods/shared/` at your mod's startup:
- `DarnMenu_schema_<Name>.lua` → `return { ...your schema... }`
- `DarnMenu_schema_index.lua` → `return { "<Name>", ... }` (add your name to the list)

If **DarnToasts** is installed, one idempotent, version-gated call does both. Look it up
defensively — `Info.json` `Dependencies` is metadata only (auto-install comes from your Workshop
page's **Required Items**, which you should also set), and a user can always unsubscribe a dep,
so your mod must survive its absence:
```lua
local dir = (debug.getinfo(1, "S").source:gsub("^@", ""):gsub("[^/\\]+$", ""))
package.path = dir .. "../../DarnToasts/Scripts/?.lua;" .. package.path
local haveToasts, ToastLib = pcall(require, "ToastLib")
if haveToasts then
  ToastLib.registerMenuSchema("<Name>", <schemaVersion>, "<the return{} source text>")
end
```
The index is re-read every time the menu opens, so a newly registered page appears without a restart.
(No DarnToasts? Write the two files with plain `io` — worked example in `DarnMenu_TUTORIAL.md`'s
appendix. No DarnMenu at all? The files sit unread — harmless; ship your defaults.)

---

## Schema table — top-level fields

| field | req | type | meaning |
|---|---|---|---|
| `schemaVersion` | ✓ | number | Bump when you change the schema so it re-registers (via the helper). |
| `tab` | ✓ | string | Your entry in the left-hand mod list. |
| `target` | ✓ | string | File the values are saved to: `Mods/shared/<target>.lua`. **Must end in `_user`** and be a **plain file name** — letters, digits, `_`, `-`, `.` only, no `/`, no `\`, no `..` (sandbox: a schema may only write `*_user` files inside `shared/`; `ToastLib_config` is the one allowlisted exception). A name that fails either rule is rejected at load with a line in UE4SS.log. |
| `order` | | number | Sort key among mods (default 100; lower = higher up). |
| `note` | | string | A line shown at the top of your page. Use it to say what applies live vs after a relaunch. |
| `applyNote` | | string | Fallback Apply message. When the saved options all carry `live` flags, DarnMenu **computes** the message from exactly what was saved ("applied live" / "after relaunch" / counts for a mixed save — per-option notes can't compose, one Apply saves many options). `applyNote` shows only when some saved option has no flag; the generic line is last. |
| `live` | | bool | Page-wide default for the **live/relaunch dots**: `true` = green dot ("applies now"), `false` = amber dot ("needs relaunch") on every option; individual options override with their own `live`. Omit both = no dots. A legend appears by the footer whenever any page declares them. |
| `defaults` | | table | `{ key = value }` baseline, used for a control until the player changes it. **These keys are the keys your mod reads.** |
| `sections` | ✓ | array | The page body (see below). |

## Section

```lua
sections = {
  { title = "General", options = { --[[ controls ]] } },  -- a titled group of controls
  { title = "List",    custom  = { --[[ widget ]] } },    -- OR one custom widget (see "custom")
}
```

---

## Options (controls)

Each control is one entry in a section's `options`. **Value controls** need a `path` (the key written
to your file and read by your mod). **Layout entries** have no `path`.

### Common fields
| field | applies to | meaning |
|---|---|---|
| `path` | value controls | The config key. Written to `<target>.lua` and read as `cfg.<path>`. Name it exactly like the key your mod uses. |
| `label` | value controls | The control's caption. |
| `kind` | value controls | One of the types below. |
| `help` | any | Small grey helper text shown by the control. |
| `note` | value controls | Appended to the label in parentheses. |
| `dependsOn` | value controls | Name of another (bool) option's `path`; this control greys out while that key is `false`. |
| `live` | value controls | Overrides the schema's `live` default for this option: `true` = green "applies now" dot, `false` = amber "needs relaunch" dot. Only honest if your mod actually hot-applies the key (see "Live settings"). |

### Value types (`kind`)

**`bool`** — an ON/OFF toggle. Stored as a boolean (`true`/`false`).
```lua
{ path = "enabled", label = "Enable mod", kind = "bool" }
```

**`enum`** — a button that cycles a fixed list. Needs `values`. Entries are plain values, or
`{ value = ..., label = "display text" }` pairs when the stored value shouldn't be what the
player reads — the **value** is what's saved and what your mod gets; the **label** is display-only.
```lua
{ path = "mode", label = "Mode", kind = "enum", values = { "gentle", "balanced", "aggressive" } }
{ path = "mode", label = "Mode", kind = "enum", values = {
    { value = "gentle",     label = "Gentle (-50%)" },
    { value = "balanced",   label = "Balanced" },
    { value = "aggressive", label = "Aggressive (+50%)" },
} }
```

**`number`** — a text field parsed as a number; input that doesn't parse is rejected with a
message on Apply. Optional validation fields (any subset):
- `min` / `max` — inclusive bounds; out-of-range input is **rejected with a message, never
  silently clamped** (the value stays in the box for the player to fix).
- `integer = true` — whole numbers only.
- `step = N` — renders **− / + buttons** around the box; each click moves the value by N,
  clamped to `min`/`max` (typing stays possible — steps start from whatever is in the box).

Declared bounds are shown on the label automatically (e.g. `Strength (0-2)`) unless you set your
own `note`.
```lua
{ path = "strength", label = "Strength", kind = "number", min = 0, max = 2, step = 0.1 }
{ path = "count",    label = "Count",    kind = "number", min = 1, max = 10, integer = true, step = 1 }
```

**`text`** — a free text field. Stored as a string, as typed. Optional validation:
- `maxLen` / `minLen` — length bounds, rejected with a message when violated. **Length is in
  BYTES** (Lua `#`), so non-ASCII characters count as more than one — leave headroom if players
  may type accented or non-Latin text.
```lua
{ path = "label", label = "Custom label", kind = "text", maxLen = 32 }
```

**Custom validation (`number` and `text`)** — when the built-in fields aren't enough, attach your
own check; it runs after the built-ins pass. Return `true` to accept, or `false, "why"` to reject
(the message reaches the player's status line). Schemas are Lua, so functions ride along fine —
including through `registerMenuSchema`'s source text.
```lua
{ path = "port", label = "Port", kind = "number", integer = true,
  validate = function(v) return v >= 1024 and v <= 65535, "must be 1024-65535" end }
```

**`keycapture`** — a button you click, then press a key to bind. Stored as the key **name string**
(e.g. `"F8"`). See the dedicated section below for its real limits.
```lua
{ path = "toggleKey", label = "Toggle hotkey", kind = "keycapture" }
```

### Layout entries (no `path`, no value)
```lua
options = {
  { subtitle = "Advanced (careful):" },   -- a sub-heading row (optional `help`)
  { divider = true },                     -- a horizontal separator
}
```

---

## `keycapture` in depth — capabilities & limits

**What the player sees:** a button showing the current key. Click it → it reads "Press a key…" →
they press one key → the name is staged → **Apply** saves it. Clicking anything else (another tab,
Apply, a toggle) **cancels** the capture — no accidental keystroke grabs.

**What's stored:** the UE4SS key **name** as a string, e.g. `"F8"`, `"K"`, `"NUM_FIVE"`. It is always
a valid `Key.<NAME>`, so your mod can resolve it directly.

**How your mod uses it** — register your own bind from the stored name:
```lua
local keyName = cfg.toggleKey                 -- e.g. "F8", read from your _user file
local k = Key[keyName]
if k then RegisterKeyBind(k, function() doTheThing() end) end
```

**THE LIMIT (important):** UE4SS has **no any-key listener** and keybinds **cannot be unregistered**,
so DarnMenu pre-binds a fixed battery of keys once and only listens while a capture is armed. That
means **only these keys are capturable:**
- **F1–F12**
- **A–Z**
- **0–9** (top row) and **numpad 0–9**
- numpad **`- + * / .`**
- **Ins, Del, Home, End, Page Up, Page Down**

**Not capturable:** modifier combos (Ctrl/Alt/Shift+key), arrow keys, Space, Enter, Tab, Esc,
Backspace, and symbol/punctuation keys (`; ' [ ] \` etc.). If a player presses one of those while
capturing, nothing is staged. Design your defaults around the list above.

---

## `custom` widgets

A section can hold one custom widget instead of `options`. Currently:

**`listfile`** — a managed add/remove text list. DarnMenu gives the player an editor; the entries
live in a plain `.txt` in `Mods/shared/`, **one per line** — your mod reads that file itself (it is
NOT part of `target`).
```lua
{ title = "Watch list", custom = {
    type  = "listfile",
    file  = "MyMod_watchlist.txt",     -- Mods/shared/MyMod_watchlist.txt
    empty = "No entries yet — add one below.",
}}
```
Read it with `for line in io.lines(shared .. "MyMod_watchlist.txt") do ... end`.

> **File names are sandboxed.** `file` here — and the `file` of an `actionpanel`, and the page's
> `target` — must be a **plain file name** with the right extension: letters, digits, `_`, `-`, `.`
> only. No `/`, no `\`, no `..`. Everything DarnMenu reads or writes on a schema's behalf lives
> directly in `Mods/shared/`, and a name that could climb out of it is refused. This is enforced,
> not advisory — if your section silently does nothing, check UE4SS.log for a rejection line.

**`records`** — a dynamic **map of named entries**, each with fields, where a field can itself be a
dynamic **list** (a list inside a list). Unlike `listfile`, it IS part of `target` — the whole table
is written to a key in your `_user.lua`. Step-by-step walkthrough: the "nested lists" recipe in
`DarnMenu_TUTORIAL.md`.
```lua
{ title = "NPC skill overrides", custom = {
    type      = "records",
    target    = "NPCS",            -- writes cfg.NPCS = { [name] = {...} }
    keyLabel  = "NPC name",        -- label on the add box
    addLabel  = "Add NPC",         -- add-button text
    empty     = "No NPCs yet.",    -- shown when the map is empty
    keyValues = { ... },           -- OPTIONAL: predictive suggestions for the add box
    keyMaxLen = 40,                -- OPTIONAL key checks: keyMaxLen, keyPattern (+keyPatternMsg),
                                   --   keyValidate = function(name) return ok, "why" end
    fields = {
      -- an enum field: <=8 values renders as a click-to-cycle button, more as a
      -- type-to-search dropdown. Force with input = "cycle" | "text".
      { path = "mode", label = "Mode", kind = "enum",
        values = { "append", "merge", "replace" }, default = "append" },
      -- a dynamic list field. With `values` it becomes a type-to-search dropdown
      -- (click to open + scroll, or type to filter; only listed values accepted).
      { path = "mastered", label = "Mastered Skills", kind = "list", addLabel = "Add skill",
        values = { ... },          -- OPTIONAL allowed set (dropdown + membership check)
        numeric = "auto",          -- "auto": digits store as numbers; "only": reject non-numbers
        unique = true,             -- no duplicates
        -- also: min / max (numbers), maxLen / minLen (strings), validate = function(v) return ok,"why" end
      },
    },
}}
```
Entries are collapsible (`[+] Name` / `[-] Name`). On a **list field**, picking a value from the
dropdown adds it straight to the list and clears the box (remove a wrong one with its `X`) — so nothing
is left parked in the input. Bad input is rejected on add/apply with a message on the status line; your
typed text stays so it can be fixed. Read it back as a normal table:
`cfg.NPCS["Zoe & Grizzbolt"].mode` / `.mastered`.

**Scale.** `values` / `keyValues` may be as large as you like — pass the whole Pal or skill list.
The type-to-search dropdown renders at most **60 matches** at once (it filters as you type and
scrolls), so a big allowed-set does **not** produce a big widget count; it only enlarges the schema
file. The cost that *does* scale is the number of **saved entries**: each is a header (plus its
fields when expanded) on one canvas, so a page a player could fill with hundreds of entries is the
one to design around — cap it, or split across sections/pages. Records-page height is estimated
before render (DarnMenu 1.4.1+), so a tall page sizes correctly on the first frame.

---

## How the saved file looks / how you read it

DarnMenu writes **only changed keys**, merged into the existing file, as a plain table:
```lua
-- Mods/shared/MyMod_user.lua
return { enabled = false, strength = 1.5, mode = "aggressive", toggleKey = "F9" }
```
Value types round-trip as string / number / boolean (and nested tables). Your mod loads this over its
defaults at startup:
```lua
local cfg = { --[[ your defaults, mirroring schema.defaults ]] }
local chunk = loadfile(shared .. "MyMod_user.lua")
if chunk then local ok, u = pcall(chunk); if ok and type(u)=="table" then
  for k,v in pairs(u) do cfg[k] = v end end end
```
(Darn-family mods do those two lines as one type-guarded call: `Darn.overlay(cfg, "MyMod_user", log)`.)

---

## What every page gets for free

- **Apply** — coerces + validates every edited control; problems land on the status line, good
  values are merged into `<target>.lua`. The success message is **computed from the `live`
  flags of exactly what was saved** (see `applyNote`).
- **Restore Defaults** — stages the schema's `defaults` for the selected mod (player still
  confirms with Apply). You don't build this; it's platform furniture.
- A **status line** for save results, validation messages, and key-capture prompts — cleared
  automatically when the player switches to another mod's page.
- The **live/relaunch dot legend** (bottom-right) whenever any page declares `live` flags.
- **Controller support** — the left stick / D-pad moves focus and the page auto-scrolls to keep the
  focused control centered, so your dropdowns, nested lists, and off-screen controls are all reachable
  on a gamepad. The mod list scrolls too. You get this for free; there's nothing to declare.
- **Lifecycle hygiene** — pages and panels are born hidden (no construction flash), stale
  menu instances are swept, half-built panels clean up after themselves, and the page closes
  itself if the game's menu moves on without telling us.

## Feature-gating: the capability marker

DarnMenu writes `Mods/shared/DarnMenu_caps.lua` at startup. A dependency listed in `Info.json`
says nothing about *which* DarnMenu the user has — older versions silently ignore newer schema
fields (safe, but your fancy option renders as its plain fallback). When it matters, check:
```lua
local caps = {}
local c = loadfile(shared .. "DarnMenu_caps.lua")
if c then local ok, t = pcall(c); if ok and type(t) == "table" then caps = t end end
-- caps.rev >= 2 means: validation, enumLabels, stepper, customValidate,
--                      restoreDefaults, applyNote, liveDots
if caps.stepper then --[[ safe to rely on step = N ]] end
```
Missing file = DarnMenu 1.0.x or not installed.

## Live settings — apply without relaunch

By default settings apply at your mod's next startup read. To react the moment the player hits
Apply, poll the target file for changes — vendored `darn.lua` ships a helper (or copy its ~25
lines from `shared-src`):
```lua
Darn.watchConfig("MyMod_user", function(user)
  for k, v in pairs(user) do cfg[k] = v end   -- or your type-guarded overlay
  applyRuntimeChanges(cfg)                    -- your code: re-read what matters live
end)                                          -- optional 3rd arg: poll ms (default 2000)
```
It text-compares against a startup baseline (works with any DarnMenu version and hand edits) and
never fires for the state your boot already read.

**How to tell whether a key can go live** — trace where your mod READS it:

- **Read at use time** (inside a tick, a hook body, a draw call, a notify — `cfg.X` consulted
  every time) → **live-able**: overlay the table in place and the next read sees the new value.
  Mark it `live = true`.
- **Consumed once at boot** (`RegisterKeyBind`, `RegisterHook`, one-time widget construction,
  a value baked into a local/upvalue at load) → **relaunch-only**: UE4SS can't unregister binds
  or hooks, and baked locals never re-read. Mark it `live = false`.
- **Re-keys persistent state** (storage scoping, save-file layout, IDs) → **relaunch-only even
  if it's read at use time** — hot-switching forks or corrupts state (e.g. Living Arsenal's
  `progressScope` re-keys the weapon store; it stays amber on purpose).
- **Borderline** (a cached derivation of cfg): make it live only if you also re-derive the
  cache in your watchConfig callback — that's what DarnToasts' `refreshStyle()` does.

When in doubt, mark it `live = false` — a relaunch that wasn't needed costs a minute; a green
dot that lies costs the player's trust in every other dot.

## Gotchas
- **Dependencies: `Info.json` alone installs nothing.** Auto-install comes from your Workshop
  page's **Required Items** — set those (and keep `Info.json` `Dependencies` as metadata). Either
  way, code so a missing dep only costs its feature — never the whole mod.
- **Settings apply on the next launch** by default — your mod reads the file at startup. Opt into
  live application with `Darn.watchConfig` (see "Live settings" above).
- **The `_user` file doesn't exist until the player saves once** — until then your `defaults` are it.
- **Validation guards the MENU, not the file.** `min`/`max`/`integer`/`maxLen`/`minLen` reject bad
  input on Apply — but a hand-edited `_user.lua` bypasses them, so your mod should still sanity-check
  what it loads.
- **Bump `schemaVersion`** whenever you change the schema, or the helper won't re-register it.
- **`target` must end in `_user`** (sandbox) — you cannot write arbitrary shared files from a schema.
- **`keycapture` is limited to the curated key set above** — don't promise players Ctrl+combos or arrows.
