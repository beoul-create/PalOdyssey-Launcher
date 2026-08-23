-- ============================================================================
--  DarnMenu writers.lua -- reading, merging and atomically writing the config
--  files DarnMenu manages (Mods/shared/<target>.lua).
--
--  Rewritten by virtualbjorn, merged 2026-07-28: compare-and-swap against the
--  bytes we read, backup preservation, refusal to overwrite a malformed config,
--  and read-back verification of what was actually moved.
--
--  THE PROPERTY THAT MUST NEVER REGRESS, carried forward from the version this
--  replaces: THE PRIMARY FILE IS MOVED, NEVER DELETED. An earlier writer called
--  os.remove(path) before renaming the temp in, which leaves a window where
--  NEITHER file exists -- die there and the player's settings are simply gone.
--  Living Arsenal shipped exactly that sequence and wiped every player's weapon
--  progress. It is a proven failure, not a theoretical one. Windows rename
--  cannot overwrite, so the live file does have to move -- but it moves to .bak
--  and is put back on every failure path. Verified true of this rewrite:
--  removeFile() is applied only to temporaries and sidecars, never to the
--  primary, which is only ever renamed.
--
--  MERGE CONTRACT (unchanged): we only ever set the keys a schema manages; every
--  other key in the existing file is preserved verbatim. Comments are not (Lua
--  tables do not carry them) -- the generated header says so.
-- ============================================================================

local W = {}

local function errText(v)
  if v == nil then return "unknown error" end
  return tostring(v)
end

local function isMissingError(message, code)
  if code == 2 or code == 3 then return true end
  local s = tostring(message or ""):lower()
  return s:find("no such file", 1, true) ~= nil
    or s:find("cannot find", 1, true) ~= nil
    or s:find("not found", 1, true) ~= nil
end

-- Read exact bytes first. Compiling those same bytes (rather than calling
-- loadfile after a separate read) gives W.apply a trustworthy compare token.
local function readRaw(path)
  local f, openErr, openCode = io.open(path, "rb")
  if not f then
    if isMissingError(openErr, openCode) then return nil, "missing", errText(openErr) end
    return nil, "unreadable", errText(openErr)
  end

  local readCall, raw, readErr = pcall(function() return f:read("*a") end)
  local closeCall, closeOK, closeErr = pcall(function() return f:close() end)
  if not readCall then return nil, "unreadable", errText(raw) end
  if raw == nil then return nil, "unreadable", errText(readErr) end
  if not closeCall then return nil, "unreadable", errText(closeOK) end
  if closeOK == nil then return nil, "unreadable", errText(closeErr) end
  return raw, "ok"
end

local function compileSource(raw, path)
  local source = raw
  -- Match loadfile's useful handling for generated/config files.
  if source:sub(1, 3) == "\239\187\191" then source = source:sub(4) end
  if source:sub(1, 1) == "#" then source = source:gsub("^[^\r\n]*", "", 1) end
  if _VERSION == "Lua 5.1" and type(loadstring) == "function" then
    return loadstring(source, "@" .. path)
  end
  return load(source, "@" .. path, "t", _ENV)
end

local function readOne(path)
  local raw, status, readErr = readRaw(path)
  if status ~= "ok" then return { status = status, error = readErr } end

  local compileCall, chunk, compileErr = pcall(compileSource, raw, path)
  if not compileCall then
    return { status = "malformed", error = errText(chunk), raw = raw }
  end
  if not chunk then
    return { status = "malformed", error = errText(compileErr), raw = raw }
  end

  local ok, value = pcall(chunk)
  if not ok then
    return { status = "malformed", error = "execution failed: " .. errText(value), raw = raw }
  end
  if type(value) ~= "table" then
    return {
      status = "malformed",
      error = "config must return a table (got " .. type(value) .. ")",
      raw = raw,
    }
  end
  return { status = "ok", value = value, raw = raw }
end

