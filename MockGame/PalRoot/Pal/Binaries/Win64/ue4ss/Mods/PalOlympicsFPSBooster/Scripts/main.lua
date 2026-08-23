-- ====================================================================================
-- PalOdyssey Ultra FPS, Memory & Engine Fluidity Suite (v1.2.0)
-- Full Real-Time Config Integration, Adaptive Unreal Engine CVars,
-- Fast Travel Teleport Acceleration, URO Pal Anim Culling, and Zero-Overhead GC.
-- ====================================================================================

local Config = {
    server_branding_text = "⚡ PalOdyssey Expedition Realm",
    enable_server_info_branding = true,
    enable_pal_animation_fluidity = true,
    enable_ultra_texture_clarity = true,
    enable_custom_stylized_sky = true,
    enable_background_fps_limiter = true,
    background_fps_target = 30,
    enable_cpu_resource_reduction = true,
    enable_base_pal_tick_optimization = true,
    enable_smart_gc_on_fast_travel = true,
    enable_instant_ui_responsiveness = true,
    enable_storage_data_caching = true,
    enable_instant_fast_travel_loading = true,
    texture_streaming_pool_mb = 4096,
    distant_pal_tick_interval_ms = 250,
    fast_travel_gc_delay_ms = 1500
}

-- Simple, zero-dependency JSON decoder for standard Lua in UE4SS
local function parseJson(str)
    if not str or str == "" then return {} end
    local res = {}
    -- Booleans
    for k, v in string.gmatch(str, '"([%w_]+)"%s*:%s*(true|false)') do
        res[k] = (v == "true")
    end
    -- Numbers
    for k, v in string.gmatch(str, '"([%w_]+)"%s*:%s*([%-0-9%.]+)') do
        res[k] = tonumber(v)
    end
    -- Strings
    for k, v in string.gmatch(str, '"([%w_]+)"%s*:%s*"([^"]*)"') do
        res[k] = v
    end
    return res
end

local function loadConfig()
    local searchPaths = {
        "Mods/PalOlympicsFPSBooster/config.json",
        "Pal/Binaries/Win64/Mods/PalOlympicsFPSBooster/config.json",
        "../Mods/PalOlympicsFPSBooster/config.json"
    }
    for _, p in ipairs(searchPaths) do
        local f = io.open(p, "r")
        if f then
            local content = f:read("*all")
            f:close()
            local parsed = parseJson(content)
            for k, v in pairs(parsed) do
                Config[k] = v
            end
            print(string.format("[PalOdysseyFPSBooster] Config successfully parsed from '%s'.", p))
            return
        end
    end
    print("[PalOdysseyFPSBooster] Notice: config.json not found in search paths. Using optimized defaults.")
end

loadConfig()

-- ====================================================================================
-- Engine CVars & Native Execution Pipeline
-- ====================================================================================

local KismetInstance = nil
local function getKismet()
    if not KismetInstance or not KismetInstance:IsValid() then
        KismetInstance = StaticFindObject("/Script/Engine.Default__KismetSystemLibrary")
    end
    return KismetInstance
end

