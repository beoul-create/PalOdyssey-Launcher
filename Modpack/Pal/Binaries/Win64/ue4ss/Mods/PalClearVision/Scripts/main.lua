-- PalClearVision: Removes washed-out fog haze, film grain, and chromatic aberration for crystal clear visuals
local ok, Config = pcall(require, "config")
if not ok or type(Config) ~= "table" then
    Config = {
        enabled = true,
        removeFogHaze = true,
        disableChromaticAberration = true,
        disableFilmGrain = true,
        crispDepthOfField = true,
        enhancedShadowDistance = true,
        log = true
    }
end

local function Log(msg)
    if Config.log then
        print(string.format("[PalClearVision] %s\n", tostring(msg)))
    end
end

if not Config.enabled then return end

local function ApplyVisualTweaks()
    pcall(function()
        local player = GetPlayerController()
        if not player or not player:IsValid() then return end

        if Config.removeFogHaze then
            ExecuteConsoleCommand("r.VolumetricFog 0")
        end
        if Config.disableChromaticAberration then
            ExecuteConsoleCommand("r.SceneColorFringeQuality 0")
        end
        if Config.disableFilmGrain then
            ExecuteConsoleCommand("r.Tonemapper.GrainQuantization 0")
            ExecuteConsoleCommand("r.Tonemapper.Quality 1")
        end
        if Config.crispDepthOfField then
            ExecuteConsoleCommand("r.DepthOfFieldQuality 0")
        end
        if Config.enhancedShadowDistance then
            ExecuteConsoleCommand("r.Shadow.DistanceScale 1.4")
        end

        Log("Applied visual clarity settings.")
    end)
end

-- Apply on game start and world entry
NotifyOnNewObject("/Script/Pal.PalGameSetting", function()
    LoopAsync(3000, function()
        ApplyVisualTweaks()
        return true -- Run once per session after player spawns
    end)
end)

Log("PalClearVision loaded successfully.")
