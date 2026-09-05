local Performance = {}

local Enabled = false
local Stats = {}
local SessionStartedAt = os.clock()

local function GetStat(name)
    local stat = Stats[name]
    if not stat then
        stat = { Calls = 0, Total = 0, Max = 0, Errors = 0, Count = 0 }
        Stats[name] = stat
    end
    return stat
end

function Performance.Configure(config)
    config = config or {}
    Enabled = config.PerformanceDiagnosticsEnabled == true
end

function Performance.IsEnabled()
    return Enabled
end

function Performance.SetEnabled(enabled)
    Enabled = enabled == true
    if Enabled then SessionStartedAt = os.clock() end
end

function Performance.Reset()
    Stats = {}
    SessionStartedAt = os.clock()
end

function Performance.Start()
    if not Enabled then return nil end
    return os.clock()
end

function Performance.Finish(name, startedAt, succeeded)
    if not Enabled or not startedAt then return end
    local elapsed = math.max(0, os.clock() - startedAt)
    local stat = GetStat(name)
    stat.Calls = stat.Calls + 1
    stat.Total = stat.Total + elapsed
    if elapsed > stat.Max then stat.Max = elapsed end
    if succeeded == false then stat.Errors = stat.Errors + 1 end
end

function Performance.Count(name, amount)
    if not Enabled then return end
    local stat = GetStat(name)
    stat.Count = stat.Count + (tonumber(amount) or 1)
end

function Performance.FormatReport()
    local lines = {
        string.format(
            "[WorldBossAuraSystem][Perf] enabled=%s elapsed=%.1fs",
            tostring(Enabled), math.max(0, os.clock() - SessionStartedAt))
    }
    local names = {}
    for name in pairs(Stats) do names[#names + 1] = name end
    table.sort(names)
    if #names == 0 then
        lines[#lines + 1] = "[WorldBossAuraSystem][Perf] No samples recorded."
    end
    for _, name in ipairs(names) do
        local stat = Stats[name]
        local averageMs = stat.Calls > 0 and (stat.Total * 1000 / stat.Calls) or 0
        lines[#lines + 1] = string.format(
            "[WorldBossAuraSystem][Perf] %s calls=%d avg=%.3fms max=%.3fms errors=%d count=%d",
            name, stat.Calls, averageMs, stat.Max * 1000, stat.Errors, stat.Count)
    end
    return table.concat(lines, "\n")
end

function Performance.PrintReport()
    print(Performance.FormatReport())
end

return Performance
