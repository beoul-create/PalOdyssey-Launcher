-- ============================================================================
--  DarnMenu -- in-game "Mod Options" for any mod that registers a schema.
--  Injects a native-looking button into the ESC menu (under Link Discord, with
--  a small gap); it opens a MASTER-DETAIL options page: registered mods listed
--  down the LEFT, the selected mod's controls on the RIGHT. Edits are written
--  to Mods/shared/<target>.lua files (the update-surviving config pattern);
--  most changes apply on the next relaunch.
--
--  Clean-room implementation of the ESC-menu injection technique (recipe in
--  the project vault); no third-party code. Pure Lua, no assets.
--
--  Other mods add their own page by writing a schema file to
--  Mods/shared/DarnMenu_schema_<Name>.lua and merging <Name> into
--  Mods/shared/DarnMenu_schema_index.lua (ToastLib.registerMenuSchema does both
--  for you). See schemas.lua for the schema format and
--  DarnMenu_schema_example.lua for a ready-to-copy example.
-- ============================================================================

-- ui.lua lives in the DarnUI foundation mod (the shared UMG widget kit). Load it
-- through Darn.requireUI(), which owns the package.path dance. This was hand-rolled
-- here, which is exactly what darn.lua tells consumers never to do -- two ways to
-- reach DarnUI inside one family is how the two drift apart. Darn is required FIRST
-- (it has no dependency of its own) so the helper exists before we need it.
local Darn = require("darn")
local UI = Darn.requireUI()   -- DarnUI is a hard dependency (auto-installed)
local alive = function(o) return (UI and UI.alive and UI.alive(o)) or false end
local Schemas = require("schemas")
local Writers = require("writers")
local log  = Darn.logger("[DarnMenu]")
local safe = Darn.safe
local DIR = Darn.dir
local SHARED = DIR .. "../../shared/"
local VERSION = Darn.version()

local function safe_loadfile(path)
  if not path or type(path) ~= "string" then return nil end
  local f = io.open(path, "rb")
  if not f then return nil end
  local content = f:read("*a")
  f:close()
  if not content or content == "" then return nil end
  local chunk, err = load(content, "@" .. path, "t")
  return chunk, err
end

