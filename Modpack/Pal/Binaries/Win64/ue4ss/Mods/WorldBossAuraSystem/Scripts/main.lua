---@diagnostic disable: undefined-global
-- ============================================================================
-- WorldBossAuraSystem: World Boss, Multi-Aura & Mythic Overlap Engine for PalOdyssey
--
-- 1. Periodic World Bosses:
--    - Extended to ALL official vanilla Pals in Paldeck roster.
--    - 1-hour interval, 10-minute despawn, 3x scale, 100x HP, 2x ATK/DEF.
--    - On-capture: 2x scale, 2x base HP, 200 IV talents.
--
-- 2. Standard Wild Auras (0.1% spawn chance / 1 in 1,000):
--    - Cannot overlap with each other or World Boss base aura.
--    - Corrupted (Neon Purple 253): 2x Move Speed, 2x Work Speed
--    - Celestial (Radiant Gold 254): 2x Move Speed, 2x Work Speed
--    - Overcharged (Neon Cyan 248): 2x Move Speed, 1.5x Jump, Swift + Runner
--    - Colossus (Neon Emerald 247): 1.5x Scale, 4x Defense, 2x HP, BurlyBody
--    - Berserker (Blood Crimson 246): 2.5x Attack, 0.5x Defense, 1.5x Move Speed, Ferocious + Musclehead
--    - Master Artisan (Amber Orange 245): 4x Work Speed, Max Sanity lock, Artisan + WorkSlave
--
-- 3. Mythic Auras (0.0001% spawn chance / 1 in 1,000,000):
--    - Regressor (Chrono Platinum 244): 2x Combat Stats, 2x Partner Skill, 100% Active Skill Cooldown (0 CD)
--    - Transmigrator (Cosmic Prismatic 243): Unlimited Level Cap, Lv 5 in ALL Work Suitabilities, Ranch Dog Coins
--    - OVERLAP RULES: Exclusive permission to overlap with ANY standard aura or World Boss!
--    - Regressor and Transmigrator cannot overlap with each other.
--    - When overlapped, Regressor or Transmigrator OVERTAKES the visual stencil outline.
--
-- 100% Original Custom Script for PalOdyssey
-- ============================================================================