-- Structured form used by writes and by callers that need to distinguish a
-- broken primary from a table successfully read from its backup.
function W.readState(path)
  local primary = readOne(path)
  local state = {
    path = path,
    primaryStatus = primary.status,
    primaryError = primary.error,
    primaryRaw = primary.raw,
    primaryValue = primary.value,
    source = nil,
    value = nil,
    status = primary.status,
    error = primary.error,
  }
  if primary.status == "ok" then
    state.value, state.source = primary.value, path
    return state
  end

  local backupPath = path .. ".bak"
  local backup = readOne(backupPath)
  state.backupPath = backupPath
  state.backupStatus = backup.status
  state.backupError = backup.error
  state.backupRaw = backup.raw
  if backup.status == "ok" then
    state.value = backup.value
    state.source = backupPath
    state.status = "recovered"
    state.error = "primary is " .. primary.status .. " (" .. errText(primary.error)
      .. "); using backup"
  elseif primary.status == "missing" and backup.status ~= "missing" then
    state.status = backup.status .. "_backup"
    state.error = "primary is missing; backup is " .. backup.status
      .. " (" .. errText(backup.error) .. ")"
  elseif backup.status ~= "missing" then
    state.error = "primary is " .. primary.status .. " (" .. errText(primary.error)
      .. "); backup is " .. backup.status .. " (" .. errText(backup.error) .. ")"
  end
  return state
end

local finiteNumber

local function clonePlain(value, stack, at)
  local kind = type(value)
  if kind == "string" or kind == "boolean" then return value end
  if kind == "number" then
    if not finiteNumber(value) then error("non-finite number at " .. at, 0) end
    return value
  end
  if kind ~= "table" then error("unsupported " .. kind .. " at " .. at, 0) end
  if stack[value] then error("cyclic table at " .. at, 0) end
  stack[value] = true
  local copy = {}
  for key in next, value do
    local keyKind = type(key)
    if keyKind ~= "string" and (keyKind ~= "number" or not finiteNumber(key)) then
      error("unsupported table key at " .. at, 0)
    end
    copy[key] = clonePlain(rawget(value, key), stack, at .. "[" .. tostring(key) .. "]")
  end
  stack[value] = nil
  return copy
end

-- Read a `return {...}` data config into metatable-free plain tables. A valid
-- .bak is returned when the primary cannot be read; W.apply still refuses to
-- replace an existing malformed primary. Schema loading uses readState directly
-- because author validators are functions rather than persisted data.
function W.read(path)
  local state = W.readState(path)
  if state.value == nil then return nil, state.status, state.error end
  local ok, value = pcall(clonePlain, state.value, {}, "$")
  if not ok then return nil, "malformed", tostring(value) end
  return value, state.status, state.error
end

finiteNumber = function(v)
  return v == v and v ~= math.huge and v ~= -math.huge
end

local function serNumber(v)
  if not finiteNumber(v) then error("cannot serialize NaN or infinity", 0) end
  if type(math.type) == "function" and math.type(v) == "integer" then
    return string.format("%d", v)
  end
  if v == math.floor(v) and math.abs(v) < 2 ^ 53 then
    return string.format("%.0f", v)
  end
  return string.format("%.17g", v)
end

