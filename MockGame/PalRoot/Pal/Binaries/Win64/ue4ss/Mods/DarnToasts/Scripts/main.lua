-- ============================================================================
--  DarnToasts -- shared toast library for UE4SS Lua mods. This main.lua is just
--  a breadcrumb: the library does nothing on its own. Consumer mods load it via
--  require after adding this package's Scripts dir to package.path:
--
--      local SDIR = (debug.getinfo(1, "S").source:gsub("^@", ""):gsub("[^/\\]+$", ""))
--      package.path = SDIR .. "../../DarnToasts/Scripts/?.lua;" .. package.path
--      local Toast = require("ToastLib").new("MyModName", { yOffset = 0 })
--      Toast.notify("hello!")                     -- default color
--      Toast.notify("saved", 0.45, 1.0, 0.55)     -- custom accent {r,g,b}
--      -- yOffset = your default lane (px below other mods' toasts); each
--      -- notify() is its own toast -- stacking/unravel/mute all handled here.
--
--  USER CONFIG (position / style / mute, survives mod updates):
--  copy Scripts/ToastLib_config_example.lua to
--      Mods/NativeMods/UE4SS/Mods/shared/ToastLib_config.lua
--  and edit. The packaged example is overwritten on every update -- your copy
--  in shared/ is not.
-- ============================================================================
local Darn = require("darn")
print("[DarnToasts] toast library present (require via ToastLib) -- v" .. Darn.version() .. "\n")

-- ============================================================================
-- THE TOAST TEST PARADE (Maiq, 2026-08-10: "give me a keybind... to cause N
-- toasts to show up staggered so I can test the full breadth of the toasts in
-- the current configuration"). F9 fires five DISTINCT toasts 450ms apart --
-- distinct on purpose: identical text is merged by the repeat-collapse, which
-- is why spamming one message redraws a single toast -- then a sticky progress
-- panel that updates in place and ravels shut. Registered HERE, in DarnToasts'
-- own state, so one press is one parade (a keybind inside ToastLib would fire
-- once per consumer mod). This also gives DarnToasts the channel instance the
-- style-preview toast speaks through.
-- ============================================================================
local okT, Toast = pcall(function() return require("ToastLib").new("DarnToasts") end)
if okT and Toast then
    -- Toast.notify builds and mutates widgets. Off the game thread that races the game's own
    -- per-frame layout pass -- the mechanism behind a 20-instance CTD family (2026-08-12,
    -- crash ledger). A bench tool is not a reason to make native UI calls from a timer thread.
    local function laterOnGameThread(ms, fn)
        if type(_G.ExecuteInGameThreadWithDelay) == "function" then
            if pcall(_G.ExecuteInGameThreadWithDelay, ms, fn) then return end
        end
        ExecuteWithDelay(ms, fn)   -- timer-check: allow last-resort fallback if the loader lacks the game-thread scheduler
    end

    local function parade()
        local msgs = {
            { "Toast test 1 of 5: a short one",                          0.55, 0.85, 1.0 },
            { "Toast test 2 of 5: the accent goes green",                0.45, 1.0,  0.55 },
            { "Toast test 3 of 5: amber, the warning shade",             1.0,  0.75, 0.3 },
            { "Toast test 4 of 5: red, the urgent shade",                1.0,  0.45, 0.4 },
            { "Toast test 5 of 5: a deliberately long line to exercise word wrap "
              .. "-- it should fold onto extra rows at your Wrap setting and hold "
              .. "its place in the stack while doing it",                0.8,  0.6,  1.0 },
        }
        for i, m in ipairs(msgs) do
            laterOnGameThread(1 + (i - 1) * 450, function()
                pcall(function() Toast.notify(m[1], m[2], m[3], m[4]) end)
            end)
        end
        laterOnGameThread(5 * 450 + 300, function()
            pcall(function() Toast.progress("darntoast_test",
                { text = "Test panel", sub = "a sticky progress surface", frac = 0.35 }) end)
        end)
        laterOnGameThread(5 * 450 + 1800, function()
            pcall(function() Toast.progress("darntoast_test",
                { text = "Test panel", sub = "updating in place", frac = 0.8 }) end)
        end)
        laterOnGameThread(5 * 450 + 3300, function()
            pcall(function() Toast.dismiss("darntoast_test") end)
        end)
    end
    -- OPT-IN, AND OFF FOR EVERY PLAYER BY DEFAULT (2026-08-13).
    -- This was registered unconditionally, so every install of DarnToasts had F9 bound to five
    -- toasts reading "Toast test 1 of 5" and a fake progress panel. It is a bench tool built on
    -- request (2026-08-10), not a feature: a player who presses F9 for any other reason gets
    -- debug spam from a mod they installed to make toasts look nicer.
    -- The KEY is configurable too. Hardcoding F9 was a guess about a key nobody verified was
    -- free, and the F-row is heavily contested by other mods and by the game itself.
    -- NESTED, not an early `return`. A bare return here leaves the whole CHUNK, not just this
    -- block -- harmless while this is the last thing in the file, and a silent trap the moment
    -- anything is added below it. Not worth leaving armed to save one indent.
    local PCFG = { testParade = false, testParadeKey = "F9" }
    pcall(function() Darn.overlay(PCFG, "ToastLib_config", print) end)
    if PCFG.testParade == true then
        local keyName = tostring(PCFG.testParadeKey or "F9"):upper()
        local keyObj  = (type(Key) == "table") and Key[keyName] or nil
        if not keyObj then
            print("[DarnToasts] test parade: no such key '" .. keyName .. "' -- not bound\n")
        else
            local okB = pcall(function() RegisterKeyBind(keyObj, parade) end)
            print(okB and ("[DarnToasts] " .. keyName
                           .. " = toast test parade (5 toasts + a sticky)\n")
                      or  "[DarnToasts] test-parade keybind unavailable\n")
        end
    end
end
