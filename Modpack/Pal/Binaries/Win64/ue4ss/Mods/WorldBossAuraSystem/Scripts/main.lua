---@diagnostic disable: undefined-global
-- ============================================================================
-- WorldBossAuraSystem: World Boss & Wild Aura Engine for PalOdyssey
-- 1. Periodic World Bosses: 1-hour interval, strictly "World Boss" Neon Red aura,
--    3x scale, 100x HP, 2x ATK/DEF, 10m despawn, on-capture 2x scale + 2x stats.
-- 2. Wild Auras (0.1% chance on normal wild Pal spawns):
--    - Corrupted (Neon Purple): 2x Move Speed, 2x Work Speed
--    - Celestial (Radiant Gold): 2x Move Speed, 2x Work Speed
--    - Overcharged (Neon Cyan): 2x Move Speed, 1.5x Jump, Swift + Runner
--    - Colossus (Neon Emerald): 1.5x Scale, 4x Defense, 2x HP, BurlyBody
--    - Berserker (Blood Crimson): 2.5x Attack, 0.5x Defense, 1.5x Move Speed, Ferocious + Musclehead
--    - Master Artisan (Amber Orange): 4x Work Speed, Max Sanity lock, Artisan + WorkSlave
--    - Regressor (Chrono Platinum): 2x Combat Stats, 2x Partner Skill, 100% Active Skill Cooldown (0 CD)
--    - Transmigrator (Cosmic Prismatic): Unlimited Level Cap (Bypasses Lv 80 cap), Lv 5 in ALL Work Suitabilities
-- 100% Original Custom Script for PalOdyssey
-- ============================================================================

local ok, Config = pcall(require, "config")
if not ok or type(Config) ~= "table" then
    Config = {
        enabled = true,
        log = true,

        -- ====================================================================
        -- 1. WORLD BOSS RAID CONFIGURATION
        -- ====================================================================
        SpawnIntervalSeconds = 3600,    -- 1 hour between raid boss spawns
        DespawnSeconds       = 600,     -- 10 minutes despawn window if uncaptured

        BossPals = {
            "Foxparks",
            "Orserk",
            "Mammorest",
            "Chillet",
            "Anubis"
        },

        SpawnPoints = {
            { Name = "Grassy Behemoth Hills",   X = 172000.0,  Y = -420000.0, Z = 3500.0  },
            { Name = "Desolate Dunes",          X = -120000.0, Y = -180000.0, Z = 4200.0  },
            { Name = "Astral Mountains",        X = -320000.0, Y = 250000.0,  Z = 12000.0 },
            { Name = "Windswept Plateau",       X = 45000.0,   Y = -310000.0, Z = 5800.0  },
            { Name = "Frozen Ravine",           X = -250000.0, Y = 100000.0,  Z = 8500.0  }
        },

        BossAura = { Name = "World Boss", StencilValue = 252, GlowColor = "NeonRed" },

        BossScale      = 3.0,    -- Actor scale for spawned boss
        CapturedScale  = 2.0,    -- Actor scale after capture
        HpMultiplier   = 100,    -- HP multiplier (100x base)
        AtkMultiplier  = 2,      -- Attack multiplier
        DefMultiplier  = 2,      -- Defense multiplier
        CapturedTalent = 200,    -- Talent IV value for captured boss (200 = 2x permanent)

        -- ====================================================================
        -- 2. WILD AURA CONFIGURATION (0.1% Spawn Chance: 1 in 1,000)
        -- ====================================================================
        WildAuraChance = 0.001, -- 0.1% chance on normal wild Pal spawns

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
            },
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
                Passives = { "Legend", "Artisan", "Swift", "BurlyBody" }
            }
        },

        -- ====================================================================
        -- 3. INTEGRATION
        -- ====================================================================
        DaemonPort  = 8215,     -- RemoteServerDaemon port for Discord announcements
        NotifyToast = true      -- In-game DarnToasts notifications
    }
end

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
print("  WorldBossAuraSystem: Raid & Multi-Aura Engine Active")
print("==========================================================")

-- ============================================================================
-- State Tracking
-- ============================================================================

