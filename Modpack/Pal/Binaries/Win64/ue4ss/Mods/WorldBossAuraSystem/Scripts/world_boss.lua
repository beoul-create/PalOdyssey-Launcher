local ScriptDir = debug.getinfo(1, "S").source:gsub("^@", ""):gsub("[^/\\]+$", "")
package.path = ScriptDir .. "?.lua;" .. ScriptDir .. "../?.lua;" .. package.path

local WorldBoss = {}
local AuraSystem = require("aura_system")
local LiveboardExport = require("liveboard_export")

local ActiveBosses = {}
local Config = {}
local SpawnInProgress = false
local LastCommandSpawn = 0
local PalDisplayNames = {
    Kitsunebi = "Foxparks",
    ThunderDragonMan = "Orserk",
    GrassMammoth = "Mammorest",
    WeaselDragon = "Chillet",
    Anubis = "Anubis"
}

function WorldBoss.LoadConfig(Cfg)
    Config = Cfg or {}
end

function WorldBoss.GetActiveBosses()
    return ActiveBosses
end

function WorldBoss.HasOnlinePlayer()
    local found = false
    pcall(function()
        -- 1. Check Player Controllers
        for _, pc in ipairs(FindAllOf("PalPlayerController") or {}) do
            if pc and pc:IsValid() then
                found = true
                return
            end
        end
        -- 2. Check Player Characters
        for _, ch in ipairs(FindAllOf("PalPlayerCharacter") or {}) do
            if ch and ch:IsValid() then
                found = true
                return
            end
        end
        -- 3. Check Player States
        for _, ps in ipairs(FindAllOf("PalPlayerState") or {}) do
            if ps and ps:IsValid() then
                found = true
                return
            end
        end
    end)
    return found
end

local function BroadcastInGame(Text, PalDisplayName, SelectedAura, LocationName, Pos)
    -- 1. Native Chat / System Broadcast
    pcall(function()
        local controllers = FindAllOf("PalPlayerController") or {}
        local PalUtil = StaticFindObject("/Script/Pal.Default__PalUtility")
        local world = (UEHelpers and UEHelpers.GetWorldContextObject and UEHelpers.GetWorldContextObject())
            or (GetWorldContext and GetWorldContext()) or nil
        
        for _, pc in ipairs(controllers) do
            if pc and pc:IsValid() then
                local ps = pc.PlayerState
                if PalUtil and PalUtil:IsValid() and world and ps and ps:IsValid() then
                    PalUtil:SendSystemToPlayerChat(world, Text, ps.PlayerUId)
                    if type(PalUtil.SendSystemAnnounce) == "function" then
                        PalUtil:SendSystemAnnounce(world, Text, 10.0)
                    end
                end
            end
        end
    end)

    -- 2. On-Screen Visual HUD Banner via DarnToasts
    pcall(function()
        local ToastLib = nil
        pcall(function() ToastLib = require("ToastLib") end)
        if not ToastLib then
            pcall(function() ToastLib = require("DarnToasts.Scripts.ToastLib") end)
        end
        if ToastLib and type(ToastLib.show) == "function" then
            ToastLib.show("WorldBoss", {
                text = string.format("⚠️ WORLD BOSS SPAWNED: %s (%s Aura)!", tostring(PalDisplayName), tostring(SelectedAura)),
                sub = string.format("Location: %s (Coords: %.0f, %.0f)", tostring(LocationName), Pos.X, Pos.Y),
                duration = 12.0,
                style = "panel"
            })
        end
    end)

    print("[WorldBossAuraSystem] Broadcast: " .. tostring(Text))
end

function WorldBoss.BroadcastDiscordEvent(title, description, color)
    if not Config.DiscordWebhookURL or Config.DiscordWebhookURL == "YOUR_DISCORD_WEBHOOK_URL_HERE" or Config.DiscordWebhookURL == "" then return end
    pcall(function()
        local payload = string.format(
            '{"embeds":[{"title":"%s","description":"%s","color":%d,"footer":{"text":"PalOdyssey World Boss Alert System"}}]}',
            tostring(title), tostring(description), tonumber(color) or 3447003
        )
        local tempPath = os.getenv("TEMP") or os.getenv("TMP") or "."
        local filePath = tempPath .. "\\pal_wb_discord.json"
        local f = io.open(filePath, "w")
        if f then
            f:write(payload)
            f:close()
            local cmd = string.format('start /B curl.exe -s -H "Content-Type: application/json" -X POST --data-binary @"%s" "%s"', filePath, Config.DiscordWebhookURL)
            if os.execute then
                os.execute(cmd)
            end
        end
    end)
