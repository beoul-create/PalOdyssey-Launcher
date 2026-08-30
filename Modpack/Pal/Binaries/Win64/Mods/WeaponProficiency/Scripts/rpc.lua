-- rpc.lua -- the client->server proficiency channel, piggybacked on a shipping game RPC.
--
-- WHY A CHANNEL AT ALL. The server owns MaxDurability (measured 2026-08-18) but has no
-- idea what level any weapon is: the store is the client's. Stage 1 papered over that
-- with a flat multiplier, which is why a fishing rod currently gets the same max-level
-- durability as a Terraprisma. The server needs one number per weapon, and it needs it
-- from the machine that already knows it.
--
-- THE ALTERNATIVE WE ARE NOT BUILDING. A server-side store with its own counting would
-- fork: two tallies of the same kills, and prestige spent on the client that the server
-- never sees. This channel removes the need for a server store entirely -- the server
-- stops being a second brain and becomes a hand.
--
-- THE MECHANISM (PalPriority, runtime-proven; see the vault note). A real game RPC on
-- PalNetworkBaseCampComponent carries an FName and an int32:
--     Request_Server_int32(BaseCampId, FunctionName:FName, Value:int32)
-- We send our own FName prefix and ignore everything that is not ours.
--
-- THE HARD LIMIT, AND WHY THE PAYLOAD IS SPLIT THE WAY IT IS. Every unique FName string
-- interns PERMANENTLY in UE's global name table and is never freed. So the STRING must
-- be bounded-cardinality and the VARYING part must ride the int32:
--     FName  "LAdur|<weaponKey>"   one per weapon model -- bounded, ~30 for this mod
--     int32  level*100 + prestige  the part that changes, costing no name-table entry
-- Encoding the level into the string instead would mint a new permanent name per level
-- per weapon and leak for the life of the process. That is the misuse this file exists
-- to not commit.
--
-- SCOPE. The component belongs to the base-camp system, so a send needs a base camp to
-- send through. That is acceptable HERE and would not have been for detection: durability
-- is not latency-critical and a missed send is corrected by the next one, whereas a
-- detection handshake that silently fails away from base would be worse than no
-- detection at all.
--
-- NOT PROVEN IN THIS CODEBASE YET. PalPriority establishes that the channel works; it
-- does not establish OUR call shape. A native call new to this codebase gets proven in a
-- throwaway world before it goes near a live server, so the send is OFF by default and
-- the receive logs everything it sees without acting on it until cfg.rpcApply is set.

local RPC = {}

local PREFIX = "LAdur"
local SEP    = "|"

RPC.PREFIX = PREFIX

-- ---------------------------------------------------------------------------
-- CODEC. Pure functions, no engine contact, so the wire format is testable
-- without a game running -- which is the only part of this file that can be
-- proven from a desk.
-- ---------------------------------------------------------------------------

-- Levels are 0..999 and prestige 0..99, so the pair fits an int32 with room to
-- spare. Both are clamped rather than rejected: a value out of range is a bug on
-- our side, and dropping the message would lose a weapon's progress silently
-- where clamping merely caps it.
function RPC.encode(level, prestige)
  local lv = math.floor(tonumber(level) or 0)
  local pr = math.floor(tonumber(prestige) or 0)
  if lv < 0 then lv = 0 elseif lv > 999 then lv = 999 end
  if pr < 0 then pr = 0 elseif pr > 99 then pr = 99 end
  return lv * 100 + pr
end

function RPC.decode(v)
  local n = math.floor(tonumber(v) or 0)
  if n < 0 then n = 0 end
  local lv = math.floor(n / 100)
  local pr = n - lv * 100
  if lv > 999 then lv = 999 end
  return lv, pr
end

-- The FName half. Kept deliberately dull: a weapon key with the prefix on it and
-- nothing else, because every distinct string here is permanent.
function RPC.tag(weaponKey)
  return PREFIX .. SEP .. tostring(weaponKey or "?")
end

-- Returns the weapon key, or nil when the name is not ours. Anything not ours must
-- be ignored without comment -- this RPC is the game's, and other traffic on it is
-- normal rather than an error.
function RPC.parse(name)
  local s = tostring(name or "")
  local head, rest = s:match("^([^" .. SEP .. "]+)" .. SEP .. "(.+)$")
  if head ~= PREFIX then return nil end
  if rest == nil or rest == "" then return nil end
  return rest
end