-- MAP-BOUNDARY STAND-DOWN (see the block of the same name in DarnUI's ui.lua).
-- Every timer below skips its body while the engine is swapping maps, because a
-- tick that lands mid-teardown touches half-dead widgets and IsValid() does not
-- catch that. Called through a shim, never directly: a user can have DarnMenu
-- 1.6.2 sitting on DarnUI 1.2.0, where these functions do not exist yet, and a
-- nil call in a poll would break the whole menu for them.
local function worldGone() return UI.worldIsGone ~= nil and UI.worldIsGone() == true end
local function worldBack() if UI.worldBack then UI.worldBack() end end

-- Capability marker: lets other mods feature-gate against the INSTALLED
-- DarnMenu (a dep listed in Info.json says nothing about which version the
-- user actually has). Read it with loadfile(shared .. "DarnMenu_caps.lua").
-- rev history: 2 = validation/enumLabels/stepper/customValidate/restoreDefaults.
pcall(function()
  local f = io.open(SHARED .. "DarnMenu_caps.lua", "w")
  if f then
    f:write("-- written by DarnMenu at startup; read-only capability marker\n")
    f:write(string.format(
      "return { rev = 2, version = %q, validation = true, enumLabels = true, "
      .. "stepper = true, customValidate = true, restoreDefaults = true, "
      .. "applyNote = true, liveDots = true }\n", tostring(VERSION)))
    f:close()
  end
end)

-- Backspace-close guard: ON, in the "90% state" (Mikey's call 2026-07-25 -- he judged
-- the trade worth it). Backspace while typing deletes instead of destroying the ESC
-- menu; the cost is that ESC's exit is degraded for that menu instance ONCE a field has
-- been focused (tab-switch + ESC and the menu's own buttons still close it; a relaunch
-- always clears it). Set to false to go back to stock behaviour. See openPage.
local BACKSPACE_GUARD = true

-- BACKGROUND PRE-BUILD: OFF (2026-07-29). The switch schedulePrebuild's own comment block has
-- described since 2026-07-27 finally exists -- it was documented but never wired, so the pre-build
-- had been running unconditionally the whole time.
--
-- WHY OFF. Seven incidents are now anchored to the line this feature logs. Two of them landed in a
-- single 8-minute session on 2026-07-29: a CTD (`AV writing 0x1c`) **50ms** after
-- "page shell pre-built (idle)", and a hard freeze **4s** after it. It builds ~100 widgets on EVERY
-- ESC menu open, whether or not Mod Options is ever clicked, and the vault's ONE proven lever
-- against this crash family is INJECT FEWER WIDGETS. Delaying it (400ms -> 1200ms on 2026-07-25)
-- reduced how often it fired but never removed the cost.
--
-- WHAT IS LOST: only warm-up. `openPage`/`selectMod` call `ensurePanel`, which is idempotent and
-- builds on demand -- so the first click into Mod Options is slower and nothing else changes.
-- Set true to restore pre-warming. See [[palworld-crash-ledger]] 2026-07-29.
local PREBUILD = false


local MENU_CLASS = "/Game/Pal/Blueprint/UI/UserInterface/ESCMenu/WBP_MenuESC.WBP_MenuESC_C"
local CLICK_EVENT = UI.BUTTON_CLASS
  .. ":BndEvt__WBP_MenuESC_Button_WBP_PalInvisibleButton_K2Node_ComponentBoundEvent_0_CommonButtonBaseClicked__DelegateSignature"
local UNHOVER_EVENT = UI.BUTTON_CLASS
  .. ":BndEvt__WBP_MenuESC_Button_WBP_PalInvisibleButton_K2Node_ComponentBoundEvent_2_CommonButtonBaseClicked__DelegateSignature"
local STACK_CLOSE = "/Script/Pal.PalUserWidgetStackableUI:Close"

local VIS = UI.VIS
local instances = {}     -- [menuAddr] = inst
-- [buttonAddr] = true for entry buttons on SWEPT menus that we cannot remove (touching
-- a lingering menu's native VerticalBox AVs). They stay clickable, so we adopt them and
-- route their clicks to the live page. Consulted only AFTER the live instances, so a
-- recycled address always belongs to whoever registered it for real.
local ghostOpen, ghostCount = {}, 0
-- STRICT CLICK DISPATCH -- written, tested, NOT ARMED. false = observe and log only, behaviour
-- byte-identical to 1.6.3. See onButtonClicked. Arm it when a log line justifies it.
local DISPATCH_STRICT = false
local gens = {}          -- [menuAddr] = generation (bumped on Destruct; stales delayed work)
-- SUPERSESSION COUNTER. `gens` only notices that MY menu Destructed -- and the crash log
-- of 2026-07-26 09:49 shows Destruct is exactly what does NOT happen: a stale instance is
-- swept on essentially every single inject, so old ESC menus linger, alive, carrying our
-- widgets. Worse, at 09:46:19 a page was still being BUILT (19.9167) when its instance was
-- swept (19.9525), and the build ran to completion anyway (19.9959), attaching ~100 widgets
-- to a menu we had already declared stale. `gens` could not see that: the menu never died,
-- it was merely superseded. So stamp every instance and refuse to build for any but the
-- newest -- the vault's one proven lever against the 0x78 race is to INJECT FEWER WIDGETS,
-- and a superseded menu is the clearest case of widgets nobody will ever see.
local injectSeq = 0
-- THE NEWEST MENU THE GAME HAS CONSTRUCTED (2026-07-31). injectSeq above already refuses to
-- BUILD A PAGE for a superseded instance -- but nothing refused to INJECT into one, and that is
-- the hole that ESC-spam falls through: NotifyOnNewObject schedules tryInject 50ms out, and at
-- ~400ms per open (measured, crash log 13:15:35-37) a newer menu frequently exists by the time
-- that callback runs. We then swept + injected into a menu the game had already moved past.
-- `gens` cannot see it (that only notices MY menu's Destruct, which is exactly what does not
-- happen here) and `alive()` cannot either (a lingering menu is a valid UObject).
-- Reproduced 2026-07-31 by spamming ESC: three CTDs, DarnMenu alone and with AntiPhat.
local newestMenuAddr = nil
-- Addresses are reused by UE, so an old menu can acquire the same pointer as a newer
-- one.  Keep a monotonic construction generation as the authoritative ordering key.
local newestMenuGeneration = 0
-- CHURN GATE (2026-07-31). Spamming ESC builds a new menu every ~330ms (measured across four
-- crash logs), and we answered every single one: create a button, sweep the previous instance,
-- write to the native canvas. Crashes 6/7/8 share one engine-only call path with a DIFFERENT bad
-- address each time (`0x207de368d48`, `0xffffffffffff`, `0xa0`) -- a garbage pointer read out of
-- the same structure -- and each died on a sweep during exactly that churn.
--
-- The vault's one proven lever against this whole class is to TOUCH FEWER WIDGETS. So: wait for
-- the churn to stop before touching anything. A menu the player blew past in 300ms never needed
-- our button; only the one they settle on does. This costs a visible delay before the entry
-- button appears while mashing ESC, and nothing at all in normal play.
-- CHURN_BURST: a new menu arriving within this long of the previous one means the player is
-- MASHING, not opening. That distinction is what keeps a normal open instant.
--
-- The first cut gated every open: it asked "has it been quiet for 300ms?" 50ms after
-- construction, which is never true, so every single open -- including a lone one -- paid ~350ms
-- before the button appeared. Maiq felt it immediately ("the latency on mod options showing up is
-- pretty high"). We cannot predict a burst, but we can DETECT one: a lone open follows a long
-- gap, so it injects immediately; the moment a second menu lands within CHURN_BURST we know we
-- are in a storm and gate everything after it. Cost is one un-gated inject at the start of a
-- burst, which is the same one a normal open would have done anyway.
local CHURN_QUIET, CHURN_MAX_WAIT, CHURN_BURST = 0.30, 3.0, 0.60
local lastMenuAt = -1e9
local menuBurst = 0
-- LINGERING-MENU COUNTER (2026-07-31). Measured across five sessions: only about a THIRD of ESC
-- menus ever Destruct (62 opened -> 10 destructed in one session). The rest stay alive holding a
-- button we created and parented into their native canvas, plus our page in their overlay. That
-- is a per-open leak, which is why the failure scales with ESC-spam without spam being the cause.
--
-- This exists to test whether the leak is what kills us: every inject prints the running count,
-- so each crash log ends with a number. If crashes cluster near a similar count that is causal
-- evidence; if they land anywhere, the leak is a red herring and the search moves on. Two data
-- points so far, from logs written before this counter existed: crashes at ~7 and ~16 lingering,
-- and one session that reached 52 whose ending is unknown.
--
-- ONE TABLE, NOT TWO LOCALS: this file's main chunk is heavily populated and the 200-local
-- ceiling is a parse error, not a warning.
local menuCount = { seen = 0, gone = 0 }
local hooksArmed = false
local serverDisabled = false

-- ---- layout (master-detail) ------------------------------------------------
-- Everything lives inside ONE fixed-size content canvas that is anchored to the
-- HORIZONTAL CENTER of the screen (ultrawide fix, 2026-07-22) -- coordinates
-- below are relative to that container, not the screen.
local CONTENT_W, CONTENT_H, CONTENT_Y = 1600, 880, 80
local TITLE_X, TITLE_Y = 20, 20
local LIST_X, LIST_Y, LIST_W, LIST_ROW = 20, 110, 300, 64
local PANEL_X, PANEL_Y, PANEL_W, PANEL_H = 360, 110, 1200, 620
local FOOT_Y = PANEL_Y + PANEL_H + 30
local ROW_H, SECTION_H = 52, 60
-- MAX rows a managed list will draw, not the number it shows. The section sits inside the
-- panel's ScrollBox, so the old cap of 10 was arbitrary -- it hid the rest of the list behind a
-- "(showing first 10)" note with no way to reach it, and a player asked for exactly this
-- (Jarol, Steam 2026-07-29: "why not put the list into a scrollable UI widget so we can view all
-- of them"). Now it draws one row per item and the scroll does its job.
--
-- The ceiling stays, well above any real blacklist, because each row is a native button clone:
-- a corrupt or absurd file must not try to build ten thousand widgets while the player waits.
local BL_ROWS = 400

-- A normal option row must be TALL ENOUGH for its wrapping help text, or long help
-- spills down over the rows beneath it (the help column is ~480px at font 12, so it
-- wraps around ~55 chars/line). Grow the row to fit; short help keeps the ROW_H floor.
local function optRowH(opt)
  local help = opt and opt.help
  if type(help) ~= "string" or help == "" then return ROW_H end
  local lines = math.max(1, math.ceil(#help / 55))
  return math.max(ROW_H, lines * 24 + 16)
end

-- ApplicationScale awareness (2026-07-23). The game shrinks ALL UMG when
-- [/Script/Engine.UserInterfaceSettings] ApplicationScale < 1 (Engine.ini) -- our
-- page inherits that fine, but because the content is TOP-anchored (Y=0) while the
-- native menu centers differently, it rides UP as the scale shrinks. Nudge it DOWN
-- by (1 - scale) * UISCALE_DROP so it re-centers. Zero at scale 1.0 -> the normal,
-- unscaled layout that everyone else runs is left byte-for-byte unchanged.
local UISCALE_DROP = 900
local function appUIScale()
  local ok, s = pcall(function()
    return StaticFindObject("/Script/Engine.Default__UserInterfaceSettings").ApplicationScale
  end)
  if ok and type(s) == "number" and s > 0.1 and s <= 4 then return s end
  return 1.0
end

-- ---------------------------------------------------------------------------
-- blacklist list (custom section): reads/writes the loot filter's real file.
-- Menu removals apply on relaunch; an in-session F10 save can restore an entry
-- (the live mod holds its own copy) -- the status line says so.
-- ---------------------------------------------------------------------------
-- generic managed-list UI (schema section custom = {type="listfile", file=...});
-- files are sandboxed to plain .txt basenames inside shared/
-- ONE rule for every schema-supplied file name. DarnMenu is an OPEN platform: the
-- names below arrive from third-party schema files, so they are untrusted input and
-- the paths are built by concatenation (SHARED .. name). A name containing separators
-- or ".." therefore escapes the shared folder entirely. This existed for list files
-- but not for schema targets or action-panel bridge files -- two write paths that
-- took the name straight from the schema. Same rule, one place, all three callers.
local function sharedPath(name, ext)
  name = tostring(name or "")
  if name:find("%.%.") then return nil end
  if ext then
    if not name:match("^[%w_%-%.]+$") or name:sub(-#ext) ~= ext then return nil end
  elseif not name:match("^[%w_%-%.]+$") then return nil
  end
  return SHARED .. name
end
local function listfilePath(fileName) return sharedPath(fileName, ".txt") end

-- WHICH FOLDER A SCHEMA BELONGS TO. regName is the registered schema name, which IS the mod's
-- folder; schema files written before regName existed fall back to the sandboxed target minus
-- its _user suffix. ToastLib_config is the one allowlisted target that does not match its own
-- folder. Returns nil for anything that is not a plain folder name, so no caller can build a
-- path out of a crafted schema field.
local function modFolderOf(schema)
  local folder = type(schema.regName) == "string" and schema.regName
                 or (type(schema.target) == "string" and schema.target:gsub("_user$", ""))
  if folder == "ToastLib_config" then folder = "DarnToasts" end
  if type(folder) == "string" and folder:match("^[%w_%-]+$") then return folder end
  return nil
end

-- GHOST PAGES. A schema file lives in shared/, which is exactly the folder that SURVIVES an
-- uninstall (that is the whole point of it -- settings outlive updates). So unsubscribing from
-- a mod removes its folder and leaves its DarnMenu page registered forever, and the page still
-- edits a file nothing reads. Reported repeatedly ("Despite being uninstalled DarnMenu still
-- references this mod").
--
-- HIDING SUCH A PAGE AUTOMATICALLY IS FORBIDDEN. The kit registers its own page from inside
-- whichever mod vendored it, so DarnUI's page has no folder of its own and would be hidden on
-- every install that does not also have the standalone DarnUI item -- a guaranteed false
-- positive on a live page. The read-only Other Mods tab has no folder either. So this only
-- ever TAGS a row and offers a button; the player decides.
--
-- Liveness is "is the mod's folder still there", tested through three files rather than one.
-- Info.json is the Workshop manifest and is what the page header already reads its version
-- from -- but a hand-installed or dedicated-server layout has no Info.json at all, and every
-- such install would have been tagged as missing. enabled.txt and Scripts/main.lua cover
-- those: a UE4SS Lua mod cannot load without the latter.
local function modMissing(schema)
  if schema.otherMod then return false end
  local folder = modFolderOf(schema)
  if not folder or folder == "DarnUI" then return false end
  for _, probe in ipairs({ "/Info.json", "/enabled.txt", "/Scripts/main.lua" }) do
    local f = io.open(DIR .. "../../" .. folder .. probe, "r")
    if f then pcall(function() f:close() end); return false end
  end
  return true
end

-- Delete a ghost page: its schema file, that file's backup, and its name in the index.
--
-- The index goes through Writers' compare-and-swap, NOT a truncate-write: another mod can be
-- registering itself in the same file while we do this (registration is a write from whatever
-- Lua state loaded first), and a blind rewrite would drop its entry. If the index write loses
-- the race the schema file is already gone, so loadAll's own self-heal prunes the name at the
-- next page build -- the failure mode is a stale line for one menu open, not a lost page.
--
-- THE SETTINGS FILE IS DELIBERATELY LEFT. <target>_user.lua is the player's own configuration;
-- reinstalling the mod re-registers the page and finds every value still there. Deleting it
-- would make an "undo the clutter" button into a data-loss button.
local function removeGhostPage(name)
  if type(name) ~= "string" or not name:match("^[%w_%-]+$") then return false, "unsafe page name" end
  local schemaPath = SHARED .. "DarnMenu_schema_" .. name .. ".lua"
  pcall(os.remove, schemaPath)
  pcall(os.remove, schemaPath .. ".bak")
  local indexPath = SHARED .. "DarnMenu_schema_index.lua"
  local state = Writers.readState(indexPath)
  if state.primaryStatus ~= "ok" and state.primaryStatus ~= "missing" then
    return false, "the schema index is " .. tostring(state.primaryStatus)
      .. " -- the page file is gone, but repair the index by hand"
  end
  local keep = {}
  for _, n in ipairs((state.primaryStatus == "ok" and state.primaryValue) or {}) do
    if type(n) == "string" and n ~= name then keep[#keep + 1] = n end
  end
  local opts = (state.primaryStatus == "ok")
    and { expectedRaw = state.primaryRaw } or { expectMissing = true }
  local ok, err = Writers.write(indexPath, keep, opts)
  if not ok then return false, tostring(err) end
  return true
end
local function readBlacklist(path)
  local items = {}
  local f = safe(function() return io.open(path, "r") end)
  if not f then return items end
  pcall(function()
    for line in f:lines() do
      local id = line:gsub("%s+$", "")
      if id ~= "" then items[#items + 1] = id end
    end
  end)
  pcall(function() f:close() end)
  return items
end
local function writeBlacklist(path, items)
  -- ATOMIC (2026-08-04): this used to truncate-write the SAME file OLF's watcher polls every
  -- 2s -- a poll landing inside the truncate window read empty and gutted OLF's in-memory
  -- list (Mechanos's wipe, one of three converging paths). writeAtomic's rename is the fix
  -- on this side; OLF's watcher additionally ignores transient empties on its side.
  local body = {}
  for _, id in ipairs(items) do body[#body + 1] = id end
  return Darn.writeAtomic(path, table.concat(body, "\n") .. ((#body > 0) and "\n" or ""))
end

-- FOLD MEMORY. secClosed lives on the menu INSTANCE, and the instance dies with every
-- menu close -- so a fold lasted exactly one ESC. Player toggles are recorded per
-- "<tab>|<section>" and survive both the menu and the session; sections the player
-- never touched keep following their schema's own default.
local FOLDS_PATH = SHARED .. "DarnMenu_folds.lua"
local secFolds = (function()
  local t = {}
  local chunk = safe(function() return safe_loadfile(FOLDS_PATH) end)
  if chunk then
    local okc, v = pcall(chunk)
    if okc and type(v) == "table" then
      for k, val in pairs(v) do
        if type(k) == "string" and type(val) == "boolean" then t[k] = val end
      end
    end
  end
  return t
end)()
local function saveFolds()
  local body = { "return {\n" }
  for k, v in pairs(secFolds) do
    body[#body + 1] = string.format("  [%q] = %s,\n", k, tostring(v))
  end
  body[#body + 1] = "}\n"
  return Darn.writeAtomic(FOLDS_PATH, table.concat(body))
end

-- ---------------------------------------------------------------------------
-- NESTED RECORDS (v1). Schema section: custom = { type="records", target="NPCS",
--   keyLabel=, addLabel=, empty=, fields = {
--     { path="mode", label=, kind="enum", values={...}, default= },
--     { path="mastered", label=, kind="list", addLabel=, numeric="auto" },  -- INNER dynamic list
--   } }
-- A dynamic MAP of named records; each record has scalar fields plus (optionally)
-- an inner dynamic list -- a dynamic list inside a dynamic list. Stored as one
-- nested table under staged[custom.target]; the serializer already handles the
-- nesting and applyAll writes it verbatim. Text-entry add (type the name); per-
-- row remove. No picker in v1.
-- ---------------------------------------------------------------------------
local function trimStr(s) return (tostring(s or ""):gsub("^%s+", ""):gsub("%s+$", "")) end
local function deepCopy(v)
  if type(v) ~= "table" then return v end
  local o = {}; for k, val in pairs(v) do o[k] = deepCopy(val) end; return o
end
-- store "68" as the number 68 (skill IDs); keep names as strings. numeric="auto".
local function coerceItem(val, numeric)
  val = trimStr(val)
  if numeric == "auto" and val:match("^%-?%d+$") then return tonumber(val) end
  return val
end
local function defaultRecord(custom)
  local rec = {}
  for _, f in ipairs(custom.fields or {}) do
    if f.kind == "list" then rec[f.path] = {}
    elseif f.default ~= nil then rec[f.path] = f.default
    elseif f.kind == "enum" and f.values and f.values[1] ~= nil then
      rec[f.path] = Schemas.enumValue(f.values[1])
    end
  end
  return rec
end

-- VALIDATION. Same contract as scalar options: return ok,message; on failure the
-- caller shows the message on the status line and leaves the typed text in the
-- box so the player can fix it. Author declares constraints on the schema.
--
-- record KEY (NPC name): custom.keyMaxLen, custom.keyPattern (Lua pattern the
--   whole name must match), custom.keyValidate = function(name) -> ok, why.
local function validateKey(custom, name)
  if custom.keyMaxLen and #name > custom.keyMaxLen then
    return false, "name too long (max " .. custom.keyMaxLen .. ")"
  end
  if type(custom.keyPattern) == "string" and not name:match(custom.keyPattern) then
    return false, custom.keyPatternMsg or "name has invalid characters"
  end
  if type(custom.keyValidate) == "function" then
    local okCall, ok, why = pcall(custom.keyValidate, name)
    if not okCall then return false, "name validator errored" end
    if not ok then return false, tostring(why or "invalid name") end
  end
  return true
end

-- list ITEM (a mastered skill). `val` is already coerced (number or string).
--   numeric="only" rejects non-numbers; min/max/integer apply to numbers; maxLen
--   to strings; unique=true forbids duplicates; validate = function(v) -> ok, why.
local function validateItem(f, val, list)
  local nm = f.label or f.path
  if type(val) == "number" then
    if f.integer and val % 1 ~= 0 then return false, nm .. ": whole numbers only" end
    if f.min and val < f.min then return false, nm .. ": min is " .. f.min end
    if f.max and val > f.max then return false, nm .. ": max is " .. f.max end
  else
    if f.numeric == "only" then return false, nm .. ": must be a number" end
    if f.maxLen and #val > f.maxLen then return false, nm .. ": too long (max " .. f.maxLen .. ")" end
    if f.minLen and #val < f.minLen then return false, nm .. ": too short (min " .. f.minLen .. ")" end
  end
  if type(f.values) == "table" then   -- must be one of the allowed values
    local ok = false
    for _, e in ipairs(f.values) do if Schemas.enumValue(e) == val then ok = true break end end
    if not ok then return false, nm .. ": '" .. tostring(val) .. "' is not an allowed value" end
  end
  if f.unique then
    for _, e in ipairs(list) do if e == val then return false, nm .. ": '" .. tostring(val) .. "' is already listed" end end
  end
  if type(f.validate) == "function" then
    local okCall, ok, why = pcall(f.validate, val)
    if not okCall then return false, nm .. ": validator errored" end
    if not ok then return false, nm .. ": " .. tostring(why or "invalid value") end
  end
  return true
end
local function hasRecordsSection(schema)
  for _, sec in ipairs(schema.sections or {}) do
    if type(sec.custom) == "table" and sec.custom.type == "records" then return true end
  end
  return false
end
-- the live working copy of a records map: staged[target], seeded once (per page
-- open, since openPage clears staged) from the on-disk config, else empty. Self-
-- loads the file if a background prebuild reaches it before openPage.
local function recordsFor(inst, ti, target)
  local ts = inst.tabs[ti]
  local recs = ts.staged[target]
  if type(recs) ~= "table" then
    if type(ts.fileTable) ~= "table" then
      local tp = sharedPath(tostring(ts.schema.target) .. ".lua", ".lua")
      ts.fileTable = (tp and Writers.read(tp)) or {}
    end
    local src = (type(ts.fileTable[target]) == "table") and ts.fileTable[target] or {}
    recs = deepCopy(src)
    ts.staged[target] = recs
  end
  return recs
end

-- Enum record-fields are TEXT INPUTS (type the value, matched against the field's
-- values; predictive suggestions help). Their boxes aren't read at click time, so
-- capture them into the staged records before any rebuild and on Apply. A typed
-- value must MATCH one of the field's `values`; a non-matching non-empty entry is
-- rejected (old value kept) and reported. `alive` here is UI.alive. Returns errs.
local function captureRecordFields(inst, ti)
  local ts = inst.tabs[ti]
  local errs = {}
  for _, rf in ipairs(ts.recFields or {}) do
    if UI.alive(rf.box) then
      local raw = trimStr(UI.editText(rf.box) or "")
      local recs = recordsFor(inst, ti, rf.target)
      local rec = recs[rf.key]
      if type(rec) == "table" and raw ~= "" then
        local matched, allowed = nil, {}
        for _, e in ipairs(rf.field.values or {}) do
          local v = Schemas.enumValue(e)
          allowed[#allowed + 1] = tostring(v)
          if tostring(v) == raw then matched = v end
        end
        if matched ~= nil then
          rec[rf.path] = matched
        elseif raw ~= tostring(rec[rf.path]) then
          errs[#errs + 1] = (rf.field.label or rf.path) .. ": '" .. raw .. "' must be one of " ..
            table.concat(allowed, " / ")
        end
      end
    end
  end
  return errs
end

-- ---------------------------------------------------------------------------
-- hotkey capture: UE4SS has no any-key listener and keybinds can't be
-- unregistered, so a ONE-TIME battery of binds over a curated key set feeds a
-- gate that's armed only while a "press a key..." button waits. Unarmed, the
-- handlers are no-ops. Binds are armed lazily on first use.
-- ---------------------------------------------------------------------------
local CAPTURE_KEYS = {
  "F1","F2","F3","F4","F5","F6","F7","F8","F9","F10","F11","F12",
  "A","B","C","D","E","F","G","H","I","J","K","L","M",
  "N","O","P","Q","R","S","T","U","V","W","X","Y","Z",
  "ZERO","ONE","TWO","THREE","FOUR","FIVE","SIX","SEVEN","EIGHT","NINE",
  "NUM_ZERO","NUM_ONE","NUM_TWO","NUM_THREE","NUM_FOUR",
  "NUM_FIVE","NUM_SIX","NUM_SEVEN","NUM_EIGHT","NUM_NINE",
  "SUBTRACT","ADD","MULTIPLY","DIVIDE","DECIMAL",
  "INS","DEL","HOME","END","PAGE_UP","PAGE_DOWN",
}
local capture = nil          -- { inst, tab, path, token } while waiting
local cancelCapture          -- fwd decl: defined below, used by closePage/runAction
local capToken = 0
local captureArmed = false

-- A SWITCH, so a toggle looks like a toggle.
--
-- A bool option was a native button reading ON or OFF -- pixel-identical to the enum cycler
-- next to it and to any plain action button, so nothing on screen said "this one flips". The
-- affordance existed in the mod's own artwork (DarnMenu's thumbnail has been drawing green
-- switch pills since launch) but never in the menu itself.
--
-- Two tinted Images over the right end of the button: a track that changes colour and a knob
-- that slides. Both are ours, both are canvas children, and flipping one only recolours and
-- MOVES them -- no widget is built or destroyed when a value changes.
local SW_ON_TRACK  = { R = 0.31, G = 0.78, B = 0.47, A = 1 }    -- the green from the thumbnail
local SW_OFF_TRACK = { R = 0.26, G = 0.30, B = 0.36, A = 1 }
local SW_KNOB      = { R = 0.94, G = 0.96, B = 0.98, A = 1 }
local SW_W, SW_H, SW_KNOB_W = 56, 24, 24
local SW_X = 566          -- right end of the 380..640 control column
local function setSwitch(ctl, on)
  if not ctl then return end
  pcall(function()
    if ctl.swTrack then ctl.swTrack:SetColorAndOpacity(on and SW_ON_TRACK or SW_OFF_TRACK) end
  end)
  -- the knob's travel IS the signal: a colour change alone reads as decoration
  if ctl.swKnob and ctl.swY then
    UI.canvasMove(ctl.swKnob, SW_X + (on and (SW_W - SW_KNOB_W - 2) or 2), ctl.swY + 2)
  end
end

local function valueLabel(v)
  if type(v) == "boolean" then return v and "ON" or "OFF" end
  return tostring(v)
end

-- live/relaunch indicator dots: green = applies now, amber = needs a relaunch.
-- Shown only when a schema declares `live` (per option, or page-wide default).
local LIVE_C     = { R = 0.45, G = 1.0, B = 0.55, A = 1 }
local RELAUNCH_C = { R = 1.0, G = 0.72, B = 0.35, A = 1 }
-- the game's own "notice" mark, tinted red, for the needs-relaunch marker
-- (VirtualBjorn). No "applies now" marker -- absence of this MEANS it applies now.
local RESTART_ICON = "/Game/Pal/Texture/UI/Common/T_prt_NoticeMark.T_prt_NoticeMark"
local RESTART_TINT = { R = 1, G = 0.32, B = 0.18, A = 1 }
local KEY_RESET_ICON = "/Game/Pal/Texture/UI/KeyGuide/T_prt_KeyGuide_change.T_prt_KeyGuide_change"
local function tintText(tb, c)
  if not tb then return end
  pcall(function() tb:SetColorAndOpacity({ SpecifiedColor = c, ColorUseRule = 0 }) end)
end
local optLive = Schemas.optLive   -- nil = undeclared (no dot); logic lives in
                                  -- schemas.lua where test-darn.js can reach it

local function currentVal(inst, ti, path)
  local tabState = inst.tabs[ti]
  local v = tabState.staged[path]
  if v == nil then v = tabState.values[path] end
  return v
end

local function setStatus(inst, text)
  if inst.statusText and UI.alive(inst.statusText) then
    pcall(function() inst.statusText:SetText(FText(text)) end)
  end
end

-- Assigned to markDirty below; the keychord helper above needs it and is defined first, and a
-- direct call there would read a nil GLOBAL.
local markDirtyRef = nil

-- SAY THAT SOMETHING IS WAITING TO BE SAVED -- on the button they have to press.
--
-- Every control here STAGES its change; nothing reaches disk until Apply. That is the right
-- design (a page of edits becomes one atomic save) but nothing said so, and a toggle that
-- visibly flips looks like it took effect. Mikey switched on a setting, left the menu, and found
-- the mod still doing the old thing -- then asked for exactly this (2026-07-30). Jarol had
-- reported the same shape from the other side a day earlier: an edit that "doesn't save unless
-- you edit another option, hit apply".
--
-- The count goes on the Apply BUTTON rather than only in the status line, because the status
-- line is where results appear and is easy to read past -- the button is where the player has to
-- go, and a button that has changed its own label is hard to miss.
local function markDirty(inst)
  local n = 0
  for _, ts in ipairs(inst.tabs or {}) do
    for _ in pairs(ts.staged or {}) do n = n + 1 end
  end
  if UI.alive(inst.applyBtn) then
    UI.setLabel(inst.applyBtn,
      (n > 0) and ("Apply " .. n .. " change" .. ((n == 1) and "" or "s")) or "Apply")
  end
  if n > 0 then
    setStatus(inst, n .. " unsaved change" .. ((n == 1) and "" or "s")
      .. " -- press Apply, or they are lost when you close this page.")
  end
  return n
end

markDirtyRef = markDirty

-- ---- KEYCHORD helpers (ported from VirtualBjorn) --------------------------
local MODIFIER_ORDER = { "CONTROL", "ALT", "SHIFT" }
local function normalizeChord(value) return Schemas.normalizeChord(value) or { key = "", modifiers = {} } end
local function chordHasModifier(chord, wanted)
  for _, name in ipairs(chord.modifiers or {}) do if name == wanted then return true end end
  return false
end
local function chordsEqual(a, b)
  local ca, cb = Schemas.normalizeChord(a), Schemas.normalizeChord(b)
  if not (ca and cb) or ca.key ~= cb.key then return false end
  for _, modifier in ipairs(MODIFIER_ORDER) do
    if chordHasModifier(ca, modifier) ~= chordHasModifier(cb, modifier) then return false end
  end
  return true
end
local function setOpacity(widget, opacity) if widget then pcall(function() widget:SetRenderOpacity(opacity) end) end end
-- draw a bind control: keycapture = a single keycap; keychord = 3 modifier toggle
-- cells (dimmed when off) + the primary keycap.
local function renderKeyControl(ctl, value)
  if ctl.opt.kind ~= "keychord" then UI.setKeycap(ctl.button, ctl.keyIcon, value); return end
  local chord = normalizeChord(value)
  for _, modifier in ipairs(MODIFIER_ORDER) do
    local button = ctl.modButtons and ctl.modButtons[modifier]
    local icon = ctl.modIcons and ctl.modIcons[modifier]
    if button and icon then
      UI.setKeycap(button, icon, modifier)
      local op = chordHasModifier(chord, modifier) and 1.0 or 0.28
      setOpacity(button, op); setOpacity(icon, op)
    end
  end
  UI.setKeycap(ctl.button, ctl.keyIcon, chord.key)
  if ctl.resetButton then
    local showReset = ctl.defaultValue ~= nil and not chordsEqual(value, ctl.defaultValue)
    UI.setVis(ctl.resetButton, showReset and VIS.SHOW or VIS.HIDE)
    UI.setVis(ctl.resetIcon, showReset and VIS.PASSIVE or VIS.HIDE)
  end
end

local function onCapturedKey(name)
  local c = capture
  if not c then return end
  capture = nil
  local inst = c.inst
  if inst.disposed or not inst.pageOpen then return end
  local ctl = inst.tabs[c.tab].controls[c.path]
  local staged = name
  if ctl and ctl.opt and ctl.opt.kind == "keychord" then   -- keep modifiers, set primary key
    local chord = normalizeChord(currentVal(inst, c.tab, c.path))
    chord.key = name
    staged = Schemas.encodeChord(chord) or name
  end
  inst.tabs[c.tab].staged[c.path] = staged
  if markDirtyRef then markDirtyRef(inst) end
  if ctl and ctl.button then
    if ctl.opt and (ctl.opt.kind == "keycapture" or ctl.opt.kind == "keychord") and ctl.keyIcon then renderKeyControl(ctl, staged)
    else UI.setLabel(ctl.button, name) end
  end
  setStatus(inst, "Hotkey staged: " .. name .. " -- press Apply to save.")
end

local function armCaptureBinds()
  if captureArmed then return end
  captureArmed = true
  local armed = 0
  for _, n in ipairs(CAPTURE_KEYS) do
    local k = safe(function() return Key[n] end)
    if k ~= nil then
      local ok = pcall(function()
        RegisterKeyBind(k, function() pcall(onCapturedKey, n) end)
      end)
      if ok then armed = armed + 1 end
    end
  end
  log("key-capture binds armed: " .. armed)
end

-- ---------------------------------------------------------------------------
-- entry button placement: under Link Discord, with a small gap.
-- ---------------------------------------------------------------------------
local ENTRY_GAP = 8
local function padEntrySlot(slot)
  pcall(function() slot:SetPadding({ Left = 0, Top = ENTRY_GAP, Right = 0, Bottom = 0 }) end)
end
-- ENTRY BUTTON: APPEND ONLY (2026-07-29, CTD `AV reading 0x28` at 19:24:32). With the
-- pre-build already off, the crash landed at the exact millisecond of `inject` on the 4th
-- ESC open of the session -- stack was an engine widget-tree walk (one offset repeating
-- x11), our Lua completed (no crumb, "injected" logged), engine died on the next frame.
-- The one bulk mutation left on the open path was THIS function's positional insert:
-- UI.insertChildAt with an index detaches the ENTIRE TAIL of the game's live button
-- column and re-adds it -- a full Slots rewrite of a menu mid-construction, the same
-- class as the `writing 0x80` crash. A nil index is a plain single AddChild: no existing
-- slot is touched. Cost: our button sits at the BOTTOM of the column instead of under
-- Discord. Set false to restore positional placement.
local ENTRY_APPEND_ONLY = true

-- CANVAS PLACEMENT (2026-07-31) -- the ESC-spam CTD, and why appending to the column is the
-- cause rather than a bystander.
--
-- Adding a child to a CanvasPanel positions that child alone: no sibling is touched. Adding a
-- child to a VERTICAL BOX reflows the whole column -- every sibling slot's geometry recomputed
-- and the children array rebuilt -- and that happens on the engine's next layout pass, AFTER our
-- Lua has returned. Which is exactly where we died: `injected` is the last line inject() writes,
-- and all four 2026-07-31 crash logs end on it or the sweep beside it.
--
-- The evidence that settled it was a CONTROL, not a theory. AntiPhat hooks the same five
-- functions, seats an entry button on the same menu, keeps the same address-keyed state, and
-- survives the identical ESC-spam that kills us three times out of three. The difference is
-- placement: its column append is a FALLBACK; its primary path is an absolutely-positioned
-- canvas child. That also explains why it may collapse its stale entry button while our own code
-- comments record that collapsing ours AV'd (`writing 0x80`) -- a collapse in a VerticalBox is
-- another reflow.
--
-- It explains the whole history: ENTRY_APPEND_ONLY (2026-07-29) removed insertChildAt's
-- tail-detach and cut the rate, but a plain AddChild to a VerticalBox still reflows, so it could
-- never remove the cause.
--
-- Set false to go back to the column and reproduce the crash.
local ENTRY_ON_CANVAS = true
-- 400 design units wide: the native rows measure ~535px on Mikey's 3440x1440 screenshot, and
-- the canvas is drawn at ~1.34x there (engine UI scale), so ~400 in canvas units. Verified
-- against the same screenshot's rendering of the previous 320 (~428px). Refine from the
-- geometry line this function logs, not from another screenshot measurement.
local ENTRY_W, ENTRY_H, ENTRY_Z = 400, 56, 30
local ENTRY_FALLBACK_X, ENTRY_FALLBACK_Y = 60, 640
-- The ESC menu has TWO native button columns: VerticalBox_148 at the top (Options, Survival
-- Guide, Journals, Emergency Respawn, Link Discord) and VerticalBox_293 at the bottom (Return to
-- Title). Confirmed on screen 2026-07-31 -- the bottom group is where a mod entry reads as
-- native. Anchoring under the TOP column is what put our button through the middle of Emergency
-- Respawn/Link Discord: that column is AUTO-SIZED, so its slot reports height 0 and "below it"
-- resolved to "just below its top edge".
local COLUMN_BOTTOM, COLUMN_TOP = "VerticalBox_293", "VerticalBox_148"
-- LEARNED ONCE, THEN CACHED (Maiq, 2026-07-31: "check once robustly and cache that result, it's
-- not going to leave mid-session").
--
-- Every ESC menu is a FRESH widget tree, so each open is a fresh race: the other mod re-injects
-- its own button on its own timer, and whichever of us looks first sees an empty shelf. Measured
-- over 21 opens in one session: 19 detected the neighbour and lifted, 2 did not -- and the misses
-- were scattered through the session, not just the first open, so "only the first one is wrong"
-- would have been the wrong model.
--
-- A neighbouring mod cannot be installed or removed mid-session, so the lift is a property of the
-- SESSION, not of the menu instance. Keep scanning until the scan is informative, then freeze it
-- and stop touching the native canvas altogether. Fewer reads of a native panel during menu churn
-- is also the direction everything else today has moved in.
--
-- Cost: a mod that first appears AFTER we have cached a non-zero lift will not be noticed. It
-- cannot happen without a relaunch, which resets this to nil anyway.
local stackLift = nil

-- MANUAL ESCAPE HATCH: shared/DarnMenu_user.lua may set `entryRowOffset = 1`.
--
-- The scan above is best-effort and cannot be made complete. It reads the DIRECT
-- bottom-anchored children of Canvas_Buttons, so a neighbour that seats its button on a
-- different parent, or with a top anchor, or after us, is invisible to it and we draw on top
-- of them. That is the shape of the AntiPhat overlap reports: the lift stays 0 while another
-- mod's row is plainly underneath ours. Hardening the scan is guesswork against layouts we
-- cannot see; one extra row, chosen by the person looking at the screen, always works.
--
-- Hand-edited by design -- it exists for a layout we failed to detect, not as a setting worth
-- a page, and the file normally does not exist at all (a missing file is the NORMAL case here,
-- not an error). Clamped and floored because a user file is untrusted input: an offset of 500
-- would put the button off screen with no way back except finding this file again. Negative
-- values are allowed so someone whose scan lifts too far can push back down.
--
-- `logged` rides on the same table so the applied offset is reported once per session without
-- a second file-scope local (main.lua's chunk keeps its local budget for real state).
local ENTRY_OFFSET = {
  logged = false,
  rows = (function()
    local chunk = safe(function() return safe_loadfile(SHARED .. "DarnMenu_user.lua") end)
    if not chunk then return 0 end
    local ok, t = pcall(chunk)
    if not ok or type(t) ~= "table" then return 0 end
    local v = tonumber(t.entryRowOffset)
    if type(v) ~= "number" or v ~= v then return 0 end
    return math.max(-4, math.min(8, math.floor(v)))
  end)(),
}

-- Seat the entry button on Canvas_Buttons instead of inside the native column. Position is read
-- from the COLUMN'S OWN canvas slot so we land under it wherever the game put it (Mikey plays at
-- 3440x1440; a hard-coded corner would be wrong there -- see the vault's ultrawide note). If that
-- slot cannot be read, a constant keeps the button on screen rather than nowhere.
-- Seat the entry button on the canvas instead of inside a native column.
--
-- PREFERRED: directly ABOVE the bottom column, mirroring its anchors -- UI.canvasAddAbove does
-- exactly this (it was built to pin the prestige badge above the native Block List button) and
-- it undoes the anchor's own pivot, so the result tracks at any resolution/aspect. That matters
-- here: Mikey plays at 3440x1440 and the vault's standing rule is to anchor to real widgets,
-- never to a screen corner.
local function placeEntryOnCanvas(menu, btn, canvas)
  if not (UI.alive(canvas) and UI.alive(btn)) then return false end
  -- canvasAddAboveStretch, NOT canvasAddAbove. The bottom column is STRETCH-anchored
  -- ((0,1)-(1,1), measured), and canvasAddAbove mirrors those anchors while writing
  -- Position/Size -- a combination the slot cannot represent. It produced a degenerate rect and
  -- Slate AV'd laying it out (`writing 0x1c`, 2026-07-31 13:39, second ESC open, no spam needed).
  -- The stretch variant writes OFFSETS, which is what a stretched slot is actually made of, and
  -- inherits the column's Left/Right so the width matches the native rows for free.
  local anchorBox = UI.findByName(menu, COLUMN_BOTTOM)
  -- SHARE THE SHELF. Canvas_Buttons is a public space: any mod that pins a row above the bottom
  -- column computes the same spot we do, so whoever injects second draws on top of the first.
  -- That is what happened on 2026-07-31 -- our button landed squarely on AntiPhat's.
  --
  -- So ask the canvas how far its bottom-anchored stack already reaches and start above it. No
  -- mod names and no negotiation: anything parked there, by anyone, moves us up one row. If we
  -- are first, the stack is just the column itself and the lift is zero.
  --
  -- It only orders arrivals that come BEFORE us: a mod injecting later still computes its own
  -- spot from the column and can land on us. Nothing on our side can prevent that -- it is the
  -- same first-come rule seen from the other end.
  -- Once learned, never re-scanned -- see stackLift.
  local lift = stackLift or 0
  if stackLift == nil and UI.alive(anchorBox) and UI.bottomStackTop then
    local baseTop = safe(function() return anchorBox.Slot:GetOffsets().Top end)
    local stackTop = UI.bottomStackTop(canvas, btn)
    if type(baseTop) == "number" and type(stackTop) == "number" and stackTop < baseTop then
      -- Round UP to a whole row. A neighbour parked at an odd offset would otherwise leave us
      -- straddling it; snapping to the row pitch keeps the column looking like a column.
      local rows = math.ceil((baseTop - stackTop) / (ENTRY_H + ENTRY_GAP))
      lift = rows * (ENTRY_H + ENTRY_GAP)
      stackLift = lift
      log(string.format("bottom stack occupied to %.0f (column at %.0f) -- lifting %.0f "
        .. "(%d row(s)) -- CACHED for the session", stackTop, baseTop, lift, rows))
    end
  end
  -- The manual offset is added AFTER the cache, never into it: stackLift stays purely what the
  -- scan found, so the two cannot compound each other across opens.
  if ENTRY_OFFSET.rows ~= 0 then
    lift = lift + ENTRY_OFFSET.rows * (ENTRY_H + ENTRY_GAP)
    if not ENTRY_OFFSET.logged then
      ENTRY_OFFSET.logged = true
      log(string.format("entryRowOffset = %d from shared/DarnMenu_user.lua -- entry button moved "
        .. "%d row(s) (%.0f px) from where the scan put it", ENTRY_OFFSET.rows, ENTRY_OFFSET.rows,
        ENTRY_OFFSET.rows * (ENTRY_H + ENTRY_GAP)))
    end
  end
  if alive(anchorBox)
      and UI.canvasAddAboveStretch(anchorBox, btn, ENTRY_GAP + lift, ENTRY_H, ENTRY_Z) then
    log(string.format("entry button on CANVAS above %s (lift %.0f)", COLUMN_BOTTOM, lift))
    return true
  end
  -- Last resort: a fixed spot. Visible and clickable beats absent.
  local ok = UI.canvasAdd(canvas, btn, ENTRY_FALLBACK_X, ENTRY_FALLBACK_Y, ENTRY_W, ENTRY_H, ENTRY_Z)
  log(string.format("entry button on CANVAS at fallback (%d,%d): %s",
    ENTRY_FALLBACK_X, ENTRY_FALLBACK_Y, tostring(ok)))
  return ok
end

local function findMenuVerticalBox(menu)
  if not UI.alive(menu) then return nil end
  -- 1. Try finding any child button's parent vertical box
  local testButtons = {
    "WBP_MenuESC_Button_S_Discord",
    "WBP_MenuESC_Button_S_ReturnTitle",
    "WBP_MenuESC_Button_S_ReturnGame",
    "WBP_MenuESC_Button_S_Option",
    "WBP_MenuESC_Button_S_Options",
    "WBP_MenuESC_Button_S_WorldSetting"
  }
  for _, name in ipairs(testButtons) do
    local b = safe(function() return menu[name] end) or UI.findByName(menu, name)
    if UI.alive(b) then
      local p = safe(function() return b:GetParent() end)
      if UI.alive(p) then return p end
    end
  end
  -- 2. Search all VerticalBox instances inside menu
  local allBoxes = FindAllOf("VerticalBox") or {}
  for _, box in ipairs(allBoxes) do
    if UI.alive(box) and safe(function() return box:GetOuter() == menu or box:GetParent() == menu end) then
      return box
    end
  end
  return UI.findByName(menu, COLUMN_BOTTOM) or UI.findByName(menu, COLUMN_TOP)
end

local function placeUnderDiscord(menu, btn)
  local box = findMenuVerticalBox(menu)
  if not UI.alive(box) then return false end
  local addToBox = function(b, w) return b:AddChildToVerticalBox(w) end
  local placed = UI.insertChildAt(box, btn, nil, addToBox, padEntrySlot)
  if not placed then
    pcall(function() box:AddChildToVerticalBox(btn) end)
    placed = true
  end
  return placed
end

-- RE-SETTLE HIT-TESTING AFTER THE OPEN ANIMATION.
-- UI.insertChildAt already ends in UI.relayout, and that is what fixed clicks landing one
-- slot off in 1.6.1 -- but it is a SINGLE prepass, run at inject time, which is while the
-- ESC menu is still playing AnmEvent_FirstOpen. The 2026-07-27 log shows the symptom
-- surviving that fix: the first click after opening the menu dispatched to the NATIVE
-- button below ours --
--   click had no registered action (name=WBP_MenuESC_Button_S_ReturnTitle ours=false)
-- -- i.e. the column DREW in the new order while Slate still HIT-TESTED the old one. The
-- animation re-lays-out the column after us, so our prepass is stale by the time the
-- player can click. Re-run it twice more, after the animation has had time to settle.
-- Cheap and idempotent (invalidate + prepass on ONE VerticalBox, not the menu tree), and
-- gen/disposed-guarded like every other timer here so it cannot touch a dying menu.
--
-- 2026-07-27, SECOND ATTEMPT. The relayout retry above did NOT fix it, and the log says so
-- precisely rather than ambiguously: inject at 10:17:04.293, retry pass at ~.593, displaced
-- click at 10:17:05.158. A pass ran 565ms BEFORE the bad click and the hit-test was still
-- stale. So forcing a prepass on the VerticalBox is not the mechanism -- stop tuning delays.
--
-- WORKING HYPOTHESIS: an ancestor caches hit-test data. UMG's invalidation/retainer panels
-- cache a subtree's draw AND its hit-test grid until explicitly invalidated, which produces
-- exactly this signature -- drawn correctly, hit-tested from a stale grid, and self-healing
-- the moment anything else invalidates the cache (which is why the SECOND click always
-- works). InvalidateLayoutAndVolatility does not clear that cache.
--
-- So: walk up from the column and invalidate any cache we find. And because that is still a
-- hypothesis, LOG THE ANCESTRY ONCE -- if there is no such panel in the chain, the next log
-- says so outright and this whole line of attack is dead, which is worth more than another
-- delay guess. (Instrument rather than guess -- the vault's own rule, relearned here.)
-- ---------------------------------------------------------------------------
-- page: refresh helpers
-- ---------------------------------------------------------------------------
-- dependsValue: a dependency can match an ENUM VALUE, not just true -- "show
-- these rows only for the selected style". One helper so the refresh and every
-- action guard agree on what satisfied means.
local function depSatisfied(inst, ti, opt)
  if not opt.dependsOn then return true end
  local want = opt.dependsValue
  if want == nil then want = true end
  return currentVal(inst, ti, opt.dependsOn) == want
end
local function refreshDepends(inst, ti)
  local tabState = inst.tabs[ti]
  for path, ctl in pairs(tabState.controls) do
    local dep = ctl.opt.dependsOn
    if dep then
      local on = depSatisfied(inst, ti, ctl.opt)
      local dim = on and 1.0 or 0.35
      for _, w in ipairs({
        ctl.button, ctl.input, ctl.label, ctl.help, ctl.liveIcon, ctl.keyIcon,
        ctl.resetButton, ctl.resetIcon,
      }) do
        if w then pcall(function() w:SetRenderOpacity(dim) end) end
      end
      if not on and ctl.modButtons then   -- keychord cells: only force-dim when the dependency
        for _, w in pairs(ctl.modButtons) do setOpacity(w, dim) end  -- is off; renderKeyControl owns
        for _, w in pairs(ctl.modIcons) do setOpacity(w, dim) end    -- their per-modifier opacity otherwise
      end
      -- steppers HIDE when the dependency is off: the native button's disabled
      -- state renders as a white slab (jarring). The step action guards
      -- dependsOn, so a hidden-but-somehow-clicked button is still inert.
      for _, w in ipairs({ ctl.minus, ctl.plus }) do
        if w then UI.setVis(w, on and VIS.SHOW or VIS.HIDE) end
      end
      local target = ctl.button or ctl.input
      if target then pcall(function() target:SetIsEnabled(on) end) end
      if ctl.resetButton then pcall(function() ctl.resetButton:SetIsEnabled(on) end) end
    end
  end
end

local function refreshTab(inst, ti)
  local tabState = inst.tabs[ti]
  for path, ctl in pairs(tabState.controls) do
    local v = currentVal(inst, ti, path)
    if ctl.button then
      -- enums store the VALUE but display the entry's label (if the author gave one)
      if ctl.opt.kind == "enum" then UI.setLabel(ctl.button, Schemas.enumDisplay(ctl.opt, v))
      elseif (ctl.opt.kind == "keycapture" or ctl.opt.kind == "keychord") and ctl.keyIcon then renderKeyControl(ctl, v)
      else UI.setLabel(ctl.button, valueLabel(v)); if type(v) == "boolean" then setSwitch(ctl, v) end end
    elseif ctl.input then
      -- restyle EVERY refresh: PalEditableTextBox stomps construction styling
      -- per-instance (white-on-white "invisible values", fixed by reopening)
      UI.styleEdit(ctl.input)
      UI.setEditText(ctl.input, v == nil and "" or tostring(v))
    end
  end
  refreshDepends(inst, ti)
end

-- MANAGED-LIST ROWS IN REAL WORDS (2026-07-31, Mikey: "the white list still seems to use ids
-- instead of say"). The rows showed the raw internal id -- "MachineParts2" where the player
-- knows "Circuit Board".
--
-- DECLARED, NOT ASSUMED. DarnMenu is a platform: a listfile can hold pal ids or station ids as
-- easily as item ids, so the CONSUMER says what its file contains via
-- `custom.names = "item" | "pal" | "station"`, and anything undeclared renders verbatim
-- exactly as before. That keeps the platform ignorant of Palworld semantics while still
-- letting it read well.
--
-- BOTH, when they differ: "Circuit Board  (MachineParts2)". The name is what the player
-- recognises; the id is what a bug report needs and what the mod's own hotkeys print. Showing
-- one and hiding the other just moves the problem.
--
-- pcall'd require, and a nil-safe call: DarnMenu must not fail to build a page because the
-- kit is missing or older than the lookup it is asked for -- today's LA/DarnToasts crash is
-- the whole reason that rule exists.
local SayKit = (function() local ok, m = pcall(require, "say"); return ok and m or nil end)()
local function listLabel(id, kind)
  if not (SayKit and kind) then return id end
  local fn = (kind == "item" and SayKit.item)
          or (kind == "pal" and SayKit.pal)
          or (kind == "station" and SayKit.station)
  if type(fn) ~= "function" then return id end
  local ok, name = pcall(fn, id)
  if not ok or type(name) ~= "string" or name == "" or name == id then return id end
  return name .. "  (" .. id .. ")"
end

local function refreshBlacklist(inst, ti)
  local tabState = inst.tabs[ti]
  if not tabState or not tabState.blRows then return end
  if not tabState.blFile then return end
  local items = readBlacklist(tabState.blFile)
  tabState.blItems = items
  local n = #items
  if tabState.blCount then
    local txt = (n == 0)
      and (tabState.blEmpty or "List is empty.")
      or (n .. " item(s)" .. (n > #tabState.blRows
            and ("  (showing first " .. #tabState.blRows .. " -- reopen Mod Options to see the rest)")
            or ""))
    pcall(function() tabState.blCount:SetText(FText(txt)) end)
  end
  for i, row in ipairs(tabState.blRows) do
    local id = items[i]
    if id then
      if row.label then
        local shown = listLabel(id, tabState.blNames)
        pcall(function() row.label:SetText(FText(shown)) end); UI.setVis(row.label, VIS.PASSIVE)
      end
      if row.btn then UI.setVis(row.btn, VIS.SHOW) end
    else
      if row.label then UI.setVis(row.label, VIS.HIDE) end
      if row.btn then UI.setVis(row.btn, VIS.HIDE) end
    end
  end
end

-- PERF: panels are built LAZILY, one per mod, the first time that mod is
-- selected -- the Mod Options click only pays for the shell + list + one panel
-- instead of every widget of every mod at once. ensurePanel is assigned after
-- buildModPanel exists (definition order); it runs only from user actions.
local ensurePanel

local function selectMod(inst, index)
  local switched = inst.activeTab ~= index
  inst.activeTab = index
  if ensurePanel then ensurePanel(inst, index) end
  -- BOOKKEEPING-INDEPENDENT visibility (the "stuck panel over other panels"
  -- bug): hiding only the panels we REMEMBER leaves any orphan/ghost panel
  -- painted forever -- and the failure states that create them (recycled
  -- widget addresses, silent destructs) are nondeterministic. So enforce
  -- reality instead: every ScrollBox child of the content canvas is hidden
  -- unless it IS the active panel. Self-heals on every tab click.
  local active = inst.tabPanels[index]
  local activeA = active and UI.addr(active)
  local swept = false
  pcall(function()
    local n = inst.content:GetChildrenCount()
    for i = 0, n - 1 do
      local ch = inst.content:GetChildAt(i)
      if UI.alive(ch)
        and safe(function() return ch:GetClass():GetFName():ToString() end) == "ScrollBox" then
        -- the mod-list ScrollBox is ALSO a content child but must stay visible --
        -- it is not a panel; only panels get hidden when they aren't active
        if not (inst.listScroll and UI.addr(ch) == UI.addr(inst.listScroll)) then
          UI.setVis(ch, (UI.addr(ch) == activeA) and VIS.SHOW or VIS.HIDE)
        end
        swept = true
      end
    end
  end)
  -- fallback if the child walk failed: the old registry-only hide
  if not swept then
    for i, panel in pairs(inst.tabPanels) do UI.setVis(panel, i == index and VIS.SHOW or VIS.HIDE) end
  end
  if inst.selectorList then
    inst.selectorList:setSelected(index)
  else
    for i, btn in ipairs(inst.listButtons) do UI.selected(btn, i == index) end
  end
  -- read-only tabs (the Other Mods browser) have nothing to save -> hide Apply / Restore Defaults
  local ro = inst.tabs[index] and inst.tabs[index].schema and inst.tabs[index].schema.otherMod
  if inst.applyBtn then UI.setVis(inst.applyBtn, (ro and VIS.HIDE) or VIS.SHOW) end
  if inst.defaultsBtn then UI.setVis(inst.defaultsBtn, (ro and VIS.HIDE) or VIS.SHOW) end
  -- a status message belongs to the tab it happened on (e.g. Toasts' "applied
  -- live") -- don't let it linger over a different mod's page
  if switched then setStatus(inst, "") end
end

-- ---------------------------------------------------------------------------
-- page: construction (lazy, per menu instance)
-- ---------------------------------------------------------------------------
local function buildBlacklistSection(inst, ti, canvas, y)
  local tabState = inst.tabs[ti]
  tabState.blRows = {}
  tabState.blCount = UI.mkText(inst.widgetTree, inst.textTemplate, "", 14, 0.7)
  if tabState.blCount then UI.canvasAdd(canvas, tabState.blCount, 20, y + 2, 900, 26, 1) end
  y = y + 34
  -- ONE ROW PER ITEM. Built to the list's real length so nothing is hidden; refreshBlacklist
  -- still hides any row whose item has since gone, which is what makes Remove work without a
  -- rebuild.
  local nRows = math.max(1, math.min(#readBlacklist(tabState.blFile or ""), BL_ROWS))
  for i = 1, nRows do
    local label = UI.mkText(inst.widgetTree, inst.textTemplate, "", 15)
    if label then UI.canvasAdd(canvas, label, 40, y + 10, 480, 28, 1); UI.setVis(label, VIS.HIDE) end
    local btn = UI.nativeButton(inst.menu, "Remove", inst.actions, { type = "blremove", tab = ti, index = i })
    if btn then UI.canvasAdd(canvas, btn, 540, y, 160, 40, 1); UI.setVis(btn, VIS.HIDE) end
    tabState.blRows[i] = { label = label, btn = btn }
    y = y + 44
  end
  return y + 10
end

-- render one records section. Each record is a COLLAPSIBLE entry (name-only until
-- you click it open -- saves room over a long list). Enum fields are validated
-- TEXT INPUTS (predictive suggestions come from DarnUI's UI.suggestList, fed by predBoxes); inner
-- lists have per-item remove + an add-row. ts.recFields = enum text boxes to
-- capture on rebuild/apply; ts.predBoxes = boxes eligible for the suggestion
-- dropdown. Both are reset once per panel build (in buildModPanel's scroll builder).
local function buildRecordsSection(inst, ti, canvas, y, custom)
  local ts = inst.tabs[ti]
  local target = custom.target
  local recs = recordsFor(inst, ti, target)
  ts.expanded = ts.expanded or {}

  -- Add-<key> row (predictive if custom.keyValues gives a known set)
  local kLbl = UI.mkText(inst.widgetTree, inst.textTemplate, custom.keyLabel or "New entry", 14, 0.7)
  if kLbl then UI.canvasAdd(canvas, kLbl, 20, y + 8, 190, 30, 1) end
  local addBox = UI.mkEdit(inst.widgetTree, "")
  if addBox then
    UI.canvasAdd(canvas, addBox, 210, y + 4, 320, 40, 1)
    if type(custom.keyValues) == "table" then
      ts.predBoxes[#ts.predBoxes + 1] = { box = addBox, x = 210, y = y + 4, field = { values = custom.keyValues }, canvas = canvas }
    end
  end
  local addBtn = UI.nativeButton(inst.menu, custom.addLabel or "Add", inst.actions,
    { type = "recAdd", tab = ti, target = target, custom = custom, box = addBox })
  if addBtn then UI.canvasAdd(canvas, addBtn, 545, y, 170, 48, 1) end
  y = y + ROW_H

  local keys = {}
  for k in pairs(recs) do keys[#keys + 1] = tostring(k) end
  table.sort(keys)
  if #keys == 0 then
    local e = UI.mkText(inst.widgetTree, inst.textTemplate, custom.empty or "No entries yet.", 14, 0.5)
    if e then UI.canvasAdd(canvas, e, 40, y + 2, 800, 28, 1) end
    y = y + 40
  end

  for _, key in ipairs(keys) do
    local rec = recs[key]; if type(rec) ~= "table" then rec = {}; recs[key] = rec end
    local isOpen = ts.expanded[key] == true
    -- collapsible header: a [+]/[-] toggle glyph, separated from the name, then the
    -- name. [-] = expanded (click to collapse), [+] = collapsed (click to expand) --
    -- the standard tree convention; unambiguous vs a bare "v" that reads as a letter.
    local hdr = UI.nativeButton(inst.menu, (isOpen and "[-]    " or "[+]    ") .. key, inst.actions,
      { type = "recToggle", tab = ti, key = key })
    if hdr then UI.canvasAdd(canvas, hdr, 30, y, 540, 46, 1); ts.recHeaders[key] = hdr end
    local rm = UI.nativeButton(inst.menu, "Remove", inst.actions,
      { type = "recRemove", tab = ti, target = target, key = key })
    if rm then UI.canvasAdd(canvas, rm, 585, y, 150, 44, 1) end
    y = y + 50

    if isOpen then
      for _, f in ipairs(custom.fields or {}) do
        if f.kind == "enum" then
          local nvals = #(f.values or {})
          -- small set -> click-to-cycle (fast); big set -> predictive text input.
          -- Author can force with field.input = "cycle" | "text".
          local asCycle = (f.input == "cycle") or (f.input ~= "text" and nvals > 0 and nvals <= (f.cycleMax or 8))
          local cur = rec[f.path]
          if cur == nil and f.values and f.values[1] ~= nil then cur = Schemas.enumValue(f.values[1]) end
          if asCycle then
            local lbl = UI.mkText(inst.widgetTree, inst.textTemplate, f.label or f.path, 15)
            if lbl then UI.canvasAdd(canvas, lbl, 60, y + 8, 300, 32, 1) end
            local act = { type = "recField", tab = ti, target = target, key = key, path = f.path, values = f.values, field = f }
            local btn = UI.nativeButton(inst.menu, Schemas.enumDisplay(f, cur), inst.actions, act)
            if btn then UI.canvasAdd(canvas, btn, 380, y, 220, 44, 1); act.button = btn end
          else
            local lbl = UI.mkText(inst.widgetTree, inst.textTemplate, (f.label or f.path) .. "  (type to search)", 14)
            if lbl then pcall(function() lbl:SetAutoWrapText(true) end); UI.canvasAdd(canvas, lbl, 60, y + 4, 300, 40, 1) end
            local box = UI.mkEdit(inst.widgetTree, tostring(cur))
            if box then UI.canvasAdd(canvas, box, 380, y + 2, 260, 40, 1) end
            ts.recFields[#ts.recFields + 1] = { box = box, key = key, path = f.path, field = f, target = target }
            ts.predBoxes[#ts.predBoxes + 1] = { box = box, x = 380, y = y + 2, field = f, canvas = canvas }
          end
          y = y + ROW_H
        elseif f.kind == "list" then
          local lbl = UI.mkText(inst.widgetTree, inst.textTemplate, f.label or f.path, 15, 0.85)
          if lbl then UI.canvasAdd(canvas, lbl, 60, y + 6, 500, 30, 1) end
          y = y + 38
          local list = rec[f.path]; if type(list) ~= "table" then list = {}; rec[f.path] = list end
          for i, item in ipairs(list) do
            local it = UI.mkText(inst.widgetTree, inst.textTemplate, "- " .. tostring(item), 14, 0.9)
            if it then UI.canvasAdd(canvas, it, 90, y + 6, 470, 30, 1) end
            local xb = UI.nativeButton(inst.menu, "X", inst.actions,
              { type = "recItemRemove", tab = ti, target = target, key = key, path = f.path, index = i })
            if xb then UI.canvasAdd(canvas, xb, 570, y, 44, 40, 1) end
            y = y + 44
          end
          local ib = UI.mkEdit(inst.widgetTree, "")
          if ib then
            UI.canvasAdd(canvas, ib, 90, y + 4, 320, 40, 1)
            if type(f.values) == "table" then
              -- addTo lets a dropdown PICK add straight to the list (and clear the
              -- box) instead of parking text in the input -- controller-friendly.
              ts.predBoxes[#ts.predBoxes + 1] = { box = ib, x = 90, y = y + 4, field = f, canvas = canvas,
                addTo = { tab = ti, target = target, key = key, path = f.path, numeric = f.numeric, field = f } }
            end
          end
          local ab = UI.nativeButton(inst.menu, f.addLabel or "Add", inst.actions,
            { type = "recItemAdd", tab = ti, target = target, key = key, path = f.path,
              numeric = f.numeric, field = f, box = ib })
          if ab then UI.canvasAdd(canvas, ab, 425, y, 150, 44, 1) end
          y = y + ROW_H
        end
      end
    end

    local line = UI.construct("/Script/UMG.Image", inst.widgetTree)
    if line then
      pcall(function() line:SetColorAndOpacity({ R = 1, G = 1, B = 1, A = 0.14 }) end)
      UI.canvasAdd(canvas, line, 30, y + 6, PANEL_W - 120, 2, 1)
    end
    y = y + 18
  end
  return y
end

-- ============================================================================
-- OTHER MODS (read-only browser). Lists UE4SS Lua mods that did NOT register a
-- DarnMenu schema but have a Scripts/config.lua, and lets the player jump to the
-- file. READ-ONLY by design: we never execute or rewrite another mod's config --
-- just a raw text preview and an "Open in Explorer" button for manual editing.
-- ============================================================================
local MODS_ABS = tostring(DIR):gsub("[^/\\]+[/\\][^/\\]+[/\\]$", "")   -- ".../Mods/" (strip "DarnMenu/Scripts/")

local function fileExists(p) local f = io.open(p, "r"); if f then f:close(); return true end return false end

-- mods don't agree on where/what a config file is named -- check the common ones and
-- return the first that exists (Scripts/config.lua, root user_config.lua, etc.). nil = none.
local function findConfig(name)
  local base = MODS_ABS .. name .. "/"
  local candidates = {
    "Scripts/config.lua", "Scripts/user_config.lua", "Scripts/Config.lua", "Scripts/settings.lua",
    "config.lua", "user_config.lua", "Config.lua", "settings.lua",
  }
  for _, rel in ipairs(candidates) do
    if fileExists(base .. rel) then return base .. rel end
  end
  return nil
end

local function previewLines(path, n)
  local out = {}
  local f = io.open(path, "r"); if not f then return out end
  local i = 0
  for line in f:lines() do
    i = i + 1
    if i > (n or 10) then out[#out + 1] = "  ..."; break end
    out[#out + 1] = (#line > 92) and (line:sub(1, 92) .. "…") or line
  end
  f:close()
  return out
end

-- The Lua mods UE4SS actually LOADED this session, read from its own log -- the
-- authoritative record (no shell-out, so no console flash). Catches both the modern
-- "has enabled.txt, starting mod" line and the mods.txt "Starting Lua mod 'X'" line.
local function loadedMods()
  local out, seen = {}, {}
  local f = io.open(MODS_ABS .. "../UE4SS.log", "r")   -- ...ue4ss/UE4SS.log (one up from Mods)
  if not f then return out end
  for line in f:lines() do
    local n = line:match("Mod '([%w_%.%-]+)' has enabled%.txt, starting mod")
           or line:match("Starting Lua mod '([%w_%.%-]+)'")
    if n and not seen[n] then seen[n] = true; out[#out + 1] = n end
  end
  f:close()
  return out
end

-- Discover LOADED UE4SS Lua mods that (a) did NOT register a DarnMenu schema and are not
-- infrastructure, and (b) have a recognizable config file. Cached once per session.
local _discovered
local function discoverOtherMods(schemas)
  if _discovered then return _discovered end
  local excluded = {
    DarnMenu = true, DarnToasts = true, shared = true, Keybinds = true,
    PalSchema = true, BPModLoaderMod = true, BPML_GenericFunctions = true,
    AutomaticallySkipModCaution = true,
  }
  for _, s in ipairs(schemas or {}) do
    if s.target then excluded[(tostring(s.target):gsub("_user$", ""))] = true end
  end
  local found = {}
  for _, name in ipairs(loadedMods()) do
    if not excluded[name] then
      local cfg = findConfig(name)
      if cfg then found[#found + 1] = { name = name, path = cfg, winPath = cfg:gsub("/", "\\") } end
    end
  end
  table.sort(found, function(a, b) return a.name < b.name end)
  _discovered = found
  return found
end

local function buildModBrowserSection(inst, ti, canvas, y, custom)
  local mods = custom.mods or {}
  if #mods == 0 then
    local e = UI.mkText(inst.widgetTree, inst.textTemplate, "No other config.lua mods detected.", 15, 0.6)
    if e then UI.canvasAdd(canvas, e, 20, y + 4, 900, 28, 1) end
    return y + 40
  end
  for _, m in ipairs(mods) do
    local hdr = UI.mkText(inst.widgetTree, inst.textTemplate, m.name, 18)
    if hdr then UI.canvasAdd(canvas, hdr, 20, y, 500, 30, 1) end
    local btn = UI.nativeButton(inst.menu, "Open config file", inst.actions,
      { type = "openFile", path = m.winPath, name = m.name })
    if btn then UI.canvasAdd(canvas, btn, 560, y - 4, 240, 44, 1) end
    y = y + 40
    for _, ln in ipairs(previewLines(m.path, 10)) do
      local t = UI.mkText(inst.widgetTree, inst.textTemplate, ln, 12, 0.55)
      if t then UI.canvasAdd(canvas, t, 40, y, PANEL_W - 120, 20, 1) end
      y = y + 17
    end
    local line = UI.construct("/Script/UMG.Image", inst.widgetTree)
    if line then
      pcall(function() line:SetColorAndOpacity({ R = 1, G = 1, B = 1, A = 0.14 }) end)
      UI.canvasAdd(canvas, line, 30, y + 8, PANEL_W - 120, 2, 1)
    end
    y = y + 24
  end
  return y
end

-- ============================================================================
-- ACTION PANEL (custom = { type = "actionpanel" }). A styled, CLICKABLE panel a
-- mod declares to expose a small in-menu action: it reads a STATUS the mod wrote
-- to a shared bridge file (which target/how many stars/whether it's eligible)
-- and offers one clickable tile per allowed option. A click writes a one-shot
-- REQUEST back to that file (runAction "actionPick"); the mod acts on it once.
-- DarnMenu never runs the action itself -- it only shows status and relays picks.
-- First consumer: Living Arsenal's weapon Prestige.
-- ============================================================================
local function buildActionPanelSection(inst, ti, canvas, y, custom)
  -- same schema-supplied name as the write side (runAction "actionPick") -- sandbox
  -- the READ too, so a crafted name cannot make the page slurp a file outside shared/.
  local fpath = sharedPath(custom.file, ".lua")
  local data = (fpath and Writers.read(fpath)) or {}
  local status = data[custom.statusKey or "status"]
  local eligible = type(status) == "table" and status.eligible == true

  -- backing panel
  local box = UI.construct("/Script/UMG.Image", inst.widgetTree)
  if box then
    pcall(function() box:SetColorAndOpacity({ R = 1, G = 1, B = 1, A = 0.06 }) end)
    UI.canvasAdd(canvas, box, 10, y, PANEL_W - 60, 150, 1)
  end

  -- header line: target weapon + level + stars, or the empty message
  local head
  if type(status) == "table" and status.weapon then
    local stars = tonumber(status.stars) or 0
    -- status.summary (optional, consumer-written): the cumulative effect of the banked
    -- points ("\226\152\1333   +15% dmg   +2 mag"). It starts with the star count, so when
    -- present it REPLACES the bare star suffix rather than stacking a second star glyph.
    local tail = (type(status.summary) == "string" and status.summary ~= "" and ("   " .. status.summary))
              or ((stars > 0) and ("   \226\152\133" .. stars) or "")
    head = string.format("%s   Lv %s  (prestige at %s)%s", tostring(status.name or status.weapon),
      tostring(status.level or "?"), tostring(status.need or "?"), tail)
  else
    head = custom.emptyText or "No target."
  end
  local ht = UI.mkText(inst.widgetTree, inst.textTemplate, head, 18)
  if ht then UI.canvasAdd(canvas, ht, 30, y + 12, PANEL_W - 120, 32, 1) end
  local hint = eligible and "Ready -- pick a stat to bank a permanent point:"
                        or ("Not yet -- level this weapon to Lv " .. tostring((type(status) == "table" and status.need) or "?") .. " in play, then come back.")
  local hn = UI.mkText(inst.widgetTree, inst.textTemplate, hint, 13, 0.6)
  if hn then pcall(function() hn:SetAutoWrapText(true) end); UI.canvasAdd(canvas, hn, 30, y + 46, PANEL_W - 120, 24, 1) end

  -- tiles: only options the status permits; clickable only when eligible
  local allow = {}
  if type(status) == "table" and type(status.allowed) == "table" then
    for _, v in ipairs(status.allowed) do allow[tostring(v)] = true end
  end
  local tx, ty = 30, y + 88
  for _, opt in ipairs(custom.options or {}) do
    if allow[tostring(opt.value)] then
      if tx + 205 > PANEL_W - 60 then tx = 30; ty = ty + 56 end   -- wrap if the row is full
      if eligible then
        local btn = UI.nativeButton(inst.menu, opt.label, inst.actions,
          -- custom.file, NOT a bare `file`: that was a nil GLOBAL, so every tile carried
          -- file=nil, sharedPath(nil) refused it, and the press answered "that mod's action
          -- file name isn't allowed". The whole action panel has been dead since it shipped --
          -- the tiles drew, and not one of them could ever write its request.
          -- `tab` is carried so the rejection path can NAME the mod whose schema was refused.
          -- The one report of this message (Lolida, LA prestige) could not be attributed from
          -- the log line alone -- it said only file=nil, and any installed mod could own it.
          { type = "actionPick", tab = ti, file = custom.file,
            requestKey = custom.requestKey or "request",
            value = opt.value, label = opt.label })
        if btn then UI.canvasAdd(canvas, btn, tx, ty, 205, 48, 1) end
      else
        local t = UI.mkText(inst.widgetTree, inst.textTemplate, opt.label, 14, 0.35)
        if t then UI.canvasAdd(canvas, t, tx + 8, ty + 10, 205, 30, 1) end
      end
      tx = tx + 214
    end
  end
  return math.max(y + 165, ty + 64)
end

local function buildModPanel(inst, schema, ti)
  local scroll = UI.construct("/Script/UMG.ScrollBox", inst.widgetTree)
  if not scroll then return nil end
  -- BORN HIDDEN, ATTACH-FIRST (2026-07-23: the detached-build experiment --
  -- populate off-page, attach on success -- correlated with two CTDs in native
  -- Slate frames and was reverted the same hour; attach-first ran stably for
  -- days). Hidden at birth = no flash. Orphan cleanup for EVERY failure path
  -- lives in ensurePanel via inst._buildingScroll: graceful bails clean up here,
  -- thrown errors clean up there.
  UI.setVis(scroll, VIS.HIDE)
  inst._buildingScroll = scroll
  -- read-only tabs (Other Mods) carry no footer buttons, so the panel reclaims that room
  local panelH = (schema.otherMod and PANEL_H + 85) or PANEL_H
  UI.canvasAdd(inst.content, scroll, PANEL_X, PANEL_Y, PANEL_W, panelH, 1)
  local function bail()
    UI.remove(scroll)
    inst._buildingScroll = nil
    return nil
  end
  local height = 20
  -- page-level note (documented top-of-page text) renders above the sections; it
  -- wraps, so estimate its rows from length (~110 chars/row at PANEL_W-80).
  local noteText = type(schema.note) == "string" and schema.note ~= "" and schema.note or nil
  -- MOD VERSION ON THE PAGE (2026-07-31, Mikey: "include a version in the display").
  -- Support's first question is "what version are you on?", and until now the only answers
  -- were log excavation or Info.json spelunking. Read LIVE from the mod's own Info.json at
  -- panel build -- never from the schema, which persists across mod updates and would show
  -- a stale number. regName is the registered schema name (== the mod's folder); older
  -- schema files without it fall back to the sandboxed target minus its _user suffix.
  do
    local folder = (not schema.otherMod) and modFolderOf(schema) or nil
    if folder then
      local f = io.open(DIR .. "../../" .. folder .. "/Info.json", "r")
      if f then
        local body = f:read("*a") or ""
        f:close()
        local v = body:match('"Version"%s*:%s*"([^"]*)"')
        if v and v ~= "" then
          noteText = "Version " .. v .. (noteText and ("   |   " .. noteText) or "")
        end
      end
    end
  end
  if noteText then height = height + 24 + math.max(1, math.ceil(#noteText / 110)) * 22 end
  -- room for the ghost-page notice + its Remove button (see the render below)
  if schema.ghostPage then height = height + 108 end
  for _, sec in ipairs(schema.sections) do
    height = height + SECTION_H
    -- A COLLAPSED SECTION IS ONLY ITS HEADER. This estimate drives the scroll box's height, so
    -- leaving folded sections in it would give the page a long empty tail to scroll through --
    -- which is most of what collapsing was supposed to remove.
    local tsH = inst.tabs[ti]
    local secKeyH = tostring(sec.title or "")
    if tsH and tsH.secClosed and tsH.secClosed[secKeyH] then goto nextHeight end
    if type(sec.custom) == "table" and sec.custom.type == "listfile" then
      -- SIZE TO THE REAL LIST, not to the cap: the SizeBox is what the ScrollBox scrolls, so
      -- estimating BL_ROWS*44 left a screen of dead space under a short list and (once the cap
      -- rose) a box far taller than anything in it.
      local blN = #readBlacklist(listfilePath(sec.custom.file) or "")
      height = height + 34 + math.max(1, math.min(blN, BL_ROWS)) * 44 + 10
    elseif type(sec.custom) == "table" and sec.custom.type == "records" then
      -- records have no `options`; without a real estimate the box is sized for
      -- almost nothing and only the post-render SetHeightOverride below rescues it.
      -- Estimate it up front too: add-row + one collapsed header (~50px) per
      -- persisted key + field rows for any currently-expanded one.
      local recs = recordsFor(inst, ti, sec.custom.target)
      local ts = inst.tabs[ti]
      local nKeys, nf = 0, #(sec.custom.fields or {})
      for k in pairs(recs) do
        nKeys = nKeys + 1
        if ts and ts.expanded and ts.expanded[k] then height = height + nf * ROW_H end
      end
      height = height + ROW_H + 40 + nKeys * 50
    elseif type(sec.custom) == "table" and sec.custom.type == "modbrowser" then
      height = height + #(sec.custom.mods or {}) * 220
    elseif type(sec.custom) == "table" and sec.custom.type == "actionpanel" then
      height = height + 175
    else
      for _, opt in ipairs(sec.options or {}) do
        -- value-dependent rows that do not apply to the CURRENT choice are
        -- HIDDEN, not dimmed (by order): they neither render nor take height
        if not (opt.dependsValue ~= nil and not depSatisfied(inst, ti, opt)) then
          height = height + (opt.divider and 38 or (opt.subtitle and 94 or optRowH(opt)))
        end
      end
    end
    ::nextHeight::
  end
  local sizeBox = UI.construct("/Script/UMG.SizeBox", inst.widgetTree)
  local canvas = UI.construct("/Script/UMG.CanvasPanel", inst.widgetTree)
  if not sizeBox or not canvas then return bail() end
  local ok = pcall(function()
    scroll:AddChild(sizeBox)
    sizeBox:SetWidthOverride(PANEL_W - 40)
    sizeBox:SetHeightOverride(height)
    sizeBox:AddChild(canvas)
  end)
  if not ok then return bail() end

  -- records registries are rebuilt fresh with the panel
  inst.tabs[ti].recFields = {}
  inst.tabs[ti].predBoxes = {}
  inst.tabs[ti].recHeaders = {}      -- key -> accordion header button (focus restore)
  inst.tabs[ti].scrollCanvas = canvas -- the scroll's inner canvas (controller auto-scroll guard)

  local y = 0
  -- page-level note: the documented "top of your page" text (schema.note) -- long
  -- a dead field until 1.4.2; now rendered here, AutoWrapped so it can't overflow.
  if noteText then
    local n = UI.mkText(inst.widgetTree, inst.textTemplate, noteText, 14, 0.7)
    if n then
      pcall(function() n:SetAutoWrapText(true) end)
      UI.canvasAdd(canvas, n, 0, y + 6, PANEL_W - 80, 60, 1)
      y = y + 24 + math.max(1, math.ceil(#noteText / 110)) * 22
    end
  end
  -- GHOST PAGE: the mod this page belongs to is not installed any more (see modMissing). The
  -- page is left fully usable -- the player may be mid-reinstall -- but it says so, and offers
  -- the one thing they actually asked for: a way to make it go away. Scoped to THIS page; there
  -- is deliberately no bulk sweep, because one wrong liveness verdict times ten pages is a
  -- different kind of bug report. Block-scoped so the widgets do not hold locals open across
  -- the rest of this function.
  if schema.ghostPage then
    do
      local warn = UI.mkText(inst.widgetTree, inst.textTemplate,
        "This mod is no longer installed -- its page is left over. Removing the page keeps your "
        .. "settings file; reinstalling the mod brings the page back.", 14, 0.7)
      if warn then
        pcall(function() warn:SetAutoWrapText(true) end)
        UI.setVis(warn, VIS.PASSIVE)   -- text over a button area is hit-testable unless passive
        UI.canvasAdd(canvas, warn, 0, y + 4, PANEL_W - 80, 48, 1)
      end
      local rm = UI.nativeButton(inst.menu, "Remove this page", inst.actions,
        { type = "pageRemove", tab = ti, name = schema.regName })
      if rm then UI.canvasAdd(canvas, rm, 0, y + 52, 320, 48, 1) end
    end
    y = y + 108
  end
  for si, sec in ipairs(schema.sections) do
    -- COLLAPSIBLE SECTIONS.
    --
    -- A page with three or four groups of position sliders is mostly scrolling, and the group
    -- a player wants is rarely the one on screen. The header is a button now: click it to fold
    -- the section away. Same mechanism the records list has always used -- state on the tab,
    -- then rebuild the panel -- rather than a second way of doing the same thing.
    --
    -- Default is EXPANDED, so no shipped page changes shape unless its schema asks. A section
    -- opts in with `collapsed = true`, which means "start folded", not "cannot be opened".
    local ts0 = inst.tabs[ti]
    ts0.secClosed = ts0.secClosed or {}
    local secKey = tostring(sec.title or ("section " .. si))
    if ts0.secClosed[secKey] == nil then
      local mem = secFolds[tostring(schema.tab or "") .. "|" .. secKey]
      if mem ~= nil then ts0.secClosed[secKey] = mem
      else ts0.secClosed[secKey] = (sec.collapsed == true) end
    end
    local closed = ts0.secClosed[secKey] == true
    -- The arrow carries the state: a bare title gives no hint that it can be clicked, and no
    -- hint that something is hidden below it.
    -- A BOXED CHEVRON, not a bare character. The same shape the keycap controls already use --
    -- a tinted panel with a glyph on it -- so an expander reads as a thing you press rather
    -- than as punctuation that happened to land at the start of a title.
    local head = UI.nativeButton(inst.menu, "        " .. tostring(sec.title or ""),
                                 inst.actions, { type = "secToggle", tab = ti, key = secKey })
    if head then
      UI.canvasAdd(canvas, head, 0, y + 6, 560, 44, 1)
      local chip = UI.mkImage(inst.widgetTree)
      if chip then
        pcall(function()
          chip:SetColorAndOpacity(closed and { R = 0.20, G = 0.24, B = 0.30, A = 1 }
                                          or { R = 0.29, G = 0.55, B = 0.78, A = 1 })
        end)
        UI.canvasAdd(canvas, chip, 10, y + 14, 28, 28, 2)
      end
      -- the glyph itself sits on the chip: v when open, > when closed
      local gl = UI.mkText(inst.widgetTree, inst.textTemplate, closed and ">" or "v", 18)
      if gl then UI.canvasAdd(canvas, gl, 18, y + 14, 24, 28, 3) end
    end
    y = y + SECTION_H
    if closed then goto nextSection end
    if type(sec.custom) == "table" and sec.custom.type == "listfile" then
      local path = listfilePath(sec.custom.file)
      if path then
        inst.tabs[ti].blFile = path
        inst.tabs[ti].blEmpty = sec.custom.empty
        -- what KIND of id this file holds, so the rows can read as words (see listLabel)
        inst.tabs[ti].blNames = sec.custom.names
        y = buildBlacklistSection(inst, ti, canvas, y)
      else
        log("listfile rejected for '" .. schema.tab .. "': file=" .. tostring(sec.custom.file)
          .. " -- must be a plain name ending .txt (no slashes, no ..), living directly in shared/")
      end
    elseif type(sec.custom) == "table" and sec.custom.type == "records"
           and type(sec.custom.target) == "string" and type(sec.custom.fields) == "table" then
      y = buildRecordsSection(inst, ti, canvas, y, sec.custom)
    elseif type(sec.custom) == "table" and sec.custom.type == "modbrowser" then
      y = buildModBrowserSection(inst, ti, canvas, y, sec.custom)
    elseif type(sec.custom) == "table" and sec.custom.type == "actionpanel" then
      y = buildActionPanelSection(inst, ti, canvas, y, sec.custom)
    else
      for _, opt in ipairs(sec.options or {}) do
        if opt.dependsValue ~= nil and not depSatisfied(inst, ti, opt) then
          -- hidden: not applicable to the current choice; the enum's cycle
          -- action rebuilds this panel, which is when it can reappear
        elseif opt.divider then
          local line = UI.construct("/Script/UMG.Image", inst.widgetTree)
          if line then
            pcall(function() line:SetColorAndOpacity({ R = 1, G = 1, B = 1, A = 0.22 }) end)
            UI.canvasAdd(canvas, line, 20, y + 20, PANEL_W - 100, 2, 1)
          end
          y = y + 38
        elseif opt.subtitle then
          local sub = UI.mkText(inst.widgetTree, inst.textTemplate, opt.subtitle, 17)
          if sub then UI.canvasAdd(canvas, sub, 20, y + 8, 900, 28, 1) end
          if opt.help then
            local h = UI.mkText(inst.widgetTree, inst.textTemplate, opt.help, 13, 0.55)
            if h then
              pcall(function() h:SetAutoWrapText(true) end)
              UI.canvasAdd(canvas, h, 20, y + 41, 900, 46, 1)
            end
          end
          y = y + 94
        else
          local labelText = opt.label or opt.path
          -- author's note wins; else auto-show declared bounds (min/max/integer,
          -- maxLen/minLen) so players see limits BEFORE tripping validation
          local noteText = opt.note or Schemas.constraintNote(opt)
          if noteText then labelText = labelText .. " (" .. noteText .. ")" end
          -- TextBlocks don't clip: long labels (esp. with auto-bounds notes) would
          -- overflow under the control at x=380 -- wrap inside the column, and step
          -- the font down as labels get longer so two lines read as one row
          local lsize = (#labelText > 46 and 13) or (#labelText > 30 and 14) or 16
          local label = UI.mkText(inst.widgetTree, inst.textTemplate, labelText, lsize)
          -- relaunch marker (VirtualBjorn): needs-relaunch settings get the game's
          -- NoticeMark icon tinted RED, and the label indents to leave room. There is
          -- NO "applies now" marker -- the ABSENCE of the icon means it applies now.
          local restartReq = (optLive(schema, opt) == false)
          if label then
            pcall(function() label:SetAutoWrapText(true) end)
            UI.canvasAdd(canvas, label, restartReq and 48 or 20, y + 6, restartReq and 322 or 350, 42, 1)
          end
          local liveIcon = nil
          if restartReq then
            liveIcon = UI.mkImage(inst.widgetTree)
            if liveIcon and UI.setImageAsset(liveIcon, RESTART_ICON) then
              pcall(function() liveIcon:SetColorAndOpacity(RESTART_TINT) end)
              UI.canvasAdd(canvas, liveIcon, 8, y + 8, 32, 32, 2)
            elseif liveIcon then
              UI.remove(liveIcon); liveIcon = nil
            end
          end
          local ctl = { opt = opt, label = label, liveIcon = liveIcon }
          if opt.kind == "bool" then
            ctl.button = UI.nativeButton(inst.menu, "", inst.actions, { type = "toggle", tab = ti, path = opt.path })
            if not ctl.button then return bail() end
            UI.canvasAdd(canvas, ctl.button, 380, y, 260, 48, 1)
            -- the switch sits ON the button, so the whole row stays one click target
            ctl.swY = y + 12
            ctl.swTrack = UI.mkImage(inst.widgetTree)
            if ctl.swTrack then UI.canvasAdd(canvas, ctl.swTrack, SW_X, ctl.swY, SW_W, SW_H, 2) end
            ctl.swKnob = UI.mkImage(inst.widgetTree)
            if ctl.swKnob then
              pcall(function() ctl.swKnob:SetColorAndOpacity(SW_KNOB) end)
              UI.canvasAdd(canvas, ctl.swKnob, SW_X + 2, ctl.swY + 2, SW_KNOB_W, SW_H - 4, 3)
            end
          elseif opt.kind == "enum" then
            ctl.button = UI.nativeButton(inst.menu, "", inst.actions, { type = "cycle", tab = ti, path = opt.path })
            if not ctl.button then return bail() end
            UI.canvasAdd(canvas, ctl.button, 380, y, 260, 48, 1)
          elseif opt.kind == "keycapture" then
            ctl.button = UI.nativeButton(inst.menu, "", inst.actions, { type = "keycap", tab = ti, path = opt.path })
            if not ctl.button then return bail() end
            UI.canvasAdd(canvas, ctl.button, 380, y, 260, 48, 1)
            ctl.keyIcon = UI.mkKeycapImage(inst.widgetTree)   -- keyguide icon over the button (VirtualBjorn)
            if ctl.keyIcon then UI.canvasAdd(canvas, ctl.keyIcon, 494, y + 8, 32, 32, 2) end
          elseif opt.kind == "keychord" then
            -- 3 modifier toggle cells (CTRL/ALT/SHIFT, dimmed when off) + the primary keycap
            ctl.modButtons, ctl.modIcons = {}, {}
            for mi, modifier in ipairs(MODIFIER_ORDER) do
              local mx = 380 + ((mi - 1) * 54)
              local mbtn = UI.nativeButton(inst.menu, "", inst.actions, { type = "chordmod", tab = ti, path = opt.path, modifier = modifier })
              local micon = UI.mkKeycapImage(inst.widgetTree)
              if not (mbtn and micon) then return bail() end
              ctl.modButtons[modifier] = mbtn
              ctl.modIcons[modifier] = micon
              UI.canvasAdd(canvas, mbtn, mx, y, 48, 48, 1)
              UI.canvasAdd(canvas, micon, mx + 8, y + 8, 32, 32, 2)
            end
            ctl.button = UI.nativeButton(inst.menu, "", inst.actions, { type = "keycap", tab = ti, path = opt.path })
            ctl.keyIcon = UI.mkKeycapImage(inst.widgetTree)
            if not (ctl.button and ctl.keyIcon) then return bail() end
            -- Wider primary-key target: enough room for "Press a key..." without
            -- clipping while capture is active.
            UI.canvasAdd(canvas, ctl.button, 542, y, 176, 48, 1)
            UI.canvasAdd(canvas, ctl.keyIcon, 614, y + 8, 32, 32, 2)
            ctl.defaultValue = (schema.defaults or {})[opt.path]
            if ctl.defaultValue ~= nil then
              ctl.resetButton = UI.nativeButton(inst.menu, "", inst.actions, {
                type = "keyreset", tab = ti, path = opt.path,
              })
              ctl.resetIcon = UI.mkImage(inst.widgetTree)
              -- A MISSING ICON COSTS THE BUTTON, NEVER THE PAGE (README rule 5). This
              -- bailed the whole panel build if T_prt_KeyGuide_change failed to resolve
              -- -- one renamed texture in a game patch and Mod Options would be empty.
              -- Same shape as the RESTART_ICON legend: build it if it resolves, drop it
              -- if it doesn't, and the row still works without the restore shortcut.
              if ctl.resetButton and ctl.resetIcon and UI.setImageAsset(ctl.resetIcon, KEY_RESET_ICON) then
                UI.canvasAdd(canvas, ctl.resetButton, 726, y, 48, 48, 1)
                UI.canvasAdd(canvas, ctl.resetIcon, 734, y + 8, 32, 32, 2)
                UI.setVis(ctl.resetButton, VIS.HIDE)
                UI.setVis(ctl.resetIcon, VIS.HIDE)
              else
                -- Drop the actions[addr] entry as we discard the button: UMG recycles
                -- widget addresses, so a leftover entry can hijack a later click (the
                -- codebase's recycled-address hazard -- same reason clearPred does it).
                local ra = ctl.resetButton and UI.addr(ctl.resetButton)
                if ra then inst.actions[ra] = nil end
                UI.remove(ctl.resetButton); UI.remove(ctl.resetIcon)
                ctl.resetButton, ctl.resetIcon = nil, nil
              end
            end
          elseif opt.kind == "number" and tonumber(opt.step) then
            -- stepper: - [edit] + ; same 380..640 zone the other controls use
            ctl.minus = UI.nativeButton(inst.menu, "-", inst.actions, { type = "step", tab = ti, path = opt.path, dir = -1 })
            ctl.plus  = UI.nativeButton(inst.menu, "+", inst.actions, { type = "step", tab = ti, path = opt.path, dir = 1 })
            ctl.input = UI.mkEdit(inst.widgetTree, "")
            if not (ctl.minus and ctl.plus and ctl.input) then return bail() end
            UI.canvasAdd(canvas, ctl.minus, 380, y, 44, 48, 1)
            UI.canvasAdd(canvas, ctl.input, 430, y + 4, 160, 40, 1)
            UI.canvasAdd(canvas, ctl.plus, 596, y, 44, 48, 1)
          else
            ctl.input = UI.mkEdit(inst.widgetTree, "")
            if not ctl.input then return bail() end
            UI.canvasAdd(canvas, ctl.input, 420, y + 4, 220, 40, 1)
          end
          if opt.help then
            ctl.help = UI.mkText(inst.widgetTree, inst.textTemplate, opt.help, 12, 0.55)
            if ctl.help then
              pcall(function() ctl.help:SetAutoWrapText(true) end)
              local helpX = (opt.kind == "keychord") and 790 or 670
              UI.canvasAdd(canvas, ctl.help, helpX, y + 6, PANEL_W - helpX - 50, 44, 1)
            end
          end
          inst.tabs[ti].controls[opt.path] = ctl
          y = y + optRowH(opt)
        end
      end
    end
    ::nextSection::
  end
  -- SCROLL FIX: the height at line ~575 is an ESTIMATE and does not know about
  -- records sections (dynamic, variable height), so a tall records page could not
  -- scroll to its overflow. Re-size the SizeBox to the ACTUAL accumulated height
  -- now that everything is laid out -- correct for any content, records included.
  -- TRAILING ROOM, sized to what actually needs it. The last control sits at the
  -- content edge, so with no slack below it the panel can't scroll it up to centre --
  -- and a dropdown it opens renders off the bottom (unfocusable), so "down" leaks to
  -- Apply/Back instead of into the suggestions. That is why this was a half viewport.
  -- But only pages with a predictive box can open a dropdown, and on every other page
  -- that half viewport is ~310px of empty scrolling (VirtualBjorn, correctly, called
  -- it excess -- his fix was a flat 16, which brings the dropdown bug straight back).
  -- So: pad by the dropdown's own max height where a dropdown is possible, 16 where it
  -- is not. UI.suggestList's maxH is 300; +20 keeps a margin under the last row.
  local bottomPad = (#((inst.tabs[ti] or {}).predBoxes or {}) > 0) and 320 or 16
  pcall(function() sizeBox:SetHeightOverride(math.max(height, y + 40) + bottomPad) end)
  inst._buildingScroll = nil   -- built clean; nothing for ensurePanel to reap
  return scroll
end

ensurePanel = function(inst, ti)
  if not (UI.alive(inst.menu) and UI.alive(inst.widgetTree)) then return nil end  -- stale menu: don't build into a freed tree
  local tabState = inst.tabs[ti]
  if not tabState or inst.tabPanels[ti] or tabState.panelFailed then return inst.tabPanels[ti] end
  local ok, panel = pcall(buildModPanel, inst, tabState.schema, ti)
  if ok and panel then
    inst.tabPanels[ti] = panel
    UI.setVis(panel, VIS.HIDE)
    refreshTab(inst, ti)
    refreshBlacklist(inst, ti)
  else
    tabState.panelFailed = true
    -- reap the half-attached subtree on ANY failure -- incl. a THROW, which
    -- skips buildModPanel's own bail() (this pcall ate the error). Without
    -- this, the orphan draws over the real panel and steals its clicks.
    if inst._buildingScroll then
      UI.remove(inst._buildingScroll)
      inst._buildingScroll = nil
    end
    log("panel build failed for '" .. tabState.schema.tab .. "' (cleaned up): " .. tostring(panel))
  end
  return inst.tabPanels[ti]
end

-- Rebuild one mod's panel in place. A records add/remove changes the panel's
-- height, and the flat-canvas layout has no reflow -- so tear the scroll down and
-- rebuild it from the mutated staged state, then re-show it. Scalar controls
-- re-seed from staged/values, so their saved-but-unapplied box text is not lost;
-- only raw typed-not-committed number text would reset (acceptable for v1).
-- PREDICTIVE TEXT. While a records text box (an enum field, or a list-add box that
-- declares a `values` set) has keyboard focus, a poll loop shows up to 8 matching
-- values beneath it as clickable suggestions -- so a 40+ enum is typed-and-filtered,
-- never clicked through. No text-change delegate exists in this codebase, so we
-- POLL the focused box's text every ~200ms (the same ExecuteWithDelay pattern the
-- close-watchdog uses). Suggestions are children of the same scrolled canvas at a
-- high z-order; cleared on blur, on pick, and on every rebuild. A token stops a
-- stale loop if the page reopens.
-- remove the suggestion buttons AND drop their entries from inst.actions. That
-- second part is essential: UMG recycles widget addresses, so a leftover
-- actions[addr] from a torn-down suggestion can hijack a later click (the
-- codebase's known recycled-address hazard). Clean as we remove.
-- The predictive/filter dropdown widget now lives in DarnUI (UI.suggestList) -- created
-- + started per page in buildPage (inst.predSuggest). clearPred stays as a thin wrapper
-- so its callers (rebuildPanel, predPick, onStackClose) don't need to know the controller.
local function clearPred(inst)
  if inst.predSuggest then inst.predSuggest:clear() end
end

-- Every edit widget on this instance -- the predictive/filter boxes plus the plain
-- text inputs, across ALL tabs (a panel we've switched away from can still hold
-- focus). Shared traversal: feeds both focusedEdit and the backspace-close guard.
local function editWidgets(inst)
  local out = {}
  for _, ts in ipairs(inst.tabs or {}) do
    for _, pb in ipairs(ts.predBoxes or {}) do
      if UI.alive(pb.box) then out[#out + 1] = pb.box end
    end
    for _, ctl in pairs(ts.controls or {}) do
      if ctl.input and UI.alive(ctl.input) then out[#out + 1] = ctl.input end
    end
  end
  return out
end

local closePage   -- fwd decl: defined below, used by buildPage's close watchdog

-- CONTROLLER AUTO-SCROLL. CommonUI moves focus between our buttons for free, but
-- the ScrollBox doesn't follow focus off-screen -- so nav "stops at the last
-- visible element". Every ~150ms, find the focused menu button and scroll it into
-- view in the active panel's ScrollBox, so pushing the stick reveals the next
-- control instead of dead-ending.
local function focusProbe(inst, tok)
  if inst.disposed or not inst.pageOpen or inst.focusTok ~= tok then return end
  -- mid-map-swap: FindAllOf + focus reads over the whole button tree is the single
  -- most object-touching thing this file does on a timer. Pause, keep the loop.
  if worldGone() then ExecuteWithDelay(120, function() focusProbe(inst, tok) end); return end
  pcall(function()
    local btns = FindAllOf("WBP_MenuESC_Button_S_C") or {}
    local focusedBtn = nil
    for _, b in ipairs(btns) do
      if UI.alive(b) then
        local hasF = safe(function() return b.WBP_PalInvisibleButton:HasKeyboardFocus() end) == true
          or safe(function() return b:HasFocusedDescendants() end) == true
          or safe(function() return b:HasAnyUserFocus() end) == true
        if hasF then focusedBtn = b end
      end
    end
    -- Only act when focus MOVED (no jitter on a stable selection). MANUAL scroll:
    -- ScrollWidgetIntoView proved intermittent on this hand-built canvas, so read
    -- the focused control's REAL y from its canvas slot and set the offset so it
    -- sits inside the viewport. Guarded to buttons that are DIRECT children of the
    -- scroll canvas (a list tab / Apply / Back has a different parent -> skipped).
    if focusedBtn and focusedBtn ~= inst.lastFocusBtn then   -- a REAL focus MOVE only; ignore a transient blur (nil) so the auto-scroll can't re-fire and fight manual scrolling (zukane2 #4)
      inst.lastFocusBtn = focusedBtn
      if focusedBtn then
        local ti = inst.activeTab or 1
        local parentA = UI.addr(safe(function() return focusedBtn:GetParent() end))
        -- Which scroll container owns the focused control? Either the active mod
        -- panel, or an OPEN PREDICTIVE DROPDOWN (its own inner ScrollBox). Both are
        -- hand-built ScrollBox -> SizeBox -> Canvas, so the same centering drives
        -- both -- and without the dropdown branch, focus moving down a long
        -- suggestion list never scrolled it (parent != panel canvas) and dead-ended.
        local sb, viewH
        local sc = inst.tabs[ti] and inst.tabs[ti].scrollCanvas
        if sc and parentA == UI.addr(sc) then
          sb, viewH = inst.tabPanels[ti], PANEL_H
        elseif inst.predSuggest and inst.predSuggest:canvas()
            and parentA == UI.addr(inst.predSuggest:canvas()) then
          sb, viewH = inst.predSuggest:dropdown(), inst.predSuggest:viewH()
        elseif inst.listScroll and inst.listCanvas
            and parentA == UI.addr(inst.listCanvas) then
          sb, viewH = inst.listScroll, inst.listViewH or PANEL_H
        end
        -- The scroll MATH lives in DarnUI (UI.scrollFocusIntoView -- only scrolls when
        -- the control is off-screen, so it never fights manual scrolling, zukane2 #4).
        -- focusProbe keeps only DarnMenu's job: resolving WHICH container owns focus.
        if UI.alive(sb) then UI.scrollFocusIntoView(sb, focusedBtn, viewH) end
      end
    end
  end)
  ExecuteWithDelay(120, function() focusProbe(inst, tok) end)
end

-- focusKey (optional): after the rebuild, put focus on that record's header so a
-- controller/keyboard isn't stranded (the rebuild destroyed whatever was focused,
-- which killed navigation until the menu was reopened). Falls back to the mod's
-- list button so focus ALWAYS lands somewhere.

local function rebuildPanel(inst, ti, focusKey)
  if not (UI.alive(inst.menu) and UI.alive(inst.widgetTree)) then return end   -- menu gone: skip teardown/rebuild
  local ts = inst.tabs[ti]
  if not ts then return end
  captureRecordFields(inst, ti)   -- preserve typed enum values across the teardown
  clearPred(inst)                 -- drop any open suggestion dropdown
  local old = inst.tabPanels[ti]
  if old then UI.remove(old) end
  inst.tabPanels[ti] = nil
  ts.panelFailed = nil
  ts.controls = {}
  ts.blRows = nil
  ensurePanel(inst, ti)
  selectMod(inst, ti)
  -- restore focus a beat later, once the new widgets have settled
  ExecuteWithDelay(30, function()
    if inst.disposed or not inst.pageOpen or worldGone() then return end   -- one-shot: just drop it
    local nts = inst.tabs[ti]
    local target = focusKey and nts and nts.recHeaders and nts.recHeaders[focusKey]
    if not UI.alive(target) then target = inst.listButtons and inst.listButtons[ti] end
    if UI.alive(target) then UI.focus(target); inst.lastFocusBtn = nil end
  end)
end

local function buildPage(inst)
  -- HARDENING (CTD 2026-07-24 23:07, null-deref 0x3 on the 5th menu-open): the
  -- async prebuild can fire on a stale inst whose menu/tree the engine already
  -- freed (the gens/disposed guards miss it if Destruct didn't bump gens first).
  -- Bail before any construct -- a native build on a dead outer AVs and pcall
  -- cannot catch it. UI.construct/canvasAdd/remove also self-guard now (ui.lua).
  if not (UI.alive(inst.menu) and UI.alive(inst.widgetTree) and UI.alive(inst.pageRoot)) then
    return false
  end
  -- SUPERSEDED / SWEPT: refuse before the first construct. A newer ESC menu means this
  -- one is on its way out with our widgets still attached, and nobody will ever see the
  -- page we are about to make.
  if inst.disposed or inst.seq ~= injectSeq then return false end
  local page = UI.construct("/Script/UMG.CanvasPanel", inst.widgetTree)
  if not page or not UI.canvasFill(inst.pageRoot, page) then return false end
  -- hide from BIRTH: construction takes a few frames (pre-build spreads panels
  -- across ticks) and a visible parent paints its children -- the "clutter
  -- flash" on ESC. Hidden parent = children never draw until openPage shows it.
  UI.setVis(page, VIS.HIDE)
  inst.page = page

  -- centered content container: everything below is positioned inside this,
  -- so the layout stays centered on any aspect ratio (16:9 through ultrawide)
  local content = UI.construct("/Script/UMG.CanvasPanel", inst.widgetTree)
  local contentY = CONTENT_Y + math.floor((1 - appUIScale()) * UISCALE_DROP)   -- re-center under ApplicationScale
  if not content or not UI.canvasAddTopCenter(page, content, contentY, CONTENT_W, CONTENT_H, 2) then
    return false
  end
  inst.content = content

  -- DARNMENU'S OWN VERSION IN THE TITLE (2026-07-31, Mikey: "DarnMenu tells us the version of
  -- all the other mods, but not darnmenu?"). Every hosted mod prints its version on its page --
  -- but DarnMenu IS the host and has no page of its own, so the one version that matters most
  -- was the only one invisible: it is the shared library the whole family loads through, and a
  -- version mismatch between it and a consumer is exactly the failure that cost a player his
  -- entire mod today (LA 1.8.0+ on DarnToasts 1.x). The troubleshooting steps on every store
  -- page now ask players to check their Darn versions, so there has to be somewhere to look.
  -- The title is on screen for every page, which is the right scope for the host.
  local title = UI.mkText(inst.widgetTree, inst.textTemplate, "Mod Options", 26)
  if title then UI.canvasAdd(content, title, TITLE_X, TITLE_Y, 700, 50, 1) end
  -- ITS OWN WIDGET, NOT A LONGER TITLE. Appending to the title string would push it from
  -- ~150px to ~390px, and the hint below is placed at TITLE_X + 320 -- straight into it.
  -- Small, dim, and parked in the gap between the two, so neither moves.
  local ver = UI.mkText(inst.widgetTree, inst.textTemplate, "DarnMenu " .. tostring(VERSION), 13, 0.55)
  if ver then UI.canvasAdd(content, ver, TITLE_X + 175, TITLE_Y + 22, 200, 24, 1) end
  local hint = UI.mkText(inst.widgetTree, inst.textTemplate,
    "Each mod's page says what applies live vs after a relaunch. Backspace closes the menu.", 13, 0.55)
  if hint then UI.canvasAdd(content, hint, TITLE_X + 320, TITLE_Y + 22, 700, 24, 1) end

  local schemas = Schemas.loadAll(SHARED, log)
  -- OTHER MODS: discover unschema'd config.lua mods and append a read-only browser tab
  local others = discoverOtherMods(schemas)
  -- RE-CHECK AFTER THE SLOW PART. loadAll + discoverOtherMods read files and scan
  -- UE4SS.log -- ~80ms in the 09:46 log, and that is precisely the window in which the
  -- sweep landed while the build carried on regardless. Stop here rather than attach the
  -- remaining ~100 widgets. The shell built above stays parented to the dying menu and is
  -- freed with it (removing it is what AV'd twice); dropping inst.page just means a fresh
  -- build if this instance somehow gets opened after all.
  if inst.disposed or inst.seq ~= injectSeq then
    log("page build ABANDONED mid-flight (swept/superseded during schema load) -- shell left to the engine")
    inst.page = nil
    return false
  end
  if #others > 0 then
    schemas[#schemas + 1] = {
      tab = "Other Mods", target = "DarnMenu_othermods_readonly", otherMod = true,   -- dummy target (never written); read-only tab hides Apply/Restore
      note = "These mods don't have a DarnMenu page -- their author hasn't added a menu "
        .. "schema, so DarnMenu can't edit them here. It only shows each one's config file "
        .. "and opens it in Explorer for you to edit by hand (read-only; relaunch after you "
        .. "save). A mod's author can add a DarnMenu schema to give it a full editable page.",
      sections = { { title = "Detected mods with a config.lua (no DarnMenu page) -- read-only",
                     custom = { type = "modbrowser", mods = others } } },
    }
    log("Other Mods: discovered " .. #others .. " unschema'd config.lua mod(s)")
  end
  inst.schemas = schemas
  inst.listButtons, inst.tabPanels, inst.tabs = {}, {}, {}
  -- Journal-style list is owned by DarnUI so its header/count, row treatment,
  -- scrollbar geometry, selection and controller focus remain one shared component.
  local maxMods = 40
  local listItems = {}
  for i, schema in ipairs(schemas) do
    if i > maxMods then
      log("mod list overflow: '" .. schema.tab .. "' hidden (max " .. maxMods .. ")")
    else
      inst.tabs[i] = { schema = schema, staged = {}, values = {}, controls = {} }
      -- SOFT TAG, decided once per page build and carried on the schema so the row label and
      -- the page agree. A tag rather than a hide: see modMissing on why auto-hiding a page
      -- whose mod we cannot see is forbidden.
      schema.ghostPage = modMissing(schema)
      listItems[i] = {
        label = schema.tab .. (schema.ghostPage and " (mod not detected)" or ""),
        action = { type = "tab", index = i },
      }
    end
  end
  -- SAME NIL-TOLERANCE AS worldGone/worldBack ABOVE: UI.selectorList arrived in DarnUI
  -- 1.4.0, and someone can have DarnMenu 1.6.3 sitting on DarnUI 1.3.0 (Nexus users
  -- update one file at a time; a dep listed in Info.json says nothing about version).
  -- Calling a nil there would take the whole menu down over a cosmetic component, so
  -- the plain column DarnMenu used through 1.6.2 stays as the fallback.
  local selectorList = (type(UI.selectorList) == "function") and UI.selectorList({
    menu = inst.menu,
    widgetTree = inst.widgetTree,
    parent = inst.content,
    actions = inst.actions,
    items = listItems,
    x = LIST_X,
    y = LIST_Y,
    width = LIST_W,
    height = PANEL_H,
    rowH = LIST_ROW,
    header = "Mods",
    textTemplate = inst.textTemplate,
  }) or nil
  if selectorList then
    inst.selectorList = selectorList
    inst.listScroll = selectorList.scroll
    inst.listCanvas = selectorList.canvas
    inst.listViewH = selectorList.viewH
    inst.listButtons = selectorList.buttons
  else
    if type(UI.selectorList) ~= "function" then
      log("NOTE: DarnUI is older than 1.4.0 (no UI.selectorList) -- using the plain mod list. "
        .. "Update DarnUI for the scrollable one.")
    end
    -- pre-1.6.3 layout: ScrollBox -> SizeBox(full height) -> canvas of row buttons.
    -- This ScrollBox is a child of content like the panels are, so selectMod's
    -- "hide every ScrollBox that isn't the active panel" sweep must SKIP it.
    local nMods = math.min(#schemas, maxMods)
    local listScroll = UI.construct("/Script/UMG.ScrollBox", inst.widgetTree)
    local listSize   = UI.construct("/Script/UMG.SizeBox", inst.widgetTree)
    local listCanvas = UI.construct("/Script/UMG.CanvasPanel", inst.widgetTree)
    if not (listScroll and listSize and listCanvas) then return false end
    UI.canvasAdd(inst.content, listScroll, LIST_X, LIST_Y, LIST_W, PANEL_H, 1)
    pcall(function()
      listScroll:AddChild(listSize)
      listSize:SetWidthOverride(LIST_W)
      listSize:SetHeightOverride(math.max(PANEL_H, nMods * LIST_ROW + 8))
      listSize:AddChild(listCanvas)
    end)
    inst.listScroll, inst.listCanvas = listScroll, listCanvas
    for i, item in ipairs(listItems) do
      local btn = UI.nativeButton(inst.menu, item.label, inst.actions, item.action)
      if not btn then return false end
      UI.canvasAdd(listCanvas, btn, 0, (i - 1) * LIST_ROW, LIST_W, 56, 1)
      inst.listButtons[i] = btn
    end
  end
  -- panels remain lazy: first open pays only for the shell, list and active panel

  -- No "Back" button: the page closes when you dismiss the ESC menu the normal way
  -- (Backspace / ESC / controller-B -> onStackClose + the close watchdog), so Back was
  -- redundant. Apply / Restore Defaults are stored on inst so read-only tabs (Other Mods)
  -- can hide them (nothing to save there).
  local apply = UI.nativeButton(inst.menu, "Apply", inst.actions, { type = "apply" })
  if not apply then return false end
  UI.canvasAdd(inst.content, apply, PANEL_X, FOOT_Y, 300, 56, 1)
  inst.applyBtn = apply
  local defaults = UI.nativeButton(inst.menu, "Restore Defaults", inst.actions, { type = "defaults" })
  if defaults then UI.canvasAdd(inst.content, defaults, PANEL_X + 320, FOOT_Y, 300, 56, 1) end
  inst.defaultsBtn = defaults
  inst.statusText = UI.mkText(inst.widgetTree, inst.textTemplate, "", 15)
  if inst.statusText then UI.canvasAdd(inst.content, inst.statusText, PANEL_X, FOOT_Y + 66, 1100, 34, 1) end

  -- legend for the live/relaunch dots -- only when some page declares them
  local anyDots = false
  for _, t in ipairs(inst.tabs) do
    if t.schema.live ~= nil then anyDots = true break end
    for _, sec in ipairs(t.schema.sections or {}) do
      for _, opt in ipairs(sec.options or {}) do
        if opt.live ~= nil then anyDots = true break end
      end
      if anyDots then break end
    end
    if anyDots then break end
  end
  if anyDots then
    -- only a "needs relaunch" legend (red NoticeMark). No "applies now" row --
    -- absence of the marker means it applies now.
    local icon = UI.mkImage(inst.widgetTree)
    if icon and UI.setImageAsset(icon, RESTART_ICON) then
      pcall(function() icon:SetColorAndOpacity(RESTART_TINT) end)
      UI.canvasAdd(inst.content, icon, PANEL_X + 962, FOOT_Y + 16, 24, 24, 1)
    end
    local t = UI.mkText(inst.widgetTree, inst.textTemplate, "needs relaunch", 12, 0.55)
    if t then UI.canvasAdd(inst.content, t, PANEL_X + 992, FOOT_Y + 21, 180, 22, 1) end
  end

  UI.setVis(page, VIS.HIDE)
  return true
end

-- ---------------------------------------------------------------------------
-- page open/close + actions
-- ---------------------------------------------------------------------------
local function openPage(inst)
  if inst.pageOpen then return end
  if not inst.page then
    if inst.pageFailed then return end
    local ok, built = pcall(buildPage, inst)
    if not ok or not built then
      inst.pageFailed = true
      UI.remove(inst.page)
      inst.page = nil
      log("WARNING: options page construction failed (" .. tostring(ok and "incomplete" or built) .. ")")
      return
    end
    log("options page built")
  end
  inst.pageOpen = true
  -- INVARIANT CANARY. The page must STAY open once opened; a close within a second of
  -- opening is never a user action, it is something of ours misfiring. That is exactly
  -- how the "first click on Mod Options is a no-op" bug behaved -- the close-watchdog
  -- read the menu's open animation as a screen takeover and shut the page ~300ms in --
  -- and it stayed invisible for three rounds because the successful path logged nothing.
  -- The signature of this whole bug class is "only the FIRST access fails, never again":
  -- the first open is the only one landing inside the open-animation window. If this
  -- line ever appears again, suspect a transient sampled during that window.
  inst.justOpened = true
  ExecuteWithDelay(1000, function() inst.justOpened = false end)
  inst.worldWasVisible = false
  pcall(function() inst.worldWasVisible = UI.isVisible(inst.worldCanvas) end)
  if inst.buttonCanvas then UI.setVis(inst.buttonCanvas, VIS.HIDE) end
  if inst.contentCanvas then UI.setVis(inst.contentCanvas, VIS.HIDE) end
  if inst.worldCanvas then UI.setVis(inst.worldCanvas, VIS.HIDE) end
  UI.setVis(inst.page, VIS.SHOW)
  for ti, tabState in ipairs(inst.tabs) do
    local tp2 = sharedPath(tostring(tabState.schema.target) .. ".lua", ".lua")
    local fileTable = tp2 and Writers.read(tp2)
    tabState.fileTable = fileTable or {}   -- raw config, for records seeding
    tabState.values = Schemas.currentValues(tabState.schema, fileTable)
    tabState.staged = {}
    -- a records panel renders from the (now re-read) file, but a cached panel was
    -- built earlier -- drop it so selectMod below rebuilds it against fresh disk state
    if hasRecordsSection(tabState.schema) and inst.tabPanels[ti] then
      UI.remove(inst.tabPanels[ti]); inst.tabPanels[ti] = nil; tabState.controls = {}
    end
    refreshTab(inst, ti)
    refreshBlacklist(inst, ti)
  end
  setStatus(inst, "")
  selectMod(inst, inst.activeTab or 1)
  if inst.listButtons[inst.activeTab or 1] then UI.focus(inst.listButtons[inst.activeTab or 1]) end
  -- start the predictive-suggestion poll loop (token stops any stale prior loop)
  -- the predictive-dropdown widget (DarnUI UI.suggestList). Created once per inst;
  -- boxes() maps the active tab's registered enum/list edit boxes (values resolved to
  -- plain strings) for the widget; a pick fires a "predPick" action we handle below.
  inst.predSuggest = inst.predSuggest or UI.suggestList({
    menu = inst.menu, widgetTree = inst.widgetTree, actions = inst.actions, pickType = "predPick",
    alive = function() return not inst.disposed and inst.pageOpen end,
    boxes = function()
      local ts = inst.tabs[inst.activeTab or 1]
      local out = {}
      for _, pb in ipairs((ts and ts.predBoxes) or {}) do
        local vals = {}
        for _, e in ipairs((pb.field and pb.field.values) or {}) do vals[#vals + 1] = tostring(Schemas.enumValue(e)) end
        out[#out + 1] = { box = pb.box, values = vals, canvas = pb.canvas, x = pb.x, y = pb.y, meta = pb.addTo }
      end
      return out
    end,
  })
  inst.predSuggest:start()
  -- BACKSPACE-CLOSE GUARD (DarnUI UI.editCloseGuard, zukane2 #1): while any of our
  -- BACKSPACE-CLOSE GUARD -- THE "90% STATE" (round 3, the one configuration confirmed
  -- working live; kept deliberately after seven rounds of alternatives). While one of
  -- our text fields holds focus, the cancel action is cleared, so Backspace deletes
  -- characters instead of destroying the ESC menu.
  -- What every OTHER lever did (full detail in the vault, palworld-esc-menu-injection):
  --   * `IsEnableCancelAction` is INERT -- measured false on both the menu and its host
  --     with drift=0 while the host closed anyway. It is NOT the gate its name suggests.
  --   * `ClearCancelAction()` DOES suppress Backspace, but it and `ResetCancelAction()`
  --     are BOTH one-way doors on the host's close binding -- hence the ESC cost below.
  --   * `OverrideCancelActionByType` (the surgical fix, CommonCancel only) CANNOT BE
  --     CALLED -- UE4SS can't marshal a Lua function into a delegate param
  --     (`[push_delegateproperty] Error`), ruling out every callback-taking API.
  -- FOCUS-GATED, both levers: Clear on focus, Reset on blur. Reproduced EXACTLY --
  -- do not "improve" it:
  -- FOCUS-GATED, both levers: ClearCancelAction() on focus, ResetCancelAction() on
  -- blur. Reproduced EXACTLY -- do not "improve" it:
  --   * suppressAlways (clear at page open, never Reset) was round 7 and killed ESC
  --     COMPLETELY -- strictly worse. Not a safe simplification.
  --   * UI.assertEscCloses is deliberately NOT armed here: its RegisterKeyBind is what
  --     CTD'd the game, and even thread-corrected it never restored the exit.
  -- Known cost, accepted: once a field has been focused, ESC stops exiting THIS menu
  -- instance (switch tabs then ESC, or use the menu's own buttons; relaunch clears it).
  if BACKSPACE_GUARD then
    inst.closeGuard = inst.closeGuard or UI.editCloseGuard({
      menu = inst.menu,
      alive = function() return not inst.disposed and inst.pageOpen end,
      boxes = function() return editWidgets(inst) end,
      onClobber = function() inst.escClobbered = true end,
    })
    inst.closeGuard:start()
    -- ESC AND BACKSPACE ARE THE SAME ACTION on the host, so suppressing Backspace
    -- necessarily takes ESC with it -- no action-level surgery can split them (proven:
    -- the bool is inert, ClearCancelAction is type-agnostic, OverrideCancelActionByType
    -- and UnregisterActionBinding are both uncallable from Lua). The split therefore
    -- has to happen at the KEY level: we suppress the shared action and re-provide ESC
    -- ourselves. Armed at page OPEN so the first press works; stays armed once we've
    -- clobbered, because the action stays dead for this menu instance.
    UI.assertEscCloses({
      menu = inst.menu,
      shouldClose = function()
        return not inst.disposed and (inst.pageOpen or inst.escClobbered)
      end,
    })
  end
  -- controller: focus-follow auto-scroll (the raw analog-stick axis isn't reachable
  -- in UE4SS Lua, so left-stick focus nav drives the scroll -- keeping focus centered)
  inst.focusTok = (inst.focusTok or 0) + 1
  inst.lastFocusBtn = nil
  focusProbe(inst, inst.focusTok)

  -- PAGE-CLOSE WATCHDOG: we close on our Back button, StackableUI:Close, or
  -- Destruct -- but the menu can move on without any of those (top-tab switch
  -- to Inventory/Technology, unhooked close paths), leaving the page painted
  -- over everything. We HID the menu's own canvases at open; if the game shows
  -- them again while we think we're open, it took the screen back: close.
  local tok = (inst.openToken or 0) + 1
  inst.openToken = tok
  -- Do not arm from elapsed time: FirstOpen animation duration varies with frame
  -- rate and can re-show these canvases more than once. Arm only after five
  -- consecutive hidden samples. Until then, a visible native canvas is an opening
  -- animation write, so re-assert our page and restart the stability count.
  local armed, stableSamples = false, 0
  local strikes = 0
  local function watch()
    if inst.disposed or not inst.pageOpen or inst.openToken ~= tok then return end
    -- during a map swap the canvases read as whatever teardown left them; acting on
    -- that would call closePage on a dying tree. Skip the sample, keep watching.
    if worldGone() then ExecuteWithDelay(300, watch); return end
    local took = false
    pcall(function()
      -- PASSIVE (SelfHitTestInvisible) is VISIBLE, so it means the game has taken the
      -- screen back just as much as SHOW does. The old == VIS.SHOW test missed that.
      took = UI.isVisible(inst.buttonCanvas) or UI.isVisible(inst.contentCanvas)
    end)
    if not armed then
      if took then
        stableSamples = 0
        if inst.buttonCanvas then UI.setVis(inst.buttonCanvas, VIS.HIDE) end
        if inst.contentCanvas then UI.setVis(inst.contentCanvas, VIS.HIDE) end
        if inst.worldCanvas then UI.setVis(inst.worldCanvas, VIS.HIDE) end
        UI.setVis(inst.page, VIS.SHOW)
      else
        stableSamples = stableSamples + 1
        if stableSamples >= 5 then armed = true end
      end
      strikes = 0
    elseif took then
      strikes = strikes + 1
      if strikes >= 2 then
        pcall(closePage, inst)
        return
      end
      -- first strike: re-assert, the animation may simply have overwritten us
      if inst.buttonCanvas then UI.setVis(inst.buttonCanvas, VIS.HIDE) end
      if inst.contentCanvas then UI.setVis(inst.contentCanvas, VIS.HIDE) end
      if inst.worldCanvas then UI.setVis(inst.worldCanvas, VIS.HIDE) end
      UI.setVis(inst.page, VIS.SHOW)
    else
      strikes = 0
    end
    ExecuteWithDelay(300, watch)
  end
  ExecuteWithDelay(300, watch)
end

function closePage(inst)
  if not inst.pageOpen then return end
  if inst.justOpened then
    log("WARNING: page closed <1s after opening")
  end
  inst.pageOpen = false
  cancelCapture()
  -- restore the cancel action BEFORE anything else: the menu outlives our page, and
  -- leaving the gate off would break backspace/B on the native menu until relaunch
  if inst.closeGuard then inst.closeGuard:stop() end
  UI.setVis(inst.page, VIS.HIDE)
  if inst.buttonCanvas then UI.setVis(inst.buttonCanvas, VIS.SHOW) end
  if inst.contentCanvas then UI.setVis(inst.contentCanvas, VIS.SHOW) end
  if inst.worldCanvas and inst.worldWasVisible then UI.setVis(inst.worldCanvas, VIS.SHOW) end
  if inst.entryButton then UI.focus(inst.entryButton) end
end

-- FULL PAGE REBUILD -- the mod LIST changed, not just a panel.
--
-- rebuildPanel handles everything else because everything else is inside one panel. The list
-- is built once, in buildPage, and DarnUI's selectorList has no re-item call -- so a page
-- disappearing means building the shell again. This tears down and reopens by the same route
-- the failed-build path already takes: our own CanvasPanel is removed (never a native one --
-- see the safety contract in ui.lua), the per-tab registries are dropped so nothing points at
-- a freed widget, and openPage builds from a fresh Schemas.loadAll.
--
-- The status line is set AFTER the rebuild, because buildPage constructs a new one.
-- Only reachable from an explicit, confirmed player action; nothing takes this path on a timer.
local function rebuildPageFull(inst, status)
  if not (UI.alive(inst.menu) and UI.alive(inst.widgetTree) and UI.alive(inst.pageRoot)) then return end
  clearPred(inst)
  closePage(inst)
  UI.remove(inst.page)
  inst.page, inst.pageFailed = nil, nil
  inst.selectorList, inst.listScroll, inst.listCanvas = nil, nil, nil
  inst.tabs, inst.tabPanels, inst.listButtons = {}, {}, {}
  inst.activeTab = 1
  openPage(inst)
  if status then setStatus(inst, status) end
end

local function applyAll(inst)
  local wrote, errs = 0, {}
  for ti, tabState in ipairs(inst.tabs) do
    -- commit any typed enum record-fields into the staged records first (validated)
    for _, e in ipairs(captureRecordFields(inst, ti)) do errs[#errs + 1] = e end
    local staged = {}
    for path, v in pairs(tabState.staged) do staged[path] = v end
    for path, ctl in pairs(tabState.controls) do
      if ctl.input then
        local raw = UI.editText(ctl.input)
        if raw ~= nil and raw ~= "" and raw ~= tostring(currentVal(inst, ti, path)) then
          local v, err = Schemas.coerce(ctl.opt, raw)
          if err then errs[#errs + 1] = err
          else staged[path] = v end
        end
      end
    end
    if next(staged) ~= nil then
      -- schemas.lua already sandboxes `target` at load; re-check at the WRITE as
      -- defence in depth, so no future load path can hand this an unchecked name.
      local tpath = sharedPath(tostring(tabState.schema.target) .. ".lua", ".lua")
      local ok, err = false, "unsafe target"
      if tpath then ok, err = Writers.apply(tpath, staged) end
      if ok then
        wrote = wrote + 1
        for path, v in pairs(staged) do tabState.values[path] = v end
        tabState.lastSaved = staged   -- for the computed live/relaunch apply message
        tabState.staged = {}
      else
        errs[#errs + 1] = tabState.schema.tab .. ": " .. tostring(err)
      end
    end
    refreshTab(inst, ti)
  end
  markDirty(inst)   -- staged is empty now; put the button's label back to plain "Apply"
  if #errs > 0 then setStatus(inst, "Problems: " .. table.concat(errs, " | "))
  elseif wrote > 0 then
    -- tell the player what actually happens now: the saved tab's applyNote wins
    -- (schemas declare what's live vs relaunch-only), generic text otherwise
    -- COMPUTED apply message: per-option applyNotes can't compose (one Apply
    -- saves many options), but the live dots of exactly-what-was-saved can --
    -- all live, all relaunch, or counts for a mixed save. Falls back to the
    -- page's applyNote (options without dots), then the generic line.
    local at = inst.tabs[inst.activeTab or 1]
    local msg
    if at and at.lastSaved then
      -- message logic in Schemas.applyMessage (pure, unit-tested)
      msg = Schemas.applyMessage(at.schema, at.lastSaved, function(path)
        local ctl = at.controls[path]
        return ctl and ctl.opt or nil
      end)
    end
    setStatus(inst, msg or (at and at.schema.applyNote) or "Saved. Most changes apply after a relaunch.")
  else setStatus(inst, "Nothing to save.") end
end

local function restoreDefaults(inst)
  local ti = inst.activeTab or 1
  local tabState = inst.tabs[ti]
  if not tabState then return end
  for path, v in pairs(tabState.schema.defaults or {}) do tabState.staged[path] = v end
  refreshTab(inst, ti)
  setStatus(inst, "Defaults staged for '" .. tabState.schema.tab .. "' -- press Apply to save.")
end

-- cancel a pending "Press a key..." capture and restore its button label
cancelCapture = function()
  local c = capture
  if not c then return end
  capture = nil
  local tabState = c.inst.tabs and c.inst.tabs[c.tab]
  local ctl = tabState and tabState.controls[c.path]
  if ctl and ctl.button then
    local v = currentVal(c.inst, c.tab, c.path)
    if ctl.opt and (ctl.opt.kind == "keycapture" or ctl.opt.kind == "keychord") and ctl.keyIcon then
      renderKeyControl(ctl, v)   -- restore the key icon (+ modifier cells), not a text label
    else
      UI.setLabel(ctl.button, valueLabel(v))
      if type(v) == "boolean" then setSwitch(ctl, v) end
    end
  end
end

local function runAction(inst, action)
  -- clicking ANYTHING other than the capture button itself (another tab, Apply,
  -- Back, a toggle...) cancels a pending key capture -- no keystroke ambushes
  -- a control you can no longer see.
  if capture and action.type ~= "keycap" then
    cancelCapture()
    setStatus(inst, "Key capture canceled.")
  end
  if action.type == "open" then openPage(inst)
  elseif action.type == "openFile" then
    -- launch Windows Explorer with the mod's config.lua selected (read-only feature).
    -- os.execute may be sandboxed in some UE4SS builds -> guard + report either way.
    -- This DOES flash a console window (os.execute spawns cmd). That is acceptable
    -- ONLY because it is user-initiated -- they clicked "Open config file". Never do
    -- this on a timer, at load, or at menu-open: that was the startup-flash bug.
    local cmd = 'explorer /select,"' .. tostring(action.path) .. '"'
    local ok = (os and os.execute) and select(1, pcall(os.execute, cmd)) or false
    setStatus(inst, ok and ("Opened " .. tostring(action.name) .. " config in Explorer.")
                        or ("Could not open Explorer. File: " .. tostring(action.path)))
  elseif action.type == "actionPick" then
    -- an action-panel tile: write a one-shot request into the mod's shared bridge
    -- file. We only ever set OUR key (Writers.apply merges), and bump seq so the
    -- mod runs it exactly once (it echoes ackSeq).
    -- the bridge file name comes from a third-party schema: sandbox it like every
    -- other schema-supplied name, or a crafted name writes outside shared/.
    local path = sharedPath(action.file, ".lua")
    if not path then
      -- NAME THE MOD AND OUR VERSION, in both places. A player pastes the status line; a report
      -- with a log attached pastes the log line; neither used to say which mod's page it came
      -- from or which DarnMenu produced it, so the one report of this took a code read to place.
      local rts = inst.tabs[action.tab]
      local who = (rts and rts.schema and tostring(rts.schema.tab)) or "this mod"
      setStatus(inst, "Blocked: " .. who .. "'s action file name isn't allowed ("
        .. tostring(action.file) .. ") -- DarnMenu " .. tostring(VERSION)
        .. ". Report it to that mod's author.")
      log("actionPick rejected: mod=" .. who .. " file=" .. tostring(action.file)
        .. " DarnMenu=" .. tostring(VERSION)
        .. " -- must be a plain name ending .lua (no slashes, no ..), living directly in shared/")
      return
    end
    local cur = Writers.read(path) or {}
    local prev = (type(cur[action.requestKey]) == "table" and tonumber(cur[action.requestKey].seq)) or 0
    local ok = Writers.apply(path, { [action.requestKey] = { stat = action.value, seq = prev + 1 } })
    setStatus(inst, ok and ("Queued: " .. tostring(action.label) .. "  (applies in-game in a moment)")
                        or "Could not write the request file.")
  elseif action.type == "pageRemove" then
    -- TWO-STEP. This is the only control in the menu that deletes a file, so it does not fire
    -- on a single click: the first press arms and says exactly what will happen, a second press
    -- within ten seconds does it, and anything else (a tab switch, a stray click elsewhere on
    -- the page) simply lets the arm expire. The arm hangs off the instance -- it dies with the
    -- menu, and it costs no file-scope local.
    local rmTs = inst.tabs[action.tab]
    local rmName = (rmTs and rmTs.schema and tostring(rmTs.schema.tab)) or tostring(action.name)
    local now = os.time()
    if not (inst.removeArm and inst.removeArm.name == action.name
            and (now - inst.removeArm.at) <= 10) then
      inst.removeArm = { name = action.name, at = now }
      setStatus(inst, "Press 'Remove this page' again within 10 seconds to remove " .. rmName
        .. ". This deletes the page file only -- your saved settings for that mod are KEPT, "
        .. "and reinstalling it brings the page back.")
      return
    end
    inst.removeArm = nil
    local rmOK, rmWhy = removeGhostPage(action.name)
    if not rmOK then
      setStatus(inst, "Could not remove the page: " .. tostring(rmWhy))
      log("page remove FAILED name=" .. tostring(action.name) .. ": " .. tostring(rmWhy))
      return
    end
    log("removed ghost page " .. tostring(action.name)
      .. " (schema file + backup deleted, index pruned; settings file left in place)")
    rebuildPageFull(inst, "Removed " .. rmName .. ". Its settings file was left alone.")
  elseif action.type == "tab" then if inst.pageOpen then selectMod(inst, action.index) end
  elseif action.type == "apply" then applyAll(inst)
  elseif action.type == "defaults" then restoreDefaults(inst)
  elseif action.type == "toggle" then
    local ctl = inst.tabs[action.tab].controls[action.path]
    if not depSatisfied(inst, action.tab, ctl.opt) then return end
    local v = not currentVal(inst, action.tab, action.path)
    inst.tabs[action.tab].staged[action.path] = v
    UI.setLabel(ctl.button, valueLabel(v))
    setSwitch(ctl, v)
    refreshDepends(inst, action.tab)
    markDirty(inst)
  elseif action.type == "cycle" then
    local ctl = inst.tabs[action.tab].controls[action.path]
    local vals = ctl.opt.values or {}
    if #vals == 0 then return end
    local cur = currentVal(inst, action.tab, action.path)
    local idx = 1
    for i, e in ipairs(vals) do if Schemas.enumValue(e) == cur then idx = i break end end
    local v = Schemas.enumValue(vals[(idx % #vals) + 1])
    inst.tabs[action.tab].staged[action.path] = v
    UI.setLabel(ctl.button, Schemas.enumDisplay(ctl.opt, v))
    markDirty(inst)
    -- an enum can be a dependency target. Value-dependent rows are HIDDEN
    -- when not applicable, so changing the value changes WHICH rows exist --
    -- that is a rebuild (the same mechanism section folds use), not a re-dim.
    -- Enums nothing depends on by value keep the cheap dim refresh.
    local hasValueDeps = false
    for _, sec2 in ipairs((inst.tabs[action.tab].schema or {}).sections or {}) do
      for _, o2 in ipairs(sec2.options or {}) do
        if o2.dependsOn == action.path and o2.dependsValue ~= nil then
          hasValueDeps = true; break
        end
      end
      if hasValueDeps then break end
    end
    if hasValueDeps then rebuildPanel(inst, action.tab)
    else refreshDepends(inst, action.tab) end
  elseif action.type == "step" then
    local ctl = inst.tabs[action.tab].controls[action.path]
    local opt = ctl.opt
    if not depSatisfied(inst, action.tab, opt) then return end
    -- math in Schemas.stepValue (pure, unit-tested): typed-box override, clamp,
    -- integer floor, float-drift kill
    local v = Schemas.stepValue(opt, UI.editText(ctl.input), currentVal(inst, action.tab, action.path), action.dir)
    inst.tabs[action.tab].staged[action.path] = v
    UI.styleEdit(ctl.input)   -- restyle-on-write: see refreshTab
    UI.setEditText(ctl.input, tostring(v))
  elseif action.type == "chordmod" then
    -- toggle one modifier on the chord, keeping canonical CTRL<ALT<SHIFT order
    local ctl = inst.tabs[action.tab].controls[action.path]
    local opt = ctl.opt
    if not depSatisfied(inst, action.tab, opt) then return end
    local chord = normalizeChord(currentVal(inst, action.tab, action.path))
    local requested = {}
    for _, modifier in ipairs(chord.modifiers) do requested[modifier] = true end
    requested[action.modifier] = not requested[action.modifier]
    chord.modifiers = {}
    for _, modifier in ipairs(MODIFIER_ORDER) do
      if requested[modifier] then chord.modifiers[#chord.modifiers + 1] = modifier end
    end
    local staged, err = Schemas.encodeChord(chord)
    if not staged then setStatus(inst, "Could not stage binding: " .. tostring(err)); return end
    inst.tabs[action.tab].staged[action.path] = staged
    renderKeyControl(ctl, staged)
    setStatus(inst, "Chord staged -- press Apply to save.")
  elseif action.type == "keyreset" then
    local tabState = inst.tabs[action.tab]
    local ctl = tabState and tabState.controls[action.path]
    local default = ctl and ctl.defaultValue
    if not default then return end
    local staged, err = Schemas.encodeChord(default)
    if not staged then setStatus(inst, "Could not restore binding: " .. tostring(err)); return end
    tabState.staged[action.path] = staged
    renderKeyControl(ctl, staged)
    setStatus(inst, "Default binding staged -- press Apply to save.")
  elseif action.type == "keycap" then
    local ctl = inst.tabs[action.tab].controls[action.path]
    if capture then
      local samButton = (capture.inst == inst and capture.tab == action.tab and capture.path == action.path)
      cancelCapture()
      if samButton then
        setStatus(inst, "Capture canceled.")
        return
      end
    end
    armCaptureBinds()
    capToken = capToken + 1
    local tok = capToken
    capture = { inst = inst, tab = action.tab, path = action.path, token = tok }
    if ctl.keyIcon then UI.setKeycapPrompt(ctl.button, ctl.keyIcon, "Press a key...") else UI.setLabel(ctl.button, "Press a key...") end
    setStatus(inst, "Press the key to assign (click again to cancel).")
    ExecuteWithDelay(10000, function()
      if capture and capture.token == tok then
        capture = nil                                            -- state reset happens either way
        if inst.disposed or not inst.pageOpen or worldGone() then return end   -- menu died/closed meanwhile
        pcall(function()
          local v = currentVal(inst, action.tab, action.path)
          if ctl.keyIcon then renderKeyControl(ctl, v)
          else UI.setLabel(ctl.button, valueLabel(v)); if type(v) == "boolean" then setSwitch(ctl, v) end end
        end)
        pcall(setStatus, inst, "Capture timed out.")
      end
    end)
  elseif action.type == "blremove" then
    local tabState = inst.tabs[action.tab]
    local id = tabState.blItems and tabState.blItems[action.index]
    if id then
      local items = {}
      for _, it in ipairs(tabState.blItems) do if it ~= id then items[#items + 1] = it end end
      if writeBlacklist(tabState.blFile, items) then
        setStatus(inst, "Removed " .. id .. " -- applies on relaunch (an in-session F10 save may restore it).")
      else
        setStatus(inst, "Could not write the blacklist file.")
      end
      refreshBlacklist(inst, action.tab)
    end
  elseif action.type == "recAdd" then
    local name = trimStr(UI.editText(action.box))
    if name == "" then setStatus(inst, "Type a name first, then Add."); return end
    local recs = recordsFor(inst, action.tab, action.target)
    if recs[name] ~= nil then setStatus(inst, "'" .. name .. "' is already in the list."); return end
    local okK, whyK = validateKey(action.custom, name)
    if not okK then setStatus(inst, whyK); return end
    recs[name] = defaultRecord(action.custom)
    inst.tabs[action.tab].expanded = inst.tabs[action.tab].expanded or {}
    inst.tabs[action.tab].expanded[name] = true   -- open the new entry for editing
    setStatus(inst, "Added " .. name .. " -- press Apply to save.")
    rebuildPanel(inst, action.tab, name)
  elseif action.type == "recRemove" then
    local recs = recordsFor(inst, action.tab, action.target)
    recs[action.key] = nil
    if inst.tabs[action.tab].expanded then inst.tabs[action.tab].expanded[action.key] = nil end
    setStatus(inst, "Removed " .. action.key .. " -- press Apply to save.")
    rebuildPanel(inst, action.tab)
  elseif action.type == "secToggle" then   -- fold/unfold a whole settings section
    local ts = inst.tabs[action.tab]
    ts.secClosed = ts.secClosed or {}
    ts.secClosed[action.key] = not ts.secClosed[action.key]
    local tabName = (ts.schema and tostring(ts.schema.tab or "")) or ""
    secFolds[tabName .. "|" .. action.key] = ts.secClosed[action.key]
    saveFolds()
    rebuildPanel(inst, action.tab)
  elseif action.type == "recToggle" then   -- expand/collapse a record entry
    local ts = inst.tabs[action.tab]
    ts.expanded = ts.expanded or {}
    ts.expanded[action.key] = not ts.expanded[action.key]
    rebuildPanel(inst, action.tab, action.key)
  elseif action.type == "recField" then     -- cycle a SMALL enum field (click-to-cycle)
    local recs = recordsFor(inst, action.tab, action.target)
    local rec = recs[action.key]; if type(rec) ~= "table" then return end
    local vals = action.values or {}
    if #vals == 0 then return end
    local cur, idx = rec[action.path], 1
    for i, e in ipairs(vals) do if Schemas.enumValue(e) == cur then idx = i break end end
    local nv = Schemas.enumValue(vals[(idx % #vals) + 1])
    rec[action.path] = nv
    -- update the button label IN PLACE -- no rebuild, so focus stays on this button
    if action.button then UI.setLabel(action.button, Schemas.enumDisplay(action.field or {}, nv)) end
  elseif action.type == "predPick" then     -- click a predictive suggestion
    if action.meta then                              -- LIST field (meta carries the addTo target)
      -- pick adds STRAIGHT to the list and the box clears on rebuild, so nothing is
      -- parked in the input to filter later picks. Wrong pick -> use the item's X to
      -- remove it (the standard list gesture).
      local a = action.meta
      local recs = recordsFor(inst, a.tab, a.target)
      local rec = recs[a.key]
      if type(rec) == "table" then
        local val = coerceItem(action.value, a.numeric)
        local list = rec[a.path]; if type(list) ~= "table" then list = {}; rec[a.path] = list end
        local okI, whyI = validateItem(a.field or {}, val, list)
        if not okI then setStatus(inst, whyI)          -- e.g. duplicate/unique
        else list[#list + 1] = val; setStatus(inst, "Added -- press Apply to save.") end
      end
      clearPred(inst)
      rebuildPanel(inst, a.tab, a.key)                 -- fresh empty add box; focus -> header
      return
    end
    if UI.alive(action.box) then
      UI.setEditText(action.box, action.value)
      UI.styleEdit(action.box)
    end
    clearPred(inst)
    -- Single-value field: picking destroys the focused suggestion button -> a
    -- controller would be stranded. Hand focus back to the box the value landed in,
    -- and mark that text as already-picked so the suggest widget does NOT immediately reopen
    -- the dropdown (leave and return to reopen -- it then shows the full list).
    if UI.alive(action.box) then
      if inst.predSuggest then inst.predSuggest:markPicked(action.box, action.value) end
      UI.focusEdit(action.box)
    end
  elseif action.type == "recItemAdd" then
    local recs = recordsFor(inst, action.tab, action.target)
    local rec = recs[action.key]; if type(rec) ~= "table" then return end
    local val = coerceItem(UI.editText(action.box), action.numeric)
    if val == nil or val == "" then setStatus(inst, "Type a value first, then Add."); return end
    local list = rec[action.path]; if type(list) ~= "table" then list = {}; rec[action.path] = list end
    local okI, whyI = validateItem(action.field or {}, val, list)
    if not okI then setStatus(inst, whyI); return end
    list[#list + 1] = val
    setStatus(inst, "Added -- press Apply to save.")
    rebuildPanel(inst, action.tab, action.key)
  elseif action.type == "recItemRemove" then
    local recs = recordsFor(inst, action.tab, action.target)
    local rec = recs[action.key]; if type(rec) ~= "table" then return end
    local list = rec[action.path]
    if type(list) == "table" and list[action.index] ~= nil then
      table.remove(list, action.index)
      rebuildPanel(inst, action.tab, action.key)
    end
  end
end

-- ---------------------------------------------------------------------------
-- background pre-build: after injection the ESC menu sits idle while the
-- player reads it -- use that window. 400ms after inject, build the (hidden)
-- page shell; then one panel every 180ms until all are built. By the time
-- Mod Options is clicked, openPage/selectMod find everything already made and
-- the click is instant. Clicking early just builds the remainder on demand
-- (ensurePanel is idempotent); menu close cancels via the generation counter.
-- ---------------------------------------------------------------------------
-- EXPERIMENT SWITCH (2026-07-27). Set false to skip the background pre-build entirely.
--
-- The first-click no-op is TIME-dependent, which is the one thing we had never measured.
-- Three data points, each timed from that menu's own inject:
--     0.87s -> no-op      2.58s -> no-op      ~10s -> WORKED
-- It is not click order, not our button's position (it survived moving from mid-column to
-- appended), not page-build state (it failed with actions=1 and with actions=164). It is a
-- window that closes on its own after a few seconds -- which is exactly the window in which
-- THIS function is constructing ~100 widgets per panel on 180ms timers, starting at 1200ms.
--
-- The vault's one proven lever on this menu is INJECT FEWER WIDGETS, and a page build has
-- already been measured running to completion 44ms after its own instance was swept. Heavy
-- UMG construction landing in the same frames as a click is a plausible way for that click
-- to be misrouted -- and it explains why waiting makes the problem vanish.
--
-- If the first click works reliably with this off, the pre-build is the cause and the fix is
-- to make it yield to interaction (start later, cancel on first click, or build lazily).
-- If it still no-ops, the pre-build is exonerated and the window belongs to something else
-- the game is doing in those seconds.
local function schedulePrebuild(inst, menuAddr)
  local gen = gens[menuAddr] or 0
  local first = true
  local function step()
    -- 1200ms, not 400. Under menu churn (measured 2026-07-25: three construct/sweep
    -- cycles in 3s) a 400ms delay meant every short-lived menu still got a full
    -- ~100-widget page built, which was then orphaned on a lingering menu 1.2s later.
    -- That accumulation IS the base ESC open/close race (AV reading 0x78, crash ledger),
    -- and the vault's only proven lever against it is to INJECT FEWER WIDGETS. Waiting
    -- longer means a menu the player is just cycling through never pays the cost; the
    -- pre-build still lands long before anyone reads the menu and clicks.
    ExecuteWithDelay(first and 1200 or 180, function()
      first = false
      -- The most expensive timer in the family: it constructs ~100 widgets. Doing
      -- that into a tree the engine is dismantling is the crash we are buying out.
      -- Retry instead of abandoning -- if the menu really is gone, the gens check on
      -- the next pass ends it.
      if worldGone() then step(); return end
      if (gens[menuAddr] or 0) ~= gen then return end   -- menu destructed
      if serverDisabled then return end
      -- SWEPT or SUPERSEDED. Measured in the 09:46 crash log: injects arrived ~1s apart
      -- while the prebuild waits 1200ms, so under menu churn the pre-build for menu N
      -- routinely fires AFTER menu N+1 exists. Building a page for a menu nobody is looking
      -- at is pure added exposure. `disposed` (set by the sweep) already covered most of
      -- this and covered it SILENTLY -- which is why we could not tell a dropped pre-build
      -- from a normal one, and could not answer "how much of this work is wasted?".
      -- Now both cases say so, and say which they were.
      if inst.disposed or inst.seq ~= injectSeq then
        log(string.format("pre-build dropped (%s): menu %s of %s",
          inst.disposed and "swept" or "superseded", tostring(inst.seq), tostring(injectSeq)))
        return
      end
      if not inst.page then
        if inst.pageFailed then return end
        local ok, built = pcall(buildPage, inst)
        if not ok or not built then
          inst.pageFailed = true
          log("WARNING: page shell pre-build failed (" .. tostring(ok and "incomplete" or built) .. ")")
          return
        end
        log("page shell pre-built (idle)")
        step()
        return
      end
      for ti in ipairs(inst.tabs) do
        if not inst.tabPanels[ti] and not inst.tabs[ti].panelFailed then
          ensurePanel(inst, ti)
          step()
          return
        end
      end
    end)
  end
  step()
end

-- ---------------------------------------------------------------------------
-- hooks + dispatch
-- ---------------------------------------------------------------------------
local function onButtonClicked(Context)
  if not Context then return end
  local btn = safe(function() return Context:get() end)
  if not btn or not UI.alive(btn) then return end
  local a = UI.addr(btn)
  if not a then return end
  for _, inst in pairs(instances) do
    -- UI.actionFor, NOT the raw `inst.actions[a]` (2026-07-31). An address is not an identity:
    -- UE recycles allocator addresses, so a widget built by ANOTHER MOD can land on the address
    -- of one of our torn-down controls and inherit its action -- their click runs our handler
    -- and never reaches theirs. DarnUI's overlay dispatch learned this and switched to
    -- actionFor; this dispatch -- the ESC menu's own, the one another ESC-menu mod shares a
    -- button class with -- was never migrated. Every binding here goes through UI.nativeButton,
    -- which registers exactly what actionFor validates, so this is strictly more selective and
    -- never less. Prompted by a report that AntiPhat is incompatible with DarnMenu; whether it
    -- is THIS is what the log line below will say.
    -- OBSERVE FIRST (Mikey, 2026-07-31: "do we not want to repro before implementing a fix").
    -- The strict resolution is written and ready, but it is NOT live: with DISPATCH_STRICT false
    -- this only WATCHES, logs a mismatch, and dispatches exactly as it always did. If the fix
    -- shipped first and the AntiPhat report then went quiet, we could not tell "fixed" from
    -- "never triggered" -- so behaviour stays frozen until the log says what is actually
    -- happening. Flip DISPATCH_STRICT to true once there is evidence to fix.
    -- dispatch-check: allow -- deliberate raw read; the identity check runs below in observe mode
    local action = inst.actions[a]
    if UI.actionFor and action ~= nil and not inst.disposed then
      local owned = UI.actionFor(inst.actions, btn)
      if owned == nil then
        -- A raw hit that IDENTITY rejects is, by construction, a widget that is not the button
        -- this action was bound to -- a foreign or recycled one. Silent until now.
        log(string.format("DISPATCH MISMATCH: widget at %s matches a stored action but is NOT "
          .. "the button it was bound to (name=%s) -- foreign widget on a recycled address. "
          .. "Dispatched anyway (DISPATCH_STRICT=false).",
          tostring(a), tostring(safe(function() return btn:GetFName():ToString() end))))
        if DISPATCH_STRICT then action = nil end
      end
    end
    if action and not inst.disposed then
      local ok, err = pcall(runAction, inst, action)
      if not ok then log("action error: " .. tostring(err)) end
      return
    end
  end
  -- ADOPTED GHOST: the entry button of a swept menu, which we are not allowed to
  -- remove. Route it to the live instance so the click opens the page instead of
  -- falling through and closing the menus. Checked AFTER the live lookup above, so a
  -- recycled address can never be hijacked away from its real owner.
  -- ...or ANY button we created that no live instance owns. Catching it via the sweep
  -- alone was not enough (a menu can lose its instance via Destruct too, and its button
  -- can outlive that), so the reliable test is authorship: UI.isOurs. Native ESC buttons
  -- share our class and MUST fall through untouched -- this is what keeps them safe.
  -- THE GHOST ARM, ALSO OBSERVED-NOT-CHANGED. `ghostOpen` is a bare address set checked on its
  -- OWN, so a button another mod created at a recycled ghost address opens OUR page instead of
  -- doing its own job -- the same identity mistake as the dispatch above, and the one that would
  -- most directly read as "AntiPhat is incompatible with DarnMenu". Behaviour is unchanged until
  -- DISPATCH_STRICT is armed; for now it says so in the log.
  local ghostHit = ghostOpen[a] == true
  local ownedHit = (UI.isOurs and UI.isOurs(btn)) == true
  if ghostHit and not ownedHit then
    log(string.format("GHOST MISMATCH: %s is a known ghost ADDRESS but the widget there is not "
      .. "ours (name=%s) -- another mod's button on a recycled address would open our page here. "
      .. "Opened anyway (DISPATCH_STRICT=false).",
      tostring(a), tostring(safe(function() return btn:GetFName():ToString() end))))
  end
  if (DISPATCH_STRICT and (ownedHit or (ghostHit and UI.isOurs and UI.isOurs(a))))
      or (not DISPATCH_STRICT and (ghostHit or ownedHit)) then
    for _, inst in pairs(instances) do
      if not inst.disposed then
        local ok, err = pcall(runAction, inst, { type = "open" })
        if not ok then log("ghost open error: " .. tostring(err)) end
        return
      end
    end
    return   -- no live instance: swallow it rather than let it close the menus
  end
  -- a UI.overlay button (e.g. the inventory star/picker) rides this same click
  -- delegate but is dispatched by the overlay's own hook -- not an ESC-page miss.
  if UI.ownsButton(a) then return end
  -- SILENT-FAILURE ALARM -- and it must only fire for OUR OWN buttons (narrowed 2026-07-28).
  --
  -- "Never fires in normal play" stopped being true. Every mod VENDORS its own copy of the kit,
  -- so DarnMenu's UI.ourButtons/_overlayEntries can never contain a button another mod built --
  -- different Lua state, different tables. A Standing Orders overlay button therefore misses
  -- both guards above and lands here, gets logged as an anomaly, and is then dispatched
  -- perfectly well by Standing Orders' own hook. Mikey confirmed the actions do fire.
  --
  -- So the log was reporting healthy clicks as breakage, and it cost real time: it is what sent
  -- this session chasing a phantom dispatch regression after a CTD. An alarm that fires on the
  -- normal case is worse than no alarm -- it trains you to ignore it, and it misdirects the one
  -- time it matters.
  --
  -- The genuine anomaly is narrow: a button WE authored, on OUR page, with no action bound.
  -- ours=false means "somebody else's button", which is not our business and never was.
  if not (UI.isOurs and UI.isOurs(a)) then return end
  local n, ni = 0, 0
  for _, inst in pairs(instances) do
    ni = ni + 1
    for _ in pairs(inst.actions) do n = n + 1 end
  end
  -- IDENTIFY the button, don't just count the miss. "Which widget was this?" is the
  -- question that settles whether the player hit an orphaned button of OURS or a NATIVE
  -- one (Discord/Eula/Pause share our button CLASS, so the hook sees them too).
  local bname = safe(function() return btn:GetFName():ToString() end)
  local blabel = safe(function() return btn.Text_Main:GetText():ToString() end)
  log(string.format(
    "WARNING: click had no registered action (addr=%s name=%s label=%q ours=%s ghost=%s"
    .. " instances=%d actions=%d) -- mismatched/stale page?",
    tostring(a), tostring(bname), tostring(blabel or ""),
    tostring(UI.isOurs and UI.isOurs(a)), tostring(ghostOpen[a] == true), ni, n))
end

local function onButtonUnhover(Context)
  local btn = safe(function() return Context:get() end)
  local a = btn and UI.addr(btn)
  if not a then return end
  for _, inst in pairs(instances) do
    if inst.pageOpen and not inst.disposed then
      local active = inst.listButtons[inst.activeTab]
      if active and UI.addr(active) == a then UI.selected(active, true); return end
    end
  end
end

-- the edit box (text field / predictive box) that currently holds keyboard focus, or nil
local function focusedEdit(inst)
  for _, box in ipairs(editWidgets(inst)) do
    if safe(function() return box:HasKeyboardFocus() end) == true then return box end
  end
  return nil
end

-- Backspace/gamepad-B and ESC both land here (PalUserWidgetStackableUI:Close). A post-hook
-- can't veto the native close -- and no longer needs to: while a text field holds focus the
-- menu's cancel action is gated off (UI.editCloseGuard), so backspace never reaches Close at
-- all and just edits the text. Anything that DOES get here is a real, deliberate close.
local function onStackClose(Context)
  local closing = safe(function() return Context:get() end)
  local closingAddr = closing and UI.addr(closing)
  if not closingAddr then return end
  for _, inst in pairs(instances) do
    -- This hook is global to every stackable Pal UI. An unrelated overlay often
    -- closes while the ESC menu is finishing FirstOpen; that must not close our
    -- page. Only the ESC instance that owns this DarnMenu page is relevant.
    if inst.pageOpen and not inst.disposed
        and alive(inst.menu) and UI.addr(inst.menu) == closingAddr then
      pcall(closePage, inst)
    end
  end
end

-- THE DESTRUCT HOOK ARMS HERE, NOT AT LOAD (2026-08-06, bug #1114273). It was registered
-- once at mod load in a bare pcall -- but on a cold boot WBP_MenuESC_C is not loaded yet,
-- RegisterHook returns nil ids, and the hook silently never exists (the exact trap ui.lua
-- documents above tryArmDestruct, fixed in the kit 2026-07-28 and never here). Consequences
-- of the blind hook: `gone` never counted, instances[] never cleared at destruct, every next
-- inject "swept" a corpse, and the log broadcast a fictional leak ("destructed 0, LINGERING
-- N") that players read back to us word-for-word as a crash report. Living Arsenal's vendored
-- kit hook proved 100% seen-vs-disposed parity across six dogfood sessions -- the game frees
-- every closed menu; only our bookkeeping was blind. Worse than the counter: with `disposed`
-- never set, the sweep could SetVis a destroyed menu's page and closeGuard/watchdog polls
-- kept touching destroyed widgets -- this project's documented AV class.
-- Arming from armHooks() (first inject) guarantees the class is loaded; ids are verified
-- (nil id = UFunction not resolved) and arming retries on later injects until it takes.
local destructArmed = false
local function onMenuDestruct(Context)
  local menu = safe(function() return Context:get() end)
  local a = menu and UI.addr(menu)
  if not a then return end
  menuCount.gone = menuCount.gone + 1     -- counts EVERY menu that dies, injected or not
  local inst = instances[a]
  if inst then
    inst.disposed = true
    if inst.closeGuard then inst.closeGuard:stop() end   -- kill the poll; restore is a no-op on the dying menu
  end
  if capture and inst and capture.inst == inst then capture = nil end
  instances[a] = nil
  gens[a] = (gens[a] or 0) + 1
end
local function armDestruct()
  if destructArmed then return true end
  local ok, preId, postId = pcall(RegisterHook, MENU_CLASS .. ":Destruct", onMenuDestruct)
  -- BOTH ids must come back. A nil id is UE4SS saying the UFunction was not resolved.
  if not (ok and preId ~= nil and postId ~= nil) then return false end
  destructArmed = true
  return true
end

local function armHooks()
  -- Destruct arming sits OUTSIDE the hooksArmed latch: it retries on every inject until
  -- it verifies, so one bad first attempt does not blind the counters for the session.
  if not destructArmed then
    log("destruct hook " .. (armDestruct() and "armed (ids verified)"
                                            or "NOT armed -- will retry on next menu"))
  end
  if hooksArmed then return end
  hooksArmed = true
  local okClick = pcall(RegisterHook, CLICK_EVENT, onButtonClicked)
  local okUnhover = pcall(RegisterHook, UNHOVER_EVENT, onButtonUnhover)
  local okClose = pcall(RegisterHook, STACK_CLOSE, onStackClose)
  log(string.format("hooks: click=%s unhover=%s close=%s",
    tostring(okClick), tostring(okUnhover), tostring(okClose)))
  if not okClick then log("WARNING: click hook failed -- menu will not respond") end
end

-- ---------------------------------------------------------------------------
-- injection
-- ---------------------------------------------------------------------------
local function isDedicated(worldContext)
  local ok, v = pcall(function()
    local lib = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
    return lib and lib:IsValid() and lib:IsDedicatedServer(worldContext) == true
  end)
  return ok and v == true
end

-- (scheduleStaleCleanup REMOVED 2026-07-25: deferring RemoveFromParent of a
-- swept instance's widgets to +1.5s past the swap STILL AV'd the engine -- the
-- swept menu lingers and paints, so mutating it corrupts Slate state. Proven the
-- author's line-2031 warning twice. Stale widgets are left for the engine to
-- free when it finally destructs the menu.)

local function inject(menu)
  local a = UI.addr(menu)
  if not a then return false, "menu has no UObject address" end
  if instances[a] then return true end
  if isDedicated(menu) then
    serverDisabled = true
    log("dedicated server detected -- UI disabled")
    return true
  end
  -- SINGLETON SWEEP: the game constructs fresh ESC menus in rapid succession
  -- (two injects 1.5s apart in the 09:47 crash log) and old ones don't always
  -- Destruct. A stale instance's open page kept painting over everything (the
  -- "stuck Toasts overlay") and its stacked twins ate the repaint ("updates
  -- behind the scenes, doesn't repaint"). One live menu = one instance.
  for a2, i2 in pairs(instances) do
    if a2 ~= a then
      i2.disposed = true
      -- stop the backspace-close guard's poll and restore the cancel action (a bare
      -- bool UPROPERTY write -- no layout mutation, so unlike SetVisibility it is
      -- safe on a lingering menu; alive-gated + pcall'd inside DarnUI regardless)
      if i2.closeGuard then i2.closeGuard:stop() end
      -- HIDE OUR PAGE ONLY (long-proven safe). Do NOT touch any other injected
      -- widget on the lingering menu -- not RemoveFromParent (AV'd twice) and NOT
      -- SetVisibility on the entry button either: it lives in the game's native
      -- VerticalBox, and collapsing it triggers a VerticalBox REFLOW = a layout
      -- mutation of the lingering menu, which AV'd (writing 0x80, 2026-07-25 01:18
      -- dump) just like removal. Our page is a child of OUR overlay on pageRoot, so
      -- hiding it is safe; the native-container entry button is not ours to poke.
      -- The engine frees all our children when it finally Destructs the menu.
      -- ...but ONLY IF IT WAS ACTUALLY OPEN (2026-07-31). This hide exists for one symptom: a
      -- stale instance whose page was OPEN kept painting over everything. A page that was never
      -- opened is already hidden, so the write bought nothing -- and SetVisibility is only
      -- UObject-alive-gated (UI.setVis), which does not prove the underlying Slate widget
      -- survived the menu's teardown. Crash 3 (2026-07-31 13:15:37, DarnMenu ALONE, ESC-spam,
      -- `AV reading 0x21c004e` -- a dangling read, not a null one) died between this sweep and
      -- the inject that follows it, with no page ever opened in the session. Same lesson as
      -- RemoveFromParent (AV'd twice) and the entry-button SetVisibility (`writing 0x80`):
      -- every touch of a lingering menu eventually AVs, so only pay for the ones that buy
      -- something.
      if i2.pageOpen then UI.setVis(i2.page, VIS.HIDE) end
      -- ...but that button STAYS ON SCREEN AND STAYS CLICKABLE. Dropping the instance
      -- also drops its actions, so clicking the ghost found no action, we no-op'd, and
      -- the click fell through to the stack and closed the menus -- the "first click on
      -- Mod Options is a no-op that exits" bug. We can't remove the ghost (see above),
      -- so ADOPT it: remember its address and route it to the live page instead.
      local ga = UI.addr(i2.entryButton)
      if ga then
        ghostCount = ghostCount + 1
        if ghostCount > 64 then ghostOpen, ghostCount = {}, 1 end   -- bound a long session
        ghostOpen[ga] = true
      end
      instances[a2] = nil
      log("swept stale menu instance " .. tostring(a2) .. " (page hidden, entry button adopted)")
    end
  end
  local widgetTree = safe(function() return menu.WidgetTree end)
  local pageRoot = UI.findByName(menu, "CanvasPanel_0")
  -- Generated root names are not a stable Blueprint contract. CanvasPanel_0 is
  -- still the name on the current build, but use the WidgetTree's actual root
  -- when a game update renames it.
  if not UI.alive(pageRoot) and widgetTree then
    pageRoot = safe(function() return widgetTree.RootWidget end)
  end
  local buttonCanvas = UI.findByName(menu, "Canvas_Buttons")
  if not (widgetTree and UI.alive(pageRoot) and UI.alive(buttonCanvas)) then
    return false, string.format(
      "widget tree not ready (WidgetTree=%s, root=%s, Canvas_Buttons=%s)",
      tostring(widgetTree ~= nil), tostring(UI.alive(pageRoot)), tostring(UI.alive(buttonCanvas)))
  end

  local inst = {
    menu = menu,
    widgetTree = widgetTree,
    pageRoot = pageRoot,
    buttonCanvas = buttonCanvas,
    contentCanvas = UI.findByName(menu, "Canvas_Content"),
    worldCanvas = UI.findByName(menu, "WorldOptionCanvas"),
    textTemplate = UI.styleTemplate(menu),
    actions = {},
    tabs = {},
    listButtons = {},
    tabPanels = {},
    activeTab = 1,
    pageOpen = false,
    -- inst.seq (the supersession stamp) is claimed further down, once this inject is
    -- known to have succeeded. Deliberately absent here: a half-built inst must never
    -- carry a stamp, or a failed inject could supersede the working instance.
  }
  -- "DARN MOD OPTIONS", not "Mod Options" (2026-08-11). PalModOptions labels its ESC entry
  -- "Mod Options" too, so players running both got two identical rows and opened the wrong
  -- one -- reported twice on the store pages. The label is cosmetic: nothing branches on it
  -- (dispatch is by bound action, and the placement scan matches widget CLASS), so the name
  -- can carry the family instead. The PAGE TITLE stays "Mod Options": its version chip sits
  -- at a hand-tuned offset measured against that string's width.
  local entry = UI.nativeButton(menu, "Darn Mod Options", inst.actions, { type = "open" })
  if not entry then
    return false, "could not create WBP_MenuESC_Button_S (asset/class/player not ready)"
  end
  -- CANVAS FIRST, column only as a fallback. The column path is what reflows a native
  -- VerticalBox on the engine's next layout pass -- see ENTRY_ON_CANVAS above.
  local placed = false
  if ENTRY_ON_CANVAS then placed = placeEntryOnCanvas(menu, entry, buttonCanvas) end
  if not placed then placed = placeUnderDiscord(menu, entry) end
  if not placed then
    UI.remove(entry)
    return false, "could not place the entry button (canvas and column both refused)"
  end
  inst.entryButton = entry
  -- Claim the newest slot only NOW. Bumping it earlier would have let a FAILED inject
  -- (no widget tree, no room under Discord -- both bail above) supersede the working
  -- instance and silently stop its page from ever being built.
  injectSeq = injectSeq + 1
  inst.seq = injectSeq
  instances[a] = inst
  armHooks()
  if PREBUILD then schedulePrebuild(inst, a) end
  -- seen-gone is the number this line exists for: menus constructed minus menus destructed.
  -- With the destruct hook armed it reads 1 in normal play (the menu that is open right now);
  -- >1 sustained means dead-but-alive menus still carry our widgets -- read it off the last
  -- line of a crash log. (Worded neutrally on purpose: the old "LINGERING N / destructed 0"
  -- phrasing -- fed by the never-armed hook -- was quoted back verbatim as bug #1114273.)
  log(string.format("%s [menus seen %d, destructed %d, live %d%s]",
    PREBUILD and "injected (page pre-building in background)"
             or "injected (pre-build OFF -- page builds on first click)",
    menuCount.seen, menuCount.gone, menuCount.seen - menuCount.gone,
    destructArmed and "" or " -- destruct hook unarmed, counts blind"))
  return true
end

-- waitedS: seconds already spent waiting out menu churn (see the CHURN GATE below). Carried
-- across re-arms so the wait is bounded overall, not per attempt.
local function tryInject(menu, attempt, waitedS, generation)
  if serverDisabled then return end
  local a = UI.addr(menu)
  if not a then return end
  local gen = gens[a] or 0
  ExecuteWithDelay(attempt == 1 and 50 or 250, function()
    if serverDisabled then return end
    if (gens[a] or 0) ~= gen then return end
    if not UI.alive(menu) then return end
    -- SUPERSEDED: the game has built a NEWER ESC menu since this one was scheduled. Injecting
    -- now would sweep the live instance and hang our widgets on a menu the player has already
    -- moved past -- the exact sweep+inject pair that ends all three 2026-07-31 crash logs. The
    -- newer menu has its own tryInject in flight, so the button still arrives; it just arrives
    -- on the menu that is actually on screen. Retries stop too: attempt 2+ would race the same
    -- way. This is the same lever injectSeq already applies to page BUILDS, one step earlier.
    if generation and generation ~= newestMenuGeneration then
      log(string.format("inject skipped: menu generation %d was superseded by %d before we ran",
        generation, newestMenuGeneration))
      return
    end
    if newestMenuAddr and newestMenuAddr ~= a then
      log(string.format("inject skipped: menu %s was superseded by %s before we ran",
        tostring(a), tostring(newestMenuAddr)))
      return
    end
    -- CHURN GATE: wait for the storm to pass before touching anything. While ESC is being
    -- mashed a new menu lands every ~330ms; injecting into each one means a widget created, a
    -- sweep run and a native canvas written every third of a second. Hold off until the game has
    -- gone quiet for CHURN_QUIET, then inject into whatever the player actually settled on.
    -- Bounded by CHURN_MAX_WAIT so a pathological case still gets its button rather than none.
    local waited = tonumber(waitedS) or 0
    if menuBurst > 0 and (os.clock() - lastMenuAt) < CHURN_QUIET and waited < CHURN_MAX_WAIT then
      ExecuteWithDelay(150, function()
        pcall(function() tryInject(menu, attempt, waited + 0.15, generation) end)
      end)
      return
    end
    local ok, done, reason = pcall(inject, menu)
    if (not ok or not done) and attempt < 4 then
      tryInject(menu, attempt + 1, 0, generation)
    elseif not ok or not done then
      log("WARNING: could not inject into the ESC menu: "
        .. tostring(ok and reason or done or "unknown failure"))
    end
  end)
end

-- (Destruct hook moved into armHooks()/armDestruct() above, 2026-08-06 -- the load-time
-- registration silently never armed on a cold boot. See the note above onMenuDestruct.)

-- NEVER INJECT SYNCHRONOUSLY FROM THIS CALLBACK. (Reversed 2026-07-26; it used to run
-- `inject` inline so the button existed before the menu's first paint -- the "jarring pop"
-- fix -- with the delayed ladder only as a fallback.)
--
-- What that meant in practice: seating the entry button calls UI.insertChildAt on the game's
-- own VerticalBox, and UMG exposes no reorder API (checked the header dump: UPanelWidget has
-- AddChild/RemoveChildAt and nothing else), so the only way to place a row is to DETACH every
-- child after it and re-add them. That rewrites the panel's `Slots` array -- while we are still
-- inside the engine's construction callback for that very widget, with whatever indices and
-- pointers it holds across our call.
--
-- CTD 2026-07-26 10:26:17, `AV WRITING 0x80`, hash D6BE4C66A445 (also seen 2026-07-25 01:35):
-- the crash timestamp matches the "injected" log line to seven decimal places -- i.e. our Lua
-- finished and the engine died on the very next thing it did. Writing 0x80 is this project's
-- known signature for a layout mutation of a menu that is not in a state to be mutated.
--
-- 50ms later the widget is built and the mutation is ordinary. The pop it was avoiding was a
-- ~1s-late appearance; 50ms lands inside the open animation, so the fix it bought is kept.
local function onMenuConstructed(menu)
  if serverDisabled then return end
  worldBack()
  newestMenuGeneration = newestMenuGeneration + 1
  local generation = newestMenuGeneration
  newestMenuAddr = UI.addr(menu) or newestMenuAddr
  menuCount.seen = menuCount.seen + 1
  local nowC = os.clock()
  if (nowC - lastMenuAt) > CHURN_BURST then menuBurst = 0 else menuBurst = menuBurst + 1 end
  lastMenuAt = nowC
  pcall(function() tryInject(menu, 1, 0, generation) end)
end

NotifyOnNewObject(MENU_CLASS, onMenuConstructed)
pcall(function() NotifyOnNewObject("WBP_MenuESC_C", onMenuConstructed) end)

-- Polling fallback: ensures ESC menu is injected even if NotifyOnNewObject missed the blueprint path
LoopAsync(300, function()
  if serverDisabled then return false end
  pcall(function()
    local escMenu = FindFirstOf("WBP_MenuESC_C")
    if escMenu and escMenu:IsValid() and UI.alive(escMenu) then
      local a = UI.addr(escMenu)
      if not instances[a] then
        onMenuConstructed(escMenu)
      end
    end
  end)
  return false
end)

-- Startup diagnostic: confirm injection state in UE4SS console
local diagCount = 0
LoopAsync(10000, function()
  diagCount = diagCount + 1
  if diagCount > 3 then return true end  -- stop after 30s
  local count = 0
  for _ in pairs(instances) do count = count + 1 end
  if serverDisabled then
    print("[DarnMenu:DIAG] Server mode detected — ESC menu UI disabled (expected on dedicated server).")
    return true
  elseif count > 0 then
    print(string.format("[DarnMenu:DIAG] ESC menu button ACTIVE (%d instance(s) tracked). 'Darn Mod Options' should be visible.", count))
    return true
  else
    print("[DarnMenu:DIAG] No ESC menu instance found yet. Waiting for player to open ESC menu...")
  end
  return false
end)

-- Pure platform: no built-in pages, no directory scan (and therefore no
-- console flash, ever). Mods register via shared/DarnMenu_schema_* files --
-- the index is loadfile'd fresh at every page build.
-- ===========================================================================

-- Arm the map-boundary hooks once, and say in the log whether they took. If pre=false
-- we simply behave as before (nothing stands down) rather than latching with no way
-- back -- but the log line is what tells us which of those two worlds we are in.
if UI.armMapBoundary then pcall(UI.armMapBoundary, log) end

log("v" .. VERSION .. " loaded -- ESC menu > Darn Mod Options (pure platform; schemas via shared/DarnMenu_schema_*.lua)")