end

function WorldBoss.BroadcastDiscord(PalName, AuraType, LocationName, Pos)
    if not Config.DiscordWebhookURL or Config.DiscordWebhookURL == "YOUR_DISCORD_WEBHOOK_URL_HERE" or Config.DiscordWebhookURL == "" then return end
    pcall(function()
        local meta = AuraSystem.GetMetadata and AuraSystem.GetMetadata(AuraType)
        local color = (meta and meta.Color) or 16724736
        local perkDesc = (meta and meta.Desc) or ""

        local payload = string.format(
            '{"embeds":[{"title":"⚠️ WORLD BOSS SPAWNED!","description":"**%s (%s Aura)** has appeared!\\n*%s*\\n\\n**Location:** %s\\n**Coords:** X: %.0f, Y: %.0f","color":%d,"footer":{"text":"PalOdyssey World Boss Alert System"}}]}',
            tostring(PalName), tostring(AuraType), perkDesc, tostring(LocationName), Pos.X, Pos.Y, color
        )
        
        local tempPath = os.getenv("TEMP") or os.getenv("TMP") or "."
        local filePath = tempPath .. "\\pal_wb_discord.json"
        local f = io.open(filePath, "w")
        if f then
            f:write(payload)
            f:close()
            local cmd = string.format('start /B curl.exe -s -H "Content-Type: application/json" -X POST --data-binary @"%s" "%s"', filePath, Config.DiscordWebhookURL)
            if os.execute then
                os.execute(cmd)
            end
        end
    end)
end