-- Deterministic serializer. Unsupported keys/values and cycles are rejected
-- instead of silently becoming nil, because silently dropping an unmanaged key
-- would violate the merge contract.
local function serVal(v, indent, stack, at)
  local tv = type(v)
  if tv == "string" then return string.format("%q", v) end
  if tv == "number" then return serNumber(v) end
  if tv == "boolean" then return tostring(v) end
  if tv ~= "table" then
    error("cannot serialize " .. tv .. " at " .. at, 0)
  end
  if stack[v] then error("cannot serialize cyclic table at " .. at, 0) end
  stack[v] = true

  local stringKeys, numberKeys = {}, {}
  for key in next, v do
    local tk = type(key)
    if tk == "string" then
      stringKeys[#stringKeys + 1] = key
    elseif tk == "number" and finiteNumber(key) then
      numberKeys[#numberKeys + 1] = key
    else
      error("cannot serialize " .. tk .. " table key at " .. at, 0)
    end
  end
  table.sort(stringKeys)
  table.sort(numberKeys)

  local out = { "{" }
  for _, keyValue in ipairs(stringKeys) do
    local key = keyValue:match("^[%a_][%w_]*$") and keyValue
      or ("[" .. string.format("%q", keyValue) .. "]")
    out[#out + 1] = indent .. "  " .. key .. " = "
      .. serVal(rawget(v, keyValue), indent .. "  ", stack, at .. "." .. keyValue) .. ","
  end
  for _, keyValue in ipairs(numberKeys) do
    local key = serNumber(keyValue)
    out[#out + 1] = indent .. "  [" .. key .. "] = "
      .. serVal(rawget(v, keyValue), indent .. "  ", stack, at .. "[" .. key .. "]") .. ","
  end
  out[#out + 1] = indent .. "}"
  stack[v] = nil
  return table.concat(out, "\n")
end

function W.serialize(t)
  if type(t) ~= "table" then error("config root must be a table", 0) end
  return "-- Managed by DarnMenu (in-game options, ESC menu > Darn Mods).\n"
    .. "-- Hand edits to keys DarnMenu doesn't manage are preserved on save;\n"
    .. "-- comments are not. Most changes apply after a game relaunch.\n"
    .. "return " .. serVal(t, "", {}, "$") .. "\n"
end

local sidecarCounter = 0

local function uniqueSidecar(path, kind)
  local timePart = tostring(os.time() or 0)
  local clockPart = tostring(math.floor((os.clock() or 0) * 1000000))
  for _ = 1, 256 do
    sidecarCounter = sidecarCounter + 1
    local identity = tostring({}):gsub("[^%w]", "")
    local candidate = path .. "." .. kind .. "." .. timePart .. "." .. clockPart
      .. "." .. sidecarCounter .. "." .. identity
    local _, status = readRaw(candidate)
    if status == "missing" then return candidate end
  end
  return nil, "could not reserve a unique " .. kind .. " sidecar"
end

local function removeFile(path)
  local callOK, ok, message, code = pcall(os.remove, path)
  if not callOK then return false, errText(ok) end
  if ok then return true end
  if isMissingError(message, code) then return true end
  return false, errText(message)
end

local function renameFile(from, to)
  local callOK, ok, message = pcall(os.rename, from, to)
  if not callOK then return false, errText(ok) end
  if ok then return true end
  return false, errText(message)
end

local function writeTemp(path, body)
  local tmp, uniqueErr = uniqueSidecar(path, "tmp")
  if not tmp then return nil, uniqueErr end
  local f, openErr = io.open(tmp, "wb")
  if not f then return nil, "cannot open temporary file: " .. errText(openErr) end

  local writeCall, writeOK, writeErr = pcall(function() return f:write(body) end)
  local flushCall, flushOK, flushErr = pcall(function() return f:flush() end)
  local closeCall, closeOK, closeErr = pcall(function() return f:close() end)
  local problem
  if not writeCall then problem = errText(writeOK)
  elseif writeOK == nil then problem = errText(writeErr)
  elseif not flushCall then problem = errText(flushOK)
  elseif flushOK == nil then problem = errText(flushErr)
  elseif not closeCall then problem = errText(closeOK)
  elseif closeOK == nil then problem = errText(closeErr) end
  if problem then
    local _, cleanupErr = removeFile(tmp)
    if cleanupErr then problem = problem .. "; temporary cleanup failed: " .. cleanupErr end
    return nil, "temporary write failed: " .. problem
  end
  return tmp
end

local function expectedMatches(path, expectedStatus, expectedRaw)
  local raw, status, readErr = readRaw(path)
  if expectedStatus == "missing" then
    if status == "missing" then return true, false end
    return false, status == "ok",
      "config appeared while preparing the save" .. (readErr and (": " .. readErr) or "")
  end
  if status ~= "ok" then
    return false, status ~= "missing",
      "config became " .. status .. " while preparing the save: " .. errText(readErr)
  end
  if raw ~= expectedRaw then return false, true, "config changed while preparing the save" end
  return true, true
end

-- Windows cannot rename over an existing destination. The old primary is
-- therefore parked at canonical .bak, but an older .bak is first moved to a
-- unique holding name so neither generation is destroyed before commit.
local function atomicWriteBody(path, body, expectedStatus, expectedRaw)
  local tmp, tempErr = writeTemp(path, body)
  if not tmp then return false, tempErr, "temporary_write" end

  local matches, primaryExists, compareErr = expectedMatches(path, expectedStatus, expectedRaw)
  if not matches then
    local _, cleanupErr = removeFile(tmp)
    if cleanupErr then compareErr = compareErr .. "; temporary cleanup failed: " .. cleanupErr end
    return false, compareErr, "conflict"
  end

  if not primaryExists then
    local committed, commitErr = renameFile(tmp, path)
    if committed then return true end
    local _, cleanupErr = removeFile(tmp)
    if cleanupErr then commitErr = commitErr .. "; temporary retained at " .. tmp end
    return false, "cannot install new config: " .. commitErr, "commit"
  end

  local backup = path .. ".bak"
  local _, backupStatus, backupReadErr = readRaw(backup)
  if backupStatus ~= "ok" and backupStatus ~= "missing" then
    local _, cleanupErr = removeFile(tmp)
    local message = "cannot preserve existing backup: " .. errText(backupReadErr)
    if cleanupErr then message = message .. "; temporary retained at " .. tmp end
    return false, message, "backup_unreadable"
  end

  local heldBackup
  if backupStatus == "ok" then
    local uniqueErr
    heldBackup, uniqueErr = uniqueSidecar(path, "bak.previous")
    if not heldBackup then
      removeFile(tmp)
      return false, uniqueErr, "backup_prepare"
    end
    local parked, parkErr = renameFile(backup, heldBackup)
    if not parked then
      removeFile(tmp)
      return false, "cannot preserve previous backup: " .. parkErr, "backup_prepare"
    end
  end

  -- Backup preparation is outside the initial compare. Re-check immediately
  -- before moving the live primary so a newer writer is never displaced by the
  -- stale body this operation serialized.
  local stillMatches, _, finalCompareErr = expectedMatches(path, expectedStatus, expectedRaw)
  if not stillMatches then
    local restoreErr
    if heldBackup then
      local restored, why = renameFile(heldBackup, backup)
      if not restored then restoreErr = why end
    end
    local _, cleanupErr = removeFile(tmp)
    local message = finalCompareErr or "config changed before commit"
    if restoreErr then message = message .. "; previous backup retained at " .. heldBackup end
    if cleanupErr then message = message .. "; temporary retained at " .. tmp end
    return false, message, "conflict"
  end

  local parkedPrimary, parkPrimaryErr = renameFile(path, backup)
  if not parkedPrimary then
    local restoreErr
    if heldBackup then
      local restored, why = renameFile(heldBackup, backup)
      if not restored then restoreErr = why end
    end
    local _, cleanupErr = removeFile(tmp)
    local message = "cannot set aside existing config: " .. parkPrimaryErr
    if restoreErr then message = message .. "; previous backup retained at " .. heldBackup end
    if cleanupErr then message = message .. "; temporary retained at " .. tmp end
    return false, message, "backup_prepare"
  end

  -- The compare and rename cannot be one atomic operation in stock Lua. A
  -- concurrent writer can publish after the final compare but before this
  -- process parks `path`. Verify the bytes we actually moved before installing
  -- our temp; on mismatch, put that newer file back and report a conflict.
  local parkedRaw, parkedStatus, parkedReadErr = readRaw(backup)
  if parkedStatus ~= "ok" or parkedRaw ~= expectedRaw then
    local restoredPrimary, restorePrimaryErr = renameFile(backup, path)
    local restoredBackup, restoreBackupErr = true, nil
    if restoredPrimary and heldBackup then
      restoredBackup, restoreBackupErr = renameFile(heldBackup, backup)
    end
    local _, cleanupErr = removeFile(tmp)
    local message = parkedStatus == "ok"
      and "config changed during commit"
      or ("parked config became " .. parkedStatus .. ": " .. errText(parkedReadErr))
    if not restoredPrimary then
      message = message .. "; NEWER CONFIG IS RETAINED AT " .. backup
        .. " (restore failed: " .. errText(restorePrimaryErr) .. ")"
    elseif not restoredBackup then
      message = message .. "; previous backup retained at " .. heldBackup
        .. " (restore failed: " .. errText(restoreBackupErr) .. ")"
    end
    if cleanupErr then message = message .. "; temporary retained at " .. tmp end
    return false, message, restoredPrimary and "conflict" or "rollback_failed"
  end

  local committed, commitErr = renameFile(tmp, path)
  if not committed then
    local restoredPrimary, restorePrimaryErr = renameFile(backup, path)
    local restoredBackup, restoreBackupErr = true, nil
    if restoredPrimary and heldBackup then
      restoredBackup, restoreBackupErr = renameFile(heldBackup, backup)
    end
    local _, cleanupErr = removeFile(tmp)
    local message = "cannot install new config: " .. commitErr
    if not restoredPrimary then
      message = message .. "; ORIGINAL CONFIG IS RETAINED AT " .. backup
        .. " (restore failed: " .. errText(restorePrimaryErr) .. ")"
    elseif not restoredBackup then
      message = message .. "; previous backup retained at " .. heldBackup
        .. " (restore failed: " .. errText(restoreBackupErr) .. ")"
    end
    if cleanupErr then message = message .. "; temporary retained at " .. tmp end
    return false, message, restoredPrimary and "commit" or "rollback_failed"
  end

  if heldBackup then
    local removed, cleanupErr = removeFile(heldBackup)
    if not removed then
      return true, nil, {
        warning = "saved, but an older backup could not be removed",
        retainedBackup = heldBackup,
      }
    end
  end
  return true
end

-- Atomic plain-text companion used by managed list files. It shares the same
-- compare-before-swap, backup, and rollback behavior as Lua-table configs.
function W.writeText(path, body)
  if type(path) ~= "string" or path == "" then return false, "invalid path", "argument" end
  if type(body) ~= "string" then return false, "body must be a string", "argument" end
  local raw, status, readErr = readRaw(path)
  if status ~= "ok" and status ~= "missing" then
    return false, "refusing to replace " .. status .. " file at " .. path
      .. ": " .. errText(readErr), status
  end
  if status == "ok" and raw == body then return true end
  return atomicWriteBody(path, body, status, raw)
end

local function unsafePrimaryMessage(path, state)
  local message = "refusing to overwrite " .. state.status .. " config at " .. path
    .. ": " .. errText(state.error)
  if state.status == "malformed" and state.raw ~= nil then
    message = message .. " (move or repair it first)"
  end
  return message
end

-- Full-table write. Optional compatibility extension:
--   opts.expectedRaw = exact source bytes read earlier
--   opts.expectMissing = true when the caller observed no primary
-- Supplying one of these enables a compare-before-swap against that observation.
function W.write(path, t, opts)
  if type(path) ~= "string" or path == "" then return false, "invalid path", "argument" end
  local primary = readOne(path)
  if primary.status == "malformed" or primary.status == "unreadable" then
    return false, unsafePrimaryMessage(path, primary), primary.status
  end

  local serializeOK, body = pcall(W.serialize, t)
  if not serializeOK then return false, "serialize failed: " .. errText(body), "serialize" end
  if primary.status == "ok" and primary.raw == body then return true end

  opts = opts or {}
  local expectedStatus, expectedRaw
  if opts.expectMissing == true then
    expectedStatus = "missing"
  elseif opts.expectedRaw ~= nil then
    expectedStatus, expectedRaw = "ok", opts.expectedRaw
  else
    expectedStatus, expectedRaw = primary.status, primary.raw
  end
  if expectedStatus ~= "ok" and expectedStatus ~= "missing" then
    return false, "cannot safely replace " .. expectedStatus .. " config", expectedStatus
  end
  return atomicWriteBody(path, body, expectedStatus, expectedRaw)
end

local function copyTopLevel(source)
  local copy = {}
  for key, value in next, source do copy[key] = value end
  return copy
end

local function plainEqual(a, b, seen)
  if type(a) ~= type(b) then return false end
  if type(a) ~= "table" then return a == b end
  seen = seen or {}
  if seen[a] ~= nil then return seen[a] == b end
  seen[a] = b
  for key, value in next, a do
    local other = rawget(b, key)
    if other == nil or not plainEqual(value, other, seen) then return false end
  end
  for key in next, b do
    if rawget(a, key) == nil then return false end
  end
  return true
end

-- Merge staged {key=value} into the existing file. A missing primary can be
-- rebuilt from a valid .bak; a malformed/unreadable existing primary is never
-- replaced, even when its backup is valid. Three bounded retries handle another
-- mod writing the same config between our read and atomic swap.
--
-- opts.guardTopLevel may contain { key=..., exists=bool, value=... } entries.
-- Each guarded value is compared against the fresh table on every retry. This is
-- used for nested record maps: unrelated top-level changes may merge, but a
-- concurrent edit to the same record map is never overwritten wholesale.
function W.apply(path, staged, opts)
  if type(staged) ~= "table" then return false, "staged values must be a table", "argument" end
  opts = opts or {}
  local guards = opts.guardTopLevel
  if guards ~= nil and type(guards) ~= "table" then
    return false, "guardTopLevel must be a table", "argument"
  end
  for _ = 1, 3 do
    local state = W.readState(path)
    if state.primaryStatus == "malformed" or state.primaryStatus == "unreadable" then
      local suffix = state.backupStatus == "ok"
        and ("; a readable backup remains at " .. state.backupPath) or ""
      return false, "refusing to overwrite " .. state.primaryStatus .. " config at " .. path
        .. ": " .. errText(state.primaryError) .. suffix, state.primaryStatus
    end

    local base
    if state.primaryStatus == "ok" then
      base = state.value
    elseif state.primaryStatus == "missing" and state.backupStatus == "ok" then
      base = state.value
    elseif state.primaryStatus == "missing"
      and (state.backupStatus == nil or state.backupStatus == "missing") then
      base = {}
    else
      return false, "cannot preserve unmanaged keys: primary is missing and backup is "
        .. tostring(state.backupStatus) .. " (" .. errText(state.backupError) .. ")",
        state.backupStatus or "backup"
    end

    for _, guard in ipairs(guards or {}) do
      if type(guard) ~= "table"
          or (type(guard.key) ~= "string" and type(guard.key) ~= "number")
          or type(guard.exists) ~= "boolean" then
        return false, "invalid top-level guard", "argument"
      end
      local current = rawget(base, guard.key)
      local exists = current ~= nil
      if exists ~= guard.exists
          or (exists and not plainEqual(current, guard.value)) then
        return false, "config field '" .. tostring(guard.key)
          .. "' changed externally; reopen the menu before applying record edits", "stale"
      end
    end

    local merged = copyTopLevel(base)
    for key, value in next, staged do merged[key] = value end
    local options
    if state.primaryStatus == "ok" then
      options = { expectedRaw = state.primaryRaw }
    else
      options = { expectMissing = true }
    end
    local ok, message, code = W.write(path, merged, options)
    if ok then return true, message, code end
    if code ~= "conflict" then return false, message, code end
  end
  return false, "config kept changing while preparing the save; try Apply again", "conflict"
end

return W
