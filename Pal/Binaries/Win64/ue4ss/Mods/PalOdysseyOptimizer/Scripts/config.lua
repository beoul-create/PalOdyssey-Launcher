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
        limitBackgroundCpu = true,
        backgroundMaxFPS = 30,
        taskGraphTasksPerTick = 100,
        gcIntervalSeconds = 60
    },
    memory = {
        enabled = true,
        autoTrimWorkingSet = false,
        trimIntervalMinutes = 5,
        defragTexturePool = false
    },
    server = {
        enabled = true,
        connectionTimeout = 120,
        initialConnectTimeout = 180,
        adaptiveReplication = true
    }
}

function Config.load()
    local scriptDir = debug.getinfo(1, "S").source:gsub("^@", ""):gsub("[^/\\]+$", "")
    local ok, file = pcall(io.open, scriptDir .. "../config.json", "r")

    if ok and file then
        local content = file:read("*a")
        file:close()
        if type(JSON) == "table" and type(JSON.parse) == "function" then
            local parsedOk, parsed = pcall(JSON.parse, content)
            if parsedOk and type(parsed) == "table" then
                local function merge(target, source)
                    for key, value in pairs(source) do
                        if type(value) == "table" and type(target[key]) == "table" then
                            merge(target[key], value)
                        else
                            target[key] = value
                        end
                    end
                end
                merge(Config.current, parsed)
            end
        end
    end
    return Config.current
end

return Config