local ActiveBosses     = {}  -- [ptrKey] = { PalName, Aura, SpawnTime, ActorRef }
local ActiveWildAuras  = {}  -- [ptrKey] = { PalName, AuraConfig, ActorRef }
local ZeroCooldownPals = {}  -- [ptrKey] = palActor (Regressor zero cooldown loop)
local TransmigratorPals = {} -- [ptrKey] = palActor (Transmigrator uncapped level loop)

-- ============================================================================
-- 1. DARNTOAST IN-GAME NOTIFICATIONS
-- ============================================================================

local function SendBossToast(palName, auraName, locationName)
    if not Config.NotifyToast then return end
    pcall(function()
        local SDIR = (debug.getinfo(1, "S").source:gsub("^@", ""):gsub("[^/\\]+$", ""))
        package.path = SDIR .. "../../DarnToasts/Scripts/?.lua;" .. package.path
        local Toast = require("ToastLib").new("WorldBossAura")
        if Toast and Toast.notify then
            Toast.notify(
                string.format("⚠️ RAID BOSS: %s (%s Aura) at %s!", palName, auraName, locationName),
                1.0, 0.05, 0.1 -- Glowing Neon Red
            )
        end
    end)
end

local function SendWildAuraToast(palName, auraConfig)
    if not Config.NotifyToast then return end
    pcall(function()
        local SDIR = (debug.getinfo(1, "S").source:gsub("^@", ""):gsub("[^/\\]+$", ""))
        package.path = SDIR .. "../../DarnToasts/Scripts/?.lua;" .. package.path
        local Toast = require("ToastLib").new("WorldBossAura")
        if Toast and Toast.notify then
            local rgb = auraConfig.RGB or { 1.0, 1.0, 1.0 }
            Toast.notify(
                string.format("✨ RARE WILD PAL: %s with %s Aura!", palName or "Pal", auraConfig.Name),
                rgb[1], rgb[2], rgb[3]
            )
        end
    end)
end

local function SendCaptureToast(palName, isBoss, auraName)
    if not Config.NotifyToast then return end
    pcall(function()
        local SDIR = (debug.getinfo(1, "S").source:gsub("^@", ""):gsub("[^/\\]+$", ""))
        package.path = SDIR .. "../../DarnToasts/Scripts/?.lua;" .. package.path
        local Toast = require("ToastLib").new("WorldBossAura")
        if Toast and Toast.notify then
            if isBoss then
                Toast.notify(string.format("🏆 RAID BOSS CAPTURED: %s has been tamed (2x Scale & Stats)!", palName), 0.0, 1.0, 0.5)
            else
                Toast.notify(string.format("✨ %s TAMED: %s retains permanent aura & stat buffs!", auraName or "Aura", palName), 0.0, 0.85, 1.0)
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
-- 3. AURA ATTACHMENT SYSTEM (Custom Depth Stencil Outline)
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

-- ============================================================================
-- 4. DYNAMIC WILD AURA BUFF APPLICATION
-- ============================================================================

local function ApplyWildAuraBuffs(pal, auraConfig)
    if not pal or not pal:IsValid() or not auraConfig then return end
    local ptrKey = tostring(pal:GetAddress())

    pcall(function()
        -- A. Visual Stencil Outline
        AttachAuraStencil(pal, auraConfig.StencilValue)

        -- B. Actor Scaling
        if auraConfig.ScaleMult and pal.SetActorScale3D then
            pal:SetActorScale3D({
                X = auraConfig.ScaleMult,
                Y = auraConfig.ScaleMult,
                Z = auraConfig.ScaleMult
            })
        end

        -- C. Movement & Jump Physics
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

        -- D. Parameter Component (Work, HP, ATK, DEF, Sanity, Support)
        local paramComp = pal.CharacterParameterComponent
        if paramComp and paramComp:IsValid() then
            -- Work Speed Multipliers
            if auraConfig.WorkMult then
                if paramComp.SetCraftSpeed then
                    local curCraft = paramComp:GetCraftSpeed() or 100
                    paramComp:SetCraftSpeed(math.floor(curCraft * auraConfig.WorkMult))
                end
                if paramComp.SetWorkSpeed then
                    local curWork = paramComp:GetWorkSpeed() or 100
                    paramComp:SetWorkSpeed(math.floor(curWork * auraConfig.WorkMult))
                end
            end

            -- Combat Stats
            if auraConfig.HpMult and paramComp.GetMaxHP and paramComp.SetMaxHP and paramComp.SetHP then
                local curHP = paramComp:GetMaxHP()
                if curHP and curHP > 0 then
                    local newHP = math.floor(curHP * auraConfig.HpMult)
                    paramComp:SetMaxHP(newHP)
                    paramComp:SetHP(newHP)
                end
            end

            if auraConfig.AtkMult and paramComp.GetAttack and paramComp.SetAttack then
                local curAtk = paramComp:GetAttack()
                if curAtk and curAtk > 0 then
                    paramComp:SetAttack(math.floor(curAtk * auraConfig.AtkMult))
                end
            end

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
                    TransmigratorPals[ptrKey] = pal
                end)
            end
        end

        -- E. Passives Injection (Individual Parameter)
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

        -- F. Regressor Zero Cooldown Registration
        if auraConfig.ZeroCooldown then
            ZeroCooldownPals[ptrKey] = pal
        end
    end)