local function applyEngineCVars()
    local Kismet = getKismet()
    local World = FindFirstOf("World")
    if not (Kismet and Kismet:IsValid() and World and World:IsValid()) then
        return
    end

    -- 1. Ultra-Fast Texture & Asset Streaming
    if Config.enable_ultra_texture_clarity then
        local poolMb = Config.texture_streaming_pool_mb or 4096
        Kismet:ExecuteConsoleCommand(World, string.format("r.Streaming.PoolSize %d", poolMb), nil)
        Kismet:ExecuteConsoleCommand(World, "r.Streaming.LimitPoolSizeToVRAM 1", nil)
        Kismet:ExecuteConsoleCommand(World, "r.Streaming.MaxNumTexturesToStreamPerCycle 4", nil)
        Kismet:ExecuteConsoleCommand(World, "r.Streaming.FramesForFullUpdate 20", nil)
        Kismet:ExecuteConsoleCommand(World, "r.Streaming.AmortizeCPUToGPUCopy 1", nil)
        Kismet:ExecuteConsoleCommand(World, "r.Streaming.DefragDynamicBounds 1", nil)
        Kismet:ExecuteConsoleCommand(World, "r.TextureStreaming 1", nil)
    end

    -- 2. CPU Multi-threading, Async Niagara & Shader Pipeline
    if Config.enable_cpu_resource_reduction then
        Kismet:ExecuteConsoleCommand(World, "r.ParallelMeshDispatch 1", nil)
        Kismet:ExecuteConsoleCommand(World, "fx.Niagara.AllowAsyncTick 1", nil)
        Kismet:ExecuteConsoleCommand(World, "s.AsyncLoadingTime 6.0", nil)
        Kismet:ExecuteConsoleCommand(World, "s.PriorityAsyncLoadingExtraTime 8.0", nil)
        Kismet:ExecuteConsoleCommand(World, "s.LevelStreamingActorsUpdateTimeLimit 5.0", nil)
        Kismet:ExecuteConsoleCommand(World, "s.PriorityLevelStreamingActorsUpdateExtraTime 8.0", nil)
        Kismet:ExecuteConsoleCommand(World, "r.ShaderPipelineCache.PreCompile 0", nil)
    end

    -- 3. Base Pal Animation Fluidity & Update Rate Optimization (URO)
    if Config.enable_base_pal_tick_optimization or Config.enable_pal_animation_fluidity then
        Kismet:ExecuteConsoleCommand(World, "a.URO.Enable 1", nil)
        Kismet:ExecuteConsoleCommand(World, "a.URO.ForceAnimRate 0", nil)
        Kismet:ExecuteConsoleCommand(World, "a.URO.Bypass 0", nil)
        Kismet:ExecuteConsoleCommand(World, "r.MeshLODRange 1", nil)
    end

    -- 4. Garbage Collection Management
    if Config.enable_smart_gc_on_fast_travel then
        Kismet:ExecuteConsoleCommand(World, "gc.TimeBetweenPurgingPendingKillObjects 60", nil)
        Kismet:ExecuteConsoleCommand(World, "gc.FlushStreamingOnGC 0", nil)
    end

    -- 5. Background FPS Limiter
    if Config.enable_background_fps_limiter then
        local targetFps = Config.background_fps_target or 30
        Kismet:ExecuteConsoleCommand(World, string.format("t.UnfocusedFPS %d", targetFps), nil)
    end

    -- 6. Stylized Sky & Volumetrics
    if Config.enable_custom_stylized_sky then
        Kismet:ExecuteConsoleCommand(World, "r.VolumetricFog 1", nil)
        Kismet:ExecuteConsoleCommand(World, "r.SkyAtmosphere 1", nil)
    end

    print("[PalOdysseyFPSBooster] Performance CVars successfully applied from active configuration.")
end

-- Apply on boot and on periodic intervals
applyEngineCVars()
ExecuteWithDelay(1500, applyEngineCVars)
ExecuteWithDelay(5000, applyEngineCVars)

-- Re-apply whenever a world or game state initializes
pcall(function()
    RegisterHook("/Script/Engine.GameModeBase:InitGameState", function()
        ExecuteWithDelay(1000, function()
            loadConfig()
            applyEngineCVars()
        end)
    end)
    RegisterHook("/Script/Pal.PalPlayerCharacter:ReceiveBeginPlay", function()
        ExecuteWithDelay(500, function()
            applyEngineCVars()
        end)
    end)
end)

-- ====================================================================================
-- Fast Travel & UI Fluidity Acceleration Suite
-- ====================================================================================

if Config.enable_instant_ui_responsiveness then
    pcall(function()
        RegisterHook("/Script/UMG.UserWidget:PlayAnimation", function(self, InAnimation, StartAtTime, NumLoopsToPlay, PlayMode, PlaybackSpeed)
            local widget = self:get()
            if widget and widget:IsValid() then
                local class = widget:GetClass()
                if class and class:IsValid() then
                    local wName = class:GetFName():ToString()
                    if Config.enable_instant_fast_travel_loading and (string.find(wName, "Fade") or string.find(wName, "Loading") or string.find(wName, "Blackout") or string.find(wName, "Teleport") or string.find(wName, "Transition")) then
                        pcall(function()
                            PlaybackSpeed:set(100.0) -- 100x instant animation playback
                        end)
                    elseif string.find(wName, "Map") or string.find(wName, "Inventory") or string.find(wName, "PalBox") or string.find(wName, "Chest") or string.find(wName, "Storage") or string.find(wName, "BuildMenu") or string.find(wName, "Technology") then
                        pcall(function()
                            PlaybackSpeed:set(6.0) -- 6x Snappy interactive menus
                        end)
                    end
                end
            end
        end)
    end)
end

