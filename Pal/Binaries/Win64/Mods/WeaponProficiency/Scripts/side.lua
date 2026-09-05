-- side.lua -- which machine is this, resolved from the install path alone.
--
-- WHY NOT THE NET DRIVER. Reading the net driver or IsStandalone to work out
-- client-vs-server has crashed this codebase before and is a standing prohibition.
-- Both reads touch the engine object graph during boot, which is the exact window
-- where a walk returns a garbage pointer through every IsValid gate.
--
-- The install path answers the same question with a string compare and no engine
-- contact at all. debug.getinfo(1,"S").source is this file's own absolute path --
-- the same idiom store.lua uses to find shared/, so it is already proven here.
--
-- THE DISCRIMINATOR IS THE STEAM APP FOLDER, NOT THE UE4SS LAYOUT:
--   client   ...\steamapps\common\Palworld\Mods\NativeMods\UE4SS\Mods\<mod>\Scripts\
--   server   C:\PalServer\Pal\Binaries\Win64\ue4ss\Mods\<mod>\Scripts\
-- The classic Pal\Binaries\Win64\ue4ss layout is NOT a server tell: a client can
-- carry a second UE4SS install at exactly that path, and matching on it would call
-- that client a server. PalServer is the dedicated server's own product folder and
-- the client's is Palworld, so the two never collide.
--
-- Detection is a guess about someone else's disk, so it is overridable two ways and
-- it logs the path it judged. A wrong verdict must be readable in the boot line
-- rather than inferred from a feature quietly doing nothing.

local Side = {}

local SRC = (debug.getinfo(1, "S").source or ""):gsub("^@", "")
local DIR = SRC:gsub("[^/\\]+$", "")

-- A file named .server or .client beside the mod folder wins over the path sniff.
-- This is the escape hatch for an install laid out in a way this file did not predict;
-- it needs no config edit, so it survives a Workshop update replacing the mod folder.
-- io is pcall-guarded: a host that does not expose it must fall through to the path
-- sniff, not fail the whole module and take the mod down with it.
local function marker(name)
  local ok, found = pcall(function()
    local h = io.open(DIR .. "../" .. name, "r")
    if h then h:close(); return true end
    return false
  end)
  return ok and found == true
end

-- The verdict is a pure function of its inputs so it can be exercised against both
-- real install paths in a test, instead of being trusted on inspection. Order matters:
-- an explicit answer beats a marker, and a marker beats a sniff at someone else running a layout we did not predict.
function Side.judge(src, forced, hasServer, hasClient)
  if forced == "server" or forced == "client" then return forced, "config.side" end
  if hasServer then return "server", "marker file" end
  if hasClient then return "client", "marker file" end
  if type(src) ~= "string" or src == "" then
    -- No path to judge. Client is the safe default: it is what every install was
    -- before this file existed, so an unreadable source cannot silently disarm a
    -- working client.
    return "client", "no source path -- defaulted"
  end
  local norm = src:gsub("\\", "/"):lower()
  if norm:find("/palserver/", 1, true) then return "server", "install path" end
  return "client", "install path"
end

local ok, cfg = pcall(require, "config")
local forced = ok and type(cfg) == "table" and cfg.side or nil
local resolved, why = Side.judge(SRC, forced, marker(".server"), marker(".client"))

function Side.isServer() return resolved == "server" end
function Side.isClient() return resolved == "client" end
function Side.name()     return resolved end
function Side.why()      return why end
function Side.path()     return SRC end

return Side
