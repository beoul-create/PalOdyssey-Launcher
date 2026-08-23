-- PalworldTuner (script half) -- multiplier-based; reads live 1.0 values and scales them.
-- No reflection / no memory scanning -- only assigns known properties, each wrapped in
-- pcall so a bad value can never crash the game. Pairs with the PalworldTuner PalSchema
-- data mod (enemy difficulty + QoL).
local ok, Config = pcall(require, "config")
if not ok or type(Config) ~= "table" then print("[PalworldTuner] config missing\n"); Config = {} end
local function log(m) if Config.log then print("[PalworldTuner] " .. m .. "\n") end end
local function rnd(x) if Config.round_up == false then return x else return math.ceil(x) end end
local GAME_SETTING = {
    { m="carry_weight_mult",            p="DefaultMaxInventoryWeight",           t="carryBase" },
    { m="carry_weight_mult",            p="AddMaxInventoryWeightPerStatusPoint", t="carryPerPoint" },
    { m="tech_point_mult",              p="technologyPointPerLevel",             t="techPerLevel" },
    { m="tech_point_mult",              p="TechnologyPoint_UnlockFastTravel",    t="techFastTravel" },
    { m="tech_point_mult",              p="bossTechnologyPointPerTowerBoss",     t="techTowerBoss" },
    { m="tech_point_mult",              p="bossTechnologyPointPerNormalBoss",    t="techNormalBoss" },
    { m="enemy_damage_mult",            p="EnemyDamageRate",                     t="enemyDamage" },
    { m="player_damage_taken_mult",     p="PlayerDamageTakenRate",               t="playerDamageTaken" },
    { m="player_stamina_decrease_mult", p="PlayerStaminaDecreaseRate",           t="playerStamina" },
    { m="player_hunger_depletion_mult", p="PlayerHungerDepletionRate",           t="playerHunger" },
    { m="pal_stamina_decrease_mult",    p="PalStaminaDecreaseRate",              t="palStamina" },
}
local function scale(o, p, mult, tag)
    if not mult or mult == 1 then return end
    pcall(function()
        local cur = o[p]
        if cur ~= nil then local nv = rnd(cur * mult); o[p] = nv; log(string.format("%s: %s -> %s (x%s)", tag, tostring(cur), tostring(nv), tostring(mult))) end
    end)
end
NotifyOnNewObject("/Script/Pal.PalGameSetting", function(s)
    if not s or not s:IsValid() then return end
    for _, e in ipairs(GAME_SETTING) do scale(s, e.p, Config[e.m], e.t) end
    log("PalGameSetting done")
end)
log("loaded")
