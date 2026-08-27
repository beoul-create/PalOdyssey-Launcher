---@diagnostic disable: undefined-global
-- ============================================================================
-- WorldBossAuraSystem: Periodic Raid Boss Spawner with Aura VFX & Discord
-- Spawns 3x scale, 100x HP, 2x stat bosses at random map coordinates.
-- Downsizes to 2x scale with permanent 2x talents on capture.
-- 100% Original Custom Script for PalOdyssey
-- ============================================================================

local ok, Config = pcall(require, "config")
if not ok or type(Config) ~= "table" then
    Config = {
        enabled = true,
        log = true,

        -- Spawn Timing
        SpawnIntervalSeconds = 1800,    -- 30 minutes between spawns

        -- Boss Roster (base Pal character IDs)
        BossPals = {
            "Foxparks",
            "Orserk",
            "Mammorest",
            "Chillet",
            "Anubis"
        },

        -- Randomized Spawn Coordinates
        SpawnPoints = {
            { Name = "Grassy Behemoth Hills",   X = 172000.0,  Y = -420000.0, Z = 3500.0  },
            { Name = "Desolate Dunes",          X = -120000.0, Y = -180000.0, Z = 4200.0  },
            { Name = "Astral Mountains",        X = -320000.0, Y = 250000.0,  Z = 12000.0 },
            { Name = "Windswept Plateau",       X = 45000.0,   Y = -310000.0, Z = 5800.0  },
            { Name = "Frozen Ravine",           X = -250000.0, Y = 100000.0,  Z = 8500.0  }
        },

        -- Aura Types & Stencil Values (Custom Depth Stencil for visual outlines)
        Auras = {
            { Name = "Fiery",     StencilValue = 252 },
            { Name = "Corrupted", StencilValue = 253 },
            { Name = "Celestial", StencilValue = 254 }
        },

        -- Boss Stat Multipliers
        BossScale      = 3.0,    -- Actor scale for spawned boss
        CapturedScale  = 2.0,    -- Actor scale after capture
        HpMultiplier   = 100,    -- HP multiplier (100x base)
        AtkMultiplier  = 2,      -- Attack multiplier
        DefMultiplier  = 2,      -- Defense multiplier
        CapturedTalent = 200,    -- Talent IV value for captured boss (200 = 2x permanent)

        -- Integration
        DaemonPort   = 8215,     -- RemoteServerDaemon port for Discord announcements
        NotifyToast  = true      -- In-game DarnToasts notifications
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
print("  WorldBossAuraSystem: Periodic Raid Boss Engine Active")
print("==========================================================")

-- ============================================================================
-- State
-- ============================================================================

local ActiveBosses = {}  -- [ptrKey] = { PalName, Aura, SpawnTime }

-- ============================================================================
-- 1. DARNTOAST IN-GAME NOTIFICATION
-- ============================================================================

local function SendBossToast(palName, auraName, locationName)
    if not Config.NotifyToast then return end
    pcall(function()
        local SDIR = (debug.getinfo(1, "S").source:gsub("^@", ""):gsub("[^/\\]+$", ""))
        package.path = SDIR .. "../../DarnToasts/Scripts/?.lua;" .. package.path
        local Toast = require("ToastLib").new("WorldBossAura")
        if Toast and Toast.notify then
            local r, g, b = 1.0, 0.2, 0.0
            if auraName == "Corrupted" then r, g, b = 0.6, 0.0, 1.0 end
            if auraName == "Celestial" then r, g, b = 1.0, 0.84, 0.0 end
            Toast.notify(
                string.format("⚠️ RAID BOSS: %s (%s) at %s!", palName, auraName, locationName),
                r, g, b
            )
        end
    end)
end

local function SendCaptureToast(palName)
    if not Config.NotifyToast then return end
    pcall(function()
        local SDIR = (debug.getinfo(1, "S").source:gsub("^@", ""):gsub("[^/\\]+$", ""))
        package.path = SDIR .. "../../DarnToasts/Scripts/?.lua;" .. package.path
        local Toast = require("ToastLib").new("WorldBossAura")
        if Toast and Toast.notify then
            Toast.notify(
                string.format("🏆 BOSS CAPTURED: %s has been tamed!", palName),
                0.0, 1.0, 0.5
            )
        end
    end)
end

-- ============================================================================
-- 2. DISCORD ANNOUNCEMENT VIA REMOTE DAEMON HTTP API
-- ============================================================================

local function NotifyDaemonSpawn(palName, locationName, auraName, x, y)
    pcall(function()
        local payload = string.format(
            '{"event":"spawn","palName":"%s","location":"%s","aura":"%s","x":%.0f,"y":%.0f}',
            palName, locationName, auraName, x, y
        )
        local url = string.format("http://127.0.0.1:%d/api/world-boss", Config.DaemonPort)

        -- Use UE4SS HTTP or console bridge
        -- Primary: Try engine HTTP module if available
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
            -- Fallback: Fire-and-forget via console cURL command
            local cmd = string.format(
                'curl -s -X POST -H "Content-Type: application/json" -d "%s" %s',
                payload:gsub('"', '\\"'), url
            )
            pcall(function()
                ExecuteConsoleCommand(nil, cmd, nil)
            end)
            -- Additional fallback: os.execute
            pcall(function()
                os.execute('start /B ' .. cmd .. ' >nul 2>&1')
            end)
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
-- 3. AURA & VISUAL ENHANCEMENT SYSTEM (Custom Depth Stencil)
-- ============================================================================

local function AttachBossAura(pal, auraConfig)
    if not pal or not pal:IsValid() then return end

    pcall(function()
        -- Apply Custom Depth Stencil rendering for glowing outline effect
        local meshComp = pal.Mesh
        if meshComp and meshComp:IsValid() then
            meshComp.bRenderCustomDepth = true
            meshComp.CustomDepthStencilValue = auraConfig.StencilValue or 252
            Log(string.format("Applied %s aura (Stencil=%d) to boss mesh.", auraConfig.Name, auraConfig.StencilValue))
        end
    end)
end

-- ============================================================================
-- 4. BOSS STAT SCALING (100x HP, 2x Attack/Defense)
-- ============================================================================

local function ScaleBossStats(pal)
    if not pal or not pal:IsValid() then return end

    pcall(function()
        local paramComp = pal.CharacterParameterComponent
        if paramComp and paramComp:IsValid() then
            -- Scale HP
            if paramComp.GetMaxHP and paramComp.SetMaxHP and paramComp.SetHP then
                local baseMaxHP = paramComp:GetMaxHP()
                if baseMaxHP and baseMaxHP > 0 then
                    local bossHP = baseMaxHP * Config.HpMultiplier
                    paramComp:SetMaxHP(bossHP)
                    paramComp:SetHP(bossHP)
                    Log(string.format("  HP: %d -> %d (x%d)", baseMaxHP, bossHP, Config.HpMultiplier))
                end
            end

            -- Scale Attack
            if paramComp.GetAttack and paramComp.SetAttack then
                local baseAtk = paramComp:GetAttack()
                if baseAtk and baseAtk > 0 then
                    local bossAtk = baseAtk * Config.AtkMultiplier
                    paramComp:SetAttack(bossAtk)
                    Log(string.format("  ATK: %d -> %d (x%d)", baseAtk, bossAtk, Config.AtkMultiplier))
                end
            end

            -- Scale Defense
            if paramComp.GetDefense and paramComp.SetDefense then
                local baseDef = paramComp:GetDefense()
                if baseDef and baseDef > 0 then
                    local bossDef = baseDef * Config.DefMultiplier
                    paramComp:SetDefense(bossDef)
                    Log(string.format("  DEF: %d -> %d (x%d)", baseDef, bossDef, Config.DefMultiplier))
                end
            end
        end
    end)
end

-- ============================================================================
-- 5. PERIODIC WORLD BOSS SPAWNER
-- ============================================================================

local function SpawnWorldBoss()
    pcall(function()
        -- Select random spawn point
        local spawnIndex = math.random(#Config.SpawnPoints)
        local targetLocation = Config.SpawnPoints[spawnIndex]

        -- Select random boss Pal
        local selectedPal = Config.BossPals[math.random(#Config.BossPals)]

        -- Select random aura
        local selectedAura = Config.Auras[math.random(#Config.Auras)]

        Log(string.format("=== SPAWNING WORLD BOSS: %s (%s Aura) at %s ===",
            selectedPal, selectedAura.Name, targetLocation.Name))

        -- Attempt to spawn Pal character using UE4SS spawning APIs
        local spawnedPal = nil

        -- Method 1: SpawnPalCharacter (if available via game API)
        pcall(function()
            if SpawnPalCharacter then
                local spawnTransform = {
                    Translation = {
                        X = targetLocation.X,
                        Y = targetLocation.Y,
                        Z = targetLocation.Z
                    },
                    Rotation = { Pitch = 0, Yaw = math.random(0, 360), Roll = 0, W = 1 },
                    Scale3D = { X = Config.BossScale, Y = Config.BossScale, Z = Config.BossScale }
                }
                spawnedPal = SpawnPalCharacter(selectedPal, spawnTransform)
            end
        end)

        -- Method 2: FindFirstOf + World context spawning
        if not spawnedPal or (spawnedPal and not spawnedPal:IsValid()) then
            pcall(function()
                local gameMode = FindFirstOf("PalGameMode")
                if gameMode and gameMode:IsValid() then
                    local spawner = gameMode.PalSpawner
                    if spawner and spawner:IsValid() and spawner.SpawnPalByName then
                        spawnedPal = spawner:SpawnPalByName(
                            selectedPal,
                            targetLocation.X, targetLocation.Y, targetLocation.Z,
                            0, -- Level (0 = use default scaling)
                            false -- Not owned by player
                        )
                    end
                end
            end)
        end

        -- Method 3: Console command spawning as fallback
        if not spawnedPal or (type(spawnedPal) == "userdata" and not spawnedPal:IsValid()) then
            pcall(function()
                local spawnCmd = string.format(
                    "SpawnPal %s %f %f %f",
                    selectedPal, targetLocation.X, targetLocation.Y, targetLocation.Z
                )
                local KismetSystemLibrary = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
                local pc = GetPlayerController()
                if KismetSystemLibrary and KismetSystemLibrary:IsValid() and pc and pc:IsValid() then
                    KismetSystemLibrary:ExecuteConsoleCommand(pc, spawnCmd, nil)
                    Log("Spawned boss via console command fallback.")
                end
            end)
        end

        -- Post-spawn enhancement: Hook into newly spawned PalCharacter
        -- Use NotifyOnNewObject with a short-lived capture window
        local captureWindow = true
        local captureTimer = 0

        -- Register a temporary listener for the next PalCharacter spawns
        -- to identify and enhance our boss
        local function TryEnhanceBoss(pal)
            if not captureWindow then return end
            if not pal or not pal:IsValid() then return end

            pcall(function()
                local palName = ""
                local charParam = pal.CharacterParameterComponent
                if charParam and charParam:IsValid() and charParam.GetCharacterID then
                    palName = tostring(charParam:GetCharacterID() or "")
                end

                -- Check if this matches our selected boss (by proximity to spawn point)
                local palLoc = pal:K2_GetActorLocation()
                if palLoc then
                    local dx = palLoc.X - targetLocation.X
                    local dy = palLoc.Y - targetLocation.Y
                    local dz = palLoc.Z - targetLocation.Z
                    local dist = math.sqrt(dx*dx + dy*dy + dz*dz)

                    -- If spawned within 500 units of target, this is our boss
                    if dist < 500.0 then
                        captureWindow = false -- Only enhance one

                        -- Set actor scale
                        if pal.SetActorScale3D then
                            pal:SetActorScale3D({
                                X = Config.BossScale,
                                Y = Config.BossScale,
                                Z = Config.BossScale
                            })
                        end

                        -- Apply stat scaling
                        ScaleBossStats(pal)

                        -- Apply aura VFX
                        AttachBossAura(pal, selectedAura)

                        -- Track as active boss
                        local ptrKey = tostring(pal:GetAddress())
                        ActiveBosses[ptrKey] = {
                            PalName  = selectedPal,
                            Aura     = selectedAura,
                            Location = targetLocation,
                            SpawnTime = os.time()
                        }

                        Log(string.format("Boss enhanced: %s (Aura: %s, Scale: %.1fx, HP: x%d)",
                            selectedPal, selectedAura.Name, Config.BossScale, Config.HpMultiplier))

                        -- Send in-game toast
                        SendBossToast(selectedPal, selectedAura.Name, targetLocation.Name)

                        -- Notify C# daemon for Discord announcement
                        NotifyDaemonSpawn(selectedPal, targetLocation.Name, selectedAura.Name,
                            targetLocation.X, targetLocation.Y)
                    end
                end
            end)
        end

        -- If we got a direct reference, enhance immediately
        if spawnedPal and type(spawnedPal) == "userdata" and spawnedPal:IsValid() then
            captureWindow = false

            if spawnedPal.SetActorScale3D then
                spawnedPal:SetActorScale3D({
                    X = Config.BossScale,
                    Y = Config.BossScale,
                    Z = Config.BossScale
                })
            end

            ScaleBossStats(spawnedPal)
            AttachBossAura(spawnedPal, selectedAura)

            local ptrKey = tostring(spawnedPal:GetAddress())
            ActiveBosses[ptrKey] = {
                PalName  = selectedPal,
                Aura     = selectedAura,
                Location = targetLocation,
                SpawnTime = os.time()
            }

            Log(string.format("Boss enhanced (direct ref): %s (Aura: %s)", selectedPal, selectedAura.Name))
            SendBossToast(selectedPal, selectedAura.Name, targetLocation.Name)
            NotifyDaemonSpawn(selectedPal, targetLocation.Name, selectedAura.Name,
                targetLocation.X, targetLocation.Y)
        else
            -- Fallback: Listen for new PalCharacter objects in the next 5 seconds
            ExecuteWithDelay(500, function()
                pcall(function()
                    local allPals = FindAllOf("PalCharacter")
                    if allPals then
                        for _, pal in ipairs(allPals) do
                            TryEnhanceBoss(pal)
                            if not captureWindow then break end
                        end
                    end
                end)
            end)
        end
    end)
end

-- ============================================================================
-- 6. CAPTURE HOOK (Downsize to 2x Scale, Permanent 2x Talent IVs)
-- ============================================================================

local function OnBossCaptured(pal, playerActor)
    if not pal or not pal:IsValid() then return end

    local ptrKey = tostring(pal:GetAddress())
    local bossInfo = ActiveBosses[ptrKey]
    if not bossInfo then return end -- Not a tracked boss

    pcall(function()
        Log(string.format("=== BOSS CAPTURED: %s (%s Aura) ===", bossInfo.PalName, bossInfo.Aura.Name))

        -- 1. Downsize to captured scale (2x)
        if pal.SetActorScale3D then
            pal:SetActorScale3D({
                X = Config.CapturedScale,
                Y = Config.CapturedScale,
                Z = Config.CapturedScale
            })
            Log(string.format("  Scale: %.1fx -> %.1fx", Config.BossScale, Config.CapturedScale))
        end

        -- 2. Normalize HP and apply permanent 2x talent IVs
        local individualParam = nil
        pcall(function()
            if pal.GetIndividualParameter then
                individualParam = pal:GetIndividualParameter()
            end
        end)

        if individualParam and individualParam:IsValid() then
            pcall(function()
                if individualParam.SetTalentHP then
                    individualParam:SetTalentHP(Config.CapturedTalent)
                end
                if individualParam.SetTalentShotAttack then
                    individualParam:SetTalentShotAttack(Config.CapturedTalent)
                end
                if individualParam.SetTalentDefense then
                    individualParam:SetTalentDefense(Config.CapturedTalent)
                end
                Log(string.format("  Talents set to: HP=%d, ATK=%d, DEF=%d",
                    Config.CapturedTalent, Config.CapturedTalent, Config.CapturedTalent))
            end)
        end

        -- 3. Reset HP to proper 2x base (not 100x)
        pcall(function()
            local paramComp = pal.CharacterParameterComponent
            if paramComp and paramComp:IsValid() then
                if paramComp.GetMaxHP and paramComp.SetMaxHP and paramComp.SetHP then
                    local currentMax = paramComp:GetMaxHP()
                    if currentMax and currentMax > 0 then
                        -- Divide by HP multiplier, multiply by ATK multiplier to get 2x base
                        local normalizedHP = math.floor(currentMax / Config.HpMultiplier * Config.AtkMultiplier)
                        paramComp:SetMaxHP(normalizedHP)
                        paramComp:SetHP(normalizedHP)
                        Log(string.format("  HP normalized: %d -> %d", currentMax, normalizedHP))
                    end
                end
            end
        end)

        -- 4. Determine capturer name
        local capturerName = "Unknown Pioneer"
        pcall(function()
            if playerActor and playerActor:IsValid() then
                local playerState = playerActor.PlayerState
                if playerState and playerState:IsValid() and playerState.GetPlayerName then
                    local name = playerState:GetPlayerName()
                    if name and name ~= "" then
                        capturerName = tostring(name)
                    end
                end
            end
        end)

        -- 5. Announce
        SendCaptureToast(bossInfo.PalName)
        NotifyDaemonCapture(bossInfo.PalName, capturerName)

        -- 6. Remove from active tracking
        ActiveBosses[ptrKey] = nil
        Log(string.format("Boss '%s' removed from active tracking. Captured by: %s", bossInfo.PalName, capturerName))
    end)
end

-- Register capture hook (with pcall guard for version compatibility)
pcall(function()
    RegisterHook("/Script/Pal.PalCaptureSubsystem:OnCaptureSuccess", function(Context, TargetPal, PlayerActor)
        ExecuteInGameThread(function()
            local pal = nil
            local player = nil
            pcall(function() pal = TargetPal:get() end)
            pcall(function() player = PlayerActor:get() end)
            OnBossCaptured(pal, player)
        end)
    end)
    Log("Capture hook registered: /Script/Pal.PalCaptureSubsystem:OnCaptureSuccess")
end)

-- Fallback capture hook via alternative path
pcall(function()
    RegisterHook("/Script/Pal.PalCharacter:OnCaptured", function(Context, CapturedBy)
        ExecuteInGameThread(function()
            local pal = nil
            local player = nil
            pcall(function() pal = Context:get() end)
            pcall(function() player = CapturedBy:get() end)
            OnBossCaptured(pal, player)
        end)
    end)
    Log("Fallback capture hook registered: /Script/Pal.PalCharacter:OnCaptured")
end)

-- ============================================================================
-- 7. PERIODIC TIMER (LoopAsync pattern matching existing mods)
-- ============================================================================

local spawnIntervalMs = (Config.SpawnIntervalSeconds or 1800) * 1000

LoopAsync(spawnIntervalMs, function()
    pcall(function()
        Log(string.format("Periodic boss timer fired (interval: %ds). Spawning world boss...",
            Config.SpawnIntervalSeconds))
        SpawnWorldBoss()
    end)
    return false -- Keep repeating
end)

-- ============================================================================
-- 8. ACTIVE BOSS CLEANUP (Despawn after 30 minutes if uncaptured)
-- ============================================================================

LoopAsync(60000, function()
    pcall(function()
        local now = os.time()
        local despawnAge = Config.SpawnIntervalSeconds or 1800 -- Despawn when next boss would spawn

        for ptrKey, info in pairs(ActiveBosses) do
            if now - info.SpawnTime >= despawnAge then
                Log(string.format("Boss '%s' despawned (timed out after %ds).", info.PalName, despawnAge))
                ActiveBosses[ptrKey] = nil
            end
        end
    end)
    return false
end)

Log(string.format("WorldBossAuraSystem initialized. Boss spawns every %d seconds (%d minutes).",
    Config.SpawnIntervalSeconds, Config.SpawnIntervalSeconds / 60))
