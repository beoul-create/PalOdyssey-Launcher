-- ============================================================================
--  DarnMenu schemas.lua -- schema loading. DarnMenu is a PURE PLATFORM: it has
--  NO built-in pages. Every mod (the Darn family included) registers by writing
--  two files at its own startup:
--
--    Mods/shared/DarnMenu_schema_<Name>.lua     -- returns the schema table
--    Mods/shared/DarnMenu_schema_index.lua      -- returns { "<Name>", ... }
--                                                  (merge your name in)
--
--  ToastLib.registerMenuSchema(name, version, sourceText) does both steps for
--  you (idempotent, version-gated); mods that don't use DarnToasts can write
--  the files with plain io. The index is read with loadfile -- no shell, no
--  console window, and a newly registered mod's page appears at the next menu
--  open (the index is re-read every page build).
--
--  A SCHEMA (full reference: DarnMenu_API.md; copy-paste: DarnMenu_schema_example.lua):
--    {
--      schemaVersion = 1,               -- bump to force re-registration
--      tab      = "Loot Filter",        -- entry in the mod list
--      order    = 20,                   -- sort key (default 100)
--      target   = "OutdoorLootFilter_user",  -- Mods/shared/<target>.lua gets the
--                                            -- values (merged); MUST end in _user
--                                            -- (ToastLib_config is allowlisted)
--      note     = "...",                -- shown at the top of the page
--      applyNote = "...",               -- status line after a successful Apply
--                                       -- (say what's live vs relaunch-only)
--      live     = true|false,           -- page default for the live/relaunch dots
--                                       -- (green = applies now, amber = relaunch);
--                                       -- omit = no dots. Per-option `live` overrides.
--      defaults = { key = value, ... },  -- baseline when the file lacks a key
--      sections = {
--        { title = "...", options = {
--            { path="key", label="...", kind="bool"|"enum"|"number"|"text"|"keycapture",
--              values={...}, help="...", dependsOn="otherKey", note="...", live=true|false },
--            -- number extras: min=, max= (inclusive, rejected not clamped),
--            --   integer=true, step=N (renders -/+ buttons)
--            -- text extras: maxLen=, minLen= (BYTES, not glyphs)
--            -- number/text: validate = function(v) return ok, "why" end
--            -- enum values: plain OR { value = "stored", label = "displayed" }
--            { subtitle = "...", help = "..." },
--            { divider = true },
--        }},
--        { title = "...", custom = { type = "listfile",       -- managed list UI:
--            file = "YourMod_things.txt",                     -- lives in shared/
--            empty = "shown when the list is empty" } },      -- (plain .txt basename)
--      },
--    }
-- ============================================================================

local S = {}
local Writers = require("writers")

local OPTION_KINDS = {
  bool = true, enum = true, number = true, text = true,
  keycapture = true, keychord = true,
}

local RECORD_KINDS = { enum = true, list = true }
local DEFAULT_MODIFIER_SET = { CONTROL = true, CTRL = true, ALT = true, SHIFT = true }

local function finiteNumber(value)
  return type(value) == "number"
    and value == value and value ~= math.huge and value ~= -math.huge
end

local function plainTable(value, at)
  if type(value) ~= "table" then return false, at .. " must be a table" end
  if getmetatable(value) ~= nil then return false, at .. " must not have a metatable" end
  return true
end

local function arrayValues(value, at)
  local ok, why = plainTable(value, at)
  if not ok then return nil, why end
  local keys, max = 0, 0
  for key in next, value do
    if not finiteNumber(key) or key < 1 or key % 1 ~= 0 then
      return nil, at .. " must be a contiguous numeric list"
    end
    keys = keys + 1
    if key > max then max = key end
  end
  if keys ~= max then return nil, at .. " must not contain holes" end
  local out = {}
  for i = 1, max do out[i] = rawget(value, i) end
  return out
end

local function validateDataTree(value, at, stack)
  local kind = type(value)
  if kind == "string" or kind == "boolean" then return true end
  if kind == "number" then
    if not finiteNumber(value) then
      return false, at .. " contains a non-finite number"
    end
    return true
  end
  if kind ~= "table" then return false, at .. " contains unsupported " .. kind end
  if getmetatable(value) ~= nil then return false, at .. " must not contain metatables" end
  stack = stack or {}
  if stack[value] then return false, at .. " contains a cycle" end
  stack[value] = true
  for key in next, value do
    local keyKind = type(key)
    if keyKind ~= "string" and (keyKind ~= "number" or not finiteNumber(key)) then
      return false, at .. " contains an unsupported key"
    end
    local ok, why = validateDataTree(rawget(value, key), at .. "[" .. tostring(key) .. "]", stack)
    if not ok then return false, why end
  end
  stack[value] = nil
  return true
end

local function optionalType(owner, field, wanted, at, nonEmpty)
  local value = rawget(owner, field)
  if value == nil then return true end
  if type(value) ~= wanted then
    return false, at .. "." .. field .. " must be a " .. wanted
  end
  if nonEmpty and value == "" then
    return false, at .. "." .. field .. " must not be empty"
  end
  return true
end

local function finiteField(owner, field, at)
  local value = rawget(owner, field)
  if value ~= nil and not finiteNumber(value) then
    return nil, at .. "." .. field .. " must be a finite number"
  end
  return value
end

local function lengthField(owner, field, at)
  local value, why = finiteField(owner, field, at)
  if why then return nil, why end
  if value ~= nil and (value < 0 or value % 1 ~= 0) then
    return nil, at .. "." .. field .. " must be a non-negative whole number"
  end
  return value
end

local function scalarValue(value, at)
  local kind = type(value)
  if kind == "string" or kind == "boolean" then return true end
  if finiteNumber(value) then return true end
  return false, at .. " must be a string, boolean, or finite number"
end

local function choiceValue(entry)
  if type(entry) == "table" then return rawget(entry, "value") end
  return entry
end

local function validateChoices(value, at, requireOne)
  local entries, why = arrayValues(value, at)
  if not entries then return nil, why end
  if requireOne and #entries == 0 then return nil, at .. " must contain at least one value" end
  for i, entry in ipairs(entries) do
    local entryAt = at .. "[" .. i .. "]"
    if type(entry) == "table" then
      local ok
      ok, why = plainTable(entry, entryAt)
      if not ok then return nil, why end
      if rawget(entry, "value") == nil then return nil, entryAt .. ".value is required" end
      ok, why = scalarValue(rawget(entry, "value"), entryAt .. ".value")
      if not ok then return nil, why end
      ok, why = optionalType(entry, "label", "string", entryAt)
      if not ok then return nil, why end
    else
      local ok
      ok, why = scalarValue(entry, entryAt)
      if not ok then return nil, why end
    end
  end
  return entries
end

local function choicesContain(entries, wanted)
  for _, entry in ipairs(entries or {}) do
    if choiceValue(entry) == wanted then return true end
  end
  return false
end

local function validateBounds(owner, at, includeStep)
  local min, why = finiteField(owner, "min", at)
  if why then return false, why end
  local max
  max, why = finiteField(owner, "max", at)
  if why then return false, why end
  if min ~= nil and max ~= nil and min > max then
    return false, at .. ".min must not exceed .max"
  end
  if includeStep then
    local step
    step, why = finiteField(owner, "step", at)
    if why then return false, why end
    if step ~= nil and step <= 0 then return false, at .. ".step must be greater than zero" end
  end
  local ok
  ok, why = optionalType(owner, "integer", "boolean", at)
  if not ok then return false, why end
  return true
end

local function validateLengths(owner, at)
  local minLen, why = lengthField(owner, "minLen", at)
  if why then return false, why end
  local maxLen
  maxLen, why = lengthField(owner, "maxLen", at)
  if why then return false, why end
  if minLen ~= nil and maxLen ~= nil and minLen > maxLen then
    return false, at .. ".minLen must not exceed .maxLen"
  end
  return true
end

-- UNBOUND IS A LEGITIMATE STATE (2026-07-28). This rejected an empty key outright, which
-- looked reasonable and broke a shipping mod on contact: Standing Orders declares
--     bindFill = { key = "", modifiers = {} }
-- meaning "this action has no key by default -- bind one if you want it". The validator called
-- that malformed, and because one bad field invalidates the WHOLE schema, Standing Orders' page
-- vanished from Mod Options entirely. The symptom Mikey reported was "I can't deactivate the SO
-- badge" -- the toggle was not broken, the page it lives on was never registered.
--
-- A validator's job is to catch things that would break the menu, not to have opinions about
-- values a mod is entitled to choose. An empty key means unbound; the keychord control already
-- renders that as "unbound" and lets the player set one. So: empty is ACCEPTED for a table
-- chord, and only a non-string or a whitespace-only-but-non-empty key is rejected.
--
-- The bare-STRING form still requires a name, because there `""` is not "unbound" -- it is a
-- string where a key was expected, with no modifiers table to make the intent clear.
local function validateChord(value, at)
  if type(value) == "string" then
    if value:match("%S") then return true end
    return false, at .. " requires a key name"
  end
  local ok, why = plainTable(value, at)
  if not ok then return false, why end
  local key = rawget(value, "key")
  if key == nil then key = rawget(value, 1) end
  if type(key) ~= "string" then
    return false, at .. ".key must be a string (\"\" means unbound)"
  end
  if key ~= "" and not key:match("%S") then
    return false, at .. ".key must be a key name or \"\" for unbound"
  end
  local modifiers = rawget(value, "modifiers")
  if modifiers == nil then modifiers = {} end
  local entries
  entries, why = arrayValues(modifiers, at .. ".modifiers")
  if not entries then return false, why end
  for i, modifier in ipairs(entries) do
    if type(modifier) ~= "string" or not DEFAULT_MODIFIER_SET[modifier:upper()] then
      return false, at .. ".modifiers[" .. i .. "] is unsupported"
    end
  end
  return true
end

local function validateDefault(opt, value, at, choices)
  local kind = rawget(opt, "kind")
  if kind == "bool" then
    if type(value) ~= "boolean" then return false, at .. " must be a boolean" end
  elseif kind == "enum" then
    local ok, why = scalarValue(value, at)
    if not ok then return false, why end
    if not choicesContain(choices, value) then return false, at .. " is not present in the enum values" end
  elseif kind == "number" then
    if not finiteNumber(value) then return false, at .. " must be a finite number" end
    if rawget(opt, "integer") == true and value % 1 ~= 0 then
      return false, at .. " must be a whole number"
    end
    local min, max = rawget(opt, "min"), rawget(opt, "max")
    if min ~= nil and value < min then return false, at .. " is below the option minimum" end
    if max ~= nil and value > max then return false, at .. " is above the option maximum" end
  elseif kind == "text" then
    if type(value) ~= "string" then return false, at .. " must be a string" end
    local minLen, maxLen = rawget(opt, "minLen"), rawget(opt, "maxLen")
    if minLen ~= nil and #value < minLen then return false, at .. " is shorter than minLen" end
    if maxLen ~= nil and #value > maxLen then return false, at .. " is longer than maxLen" end
  elseif kind == "keycapture" then
    if type(value) ~= "string" then return false, at .. " must be a key-name string" end
  elseif kind == "keychord" then
    return validateChord(value, at)
  end
  return true
end

local function validateOption(opt, at, optionPaths, configKeys, dependencies)
  local ok, why = plainTable(opt, at)
  if not ok then return false, why end

  ok, why = optionalType(opt, "divider", "boolean", at)
  if not ok then return false, why end
  if rawget(opt, "divider") == true then return true end

  local subtitle = rawget(opt, "subtitle")
  if subtitle ~= nil then
    ok, why = optionalType(opt, "subtitle", "string", at, true)
    if not ok then return false, why end
    ok, why = optionalType(opt, "help", "string", at)
    if not ok then return false, why end
    return true
  end

  local path, kind = rawget(opt, "path"), rawget(opt, "kind")
  if type(path) ~= "string" or path == "" then return false, at .. ".path must be a non-empty string" end
  if configKeys[path] then return false, at .. ".path duplicates config key " .. path end
  if not OPTION_KINDS[kind] then return false, at .. ".kind is unsupported: " .. tostring(kind) end

  for _, field in ipairs({ "label", "help", "note" }) do
    ok, why = optionalType(opt, field, "string", at)
    if not ok then return false, why end
  end
  ok, why = optionalType(opt, "dependsOn", "string", at, true)
  if not ok then return false, why end
  ok, why = optionalType(opt, "live", "boolean", at)
  if not ok then return false, why end
  ok, why = optionalType(opt, "validate", "function", at)
  if not ok then return false, why end

  local choices
  if kind == "enum" then
    choices, why = validateChoices(rawget(opt, "values"), at .. ".values", true)
    if not choices then return false, why end
  elseif kind == "number" then
    ok, why = validateBounds(opt, at, true)
    if not ok then return false, why end
  elseif kind == "text" then
    ok, why = validateLengths(opt, at)
    if not ok then return false, why end
  end

  optionPaths[path] = { opt = opt, at = at, choices = choices, kind = kind }
  configKeys[path] = at
  if rawget(opt, "dependsOn") ~= nil then
    dependencies[#dependencies + 1] = { at = at .. ".dependsOn",
                                       path = rawget(opt, "dependsOn"),
                                       value = rawget(opt, "dependsValue") }
  end
  return true
end

local function validateRecordField(field, at, seenPaths)
  local ok, why = plainTable(field, at)
  if not ok then return false, why end
  local path, kind = rawget(field, "path"), rawget(field, "kind")
  if type(path) ~= "string" or path == "" then return false, at .. ".path must be a non-empty string" end
  if seenPaths[path] then return false, at .. ".path duplicates " .. path end
  if not RECORD_KINDS[kind] then return false, at .. ".kind must be enum or list" end
  seenPaths[path] = true

  for _, name in ipairs({ "label", "help" }) do
    ok, why = optionalType(field, name, "string", at)
    if not ok then return false, why end
  end
  ok, why = optionalType(field, "validate", "function", at)
  if not ok then return false, why end

  local choices
  if kind == "enum" then
    choices, why = validateChoices(rawget(field, "values"), at .. ".values", true)
    if not choices then return false, why end
    local input = rawget(field, "input")
    if input ~= nil and input ~= "cycle" and input ~= "text" then
      return false, at .. ".input must be \"cycle\" or \"text\""
    end
    local cycleMax
    cycleMax, why = lengthField(field, "cycleMax", at)
    if why then return false, why end
    if cycleMax ~= nil and cycleMax < 1 then return false, at .. ".cycleMax must be at least 1" end
    local default = rawget(field, "default")
    if default ~= nil then
      ok, why = scalarValue(default, at .. ".default")
      if not ok then return false, why end
      if not choicesContain(choices, default) then
        return false, at .. ".default is not present in the enum values"
      end
    end
  else
    ok, why = optionalType(field, "addLabel", "string", at)
    if not ok then return false, why end
    local values = rawget(field, "values")
    if values ~= nil then
      choices, why = validateChoices(values, at .. ".values", false)
      if not choices then return false, why end
    end
    local numeric = rawget(field, "numeric")
    if numeric ~= nil and numeric ~= "auto" and numeric ~= "only" then
      return false, at .. ".numeric must be \"auto\" or \"only\""
    end
    for _, name in ipairs({ "unique", "integer" }) do
      ok, why = optionalType(field, name, "boolean", at)
      if not ok then return false, why end
    end
    ok, why = validateBounds(field, at, false)
    if not ok then return false, why end
    ok, why = validateLengths(field, at)
    if not ok then return false, why end
  end
  return true
end

local function validSharedFile(name, extension)
  return type(name) == "string" and name ~= ""
    and name:match("^[%w_%-%.]+$") ~= nil
    and name:find("..", 1, true) == nil
    and name:sub(-#extension) == extension
end

local function validateCustom(custom, at, configKeys)
  local ok, why = plainTable(custom, at)
  if not ok then return false, why end
  local kind = rawget(custom, "type")
  if type(kind) ~= "string" then return false, at .. ".type must be a string" end

  if kind == "records" then
    local target = rawget(custom, "target")
    if type(target) ~= "string" or target == "" then
      return false, at .. ".target must be a non-empty string for records"
    end
    if configKeys[target] then return false, at .. ".target duplicates config key " .. target end
    configKeys[target] = at .. ".target"
    for _, name in ipairs({ "keyLabel", "addLabel", "empty", "keyPattern", "keyPatternMsg" }) do
      ok, why = optionalType(custom, name, "string", at)
      if not ok then return false, why end
    end
    local keyMaxLen
    keyMaxLen, why = lengthField(custom, "keyMaxLen", at)
    if why then return false, why end
    ok, why = optionalType(custom, "keyValidate", "function", at)
    if not ok then return false, why end
    local keyPattern = rawget(custom, "keyPattern")
    if keyPattern ~= nil then
      local patternOK = pcall(string.match, "", keyPattern)
      if not patternOK then return false, at .. ".keyPattern is not a valid Lua pattern" end
    end
    local keyValues = rawget(custom, "keyValues")
    if keyValues ~= nil then
      local entries
      entries, why = validateChoices(keyValues, at .. ".keyValues", false)
      if not entries then return false, why end
    end
    local fields = rawget(custom, "fields")
    if fields == nil then return false, at .. ".fields is required for records" end
    local entries
    entries, why = arrayValues(fields, at .. ".fields")
    if not entries then return false, why end
    local fieldPaths = {}
    for i, field in ipairs(entries) do
      ok, why = validateRecordField(field, at .. ".fields[" .. i .. "]", fieldPaths)
      if not ok then return false, why end
    end
  elseif kind == "listfile" then
    if not validSharedFile(rawget(custom, "file"), ".txt") then
      return false, at .. ".file must be a safe .txt basename for listfile"
    end
    ok, why = optionalType(custom, "empty", "string", at)
    if not ok then return false, why end
  elseif kind == "actionpanel" then
    if not validSharedFile(rawget(custom, "file"), ".lua") then
      return false, at .. ".file must be a safe .lua basename for actionpanel"
    end
    for _, name in ipairs({ "statusKey", "requestKey", "emptyText" }) do
      ok, why = optionalType(custom, name, "string", at, name ~= "emptyText")
      if not ok then return false, why end
    end
    local entries
    entries, why = arrayValues(rawget(custom, "options"), at .. ".options")
    if not entries then return false, why end
    for i, entry in ipairs(entries) do
      local entryAt = at .. ".options[" .. i .. "]"
      ok, why = plainTable(entry, entryAt)
      if not ok then return false, why end
      ok, why = optionalType(entry, "label", "string", entryAt, true)
      if not ok or rawget(entry, "label") == nil then
        return false, why or (entryAt .. ".label is required")
      end
      if rawget(entry, "value") == nil then return false, entryAt .. ".value is required" end
      ok, why = scalarValue(rawget(entry, "value"), entryAt .. ".value")
      if not ok then return false, why end
    end
  elseif kind == "modbrowser" then
    local mods = rawget(custom, "mods")
    if mods ~= nil then
      local entries
      entries, why = arrayValues(mods, at .. ".mods")
      if not entries then return false, why end
      for i, entry in ipairs(entries) do
        local entryAt = at .. ".mods[" .. i .. "]"
        ok, why = plainTable(entry, entryAt)
        if not ok then return false, why end
        for _, name in ipairs({ "name", "path", "winPath" }) do
          ok, why = optionalType(entry, name, "string", entryAt, true)
          if not ok or rawget(entry, name) == nil then
            return false, why or (entryAt .. "." .. name .. " is required")
          end
        end
      end
    end
  else
    return false, at .. ".type is unsupported: " .. tostring(kind)
  end
  return true
end

local function validSchema(t)
  local ok, why = plainTable(t, "schema")
  if not ok then return false, why end
  if type(rawget(t, "tab")) ~= "string" or rawget(t, "tab") == "" then
    return false, "schema.tab must be a non-empty string"
  end
  if type(rawget(t, "target")) ~= "string" or rawget(t, "target") == "" then
    return false, "schema.target must be a non-empty string"
  end

  for _, name in ipairs({ "note", "applyNote" }) do
    ok, why = optionalType(t, name, "string", "schema")
    if not ok then return false, why end
  end
  ok, why = optionalType(t, "live", "boolean", "schema")
  if not ok then return false, why end
  local order
  order, why = finiteField(t, "order", "schema")
  if why then return false, why end
  local schemaVersion
  schemaVersion, why = finiteField(t, "schemaVersion", "schema")
  if why then return false, why end
  if schemaVersion ~= nil and (schemaVersion < 0 or schemaVersion % 1 ~= 0) then
    return false, "schema.schemaVersion must be a non-negative whole number"
  end

  local defaults = rawget(t, "defaults")
  if defaults ~= nil then
    ok, why = plainTable(defaults, "schema.defaults")
    if not ok then return false, why end
    ok, why = validateDataTree(defaults, "schema.defaults")
    if not ok then return false, why end
  end

  local sections, sectionsErr = arrayValues(rawget(t, "sections"), "schema.sections")
  if not sections then return false, sectionsErr end
  local optionPaths, configKeys, dependencies = {}, {}, {}
  for si, section in ipairs(sections) do
    local at = "schema.sections[" .. si .. "]"
    ok, why = plainTable(section, at)
    if not ok then return false, why end
    ok, why = optionalType(section, "title", "string", at)
    if not ok then return false, why end
    ok, why = optionalType(section, "collapsed", "boolean", at)
    if not ok then return false, why end
    local options, custom = rawget(section, "options"), rawget(section, "custom")
    if options ~= nil and custom ~= nil then
      return false, at .. " must use options or custom, not both"
    end
    if options ~= nil then
      local entries, optionsErr = arrayValues(options, at .. ".options")
      if not entries then return false, optionsErr end
      for oi, option in ipairs(entries) do
        ok, why = validateOption(option, at .. ".options[" .. oi .. "]",
          optionPaths, configKeys, dependencies)
        if not ok then return false, why end
      end
    end
    if custom ~= nil then
      ok, why = validateCustom(custom, at .. ".custom", configKeys)
      if not ok then return false, why end
    end
    if options == nil and custom == nil then
      return false, at .. " requires options or custom"
    end
  end

  for _, dependency in ipairs(dependencies) do
    local target = optionPaths[dependency.path]
    if not target then return false, dependency.at .. " references an unknown option" end
    if dependency.value ~= nil then
      -- dependsValue: the dependency matches a picked value -- the target must
      -- be an enum and the value one of its choices (a typo here would hide
      -- the row forever, silently)
      if target.kind ~= "enum" then
        return false, dependency.at .. " with dependsValue must reference an enum option"
      end
      if not choicesContain(target.choices, dependency.value) then
        return false, dependency.at .. " dependsValue '" .. tostring(dependency.value)
               .. "' is not one of the enum's values"
      end
    elseif target.kind ~= "bool" then
      return false, dependency.at .. " must reference a bool option (or add dependsValue for an enum)"
    end
  end

  if defaults ~= nil then
    for path, meta in next, optionPaths do
      local value = rawget(defaults, path)
      if value ~= nil then
        ok, why = validateDefault(meta.opt, value, "schema.defaults[" .. path .. "]", meta.choices)
        if not ok then return false, why end
      end
    end
  end
  return true
end

-- sharedDir must end with a separator. Re-reads the index every call (cheap:
-- one loadfile + one per registered schema), so new registrations appear at
-- the next page build without restarting anything.
function S.loadAll(sharedDir, log)
  local all = {}
  local names = {}
  local indexPath = sharedDir .. "DarnMenu_schema_index.lua"
  local indexState = Writers.readState(indexPath)
  if type(indexState.value) == "table" then
    names = indexState.value
    if indexState.status == "recovered" and log then
      log("schema index primary is " .. tostring(indexState.primaryStatus)
        .. " -- reading " .. tostring(indexState.backupPath))
    end
  elseif indexState.status ~= "missing" and log then
    log("schema index " .. tostring(indexState.status) .. ": "
      .. tostring(indexState.error or "unknown error"))
  end

  -- SELF-HEAL a stale index: a mod that's uninstalled leaves its name in the
  -- index but takes its DarnMenu_schema_<name>.lua with it, so every page build
  -- logs a dead entry forever (zukane2's report). We prune names whose PRIMARY
  -- schema file is gone and rewrite the index atomically. We do NOT prune a name
  -- whose file is unreadable/malformed -- that's a live bug in an installed mod,
  -- not a leftover, and the mod owns its own entry.
  --
  -- Normalize through sorted numeric keys rather than ipairs: a hole in a broken
  -- index must not silently hide every registration after it.
  local indexedNames, normalized = {}, false
  for key, name in next, names do
    if type(key) == "number" and key >= 1 and key % 1 == 0 then
      indexedNames[#indexedNames + 1] = { key = key, name = name }
    else
      normalized = true
      if log then log("schema index has a non-list entry -- dropping it during repair") end
    end
  end
  table.sort(indexedNames, function(a, b) return a.key < b.key end)

  local keep, pruned, seen = {}, normalized, {}
  for expected, indexed in ipairs(indexedNames) do
    if indexed.key ~= expected then pruned = true end
    local name = indexed.name
    local seenKey = type(name) == "string" and name:lower() or nil
    local isBlocked = seenKey and (seenKey == "weaponproficiency" or seenKey == "livingarsenal" or seenKey == "palworldtuner" or seenKey == "paltuner")
    if type(name) == "string" and name:match("^[%w_%-]+$") and not seen[seenKey] and not isBlocked then
      seen[seenKey] = true
      local path = sharedDir .. "DarnMenu_schema_" .. name .. ".lua"
      local schemaState = Writers.readState(path)
      if schemaState.primaryStatus == "missing" and schemaState.backupStatus == "missing" then
        pruned = true
        if log then log("schema " .. name .. " gone -- pruning stale index entry") end
      else
        keep[#keep + 1] = name
        local t
        if schemaState.primaryStatus == "ok" then
          t = schemaState.primaryValue
        elseif schemaState.primaryStatus == "missing" and schemaState.backupStatus == "ok" then
          t = schemaState.value
          if log then log("schema " .. name .. " primary missing -- using readable backup") end
        end
        if t and (t.tab == "Living Arsenal" or t.tab == "Palworld Tuner" or t.tab == "Weapon Proficiency") then
          t = nil -- Block player editing of locked progression schemas
        end
        local validateCall, schemaOK, schemaErr = pcall(validSchema, t)
        if not validateCall then
          schemaErr, schemaOK = "schema validation failed: " .. tostring(schemaOK), false
        end
        if t ~= nil and schemaOK then
          -- targets are sandboxed: a schema may only write *_user files (plus the
          -- allowlisted ToastLib_config) -- never arbitrary shared configs
          -- Targets are sandboxed TWICE, and the second half is the one that matters:
          --   1. it must be a *_user file (or the allowlisted ToastLib_config), so a schema
          --      cannot take over another mod's real config; and
          --   2. it must be a BARE NAME -- no separators, no "..". Without that, a target of
          --      "../../../../evil_user" satisfies the _user rule and escapes shared/ entirely,
          --      because the path is built as SHARED .. target .. ".lua". DarnMenu is an OPEN
          --      platform (any author ships a schema file), so this is untrusted input by
          --      design. listfilePath() already applies exactly this rule to custom list files;
          --      the target had been left behind.
          local bareName = t.target:match("^[%w_%-%.]+$") ~= nil and t.target:find("%.%.") == nil
          if bareName and (t.target:match("_user$") or t.target == "ToastLib_config") then
            -- carry the REGISTERED name on the schema: it is the mod's folder name, which is
            -- what lets the page header show the mod's live version (read from Info.json at
            -- build). The schema text itself must never carry a version -- it persists across
            -- mod updates and would show a stale number.
            t.regName = name
            all[#all + 1] = t
          elseif log then log("schema " .. name .. " rejected: target=" .. tostring(t.target)
            .. " -- must be a plain name ending in _user (no slashes, no ..); ToastLib_config is the only exception") end
        elseif log then
          log("schema " .. name .. " invalid (" .. tostring(schemaState.primaryStatus)
            .. (schemaErr and (": " .. tostring(schemaErr))
              or (schemaState.primaryError and (": " .. tostring(schemaState.primaryError)) or ""))
            .. ")")
        end
      end
    else
      pruned = true   -- malformed/duplicate index entry: drop it
      if type(name) == "string" and seen[name:lower()] and log then
        log("schema " .. name .. " duplicated -- keeping one entry")
      end
    end
  end

  -- A valid backup is also used when the primary index disappeared during an
  -- interrupted swap. Reinstall it atomically. A malformed/unreadable existing
  -- primary is deliberately NOT overwritten; preserving evidence and third-party
  -- registrations is safer than guessing.
  local recoveredMissing = indexState.status == "recovered"
    and indexState.primaryStatus == "missing"
  local needsRepair = pruned or recoveredMissing
  if needsRepair then
    if indexState.primaryStatus == "ok" or indexState.primaryStatus == "missing" then
      local options = indexState.primaryStatus == "ok"
        and { expectedRaw = indexState.primaryRaw } or { expectMissing = true }
      local ok, writeErr, code = Writers.write(indexPath, keep, options)
      if ok then
        if log then log("transactionally repaired schema index (" .. #keep .. " live entries)") end
      elseif log then
        local suffix = code == "conflict" and " -- another writer won; retrying next menu open" or ""
        log("schema index repair failed: " .. tostring(writeErr) .. suffix)
      end
    elseif log then
      log("schema index repair skipped: existing primary is "
        .. tostring(indexState.primaryStatus) .. " (move or repair it manually)")
    end
  end
  table.sort(all, function(a, b)
    local oa, ob = tonumber(a.order) or 100, tonumber(b.order) or 100
    if oa ~= ob then return oa < ob end
    return tostring(a.tab) < tostring(b.tab)
  end)
  return all
end

-- current value for an option: user file overlay -> schema default
function S.currentValues(schema, fileTable)
  local vals = {}
  for _, sec in ipairs(schema.sections) do
    for _, opt in ipairs(sec.options or {}) do
      if opt.path then
        local v = fileTable and fileTable[opt.path]
        if v == nil then v = (schema.defaults or {})[opt.path] end
        if opt.kind == "keychord" then   -- normalize (accepts legacy string or table)
          local chord = S.encodeChord(v)
          if chord == nil then chord = S.encodeChord((schema.defaults or {})[opt.path]) end
          v = chord or ""
        end
        vals[opt.path] = v
      end
    end
  end
  return vals
end

-- coerce an edited string back to the option's kind; nil,err on bad input.
-- Validation (all optional, author-declared on the option):
--   number: min / max (inclusive bounds), integer = true (whole numbers only)
--   text:   maxLen / minLen (LENGTH IN BYTES -- Lua #; non-ASCII counts >1)
-- Out-of-range input is REJECTED with a message (never silently clamped): the
-- staged value stays in the box so the player can fix it.
-- optional author-supplied validator: validate = function(v) return ok, "why" end
-- (runs AFTER the built-in checks pass; errors in it are treated as rejection)
local function optionLabel(opt)
  local label = type(opt) == "table" and rawget(opt, "label") or nil
  if type(label) == "string" and label ~= "" then return label end
  local path = type(opt) == "table" and rawget(opt, "path") or nil
  if type(path) == "string" and path ~= "" then return path end
  return "Option"
end

local function runValidate(opt, v)
  if type(opt.validate) ~= "function" then return v end
  local okCall, ok, why = pcall(opt.validate, v)
  local label = optionLabel(opt)
  if not okCall then return nil, label .. ": validator failed (" .. tostring(ok) .. ")" end
  if not ok then return nil, label .. ": " .. tostring(why or "invalid value") end
  return v
end

-- ---- KEYCHORD (VirtualBjorn) ----------------------------------------------
-- A bind is either a legacy key string ("G") or a chord table { key, modifiers }.
local MODIFIER_ORDER = { "CONTROL", "ALT", "SHIFT" }
local MODIFIER_SET = { CONTROL = true, ALT = true, SHIFT = true }
local function modifierName(value)
  if type(value) ~= "string" then return nil end
  local name = value:upper()
  if name == "CTRL" then name = "CONTROL" end
  if MODIFIER_SET[name] then return name end
  return nil
end
-- Validate/clone the keychord wire format. Legacy string values stay valid; table
-- values are reduced to the safe public shape (no functions/userdata/cycles).
function S.normalizeChord(value)
  local key, rawModifiers
  if type(value) == "string" then
    key, rawModifiers = value, {}
  elseif type(value) == "table" then
    key, rawModifiers = value.key or value[1], value.modifiers
    if rawModifiers == nil then rawModifiers = {} end
  else
    return nil, "binding must be a key name or keychord table"
  end
  if type(key) ~= "string" or not key:match("%S") then return nil, "binding requires a key" end
  key = key:match("^%s*(.-)%s*$")
  if not key or key == "" then return nil, "binding requires a key" end
  key = key:upper()
  if modifierName(key) then return nil, "Ctrl, Alt, and Shift are modifiers; choose a primary key" end
  if type(rawModifiers) ~= "table" then return nil, "modifiers must be a list" end
  local count, maxIndex = 0, 0
  for index in pairs(rawModifiers) do
    if type(index) ~= "number" or index < 1 or index % 1 ~= 0 then return nil, "modifiers must be a contiguous list" end
    count = count + 1
    if index > maxIndex then maxIndex = index end
  end
  if count ~= maxIndex then return nil, "modifiers must be a contiguous list" end
  local requested = {}
  for index = 1, maxIndex do
    local name = modifierName(rawModifiers[index])
    if not name then return nil, "unsupported modifier at position " .. index end
    requested[name] = true
  end
  local modifiers = {}
  for _, name in ipairs(MODIFIER_ORDER) do if requested[name] then modifiers[#modifiers + 1] = name end end
  return { key = key, modifiers = modifiers }
end
-- Old unmodified binds stay strings on disk; modified binds use the table shape.
function S.encodeChord(value)
  local chord, err = S.normalizeChord(value)
  if not chord then return nil, err end
  if #chord.modifiers == 0 then return chord.key end
  return chord
end

function S.coerce(opt, raw)
  local label = optionLabel(opt)
  if opt.kind == "keychord" then
    local chord, err = S.encodeChord(raw)
    if not chord then return nil, label .. ": " .. err end
    return chord
  end
  if opt.kind == "number" then
    local n = tonumber(raw)
    if n == nil then return nil, label .. ": not a number" end
    if not finiteNumber(n) then return nil, label .. ": must be a finite number" end
    if opt.integer == true and n % 1 ~= 0 then return nil, label .. ": whole numbers only" end
    if finiteNumber(opt.min) and n < opt.min then return nil, label .. ": minimum is " .. opt.min end
    if finiteNumber(opt.max) and n > opt.max then return nil, label .. ": maximum is " .. opt.max end
    return runValidate(opt, n)
  end
  local s = tostring(raw)
  if opt.kind == "text" then
    if finiteNumber(opt.maxLen) and #s > opt.maxLen then
      return nil, label .. ": too long (max " .. opt.maxLen .. " chars)"
    end
    if finiteNumber(opt.minLen) and #s < opt.minLen then
      return nil, label .. ": too short (min " .. opt.minLen .. " chars)"
    end
    return runValidate(opt, s)
  end
  return s
end

-- effective live flag for an option: per-option wins, else the page default;
-- nil = undeclared (no dot, unknown in the apply message)
function S.optLive(schema, opt)
  if opt.live ~= nil then return opt.live end
  return schema.live
end

-- stepper math, pure for testability: current value + direction*step, clamped
-- to min/max, floored for integer options, float-drift killed. `boxText` is
-- whatever is in the edit box (the player may have typed); falls back to the
-- staged/saved value, then 0.
function S.stepValue(opt, boxText, fallback, dir)
  local cur = tonumber(boxText) or tonumber(fallback) or 0
  local v = cur + dir * (tonumber(opt.step) or 1)
  if opt.min and v < opt.min then v = opt.min end
  if opt.max and v > opt.max then v = opt.max end
  if opt.integer then v = math.floor(v + 0.5) end
  return tonumber(string.format("%.6g", v))
end

-- computed Apply message, pure for testability. savedKeys = {path=value,...};
-- optForPath(path) -> the option table or nil. Returns nil when any saved key
-- lacks a declared live flag (caller falls back to applyNote / generic text).
function S.applyMessage(schema, savedKeys, optForPath)
  local nLive, nRelaunch = 0, 0
  for path in pairs(savedKeys) do
    local opt = optForPath(path)
    local lv = nil   -- NOT `opt and ... or nil`: that collapses false to nil
    if opt then lv = S.optLive(schema, opt) end
    if lv == true then nLive = nLive + 1
    elseif lv == false then nRelaunch = nRelaunch + 1
    else return nil end
  end
  if nLive + nRelaunch == 0 then return nil end
  if nRelaunch == 0 then return "Saved -- applied live." end
  if nLive == 0 then return "Saved -- applies after your next relaunch." end
  return "Saved -- " .. nLive .. " applied live, " .. nRelaunch .. " after a relaunch."
end

-- ---- enum entries: plain values OR { value = ..., label = "display text" } --
function S.enumValue(entry)
  if type(entry) == "table" then return entry.value end
  return entry
end

function S.enumLabel(entry)
  if type(entry) == "table" then return tostring(entry.label or entry.value) end
  return tostring(entry)
end

-- display label for an option's STORED value (stored = the value, never the label)
function S.enumDisplay(opt, v)
  for _, e in ipairs(opt.values or {}) do
    if S.enumValue(e) == v then return S.enumLabel(e) end
  end
  return tostring(v)
end

-- human hint for an option's declared bounds -- shown on the label when the
-- author gave no explicit `note`, so players see limits BEFORE erroring
function S.constraintNote(opt)
  local parts = {}
  if opt.kind == "number" then
    if opt.min and opt.max then parts[#parts + 1] = opt.min .. "-" .. opt.max
    elseif opt.min then parts[#parts + 1] = "min " .. opt.min
    elseif opt.max then parts[#parts + 1] = "max " .. opt.max end
    if opt.integer then parts[#parts + 1] = "whole" end
  elseif opt.kind == "text" then
    if opt.maxLen then parts[#parts + 1] = "max " .. opt.maxLen .. " chars" end
    if opt.minLen then parts[#parts + 1] = "min " .. opt.minLen end
  end
  if #parts > 0 then return table.concat(parts, ", ") end
  return nil
end

-- EXPORTED FOR TESTING (2026-07-28). validSchema was private, so nothing exercised it -- and a
-- tightened rule silently invalidated a shipping mod's entire page (Standing Orders, see
-- validateChord). tools/test-darn.js now validates every real DarnMenu_schema_*.lua on disk
-- through this, so "one mod's page disappeared" is caught by the gates instead of in play.
S.validate = validSchema

return S
