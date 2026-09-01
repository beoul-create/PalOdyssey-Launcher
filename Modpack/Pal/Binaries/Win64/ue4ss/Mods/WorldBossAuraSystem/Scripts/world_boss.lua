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
        for _, pc in ipairs(FindAllOf("PalPlayerController") or {}) do
            local ps = pc and pc:IsValid() and pc.PlayerState or nil
            if ps and ps:IsValid() then
                found = true
                return
            end
        end
    end)
    return found
end

local function BroadcastInGame(Text)
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
                end
            end
        end
    end)
    print("[WorldBossAuraSystem] Broadcast: " .. tostring(Text))
end

function WorldBoss.BroadcastDiscord(PalName, AuraType, LocationName, Pos)
    if not Config.DiscordWebhookURL or Config.DiscordWebhookURL == "YOUR_DISCORD_WEBHOOK_URL_HERE" then return end
    pcall(function()
        local Payload = string.format(
            '{"embeds":[{"title":"⚠️ WORLD BOSS SPAWNED!","description":"**%s (%s Aura)** has appeared!\\n**Location:** %s\\n**Coords:** X: %.0f, Y: %.0f","color":16711680}]}',
            PalName, AuraType, LocationName, Pos.X, Pos.Y
        )
        if type(ExecuteConsoleCommand) == "function" then
            ExecuteConsoleCommand(string.format('curl -s -H "Content-Type: application/json" -X POST -d \'%s\' %s', Payload, Config.DiscordWebhookURL))
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
    local Auras = { "Fiery", "Corrupted", "Celestial" }
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

        -- 1. Direct UE5 World:SpawnActor with Monster Blueprint Class
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
                        local name = actor:GetClass():GetName()
                        if name:find(PalId) or name:find("Monster") or name:find("PalCharacter") then
                            BossActor = actor
                            local loc = actor:K2_GetActorLocation() or actor:GetActorLocation()
                            if loc then
                                SpawnLoc = { X = loc.X, Y = loc.Y, Z = loc.Z }
                                Point = { Name = "Wild Encounter Location", X = loc.X, Y = loc.Y, Z = loc.Z }
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

        -- 2. Apply 100x HP and 2x Combat Parameters
        pcall(function()
            local Param = BossActor.CharacterParameterComponent
            if Param and Param:IsValid() then
                local BaseHP = Param:GetMaxHP() or 5000
                Param:SetMaxHP(BaseHP * 100)
                Param:SetHP(BaseHP * 100)
                if type(Param.SetAttack) == "function" then Param:SetAttack((Param:GetAttack() or 100) * 2) end
                if type(Param.SetDefense) == "function" then Param:SetDefense((Param:GetDefense() or 100) * 2) end
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
            Aura = SelectedAura,
            LocationName = Point.Name,
            Coords = { X = Point.X, Y = Point.Y },
            SpawnTime = os.time()
        }

        -- 5. Broadcast to in-game chat and HUD
        BroadcastInGame(string.format("⚠️ WORLD BOSS SPAWNED: [%s (%s Aura)] has appeared at %s! (Coords: %.0f, %.0f)", PalDisplayName, SelectedAura, Point.Name, Point.X, Point.Y))

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

function WorldBoss.InitHooks()
    -- Hook Capture Event to Downscale to 2x size and normalize stats
    pcall(RegisterHook, "/Script/Pal.PalCaptureSubsystem:OnCaptureSuccess", function(Context, TargetPal, PlayerActor)
        local Pal = TargetPal and TargetPal.get and TargetPal:get() or TargetPal
        if not Pal or not Pal:IsValid() then return end

        local UID = Pal:GetUniqueID()
        if ActiveBosses[UID] then
            local CapturedScale = tonumber(Config.BossScaleCaptured) or 2.0
            Pal:SetActorScale3D({ X = CapturedScale, Y = CapturedScale, Z = CapturedScale })

            local IndividualParam = Pal:GetIndividualParameter()
            if IndividualParam and IndividualParam:IsValid() then
                IndividualParam:SetTalentHP(200)
                IndividualParam:SetTalentShotAttack(200)
                IndividualParam:SetTalentDefense(200)
            end

            ActiveBosses[UID] = nil
            LiveboardExport.DumpState(ActiveBosses, Config)
            BroadcastInGame("🎉 A World Boss has been captured!")
        end
    end)

    pcall(RegisterHook, "/Script/Pal.PalCharacter:OnDead", function(Context)
        local Pal = Context and Context.get and Context:get() or Context
        if not Pal or not Pal:IsValid() then return end

        local UID = Pal:GetUniqueID()
        if ActiveBosses[UID] then
            ActiveBosses[UID] = nil
            LiveboardExport.DumpState(ActiveBosses, Config)
            BroadcastInGame("⚔️ A World Boss has been defeated!")
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
