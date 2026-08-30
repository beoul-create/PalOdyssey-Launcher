local Config = {
    enabled = true,
    bypassIntroMovies = true,
    accelerateLoadingScreens = true,
    bypassFastTravelWait = true,
    ultraFastNetworkRates = true,
    prewarmShaderPipelines = true
}

local ScriptDir = debug.getinfo(1, "S").source:gsub("^@", ""):gsub("[^/\\]+$", "")

local function LoadConfig()
    pcall(function()
        local configFile = io.open(ScriptDir .. "../config.json", "r")
        if configFile then
            local content = configFile:read("*all")
            configFile:close()
            local jsonDecoder = JSON or json or _G.json
            if not jsonDecoder then
                pcall(function() jsonDecoder = require("json") end)
            end
            local decode = jsonDecoder and (jsonDecoder.decode or jsonDecoder.parse)
            if type(decode) == "function" then
                local decoded = decode(content)
                if type(decoded) == "table" then
                    for k, v in pairs(decoded) do
                        Config[k] = v
                    end
                end
            end
        end
    end)
end

LoadConfig()

return Config
