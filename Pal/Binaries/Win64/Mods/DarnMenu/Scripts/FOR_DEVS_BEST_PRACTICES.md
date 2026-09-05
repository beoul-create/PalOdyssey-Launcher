# Palworld UE4SS modding — things I learned the hard way

**Start with the real documentation, not this file.** Two references exist and are good:

- [pwmodding.wiki](https://pwmodding.wiki/) — the official Palworld Modding Docs, including a
  [UE4SS function reference](https://pwmodding.wiki/docs/developers/ue4ss-modding/lua-mods/ue4ss-functions)
  with Palworld-specific examples.
- [UE4SS's own docs](https://docs.ue4ss.com/) — the authority on the Lua API itself.
- **The game's own files, which beat both.** UE4SS writes a `CXXHeaderDump/` folder next to
  itself, generated from the running game: `Pal.hpp` has every class, function signature and
  property offset, `Pal_enums.hpp` every enum and its values. When a call returns something
  surprising, the answer is usually in there, exactly and today — not in anyone's blog post.
  For game DATA (items, recipes, stations, and the English names of all of them), extract the
  paks: [FModel](https://fmodel.app/) for browsing and JSON export, or
  [repak](https://github.com/trumank/repak) to pull one file out of the 40 GB pak in seconds
  while the game is running. Two notes that cost me a detour: Palworld does NOT use `.locres`
  for localisation — English lives in per-language DataTables under
  `Pal/Content/L10N/<lang>/` — and those text tables store their rows as plain inline strings,
  so they can be read without a full property parser.

What neither covers is the **failure modes**: the calls that do not throw but kill the process,
the ones that silently return something useless, and the layout assumptions that are wrong on
half of people's monitors. That is what this file is. I worked it out by building mods, breaking
things, and reading logs at two in the morning, and it seems worth writing down rather than
leaving in my head.

Treat it as field notes, not gospel. Every item is something I **measured**, usually after it cost
me a crash, a play-test or a shipped bug. Where the official docs confirm something I say so and
link it; where I am only reporting what I observed, I say that too. If something here is wrong or
has changed, I would genuinely like to know — I have already had to correct one section of it
after actually reading the UE4SS docs.

*— A New Darn (maiqthecurious)*

---

## 1. The one that kills servers: `ForEach` callbacks

**A Lua error raised inside a UE4SS `ForEach` callback does not throw. It kills the process.**

UE4SS `__fastfail`s: exit code `0xC0000409` (`STATUS_STACK_BUFFER_OVERRUN`). No crash dump, no
Lua traceback, and your log simply stops mid-line. It looks like an engine or hardware fault, not
a mod fault, which is what makes it so expensive to find.

**A `pcall` around the `ForEach` call does NOT protect you.** The failure happens inside the
native iteration before the error can propagate out.

```lua
-- WRONG. Looks guarded. Is not.
pcall(function()
    arr:ForEach(function(_, elem) doSomething(elem:get()) end)
end)

-- RIGHT. The pcall goes INSIDE the callback body.
arr:ForEach(function(_, elem)
    pcall(function() doSomething(elem:get()) end)
end)
```

I audited my own machine after one of these took down my dedicated server and found **twenty**
more sites with this shape across installed mods — every one of them looking guarded. If you
write one rule from this document into your linter, make it this one.

## 2. `pcall` does not catch native access violations

This underpins several entries below and it is the thing people assume hardest. `pcall` catches
**Lua** errors. If you make the game dereference a bad pointer, the process dies and your `pcall`
never runs.

So "I wrapped it in pcall, it is safe to try" is false for anything that reaches into the engine.

## 3. Probing an unknown API: READ properties, never CALL functions

|                        | Safe? | What happens when you are wrong |
|------------------------|-------|---------------------------------|
| Reading a property     | yes   | returns `nil` (or an empty value — see below) |
| Calling a function     | **no**| signature mismatch dereferences the stack → **AV, process dies** |

I wrote a probe to find Palworld's item-name table. It found the table, then called
`GetItemName` / `FindRow` / `GetRowNames` on it to see which existed. It killed the game **thirty
seconds into every session**, 0.4 ms after logging the find.

Never call a native UFunction to discover whether it exists or what it takes.

**And: UE4SS returns a non-nil EMPTY value for an unknown property.** A probe that prints
`.Foo = ` for every candidate has told you nothing. Distinguish absent from empty — check the
type, check array length, treat an unnamed userdata as absent — or your output is noise. My first
property probe printed fourteen fields as "empty", including names I invented.

## 4. Struct out-param getters can crash

`Slot:GetPosition()`, `Slot:GetSize()`, `widget:GetCachedGeometry()` — anything returning a struct
by out-param writes into memory UE4SS hands it, and on a native widget that can be a hard crash.
`AV reading 0x3fce0003` cost me an afternoon.

Reading a plain property (`w.Visibility`, `w.Slot`) and calling things that return pointers or
primitives (`GetParent()`, `GetFullName()`, `IsValid()`) have been fine for me. Writing through
`SetPosition({X=,Y=})` / `SetSize(...)` on **your own** widgets is fine too.

**Corollary:** you cannot ask the game where its widgets are, so do not build layouts that depend
on knowing. See §8.

## 5. Validate that an "object" is a constructed page before you build on it

At some point an Assignment Board page "built" twenty seconds after load — before the player had
opened one — with a nil widget-tree root, and constructing widgets against it produced nothing at
best and a null deref inside UMG at worst.

**I originally blamed `FindAllOf` for handing back class default objects. That was wrong**, and
the UE4SS docs say so plainly: *"This function cannot be used to find non-instances or default
instances."* Re-reading my own evidence agreed — gating only the `FindAllOf` path did not stop it;
it stopped when I gated every path into my construction code, including the `NotifyOnNewObject`
callback.

So I cannot tell you exactly which source produced the bad object. What I can tell you is the
test that fixed it, which does not care:

```lua
local function usablePage(w)
  if not alive(w) then return false end
  local n = safe(function() return w:GetFullName() end) or ""
  for _, bad in ipairs({ "Default__", "REINST_", "SKEL_", "TRASHCLASS_" }) do
    if n:find(bad, 1, true) then return false end          -- shadows, never usable
  end
  -- the real test: a page the game has actually CONSTRUCTED has a widget tree with a root
  return alive(safe(function() return w.WidgetTree.RootWidget end))
end
```

A page that fails only the second test may just be early — retry it a few times before giving up,
because a genuinely new page can be notified before its tree is populated. A name-shadow will
never become usable, so drop those immediately.

## 6. `NotifyOnNewObject` only fires for newly constructed widgets

This one is documented, and worth reading in the source: the callback fires "whenever an instance
of the supplied class is constructed via `StaticConstructObject_Internal`"
([UE4SS docs](https://docs.ue4ss.com/lua-api/global-functions/notifyonnewobject.html)). Nothing
about objects that already exist — which is exactly the trap.

Right for the ESC menu, which Palworld rebuilds every time you open it. **Wrong** for the
IngameMenu pages (WorkSpace, Monitoring, AssignBoard), which are constructed once and then shown
and hidden. If your mod loads after they exist, the notification never comes and your injection
silently never happens.

Add a slow poll (2 s) that `FindAllOf`s the class and adopts anything it has not seen — gated by
§5's test.

**The tell:** an overlay that logs "registered" and never logs from its build function was never
constructed. It is not mis-placed, mis-sized or clipped. Check that before touching coordinates —
I burned two play-tests hunting for a button that had never existed.

## 7. UMG visibility has FIVE values

```
0 Visible   1 Collapsed   2 Hidden   3 HitTestInvisible   4 SelfHitTestInvisible
```

(That order is Unreal's `ESlateVisibility`, confirmed against Epic's own documentation — not
something I inferred.)

Only **1 and 2** mean "not on screen". 3 and 4 are visible — they only opt out of hit testing —
and a native canvas commonly sits at 4 in normal use.

So `w.Visibility ~= 0` does **not** mean hidden. I shipped that comparison once and a UI element
vanished entirely for every user.

Restoring matters too: if you hide something that was at 4 and restore it as 0, it becomes
hit-testable and starts eating clicks meant for the page behind it.

## 8. Palworld scales its UI by HEIGHT, and its panels are CENTRED

I calibrated this by placing a widget at a known offset and measuring where it landed on a
3440×1440 screen: **1.33 px per unit — exactly 1440/1080.** So canvas units are 1080p pixels, and
the horizontal extent varies with aspect ratio.

Consequences:

- **A pixel offset from a screen corner is only ever right at one resolution.** On an ultrawide,
  a corner-anchored widget ends up nowhere near the game's centred dialog. This bit me four
  separate times in one evening.
- **Anchor to the centre instead.** A slot anchored at 0.5/0.5 with alignment 0.5/0.5 is centred
  everywhere, free, with no viewport query. Offset from there for things that must sit beside a
  game panel.
- At 16:9 the screen half-width is **960 units**. Bound your layouts by that, not by the screen
  you happen to own — I nearly shipped a panel that hung off the edge of a 1080p display.

## 9. A `CanvasPanel` clips its children

Anything outside its bounds is not drawn. Injecting into a small inner canvas made my button
visible at `y = -64` and invisible at `y = 330`, with no anchor setting able to help — the
clipping is the canvas, not the anchor. **Inject into the page root.**

## 10. Widget churn inside a live menu is what crashes UMG mods

Constructing and destroying native widgets while a menu is open is the pressure behind most of
the UI crashes I have had. Practical rules that made mine stable:

- **Build once**, in a build step. Never in a per-second refresh.
- Use a **fixed pool** of rows and hide the unused ones. Page through it if the list is longer.
- To change a layout, **move and resize slots you own** — do not rebuild.
- **Hide, never `RemoveFromParent`** anything belonging to the game. Detaching its widgets wedges
  its menus.

## 11. Toasts draw on the HUD, and the HUD is under an open menu

Any message you fire while a full-screen menu is up is invisible **by construction**. No amount
of repositioning fixes it. If the message is about something happening *in* a menu, it has to be
a widget inside that menu.

I fired the same message into a covered HUD three times in one evening before the penny dropped.

## 12. Every mod gets its own `lua_State`

Two mods cannot share Lua state, tables or functions. `require` reaches files, not other mods'
runtime.

This makes the "shared library mod" pattern fragile: your consumer and the library run separate
copies, and a version mismatch is a nil call that takes the whole mod down. I ended up
**vendoring** my widget kit into each consumer — every mod ships and runs the copy it was tested
with. Bigger downloads, no mismatch class at all.

If you do keep a shared-library mod, assert the API you need at load and fail loudly with a
message naming the version you expected.

## 13. Player data: write atomically, or lose it

A truncating `io.open(path, "wb")` that is interrupted leaves an empty file. That wiped weapon
progression for my users once and emptied loot-filter blacklists another time.

```
write tmp -> move current aside as .bak -> rename tmp into place
```

Read with a fallback to `.bak`. Note the contract: **`.bak` is one generation OLD**, not a mirror
— it holds the state before the most recent save. Recovery returns you to the previous good
state, which is the promise; expecting the newest write is expecting a mirror.

Keep it in `Mods/shared/`, not inside your mod folder — mod updates replace the folder.

## 14. Two different crash dump locations

- The game writes to `%LOCALAPPDATA%\Pal\Saved\Crashes\`
- **UE4SS writes its own** to `Mods\NativeMods\UE4SS\crash_<stamp>.dmp`

Looking in only the first one and concluding "no crash dump" cost me a diagnosis. And remember
§1: a fastfail writes **neither**.

`UE4SS.log` truncates on relaunch. Archive it before restarting or the evidence is gone — I
automated this and it has paid for itself repeatedly.

## 15. Things I found by measuring, that you cannot derive

- **`PalUIConvertItemModel:GetOuter()` is not the station.** The game's model is owned by the
  craft-screen widget; a model **you** construct has the station as its outer. Same call, different
  answers, depending on who built the object. To find the station a player is actually using, ask
  the world what just started producing.
- **Item ids are not display names, and no rule connects them.** `CopperIngot` is "Ingot".
  `MachineParts` is "Nail". `Plastic` is "Plasteel". Keep ids on the matching path and names for
  display only, so a rename can never break a lookup.
- **The bench type is in the object path**, not on a property:
  `...PersistentLevel.BP_BuildObject_CookingStove_C_2147436403.PalMapObjectConvertItemModel_...`
  The model class is identical for every converter, which is why matching on it distinguishes
  nothing.
- **The item text table is `/Game/Pal/DataTable/Text/DT_ItemNameText`** and it is a
  `CompositeDataTable`. I have not yet found a safe way to read rows from one in Lua — if you
  have, tell me.

## 16. Do not take the player's keys

I shipped a mod holding F5–F9 without asking, including an **undocumented F6 that wiped all the
user's saved data on one keypress**. F-keys are contested space; every mod wants them, and a
silent grab collides with someone.

Bind nothing by default. Offer keys in your settings and let the player choose. If you must have
a default, gate it on your own screen being open so it cannot fire during normal play.

And document every key somewhere a player will actually look. Mine were only in a boot log line,
which is how the destructive one went unnoticed for a day.

## 17. Release discipline

- **The store is the source of truth for what shipped**, not your notes. I called a version
  "pending upload" for twelve hours after it had gone live, because my ledger said so.
- **The moment a version is uploaded, freeze it.** The next change bumps. I added two features
  under an already-published version number, and "1.6.4" then meant two different builds
  depending on where you looked.
- **Check what is actually in the staged package**, not what your changelog claims. Grep the
  built artifact for the feature you think you are shipping.
- Steam can revert files you hand-place in a subscribed Workshop content directory. Re-stage
  immediately before publishing.

---

## 18. TOCTOU: the disease behind most native crashes (added after a three-day hunt, 2026-07-29→31)

Ten crashes across a dedicated server and two clients turned out to be ONE pattern in different
clothes: **check an object's validity at one moment, use it at a later moment, and the engine
changes it in between.** `IsValid()` is a snapshot that is stale before your next line runs, and
there is no transactional access from Lua. Concrete rules, each paid for with a real crash:

- **`IsValid()` does not prove it is the SAME object.** UE recycles addresses; a recycled wrapper
  passes `alive()` under a different identity. If you cache a wrapper across ticks, freeze its
  `GetFullName()` when you accept it and compare before every use. Evict on mismatch.
- **A name check cannot detect teardown-in-progress.** Same object, name intact, internals being
  freed. The only defense is FRESHNESS: only touch objects the engine itself handed you recently
  (a hook parameter, a FindAllOf from this tick). We gate sends/walks on "engine-confirmed within
  N seconds" and it works.
- **Every crash our instrumentation ever attributed was inside a TIMER poll. Zero were inside
  hook callbacks.** An object delivered BY a hook was vouched for at that instant; an object a
  poll DISCOVERED is stale by construction. Prefer event-driven acquisition: hooks extract plain
  data immediately, a slow drain does the work.
- **Replacing a method call with a property read changes LIFETIME semantics.** A by-value struct
  return is a Lua-owned copy; a struct property is a live reference into the object. Copy the
  fields to plain Lua values in the same statement, retain nothing native — heavy retained
  struct-wrapper traffic also stressed UE4SS itself in our testing.
- **`FindAllOf` + `valid()` + a native method call is the canonical trap.** The list includes
  lingering half-dead objects; `valid()` passes them; the method walks freed internals. Walk
  plain properties instead, and SANITY-BOUND any count/index you read: our crashes were faults at
  `null + 65535*2` and `null + 62208*2` — garbage element counts from dead containers. If a
  container claims 62,208 slots, it is not a container any more.
- **Diagnostic craft:** a fault address that factors as `index * stride` means an array read off
  a null base — go find who indexes an array of that stride. And compare crash callstack OFFSETS
  (including the TOP frames) before believing any log-tail attribution: two of our "obvious"
  suspects were exonerated by byte-identical stacks appearing with the suspect disabled.

## 19. Do no native work inside loading/streaming frames

World-partition streaming (fast travel, map load) is when objects are half-built and half-dead at
once. A hook that fires in that window (`WaitLoadingWorldPartition`, load-map events) must not
read game objects — set a flag, `ExecuteWithDelay` the real work a few hundred ms, and do it
after the world settles. Two client CTDs came from one graphics mod reading its hook's Context
mid-stream; the deferred version lost nothing but the crash.

## The general lesson

Almost everything above follows from one habit: **when something breaks, get evidence before
forming a theory.** The log, the exit code, the object path, the actual pixel where the thing
landed. Every wrong turn I made came from reasoning about what the engine probably does; every
fix came from making it tell me.

Corrections and additions are welcome — I would much rather this file be right than be mine.
