# DarnToasts — API reference

Toast + panel drawing for UE4SS mods, with a hard authority boundary (the **channel model**,
2.0). Hands-on start: `DarnToasts_TUTORIAL.md`. This file is the complete reference.

## The channel model — who manages what

| | **Default channel** | **Custom surface** |
|---|---|---|
| Constructor | `ToastLib.new("MyMod")` — *no opts* | `ToastLib.custom("MyMod", { ...opts })` |
| Style & position | DarnToasts (the Toasts page) | **You** (`configure()`, your own page) |
| Stacking / lanes | DarnToasts (auto-lanes) | You (your position, your problem) |
| Mute | Toasts page's **Muted mods** toggles (auto-generated per mod) | Toasts page too (2.4.0) — the user's mute reaches every surface; you may also gate with `configure{ enabled = false }` |
| Live updates | Automatic (~2s after Toasts-page Apply) | You call `configure()` when *your* config changes |
| Config your mod ships | **None** | Your keys, on your page |

A write is either in the channel (fully DarnToasts') or out of it (fully yours). There is no
precedence chain and no partial opt-out: passing *any* opts to `new()` promotes the instance to
a custom surface (with a deprecation log — 1.x callers keep working, minus global styling).

## Constructors

```lua
local haveToasts, ToastLib = pcall(require, "ToastLib")   -- deps don't auto-install; degrade
local Toast = haveToasts and ToastLib.new("MyMod") or nil -- (or use Darn.toastlib's stub)

local Panel = haveToasts and ToastLib.custom("MyMod", {
  anchor = "right", xOffset = 16, yFrac = 0.5,   -- position: yours
  opacity = 100, scale = 1.25,                   -- style: yours (any key from the table below)
})
```
One mod may hold **both** (Living Arsenal: channel level-up toasts + a custom weapon panel).
`ToastLib.custom` is nil on pre-2.0 DarnToasts — guard with `ToastLib.custom and ... or Toast`.

## Instance API (both kinds)

| call | behavior |
|---|---|
| `T.notify(msg [, r, g, b])` | transient toast; optional 0–1 accent color |
| `T.progress(id, { text=, sub=, frac=, r=,g=,b= })` | persistent progress panel; re-call the same `id` to update in place (max 3 stickies; oldest auto-dismissed). **`r,g,b` set THIS panel's color live** — pass them every call to recolor an existing panel (e.g. a green/red ON-OFF pill). Omit them and the panel keeps its current color (falling back to the `color` style default only on first draw). |
| `T.dismiss(id)` | ravel a progress panel shut |
| `T.muted()` | channel: Toasts-page mute (global kill, per-mod entry, or the Muted-mods list). Custom: the Toasts-page mute as well (2.4.0, re-read ~10s), plus what you set (`configure{ enabled = false }`) |
| `T.configure(tbl)` | **custom only** — merge style/position keys, restyle immediately. Channel: logged no-op (the Toasts page owns channel style) |
| `ToastLib.registerMenuSchema(name, version, sourceText)` | DarnMenu glue (see the DarnMenu docs); idempotent, version-gated |

## Style keys (`custom()` opts and `configure()` — same keys the Toasts page manages for the channel)

| key | default | meaning |
|---|---|---|
| `enabled` | `true` | `false` = this instance draws nothing |
| `anchor` | `"center"` | `"center" \| "left" \| "right"` |
| `xOffset` | `0` | px from the anchor (margin for left/right, nudge for center) |
| `yFrac` | `0.68` | vertical spot, 0 top … 1 bottom |
| `yOffset` | `0` | px added after `yFrac` (the custom surface's lane) |
| `scale` | `1.25` | text scale; the panel sizes with it |
| `ttl` | `10` | toast lifetime in 500ms ticks (10 ≈ 5s); stickies ignore it |
| `color` | soft blue | **default** accent `{r, g, b}`, used only when a `notify()`/`progress()` call passes no `r,g,b`. Changing it (config or `configure()`) affects FUTURE uncolored calls — it does NOT repaint toasts/panels that already have a color. To recolor a live panel, pass `r,g,b` on the `progress()` call itself. |
| `opacity` | `100` | 10–100, multiplies every layer |
| `animMs` | `280` | entry/exit animation (0 = instant) |
| `unravel` | `"left"` | `"left" \| "right"` wipe-open edge; `false` = classic slide+fade |
| `exit` | `"wipe"` | `"wipe" \| "fade"` |
| `shadow` | `true` | soft drop shadow |
| `lifebar` | `true` | draining time bar on toasts |
| `stack` | `4` | max simultaneous toasts for this instance |
| `stackGap` | `8` | px between stacked toasts |

## Channel plumbing (what the library maintains for you)

- **Config**: `Mods/shared/ToastLib_config.lua` — written by the Toasts page, watched by every
  channel instance (~10s). Custom surfaces read exactly one thing from it: their mute key (2.4.0).
- **Mute toggles**: generated into the Toasts page from the consumer registry (one bool per
  known mod — channel AND custom since 2.4.0; stored as mute_<Name> keys in the config). A new
  mod's toggle appears from its SECOND launch (the registry entry must exist first).
- **Consumer registry**: `Mods/shared/DarnToasts_consumers.lua` — `{ Name = "channel"|"custom"|"both" }`,
  written at instance creation. Feeds the auto-lanes; safe to delete (rebuilds next launch).
- **Auto-lanes**: channel consumers get a stable vertical slot (sorted registry order × 110px) so
  two mods toasting at once never overlap. `mods.<Name>.yOffset` in the config still overrides a
  lane — that's a Toasts-side channel override, not mod config.

## Limits & gotchas

- **One instance per Lua state**: UE4SS isolates mods, so each consumer runs its own ToastLib
  copy + draw hook. Cross-mod behavior happens through the shared files above, never in memory.
- **A new consumer's auto-lane appears at its NEXT launch** (the registry entry has to exist
  before lanes are computed). First-launch collisions self-heal on relaunch.
- **HUD text cannot be clipped** — the unravel effect works by substring; very long single-word
  messages may overshoot the pill slightly.
- **Channel instances ignore `configure()`** by design — if you need per-mod style, you want a
  custom surface (and the config for it lives on *your* page).
- **Legacy 1.x positioning opts on `new()`** promote to custom with a deprecation log: same
  position as before, but global style/mute no longer apply — ship your own keys (see the
  tutorial's panel walkthrough) or drop the opts to join the channel.
