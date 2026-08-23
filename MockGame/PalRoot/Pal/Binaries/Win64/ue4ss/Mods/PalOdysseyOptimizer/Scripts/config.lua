-- PalOdysseyOptimizer - Configuration & Preset Management
local Config = {}

Config.current = {
    preset = "balanced",
    rawInput = {
        enabled = true,
        disableSmoothing = true,
        disableAcceleration = true
    },
    network = {
        enabled = true,
        maxBandwidth = 1048576,
        minBandwidth = 65536,
        maxNetSerializePerFrame = 5000,
        reliableRetryDelay = 0.05
    },
    graphics = {
        enabled = true,
        enableGpuSkinning = true,
        oneFrameThreadLag = true,
        multithreadedShaders = true,
        optimizeNaniteLumen = true,
        shadowBudgetOptimization = true
    },
    cpu = {
        enabled = true,
        limitBackgroundCpu = false,
        taskGraphTasksPerTick = 100,
        gcIntervalSeconds = 60
    },
    memory = {
        enabled = true,
        autoTrimWorkingSet = true,
        trimIntervalMinutes = 5,
        defragTexturePool = true
    },
    server = {
        enabled = true,
        connectionTimeout = 120,
        initialConnectTimeout = 180,
        adaptiveReplication = true
    }
}

function Config.load()
    local ok, file = pcall(io.open, "ue4ss/Mods/PalOdysseyOptimizer/config.json", "r")
    if not ok or not file then
        ok, file = pcall(io.open, "Mods/PalOdysseyOptimizer/config.json", "r")
    end

    if ok and file then
        local content = file:read("*a")
        file:close()
        -- Basic json value parser or fallback to defaults
    end
    return Config.current
end

return Config
