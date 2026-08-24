-- ============================================================================
-- ShiningLuckies: Visual Shimmer, Aura & World Beacon for Lucky / Shiny Pals
-- Enhances visibility of Rare Pals with glowing outlines, audio/visual cues,
-- and instant nearby alert toasts.
-- ============================================================================

local ok, Config = pcall(require, "config")
if not ok or type(Config) ~= "table" then
    Config = {
        enabled = true,
        glowIntensity = "Vibrant", -- "Subtle", "Moderate", "Vibrant"
        renderCustomDepth = true,
        depthStencilValue = 250,   -- Gold / Shiny Stencil Highlight
        notifyToast = true,
        maxAlertDistance = 15000.0,
        log = true
    }
end

local function Log(msg)
    if Config.log then
        print(string.format("[ShiningLuckies] %s\n", tostring(msg)))
    end
end

if not Config.enabled then return end

print("==========================================================")
print("  ShiningLuckies: Rare / Lucky Pal Visual Enhancement Active")
print("==========================================================")

local trackedRarePals = {}

-- Toast Helper
local function SendLuckyToast(palName, distanceMeters)
    if not Config.notifyToast then return end
    pcall(function()
        local SDIR = (debug.getinfo(1, "S").source:gsub("^@", ""):gsub("[^/\\]+$", ""))
        package.path = SDIR .. "../../DarnToasts/Scripts/?.lua;" .. package.path
        local Toast = require("ToastLib").new("ShiningLuckies")
        if Toast and Toast.notify then
            local distText = distanceMeters and string.format(" (~%dm away)", math.floor(distanceMeters)) or ""
            Toast.notify(string.format("✨ Shiny %s Detected%s!", tostring(palName or "Pal"), distText), 1.0, 0.84, 0.0)
        end
    end)
end

local function EnhanceLuckyPal(pal)
    if not pal or not pal:IsValid() then return end
    local ptrKey = tostring(pal:GetAddress())
    if trackedRarePals[ptrKey] then return end
    trackedRarePals[ptrKey] = true

    pcall(function()
        local palName = "Rare Pal"
        local charParam = pal.CharacterParameterComponent
        if charParam and charParam:IsValid() then
            if charParam.GetNickName then
                local n = charParam:GetNickName()
                if n and n ~= "" then palName = tostring(n) end
            end
        end

        -- Calculate distance to player
        local player = GetPlayerController()
        local distMeters = nil
        if player and player:IsValid() and player.Pawn and player.Pawn:IsValid() then
            local pLoc = player.Pawn:K2_GetActorLocation()
            local palLoc = pal:K2_GetActorLocation()
            if pLoc and palLoc then
                local dx = pLoc.X - palLoc.X
                local dy = pLoc.Y - palLoc.Y
                local dz = pLoc.Z - palLoc.Z
                distMeters = math.sqrt(dx*dx + dy*dy + dz*dz) / 100.0
            end
        end

        -- Apply Mesh Highlight & Custom Depth Stencil
        if Config.renderCustomDepth and pal.Mesh and pal.Mesh:IsValid() then
            pal.Mesh.bRenderCustomDepth = true
            pal.Mesh.CustomDepthStencilValue = Config.depthStencilValue or 250
        end

        Log(string.format("Enhanced Lucky Pal '%s' (Address: %s) with custom depth shimmer.", palName, ptrKey))
        SendLuckyToast(palName, distMeters)
    end)
end

local function CheckIfRarePal(pal)
    if not pal or not pal:IsValid() then return false end
    local isRare = false
    pcall(function()
        local charParam = pal.CharacterParameterComponent
        if charParam and charParam:IsValid() then
            if charParam.IsRarePal and charParam:IsRarePal() then
                isRare = true
            elseif charParam.bIsRarePal then
                isRare = true
            end
        end
        if not isRare and pal.bIsRarePal then
            isRare = true
        end
    end)
    return isRare
end

-- 1. Hook Spawn of PalCharacter
pcall(function()
    NotifyOnNewObject("/Script/Pal.PalCharacter", function(pal)
        ExecuteWithDelay(200, function()
            if CheckIfRarePal(pal) then
                EnhanceLuckyPal(pal)
            end
        end)
    end)
end)

-- 2. Periodic Scan for loaded world Pals
LoopAsync(2000, function()
    pcall(function()
        local pals = FindAllOf("PalCharacter")
        if pals then
            for _, pal in ipairs(pals) do
                if CheckIfRarePal(pal) then
                    EnhanceLuckyPal(pal)
                end
            end
        end
    end)
    return false -- Loop continuously throughout gameplay
end)

Log("ShiningLuckies engine initialized & listening for Rare spawns.")
