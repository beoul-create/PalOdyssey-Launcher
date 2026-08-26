-- SAODeath - Configuration Loader
local Config = {
    enabled = true,
    soundVolume = 1.0,
    particleScale = 1.0,
    particleCount = 80,
    suppressRagdollPhysics = true,
    instantMeshHide = true,
    cleanupDelayMs = 150,
    enablePlayerDeathEffect = true,
    enablePalDeathEffect = true,
    enableNpcDeathEffect = true,
    log = true
}

local function LoadConfig()
    pcall(function()
        local SDIR = (debug.getinfo(1, "S").source:gsub("^@", ""):gsub("[^/\\]+$", ""))
        local cfgPath = SDIR .. "../config.json"
        local file = io.open(cfgPath, "r")
        if file then
            local content = file:read("*a")
            file:close()
            local ok, parsed = pcall(function()
                -- Simple JSON parser / fallback
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
end

LoadConfig()
return Config
