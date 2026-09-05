# DarnToasts — tutorial: toasts in 3 lines, a panel in 20

Two recipes: the **default channel** (you write zero config) and a **custom panel** (you own
everything). Full reference: `DarnToasts_API.md`.

---

## Recipe 1 — channel toasts (the 99% case)

Your mod wants to say "saved!" sometimes. That's the default channel — DarnToasts styles it,
positions it, lanes it against other mods' toasts, and gives players one Toasts page (plus a
mute list) that governs all of it. You ship **nothing**:

```lua
-- top of your Scripts/main.lua
local dir = (debug.getinfo(1, "S").source:gsub("^@", ""):gsub("[^/\\]+$", ""))
package.path = dir .. "../../DarnToasts/Scripts/?.lua;" .. package.path
local haveToasts, ToastLib = pcall(require, "ToastLib")   -- degrade if missing
local Toast = haveToasts and ToastLib.new("MyMod")        -- NO opts = channel
  or { notify = function() end, muted = function() return true end }

-- anywhere in your mod:
Toast.notify("saved!")
Toast.notify("warning!", 1.0, 0.6, 0.2)   -- optional accent color
```

That's the whole integration. Don't add position or style opts — passing opts makes it a
custom surface, and then the styling is your job. Players mute you from the Toasts page's
**Muted mods** toggles -- one appears automatically per mod, labeled with the name you passed to `new()` (from its second launch onward).

---

## Recipe 2 — a custom panel (you own the surface)

Your mod wants a persistent HUD panel somewhere specific — like Living Arsenal's weapon panel.
That's a **custom surface**: DarnToasts gives you drawing machinery only; position and style
are your config, on *your* options page.

**Step 1 — construct it where it belongs:**
```lua
local Panel = haveToasts and ToastLib.custom and
  ToastLib.custom("MyMod", { anchor = "right", xOffset = 16, yFrac = 0.5 })
  or { progress = function() end, dismiss = function() end, configure = function() end }
```

**Step 2 — drive it:**
```lua
Panel.progress("status", { text = "Mining  Lv 12", sub = "Next: 340 xp", frac = 0.62 })
-- re-call with the same id to update in place; when done:
Panel.dismiss("status")

-- COLOR is per-call: pass r,g,b to set THIS panel live (recolors an existing one).
-- e.g. a green/red status pill that flips when you toggle something:
local c = enabled and { 0.2, 1.0, 0.2 } or { 1.0, 0.2, 0.2 }
Panel.progress("status", { text = enabled and "ON" or "OFF", r = c[1], g = c[2], b = c[3] })
-- (configure{ color=… } is only the DEFAULT for calls that pass no r,g,b — it
--  won't repaint a panel that already has a color.)
```

**Step 3 — expose its style in YOUR schema** (this is the channel model's deal: your surface,
your page — see the DarnMenu docs for schema basics):
```lua
-- in your DarnMenu schema's options:
{ path = "panelOpacity", label = "Panel opacity %", kind = "number",
  min = 10, max = 100, step = 5, integer = true, live = true },
```

**Step 4 — apply it, at boot and live:**
```lua
Panel.configure({ opacity = tonumber(cfg.panelOpacity) or 100 })   -- boot
Darn.watchConfig("MyMod_user", function(u)
  if type(u.panelOpacity) == "number" then cfg.panelOpacity = u.panelOpacity end
  Panel.configure({ opacity = tonumber(cfg.panelOpacity) or 100 }) -- live = green dot honest
end)
```

`configure()` takes any style key (`scale`, `anchor`, `ttl`, `color`, …) — expose as many or
as few as your surface deserves. The Toasts page will never touch it; muting your panel is
also yours to offer (a bool in your schema → `Panel.configure({ enabled = false })`).

---

## Which recipe am I?

- "I just want to tell the player something occasionally" → **channel**, recipe 1, zero config.
- "I'm drawing a HUD element with a specific home" → **custom**, recipe 2, own your keys.
- Both needs in one mod → both instances, same name (Arsenal does exactly this).