local ok, Config = pcall(require, "config")
if not ok or type(Config) ~= "table" then
    Config = {
        enabled = true,
        log = true,

        -- ====================================================================
        -- 1. WORLD BOSS RAID CONFIGURATION (Extended to ALL Official Vanilla Pals)
        -- ====================================================================
        SpawnIntervalSeconds = 3600,    -- 1 hour between raid boss spawns
        DespawnSeconds       = 600,     -- 10 minutes despawn window if uncaptured

        BossPals = {
            "Anubis", "Astegon", "Bastet", "Beakon", "Beegarde", "Blazamut", "Blazamut_Ryu",
            "Blazehowl", "Blazehowl_Dark", "Bristla", "Broncherry", "Broncherry_Water", "Caprity",
            "Cattiva", "Celeray", "Chikipi", "ChickenPal", "Chillet", "Chillet_Dark", "Cremis",
            "Daedream", "DarkMutant", "DarkScorpion", "Dazzi", "Depresso", "Digtoise", "Dinossom",
            "Dinossom_Electric", "Direhowl", "Dumud", "Eikthyrdeer", "Eikthyrdeer_Ground", "Elizabee",
            "Elphidran", "Elphidran_Water", "Felbat", "Fenglope", "Flambelle", "Floppie", "Foxcicle",
            "Foxparks", "Frostallion", "Frostallion_Dark", "Fuddler", "Galeclaw", "Gikyou", "Gobfin",
            "Gobfin_Fire", "Gorirat", "Gorirat_Ground", "Grintale", "Grizzbolt", "Gumoss", "Hangyu",
            "Hangyu_Ground", "Helzephyr", "Hoocrates", "Incineram", "Incineram_Dark", "Jetragon",
            "Jolthog", "Jolthog_Ice", "Jormuntide", "Jormuntide_Fire", "Katress", "Katress_Fire",
            "Kelpsea", "Kelpsea_Fire", "Killamari", "Kingpaca", "Kingpaca_Ice", "Lamball", "Leezphaer",
            "Leezphaer_Fire", "Lethaur", "Lifmunk", "Loupmoon", "Lovander", "Lunaris", "Lyleen",
            "Lyleen_Dark", "Mammorest", "Mammorest_Ice", "Maraith", "Mau", "Mau_Ice", "Melpaca",
            "Menasting", "Menasting_Ground", "Mossanda", "Mossanda_Electric", "Mozzarina", "Nightingale",
            "Nitewing", "Nox", "Orserk", "Paladius", "Pengullet", "Penking", "Petallia", "Pirate",
            "Poltergeist", "Pterodactyl", "Pyrin", "Pyrin_Dark", "Quivern", "Quivern_Dark", "Ragnahawk",
            "Rayhound", "Reafy", "Reer", "Relaxaurus", "Relaxaurus_Electric", "Reptyro", "Reptyro_Ice",
            "Ribbuny", "Robinquill", "Robinquill_Ground", "Rooby", "Rushoar", "Shadowbeak", "Sibelyx",
            "SinisterGryphon", "Sparkit", "SpookyBeast", "Suzaku", "Suzaku_Water", "Swee", "Sweepa",
            "Tanzee", "Teafant", "Tocotoco", "Tombat", "Univolt", "Univolt_Ground", "Vaelet", "Vanwyrm",
            "Vanwyrm_Ice", "Verdash", "Vixy", "Warsect", "WaterLizard", "WoolFox", "Wumpo", "Wumpo_Grass"
        },

        SpawnPoints = {
            { Name = "Grassy Behemoth Hills",   X = 172000.0,  Y = -420000.0, Z = 3500.0  },
            { Name = "Desolate Dunes",          X = -120000.0, Y = -180000.0, Z = 4200.0  },
            { Name = "Astral Mountains",        X = -320000.0, Y = 250000.0,  Z = 12000.0 },
            { Name = "Windswept Plateau",       X = 45000.0,   Y = -310000.0, Z = 5800.0  },
            { Name = "Frozen Ravine",           X = -250000.0, Y = 100000.0,  Z = 8500.0  }
        },

        BossAura = { Name = "World Boss", StencilValue = 252, GlowColor = "NeonRed", IsBoss = true },

        BossScale      = 3.0,    -- Actor scale for spawned boss
        CapturedScale  = 2.0,    -- Actor scale after capture
        HpMultiplier   = 100,    -- HP multiplier (100x base)
        AtkMultiplier  = 2,      -- Attack multiplier
        DefMultiplier  = 2,      -- Defense multiplier
        CapturedTalent = 200,    -- Talent IV value for captured boss (200 = 2x permanent)

        -- ====================================================================
        -- 2. WILD AURA CONFIGURATION (0.1% Standard Wild Spawn Chance)
        -- ====================================================================
        WildAuraChance = 0.001, -- 0.1% chance (1 in 1,000) for standard wild auras

        WildAuras = {
            {
                Name = "Corrupted",
                Title = "Corrupted Void Pal",
                StencilValue = 253,
                GlowColor = "NeonPurple",
                RGB = { 0.6, 0.0, 1.0 },
                SpeedMult = 2.0,
                WorkMult = 2.0
            },
            {
                Name = "Celestial",
                Title = "Celestial Radiant Pal",
                StencilValue = 254,
                GlowColor = "NeonGold",
                RGB = { 1.0, 0.84, 0.0 },
                SpeedMult = 2.0,
                WorkMult = 2.0
            },
            {
                Name = "Overcharged",
                Title = "Overcharged Kinetic Pal",
                StencilValue = 248,
                GlowColor = "NeonCyan",
                RGB = { 0.0, 0.9, 1.0 },
                SpeedMult = 2.0,
                JumpMult = 1.5,
                Passives = { "Swift", "Runner" }
            },
            {
                Name = "Colossus",
                Title = "Colossus Titan Pal",
                StencilValue = 247,
                GlowColor = "NeonEmerald",
                RGB = { 0.0, 1.0, 0.3 },
                ScaleMult = 1.5,
                DefMult = 4.0,
                HpMult = 2.0,
                Passives = { "BurlyBody" }
            },
            {
                Name = "Berserker",
                Title = "Berserker Fury Pal",
                StencilValue = 246,
                GlowColor = "BloodCrimson",
                RGB = { 0.9, 0.0, 0.1 },
                AtkMult = 2.5,
                DefMult = 0.5,
                SpeedMult = 1.5,
                Passives = { "Ferocious", "Musclehead" }
            },
            {
                Name = "Master Artisan",
                Title = "Master Artisan Pal",
                StencilValue = 245,
                GlowColor = "AmberOrange",
                RGB = { 1.0, 0.55, 0.0 },
                WorkMult = 4.0,
                LockSanity = true,
                Passives = { "Artisan", "WorkSlave" }
            }
        },

        -- ====================================================================
        -- 3. MYTHIC AURA CONFIGURATION (0.0001% Ultra-Rare: 1 in 1,000,000)
        -- ====================================================================
        MythicAuraChance = 0.000001, -- 0.0001% chance (1 in 1,000,000)

        MythicAuras = {
            {
                Name = "Regressor",
                Title = "Regressor Chrono Pal",
                StencilValue = 244,
                GlowColor = "PlatinumSilver",
                RGB = { 0.75, 0.85, 1.0 },
                AtkMult = 2.0,
                DefMult = 2.0,
                HpMult = 2.0,
                PartnerSkillMult = 2.0,
                ZeroCooldown = true,
                IsMythic = true,
                Passives = { "Legend", "Vanguard", "StrongConstitution" }
            },
            {
                Name = "Transmigrator",
                Title = "Transmigrator Sovereign Pal",
                StencilValue = 243,
                GlowColor = "PrismaticCosmic",
                RGB = { 1.0, 0.3, 0.85 },
                AllWorkSuitabilities = 5,
                UnlimitedLevelGrowth = true,
                RanchDogCoinDrop = true,
                IsMythic = true,
                Passives = { "Legend", "Artisan", "Swift", "BurlyBody" }
            }
        },

        -- ====================================================================
        -- 4. INTEGRATION
        -- ====================================================================
        DaemonPort  = 8215,     -- RemoteServerDaemon port for Discord announcements
        NotifyToast = true      -- In-game DarnToasts notifications
    }
end