-- A whole message in one call, so a caller never has to remember which half
-- carries what.
function RPC.pack(weaponKey, level, prestige)
  return RPC.tag(weaponKey), RPC.encode(level, prestige)
end

function RPC.unpack(name, value)
  local key = RPC.parse(name)
  if not key then return nil end
  local lv, pr = RPC.decode(value)
  return key, lv, pr
end

-- ---------------------------------------------------------------------------
-- TRANSPORT. Everything below touches the engine, and NONE of it is proven in
-- this codebase yet -- PalPriority proves the channel, not our call shape. So it
-- is written to be run in a throwaway world first: the receiver logs every
-- arrival and acts on nothing until cfg.rpcApply is set, and the sender does
-- nothing at all until cfg.rpcSend is set. Two switches, because "does the hook
-- fire with the parameters we expect" and "does a send land" are separate
-- questions and answering them together tells you neither.
-- ---------------------------------------------------------------------------

local HOOK = "/Script/Pal.PalNetworkBaseCampComponent:Request_Server_int32"

local function log(s) print("[LA/rpc] " .. tostring(s) .. "\n") end

-- Hook parameters arrive as wrapper objects whose accessor differs by type, and
-- guessing wrong yields nil rather than an error. So every read is attempted
-- several ways and the one that worked is REPORTED -- the log line from the
-- throwaway world is what settles the shape, not this comment.
local function readParam(p)
  if p == nil then return nil, "nil" end
  local ok1, v1 = pcall(function() return p:get() end)
  if ok1 and v1 ~= nil then
    local ok2, s2 = pcall(function() return v1:ToString() end)
    if ok2 and s2 ~= nil then return tostring(s2), "get():ToString()" end
    return v1, "get()"
  end
  local ok3, s3 = pcall(function() return p:ToString() end)
  if ok3 and s3 ~= nil then return tostring(s3), "ToString()" end
  local ok4, v4 = pcall(function() return tostring(p) end)
  if ok4 then return v4, "tostring()" end
  return nil, "unreadable"
end

-- SERVER SIDE. cb(weaponKey, level, prestige, ctx) fires only for our own traffic.
-- Returns true when the hook registered -- a false here means the channel is dead
-- and the caller should keep whatever fallback it has rather than assume silence
-- means "no messages yet".
function RPC.listen(cfg, cb)
  cfg = type(cfg) == "table" and cfg or {}
  local shapeLogged = false
  local okReg = pcall(function()
    RegisterHook(HOOK, function(self, pBase, pName, pValue)
      pcall(function()
        local nameV, nameHow = readParam(pName)
        local valV,  valHow  = readParam(pValue)

        -- ONE shape line per process. It names how each parameter was actually
        -- read, which is the whole deliverable of the throwaway-world run.
        if not shapeLogged then
          shapeLogged = true
          log(string.format("first arrival -- name via %s (%s), value via %s (%s)",
            tostring(nameHow), tostring(nameV), tostring(valHow), tostring(valV)))
        end

        local key, lv, pr = RPC.unpack(nameV, valV)
        if not key then return end          -- the game's own traffic: ignore silently

        if cfg.rpcApply ~= true then
          log(string.format("RX (not applied -- rpcApply is off) %s lv=%d prestige=%d",
            key, lv, pr))
          return
        end
        if cb then cb(key, lv, pr, self) end
      end)
    end)
  end)
  if not okReg then
    log("could not hook " .. HOOK .. " -- the channel is unavailable this session")
    return false
  end
  log("listening" .. (cfg.rpcApply == true and "" or " (observe only -- rpcApply is off)"))
  return true
end

-- CLIENT SIDE. Sends one weapon's progress. comp is the local player's
-- PalNetworkBaseCampComponent and baseId its camp id; resolving those is the
-- caller's job because it is the part that differs between topologies.
--
-- Deliberately NOT retried in here. A dropped message costs one stale durability
-- bar until the next equip, and a retry loop on a channel whose every distinct
-- string is permanent is the wrong instinct to build in early.
function RPC.send(cfg, comp, baseId, weaponKey, level, prestige)
  cfg = type(cfg) == "table" and cfg or {}
  if cfg.rpcSend ~= true then return false, "rpcSend is off" end
  if comp == nil then return false, "no base camp component" end
  local name, value = RPC.pack(weaponKey, level, prestige)
  local ok = pcall(function()
    comp:Request_Server_int32(baseId, FName(name), value)
  end)
  if not ok then return false, "call failed" end
  return true
end

return RPC