end

-- ============================================================================
-- 5. FAST REAL-TIME TICK ENGINES (Regressor 0 CD & Transmigrator Level Uncap)
-- ============================================================================

-- A. Regressor 100% Active Skill Cooldown Reduction (Instant Cast / 0 CD Loop)
LoopAsync(250, function()
    pcall(function()
        for ptrKey, pal in pairs(ZeroCooldownPals) do
            if not pal or not pal:IsValid() then
                ZeroCooldownPals[ptrKey] = nil
            else
                pcall(function()
                    -- Reset skill cooldown timers across action components
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

-- B. Transmigrator Infinite Level Cap Watchdog
LoopAsync(2000, function()
    pcall(function()
        for ptrKey, pal in pairs(TransmigratorPals) do
            if not pal or not pal:IsValid() then
                TransmigratorPals[ptrKey] = nil
            else
                pcall(function()
                    local paramComp = pal.CharacterParameterComponent
                    if paramComp and paramComp:IsValid() then
                        if paramComp.SetMaxLevel then paramComp:SetMaxLevel(999) end
                    end
                end)
            end
        end
    end)
    return false
end)

-- ============================================================================
-- 6. WILD AURA PAL ENHANCEMENT (0.1% Spawn Chance)
-- ============================================================================

local function EnhanceWildPal(pal, auraConfig)
    if not pal or not pal:IsValid() or not auraConfig then return end
    local ptrKey = tostring(pal:GetAddress())
    if ActiveWildAuras[ptrKey] or ActiveBosses[ptrKey] then return end

    pcall(function()
        local palName = "Wild Pal"
        local charParam = pal.CharacterParameterComponent
        if charParam and charParam:IsValid() and charParam.GetCharacterID then
            local id = charParam:GetCharacterID()
            if id and id ~= "" then palName = tostring(id) end
        end

        ApplyWildAuraBuffs(pal, auraConfig)

        ActiveWildAuras[ptrKey] = {
            PalName    = palName,
            AuraConfig = auraConfig,
            ActorRef   = pal
        }

        Log(string.format("✨ [WILD AURA] Generated %s (%s Aura, Stencil %d) (Ptr: %s)",
            palName, auraConfig.Name, auraConfig.StencilValue, ptrKey))

        SendWildAuraToast(palName, auraConfig)
    end)
end

-- ============================================================================
-- 7. PERIODIC WORLD BOSS SPAWNER (Strictly "World Boss" Neon Red Aura)
-- ============================================================================

local function ScaleBossStats(pal)
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

        Log(string.format("=== SPAWNING WORLD BOSS: %s (%s Aura) at %s ===",
            selectedPal, bossAura.Name, targetLocation.Name))

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
                ScaleBossStats(pal)
                AttachAuraStencil(pal, bossAura.StencilValue)

                local ptrKey = tostring(pal:GetAddress())
                ActiveBosses[ptrKey] = {
                    PalName   = selectedPal,
                    Aura      = bossAura,
                    Location  = targetLocation,
                    SpawnTime = os.time(),
                    ActorRef  = pal
                }

                Log(string.format("World Boss active: %s (Scale: %.1fx, HP: x%d)", selectedPal, Config.BossScale, Config.HpMultiplier))
                SendBossToast(selectedPal, bossAura.Name, targetLocation.Name)
                NotifyDaemonSpawn(selectedPal, targetLocation.Name, bossAura.Name, targetLocation.X, targetLocation.Y)
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
-- 8. DYNAMIC WILD PAL SPAWN LISTENER (0.1% Aura Roll)
-- ============================================================================

pcall(function()
    NotifyOnNewObject("/Script/Pal.PalCharacter", function(pal)
        ExecuteWithDelay(350, function()
            if not pal or not pal:IsValid() then return end
            local ptrKey = tostring(pal:GetAddress())
            if ActiveBosses[ptrKey] or ActiveWildAuras[ptrKey] then return end

            -- Roll 0.1% chance (1 in 1,000)
            if math.random() <= (Config.WildAuraChance or 0.001) then
                local selectedWildAura = Config.WildAuras[math.random(#Config.WildAuras)]
                EnhanceWildPal(pal, selectedWildAura)
            end
        end)
    end)
    Log("Wild Aura spawn listener initialized (0.1% chance across 8 custom Auras).")
end)

-- ============================================================================
-- 9. CAPTURE HOOK (Boss Downsizing & Wild Aura Permanent Retention)
-- ============================================================================

local function HandlePalCaptured(pal, playerActor)
    if not pal or not pal:IsValid() then return end
    local ptrKey = tostring(pal:GetAddress())

    -- A. Check if it's a World Boss
    local bossInfo = ActiveBosses[ptrKey]
    if bossInfo then
        pcall(function()
            Log(string.format("=== RAID BOSS CAPTURED: %s ===", bossInfo.PalName))

            -- 1. Downsize to 2x scale
            if pal.SetActorScale3D then
                pal:SetActorScale3D({ X = Config.CapturedScale, Y = Config.CapturedScale, Z = Config.CapturedScale })
            end

            -- 2. Permanent 2x IV Talents
            local indParam = pal.GetIndividualParameter and pal:GetIndividualParameter() or nil
            if indParam and indParam:IsValid() then
                pcall(function()
                    if indParam.SetTalentHP then indParam:SetTalentHP(Config.CapturedTalent) end
                    if indParam.SetTalentShotAttack then indParam:SetTalentShotAttack(Config.CapturedTalent) end
                    if indParam.SetTalentDefense then indParam:SetTalentDefense(Config.CapturedTalent) end
                end)
            end

            -- 3. Normalize HP
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

            -- 4. Player name & announcements
            local capturerName = "Unknown Pioneer"
            if playerActor and playerActor:IsValid() and playerActor.PlayerState then
                pcall(function()
                    local name = playerActor.PlayerState:GetPlayerName()
                    if name and name ~= "" then capturerName = tostring(name) end
                end)
            end

            SendCaptureToast(bossInfo.PalName, true, "World Boss")
            NotifyDaemonCapture(bossInfo.PalName, capturerName)
            ActiveBosses[ptrKey] = nil
        end)
        return
    end

    -- B. Check if it's a Wild Aura Pal
    local wildInfo = ActiveWildAuras[ptrKey]
    if wildInfo then
        pcall(function()
            Log(string.format("=== WILD AURA PAL CAPTURED: %s (%s Aura) ===", wildInfo.PalName, wildInfo.AuraConfig.Name))

            -- Permanently re-apply all aura buffs on captured instance
            ApplyWildAuraBuffs(pal, wildInfo.AuraConfig)

            SendCaptureToast(wildInfo.PalName, false, wildInfo.AuraConfig.Name)
        end)
        return
    end
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
-- 10. PERIODIC TIMERS & DESPAWN CLEANUP
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

        for ptrKey, info in pairs(ActiveBosses) do
            if now - info.SpawnTime >= despawnAge then
                Log(string.format("World Boss '%s' timed out after %ds. Cleaning up actor.", info.PalName, despawnAge))
                pcall(function()
                    local pal = info.ActorRef
                    if pal and pal:IsValid() and pal.K2_DestroyActor then
                        pal:K2_DestroyActor()
                    end
                end)
                ActiveBosses[ptrKey] = nil
            end
        end
    end)
    return false
end)

Log("WorldBossAuraSystem v3.0 fully initialized with Regressor & Transmigrator engines.")
