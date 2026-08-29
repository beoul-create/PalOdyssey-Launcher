-- PalworldTuner (script half) -- multiplier-based; reads live 1.0 values and scales them.
local ok, Config = pcall(require, "config")
if not ok or type(Config) ~= "table" then print("[PalworldTuner] config missing\n"); Config = {} end
local function log(m) if Config.log then print("[PalworldTuner] " .. m .. "\n") end end
local function rnd(x) if Config.round_up == false then return x else return math.ceil(x) end end
local GAME_SETTING = {
    { m="carry_weight_mult", p="DefaultMaxInventoryWeight",           t="carryBase" },
    { m="carry_weight_mult", p="AddMaxInventoryWeightPerStatusPoint", t="carryPerPoint" },
    { m="tech_point_mult",   p="technologyPointPerLevel",             t="techPerLevel" },
    { m="tech_point_mult",   p="TechnologyPoint_UnlockFastTravel",    t="techFastTravel" },
    { m="tech_point_mult",   p="bossTechnologyPointPerTowerBoss",     t="techTowerBoss" },
    { m="tech_point_mult",   p="bossTechnologyPointPerNormalBoss",    t="techNormalBoss" },
}
local function scale(o, p, mult, tag)
    if not mult or mult == 1 then return end
    pcall(function() local cur = o[p]; if cur ~= nil then local nv = rnd(cur * mult); o[p] = nv; log(string.format("%s: %s -> %s (x%s)", tag, tostring(cur), tostring(nv), tostring(mult))) end end)
end
NotifyOnNewObject("/Script/Pal.PalGameSetting", function(s)
    if not s or not s:IsValid() then return end
    for _, e in ipairs(GAME_SETTING) do scale(s, e.p, Config[e.m], e.t) end
    log("PalGameSetting done")
end)

-- Optional proportional sprint-to-walk synchronization engine.
local syncOk, SprintSync = pcall(require, "movement_sync")
if syncOk and type(SprintSync) == "table" and SprintSync.apply then
    pcall(SprintSync.apply, Config)
end

log("loaded")