-- Native Ranch Farm Pal Roster (Pals with vanilla ranch drops)
local NativeRanchPals = {
    ChickenPal   = true,   -- Chikipi (Eggs)
    SheepBall    = true,   -- Lamball (Wool)
    CuteFox      = true,   -- Vixy (Spheres/Gold/Arrows)
    Ganesha      = true,   -- Mozzarina (Milk)
    CowPal       = true,   -- Mozzarina (Milk)
    WoolFox      = true,   -- Cremis (Wool)
    Caprico      = true,   -- Caprity (Berries)
    Alpaca       = true,   -- Melpaca (High Quality Cloth / Wool)
    Kelpie       = true,   -- Kelpsea (Pal Fluids)
    Kelpie_Fire  = true,   -- Kelpsea Ignis (High Quality Pal Oil)
    FlameBambee  = true,   -- Beegarde (Honey)
    SilkyMoth    = true,   -- Sibelyx (High Quality Cloth)
    NightFox     = true,   -- Mau (Gold Coins)
    NightFox_Ice = true,   -- Mau Cryst (Gold Coins)
    CottonDog    = true    -- Flambelle (Flame Organs)
}

-- ============================================================================
-- Logging
-- ============================================================================

local function Log(msg)
    if Config.log then
        print(string.format("[WorldBossAura] %s\n", tostring(msg)))
    end
end

if not Config.enabled then
    Log("Mod is disabled in config.")
    return
end

print("==========================================================")
print("  WorldBossAuraSystem: Multi-Tier Overlap Engine Active")
print("==========================================================")

-- ============================================================================
-- State Tracking
-- PalRecords[ptrKey] = {
--     BaseAura   = auraConfig (World Boss or 1 of 6 Wild Auras, or nil),
--     MythicAura = auraConfig (Regressor or Transmigrator, or nil),
--     PalName    = string,
--     Location   = table (if boss),
--     SpawnTime  = integer,
--     ActorRef   = palActor
-- }
-- ============================================================================

local PalRecords       = {}
local ZeroCooldownPals = {}  -- [ptrKey] = palActor (Regressor zero cooldown engine)
local TransmigratorPals = {} -- [ptrKey] = palActor (Transmigrator level uncap & ranch engine)

-- ============================================================================
-- 1. DARNTOAST IN-GAME NOTIFICATIONS
-- ============================================================================

local function SendBossToast(palName, auraName, locationName, mythicAuraName)
    if not Config.NotifyToast then return end
    pcall(function()
        local SDIR = (debug.getinfo(1, "S").source:gsub("^@", ""):gsub("[^/\\]+$", ""))
        package.path = SDIR .. "../../DarnToasts/Scripts/?.lua;" .. package.path
        local Toast = require("ToastLib").new("WorldBossAura")
        if Toast and Toast.notify then
            local title = string.format("⚠️ RAID BOSS: %s (%s Aura) at %s!", palName, auraName, locationName)
            if mythicAuraName then
                title = string.format("🌌 MYTHIC RAID BOSS: %s (%s + %s) at %s!", palName, auraName, mythicAuraName, locationName)
            end
            Toast.notify(title, 1.0, 0.05, 0.1)
        end
    end)
end

local function SendWildAuraToast(palName, auraConfig, isMythic, overlappedBaseName)
    if not Config.NotifyToast then return end
    pcall(function()
        local SDIR = (debug.getinfo(1, "S").source:gsub("^@", ""):gsub("[^/\\]+$", ""))
        package.path = SDIR .. "../../DarnToasts/Scripts/?.lua;" .. package.path
        local Toast = require("ToastLib").new("WorldBossAura")
        if Toast and Toast.notify then
            local rgb = auraConfig.RGB or { 1.0, 1.0, 1.0 }
            local msg = string.format("✨ RARE PAL: %s with %s Aura!", palName or "Pal", auraConfig.Name)
            if isMythic then
                if overlappedBaseName then
                    msg = string.format("👑 OVERLAPPED MYTHIC: %s with %s OVERTAKING %s Aura!", palName or "Pal", auraConfig.Name, overlappedBaseName)
                else
                    msg = string.format("🌌 ULTRA-MYTHIC PAL: %s with %s Aura!", palName or "Pal", auraConfig.Name)
                end
            end
            Toast.notify(msg, rgb[1], rgb[2], rgb[3])
        end
    end)
end

local function SendCaptureToast(palName, record)
    if not Config.NotifyToast or not record then return end
    pcall(function()
        local SDIR = (debug.getinfo(1, "S").source:gsub("^@", ""):gsub("[^/\\]+$", ""))
        package.path = SDIR .. "../../DarnToasts/Scripts/?.lua;" .. package.path
        local Toast = require("ToastLib").new("WorldBossAura")
        if Toast and Toast.notify then
            if record.BaseAura and record.BaseAura.IsBoss then
                if record.MythicAura then
                    Toast.notify(string.format("👑 MYTHIC RAID BOSS TAMED: %s (%s + %s)!", palName, record.BaseAura.Name, record.MythicAura.Name), 1.0, 0.84, 0.0)
                else
                    Toast.notify(string.format("🏆 RAID BOSS CAPTURED: %s tamed (2x Scale & Stats)!", palName), 0.0, 1.0, 0.5)
                end
            elseif record.MythicAura then
                Toast.notify(string.format("👑 MYTHIC SOVEREIGN TAMED: %s with %s Aura permanently bound!", palName, record.MythicAura.Name), 1.0, 0.84, 0.0)
            elseif record.BaseAura then
                Toast.notify(string.format("✨ %s TAMED: %s retains permanent aura & stat buffs!", record.BaseAura.Name, palName), 0.0, 0.85, 1.0)
            end
        end
    end)
