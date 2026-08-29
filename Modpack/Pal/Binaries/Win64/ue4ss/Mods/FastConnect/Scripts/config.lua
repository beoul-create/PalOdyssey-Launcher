local Config = {
    enabled = true,
    bypassIntroMovies = true,
    accelerateLoadingScreens = true,
    bypassFastTravelWait = true,
    ultraFastNetworkRates = true,
    prewarmShaderPipelines = true
}

local function LoadConfig()
    pcall(function()
        local configFile = io.open("Mods/FastConnect/config.json", "r")
        if configFile then
            local content = configFile:read("*all")
            configFile:close()
            local jsonDecoder = json or _G.json
            if not jsonDecoder then
                pcall(function() jsonDecoder = require("json") end)
            end
            if jsonDecoder and type(jsonDecoder.decode) == "function" then
                local decoded = jsonDecoder.decode(content)
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
