---@diagnostic disable: undefined-global
-- ============================================================================
-- WorldBossAuraSystem: World Boss & Wild Aura Engine for PalOdyssey
-- 1. Periodic World Bosses: 1-hour interval, strictly "World Boss" Neon Red aura,
--    3x scale, 100x HP, 2x ATK/DEF, 10m despawn, on-capture 2x scale + 2x stats.
-- 2. Wild Auras (Corrupted & Celestial): 0.01% chance on normal wild Pal spawns,
--    2x Move Speed + 2x Work Speed (retained on capture).
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
        -- 2. WILD AURA CONFIGURATION (Corrupted & Celestial)
        -- ====================================================================
        WildAuraChance = 0.0001, -- 0.01% (1 in 10,000) chance on normal wild Pal spawns

        WildAuras = {
            { Name = "Corrupted", StencilValue = 253, GlowColor = "NeonPurple", SpeedMult = 2.0, WorkMult = 2.0 },
            { Name = "Celestial", StencilValue = 254, GlowColor = "NeonGold",   SpeedMult = 2.0, WorkMult = 2.0 }
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
print("  WorldBossAuraSystem: Raid & Wild Aura Engine Active")
print("==========================================================")

-- ============================================================================
-- State Tracking
-- ============================================================================

local ActiveBosses    = {}  -- [ptrKey] = { PalName, Aura, SpawnTime, ActorRef }
local ActiveWildAuras = {}  -- [ptrKey] = { PalName, Aura, SpeedMult, WorkMult, ActorRef }

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
                1.0, 0.05, 0.1 -- Glowing Neon Red outline
            )
        end
    end)
end