function WorldBoss.SpawnEvent()
    if SpawnInProgress then
        print("[WorldBossAuraSystem] Spawn already in progress; request ignored.")
        return false
    end
    local activeCount = 0
    for _ in pairs(ActiveBosses) do activeCount = activeCount + 1 end
    if activeCount >= math.max(1, tonumber(Config.MaxActiveBosses) or 1) then
        print("[WorldBossAuraSystem] Active boss limit reached; spawn skipped.")
        return false
    end
    if not Config.SpawnPoints or #Config.SpawnPoints == 0 or not Config.BossPalPool or #Config.BossPalPool == 0 then
        print("[WorldBossAuraSystem] Cannot spawn boss: SpawnPoints or BossPalPool is empty.")
        return false
    end
    if not WorldBoss.HasOnlinePlayer() then
        print("[WorldBossAuraSystem] Boss spawn deferred until a player is online.")
        return false
    end
    SpawnInProgress = true

    local Point = Config.SpawnPoints[math.random(#Config.SpawnPoints)]
    local PalId = Config.BossPalPool[math.random(#Config.BossPalPool)]
    local PalDisplayName = PalDisplayNames[PalId] or PalId
    local Auras = (AuraSystem.GetAllAuras and AuraSystem.GetAllAuras()) or { "Fiery", "Glacial", "Celestial", "Corrupted", "Verdant", "Tidal", "Draconic", "Radiant" }
    local SelectedAura = Auras[math.random(#Auras)]
    local SpawnLoc = { X = Point.X, Y = Point.Y, Z = Point.Z }

    local BossActor = nil
    local actorsBefore = {}
    pcall(function()
        for _, actor in ipairs(FindAllOf("PalCharacter") or {}) do
            if actor and actor:IsValid() then actorsBefore[tostring(actor:GetAddress())] = true end
        end
    end)

    local function TrySpawn(label, callable)
        local ok, result = pcall(callable)
        if ok and result and result.IsValid and result:IsValid() then
            BossActor = result
            return true
        end
        if not ok then print(string.format("[WorldBossAuraSystem] %s failed: %s", label, tostring(result))) end
        return false
    end

        -- 1. Direct UE5 World:SpawnActor with Monster Blueprint Class (Dynamic Asset Loader)
        if not BossActor or not BossActor:IsValid() then
            pcall(function()
                local world = (UEHelpers and UEHelpers.GetWorldContextObject and UEHelpers.GetWorldContextObject())
                    or (GetWorldContext and GetWorldContext()) or (UEHelpers and UEHelpers.GetWorld and UEHelpers.GetWorld()) or nil
                if world and world:IsValid() and type(world.SpawnActor) == "function" then
                    local bpPaths = {
                        string.format("/Game/Pal/Blueprint/Character/Monster/%s/BP_%s.BP_%s_C", PalId, PalId, PalId),
                        string.format("/Game/Pal/Blueprint/Character/Monster/%s/BP_%s_C", PalId, PalId),
                        string.format("/Game/Pal/Blueprint/Character/Monster/%s/BP_%s", PalId, PalId)
                    }
                    for _, bpPath in ipairs(bpPaths) do
                        local palClass = StaticFindObject(bpPath)
                        if (not palClass or not palClass:IsValid()) and type(LoadAsset) == "function" then
                            local ok, loaded = pcall(LoadAsset, bpPath)
                            if ok and loaded then palClass = loaded end
                        end
                        if (not palClass or not palClass:IsValid()) and type(StaticLoadObject) == "function" then
                            local ok, loaded = pcall(StaticLoadObject, bpPath)
                            if ok and loaded then palClass = loaded end
                        end
                        if palClass and palClass:IsValid() then
                            TrySpawn("World:SpawnActor " .. bpPath, function()
                                return world:SpawnActor(palClass, SpawnLoc, { Pitch=0, Yaw=0, Roll=0 })
                            end)
                            if BossActor and BossActor:IsValid() then break end
                        end
                    end
                end
            end)
        end

        -- 1.5. Native CheatManager SpawnMonster
        if not BossActor or not BossActor:IsValid() then
            pcall(function()
                for _, pc in ipairs(FindAllOf("PalPlayerController") or {}) do
                    if pc and pc:IsValid() and pc.CheatManager and pc.CheatManager:IsValid() then
                        if type(pc.CheatManager.SpawnMonster) == "function" then
                            TrySpawn("CheatManager.SpawnMonster", function()
                                return pc.CheatManager:SpawnMonster(FName(PalId), tonumber(Config.BossLevel) or 100)
                            end)
                            if BossActor and BossActor:IsValid() then break end
                        end
                    end
                end
            end)
        end

        -- 2. Native PalUtility / SpawnerSubsystem / NPCManager
        if not BossActor or not BossActor:IsValid() then
            pcall(function()
                local PalUtil = StaticFindObject("/Script/Pal.Default__PalUtility")
                local world = (UEHelpers and UEHelpers.GetWorldContextObject and UEHelpers.GetWorldContextObject()) or (GetWorldContext and GetWorldContext()) or nil
                if PalUtil and PalUtil:IsValid() then
                    if type(PalUtil.SpawnPal_Server) == "function" then
                        TrySpawn("PalUtility.SpawnPal_Server", function()
                            return PalUtil:SpawnPal_Server(world, FName(PalId), SpawnLoc, { Pitch=0, Yaw=0, Roll=0 }, nil, 100, 100, true)
                        end)
                    end
                    if not BossActor and type(PalUtil.SpawnIndividualPal) == "function" then
                        TrySpawn("PalUtility.SpawnIndividualPal", function()
                            return PalUtil:SpawnIndividualPal(world, FName(PalId), SpawnLoc, { Pitch=0, Yaw=0, Roll=0 })
                        end)
                    end
                end
            end)
        end

        -- 3. Wild Pal Promotion Fallback (Promote existing wild Pal into World Boss)
        if not BossActor or not BossActor:IsValid() then
            pcall(function()
                for _, actor in ipairs(FindAllOf("PalCharacter") or {}) do
                    if actor and actor:IsValid() and not actor.IsPlayer and not actor.IsPlayerPal then
                        local name = tostring(actor:GetClass():GetName())
                        if name:find(PalId) or name:find("Monster") or name:find("BP_") then
                            BossActor = actor
                            local loc = actor:K2_GetActorLocation() or actor:GetActorLocation()
                            if loc then
                                SpawnLoc = { X = loc.X, Y = loc.Y, Z = loc.Z }
                                Point = { Name = "Wild Encounter Zone", X = loc.X, Y = loc.Y, Z = loc.Z }
                            end
                            print(string.format("[WorldBossAuraSystem] Promoted live wild %s to World Boss!", name))
                            break
                        end
                    end
                end
            end)
        end

    if BossActor and BossActor:IsValid() then
        -- 1. Apply 3.0x Visual Scale
        local WorldScale = tonumber(Config.BossScaleWorld) or 3.0
        pcall(function()
            BossActor:SetActorScale3D({ X = WorldScale, Y = WorldScale, Z = WorldScale })
        end)

        -- 2. Apply Combat Parameters (Special scaling for Regressor 4x and Transmigrator 2x speed)
        pcall(function()
            local Param = BossActor.CharacterParameterComponent
            if Param and Param:IsValid() then
                local hpMult = (SelectedAura == "Regressor" and 400) or 100
                local combatMult = (SelectedAura == "Regressor" and 8) or 2
                local BaseHP = Param:GetMaxHP() or 5000
                Param:SetMaxHP(BaseHP * hpMult)
                Param:SetHP(BaseHP * hpMult)
                if type(Param.SetAttack) == "function" then Param:SetAttack((Param:GetAttack() or 100) * combatMult) end
                if type(Param.SetDefense) == "function" then Param:SetDefense((Param:GetDefense() or 100) * combatMult) end
            end
            if SelectedAura == "Transmigrator" and BossActor.CharacterMovement and BossActor.CharacterMovement:IsValid() then
                local cm = BossActor.CharacterMovement
                if cm.MaxWalkSpeed then cm.MaxWalkSpeed = cm.MaxWalkSpeed * 2.0 end
                if cm.MaxFlySpeed then cm.MaxFlySpeed = cm.MaxFlySpeed * 2.0 end
            end
        end)

        -- 3. Attach Visual Aura
        pcall(AuraSystem.Attach, BossActor, SelectedAura)

        -- 4. Record Active Boss
        local uid = "Boss_" .. tostring(os.time())
        pcall(function()
            local nativeUid = BossActor:GetUniqueID()
            if nativeUid ~= nil then uid = nativeUid end
        end)
        ActiveBosses[uid] = {
            PalId = PalId,
            PalDisplayName = PalDisplayName,
            Aura = SelectedAura,
            LocationName = Point.Name,
            Coords = { X = Point.X, Y = Point.Y },
            SpawnTime = os.time(),
            BossActor = BossActor,
            Address = tostring(BossActor:get_address())
        }

        -- 5. Broadcast to in-game chat and HUD
        BroadcastInGame(string.format("⚠️ WORLD BOSS SPAWNED: [%s (%s Aura)] has appeared at %s! (Coords: %.0f, %.0f)", PalDisplayName, SelectedAura, Point.Name, Point.X, Point.Y), PalDisplayName, SelectedAura, Point.Name, SpawnLoc)

        -- 6. Discord & Liveboard
        WorldBoss.BroadcastDiscord(PalDisplayName, SelectedAura, Point.Name, SpawnLoc)
        LiveboardExport.DumpState(ActiveBosses, Config)
        print(string.format("[WorldBossAuraSystem] Successfully spawned World Boss %s (%s) at %s.", PalDisplayName, PalId, Point.Name))
        SpawnInProgress = false
        return true
    else
        print(string.format("[WorldBossAuraSystem] All spawn methods failed for %s at %s.", PalId, Point.Name))
        SpawnInProgress = false
        return false
    end
end

function WorldBoss.CheckDespawns()
    local now = os.time()
    local maxLifespan = tonumber(Config.BossLifespanSeconds) or 1800 -- 30 minutes default
    for uid, data in pairs(ActiveBosses) do
        local elapsed = now - (data.SpawnTime or now)
        local actorInvalid = false
        pcall(function()
            if not data.BossActor or not data.BossActor:IsValid() then
                actorInvalid = true
            elseif data.BossActor.IsDead and data.BossActor:IsDead() then
                actorInvalid = true
            end
        end)

        if elapsed >= maxLifespan or actorInvalid then
            local bossName = data.PalDisplayName or data.PalId or "World Boss"
            local aura = data.Aura or "Elemental"
            local msg = string.format("💨 [%s (%s Aura)] has vanished back into the wild.", bossName, aura)

            pcall(function()
                if data.BossActor and data.BossActor:IsValid() then
                    data.BossActor:K2_DestroyActor()
                end
            end)

            ActiveBosses[uid] = nil
            LiveboardExport.DumpState(ActiveBosses, Config)

            BroadcastInGame(msg, string.format("💨 %s FLED", bossName), aura, "Vanished from " .. tostring(data.LocationName), { X = 0, Y = 0 })

            WorldBoss.BroadcastDiscordEvent(
                "💨 WORLD BOSS DESPAWNED",
                string.format("⏳ **%s (%s Aura)** was not defeated in time and has fled from **%s**!", bossName, aura, tostring(data.LocationName)),
                9807270 -- Gray
            )
        end
    end
end

function WorldBoss.InitHooks()
    local function FindBossMatch(Pal)
        if not Pal or not Pal:IsValid() then return nil, nil end
        local palUid = nil
        pcall(function() palUid = Pal:GetUniqueID() end)
        local palAddr = nil
        pcall(function() palAddr = tostring(Pal:get_address()) end)

        for uid, data in pairs(ActiveBosses) do
            if (palUid and uid == palUid) or (data.BossActor and data.BossActor:IsValid() and data.BossActor == Pal) or (data.Address and data.Address == palAddr) then
                return uid, data
            end
        end
        return nil, nil
    end

    -- Hook Capture Event to Downscale to 2x size, normalize stats, and announce capturer
    pcall(RegisterHook, "/Script/Pal.PalCaptureSubsystem:OnCaptureSuccess", function(Context, TargetPal, PlayerActor)
        local Pal = TargetPal and TargetPal.get and TargetPal:get() or TargetPal
        if not Pal or not Pal:IsValid() then return end

        local uid, bossData = FindBossMatch(Pal)
        if bossData then
            local CapturedScale = tonumber(Config.BossScaleCaptured) or 2.0
            Pal:SetActorScale3D({ X = CapturedScale, Y = CapturedScale, Z = CapturedScale })

            local IndividualParam = Pal:GetIndividualParameter()
            if IndividualParam and IndividualParam:IsValid() then
                IndividualParam:SetTalentHP(200)
                IndividualParam:SetTalentShotAttack(200)
                IndividualParam:SetTalentDefense(200)

                -- Grant Aura Elemental Emperor / Legend / Mythic Passive Perks
                local meta = AuraSystem.GetMetadata and AuraSystem.GetMetadata(bossData.Aura)
                if meta and meta.Passive and type(IndividualParam.AddPassiveSkill) == "function" then
                    pcall(function()
                        IndividualParam:AddPassiveSkill(FName(meta.Passive))
                    end)
                end
                if meta and meta.SecondaryPassives and type(IndividualParam.AddPassiveSkill) == "function" then
                    for _, sec in ipairs(meta.SecondaryPassives) do
                        pcall(function()
                            IndividualParam:AddPassiveSkill(FName(sec))
                        end)
                    end
                end

                -- Special Mechanics for Transmigrator (2x MoveSpeed)
                if bossData.Aura == "Transmigrator" then
                    pcall(function()
                        if Pal.CharacterMovement and Pal.CharacterMovement:IsValid() then
                            local cm = Pal.CharacterMovement
                            if cm.MaxWalkSpeed then cm.MaxWalkSpeed = cm.MaxWalkSpeed * 2.0 end
                            if cm.MaxFlySpeed then cm.MaxFlySpeed = cm.MaxFlySpeed * 2.0 end
                            if cm.MaxSwimSpeed then cm.MaxSwimSpeed = cm.MaxSwimSpeed * 2.0 end
                        end
                    end)
                end

                -- Special Mechanics for Regressor (4x Base Stats)
                if bossData.Aura == "Regressor" then
                    pcall(function()
                        local charParam = Pal.CharacterParameterComponent
                        if charParam and charParam:IsValid() then
                            local hp = charParam:GetMaxHP() or 5000
                            charParam:SetMaxHP(hp * 4)
                            charParam:SetHP(hp * 4)
                            if type(charParam.SetAttack) == "function" then charParam:SetAttack((charParam:GetAttack() or 100) * 4) end
                            if type(charParam.SetDefense) == "function" then charParam:SetDefense((charParam:GetDefense() or 100) * 4) end
                        end
                    end)
                end
            end

            -- Extract Capturing Player Name
            local playerName = "A brave adventurer"
            pcall(function()
                local p = PlayerActor and PlayerActor.get and PlayerActor:get() or PlayerActor
                if p and p:IsValid() then
                    if p.CharacterParameterComponent and p.CharacterParameterComponent:IsValid() then
                        local nick = p.CharacterParameterComponent:GetNickName()
                        if nick and nick.ToString then playerName = nick:ToString() end
                    end
                    if (not playerName or playerName == "A brave adventurer") and p.PlayerState and p.PlayerState:IsValid() then
                        local psName = p.PlayerState:GetPlayerName()
                        if psName and psName.ToString then playerName = psName:ToString() end
                    end
                end
            end)

            local bossName = bossData.PalDisplayName or bossData.PalId or "World Boss"
            local aura = bossData.Aura or "Elemental"
            local msg = string.format("🎉 %s has captured [%s (%s Aura)]!", playerName, bossName, aura)

            ActiveBosses[uid] = nil
            LiveboardExport.DumpState(ActiveBosses, Config)

            BroadcastInGame(msg, string.format("🎉 %s CAPTURED!", bossName), aura, string.format("Captured by %s", playerName), { X = 0, Y = 0 })

            WorldBoss.BroadcastDiscordEvent(
                "🎉 WORLD BOSS CAPTURED!",
                string.format("🏆 **%s** has successfully captured **%s (%s Aura)**!", playerName, bossName, aura),
                65280 -- Emerald Green
            )
        end
    end)

    pcall(RegisterHook, "/Script/Pal.PalCharacter:OnDead", function(Context)
        local Pal = Context and Context.get and Context:get() or Context
        if not Pal or not Pal:IsValid() then return end

        local uid, bossData = FindBossMatch(Pal)
        if bossData then
            local bossName = bossData.PalDisplayName or bossData.PalId or "World Boss"
            local aura = bossData.Aura or "Elemental"
            local msg = string.format("⚔️ [%s (%s Aura)] has been defeated in battle!", bossName, aura)

            ActiveBosses[uid] = nil
            LiveboardExport.DumpState(ActiveBosses, Config)

            BroadcastInGame(msg, string.format("⚔️ %s DEFEATED!", bossName), aura, "Fallen in combat", { X = 0, Y = 0 })

            WorldBoss.BroadcastDiscordEvent(
                "⚔️ WORLD BOSS DEFEATED!",
                string.format("💀 **%s (%s Aura)** has fallen in battle!", bossName, aura),
                15158332 -- Amber/Red
            )
        end
    end)

    -- Chat Command Ingress (!spawnboss)
    local LastBossCommandText = ""
    local LastBossCommandTime = 0
    local function ProcessBossCommand(Context, Param1, Param2)
        local function TryGetStr(val)
            if not val then return "" end
            local s = ""
            pcall(function()
                local obj = val
                if type(val.get) == "function" then obj = val:get() end
                if type(obj) == "string" then s = obj
                elseif type(obj.ToString) == "function" then s = obj:ToString()
                elseif obj.Message and type(obj.Message.ToString) == "function" then s = obj.Message:ToString() end
            end)
            return s
        end

        local Text = TryGetStr(Param1)
        if Text == "" then Text = TryGetStr(Param2) end
        if Text == "" and Context and Context.Message then Text = TryGetStr(Context.Message) end

        Text = tostring(Text or ""):lower():match("^%s*(.-)%s*$")
        if Text == "!spawnboss" or Text == "/spawnboss" then
            local gameMode = FindFirstOf("PalGameMode")
            if not gameMode or not gameMode:IsValid() then return end
            local clock = os.clock()
            if Text == LastBossCommandText and clock - LastBossCommandTime < 1.0 then return end
            LastBossCommandText, LastBossCommandTime = Text, clock
            local now = os.time()
            local cooldown = math.max(1, tonumber(Config.SpawnCommandCooldownSeconds) or 60)
            if now - LastCommandSpawn < cooldown then
                print("[WorldBossAuraSystem] Manual boss command ignored during cooldown.")
                return
            end
            LastCommandSpawn = now
            print("[WorldBossAuraSystem] Manual boss spawn triggered via chat command!")
            WorldBoss.SpawnEvent()
        end
    end

    local registered = 0
    for _, hookPath in ipairs({
        "/Script/Pal.PalPlayerState:EnterChat",
        "/Script/Pal.PalGameStateInGame:BroadcastChatMessage"
    }) do
        local ok, preId = pcall(RegisterHook, hookPath, ProcessBossCommand)
        if ok and preId then
            registered = registered + 1
            print("[WorldBossAuraSystem] Chat ingress registered: " .. hookPath)
        end
    end
    print(string.format("[WorldBossAuraSystem] %d chat ingress hook(s) registered.", registered))
end

return WorldBoss
