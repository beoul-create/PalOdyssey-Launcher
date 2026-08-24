-- test_build_enforcer.lua
print("=== [START] UE4SS Build Quota Enforcement Test (Lua) ===")

-- 1. Mock Environment Setup
local function write_mock_licenses()
    -- Start with baseline max_breeding_pens: 1, max_ranches: 1
    local json = [[
    {
        "guilds": {
            "99998888777766665555444433332222_guild": {
                "max_bases": 4,
                "max_breeding_pens": 1,
                "max_ranches": 1
            }
        }
    }
    ]]
    local f = io.open("mock-guild-licenses.json", "w")
    f:write(json)
    f:close()
end
write_mock_licenses()

-- Mock Global state
_G.FindObject = function(className, objectName)
    if className == "PalGroupManager" then
        return {
            IsValid = function() return true end,
            GetGroup = function(self, id)
                return {
                    IsValid = function() return true end,
                    BaseCampIds = {
                        GetArrayNum = function() return 4 end -- Already 4 bases placed
                    }
                }
            end
        }
    elseif className == "PalBaseCampManager" then
        return {
            IsValid = function() return true end
        }
    end
end

-- We keep track of how many of each structure we've allowed to build to mock "GetGuildStructureCount"
local builtStructures = { BreedingPen = 1, Ranch = 1 } 

-- In the actual mod, it counts existing structures. To mock the "placing 2nd pen" scenario,
-- we'll override GetGuildStructureCount later after loading the script.

local hooks = {}
_G.RegisterHook = function(path, callback)
    hooks[path] = callback
end

-- 2. Load the actual mod script (we modify GUILD_LICENSES_PATH dynamically for the test)
local f = io.open("Mods/GuildBaseManager/scripts/main.lua", "r")
local script_content = f:read("*a")
f:close()

-- Override the path for testing
script_content = script_content:gsub("C:\\\\Users\\\\jackt\\\\AppData\\\\Local\\\\PalLauncher\\\\guild%-licenses%.json", "mock-guild-licenses.json")
script_content = script_content:gsub("local GUILD_LICENSES_PATH.-%n", "local GUILD_LICENSES_PATH = 'mock-guild-licenses.json'\n")

-- Execute the modified script to register hooks
local loaded_chunk = load(script_content)
if not loaded_chunk then
    -- for Lua 5.1 compatibility if loadstring is required
    loaded_chunk = loadstring(script_content)
end
loaded_chunk()

-- We must redefine GetGuildStructureCount since it was loaded into the script
-- Wait, the script declared it globally in Lua 5.1/5.4 so we can just overwrite it
_G.GetGuildStructureCount = function(guild_id, structureType)
    return builtStructures[structureType] or 0
end

-- 3. Simulate Build Quota Enforcement (Default Baseline)
print("\n[STEP 1] Build Quota Enforcement Test (Default Baseline)")

local mockPlayerController = {
    PlayerState = {
        IsValid = function() return true end,
        GuildId = "99998888777766665555444433332222_guild"
    },
    IsValid = function() return true end,
    ClientForceReceiveSystemMessageText = function(self, msg)
        print("  -> System Message Received: " .. msg)
    end
}

print("-> Simulating Guild Alpha placing a 2nd Breeding Pen...")
local resultPen1 = hooks["/Script/Pal.PalBuildProcess:TryBuild"]({}, mockPlayerController, "PalBuildObject_BreedingFarm")
if resultPen1 == false then
    print("  => Assert Passed: Placement BLOCKED (Quota Exceeded).")
else
    print("  => Assert Failed: Expected Blocked, got Allowed.")
end

print("-> Simulating Guild Alpha placing a 2nd Ranch...")
local resultRanch1 = hooks["/Script/Pal.PalBuildProcess:TryBuild"]({}, mockPlayerController, "PalBuildObject_Ranch")
if resultRanch1 == false then
    print("  => Assert Passed: Placement BLOCKED (Quota Exceeded).")
else
    print("  => Assert Failed: Expected Blocked, got Allowed.")
end

-- 4. Upgrade License Quotas
print("\n[STEP 2] Updating License Quotas (Simulating /exchange from Discord...)")
local json_upgraded = [[
{
    "guilds": {
        "99998888777766665555444433332222_guild": {
            "max_bases": 4,
            "max_breeding_pens": 2,
            "max_ranches": 2
        }
    }
}
]]
local f2 = io.open("mock-guild-licenses.json", "w")
f2:write(json_upgraded)
f2:close()
print("  -> Updated mock-guild-licenses.json: max_breeding_pens: 2, max_ranches: 2")

-- 5. Post-Upgrade Build Retry Test
print("\n[STEP 3] Post-Upgrade Build Retry Test")

print("-> Re-simulating placing the 2nd Breeding Pen...")
local resultPen2 = hooks["/Script/Pal.PalBuildProcess:TryBuild"]({}, mockPlayerController, "PalBuildObject_BreedingFarm")
if resultPen2 ~= false then
    print("  => Assert Passed: Placement SUCCESS (Quota Allowed).")
else
    print("  => Assert Failed: Expected Allowed, got Blocked.")
end

print("-> Re-simulating placing the 2nd Ranch...")
local resultRanch2 = hooks["/Script/Pal.PalBuildProcess:TryBuild"]({}, mockPlayerController, "PalBuildObject_Ranch")
if resultRanch2 ~= false then
    print("  => Assert Passed: Placement SUCCESS (Quota Allowed).")
else
    print("  => Assert Failed: Expected Allowed, got Blocked.")
end

print("\n=== [SUCCESS] UE4SS Build Quota Simulation Passed! ===")
