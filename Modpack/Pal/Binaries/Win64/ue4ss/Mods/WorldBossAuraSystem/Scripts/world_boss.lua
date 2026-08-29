local WorldBoss = {}
local AuraSystem = require("scripts.aura_system")
local LiveboardExport = require("scripts.liveboard_export")

local ActiveBosses = {}
local Config = {}

function WorldBoss.LoadConfig(Cfg)
    Config = Cfg
end

function WorldBoss.GetActiveBosses()
    return ActiveBosses
end

function WorldBoss.BroadcastDiscord(PalName, AuraType, LocationName, Pos)
    if not Config.DiscordWebhookURL or Config.DiscordWebhookURL == "YOUR_DISCORD_WEBHOOK_URL_HERE" then return end
    local Payload = string.format(
        '{"embeds":[{"title":"⚠️ WORLD BOSS SPAWNED!","description":"**%s (%s Aura)** has appeared!\\n**Location:** %s\\n**Coords:** X: %.0f, Y: %.0f","color":16711680}]}',
        PalName, AuraType, LocationName, Pos.X, Pos.Y
    )
    ExecuteConsoleCommand(string.format('curl -s -H "Content-Type: application/json" -X POST -d \'%s\' %s', Payload, Config.DiscordWebhookURL))
end

function WorldBoss.SpawnEvent()
    if not Config.SpawnPoints or #Config.SpawnPoints == 0 then return end

    local Point = Config.SpawnPoints[math.random(#Config.SpawnPoints)]
    local PalId = Config.BossPalPool[math.random(#Config.BossPalPool)]
    local Auras = { "Fiery", "Corrupted", "Celestial" }
    local SelectedAura = Auras[math.random(#Auras)]

    local SpawnerSubsystem = StaticFindObject("/Script/Pal.PalSpawnerSubsystem")
    if not SpawnerSubsystem or not SpawnerSubsystem:IsValid() then return end

    -- Spawn Actor at Target Location
    local SpawnLoc = { X = Point.X, Y = Point.Y, Z = Point.Z }
    local BossActor = SpawnerSubsystem:SpawnIndividualPal(FName(PalId), SpawnLoc, { Pitch=0, Yaw=0, Roll=0 })

    if BossActor and BossActor:IsValid() then
        -- Apply 3.0x Visual Scale
        BossActor:SetActorScale3D({ X = Config.BossScaleWorld, Y = Config.BossScaleWorld, Z = Config.BossScaleWorld })

        -- Apply 100x HP and 2x Combat Parameters
        local Param = BossActor.CharacterParameterComponent
        if Param and Param:IsValid() then
            local BaseHP = Param:GetMaxHP()
            Param:SetMaxHP(BaseHP * 100)
            Param:SetHP(BaseHP * 100)
            Param:SetAttack(Param:GetAttack() * 2)
            Param:SetDefense(Param:GetDefense() * 2)
        end

        -- Attach Linked Visual Aura
        AuraSystem.Attach(BossActor, SelectedAura)

        -- Record Active Boss Instance with liveboard metadata
        ActiveBosses[BossActor:GetUniqueID()] = {
            PalId = PalId,
            Aura = SelectedAura,
            LocationName = Point.Name,
            Coords = { X = Point.X, Y = Point.Y },
            SpawnTime = os.time()
        }

        -- Broadcast Discord announcement
        WorldBoss.BroadcastDiscord(PalId, SelectedAura, Point.Name, SpawnLoc)

        -- Update Liveboard export
        LiveboardExport.DumpState(ActiveBosses, Config)
    end
end

function WorldBoss.InitHooks()
    -- Hook Capture Event to Downscale to 2x size and normalize stats
    RegisterHook("/Script/Pal.PalCaptureSubsystem:OnCaptureSuccess", function(Context, TargetPal, PlayerActor)
        local Pal = TargetPal:get()
        if not Pal or not Pal:IsValid() then return end

        local UID = Pal:GetUniqueID()
        if ActiveBosses[UID] then
            -- Downsize to 2x Scale
            Pal:SetActorScale3D({ X = Config.BossScaleCaptured, Y = Config.BossScaleCaptured, Z = Config.BossScaleCaptured })

            -- Set Permanent 2x Talent (IV) Modifiers
            local IndividualParam = Pal:GetIndividualParameter()
            if IndividualParam and IndividualParam:IsValid() then
                IndividualParam:SetTalentHP(200)
                IndividualParam:SetTalentShotAttack(200)
                IndividualParam:SetTalentDefense(200)
            end

            ActiveBosses[UID] = nil

            -- Refresh liveboard file
            LiveboardExport.DumpState(ActiveBosses, Config)
        end
    end)
end

return WorldBoss
