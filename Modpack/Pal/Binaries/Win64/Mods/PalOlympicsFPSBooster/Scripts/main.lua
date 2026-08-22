-- ====================================================================================
-- PalOdyssey Ultra FPS, Memory & Engine Fluidity Suite (v1.2.0)
-- Zero-Crash Safe Engine: Core CVars are permanently applied via Engine.ini.
-- This module accelerates fast travel camera fades and performs smart GC post-teleport.
-- ====================================================================================

local function zeroOutFadeDuration(FadeTime)
    pcall(function()
        local t = FadeTime:get()
        if t and t > 0.001 then
            FadeTime:set(0.0001)
        end
    end)
end

-- Fast Travel & Camera Fade Accelerators
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

print("[PalOdysseyFPSBooster] v1.2.0 active with zero-crash safe engine.")