end

-- ============================================================================
-- 2. DISCORD ANNOUNCEMENTS VIA REMOTE DAEMON HTTP API
-- ============================================================================

local function NotifyDaemonSpawn(palName, locationName, auraName, x, y)
    pcall(function()
        local payload = string.format(
            '{"event":"spawn","palName":"%s","location":"%s","aura":"%s","x":%.0f,"y":%.0f}',
            palName, locationName, auraName, x, y
        )
        local url = string.format("http://127.0.0.1:%d/api/world-boss", Config.DaemonPort)

        local httpOk, http = pcall(require, "socket.http")
        if httpOk and http then
            pcall(function()
                http.request{
                    url = url,
                    method = "POST",
                    headers = {
                        ["Content-Type"] = "application/json",
                        ["Content-Length"] = tostring(#payload)
                    },
                    source = require("ltn12").source.string(payload)
                }
            end)
        else
            local cmd = string.format(
                'curl -s -X POST -H "Content-Type: application/json" -d "%s" %s',
                payload:gsub('"', '\\"'), url
            )
            pcall(function() ExecuteConsoleCommand(nil, cmd, nil) end)
            pcall(function() os.execute('start /B ' .. cmd .. ' >nul 2>&1') end)
        end

        Log(string.format("Notified daemon: %s spawn at %s (%s aura)", palName, locationName, auraName))
    end)
end

local function NotifyDaemonCapture(palName, capturedBy)
    pcall(function()
        local payload = string.format(
            '{"event":"captured","palName":"%s","capturedBy":"%s"}',
            palName, capturedBy or "Unknown Pioneer"
        )
        local url = string.format("http://127.0.0.1:%d/api/world-boss", Config.DaemonPort)

        local httpOk, http = pcall(require, "socket.http")
        if httpOk and http then
            pcall(function()
                http.request{
                    url = url,
                    method = "POST",
                    headers = {
                        ["Content-Type"] = "application/json",
                        ["Content-Length"] = tostring(#payload)
                    },
                    source = require("ltn12").source.string(payload)
                }
            end)
        else
            local cmd = string.format(
                'curl -s -X POST -H "Content-Type: application/json" -d "%s" %s',
                payload:gsub('"', '\\"'), url
            )
            pcall(function() os.execute('start /B ' .. cmd .. ' >nul 2>&1') end)
        end

        Log(string.format("Notified daemon: %s captured by %s", palName, capturedBy or "Unknown"))
    end)
end

-- ============================================================================
-- 3. AURA VISUAL & STENCIL MANAGER (With Mythic Overtake Priority)
-- ============================================================================

local function AttachAuraStencil(pal, stencilValue)
    if not pal or not pal:IsValid() then return end
    pcall(function()
        local meshComp = pal.Mesh
        if meshComp and meshComp:IsValid() then
            meshComp.bRenderCustomDepth = true
            meshComp.CustomDepthStencilValue = stencilValue or 252
        end
    end)
end

local function UpdatePalVisualOutline(pal, record)
    if not pal or not pal:IsValid() or not record then return end
    pcall(function()
        -- Mythic Auras (Regressor / Transmigrator) take HIGHEST visual priority
        if record.MythicAura then
            AttachAuraStencil(pal, record.MythicAura.StencilValue)
        elseif record.BaseAura then
            AttachAuraStencil(pal, record.BaseAura.StencilValue)
        end
    end)
end

-- ============================================================================
-- 4. STAT & PHYSICS MODIFIER ENGINE (Safe Native Engine Compliance)
-- ============================================================================

local function ApplySingleAuraStats(pal, auraConfig)
    if not pal or not pal:IsValid() or not auraConfig then return end
    pcall(function()
        -- 1. Actor Scaling
        if auraConfig.ScaleMult and pal.SetActorScale3D then
            pal:SetActorScale3D({
                X = auraConfig.ScaleMult,
                Y = auraConfig.ScaleMult,
                Z = auraConfig.ScaleMult
            })
        end

        -- 2. Movement & Jump Physics
        local moveComp = pal.CharacterMovement
        if moveComp and moveComp:IsValid() then
            if auraConfig.SpeedMult and moveComp.MaxWalkSpeed then
                moveComp.MaxWalkSpeed = moveComp.MaxWalkSpeed * auraConfig.SpeedMult
            end
            if auraConfig.SpeedMult and moveComp.MaxCustomMovementSpeed then
                moveComp.MaxCustomMovementSpeed = moveComp.MaxCustomMovementSpeed * auraConfig.SpeedMult
            end
            if auraConfig.JumpMult and moveComp.JumpZVelocity then
                moveComp.JumpZVelocity = moveComp.JumpZVelocity * auraConfig.JumpMult
            end
        end

        -- 3. Parameter Component (Work, HP, ATK, DEF, Sanity, Support)
        local paramComp = pal.CharacterParameterComponent
        if paramComp and paramComp:IsValid() then
            -- Work Speed
            if auraConfig.WorkMult then
                if paramComp.SetCraftSpeed and paramComp.GetCraftSpeed then
                    local curCraft = paramComp:GetCraftSpeed() or 100
                    paramComp:SetCraftSpeed(math.floor(curCraft * auraConfig.WorkMult))
                end
                if paramComp.SetWorkSpeed and paramComp.GetWorkSpeed then
                    local curWork = paramComp:GetWorkSpeed() or 100
                    paramComp:SetWorkSpeed(math.floor(curWork * auraConfig.WorkMult))
                end
            end

            -- Combat HP
            if auraConfig.HpMult and paramComp.GetMaxHP and paramComp.SetMaxHP and paramComp.SetHP then
                local curHP = paramComp:GetMaxHP()
                if curHP and curHP > 0 then
                    local newHP = math.floor(curHP * auraConfig.HpMult)
                    paramComp:SetMaxHP(newHP)
                    paramComp:SetHP(newHP)
                end
            end

            -- Combat ATK
            if auraConfig.AtkMult and paramComp.GetAttack and paramComp.SetAttack then
                local curAtk = paramComp:GetAttack()
                if curAtk and curAtk > 0 then
                    paramComp:SetAttack(math.floor(curAtk * auraConfig.AtkMult))
                end
            end

            -- Combat DEF
            if auraConfig.DefMult and paramComp.GetDefense and paramComp.SetDefense then
                local curDef = paramComp:GetDefense()
                if curDef and curDef > 0 then
                    paramComp:SetDefense(math.floor(curDef * auraConfig.DefMult))
                end
            end

            -- Partner Skill Support Boost
            if auraConfig.PartnerSkillMult and paramComp.GetSupport and paramComp.SetSupport then
                local curSup = paramComp:GetSupport() or 100
                paramComp:SetSupport(math.floor(curSup * auraConfig.PartnerSkillMult))
            end

            -- Sanity Lock
            if auraConfig.LockSanity and paramComp.SetSanity and paramComp.SetMaxSanity then
                paramComp:SetMaxSanity(100)
                paramComp:SetSanity(100)
            end

            -- Transmigrator: All Work Suitabilities to Lv 5
            if auraConfig.AllWorkSuitabilities then
                local suitLvl = auraConfig.AllWorkSuitabilities
                local suits = {
                    "EmitFlame", "Watering", "Planting", "GenerateElectricity",
                    "Handcraft", "Gathering", "Lumbering", "Mining",
                    "OilExtraction", "Medicine", "Cooling", "Transport", "MonsterFarm"
                }
                for _, s in ipairs(suits) do
                    pcall(function()
                        local setter = paramComp["SetWorkSuitability_" .. s]
                        if setter then setter(paramComp, suitLvl) end
                    end)
                end
            end

            -- Transmigrator: Unlimited Level Cap Growth past Lv 80
            if auraConfig.UnlimitedLevelGrowth then
                pcall(function()
                    if paramComp.SetMaxLevel then paramComp:SetMaxLevel(999) end
                end)
            end
        end

        -- 4. Passives Injection
        local indParam = pal.GetIndividualParameter and pal:GetIndividualParameter() or nil
        if indParam and indParam:IsValid() then
            if auraConfig.Passives and #auraConfig.Passives > 0 and indParam.AddPassiveSkill then
                for _, passiveName in ipairs(auraConfig.Passives) do
                    pcall(function() indParam:AddPassiveSkill(passiveName) end)
                end
            end
            if auraConfig.PartnerSkillMult and indParam.SetPartnerSkillRank then
                pcall(function() indParam:SetPartnerSkillRank(4) end)
            end
        end
    end)
end

local function ApplyAllPalAuras(pal, record)
    if not pal or not pal:IsValid() or not record then return end
    local ptrKey = tostring(pal:GetAddress())

    -- 1. Apply Base Aura (if present)
    if record.BaseAura then
        ApplySingleAuraStats(pal, record.BaseAura)
    end

    -- 2. Apply Mythic Aura (if present) - stacks harmoniously
    if record.MythicAura then
        ApplySingleAuraStats(pal, record.MythicAura)

        if record.MythicAura.ZeroCooldown then
            ZeroCooldownPals[ptrKey] = pal
        end
        if record.MythicAura.UnlimitedLevelGrowth then
            TransmigratorPals[ptrKey] = pal
        end
    end

    -- 3. Visual Stencil: Mythic overtakes Base Aura
    UpdatePalVisualOutline(pal, record)
end

-- ============================================================================
-- 5. FAST REAL-TIME TICK ENGINES (Regressor 0 CD & Transmigrator Ranch Dog Coins)
-- ============================================================================

-- A. Regressor 100% Active Skill Cooldown Reduction (Instant Cast / 0 CD Loop)
LoopAsync(250, function()
    pcall(function()
        for ptrKey, pal in pairs(ZeroCooldownPals) do
            if not pal or not pal:IsValid() then
                ZeroCooldownPals[ptrKey] = nil
            else
                pcall(function()
                    local actComp = pal.ActionComponent
                    if actComp and actComp:IsValid() and actComp.ResetAllSkillCooldowns then
                        actComp:ResetAllSkillCooldowns()
                    end
                    local skillComp = pal.SkillComponent or pal.PalSkillComponent
                    if skillComp and skillComp:IsValid() and skillComp.SetCooldownRate then
                        skillComp:SetCooldownRate(0.0)
                    end
                end)
            end
        end
    end)
    return false
end)

-- B. Transmigrator Infinite Level Cap Watchdog & Ranch Dog Coin Producer
LoopAsync(25000, function()
    pcall(function()
        for ptrKey, pal in pairs(TransmigratorPals) do
            if not pal or not pal:IsValid() then
                TransmigratorPals[ptrKey] = nil
            else
                pcall(function()
                    local paramComp = pal.CharacterParameterComponent
                    if paramComp and paramComp:IsValid() then
                        -- 1. Ensure level uncap remains active
                        if paramComp.SetMaxLevel then paramComp:SetMaxLevel(999) end

                        -- 2. Ranch Dog Coin Drop: If working at base camp and has no pre-existing native drop
                        local charId = paramComp.GetCharacterID and tostring(paramComp:GetCharacterID()) or ""
                        if not NativeRanchPals[charId] then
                            local baseCamp = paramComp.GetAssignedBaseCamp and paramComp:GetAssignedBaseCamp() or nil
                            if baseCamp and baseCamp:IsValid() then
                                local loc = pal:K2_GetActorLocation()
                                if loc then
                                    local dropCount = math.random(1, 3)
                                    local spawnCmd = string.format("SpawnItem DogCoin %d %f %f %f", dropCount, loc.X, loc.Y, loc.Z + 30.0)
                                    local pc = GetPlayerController()
                                    local kismet = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
                                    if kismet and kismet:IsValid() and pc and pc:IsValid() then
                                        kismet:ExecuteConsoleCommand(pc, spawnCmd, nil)
                                        Log(string.format("💰 [TRANSMIGRATOR RANCH] %s produced %d Dog Coins at Base Camp!", charId, dropCount))
                                    end
                                end
                            end
                        end
                    end
                end)
            end
        end
    end)
    return false
end)

-- ============================================================================
-- 6. PERIODIC WORLD BOSS SPAWNER (All Official Vanilla Pals)
-- ============================================================================

local function ScaleWorldBossStats(pal)
    if not pal or not pal:IsValid() then return end
    pcall(function()
        local paramComp = pal.CharacterParameterComponent
        if paramComp and paramComp:IsValid() then
            if paramComp.GetMaxHP and paramComp.SetMaxHP and paramComp.SetHP then
                local baseMaxHP = paramComp:GetMaxHP()
                if baseMaxHP and baseMaxHP > 0 then
                    local bossHP = baseMaxHP * Config.HpMultiplier
                    paramComp:SetMaxHP(bossHP)
                    paramComp:SetHP(bossHP)
                end
            end
            if paramComp.GetAttack and paramComp.SetAttack then
                local baseAtk = paramComp:GetAttack()
                if baseAtk and baseAtk > 0 then
                    paramComp:SetAttack(baseAtk * Config.AtkMultiplier)
                end
            end
            if paramComp.GetDefense and paramComp.SetDefense then
                local baseDef = paramComp:GetDefense()
                if baseDef and baseDef > 0 then
                    paramComp:SetDefense(baseDef * Config.DefMultiplier)
                end
            end
        end
    end)
end

local function SpawnWorldBoss()
    pcall(function()
        local spawnIndex = math.random(#Config.SpawnPoints)
        local targetLocation = Config.SpawnPoints[spawnIndex]
        local selectedPal = Config.BossPals[math.random(#Config.BossPals)]
        local bossAura = Config.BossAura

        Log(string.format("=== SPAWNING WORLD BOSS: %s at %s ===", selectedPal, targetLocation.Name))

        local spawnedPal = nil

        pcall(function()
            if SpawnPalCharacter then
                local spawnTransform = {
                    Translation = { X = targetLocation.X, Y = targetLocation.Y, Z = targetLocation.Z },
                    Rotation = { Pitch = 0, Yaw = math.random(0, 360), Roll = 0, W = 1 },
                    Scale3D = { X = Config.BossScale, Y = Config.BossScale, Z = Config.BossScale }
                }
                spawnedPal = SpawnPalCharacter(selectedPal, spawnTransform)
            end
        end)

        if not spawnedPal or (spawnedPal and not spawnedPal:IsValid()) then
            pcall(function()
                local gameMode = FindFirstOf("PalGameMode")
                if gameMode and gameMode:IsValid() and gameMode.PalSpawner then
                    spawnedPal = gameMode.PalSpawner:SpawnPalByName(
                        selectedPal,
                        targetLocation.X, targetLocation.Y, targetLocation.Z,
                        0, false
                    )
                end
            end)
        end

        if not spawnedPal or (type(spawnedPal) == "userdata" and not spawnedPal:IsValid()) then
            pcall(function()
                local spawnCmd = string.format("SpawnPal %s %f %f %f", selectedPal, targetLocation.X, targetLocation.Y, targetLocation.Z)
                local KismetSystemLibrary = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
                local pc = GetPlayerController()
                if KismetSystemLibrary and KismetSystemLibrary:IsValid() and pc and pc:IsValid() then
                    KismetSystemLibrary:ExecuteConsoleCommand(pc, spawnCmd, nil)
                end
            end)
        end

        local function EnhanceBossInstance(pal)
            if not pal or not pal:IsValid() then return end
            pcall(function()
                if pal.SetActorScale3D then
                    pal:SetActorScale3D({ X = Config.BossScale, Y = Config.BossScale, Z = Config.BossScale })
                end
                ScaleWorldBossStats(pal)

                local ptrKey = tostring(pal:GetAddress())
                local record = PalRecords[ptrKey] or {
                    PalName   = selectedPal,
                    Location  = targetLocation,
                    SpawnTime = os.time(),
                    ActorRef  = pal
                }

                record.BaseAura = bossAura
                PalRecords[ptrKey] = record

                -- Roll Mythic Overlap check on World Boss spawn (0.0001% chance)
                if math.random() <= (Config.MythicAuraChance or 0.000001) then
                    local selectedMythic = Config.MythicAuras[math.random(#Config.MythicAuras)]
                    record.MythicAura = selectedMythic
                    Log(string.format("🌟 [MYTHIC OVERLAP] World Boss %s rolled %s Mythic Aura!", selectedPal, selectedMythic.Name))
                end

                ApplyAllPalAuras(pal, record)

                Log(string.format("World Boss active: %s (Scale: %.1fx, HP: x%d)", selectedPal, Config.BossScale, Config.HpMultiplier))
                SendBossToast(selectedPal, bossAura.Name, targetLocation.Name, record.MythicAura and record.MythicAura.Name or nil)
                NotifyDaemonSpawn(selectedPal, targetLocation.Name, record.MythicAura and (bossAura.Name .. " + " .. record.MythicAura.Name) or bossAura.Name, targetLocation.X, targetLocation.Y)
            end)
        end

        if spawnedPal and type(spawnedPal) == "userdata" and spawnedPal:IsValid() then
            EnhanceBossInstance(spawnedPal)
        else
            ExecuteWithDelay(500, function()
                pcall(function()
                    local allPals = FindAllOf("PalCharacter")
                    if allPals then
                        for _, pal in ipairs(allPals) do
                            if pal and pal:IsValid() then
                                local loc = pal:K2_GetActorLocation()
                                if loc then
                                    local dx, dy, dz = loc.X - targetLocation.X, loc.Y - targetLocation.Y, loc.Z - targetLocation.Z
                                    if math.sqrt(dx*dx + dy*dy + dz*dz) < 600.0 then
                                        EnhanceBossInstance(pal)
                                        break
                                    end
                                end
                            end
                        end
                    end
                end)
            end)
        end
    end)
end

-- ============================================================================
-- 7. DYNAMIC WILD SPAWN LISTENER (Standard vs Mythic Overlap Engine)
-- ============================================================================

pcall(function()
    NotifyOnNewObject("/Script/Pal.PalCharacter", function(pal)
        ExecuteWithDelay(350, function()
            if not pal or not pal:IsValid() then return end
            local ptrKey = tostring(pal:GetAddress())
            local record = PalRecords[ptrKey]

            -- Extract Pal name
            local palName = "Wild Pal"
            local charParam = pal.CharacterParameterComponent
            if charParam and charParam:IsValid() and charParam.GetCharacterID then
                local id = charParam:GetCharacterID()
                if id and id ~= "" then palName = tostring(id) end
            end

            -- 1. Roll Standard Wild Aura (0.1% chance) - ONLY if no BaseAura already assigned
            if not record or not record.BaseAura then
                if math.random() <= (Config.WildAuraChance or 0.001) then
                    local selectedWildAura = Config.WildAuras[math.random(#Config.WildAuras)]
                    record = record or { PalName = palName, ActorRef = pal }
                    record.BaseAura = selectedWildAura
                    PalRecords[ptrKey] = record
                    ApplyAllPalAuras(pal, record)
                    SendWildAuraToast(palName, selectedWildAura, false, nil)
                end
            end

            -- 2. Roll Mythic Aura (0.0001% chance) - CAN overlap with BaseAura, CANNOT overlap with other Mythic
            if not record or not record.MythicAura then
                if math.random() <= (Config.MythicAuraChance or 0.000001) then
                    local selectedMythic = Config.MythicAuras[math.random(#Config.MythicAuras)]
                    record = record or { PalName = palName, ActorRef = pal }
                    local prevBaseName = record.BaseAura and record.BaseAura.Name or nil
                    record.MythicAura = selectedMythic
                    PalRecords[ptrKey] = record
                    ApplyAllPalAuras(pal, record)
                    SendWildAuraToast(palName, selectedMythic, true, prevBaseName)
                end
            end
        end)
    end)
    Log("Dynamic Aura Spawn Listener armed (Standard 0.1% non-overlapping, Mythic 0.0001% overlapping).")
end)

-- ============================================================================
-- 8. CAPTURE HOOK (Boss Normalization & Overlapped Aura Permanent Retention)
-- ============================================================================

local function HandlePalCaptured(pal, playerActor)
    if not pal or not pal:IsValid() then return end
    local ptrKey = tostring(pal:GetAddress())
    local record = PalRecords[ptrKey]
    if not record then return end

    pcall(function()
        Log(string.format("=== PAL CAPTURED: %s ===", record.PalName))

        -- A. If it was a World Boss: Downsize & Normalize HP & Talents
        if record.BaseAura and record.BaseAura.IsBoss then
            if pal.SetActorScale3D then
                pal:SetActorScale3D({ X = Config.CapturedScale, Y = Config.CapturedScale, Z = Config.CapturedScale })
            end

            local indParam = pal.GetIndividualParameter and pal:GetIndividualParameter() or nil
            if indParam and indParam:IsValid() then
                pcall(function()
                    if indParam.SetTalentHP then indParam:SetTalentHP(Config.CapturedTalent) end
                    if indParam.SetTalentShotAttack then indParam:SetTalentShotAttack(Config.CapturedTalent) end
                    if indParam.SetTalentDefense then indParam:SetTalentDefense(Config.CapturedTalent) end
                end)
            end

            local paramComp = pal.CharacterParameterComponent
            if paramComp and paramComp:IsValid() then
                pcall(function()
                    local currentMax = paramComp:GetMaxHP()
                    if currentMax and currentMax > 0 then
                        local normHP = math.floor(currentMax / Config.HpMultiplier * Config.AtkMultiplier)
                        paramComp:SetMaxHP(normHP)
                        paramComp:SetHP(normHP)
                    end
                end)
            end

            local capturerName = "Unknown Pioneer"
            if playerActor and playerActor:IsValid() and playerActor.PlayerState then
                pcall(function()
                    local name = playerActor.PlayerState:GetPlayerName()
                    if name and name ~= "" then capturerName = tostring(name) end
                end)
            end

            NotifyDaemonCapture(record.PalName, capturerName)
        end

        -- B. Permanently re-affirm all active aura modifiers (Base + Mythic) on captured instance
        ApplyAllPalAuras(pal, record)

        SendCaptureToast(record.PalName, record)
    end)
end

pcall(function()
    RegisterHook("/Script/Pal.PalCaptureSubsystem:OnCaptureSuccess", function(Context, TargetPal, PlayerActor)
        ExecuteInGameThread(function()
            local pal = nil
            local player = nil
            pcall(function() pal = TargetPal:get() end)
            pcall(function() player = PlayerActor:get() end)
            HandlePalCaptured(pal, player)
        end)
    end)
end)

pcall(function()
    RegisterHook("/Script/Pal.PalCharacter:OnCaptured", function(Context, CapturedBy)
        ExecuteInGameThread(function()
            local pal = nil
            local player = nil
            pcall(function() pal = Context:get() end)
            pcall(function() player = CapturedBy:get() end)
            HandlePalCaptured(pal, player)
        end)
    end)
end)

-- ============================================================================
-- 9. PERIODIC WORLD BOSS TIMERS & DESPAWN CLEANUP
-- ============================================================================

local spawnIntervalMs = (Config.SpawnIntervalSeconds or 3600) * 1000

LoopAsync(spawnIntervalMs, function()
    pcall(function()
        Log("Periodic boss timer triggered. Spawning World Boss...")
        SpawnWorldBoss()
    end)
    return false
end)

LoopAsync(15000, function()
    pcall(function()
        local now = os.time()
        local despawnAge = Config.DespawnSeconds or 600 -- 10 minutes

        for ptrKey, record in pairs(PalRecords) do
            if record.BaseAura and record.BaseAura.IsBoss and (now - (record.SpawnTime or now) >= despawnAge) then
                Log(string.format("World Boss '%s' timed out after %ds. Triggering SAO polygon shatter dissolve effect.", record.PalName, despawnAge))
                
                pcall(function()
                    local pal = record.ActorRef
                    if pal and pal:IsValid() then
                        -- 1. In-game toast announcement that the boss shattered/dissipated
                        pcall(function()
                            local SDIR = (debug.getinfo(1, "S").source:gsub("^@", ""):gsub("[^/\\]+$", ""))
                            package.path = SDIR .. "../../DarnToasts/Scripts/?.lua;" .. package.path
                            local Toast = require("ToastLib").new("WorldBossAura")
                            if Toast and Toast.notify then
                                local locName = record.Location and record.Location.Name or "the battlefield"
                                Toast.notify(string.format("💨 BOSS DISSIPATED: %s shattered into polygon shards at %s!", record.PalName, locName), 0.7, 0.7, 0.8)
                            end
                        end)

                        -- 2. Trigger native Palworld death dissolve & SAO polygon shatter effect
                        pcall(function()
                            if pal.PlayDead then
                                pal:PlayDead()
                            elseif pal.CharacterParameterComponent and pal.CharacterParameterComponent:IsValid() then
                                pal.CharacterParameterComponent:SetHP(0)
                            end
                        end)

                        -- 3. Spawn crystalline Niagara/Emitter burst at boss location
                        pcall(function()
                            local loc = pal:K2_GetActorLocation()
                            if loc then
                                local niagara = StaticFindObject("/Script/Niagara.Default__NiagaraFunctionLibrary")
                                if niagara and niagara:IsValid() then
                                    local deathSys = StaticFindObject("/Game/Pal/Effect/Niagara/Dead/NS_PalDead.NS_PalDead") or
                                                     StaticFindObject("/Game/Pal/Effect/Niagara/Common/NS_Disappear.NS_Disappear")
                                    if deathSys and deathSys:IsValid() then
                                        niagara:SpawnSystemAtLocation(pal, deathSys, loc, { Pitch = 0, Yaw = 0, Roll = 0 }, { X = Config.BossScale, Y = Config.BossScale, Z = Config.BossScale }, true, true, 0, true)
                                    end
                                end
                            end
                        end)

                        -- 4. Delay actor cleanup by 3.5s to let the SAO shatter animation play out fully
                        ExecuteWithDelay(3500, function()
                            pcall(function()
                                if pal and pal:IsValid() and pal.K2_DestroyActor then
                                    pal:K2_DestroyActor()
                                end
                            end)
                        end)
                    end
                end)
                PalRecords[ptrKey] = nil
            end
        end
    end)
    return false
end)

Log("WorldBossAuraSystem v4.0 fully initialized.")