if Config.enable_instant_fast_travel_loading then
    local function zeroOutFadeDuration(FadeTime)
        pcall(function()
            local t = FadeTime:get()
            if t and t > 0.001 then
                FadeTime:set(0.0001)
            end
        end)
    end

    pcall(function()
        RegisterHook("/Script/Pal.PalFadeSubsystem:FadeIn", function(self, FadeTime) zeroOutFadeDuration(FadeTime) end)
        RegisterHook("/Script/Pal.PalFadeSubsystem:FadeOut", function(self, FadeTime) zeroOutFadeDuration(FadeTime) end)
        RegisterHook("/Script/Pal.PalFadeSubsystem:StartFade", function(self, FadeType, FadeTime) zeroOutFadeDuration(FadeTime) end)
        RegisterHook("/Script/Pal.PalFadeSubsystem:StartFade_Native", function(self, FadeType, FadeTime) zeroOutFadeDuration(FadeTime) end)
        RegisterHook("/Script/Pal.PalFadeWidget:FadeIn", function(self, FadeTime) zeroOutFadeDuration(FadeTime) end)
        RegisterHook("/Script/Pal.PalFadeWidget:FadeOut", function(self, FadeTime) zeroOutFadeDuration(FadeTime) end)
        RegisterHook("/Script/Pal.PalFadeWidget:Fade", function(self, FadeType, FadeTime) zeroOutFadeDuration(FadeTime) end)
    end)

    pcall(function()
        RegisterHook("/Script/Engine.PlayerCameraManager:StartCameraFade", function(self, FromAlpha, ToAlpha, Duration, Color, bShouldFadeAudio, bHoldWhenFinished)
            pcall(function()
                local d = Duration:get()
                if d and d > 0.001 then
                    Duration:set(0.0001)
                end
            end)
        end)
    end)

    local function onFastTravelTriggered()
        local Kismet = getKismet()
        local World = FindFirstOf("World")
        if Kismet and Kismet:IsValid() and World and World:IsValid() then
            Kismet:ExecuteConsoleCommand(World, "s.AsyncLoadingTime 25.0", nil)
            Kismet:ExecuteConsoleCommand(World, "s.PriorityAsyncLoadingExtraTime 20.0", nil)

            ExecuteWithDelay(400, function()
                local K2 = getKismet()
                local W2 = FindFirstOf("World")
                if K2 and W2 and K2:IsValid() and W2:IsValid() then
                    K2:ExecuteConsoleCommand(W2, "s.AsyncLoadingTime 6.0", nil)
                    K2:ExecuteConsoleCommand(W2, "s.PriorityAsyncLoadingExtraTime 8.0", nil)
                end
            end)
        end
    end

    pcall(function()
        RegisterHook("/Script/Pal.PalPlayerLocationSubsystem:RequestFastTravel", onFastTravelTriggered)
        RegisterHook("/Script/Pal.PalPlayerLocationSubsystem:TransfarLocation", onFastTravelTriggered)
        RegisterHook("/Script/Pal.PalPlayerLocationSubsystem:TransferLocation", onFastTravelTriggered)
        RegisterHook("/Script/Pal.PalLocationManager:RequestFastTravel", onFastTravelTriggered)
    end)
end

-- ====================================================================================
-- Smart Garbage Collection Post-Teleport
-- ====================================================================================

if Config.enable_smart_gc_on_fast_travel then
    local gcDelay = Config.fast_travel_gc_delay_ms or 1500
    pcall(function()
        RegisterHook("/Script/Pal.PalLocationManager:RequestFastTravel", function()
            ExecuteWithDelay(gcDelay, function()
                local Kismet = getKismet()
                local World = FindFirstOf("World")
                if Kismet and World and Kismet:IsValid() and World:IsValid() then
                    Kismet:ExecuteConsoleCommand(World, "gc.CollectGarbage", nil)
                end
            end)
        end)
    end)
end

-- ====================================================================================
-- Auto-Dismiss & Remove In-Game Mod Guidelines & Caution Dialogs
-- ====================================================================================

pcall(function()
    RegisterHook("/Script/UMG.UserWidget:Construct", function(self)
        pcall(function()
            local widget = self:get()
            if not widget or not widget:IsValid() then return end

            local name = widget:GetClass():GetName()
            if name:find("Warning_Mod") or name:find("ModCaution") or name:find("ModPolicy") or 
               name:find("Title_Warning") or name:find("ModWarning") or name:find("Title_Notice") or
               name:find("Notice_Mod") then
                
                -- Set visibility to Collapsed
                if widget.SetVisibility then
                    widget:SetVisibility(2)
                end

                -- Auto-trigger confirm button event if present
                if widget.WBP_PalCommonButton and widget.WBP_PalCommonButton:IsValid() then
                    if widget.WBP_PalCommonButton.OnClicked then
                        widget.WBP_PalCommonButton.OnClicked:Broadcast()
                    end
                end
                if widget.Button_OK and widget.Button_OK:IsValid() and widget.Button_OK.OnClicked then
                    widget.Button_OK.OnClicked:Broadcast()
                end
                if widget.Button_Confirm and widget.Button_Confirm:IsValid() and widget.Button_Confirm.OnClicked then
                    widget.Button_Confirm.OnClicked:Broadcast()
                end

                if widget.RemoveFromParent then
                    widget:RemoveFromParent()
                end
                print(string.format("[PalOdyssey] Auto-bypassed and dismissed mod guideline dialog (%s).", name))
            elseif name:find("WBP_TitleMenu") then
                if widget.WBP_Title_Warning_Mod and widget.WBP_Title_Warning_Mod:IsValid() then
                    widget.WBP_Title_Warning_Mod:SetVisibility(2)
                    widget.WBP_Title_Warning_Mod:RemoveFromParent()
                end
            end
        end)
    end)
end)

print("[PalOdysseyFPSBooster] v1.2.0 active with fully integrated config pipeline and mod disclaimer bypass.")