local function SendWildAuraToast(palName, auraName)
    if not Config.NotifyToast then return end
    pcall(function()
        local SDIR = (debug.getinfo(1, "S").source:gsub("^@", ""):gsub("[^/\\]+$", ""))
        package.path = SDIR .. "../../DarnToasts/Scripts/?.lua;" .. package.path
        local Toast = require("ToastLib").new("WorldBossAura")
        if Toast and Toast.notify then
            local r, g, b = 0.6, 0.0, 1.0 -- Neon Purple for Corrupted
            if auraName == "Celestial" then r, g, b = 1.0, 0.84, 0.0 end -- Radiant Gold for Celestial
            Toast.notify(
                string.format("✨ RARE WILD PAL: %s with %s Aura (2x Move & Work Speed)!", palName or "Pal", auraName),
                r, g, b
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
                Toast.notify(string.format("✨ %s PAL TAMED: %s retains permanent 2x Move & Work Speed!", auraName or "Aura", palName), 0.0, 0.8, 1.0)
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
-- 4. SPEED & WORK STAT BUFFS (2x Move Speed, 2x Work Speed)
-- ============================================================================

local function ApplySpeedAndWorkBuffs(pal, speedMult, workMult)
    if not pal or not pal:IsValid() then return end
    pcall(function()
        -- 1. Scale Movement Speeds
        local moveComp = pal.CharacterMovement
        if moveComp and moveComp:IsValid() then
            if moveComp.MaxWalkSpeed then
                moveComp.MaxWalkSpeed = moveComp.MaxWalkSpeed * speedMult
            end
            if moveComp.MaxCustomMovementSpeed then
                moveComp.MaxCustomMovementSpeed = moveComp.MaxCustomMovementSpeed * speedMult
            end
        end

        -- 2. Scale Work / Crafting Speeds
        local paramComp = pal.CharacterParameterComponent
        if paramComp and paramComp:IsValid() then
            if paramComp.SetCraftSpeed then
                local curCraft = paramComp:GetCraftSpeed() or 100
                paramComp:SetCraftSpeed(math.floor(curCraft * workMult))
            end
            if paramComp.SetWorkSpeed then
                local curWork = paramComp:GetWorkSpeed() or 100
                paramComp:SetWorkSpeed(math.floor(curWork * workMult))
            end
        end
    end)
end

-- ============================================================================
-- 5. WILD AURA PAL ENHANCEMENT (0.01% Spawn Chance: Corrupted / Celestial)
-- ============================================================================

local function EnhanceWildPal(pal, auraConfig)
    if not pal or not pal:IsValid() then return end
    local ptrKey = tostring(pal:GetAddress())
    if ActiveWildAuras[ptrKey] or ActiveBosses[ptrKey] then return end

    pcall(function()
        local palName = "Wild Pal"
        local charParam = pal.CharacterParameterComponent
        if charParam and charParam:IsValid() and charParam.GetCharacterID then
            local id = charParam:GetCharacterID()
            if id and id ~= "" then palName = tostring(id) end
        end

        -- Apply Stencil VFX (Neon Purple 253 or Radiant Gold 254)
        AttachAuraStencil(pal, auraConfig.StencilValue)

        -- Apply 2x Move Speed and 2x Work Speed
        ApplySpeedAndWorkBuffs(pal, auraConfig.SpeedMult or 2.0, auraConfig.WorkMult or 2.0)

        -- Track as active wild aura Pal
        ActiveWildAuras[ptrKey] = {
            PalName   = palName,
            Aura      = auraConfig,
            SpeedMult = auraConfig.SpeedMult or 2.0,
            WorkMult  = auraConfig.WorkMult or 2.0,
            ActorRef  = pal
        }

        Log(string.format("✨ [WILD AURA] Generated %s (%s Aura) -> 2x Move Speed, 2x Work Speed (Ptr: %s)",
            palName, auraConfig.Name, ptrKey))

        SendWildAuraToast(palName, auraConfig.Name)
    end)
end

-- ============================================================================
-- 6. PERIODIC WORLD BOSS SPAWNER (Strictly "World Boss" Neon Red Aura)
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
        local bossAura = Config.BossAura -- Strictly "World Boss" Neon Red

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
-- 7. DYNAMIC WILD PAL SPAWN LISTENER (0.01% Corrupted / Celestial Aura Roll)
-- ============================================================================

pcall(function()
    NotifyOnNewObject("/Script/Pal.PalCharacter", function(pal)
        ExecuteWithDelay(350, function()
            if not pal or not pal:IsValid() then return end
            local ptrKey = tostring(pal:GetAddress())
            if ActiveBosses[ptrKey] or ActiveWildAuras[ptrKey] then return end

            -- Roll 0.01% chance (1 in 10,000)
            if math.random() <= (Config.WildAuraChance or 0.0001) then
                local selectedWildAura = Config.WildAuras[math.random(#Config.WildAuras)]
                EnhanceWildPal(pal, selectedWildAura)
            end
        end)
    end)
    Log("Wild Aura spawn listener initialized (0.01% chance for Corrupted/Celestial).")
end)

-- ============================================================================
-- 8. CAPTURE HOOK (Boss Downsizing & Wild Aura Permanent Retention)
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

    -- B. Check if it's a Wild Aura Pal (Corrupted / Celestial)
    local wildInfo = ActiveWildAuras[ptrKey]
    if wildInfo then
        pcall(function()
            Log(string.format("=== WILD AURA PAL CAPTURED: %s (%s Aura) ===", wildInfo.PalName, wildInfo.Aura.Name))

            -- Re-affirm 2x Move Speed and 2x Work Speed on captured instance
            ApplySpeedAndWorkBuffs(pal, wildInfo.SpeedMult or 2.0, wildInfo.WorkMult or 2.0)
            AttachAuraStencil(pal, wildInfo.Aura.StencilValue)

            SendCaptureToast(wildInfo.PalName, false, wildInfo.Aura.Name)
            -- Keep in ActiveWildAuras to track persistent buffs across sessions
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
-- 9. PERIODIC TIMERS & DESPAWN CLEANUP
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

Log("WorldBossAuraSystem v2.0 fully initialized.")
