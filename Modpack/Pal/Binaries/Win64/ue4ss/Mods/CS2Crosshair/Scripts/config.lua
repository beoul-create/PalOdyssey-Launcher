-- CS2Crosshair - Configuration Loader
local Config = {
    enabled = true,
    style = "ClassicDynamic", -- "ClassicStatic", "ClassicDynamic", "DotOnly", "TStyle"
    colorPreset = "Green",    -- "Green", "Cyan", "Yellow", "Red", "Pink", "White"
    size = 6.0,
    thickness = 2.0,
    gap = 3.0,
    dot = true,
    dotSize = 2.0,
    drawOutline = true,
    outlineThickness = 1.0,
    tStyle = false,
    dynamicSpread = true,
    dynamicSpreadAmount = 5.0,
    removeWatermark = true,
    cycleColorHotkey = "F7",
    log = true
}

local function LoadConfig()
    local SDIR = (debug.getinfo(1, "S").source:gsub("^@", ""):gsub("[^/\\]+$", ""))
    
    -- 1. Try config.json
    pcall(function()
        local cfgPath = SDIR .. "../config.json"
        local file = io.open(cfgPath, "r")
        if file then
            local content = file:read("*a")
            file:close()
            local ok, parsed = pcall(function()
                local res = {}
                for k, v in string.gmatch(content, '"(%w+)":%s*([^,\n}]+)') do
                    v = v:gsub('^%s*(.-)%s*$', '%1')
                    if v == "true" then res[k] = true
                    elseif v == "false" then res[k] = false
                    elseif tonumber(v) then res[k] = tonumber(v)
                    else res[k] = v:gsub('^"(.*)"$', '%1') end
                end
                return res
            end)
            if ok and parsed and type(parsed) == "table" then
                for k, v in pairs(parsed) do
                    Config[k] = v
                end
            end
        end
    end)

    -- 2. Overlay Mods/shared/CS2Crosshair_user.lua from DarnMenu if present
    pcall(function()
        local userPath = SDIR .. "../../shared/CS2Crosshair_user.lua"
        local chunk = loadfile and loadfile(userPath)
        if chunk then
            local ok, userCfg = pcall(chunk)
            if ok and type(userCfg) == "table" then
                for k, v in pairs(userCfg) do
                    Config[k] = v
                end
            end
        end
    end)
end

LoadConfig()
return Config
