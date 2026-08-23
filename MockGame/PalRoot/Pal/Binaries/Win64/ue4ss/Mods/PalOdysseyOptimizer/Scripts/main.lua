-- ============================================================================
-- PalOdysseyOptimizer - Main Coordinator
-- Unified Ultimate Performance, Networking, Input & Stability Suite
-- ============================================================================

local Config = require("config")
local InputModule = require("input")
local NetworkModule = require("network")
local GraphicsModule = require("graphics")
local MemoryModule = require("memory")
local ServerModule = require("server")

print("==========================================================")
print("  PalOdyssey Ultimate Optimization Suite v1.0.0 Starting  ")
print("==========================================================")

-- Load configuration
local cfg = Config.load()

-- Initialize each subsystem
pcall(InputModule.apply, cfg.rawInput)
pcall(NetworkModule.apply, cfg.network)
pcall(GraphicsModule.apply, cfg.graphics)
pcall(MemoryModule.apply, cfg.memory)
pcall(ServerModule.apply, cfg.server)

-- Optional: Register with DarnMenu for in-game configuration
local function registerDarnMenuCategory()
    local ok, DarnMenu = pcall(require, "DarnMenu")
    if ok and DarnMenu and type(DarnMenu.registerCategory) == "function" then
        DarnMenu.registerCategory({
            id = "palodyssey_optimizer",
            title = "PalOdyssey Performance",
            description = "Raw Input, Network Latency, FPS, CPU, RAM & Server Tuning"
        })
        print("[PalOdysseyOptimizer] Registered with DarnMenu in-game UI suite.")
    end
end

ExecuteWithDelay(5000, registerDarnMenuCategory)

print("[PalOdysseyOptimizer] All Performance & Networking subsystems successfully initialized.")
