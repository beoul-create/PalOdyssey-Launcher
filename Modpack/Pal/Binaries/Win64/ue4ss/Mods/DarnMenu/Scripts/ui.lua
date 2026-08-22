-- ============================================================================
--  DarnUI ui.lua -- the shared Darn-family widget kit (require "ui"). Everything
--  visual is built from the game's OWN pieces so it looks native:
--    * buttons  = the ESC menu's own WBP_MenuESC_Button_S blueprint
--    * text     = UMG TextBlocks styled off an existing native TextBlock
--    * layout   = raw UMG CanvasPanel/ScrollBox/SizeBox via StaticConstructObject
--  Nothing is shipped; the game provides its entire look.
--
--  SAFETY CONTRACT (hard-won -- see UI.overlay + the crash ledger). When you
--  inject into a live game menu:
--    * add widgets ONLY to a CanvasPanel (absolute layout -> no reflow);
--    * NEVER RemoveFromParent on a lingering/swept menu (native AV), and NEVER
--      SetVisibility a widget that lives in a native layout container like a
--      VerticalBox (triggers a reflow = a mutation = AV). Collapse only OUR OWN
--      canvas children; the engine frees the rest when it Destructs the menu.
--    * read game state by PROPERTY (UI.get) -- struct OUT-PARAM getters (e.g.
--      GetItemAndNum) can native-WRITE-crash; property reads are safe.
--    * every native touch is UI.alive-gated + pcall'd.
--  UI.overlay() bakes all of this in -- prefer it for new injections.
-- ============================================================================

local UI = {}

-- VENDORED, like darn.lua. Single source: workshop-publish/shared-src/ui.lua; copies are
-- written into each consumer's Scripts/ by tools/sync-shared.js. Edit the source, run the
-- sync -- never edit a mod's copy.
--
-- WHY NOT A DEPENDENCY (decided 2026-07-27): every UE4SS mod runs in its own lua_State and
-- already loaded its OWN instance of this kit, so a shared DarnUI item never gave a shared
-- runtime library -- only a shared FILE, and that file is exactly what let DarnMenu 1.6.3
-- meet DarnUI 1.3.0. Vendored, a mod always runs the kit it shipped with, so the mismatch
-- cannot occur rather than being policed. Cost is 64KB per mod and re-uploading both
-- consumers for a kit fix; they ship in the same wave anyway. It also satisfies README rule
-- 5 (a missing dependency must cost a FEATURE, never the mod) -- a stale DarnUI used to cost
-- the entire menu.
--
-- STAMPED BY THE SYNC, not hand-maintained: sync-shared.js rewrites this line from DarnUI's
-- Info.json. "dev" means an unsynced working copy. ("Keep in sync with X" in a comment is a
-- bug with a delay on it -- this family has been bitten by that twice.)
UI.KIT_VERSION = "1.8.0"

-- OWNERSHIP (2026-07-27, Mikey's rule). The kit draws; it does not decide who owns what.
-- Each mod owns the surfaces it injects and touches nothing another mod placed:
--   * DarnMenu owns the ESC-menu entry button ("Mod Options") and its options page.
--   * Living Arsenal owns its prestige badge and inventory star.
-- UI.ourButtons/UI.isOurs make that enforceable rather than a convention -- the registry is
-- per Lua state, so a mod can only ever recognise ITS OWN widgets, and the click dispatch
-- already ignores anything it did not create. Two vendored copies at different versions
-- therefore cannot fight over each other's widgets; the only shared surfaces are the game's
-- own (see the note on shared/DarnUI_user.lua below).
UI.ourButtons = {}   -- [addr] = true for every button UI.nativeButton created
-- IDENTITY IS NOT AN ADDRESS (virtualbjorn, merged 2026-07-28). UE recycles allocator
-- addresses, and UE4SS hands out a FRESH Lua userdata every time it pushes a UObject into a
-- hook callback -- so neither the address nor wrapper equality is object identity. A newer
-- button at a freed button's address would otherwise inherit the old one's click action.
-- One immutable registration record is shared by global ownership and its action scope:
--   { ref = construction wrapper, addr = address, key = objectKey, epoch = world epoch }
UI.buttonRefs = {}   -- [addr] = the wrapper we held at construction
UI.buttonRegs = {}   -- [addr] = the shared registration record
UI.actionRefs = setmetatable({}, { __mode = "k" })  -- [actions][addr] = construction wrapper
UI.actionRegs = setmetatable({}, { __mode = "k" })  -- [actions][addr] = shared registration

-- explicit `return nil`: falling off the end returns zero values, which breaks any caller
-- that passes this straight into tonumber()/tostring() (there are three such in this file).
local function safe(f) local ok, v = pcall(f); if ok then return v end return nil end

-- ---------------------------------------------------------------------------
-- GUARDED GAME-THREAD SCHEDULER  (virtualbjorn, merged 2026-07-28)
-- ---------------------------------------------------------------------------
-- UE4SS ExecuteWithDelay callbacks are asynchronous; they are NOT permission to touch UObjects.
-- The failure this prevents is one we hit repeatedly: a timer fires after the world it captured
-- is gone, and the callback dereferences a freed object. pcall does not catch that -- it is a
-- native access violation.
--
-- So: keep the function (and everything it closes over) in this Lua registry, and let the native
-- delayed closure capture only a primitive task id + epoch. Every dispatch is re-checked ON THE
-- GAME THREAD, after map-pre has had a chance to invalidate the epoch. A stale task cannot run;
-- it is dropped.
--
--   UI.gameThread(fn[, guard]) -> handle | nil, err   run on the game thread, next tick
--   UI.defer(ms, fn[, guard])  -> handle | nil, err   ...after a delay
--   UI.schedule{ ms=, fn=, ... }                      ...naming a job class (survive/release/chain)
--   UI.cancelTask(handle)                             cancel one
--   UI.newToken() / UI.cancelToken(token)             cancel a whole group
--   UI.onWorldPre(fn) / UI.onWorldPost(fn)            lifecycle hooks for your own registries
--   UI.worldEpoch() / UI.runtimeStats()               introspection
--
-- A guard is either a predicate (must explicitly return true, evaluated on the game thread) or a
-- token from UI.newToken(). Tokens bind their tasks to the creation epoch and release queued
-- closures immediately when cancelled.
local runtime = {
  epoch = 1,
  worldGone = false,
  nextTask = 0,
  tasks = {},
  preListeners = {},
  postListeners = {},
  bootAt = os.time(),   -- when this kit instance loaded; walks stand down for a while after
  restoredAt = 0,       -- last restoreWorld() (LoadMap post-hook); walks stand down after too
  -- THE JOB TABLE (see the block below UI.drainJobs). Empty and unused while
  -- UI._jobsEnabled is false, which is the shipped default.
  jobs = {},            -- [taskId] = { id, epoch, at, seq, chain }
  jobSeq = 0,           -- schedule order: the documented tiebreak between co-due jobs
  jobNow = 0,           -- kit time in ms; advanced ONLY by drainJobs
  jobOrigin = nil,      -- the driver's clock at the first drain; kit time is (now - origin)
  jobDt = 0,            -- ms between the last two drains, for a driver that wants a frame delta
}

local function nextId()
  runtime.nextTask = runtime.nextTask + 1
  if runtime.nextTask > 2147483640 then runtime.nextTask = 1 end
  while runtime.tasks[runtime.nextTask] do runtime.nextTask = runtime.nextTask + 1 end
  return runtime.nextTask
end

local function unlinkTask(task, cancelled)
  if not task then return end
  if task.handle then
    task.handle.cancelled = cancelled == true
    task.handle.done = cancelled ~= true
  end
  if task.token and task.token.tasks then task.token.tasks[task.id] = nil end
end

-- A DROPPED TASK MUST RELEASE ITS LATCH, or a feature dies for the session.
--
-- The pattern is everywhere in this family: raise a "busy"/"armed"/"pumping" flag, schedule
-- the work, and lower the flag inside the timer body. That is correct only while the timer is
-- guaranteed to fire. Every path that discards a task instead -- a cancel, a world teardown, a
-- guard that vetoes on the game thread -- leaves the flag raised with nothing left to lower it,
-- and the loop it guards never runs again. No error, no log line.
--
-- So a task may carry a release hook, and it runs exactly once, on discard only. When the body
-- DOES run the body owns the latch and the hook is consumed without firing.
local function releaseTask(task)
  if type(task) ~= "table" or task.released then return end
  task.released = true
  if type(task.release) == "function" then pcall(task.release) end
end

-- Refusal before a task record exists: the caller still asked for the latch to be lowered.
local function releaseOpts(opts)
  if type(opts) == "table" and type(opts.release) == "function" then pcall(opts.release) end
end

-- `survive` is opt-in and ONLY reached by a task that asked for it (see registerTask). For
-- everything else this is the same predicate it has always been.
local function guardAllows(guard, epoch, survive)
  if not survive and (runtime.worldGone or runtime.epoch ~= epoch) then return false end
  if guard == nil then return true end
  if type(guard) == "function" then
    local ok, allowed = pcall(guard)
    return ok and allowed == true
  end
  if type(guard) == "table" then
    if guard.cancelled == true then return false end
    -- A survivor is re-homed onto the new epoch by invalidateWorld, so an epoch-bound token
    -- would veto it on the first map change; cancellation still applies.
    if survive then return true end
    return guard.epoch == nil or guard.epoch == runtime.epoch
  end
  return guard == true
end

local function dispatchTask(id, epoch)
  local task = runtime.tasks[id]
  if not task then return end
  if task.epoch ~= epoch and not task.survive then return end
  runtime.tasks[id] = nil
  runtime.jobs[id] = nil
  unlinkTask(task, false)
  if not guardAllows(task.guard, epoch, task.survive) then releaseTask(task); return end
  -- CHECK IT IS CALLABLE BEFORE CALLING IT. Handing a non-function to UE4SS's game-action pump
  -- is how the process-wide stall starts: get_function_ref throws outside the TRY and leaves
  -- the shared m_is_currently_executing_game_action latched true, after which no Lua mod's
  -- queued actions run again. Registration already type-checks; this is the second gate, on
  -- the value as it stands at dispatch, and it costs one type().
  if type(task.fn) ~= "function" then releaseTask(task); return end
  task.released = true      -- the body owns the latch from here; the hook must not also fire
  pcall(task.fn, task.handle)
end

-- opts (all optional, all nil for every caller that passes three arguments):
--   survive = true   the task outlives a world change instead of being dropped with it
--   release = fn     run once if the task is ever DISCARDED rather than run
--   chain   = name   at most one task of this chain per drain (job table only; in the timer
--                    engine each task is its own real delay and already gets its own frame)
local function registerTask(fn, guard, opts)
  if type(fn) ~= "function" then return nil, "fn must be a function" end
  local survive = type(opts) == "table" and opts.survive == true
  if runtime.worldGone and not survive then return nil, "world unavailable" end
  if type(guard) == "table"
      and (guard.cancelled == true or (guard.epoch ~= nil and guard.epoch ~= runtime.epoch)) then
    return nil, "guard unavailable"
  end
  local id = nextId()
  local handle = { id = id, epoch = runtime.epoch, cancelled = false }
  local token = type(guard) == "table" and guard or nil
  local task = {
    id = id, epoch = runtime.epoch, fn = fn, guard = guard,
    token = token, handle = handle,
  }
  if type(opts) == "table" then
    task.survive = survive or nil
    if type(opts.release) == "function" then task.release = opts.release end
    if opts.chain ~= nil then task.chain = opts.chain end
  end
  runtime.tasks[id] = task
  if token then
    token.tasks = token.tasks or {}
    token.tasks[id] = true
  end
  return task
end

-- ---------------------------------------------------------------------------
-- THE JOB TABLE -- one drain instead of a closure per timer
-- ---------------------------------------------------------------------------
-- WHY IT EXISTS -- read in the UE4SS source we actually run (c838a8ac), not inferred:
--
--   1. ExecuteWithDelay LEAKS A REGISTRY SLOT PER FIRE. LuaMod::process_delayed_actions
--      (LuaMod.cpp:7110-7147) erases each fired async action with remove_if and never calls
--      luaL_unref -- none of that file's unref sites is on the async path. A self-rescheduling
--      async timer therefore retains one registry slot per fire for the life of the process.
--      The GAME-THREAD path does unref correctly (LuaMod.cpp:3973); only the async one leaks.
--   2. THE FAILURE IS SILENT AND IT IS NOT OURS ALONE. get_function_ref throws when a stored
--      ref is not a function (LuaMadeSimple.cpp:253-259). On the game-thread path that call
--      sits OUTSIDE the TRY (LuaMod.cpp:3912-3917): the flag is set true, the throw escapes,
--      and the flag is never cleared. It is `static inline` (LuaMod.hpp:180) -- ONE flag for
--      every Lua mod in the process -- and the pump skips every action while it is set
--      (LuaMod.cpp:3907). So one bad ref latches it and every queued game-thread action in
--      EVERY mod stops, with nothing in any log.
--
-- Both point the same way: stop minting refs per timer. Jobs live in a plain Lua table, and
-- ONE driver drains them on the game thread -- LoopInGameThreadAfterFrames(1, drain)
-- (LuaMod.cpp:4684), registered once at load, one registry ref for the whole session, no
-- per-fire registry traffic, no widget and no world required.
--
-- THE DRIVER IS NOT WIRED HERE, which is exactly why UI._jobsEnabled is false: with the switch
-- off nothing is ever scheduled into this table and the engine above behaves as it always has.
-- Turning it on without a driver would leave every timer in every consumer armed and never
-- fired, so the switch and the driver land together or not at all.
--
-- NOTHING IN THIS TABLE MAY EVER ROUTE THROUGH ExecuteWithDelay -- not as a fallback, not as a
-- retry. That is the leaking path, and a leak inside the thing built to stop the leak would be
-- invisible.
--
--   UI.schedule{ ms=, fn=, guard=, survive=, release=, chain= } -> handle | nil, err
--   UI.drainJobs([nowMs][, budget]) -> ran, more
--   UI.jobStats()
--
-- The contract, clause by clause, each one paid for by a real call site:
--   * REMOVE BEFORE INVOKE. Callbacks legitimately reschedule themselves; invoking first and
--     removing after either drops the new job or runs the old one twice.
--   * A JOB SCHEDULED DURING A DRAIN WAITS FOR THE NEXT DRAIN. Otherwise a zero-delay job that
--     re-arms itself spins inside one drain and hangs the frame.
--   * ORDER IS DUE TIME FIRST, SCHEDULE ORDER SECOND -- never pairs() order, which is not
--     stable. A toast dismiss and a toast update can land in the same drain, and running them
--     out of order resurrects a dismissing sticky and leaves a panel on screen for good.
--   * SOFT BUDGET. A drain stops when the caller's budget is spent and reports that work
--     remains; the rest waits for the next one. No drain runs unbounded.
--   * NO CATCH-UP. A job that re-arms itself computes its next due time from the time it ran,
--     so a hitch or a long pause costs fires rather than producing a burst of them.
--   * SURVIVE IS OPT-IN. The default is what the task registry has always done: a world change
--     drops everything armed. A few loops must outlive it -- they re-arm WHILE the world is
--     gone so the loop heals itself when it comes back -- and those pass survive = true.
--   * RELEASE runs on every path that discards a job and never when the body runs. See
--     releaseTask: a raised latch with no body left to lower it is a dead feature.
--   * CHAIN caps a named chain at one job per drain, independently of the budget. A page built
--     in dozens of phases spends one phase per frame on purpose; a drain that ran the whole
--     chain back-to-back would restore the multi-second freeze the phasing exists to cure.
--     With a per-frame driver, one drain IS one frame, so a chain is one phase per frame.
--   * ms = 0 NEVER RUNS INSIDE THE DRAIN THAT SCHEDULED IT. Under a per-frame driver that is a
--     real frame boundary, which is what call sites currently buy with a 1ms delay -- 0 used to
--     mean ExecuteInGameThread, which could land inside the same tick. Those call sites keep
--     their 1ms and are none the worse for it; new code can just ask for 0.
-- WIRED 2026-08-12. The driver is armed at the bottom of this file (search "JOB DRIVER"), so
-- the switch and the driver land together exactly as the note above requires. Measured on the
-- live client before enabling: LoopInGameThreadAfterFrames(1, fn) registered true, fired every
-- frame across 5,636 frames at ~60fps, and its callback slot cost <=1ms. The switch stays a
-- switch -- if the driver fails to arm, arming code sets this back to false and the legacy
-- engine carries every timer exactly as before.
UI._jobsEnabled = false

-- WHERE THE CLOCK COMES FROM when the driver does not supply one. The driver is registered as
-- LoopInGameThreadAfterFrames(1, drain) and C++ calls it with NO arguments, so the drain has to
-- be able to source its own time. os.clock() is what the kit already uses for short-interval
-- work (see texLoader's ttl); it is process CPU time rather than wall time, which is close
-- enough for scheduling at this granularity and is monotonic, which is the property that
-- matters here. A driver holding a better clock passes it in and this is never consulted.
local function clockMs() return os.clock() * 1000 end

-- Default cap on how many jobs one drain will run. A caller-supplied budget replaces it; this
-- exists so a drain called with no budget at all still cannot run away with the frame.
local JOB_BUDGET = 32

local function budgetAllows(budget, ran)
  local kind = type(budget)
  if kind == "number" then return ran < budget end
  -- A predicate is how a real FRAME budget gets expressed without this file reading a clock:
  -- the driver closes over its own deadline and answers true while there is time left.
  if kind == "function" then
    local ok, allowed = pcall(budget)
    return ok and allowed == true
  end
  return ran < JOB_BUDGET
end

local function scheduleJob(ms, fn, guard, opts)
  local task, err = registerTask(fn, guard, opts)
  if not task then releaseOpts(opts); return nil, err end
  runtime.jobSeq = runtime.jobSeq + 1
  runtime.jobs[task.id] = {
    id = task.id,
    epoch = task.epoch,
    seq = runtime.jobSeq,
    -- Due time is measured from the drain's own clock, so a job that re-arms itself from
    -- inside a drain lands at (the time it ran + its period). Never an accumulating +=.
    at = runtime.jobNow + math.max(0, tonumber(ms) or 0),
    chain = task.chain,
  }
  return task.handle
end

-- The full-featured entry point. UI.defer/UI.gameThread stay the three-argument seam everything
-- already calls; this is what a call site uses when it needs a class the plain seam cannot name.
-- It works in BOTH engines: survive and release are properties of the task record, which both
-- paths share, and chain is inherent in the timer engine (a real delay already yields a frame).
function UI.schedule(opts)
  if type(opts) ~= "table" then return nil, "opts must be a table" end
  local ms = tonumber(opts.ms) or 0
  if UI._jobsEnabled == true then return scheduleJob(ms, opts.fn, opts.guard, opts) end
  return UI.defer(ms, opts.fn, opts.guard, opts)
end

-- DRAIN. nowMs is an OPTIONAL argument, and both halves of that matter: the driver is called
-- from C++ with no arguments, so the drain sources its own time when it is not given one; and
-- a test can hand in any time it likes, which is what makes the whole scheduler provable with
-- no game attached. Any monotonic millisecond source will do -- the first drain becomes the
-- origin, so a delay armed before it still waits its full delay instead of firing at once.
--
-- Returns (ran, more): how many jobs ran, and whether due work was left behind.
function UI.drainJobs(nowMs, budget)
  -- THE CLOCK ADVANCES EVEN ON AN EMPTY DRAIN, and it has to. Due times are absolute kit
  -- time, so a clock that only moved while jobs existed would freeze at the moment the table
  -- emptied -- and the next job armed after a quiet stretch would be scheduled against that
  -- stale reading and fire instantly instead of after its delay. Three lines of arithmetic is
  -- the price; the collect/sort below is the part the fast path actually skips.
  local t = tonumber(nowMs)
  if t == nil then t = clockMs() end
  if t then
    if runtime.jobOrigin == nil then runtime.jobOrigin = t end
    local kit = t - runtime.jobOrigin
    -- Monotonic by construction. A clock that jumps backwards stalls the table for a moment
    -- rather than re-firing everything that already ran. dt is what a per-frame driver would
    -- otherwise have to work out for itself.
    if kit > runtime.jobNow then
      runtime.jobDt = kit - runtime.jobNow
      runtime.jobNow = kit
    else
      runtime.jobDt = 0
    end
  end

  local jobs = runtime.jobs
  -- THE EVERY-FRAME FAST PATH. This runs on every tick of every consumer; with nothing armed
  -- it must cost one table probe and a return.
  if next(jobs) == nil then return 0, false end
  local now = runtime.jobNow

  -- Anything scheduled from here on gets a seq above this line and is therefore NOT eligible
  -- for this drain -- including a job that re-arms itself while we are inside it.
  local ceiling = runtime.jobSeq
  local due = {}
  for _, job in pairs(jobs) do
    if job.at <= now and job.seq <= ceiling then due[#due + 1] = job end
  end
  if #due == 0 then return 0, false end
  -- Total order, so table.sort (which is not stable) still gives one defined answer.
  table.sort(due, function(a, b)
    if a.at ~= b.at then return a.at < b.at end
    return a.seq < b.seq
  end)

  local ran, more, chainUsed = 0, false, nil
  for i = 1, #due do
    local job = due[i]
    if jobs[job.id] ~= job then
      -- Cancelled or re-scheduled by an earlier job in THIS drain. A cancelled job must never
      -- fire, and this is the check that holds when the cancel comes from inside the drain.
    elseif job.chain ~= nil and chainUsed ~= nil and chainUsed[job.chain] then
      more = true                       -- one per chain per drain; the rest keep their place
    elseif not budgetAllows(budget, ran) then
      more = true                       -- out of budget: leave the remainder armed
      break
    else
      if job.chain ~= nil then
        chainUsed = chainUsed or {}
        chainUsed[job.chain] = true
      end
      jobs[job.id] = nil                -- REMOVE BEFORE INVOKE
      ran = ran + 1
      -- One throwing job must not stop the others. dispatchTask already pcalls the body; this
      -- second pcall covers the dispatch itself so nothing in the loop can be skipped.
      pcall(dispatchTask, job.id, job.epoch)
    end
  end
  return ran, more
end

function UI.jobStats()
  local n, soonest = 0, nil
  for _, job in pairs(runtime.jobs) do
    n = n + 1
    if soonest == nil or job.at < soonest then soonest = job.at end
  end
  return { enabled = UI._jobsEnabled == true, pending = n, nextDue = soonest,
           now = runtime.jobNow, dt = runtime.jobDt or 0 }
end

function UI.worldEpoch() return runtime.epoch end

function UI.newToken()
  return { epoch = runtime.epoch, cancelled = false, tasks = {} }
end

function UI.cancelTask(handle)
  if type(handle) ~= "table" then return false end
  handle.cancelled = true
  local task = runtime.tasks[handle.id]
  if not task or task.epoch ~= handle.epoch then return false end
  runtime.tasks[handle.id] = nil
  runtime.jobs[handle.id] = nil
  unlinkTask(task, true)
  releaseTask(task)
  return true
end

function UI.cancelToken(token)
  if type(token) ~= "table" then return false end
  token.cancelled = true
  local ids = {}
  for id in pairs(token.tasks or {}) do ids[#ids + 1] = id end
  for _, id in ipairs(ids) do
    local task = runtime.tasks[id]
    runtime.tasks[id] = nil
    runtime.jobs[id] = nil
    unlinkTask(task, true)
    releaseTask(task)
  end
  token.tasks = {}
  return true
end

-- timer-check: seam begin -- the sanctioned raw use of the UE4SS timer primitives is HERE and
-- nowhere else. Everything above this seam is engine-agnostic; everything below it is the one
-- implementation allowed to touch ExecuteWithDelay / ExecuteInGameThread directly.
function UI.gameThread(fn, guard, opts)
  if UI._jobsEnabled == true then return scheduleJob(0, fn, guard, opts) end
  local task, err = registerTask(fn, guard, opts)
  if not task then releaseOpts(opts); return nil, err end
  local execute = _G.ExecuteInGameThread
  if type(execute) ~= "function" then
    runtime.tasks[task.id] = nil
    unlinkTask(task, true)
    releaseTask(task)
    return nil, "ExecuteInGameThread unavailable"
  end
  local id, epoch = task.id, task.epoch
  local ok, callErr = pcall(execute, function() dispatchTask(id, epoch) end)
  if not ok then
    runtime.tasks[id] = nil
    unlinkTask(task, true)
    releaseTask(task)
    return nil, tostring(callErr)
  end
  return task.handle
end

function UI.defer(ms, fn, guard, opts)
  ms = tonumber(ms) or 0
  -- With the job table on, ms <= 0 is a job due right now rather than a hop through
  -- ExecuteInGameThread; either way it runs on the game thread at the next opportunity.
  if UI._jobsEnabled == true then return scheduleJob(ms, fn, guard, opts) end
  if ms <= 0 then return UI.gameThread(fn, guard, opts) end
  local task, err = registerTask(fn, guard, opts)
  if not task then releaseOpts(opts); return nil, err end
  local id, epoch = task.id, task.epoch
  local survive = task.survive == true
  local ok, callErr
  if type(_G.ExecuteInGameThreadWithDelay) == "function" then
    ok, callErr = pcall(_G.ExecuteInGameThreadWithDelay, ms, function()
      dispatchTask(id, epoch)
    end)
  elseif type(_G.ExecuteWithDelay) == "function" and type(_G.ExecuteInGameThread) == "function" then
    -- The async callback performs no UObject work and closes over primitives only.
    ok, callErr = pcall(_G.ExecuteWithDelay, ms, function()
      -- A survivor is re-homed onto the new epoch by invalidateWorld and is meant to fire while
      -- the world is gone; every other task is dropped here, as it always has been.
      if not survive and (runtime.worldGone or runtime.epoch ~= epoch) then return end
      if not runtime.tasks[id] then return end
      pcall(_G.ExecuteInGameThread, function() dispatchTask(id, epoch) end)
    end)
  else
    ok, callErr = false, "no delayed game-thread scheduler available"
  end
  if not ok then
    runtime.tasks[id] = nil
    unlinkTask(task, true)
    releaseTask(task)
    return nil, tostring(callErr)
  end
  return task.handle
end
-- timer-check: seam end

function UI.runtimeStats()
  local n = 0
  for _ in pairs(runtime.tasks) do n = n + 1 end
  return { epoch = runtime.epoch, worldGone = runtime.worldGone, tasks = n }
end

local function addRuntimeListener(bucket, fn)
  if type(fn) ~= "function" then return function() end end
  local entry = { fn = fn, active = true }
  bucket[#bucket + 1] = entry
  return function() entry.active = false; entry.fn = nil end
end

-- Public lifecycle subscriptions for consumers that own additional Lua registries.
-- Pre listeners must perform reference/metadata cleanup ONLY: no UObject calls.
function UI.onWorldPre(fn) return addRuntimeListener(runtime.preListeners, fn) end
function UI.onWorldPost(fn) return addRuntimeListener(runtime.postListeners, fn) end

local function notifyRuntimeListeners(bucket)
  for _, entry in ipairs(bucket) do
    if entry.active and entry.fn then pcall(entry.fn) end
  end
end

local function invalidateWorld()
  if runtime.worldGone then return end
  runtime.worldGone = true
  runtime.epoch = runtime.epoch + 1
  local old, oldJobs = runtime.tasks, runtime.jobs
  runtime.tasks, runtime.jobs = {}, {}
  for id, task in pairs(old) do
    if task.survive then
      -- OPT-IN SURVIVORS. A handful of loops re-arm themselves WHILE the world is gone so they
      -- heal when it returns; dropping them here is what forces those call sites to schedule
      -- raw. Re-home the record (and its job, and its handle) onto the new epoch so every
      -- epoch comparison downstream still means "current".
      task.epoch = runtime.epoch
      if task.handle then task.handle.epoch = runtime.epoch end
      runtime.tasks[id] = task
      local job = oldJobs[id]
      if job then
        job.epoch = runtime.epoch
        runtime.jobs[id] = job
      end
    else
      unlinkTask(task, true)
      releaseTask(task)
    end
  end
  -- Listeners are contractually Lua-reference cleanup only: no UObject calls here.
  notifyRuntimeListeners(runtime.preListeners)
  -- Last-resort ownership sweep. Stale action tables held by direct nativeButton consumers
  -- stay unauthorized because BOTH per-scope registries are replaced as well.
  UI.ourButtons, UI.buttonRefs, UI.buttonRegs = {}, {}, {}
  UI.actionRefs = setmetatable({}, { __mode = "k" })
  UI.actionRegs = setmetatable({}, { __mode = "k" })
end

local function restoreWorld()
  local wasGone = runtime.worldGone
  runtime.worldGone = false
  runtime.restoredAt = os.time()
  if wasGone then notifyRuntimeListeners(runtime.postListeners) end
end

-- MAY A TIMER WALK ENGINE OBJECTS RIGHT NOW? (2026-08-03, two boot CTDs in a row.)
--
-- The epoch-settle discipline only detects epoch CHANGES, and restoreWorld does not bump the
-- epoch -- so on a FRESH BOOT the settle counter runs off ticks that start immediately, and the
-- adopt poll's FindAllOf walk began ~8s after LoadMap-post while the first world was still
-- streaming actors in. Sentinel reads (0xffffffffffffffff) through every pcall/IsValid gate;
-- crumbs at 19:41 named the walk both times. LoadMap-post means the MAP finished loading, not
-- that streaming finished.
--
-- So walks also wait out two wall clocks: 60s from kit load (a fresh boot cannot have anything
-- to adopt that NotifyOnNewObject/Construct will not deliver -- no page predates the mod), and
-- 30s after every restoreWorld (a server join keeps streaming well past its post-hook). A mod
-- hot-reloaded mid-session pays the 60s once; the poll is a safety net, not a hot path.
function UI.walkSafe()
  if runtime.worldGone then return false end
  local now = os.time()
  if now - runtime.bootAt < 60 then return false end
  if runtime.restoredAt > 0 and now - runtime.restoredAt < 30 then return false end
  return true
end


-- ---------------------------------------------------------------------------
-- USER CONFIG (shared/DarnUI_user.lua) -- kit-wide limits players can tune.
--
-- READ HERE, NOT IN main.lua. Each consuming mod runs in its OWN Lua state and loads its
-- OWN copy of this file (darn.lua loadfiles it by path), so DarnUI's main.lua cannot hand
-- values to DarnMenu's instance -- they never share a table. The config therefore has to be
-- read by whoever is actually using it: this file.
--
-- Re-read on every access, not cached: the values are consulted when a widget is BUILT
-- (a dropdown opens), so a fresh read makes an Apply take effect at the next open with no
-- relaunch and no watcher. The file is tiny and this is not a hot path.
--
-- Type-guarded and clamped. A user file is untrusted input -- a string where a number
-- belongs, or cap = 0, must degrade to the default rather than break every dropdown in
-- every mod that consumes this kit.
local CONFIG_DEFAULTS = { suggestCap = 40, suggestRows = 8, suggestPollMs = 200 }
local CONFIG_LIMITS = { suggestCap = { 5, 60 }, suggestRows = { 3, 30 }, suggestPollMs = { 80, 2000 } }
local CONFIG_PATH = (debug.getinfo(1, "S").source:gsub("^@", ""):gsub("[^/\\]+$", ""))
  .. "../../shared/DarnUI_user.lua"

function UI.config(key)
  local fallback = CONFIG_DEFAULTS[key]
  local chunk = safe(function() return loadfile(CONFIG_PATH) end)
  if not chunk then return fallback end
  local ok, t = pcall(chunk)
  if not ok or type(t) ~= "table" then return fallback end
  local v = t[key]
  if type(v) ~= "number" or v ~= v then return fallback end        -- nil, string, NaN
  local lim = CONFIG_LIMITS[key]
  if lim then v = math.max(lim[1], math.min(lim[2], v)) end
  return math.floor(v)
end
function UI.alive(o)
  if o == nil or type(o) ~= "userdata" then return false end
  local ok, v = pcall(function()
    if type(o.is_valid) == "function" and not o:is_valid() then return false end
    if type(o.GetAddress) == "function" then
      local a = o:GetAddress()
      if not a or (type(a) == "number" and a <= 0x10000) then return false end
    end
    return o:IsValid()
  end)
  return ok and v == true
end
function UI.addr(o)
  if not o or type(o) ~= "userdata" then return nil end
  local ok, a = pcall(function()
    if type(o.is_valid) == "function" and not o:is_valid() then return nil end
    if type(o.GetAddress) == "function" then
      local addr = o:GetAddress()
      if not addr or (type(addr) == "number" and addr <= 0x10000) then return nil end
      return addr
    end
    return nil
  end)
  return ok and a or nil
end

-- Freeze native identity while the UObject is known live. GetAddress alone is insufficient
-- (UE recycles addresses); Lua userdata equality is also insufficient (each hook push creates a
-- fresh wrapper). A full name includes class, outer path and Unreal's generated object number.
function UI.objectKey(o, knownAddress)
  if not UI.alive(o) then return nil end
  local address = knownAddress or UI.addr(o)
  if address == nil then return nil end
  local fullName = safe(function() return o:GetFullName() end)
  if type(fullName) ~= "string" or fullName == "" then return nil end
  return tostring(address) .. "\0" .. fullName
end

local function registrationMatches(registration, widget, knownAddress)
  if type(registration) ~= "table" or registration.epoch ~= runtime.epoch
      or not UI.alive(widget) then return false end
  local address = knownAddress or UI.addr(widget)
  if address == nil or address ~= registration.addr then return false end
  -- Revalidate the retained construction wrapper too. During allocator reuse it may briefly
  -- report IsValid while resolving to a different object.
  local retained = registration.ref
  if not UI.alive(retained) or UI.addr(retained) ~= address
      or UI.objectKey(retained, address) ~= registration.key then return false end
  return UI.objectKey(widget, address) == registration.key
end

function UI.actionRegistration(actions, address)
  local registrations = type(actions) == "table" and UI.actionRegs[actions] or nil
  return registrations and registrations[address] or nil
end

function UI.registrationIsCurrent(registration, address)
  return type(registration) == "table"
    and UI.buttonRegs[address] == registration
    and registrationMatches(registration, registration.ref, address)
end

-- safe nested PROPERTY read: UI.get(obj, "a.b.c") -> value or nil. Each hop is
-- pcall'd, so a missing or freed link returns nil instead of throwing. Use this
-- for reading game state instead of hand-written pcall chains. NOTE: property
-- reads only -- never route a struct OUT-PARAM getter through here (those can
-- native-crash; see the SAFETY CONTRACT).
function UI.get(obj, path)
  local cur = obj
  for key in path:gmatch("[^.]+") do
    if cur == nil then return nil end
    local ok, v = pcall(function() return cur[key] end)
    if not ok then return nil end
    cur = v
  end
  return cur
end

-- (guidStr moved to the vendored darn.lua as Darn.guidStr -- one source, usable
-- by every mod without a DarnUI dependency; it's a game-key util, not a widget.)

-- ESlateVisibility
UI.VIS = { SHOW = 0, HIDE = 1, PASSIVE = 4 }   -- Visible / Collapsed / SelfHitTestInvisible
function UI.setVis(w, vis) if not UI.alive(w) then return end pcall(function() w:SetVisibility(vis) end) end

-- ASK THESE. NEVER COMPARE .Visibility BY HAND.
--
-- UMG has FIVE visibility values and UI.VIS names three:
--     0 Visible   1 Collapsed   2 Hidden   3 HitTestInvisible   4 SelfHitTestInvisible
-- Only 1 and 2 mean "not on screen". 3 and 4 are VISIBLE -- they only opt out of hit
-- testing -- and a native canvas commonly sits at 4 in normal use.
--
-- So `w.Visibility ~= UI.VIS.SHOW` does NOT mean hidden, and writing it cost a shipped
-- regression on 2026-07-27: UI.overlay's yieldWhenHidden used exactly that, read a normal
-- PASSIVE canvas as "another mod took the screen", stood down permanently, and Living
-- Arsenal's prestige badge never appeared at all. `tools/vis-check.js` now fails the build
-- on any hand-rolled `.Visibility` comparison, because the enum is too subtle to re-derive
-- correctly at each call site.
--
-- Both default to VISIBLE when the widget cannot be read: a missing element is a worse
-- failure than one that lingers a moment too long.
function UI.isHidden(w)
  if not UI.alive(w) then return false end
  local v = safe(function() return w.Visibility end)
  return v == UI.VIS.HIDE or v == 2      -- Collapsed or Hidden
end
function UI.isVisible(w) return UI.alive(w) and not UI.isHidden(w) end

-- IS THIS WIDGET ACTUALLY ON SCREEN -- itself AND its ancestry?
--
-- UI.isHidden asks about ONE widget, which is not the same question. Palworld's IngameMenu
-- pages are shown and hidden by their container: a closed page is very often still VISIBLE
-- in its own right while the panel holding it is collapsed. Asking only the page therefore
-- reports "on screen" for a menu the player closed ten minutes ago.
--
-- That matters because a page the game builds ONCE stays alive for the whole session (the
-- reason opts.adopt exists), so "alive" stopped being a usable stand-in for "open".
--
-- GetParent() returns a plain widget pointer, so this does NOT violate the crash contract --
-- that forbids struct OUT-PARAM getters (GetPosition/GetSize), which native-write into Lua
-- memory. Depth is capped because a malformed tree must not spin.
-- Unreadable -> ON SCREEN, matching the rest of this file: a missing element is a worse
-- failure than one that lingers.
-- ONE STEP UP, ACROSS WIDGET-TREE BOUNDARIES.
--
-- GetParent() only walks within ONE widget tree: a UserWidget's root panel has no parent
-- inside its own tree, so the walk stops there. That is why the first version of onScreen
-- never once reported a page as closed (play-tested 2026-07-27, no "closed" line across a
-- whole session of opening and shutting podium panes) -- Palworld hides these pages by
-- collapsing the OUTER widget that owns them, which is one boundary above where the walk gave
-- up. The page itself stays perfectly Visible the whole time.
--
-- The outer chain crosses it: widget -> WidgetTree -> the UserWidget that owns the tree, which
-- is itself a widget in the next tree up. Confirmed by the object paths in the log:
--   ...WBP_PalOverallUILayout_C.WidgetTree.WBP_BaseCampWorkFixedAssignManage_C
--                              .WidgetTree.WBP_AssignBoard
-- Both are plain pointer reads, so this stays inside the crash contract.
local function widgetParent(w)
  local p = safe(function() return w:GetParent() end)
  if UI.alive(p) then return p end
  local tree = safe(function() return w:GetOuter() end)
  local owner = tree and safe(function() return tree:GetOuter() end)
  -- Only continue if the outer really is a widget -- everything up there has a Visibility.
  if UI.alive(owner) and safe(function() return owner.Visibility end) ~= nil then return owner end
  return nil
end

function UI.onScreen(w)
  if not UI.alive(w) then return false end
  local node, depth = w, 0
  while UI.alive(node) and depth < 24 do
    if UI.isHidden(node) then return false end
    node = widgetParent(node)
    depth = depth + 1
  end
  return true
end

-- IS THIS A REAL, LIVE PAGE -- or one of the shadows FindAllOf also returns?
--
-- FindAllOf hands back the CLASS DEFAULT OBJECT alongside real instances, plus hot-reload
-- leftovers (REINST_*, SKEL_*, TRASHCLASS_*). A CDO exists from the moment the class loads, so
-- an adopt poll finds one immediately -- which is how an Assignment Board "built" twenty
-- seconds after load, long before the player opened one (2026-07-27).
--
-- That is not a harmless miss. A CDO has no constructed widget tree, so widgets built with it
-- as their outer come back nil at best; at worst UMG walks a null and the game dies reading
-- this+0x78. The real page is the one with a WIDGET TREE THAT HAS A ROOT -- an object the game
-- has actually constructed -- and that is the whole test.
--
-- Names are matched as PLAIN TEXT (find's 4th arg): these prefixes contain no magic characters
-- today, but a pattern match here would be a silent trap for whoever adds one.
UI.NOT_INSTANCE = { "Default__", "REINST_", "SKEL_", "TRASHCLASS_" }
function UI.adoptable(w)
  if not UI.alive(w) then return false end
  local n = safe(function() return w:GetFullName() end) or ""
  for _, bad in ipairs(UI.NOT_INSTANCE) do
    if n:find(bad, 1, true) then return false end
  end
  return UI.alive(safe(function() return w.WidgetTree.RootWidget end))
end

-- THE PAGE ROOT, without having to know its name.
--
-- Every injection in this family hosts on the page's outermost canvas, because a CanvasPanel
-- CLIPS its children and an inner one silently swallows anything outside its bounds. Naming
-- that canvas per page means guessing, and a wrong guess draws into nothing -- the Assignment
-- Board burned two play-tests on a candidate list that never matched. The widget tree knows.
-- readable widget name for logs, never nil, never raises
function UI.nameOf(w)
  if not UI.alive(w) then return "nil" end
  return safe(function() return w:GetFName():ToString() end) or "?"
end

function UI.pageRoot(menu)
  return safe(function() return menu.WidgetTree.RootWidget end)
end

local WIDGET_LIB = "/Script/UMG.Default__WidgetBlueprintLibrary"
UI.BUTTON_ASSET = "/Game/Pal/Blueprint/UI/UserInterface/ESCMenu/WBP_MenuESC_Button_S"
UI.BUTTON_CLASS = UI.BUTTON_ASSET .. ".WBP_MenuESC_Button_S_C"
UI.CLICK_EVENT = UI.BUTTON_CLASS
  .. ":BndEvt__WBP_MenuESC_Button_WBP_PalInvisibleButton_K2Node_ComponentBoundEvent_0_CommonButtonBaseClicked__DelegateSignature"

-- find a named widget. PERF (2026-07-22, the menu-open lag fix): named widgets
-- are usually direct PROPERTIES on the UserWidget (verified in the WBP_MenuESC
-- dump) -- property access is one reflection call, the tree walk is hundreds.
-- Fast path 1: property. Fast path 2: the tree's root widget itself (covers
-- auto-named roots like CanvasPanel_0). Full walk only as a last resort.
function UI.findByName(rootWidget, name)
  local direct = safe(function() return rootWidget[name] end)
  if UI.alive(direct) then return direct end
  local rootW = safe(function() return rootWidget.WidgetTree.RootWidget end)
  if UI.alive(rootW) and safe(function() return rootW:GetFName():ToString() end) == name then
    return rootW
  end
  local visited = {}
  local function walk(w)
    if not UI.alive(w) then return nil end
    local a = UI.addr(w)
    if a then
      if visited[a] then return nil end
      visited[a] = true
    end
    local n = safe(function() return w:GetFName():ToString() end)
    if n == name then return w end
    local count = safe(function() return w:GetChildrenCount() end)
    if count then
      for i = 0, count - 1 do
        local hit = walk(safe(function() return w:GetChildAt(i) end))
        if hit then return hit end
      end
    end
    local inner = safe(function() return w.WidgetTree.RootWidget end)
    if UI.alive(inner) then return walk(inner) end
    return nil
  end
  local root = safe(function() return rootWidget.WidgetTree.RootWidget end)
  if UI.alive(root) then return walk(root) end
  return nil
end

-- construct a plain UMG object (CanvasPanel, TextBlock, ScrollBox, ...)
function UI.construct(classPath, outer)
  if not UI.alive(outer) then return nil end   -- freed parent tree: StaticConstructObject would AV (safe/pcall can't catch a native fault)
  local w = safe(function()
    local cls = StaticFindObject(classPath)
    if not cls or not cls:IsValid() then return nil end
    return StaticConstructObject(cls, outer, 0, 0, 0, nil, false, false, nil)
  end)
  return UI.alive(w) and w or nil
end

-- create a native menu button (the game's blueprint), label it, register its
-- address in `actions` so the class-level click hook can dispatch to `action`
function UI.nativeButton(ownerMenu, label, actions, action)
  if not UI.alive(ownerMenu) then return nil end   -- freed menu: lib:Create / GetOwningPlayer would AV
  local btn = safe(function()
    local lib = StaticFindObject(WIDGET_LIB)
    if not lib or not lib:IsValid() then return nil end
    local cls = StaticFindObject(UI.BUTTON_CLASS)
    if not cls or not cls:IsValid() then
      pcall(function() LoadAsset(UI.BUTTON_ASSET) end)
      cls = StaticFindObject(UI.BUTTON_CLASS)
    end
    if not cls or not cls:IsValid() then return nil end
    return lib:Create(ownerMenu, cls, ownerMenu:GetOwningPlayer())
  end)
  if not UI.alive(btn) then return nil end
  UI.setLabel(btn, label)
  -- NO DECORATION PASS HERE. This used to fade UI.buttonDecor on every button as it was built,
  -- and that was wrong twice over: it walked the widget tree of every button in every mod on the
  -- CONSTRUCTION path of a control, and this factory has no test coverage at all -- the kit's own
  -- tests register buttons by hand rather than going through it (see test-darnui, "register ours
  -- by hand the way nativeButton does"). A cosmetic default does not belong here. Callers that
  -- want the corner marks gone call UI.fadeDecor themselves, AFTER the button is registered.
  local a = UI.addr(btn)
  local nativeKey = a and UI.objectKey(btn, a) or nil
  if not a or not nativeKey then
    -- A VISIBLE BUTTON WITH NO GENERATION-SAFE IDENTITY IS WORSE THAN A FAILED BUILD: it can
    -- never be dispatched without address-reuse risk, so it would sit there looking clickable
    -- and either do nothing or, worse, inherit someone else's action later. Remove it.
    pcall(function() btn:RemoveFromParent() end)
    return nil
  end
  -- ONE record, shared by global ownership and the action scope, built BEFORE either is written
  -- so both point at the same immutable identity. Order matters: bindAction/actionFor validate
  -- against UI.buttonRegs, so the registration has to exist first.
  local registration = { ref = btn, addr = a, key = nativeKey, epoch = runtime.epoch }
  -- Remember every button WE created. The game's own ESC buttons are the SAME class
  -- (WBP_MenuESC_Button_S_Discord, _Eula, _Pause ...), so a click-dispatch miss cannot
  -- otherwise tell "our orphaned widget" from "a native button we must not touch".
  UI.ourButtons[a] = true
  UI.buttonRefs[a] = btn
  UI.buttonRegs[a] = registration
  if actions then
    actions[a] = action
    local refs = UI.actionRefs[actions]
    if not refs then refs = {}; UI.actionRefs[actions] = refs end
    refs[a] = btn
    local regs = UI.actionRegs[actions]
    if not regs then regs = {}; UI.actionRegs[actions] = regs end
    regs[a] = registration
  end
  return btn
end

-- did WE create the button at this address? (see nativeButton)
-- Accepts a WIDGET or a bare address. A widget can be fully revalidated; a bare address can
-- only be checked against the record, which is why passing the widget is preferred.
function UI.isOurs(widgetOrAddr)
  local kind = type(widgetOrAddr)
  local widget = (kind == "number" or kind == "string") and nil or widgetOrAddr
  local a = widget and UI.addr(widget) or widgetOrAddr
  if a == nil or UI.ourButtons[a] ~= true then return false end
  local registration = UI.buttonRegs[a]
  local candidate = widget or (registration and registration.ref)
  if registrationMatches(registration, candidate, a) then return true end
  -- A probe with a mismatching alias may simply be a foreign replacement at the same address.
  -- Do not let that probe erase still-valid ownership.
  if registrationMatches(registration, registration and registration.ref, a) then return false end
  UI.ourButtons[a], UI.buttonRefs[a], UI.buttonRegs[a] = nil, nil, nil
  return false
end

-- THE SAFE WAY TO RESOLVE A CLICK. Replaces `actions[addr]`: it re-checks that this exact
-- object -- not merely something at the same address -- is the button the action was bound to.
function UI.actionFor(actions, widget)
  if type(actions) ~= "table" or not UI.alive(widget) then return nil end
  local a = UI.addr(widget)
  if a == nil then return nil end
  local refs = UI.actionRefs[actions]
  local expected = refs and refs[a]
  local registration = UI.actionRegistration(actions, a)
  if expected == nil or registration == nil or registration.ref ~= expected
      or UI.buttonRegs[a] ~= registration
      or not registrationMatches(registration, widget, a) then return nil end
  return actions[a], a, registration
end

-- Bind an action table entry to the button that currently owns `addr`. Callers that used to
-- write `actions[addr] = fn` must call this instead, or actionFor can never authorize it.
function UI.bindAction(actions, addr, value)
  if type(actions) ~= "table" or addr == nil then return false end
  local registration = UI.buttonRegs[addr]
  if not registrationMatches(registration, registration and registration.ref, addr) then return false end
  actions[addr] = value
  UI.actionRefs[actions] = UI.actionRefs[actions] or {}
  UI.actionRegs[actions] = UI.actionRegs[actions] or {}
  UI.actionRefs[actions][addr] = registration.ref
  UI.actionRegs[actions][addr] = registration
  return true
end

-- Drop every trace of one button (used when a widget is removed rather than the world ending).
--
-- TAKES A WIDGET OR A BARE ADDRESS (virtualbjorn, merged 2026-07-28). The address form performs
-- no UObject read, which is what makes it the only form safe to call from a Destruct hook or a
-- map-pre listener -- at that point the object may already be gone and reading it is an access
-- violation pcall cannot catch.
--
-- THE SUBTLE PART is what it refuses to do. Cleanup for an OLD button can arrive after a NEW
-- button has claimed the same recycled address; unregistering blindly would then unregister the
-- new one, and a live button with no registration can never be dispatched (nativeButton would
-- rather delete a button than leave one in that state). So the global tables are cleared ONLY
-- when the registration they hold is the very one being forgotten.
function UI.forgetButton(widgetOrAddr, actions, expectedRef)
  local kind = type(widgetOrAddr)
  local widget = (kind == "number" or kind == "string") and nil or widgetOrAddr
  local a = widget and UI.addr(widget) or widgetOrAddr
  if a == nil then return false end
  local refs = type(actions) == "table" and UI.actionRefs[actions] or nil
  local registrations = type(actions) == "table" and UI.actionRegs[actions] or nil
  local scopedRef = refs and refs[a] or nil
  local scopedRegistration = registrations and registrations[a] or nil
  local globalRegistration = UI.buttonRegs[a]
  local exactRef = widget or expectedRef or scopedRef
  -- Which registration is this call actually about? The scope's own is authoritative. Without
  -- one, adopt the global only when we can show it is the same object: by wrapper identity, by
  -- full revalidation against a live widget, or because the caller named no scope at all and so
  -- is speaking about the global record itself.
  local targetRegistration = scopedRegistration
  if not targetRegistration and globalRegistration then
    if exactRef ~= nil and globalRegistration.ref == exactRef then
      targetRegistration = globalRegistration
    elseif widget ~= nil and registrationMatches(globalRegistration, widget, a) then
      targetRegistration = globalRegistration
    elseif exactRef == nil and type(actions) ~= "table" then
      targetRegistration = globalRegistration
    end
  end
  local removed = (type(actions) == "table" and actions[a] ~= nil) or targetRegistration ~= nil
  if type(actions) == "table" then
    actions[a] = nil
    if refs then refs[a] = nil end
    if registrations then registrations[a] = nil end
  end
  -- Old-scope cleanup must not erase a NEWER registration at the same address.
  if targetRegistration ~= nil and globalRegistration == targetRegistration then
    UI.ourButtons[a], UI.buttonRefs[a], UI.buttonRegs[a] = nil, nil, nil
  end
  return removed
end

-- Forget every button registered in one action scope, WITHOUT READING A SINGLE UOBJECT.
--
-- This is the teardown-safe counterpart to forgetTree, and the only one of the two that may be
-- called from a Destruct hook or a map-pre listener: at that point the page's widget tree is
-- already coming apart, and walking it is expressly unsafe. Every address is taken from Lua
-- tables we own, and forgetButton's address form performs no UObject access.
function UI.forgetScope(actions)
  if type(actions) ~= "table" then return 0 end
  local addrs = {}
  for addr in pairs(actions) do addrs[addr] = true end
  -- A button built with a NIL action has no key in `actions`, but nativeButton still registered
  -- it in the scope's ref/reg tables. Take the union of all three or those leak forever.
  for _, tbl in ipairs({ UI.actionRegs[actions], UI.actionRefs[actions] }) do
    if type(tbl) == "table" then for addr in pairs(tbl) do addrs[addr] = true end end
  end
  local count = 0
  for addr in pairs(addrs) do
    if UI.forgetButton(addr, actions) then count = count + 1 end
  end
  return count
end

-- Forget every button in a LIVE OWNED SUBTREE -- call it BEFORE RemoveFromParent, while the
-- widgets can still be read. For teardown (Destruct, map-pre) use the address form of
-- forgetButton instead: walking a half-destroyed WidgetTree is expressly unsafe.
function UI.forgetTree(root, actions)
  if not UI.alive(root) then return 0 end
  local seen, count = {}, 0
  local function walk(w)
    if not UI.alive(w) then return end
    local a = UI.addr(w)
    local key = a or tostring(w)
    if seen[key] then return end        -- a cycle here would recurse until the stack gives out
    seen[key] = true
    if UI.forgetButton(w, actions) then count = count + 1 end
    local n = safe(function() return w:GetChildrenCount() end)
    if type(n) == "number" then
      for i = 0, n - 1 do walk(safe(function() return w:GetChildAt(i) end)) end
    end
    local inner = safe(function() return w.WidgetTree.RootWidget end)
    if UI.alive(inner) then walk(inner) end
  end
  walk(root)
  return count
end

-- Insert `w` into a NATIVE panel at `index` (0-based), because UMG exposes no
-- InsertChildAt -- only AddChildTo*. The only way in is to detach everything after
-- the insertion point and put it back, which means the SLOT PROPERTIES (padding,
-- size, alignments) must be captured and restored or the game's own buttons come
-- back mis-styled. `addFn(panel, widget) -> slot` does the append (a VerticalBox
-- needs AddChildToVerticalBox, a canvas something else), and `onSlot(slot)` is
-- called for OUR widget's slot so the caller can pad it.
--
-- ALWAYS ends with UI.relayout: without it Slate keeps stale cached geometry and the
-- panel DRAWS in the new order while HIT-TESTING still uses the old one -- measured
-- 2026-07-25, the first click on our ESC-menu button dispatched to the native
-- "Return to Title" beneath it, one mis-click from dropping the player to the title
-- screen. Any later relayout masked it, which is why only the FIRST click was wrong.
--
-- Returns true on a real insert, false if it fell back to a plain append (which is
-- always attempted rather than failing outright -- a button at the bottom beats no
-- button). LIVE panels only: never restructure a lingering/swept menu (the AV law).
-- A SLOT THAT IS NOT NIL IS NOT NECESSARILY VALID.
--
-- When a panel refuses a child -- which is what a menu mid-teardown does -- UE4SS can hand back
-- a non-nil slot object that is not usable. Writing a struct into it (SetPadding, SetSize) is a
-- store into a null pointer at a small offset, and pcall does NOT catch a native AV.
--
-- This is the same defect as the canvasAdd one that produced "AV writing 0x68"; here the offset
-- is 0x80. DarnMenu's own comments record an 0x80 dump from 2026-07-25 on this very path, blamed
-- then on a VerticalBox reflow -- but the reflow only crashes because the slot writes that follow
-- it are unguarded. Third crash tonight ended on the sweep-then-inject path.
local function usableSlot(s)
  if not s then return nil end
  local ok, valid = pcall(function() return s:IsValid() end)
  if ok and valid == false then return nil end
  return s
end

function UI.insertChildAt(panel, w, index, addFn, onSlot)
  if not (UI.alive(panel) and UI.alive(w) and type(addFn) == "function") then return false end
  local function append()
    local ok = pcall(function()
      local s = usableSlot(addFn(panel, w))
      if onSlot and s then onSlot(s) end
    end)
    UI.relayout(panel)
    return ok
  end
  if type(index) ~= "number" or index < 0 then return append() end
  local ok = pcall(function()
    local count = panel:GetChildrenCount()
    if count <= 0 or index > count then error("index out of range") end
    local tail = {}
    for i = index, count - 1 do
      local ch = panel:GetChildAt(i)
      local slot = ch and ch.Slot
      tail[#tail + 1] = { w = ch,
        pad  = slot and slot.Padding or nil,
        size = slot and slot.Size or nil,
        hA   = slot and slot.HorizontalAlignment or nil,
        vA   = slot and slot.VerticalAlignment or nil }
    end
    for i = count - 1, index, -1 do panel:RemoveChildAt(i) end
    -- Re-check the panel between the detach and the re-add. A menu being torn down can lose its
    -- panel mid-operation, and every write below would then land on nothing.
    if not UI.alive(panel) then error("panel died mid-insert") end
    local mine = usableSlot(addFn(panel, w))
    if onSlot and mine then onSlot(mine) end
    for _, e in ipairs(tail) do
      local s = usableSlot(addFn(panel, e.w))
      if s then                                    -- restore what we detached
        if e.pad  then pcall(function() s:SetPadding(e.pad) end) end
        if e.size then pcall(function() s:SetSize(e.size) end) end
        if e.hA   then pcall(function() s:SetHorizontalAlignment(e.hA) end) end
        if e.vA   then pcall(function() s:SetVerticalAlignment(e.vA) end) end
      end
    end
  end)
  if not ok then return append() end               -- any failure -> bottom of the panel
  UI.relayout(panel)
  return true
end

-- Force a container to recompute its layout NOW.
-- WHY THIS EXISTS (measured 2026-07-25): inserting a button into the ESC menu's native
-- VerticalBox (remove-tail / append / re-append, since UMG exposes no InsertChildAt)
-- leaves Slate's CACHED GEOMETRY stale for the first frames. The column DRAWS in the
-- new order while HIT-TESTING still uses the old one, so the first click is displaced
-- by one slot: clicking "Mod Options" actually hit the native "Return to Title"
-- (logged: name=WBP_MenuESC_Button_S_ReturnTitle ours=false) -- and, from the same
-- off-by-one, "Link Discord" on other runs. It self-corrects after any later relayout,
-- which is why ONLY the first click misbehaved and everything after it was fine.
-- Call this after ANY structural change to a native panel. Live menus only -- never on
-- a lingering/swept one (that is a layout mutation, and the vault's AV law applies).
function UI.relayout(w)
  if not UI.alive(w) then return false end
  local ok = pcall(function() w:InvalidateLayoutAndVolatility() end)
  pcall(function() w:ForceLayoutPrepass() end)
  return ok
end

-- ETextJustify: 0 Left, 1 Center, 2 Right. A native button centres its label, which is right
-- for a button and wrong for a COLUMN -- centred names and centred numbers in a list give you
-- two ragged edges and no alignment to read down.
UI.JUSTIFY = { LEFT = 0, CENTER = 1, RIGHT = 2 }
function UI.setJustify(tb, j)
  if not UI.alive(tb) then return end
  pcall(function() tb:SetJustification(j) end)
end

function UI.setLabel(btn, text) if not UI.alive(btn) then return end pcall(function() btn.Text_Main:SetText(FText(text)) end) end
function UI.focus(btn) if not UI.alive(btn) then return end pcall(function() btn.WBP_PalInvisibleButton:SetFocus() end) end
function UI.selected(btn, on)
  if not UI.alive(btn) then return end
  pcall(function()
    if on then btn:AnmEvent_Focus() else btn:AnmEvent_Normal() end
  end)
end
function UI.remove(w) if not UI.alive(w) then return end pcall(function() w:RemoveFromParent() end) end

-- pick a native TextBlock to copy style from (font/colors/shadow)
function UI.styleTemplate(menu)
  for _, name in ipairs({ "BPPalTextBlock_WorldName", "Text_InviteCode" }) do
    local t = UI.findByName(menu, name)
    if t then return t end
  end
  return nil
end

function UI.mkText(widgetTree, template, text, fontSize, alpha)
  local tb = UI.construct("/Script/UMG.TextBlock", widgetTree)
  if not tb then return nil end
  pcall(function() tb:SetText(FText(text)) end)
  if template then
    pcall(function()
      tb:SetFont(template.Font)
      tb:SetColorAndOpacity(template.ColorAndOpacity)
      tb:SetShadowColorAndOpacity(template.ShadowColorAndOpacity)
      tb:SetShadowOffset(template.ShadowOffset)
    end)
  end
  if fontSize then
    pcall(function()
      local f = tb.Font
      f.Size = fontSize
      tb:SetFont(f)
    end)
  end
  if alpha then
    pcall(function()
      tb:SetColorAndOpacity({ SpecifiedColor = { R = 1, G = 1, B = 1, A = alpha }, ColorUseRule = 0 })
    end)
  end
  return tb
end

function UI.mkEdit(widgetTree, initial)
  local eb = UI.construct("/Script/Pal.PalEditableTextBox", widgetTree)
    or UI.construct("/Script/UMG.EditableTextBox", widgetTree)
  if not eb then return nil end
  pcall(function()
    eb.IsReadOnly = false
    eb.SelectAllTextWhenFocused = true
    eb.RevertTextOnEscape = true
    eb.Justification = 1
  end)
  pcall(function() eb:SetText(FText(tostring(initial or ""))) end)
  UI.styleEdit(eb)
  return eb
end

-- dark text on the light native box. IDEMPOTENT and meant to be RE-APPLIED:
-- PalEditableTextBox can stomp construction-time styling on first paint (per
-- instance, timing-dependent), which rendered white-on-white "invisible values"
-- -- the box updated but showed nothing until a lucky rebuild. Callers re-apply
-- on every refresh/write.
function UI.styleEdit(eb)
  if not UI.alive(eb) then return end
  pcall(function()
    eb.WidgetStyle.ForegroundColor.SpecifiedColor = { R = 0.02, G = 0.02, B = 0.02, A = 1 }
    eb.WidgetStyle.ForegroundColor.ColorUseRule = 0
  end)
  pcall(function()
    eb.WidgetStyle.TextStyle.ColorAndOpacity.SpecifiedColor = { R = 0, G = 0, B = 0, A = 1 }
    eb.WidgetStyle.TextStyle.ColorAndOpacity.ColorUseRule = 0
  end)
  pcall(function() eb.WidgetStyle.TextStyle.Font.Size = 16 end)
  pcall(function() eb:SetForegroundColor({ R = 0.02, G = 0.02, B = 0.02, A = 1 }) end)
end

function UI.editText(eb)
  if not UI.alive(eb) then return nil end
  local ok, s = pcall(function() return eb:GetText():ToString() end)
  if ok then return s end
  return nil
end
function UI.setEditText(eb, s) if not UI.alive(eb) then return end pcall(function() eb:SetText(FText(tostring(s))) end) end
-- give keyboard/controller focus to an edit box (so a controller isn't stranded
-- after a dropdown pick tears down the focused suggestion button)
function UI.focusEdit(eb)
  if not UI.alive(eb) then return end
  if pcall(function() eb:SetKeyboardFocus() end) then return end
  pcall(function() eb:SetFocus() end)
end

-- absolute placement on a canvas
-- THE SLOT MUST BE CHECKED BEFORE IT IS WRITTEN TO.
--
-- AddChildToCanvas returns the new slot -- or NOTHING, if the engine refuses the add (the
-- widget already has a parent, the panel's Slate widget is not constructed yet). Writing to
-- that is a store into a null pointer at a small offset, which is exactly the crash reported on
-- 2026-07-27: EXCEPTION_ACCESS_VIOLATION *writing* address 0x68. pcall does not catch a native
-- AV, so the wrapping pcall in each of these functions never stood a chance.
--
-- Every other slot-touching function in this file already guards (canvasMove, canvasResize).
-- These three -- the ones that create the slot in the first place -- did not.
local function slotOf(canvas, w)
  local slot = canvas:AddChildToCanvas(w)
  if not (slot and slot:IsValid()) then error("canvas refused the child", 0) end
  return slot
end

function UI.canvasAdd(canvas, w, x, y, sx, sy, z)
  if not (UI.alive(canvas) and UI.alive(w)) then return false end
  return pcall(function()
    local slot = slotOf(canvas, w)
    slot:SetAnchors({ Minimum = { X = 0, Y = 0 }, Maximum = { X = 0, Y = 0 } })
    slot:SetAlignment({ X = 0, Y = 0 })
    slot:SetPosition({ X = x, Y = y })
    slot:SetSize({ X = sx, Y = sy })
    slot:SetZOrder(z or 1)
  end)
end

-- top-center anchored placement: element stays horizontally centered at any
-- aspect ratio (the ultrawide fix); y is absolute from the top, x an offset
-- from screen center applied via alignment.
function UI.canvasAddTopCenter(canvas, w, y, sx, sy, z)
  if not (UI.alive(canvas) and UI.alive(w)) then return false end
  return pcall(function()
    local slot = slotOf(canvas, w)
    slot:SetAnchors({ Minimum = { X = 0.5, Y = 0 }, Maximum = { X = 0.5, Y = 0 } })
    slot:SetAlignment({ X = 0.5, Y = 0 })
    slot:SetPosition({ X = 0, Y = y })
    slot:SetSize({ X = sx, Y = sy })
    slot:SetZOrder(z or 1)
  end)
end

-- bottom-right anchored placement: element pins to the parent's lower-right
-- corner (xOff/yOff are inward pixel offsets from that corner), so it stays put
-- at any resolution/aspect. Used by the ESC prestige badge.
function UI.canvasAddBottomRight(canvas, w, xOff, yOff, sx, sy, z)
  if not (UI.alive(canvas) and UI.alive(w)) then return false end
  return pcall(function()
    local slot = slotOf(canvas, w)
    slot:SetAnchors({ Minimum = { X = 1, Y = 1 }, Maximum = { X = 1, Y = 1 } })
    slot:SetAlignment({ X = 1, Y = 1 })
    slot:SetPosition({ X = -(xOff or 0), Y = -(yOff or 0) })
    slot:SetSize({ X = sx, Y = sy })
    slot:SetZOrder(z or 1)
  end)
end

-- bottom-LEFT twin: the native screens sign themselves with the page's name huge
-- and quiet at the screen's lower-left ("Mission", "Pal Stats") -- this is the
-- anchor that lets an overlay wear the same signature. (Standing Orders' design
-- pass, 2026-08-10; promoted to the kit master the same day after
-- kitversion-check caught the vendored-only edit.)
function UI.canvasAddBottomLeft(canvas, w, xOff, yOff, sx, sy, z)
  if not (UI.alive(canvas) and UI.alive(w)) then return false end
  return pcall(function()
    local slot = slotOf(canvas, w)
    slot:SetAnchors({ Minimum = { X = 0, Y = 1 }, Maximum = { X = 0, Y = 1 } })
    slot:SetAlignment({ X = 0, Y = 1 })
    slot:SetPosition({ X = (xOff or 0), Y = -(yOff or 0) })
    slot:SetSize({ X = sx, Y = sy })
    slot:SetZOrder(z or 1)
  end)
end

-- place `w` in anchorWidget's OWN canvas panel, directly above it, mirroring its
-- anchors + alignment so `w` tracks the anchor at ANY resolution/aspect (used to
-- pin the ESC prestige badge just above the native Block List button). Reads the
-- anchor's canvas-slot geometry BEFORE reparenting, so if the anchor isn't a live
-- CanvasPanel child this throws before adding `w` and the caller's fallback runs
-- exactly once. Returns true on success, false otherwise.
--
-- POINT-ANCHORED ANCHORS ONLY. It mirrors the anchor's anchors and then writes Position/Size,
-- which only describes a slot whose anchor is a POINT (Min == Max). Given a STRETCH-anchored
-- anchor it produces a rect the slot cannot represent, and Slate AVs laying it out -- cost a CTD
-- on 2026-07-31 (`writing 0x1c`) pinning a button above the ESC menu's full-width bottom column.
-- For a stretched anchor use UI.canvasAddAboveStretch below.
function UI.canvasAddAbove(anchorWidget, w, gap, sx, sy, z)
  if not (UI.alive(anchorWidget) and UI.alive(w)) then return false end
  return (pcall(function()
    local parent = anchorWidget:GetParent()
    if not UI.alive(parent) then error("no parent") end
    local aslot   = anchorWidget.Slot
    local anchors = aslot:GetAnchors()
    local align   = aslot:GetAlignment()
    local pos     = aslot:GetPosition()
    local size    = aslot:GetSize()
    -- undo the anchor's OWN pivot (alignment) to recover its right edge + top in
    -- the parent's frame, so `w` lands directly above it with right edges aligned,
    -- regardless of how the anchor widget itself was aligned. (Copying its pivot
    -- verbatim floated the badge up-and-left -- this is the fix.)
    local rightX = pos.X + (1 - align.X) * size.X
    local topY   = pos.Y - align.Y * size.Y
    -- Same guard as every other add site: a refused add returns a NON-NIL invalid slot, and the
    -- five writes below would each be a store into nothing. Found by tools/slot-check.js on the
    -- day it was written -- this one had been missed by both hand-fixes.
    local slot = slotOf(parent, w)
    slot:SetAnchors(anchors)
    slot:SetAlignment({ X = 0, Y = 0 })
    slot:SetPosition({ X = rightX - (sx or 0), Y = topY - (sy or 0) - (gap or 0) })
    slot:SetSize({ X = sx, Y = sy })
    slot:SetZOrder(z or 1)
  end))
end

-- place `w` directly above anchorWidget, mirroring its anchors, alignment AND horizontal
-- offsets -- the STRETCHED-ANCHOR counterpart of canvasAddAbove.
--
-- WHY BOTH EXIST. A canvas slot has two different geometries depending on its anchors. With a
-- POINT anchor (Min == Max) it is Position + Size, and canvasAddAbove is correct. With a
-- STRETCHED anchor (Min.X ~= Max.X, e.g. a full-width column) the slot is defined by OFFSETS --
-- Left/Top/Right/Bottom insets from the anchor rect -- and Position/Size report those raw
-- numbers reinterpreted, which is meaningless as coordinates.
--
-- Measured on the ESC menu's bottom button column, 2026-07-31:
--     pos=(0,-30) size=(0,30) anchors=(0,1)-(1,1) align=(0,1)
-- Read as Position/Size that says "width 0 at x 0", so canvasAddAbove put a 400-wide button at
-- x = -400 -- off the left edge of the panel entirely. Read as Offsets it says "full width,
-- 30 tall, sitting 30 above the bottom" -- which is what it actually is.
--
-- `h` is the new widget's height; width is inherited from the anchor's Left/Right insets, so the
-- result lines up with the native column at any resolution instead of guessing a pixel width.
function UI.canvasAddAboveStretch(anchorWidget, w, gap, h, z)
  if not (UI.alive(anchorWidget) and UI.alive(w)) then return false end
  return (pcall(function()
    local parent = anchorWidget:GetParent()
    if not UI.alive(parent) then error("no parent") end
    local aslot   = anchorWidget.Slot
    local anchors = aslot:GetAnchors()
    local align   = aslot:GetAlignment()
    local off     = aslot:GetOffsets()
    if not (off and off.Top) then error("no offsets") end
    -- Same guard as every other add site: a refused add returns a NON-NIL invalid slot.
    local slot = slotOf(parent, w)
    slot:SetAnchors(anchors)
    slot:SetAlignment(align)
    slot:SetOffsets({ Left = off.Left, Top = off.Top - (h + (gap or 0)),
                      Right = off.Right, Bottom = h })
    slot:SetZOrder(z or 1)
  end))
end

-- How far a canvas's BOTTOM-ANCHORED stack already reaches upward: the smallest (most negative)
-- Offsets.Top among its bottom-anchored children. Returns nil when there are none.
--
-- WHAT IT IS FOR: a shared native panel is first-come-first-served, and every mod that pins a
-- row above the same column computes the same spot and lands on the previous one. On 2026-07-31
-- DarnMenu's entry button drew squarely on top of another mod's. Reading the stack means the
-- second arrival can sit ABOVE the first instead of over it -- no mod names, no coordination,
-- just "what is already parked here".
--
-- READ-ONLY. It enumerates and reads slots; it mutates nothing, so it is safe on a native panel
-- (unlike anything that reflows one -- see canvasAddAboveStretch's note).
--
-- Bottom-anchored means Anchors.Minimum.Y == 1: a child pinned to the panel's bottom edge, which
-- is what the ESC menu's button columns and every mod row above them use. Top-anchored children
-- (the upper column) live in a different coordinate origin and must not be mixed in.
--
-- INSTRUMENTATION, OFF UNLESS shared/DarnMenu_debug.txt EXISTS (any content; the file's
-- presence is the switch). The scan reports "nothing parked here" and "there is a neighbour I
-- could not read" with the same nil, so a report of "your button still lands on top of mine"
-- carries no way to tell which of the four miss modes it was: a neighbour on a different
-- parent, a top-anchored neighbour, an unreadable slot, or one that injects after us. Guessing
-- at hardenings against a layout nobody has dumped is how the last three attempts went, so:
-- with the flag file in place, every child of the canvas is printed once per scan -- name,
-- anchors, offsets, alignment -- and the next report says which it is.
--
-- The flag is named for DarnMenu because DarnMenu is the only caller and the reports are
-- against its entry button. Kept out of the loop body's hot path: one io.open per scan, and a
-- scan happens at most once per ESC-menu open (DarnMenu caches the result for the session).
local STACK_DEBUG_PATH = (debug.getinfo(1, "S").source:gsub("^@", ""):gsub("[^/\\]+$", ""))
  .. "../../shared/DarnMenu_debug.txt"
local function stackDebugOn()
  local f = io.open(STACK_DEBUG_PATH, "r")
  if not f then return false end
  pcall(function() f:close() end)
  return true
end

-- One child, described. Everything is read defensively: this runs against native widgets whose
-- slot may not answer, and a diagnostic that throws is worse than no diagnostic.
local function describeStackChild(index, ch)
  local name = safe(function() return ch:GetFName():ToString() end) or "?"
  local class = safe(function() return ch:GetClass():GetFName():ToString() end) or "?"
  if not UI.alive(ch) then
    return string.format("  [%d] %s (%s) -- not alive", index, name, class)
  end
  local s = safe(function() return ch.Slot end)
  if not (s and safe(function() return s:IsValid() end)) then
    return string.format("  [%d] %s (%s) -- no readable slot", index, name, class)
  end
  local a = safe(function() return s:GetAnchors() end)
  local o = safe(function() return s:GetOffsets() end)
  local al = safe(function() return s:GetAlignment() end)
  return string.format(
    "  [%d] %s (%s) anchors=(%.2f,%.2f)-(%.2f,%.2f) offsets=L%.0f T%.0f R%.0f B%.0f align=(%.2f,%.2f)",
    index, name, class,
    (a and a.Minimum.X) or -1, (a and a.Minimum.Y) or -1,
    (a and a.Maximum.X) or -1, (a and a.Maximum.Y) or -1,
    (o and o.Left) or -1, (o and o.Top) or -1, (o and o.Right) or -1, (o and o.Bottom) or -1,
    (al and al.X) or -1, (al and al.Y) or -1)
end

function UI.bottomStackTop(canvas, exclude)
  if not UI.alive(canvas) then return nil end
  local best
  local dbg = stackDebugOn()
  pcall(function()
    local n = canvas:GetChildrenCount() or 0
    if dbg then print(string.format("[DarnUI] bottomStackTop: %d canvas child(ren)\n", n)) end
    for i = 0, n - 1 do
      local ch = canvas:GetChildAt(i)
      -- dumped BEFORE the alive/exclude/anchor filters, on purpose: the children this scan
      -- skips are exactly the ones a miss hides behind.
      if dbg and ch ~= nil then
        pcall(function() print("[DarnUI]" .. describeStackChild(i, ch) .. "\n") end)
      end
      if UI.alive(ch) and ch ~= exclude then
        pcall(function()
          local s = ch.Slot
          if s and s:IsValid() and s:GetAnchors().Minimum.Y == 1 then
            local t = s:GetOffsets().Top
            if type(t) == "number" and (best == nil or t < best) then best = t end
          end
        end)
      end
    end
  end)
  if dbg then print("[DarnUI] bottomStackTop -> " .. tostring(best) .. "\n") end
  return best
end

-- viewport-space (design-unit) TOP-RIGHT corner of a widget's ACTUAL rendered
-- rect. Correct on any resolution/aspect because it uses real Slate geometry, not
-- canvas-slot math (which breaks on auto-sized slots). Returns x, y numbers, or
-- nil if geometry isn't ready yet (first frame after open) or the lib is missing.
function UI.viewportTopRight(widget, world)
  if not UI.alive(widget) then return nil end
  local ok, x, y = pcall(function()
    local SBL = StaticFindObject("/Script/UMG.Default__SlateBlueprintLibrary")
    if not SBL then error("no SlateBlueprintLibrary") end
    local geo  = widget:GetCachedGeometry()
    local size = SBL:GetLocalSize(geo)
    if not size or (size.X == 0 and size.Y == 0) then error("geometry not ready") end
    local _, vp = SBL:LocalToViewport(world, geo, { X = size.X, Y = 0 })
    return vp.X, vp.Y
  end)
  if ok and type(x) == "number" then return x, y end
  return nil
end

-- full-bleed overlay on a canvas
function UI.canvasFill(canvas, w, z)
  if not (UI.alive(canvas) and UI.alive(w)) then return false end
  return pcall(function()
    local slot = slotOf(canvas, w)
    slot:SetAnchors({ Minimum = { X = 0, Y = 0 }, Maximum = { X = 1, Y = 1 } })
    slot:SetOffsets({ Left = 0, Top = 0, Right = 0, Bottom = 0 })
    slot:SetZOrder(z or 50)
  end)
end

-- ---------------------------------------------------------------------------
-- SAFE OVERLAY INJECTION -- codifies the 2026-07-25 ESC-menu crash lessons so
-- consumers cannot repeat them. HARD RULES baked in:
--   * widgets are added ONLY to a CanvasPanel (absolute layout -> no reflow);
--   * sweeping a stale menu only SetVisibility(Collapsed)s OUR OWN tracked
--     widgets -- NEVER RemoveFromParent (AV), NEVER touch a native layout
--     container's children like a VerticalBox (reflow AV, proven twice);
--   * the engine frees our children itself when it Destructs the menu;
--   * build hidden (no flash); poll is generation-guarded; every touch alive-gated.
-- opts = { class = "<BP path _C>", canvas = "<CanvasPanel widget name>",
--          pollMs = 1000, build = function(o) end, refresh = function(o) end }
-- Host `o` (passed to build/refresh): o.menu, o.canvas, o.actions, o.widgets,
--   o:place(w,x,y,sx,sy,z) -> canvasAdd to the safe canvas + track for cleanup,
--   o:button(label, action) -> tracked nativeButton on o.menu,
--   o:show(w) / o:hide(w).
-- ---------------------------------------------------------------------------
-- ---------------------------------------------------------------------------
-- KEYGUIDE (contributed by VirtualBjorn, merged 2026-07-25): render Palworld's
-- OWN key-guide textures as key icons in keybind pickers. Key names use UE4SS's
-- public Key enum so the saved value still feeds RegisterKeyBind. All construction
-- goes through the hardened UI.construct, so it inherits the safety contract.
-- ---------------------------------------------------------------------------
local KEYBOARD_ROOT = "/Game/Pal/Texture/UI/KeyGuide/keyboard/"
local MOUSE_ROOT = "/Game/Pal/Texture/UI/KeyGuide/mouse/"
local KEYCAP_OBJECTS, textureCache = {}, {}
local function addKeyboard(names, suffix)
  local asset = "T_KeyGuide_Keyboard_" .. suffix
  local objectPath = KEYBOARD_ROOT .. asset .. "." .. asset
  for _, name in ipairs(names) do KEYCAP_OBJECTS[name] = objectPath end
end
local function addMouse(names, asset)
  local objectPath = MOUSE_ROOT .. asset .. "." .. asset
  for _, name in ipairs(names) do KEYCAP_OBJECTS[name] = objectPath end
end
local digitNames = { "ZERO","ONE","TWO","THREE","FOUR","FIVE","SIX","SEVEN","EIGHT","NINE" }
for index = 0, 9 do
  addKeyboard({ digitNames[index + 1], tostring(index) }, tostring(index))
  addKeyboard({ "NUM_" .. digitNames[index + 1], "NUMPAD_" .. tostring(index) }, "Num" .. tostring(index))
end
for code = string.byte("A"), string.byte("Z") do addKeyboard({ string.char(code) }, string.char(code)) end
for index = 1, 12 do addKeyboard({ "F" .. tostring(index) }, "F" .. tostring(index)) end
addKeyboard({ "SUBTRACT", "NUMPAD_SUBTRACT" }, "NumMinus")
addKeyboard({ "ADD", "NUMPAD_ADD" }, "NumPlus")
addKeyboard({ "MULTIPLY", "NUMPAD_MULTIPLY" }, "NumAsterisk")
addKeyboard({ "DIVIDE", "NUMPAD_DIVIDE" }, "NumSlash")
addKeyboard({ "DECIMAL", "NUMPAD_DECIMAL" }, "NumPeriod")
addKeyboard({ "INS", "INSERT" }, "Insert"); addKeyboard({ "DEL", "DELETE" }, "Delete")
addKeyboard({ "HOME" }, "Home"); addKeyboard({ "END" }, "End")
addKeyboard({ "PAGE_UP" }, "PageUp"); addKeyboard({ "PAGE_DOWN" }, "PageDown")
addKeyboard({ "CONTROL", "CTRL" }, "Ctrl"); addKeyboard({ "ALT" }, "Alt")
addKeyboard({ "SHIFT" }, "shift"); addKeyboard({ "ESC", "ESCAPE" }, "Esc")
addMouse({ "LEFT_MOUSE_BUTTON", "LEFT_MOUSE" }, "T_MenuKeyGuide_MouseButtonLeft")
addMouse({ "RIGHT_MOUSE_BUTTON", "RIGHT_MOUSE" }, "T_MenuKeyGuide_MouseButtonRight")
addMouse({ "MIDDLE_MOUSE_BUTTON", "MIDDLE_MOUSE" }, "T_MenuKeyGuide_MouseWheelButton")
addMouse({ "XBUTTON_ONE", "MOUSE_BUTTON_4" }, "T_MenuKeyGuide_MouseButton4")
addMouse({ "XBUTTON_TWO", "MOUSE_BUTTON_5" }, "T_MenuKeyGuide_MouseButton5")

function UI.mkImage(widgetTree)
  local image = UI.construct("/Script/UMG.Image", widgetTree)
  if image then UI.setVis(image, UI.VIS.HIDE) end
  return image
end
function UI.mkKeycapImage(widgetTree) return UI.mkImage(widgetTree) end
local function textureAsset(objectPath)
  if type(objectPath) ~= "string" or objectPath == "" then return nil end
  local cached = textureCache[objectPath]
  if UI.alive(cached) then return cached end
  local texture = safe(function() return LoadAsset(objectPath) end)
  if not UI.alive(texture) then texture = safe(function() return StaticFindObject(objectPath) end) end
  if UI.alive(texture) then textureCache[objectPath] = texture; return texture end
  return nil
end
function UI.setImageAsset(image, objectPath)
  local texture = textureAsset(objectPath)
  if texture and UI.alive(image) then
    local ok = pcall(function() image:SetBrushFromTexture(texture, false); image:SetVisibility(UI.VIS.PASSIVE) end)
    if ok then return true end
  end
  UI.setVis(image, UI.VIS.HIDE)
  return false
end
function UI.setKeycapImage(image, keyName)
  return UI.setImageAsset(image, KEYCAP_OBJECTS[tostring(keyName or ""):upper()])
end
-- keep the native button as the hover/click frame, draw the keyguide over it;
-- if Palworld has no matching texture, fall back to the text label.
function UI.setKeycap(btn, image, keyName)
  if UI.setKeycapImage(image, keyName) then UI.setLabel(btn, ""); return true end
  UI.setLabel(btn, tostring(keyName or "")); return false
end
function UI.setKeycapPrompt(btn, image, text) UI.setVis(image, UI.VIS.HIDE); UI.setLabel(btn, text) end
function UI.focusWidget(widget)
  if not UI.alive(widget) then return false end
  local ok = pcall(function() widget:SetKeyboardFocus() end)
  if not ok then ok = pcall(function() widget:SetFocus() end) end
  return ok
end
function UI.canvasMove(w, x, y)
  if not UI.alive(w) then return false end
  return pcall(function() local s = w.Slot; if s and s:IsValid() then s:SetPosition({ X = x, Y = y }) end end)
end
-- Resize a canvas child we own. Companion to canvasMove, and needed for the same reason:
-- a backing panel sized for the maximum row count is a big empty box when the list is short,
-- and rebuilding it on every change is the widget churn this family's crashes came from.
function UI.canvasResize(w, sx, sy)
  if not UI.alive(w) then return false end
  return pcall(function()
    local s = w.Slot
    if s and s:IsValid() then s:SetSize({ X = sx, Y = sy }) end
  end)
end

-- CENTRED, WITH AN OFFSET. canvasAddCenter pins a widget to the exact middle; this puts it a
-- fixed distance from the middle, which is what you want for anything that has to sit relative
-- to the game's own centred modal -- above it, beside it -- rather than relative to a screen
-- corner. Absolute coordinates on a full-screen root always drift, because the modal moves with
-- the resolution and the corner does not.
function UI.canvasAddCentered(canvas, w, dx, dy, sx, sy, z)
  if not (UI.alive(canvas) and UI.alive(w)) then return false end
  return pcall(function()
    local slot = slotOf(canvas, w)
    slot:SetAnchors({ Minimum = { X = 0.5, Y = 0.5 }, Maximum = { X = 0.5, Y = 0.5 } })
    slot:SetAlignment({ X = 0.5, Y = 0.5 })
    slot:SetPosition({ X = dx or 0, Y = dy or 0 })
    slot:SetSize({ X = sx, Y = sy })
    slot:SetZOrder(z or 1)
  end)
end

function UI.canvasAddCenter(canvas, w, sx, sy, z)
  if not (UI.alive(canvas) and UI.alive(w)) then return false end
  return pcall(function()
    local slot = slotOf(canvas, w)
    slot:SetAnchors({ Minimum = { X = 0.5, Y = 0.5 }, Maximum = { X = 0.5, Y = 0.5 } })
    slot:SetAlignment({ X = 0.5, Y = 0.5 })
    slot:SetPosition({ X = 0, Y = 0 }); slot:SetSize({ X = sx, Y = sy }); slot:SetZOrder(z or 1)
  end)
end

-- Shared click dispatch for ALL overlays: ONE hook on the button-click delegate,
-- routes a clicked overlay button to its overlay's onClick(o, action).
local _overlayEntries = {}          -- { { insts = <table>, onClick = fn }, ... }
local _overlayClickArmed = false
local function armOverlayClick()
  if _overlayClickArmed then return end
  -- The click delegate we hook lives on UI.BUTTON_CLASS. At mod-LOAD (before any
  -- menu has opened) that asset may not be loaded yet, so RegisterHook can't
  -- resolve the function and silently fails -- which is why an overlay button
  -- would SHOW but never dispatch a click. So: (1) load the asset first, and
  -- (2) only latch `armed` when the hook actually TOOK, so make() can retry on
  -- the first real menu open (when everything is loaded), exactly like DarnMenu's
  -- armHooks arms its ESC-menu click hook on menu open rather than at boot.
  pcall(function() LoadAsset(UI.BUTTON_ASSET) end)
  local ok = pcall(RegisterHook, UI.CLICK_EVENT, function(Context)
    local btn = safe(function() return Context:get() end)
    local a = btn and UI.addr(btn)
    if not a then return end
    local live, stale = 0, 0
    for _, e in ipairs(_overlayEntries) do
      for _, o in pairs(e.insts) do
        -- actionFor, NOT o.actions[a]: the raw index would fire our handler for a foreign
        -- widget that merely inherited a recycled address.
        if o.disposed then stale = stale + 1
        else
          live = live + 1
          local action = UI.actionFor(o.actions, btn)
          if action ~= nil then pcall(e.onClick, o, action); return end
        end
      end
    end
    -- NOTHING MATCHED. If the widget is one of OURS, that is a real failure and it deserves a
    -- name: a button on screen, built by us, that dispatches nowhere. This was SILENT, which is
    -- exactly why "the SO chip stops working after the first order" could not be told apart from
    -- "the click never reached the game" -- both produced no line at all. Reported repeatedly
    -- 2026-07-30 and undiagnosable without this.
    --
    -- Once per address: a dead button gets clicked more than once by a player who expects it to
    -- work, and a line per press would bury the first one.
    if UI.isOurs(btn) and not UI.orphanSeen[a] then
      UI.orphanSeen[a] = true
      -- DEFAULT-ON. This report is the diagnostic that solved "the SO chip works once and
      -- never again" -- and it only spoke because that one consumer had wired UI.orphanLog.
      -- An opt-in diagnostic protects only the mod that already suspects the bug; every
      -- other consumer would get the same three sessions of silence. orphanLog remains the
      -- override for a consumer that wants it in its own log.
      local say = UI.orphanLog or function(m) print("[DarnUI] " .. m .. "\n") end
      pcall(say, string.format(
        "ORPHANED CLICK: a button we built dispatched nowhere (addr=%s, %d live overlay(s), "
        .. "%d disposed). The widget is ours but no live overlay claims an action for it -- "
        .. "so it is a leftover from a rebuild, or its registration was replaced.",
        tostring(a), live, stale))
    end
  end)
  if ok then _overlayClickArmed = true end
end
-- true if `addr` is an overlay button (lets another click hook skip/ignore it)
-- Accepts a widget or an address. With a widget the answer is fully revalidated; with a bare
-- address it falls back to the ownership record, which is the best that can be known.
function UI.ownsButton(widgetOrAddr)
  if runtime.worldGone then return false end
  local kind = type(widgetOrAddr)
  local addr = (kind == "number" or kind == "string") and widgetOrAddr or UI.addr(widgetOrAddr)
  if addr == nil then return false end
  for _, e in ipairs(_overlayEntries) do
    for _, o in pairs(e.insts) do
      if not o.disposed then
        if kind ~= "number" and kind ~= "string" then
          if UI.actionFor(o.actions, widgetOrAddr) ~= nil then return true end
        elseif o.actions[addr] and UI.isOurs(addr) then return true end
      end
    end
  end
  return false
end

function UI.overlay(opts)
  local class, canvasN, pollMs = opts.class, opts.canvas, opts.pollMs or 1000
  -- short, readable name for logs: the trailing "WBP_Foo_C" rather than the whole asset path
  local className = tostring(class):match("([^/.]+)$") or tostring(class)
  local insts, gens = {}, {}
  if opts.onClick then
    _overlayEntries[#_overlayEntries + 1] = { insts = insts, onClick = opts.onClick }
    armOverlayClick()
  end

  local function sweep(keep)
    for a, o in pairs(insts) do
      if a ~= keep then
        o.disposed = true
        gens[a] = (gens[a] or 0) + 1
        for _, w in ipairs(o.widgets) do UI.setVis(w, UI.VIS.HIDE) end  -- SAFE: our canvas children only
        insts[a] = nil
      end
    end
  end

  -- GATE EVERY PATH INTO make(), not just the adopt poll.
  --
  -- The first cut put the adoptable test inside the adopt tick only, and the log disproved it
  -- in one launch: the Assignment Board still "built" eighteen seconds after load with a nil
  -- page root. NotifyOnNewObject fires for the CLASS DEFAULT OBJECT too -- it is an object of
  -- that class being created, which is exactly what the notification says. So the gate belongs
  -- here, where both paths meet.
  --
  -- One wrinkle that stops this being a plain rejection: a genuinely new page can be notified
  -- BEFORE its widget tree is populated, and rejecting it then would lose the page the
  -- notification was for. So a page without a root is RETRIED, not dropped -- and a CDO, which
  -- never grows a tree, simply runs out of retries and is forgotten. Nothing is built, and no
  -- refresh loop is ever started against it.
  local TREE_TRIES = 12          -- 12 x 250ms = 3s, far longer than a real page takes
  -- Assigned below, ARMED FROM make(): an instance existing is proof the class -- and its
  -- Construct/Destruct UFunctions -- are loaded, so arming there succeeds on the first try.
  -- The old timed-retry backoff spammed a full UE4SS error report per failed RegisterHook,
  -- every 5s, FOREVER, for any page class the session never loaded -- with visible stutter
  -- (Fararagi's Nexus bug report, 2026-07-31). Zero failed attempts is the fix, not a cap.
  local tryArmDestruct, tryArmConstruct
  local function make(menu, tries)
    local a = UI.addr(menu); if not a then return end
    -- "insts[a] exists" USED TO BE THE WHOLE TEST, which makes the address the identity -- the
    -- assumption phase 3 spent a merge dismantling for buttons. UE recycles allocator addresses,
    -- so a NEW page can land on one we already hold an instance for, and returning the old
    -- instance would leave us refreshing a corpse and never building on the live page. Compare
    -- the frozen key, and never hand back an instance that is disposed or from a past world.
    local menuKey = UI.objectKey(menu, a)
    local existing = insts[a]
    if existing then
      if not existing.disposed and existing.epoch == UI.worldEpoch()
          and menuKey ~= nil and existing.menuKey == menuKey then
        return existing
      end
      -- Same address, different page (or a dead one). Drop it rather than resurrect it: its
      -- buttons are registered under addresses the new page may reuse.
      existing.disposed = true
      gens[a] = (gens[a] or 0) + 1
      UI.forgetScope(existing.actions)
      -- HIDE THE OLD INSTANCE'S WIDGETS. On the re-adopt path (a page that Destructs per
      -- close and comes back per open) the previous build's widgets are still children of the
      -- page's canvas -- alive, visible, and layered exactly where the new build is about to
      -- put its own. Without this every open/close cycle stacked another full set: dead
      -- buttons over live ones is the orphaned-click factory, and the pile-up is this
      -- family's widget-volume crash pressure. Same safe operation sweep() uses -- only OUR
      -- tracked canvas children, visibility only, never RemoveFromParent on a native tree.
      for _, w in ipairs(existing.widgets or {}) do UI.setVis(w, UI.VIS.HIDE) end
      insts[a] = nil
    end
    if not UI.adoptable(menu) then
      local nm = safe(function() return menu:GetFullName() end) or "?"
      local shadow = false
      for _, bad in ipairs(UI.NOT_INSTANCE) do
        if nm:find(bad, 1, true) then shadow = true end
      end
      -- A shadow object is never going to become a page; a rootless real one might.
      if not shadow and (tries or 0) < TREE_TRIES then
        -- UI.defer, NOT raw ExecuteWithDelay (2026-07-28). This closure captures `menu`, a raw
        -- UObject wrapper, and make() dereferences it immediately via UI.addr/UI.adoptable. If
        -- the world went away during the 250ms the object is freed and that read is an access
        -- violation -- which pcall does not catch. UI.defer drops the task on an epoch change.
        UI.defer(250, function() pcall(make, menu, (tries or 0) + 1) end)
      elseif (tries or 0) == 0 then
        pcall(function() print("[DarnUI] " .. className .. ": ignored " .. nm .. " (not a constructed page)\n") end)
      end
      return
    end
    sweep(a)
    -- the accepted instance proves the class is loaded: arm the lifecycle hooks now
    if tryArmDestruct then tryArmDestruct() end
    if tryArmConstruct then tryArmConstruct() end
    -- NAME WHAT WE ACCEPTED. Two crashes were spent inferring which object an overlay had
    -- latched onto from the absence of a build line; one printed name would have settled it.
    pcall(function()
      print("[DarnUI] " .. className .. ": instance " ..
            (safe(function() return menu:GetFullName() end) or "?") .. "\n")
    end)
    -- menuKey freezes the page's native identity the same way a button's registration does
    -- (phase 3): address + GetFullName(), so a DIFFERENT page later occupying this address is
    -- distinguishable from the one we adopted. The adopt scan uses it below.
    local o = { menu = menu, menuKey = menuKey, epoch = UI.worldEpoch(),
                canvas = UI.findByName(menu, canvasN), actions = {}, widgets = {}, disposed = false }
    function o:place(w, x, y, sx, sy, z)
      if not UI.alive(w) then return false end
      if not UI.alive(self.canvas) then self.canvas = UI.findByName(self.menu, canvasN) end
      local ok = UI.canvasAdd(self.canvas, w, x, y, sx, sy, z)
      if ok then self.widgets[#self.widgets + 1] = w end
      return ok
    end
    function o:button(label, action) return UI.nativeButton(self.menu, label, self.actions, action) end

    -- PAGE CHROME. A page built only from buttons reads as a stack of floating strips -- which
    -- is exactly what Standing Orders looked like over the world (2026-07-27). DarnMenu never
    -- had the problem because the ESC menu supplies its own dim and framing; a page that takes
    -- over an in-world screen has to bring its own. These are the same primitives DarnMenu
    -- builds its panels from -- a tinted UMG.Image -- just reachable now.
    --
    -- Colours default to black so the common case (a backdrop, a backing panel, a divider) is
    -- one call. Everything constructed here is OURS: tracked for cleanup, safe to hide.
    function o:box(x, y, sx, sy, rgba, z)
      local tree = safe(function() return self.menu.WidgetTree end)
      local img = tree and UI.construct("/Script/UMG.Image", tree)
      if not UI.alive(img) then return nil end
      rgba = rgba or {}
      pcall(function()
        img:SetColorAndOpacity({ R = rgba.R or 0, G = rgba.G or 0, B = rgba.B or 0,
                                 A = rgba.A or 0.5 })
      end)
      if not self:place(img, x, y, sx, sy, z or 0) then return nil end
      return img
    end

    -- A full-canvas dim. Anchored to the canvas rather than sized in pixels, so it covers the
    -- screen at any resolution -- the thing a fixed rectangle cannot do.
    function o:backdrop(rgba, z)
      local tree = safe(function() return self.menu.WidgetTree end)
      local img = tree and UI.construct("/Script/UMG.Image", tree)
      if not UI.alive(img) then return nil end
      rgba = rgba or {}
      pcall(function()
        img:SetColorAndOpacity({ R = rgba.R or 0, G = rgba.G or 0, B = rgba.B or 0,
                                 A = rgba.A or 0.85 })
      end)
      if not UI.canvasFill(self.canvas, img, z or 0) then return nil end
      self.widgets[#self.widgets + 1] = img
      return img
    end

    -- A CENTRED HOST for a page's content.
    --
    -- Centring by arithmetic needs the viewport size, and the only way to ask for that goes
    -- through GetCachedGeometry -- a struct out-param getter, which is on the do-not-touch
    -- list that a CTD wrote. Anchors do it without asking: a slot anchored at 0.5/0.5 and
    -- aligned 0.5/0.5 is centred at every resolution, for free, forever.
    --
    -- Everything on the page then places INTO this host at coordinates relative to its own
    -- top-left, so the layout is written once and never has to know where the screen edges
    -- are. Resize it with UI.canvasResize as the content grows.
    function o:centerHost(sx, sy, z)
      local tree = safe(function() return self.menu.WidgetTree end)
      local panel = tree and UI.construct("/Script/UMG.CanvasPanel", tree)
      if not UI.alive(panel) then return nil end
      if not UI.canvasAddCenter(self.canvas, panel, sx, sy, z or 1) then return nil end
      self.widgets[#self.widgets + 1] = panel
      return panel
    end

    -- centred on the canvas, offset by (dx, dy) -- for anything that must sit relative to the
    -- game's own centred modal rather than to a screen corner
    function o:placeCentered(w, dx, dy, sx, sy, z)
      if not UI.alive(w) then return false end
      if not UI.alive(self.canvas) then self.canvas = UI.findByName(self.menu, canvasN) end
      local ok = UI.canvasAddCentered(self.canvas, w, dx, dy, sx, sy, z or 1)
      if ok then self.widgets[#self.widgets + 1] = w end
      return ok
    end

    -- CENTRE-ANCHORED chrome, for pages we do not own. o:box/o:label place at absolute
    -- coordinates, which is right inside a host we built and wrong on one of the game's own
    -- centred panels -- there, a fixed offset from the canvas origin drifts with the
    -- resolution. These take an offset from the middle instead.
    function o:boxCentered(dx, dy, sx, sy, rgba, z)
      local tree = safe(function() return self.menu.WidgetTree end)
      local img = tree and UI.construct("/Script/UMG.Image", tree)
      if not UI.alive(img) then return nil end
      rgba = rgba or {}
      pcall(function()
        img:SetColorAndOpacity({ R = rgba.R or 0, G = rgba.G or 0, B = rgba.B or 0,
                                 A = rgba.A or 0.5 })
      end)
      if not self:placeCentered(img, dx, dy, sx, sy, z) then return nil end
      return img
    end

    function o:labelCentered(text, dx, dy, sx, sy, size, alpha, z)
      local tree = safe(function() return self.menu.WidgetTree end)
      local tb = tree and UI.mkText(tree, UI.styleTemplate(self.menu), text or "", size, alpha)
      if not UI.alive(tb) then return nil end
      if not self:placeCentered(tb, dx, dy, sx, sy, z) then return nil end
      return tb
    end

    -- place into a host built above, rather than into the page's own canvas
    function o:placeIn(host, w, x, y, sx, sy, z)
      if not (UI.alive(host) and UI.alive(w)) then return false end
      local ok = UI.canvasAdd(host, w, x, y, sx, sy, z or 1)
      if ok then self.widgets[#self.widgets + 1] = w end
      return ok
    end

    -- a tinted rectangle inside a host
    function o:boxIn(host, x, y, sx, sy, rgba, z)
      local tree = safe(function() return self.menu.WidgetTree end)
      local img = tree and UI.construct("/Script/UMG.Image", tree)
      if not UI.alive(img) then return nil end
      rgba = rgba or {}
      pcall(function()
        img:SetColorAndOpacity({ R = rgba.R or 0, G = rgba.G or 0, B = rgba.B or 0,
                                 A = rgba.A or 0.5 })
      end)
      if not self:placeIn(host, img, x, y, sx, sy, z) then return nil end
      return img
    end

    function o:labelIn(host, text, x, y, sx, sy, size, alpha, z)
      local tree = safe(function() return self.menu.WidgetTree end)
      local tb = tree and UI.mkText(tree, UI.styleTemplate(self.menu), text, size, alpha)
      if not UI.alive(tb) then return nil end
      if not self:placeIn(host, tb, x, y, sx, sy, z) then return nil end
      return tb
    end

    -- An EDITABLE BOX in a host, so a page can offer "type the number" beside its steppers
    -- without reaching for the menu's WidgetTree itself. Same shape as labelIn/boxIn.
    --
    -- Pair it with UI.editText to read and UI.setEditText to write, and RE-APPLY UI.styleEdit
    -- on every refresh: PalEditableTextBox can stomp construction-time styling on its first
    -- paint, which renders as an invisible value in a box that is actually updating (see
    -- UI.styleEdit). mkEdit styles once; that is not enough on its own.
    function o:editIn(host, initial, x, y, sx, sy, z)
      local tree = safe(function() return self.menu.WidgetTree end)
      local eb = tree and UI.mkEdit(tree, initial)
      if not UI.alive(eb) then return nil end
      if not self:placeIn(host, eb, x, y, sx, sy, z) then return nil end
      return eb
    end

    -- Static text, styled from one of the game's own text blocks so it matches the UI rather
    -- than shipping a font of our own.
    function o:label(text, x, y, sx, sy, size, alpha, z)
      local tree = safe(function() return self.menu.WidgetTree end)
      local tb = tree and UI.mkText(tree, UI.styleTemplate(self.menu), text, size, alpha)
      if not UI.alive(tb) then return nil end
      if not self:place(tb, x, y, sx, sy, z or 0) then return nil end
      return tb
    end
    function o:show(w) UI.setVis(w, UI.VIS.SHOW) end
    function o:hide(w) UI.setVis(w, UI.VIS.HIDE) end
    insts[a] = o
    if opts.onClick then armOverlayClick() end   -- retry-arm now the menu (and button class) are loaded
    gens[a] = (gens[a] or 0) + 1
    local myGen = gens[a]
    -- REPORT WHAT THE pcall SWALLOWS.
    --
    -- A build or refresh that raises used to die in silence, once a second, forever. Standing
    -- Orders read an undeclared upvalue in its refresh (a half-applied edit) and the page simply
    -- froze in its build state: rows blank, pager showing when it should not, everything after
    -- the error never running. Nothing in the log, nothing in any gate -- a lint cannot see a
    -- nil global inside a closure that never executes at load.
    --
    -- Logged ONCE per instance per callback: an error every second is noise nobody reads, and
    -- the first occurrence is the one that names the line.
    local function guard(fn, what, host)
      local ok, err = pcall(fn, host)
      if not ok and not o["_told" .. what] then
        o["_told" .. what] = true
        pcall(function() print("[DarnUI] " .. className .. " " .. what .. " ERROR: "
                               .. tostring(err) .. "\n") end)
      end
      return ok
    end
    -- FIRST BUILD MAY WAIT OUT THE HOST'S ENTRY ANIMATION (opts.buildDelayMs; CTD patch
    -- 2026-08-03, folded to shared-src after two publishes wiped the installed copy). A page
    -- still animating in cannot take native widget churn in its construct frame -- the
    -- Standing Orders bench page died inside Slate layout when built at the construct
    -- instant. A consumer that knows its host animates passes buildDelayMs; the deferred
    -- build re-checks that this exact instance (generation and identity) is still the live
    -- one. Default 0 builds inline, unchanged.
    if opts.build then
      local d = tonumber(opts.buildDelayMs) or 0
      if d > 0 then
        UI.defer(d, function()
          if gens[a] ~= myGen then return end
          if o.disposed or not UI.alive(o.menu) then return end
          guard(opts.build, "build", o)
        end)
      else
        guard(opts.build, "build", o)
      end
    end
    -- FAST FIRST PAINT: the menu's child widgets populate a beat after construct,
    -- so refresh immediately + a quick burst, THEN settle into the steady pollMs
    -- cadence -- avoids the ~1s-late appearance without polling fast forever.
    -- YIELD WHILE ANOTHER MOD OWNS THE SCREEN (opts.yieldWhenHidden).
    --
    -- Overlays anchor to the menu ROOT (CanvasPanel_0) so they survive the game hiding
    -- inner panels. That is exactly why a full-screen page from ANOTHER mod does not hide
    -- them: DarnMenu hides the menu's own inner canvases when its options page opens, but
    -- it cannot hide the root without hiding its own page too -- so Living Arsenal's
    -- prestige badge kept floating over DarnMenu's page (reported in play 2026-07-27).
    --
    -- Neither mod should reach into the other (Mikey's ownership rule: DarnMenu owns the
    -- ESC entry button and its page, Living Arsenal owns the badge and star). So the
    -- overlay watches a widget belonging to THE GAME -- name it via opts.yieldWhenHidden --
    -- and when the game's own panel is hidden, something has taken the screen and we stand
    -- down. No cross-mod channel, no shared state, and it works for any future consumer.
    --
    -- Only OUR canvas children are touched, and only ones we find currently SHOWN, so the
    -- restore cannot reveal something the consumer deliberately hid (an ineligible badge
    -- must stay hidden when the page closes).
    -- TEST FOR *HIDDEN*, NOT FOR "NOT SHOWN". UMG visibility has five values, and a native
    -- canvas commonly sits at SelfHitTestInvisible (4) in normal use -- perfectly visible.
    -- The first cut of this asked `~= SHOW`, which read PASSIVE as "someone took the
    -- screen", so the overlay yielded permanently and the prestige badge never appeared at
    -- all (caught in play immediately). Only Collapsed (1) and Hidden (2) mean gone;
    -- DarnMenu collapses with UI.VIS.HIDE. Unreadable widget -> do NOT yield: a missing
    -- badge is a worse failure than one that lingers.
    local function screenTaken()
      if not opts.yieldWhenHidden then return false end
      return UI.isHidden(UI.findByName(o.menu, opts.yieldWhenHidden))
    end

    local function fire()
      -- World tearing down: skip the refresh but KEEP the loop alive, so it resumes
      -- by itself when the next map is up. See MAP-BOUNDARY STAND-DOWN below.
      if UI.worldIsGone() then return true end
      if o.disposed or (gens[a] or 0) ~= myGen or not UI.alive(o.menu) then return false end
      local taken = screenTaken()
      if taken ~= (o._yielded == true) then
        if taken then
          o._restore = {}
          for _, w in ipairs(o.widgets) do
            if UI.isVisible(w) then
              -- keep the EXACT value: a PASSIVE widget restored as SHOW would come back
              -- hit-testable, which is not what its owner asked for
              o._restore[#o._restore + 1] = { w = w, vis = safe(function() return w.Visibility end) }
              UI.setVis(w, UI.VIS.HIDE)          -- SAFE: our own canvas children only
            end
          end
        else
          for _, r in ipairs(o._restore or {}) do UI.setVis(r.w, r.vis or UI.VIS.SHOW) end
          o._restore = nil
        end
        o._yielded = taken
      end
      if taken then return true end   -- stood down; keep the loop alive so we come back
      -- REFRESH ONLY WHILE THE PAGE IS OPEN (opts.activeOnly).
      --
      -- The loop's liveness test is "is the menu widget alive", which was exactly right when
      -- every host page was constructed on open and destructed on close. opts.adopt broke
      -- that assumption on purpose: the pages it exists for are built ONCE and then shown and
      -- hidden, so they stay alive for the rest of the session -- and refresh kept firing
      -- once a second for the rest of the session with them.
      --
      -- The cost is not just wasted work. Consumers use refresh as a HEARTBEAT meaning "my
      -- page is on screen" (Standing Orders arms order-creation while the craft page is open,
      -- and gates a keybind on the Assignment Board being up). A heartbeat that never stops
      -- means an arm that never expires and a key that is live during normal play -- the
      -- precise failure a heartbeat was chosen to prevent.
      if opts.activeOnly then
        -- Re-check provenance before walking a parent chain once a second for the life of the
        -- overlay. make() already established it, but a page can be torn down under us, and
        -- this is the last place that should be dereferencing an object we are unsure of.
        -- Unsure reads as CLOSED here: skipping a refresh is recoverable, a bad walk is not.
        local open = UI.adoptable(o.menu) and UI.onScreen(o.menu)
        if open ~= (o._open ~= false) then    -- log the edges only, not once a second
          o._open = open
          pcall(function() print("[DarnUI] " .. tostring(className) .. (open and " opened\n" or " closed\n")) end)
        end
        if not open then return true end      -- closed: skip the work, keep the loop
      end
      if opts.refresh then guard(opts.refresh, "refresh", o) end
      return true
    end
    fire()
    for _, d in ipairs({ 100, 250, 450, 750 }) do ExecuteWithDelay(d, fire) end
    local function loop() ExecuteWithDelay(pollMs, function() if fire() then loop() end end) end
    loop()
    return o
  end

  -- ADOPT EXISTING PAGES (opts.adopt). NotifyOnNewObject only fires for widgets the game
  -- constructs AFTER we hook it. The ESC menu is rebuilt every time, so notification alone is
  -- enough there -- but Palworld's IngameMenu pages (WorkSpace, Monitoring, AssignBoard) are
  -- built once and then shown/hidden, so a mod that starts after they exist waits forever.
  -- This poll adopts any live instance we have not seen. Deliberately slow (2s): it is a
  -- safety net, not a hot path, and each instance is adopted exactly once.
  if opts.adopt then
    -- SCAN ONLY A SETTLED WORLD (CTD patch 2026-08-03, crash UECC-...496213F0, 86s into a
    -- fresh session; folded to shared-src after a publish wiped the installed copy). The
    -- short-name fix above brought this poll to life for the first time, and its first world
    -- JOIN died at the FindAllOf walk: during streaming, instances of the page class from the
    -- outgoing world are exactly what FindAllOf returns, and UI.adoptable/UI.objectKey walking
    -- one read 0xffffffffffffffff -- a poisoned pointer no pcall or IsValid gate stops. So:
    -- after any epoch change, sit out three ticks (~6s) before touching natives again.
    -- Steady-state behaviour is unchanged -- bench close/open does not flip the epoch, so
    -- re-adoption still lands on the next tick.
    local adoptEpoch, adoptStable = nil, 0
    local function adoptTick()
      pcall(function()
        -- walkSafe, not just worldIsGone: the boot/join stand-down (see its comment). The
        -- epoch-settle below stays as the second gate for mid-session world churn.
        if UI.walkSafe() then
          local ep = UI.worldEpoch()
          if ep ~= adoptEpoch then adoptEpoch = ep; adoptStable = 0; return end
          adoptStable = adoptStable + 1
          if adoptStable < 3 then return end
          -- THE SHORT NAME, not the full asset path. Every working FindAllOf in this family
          -- passes a short class name ("PalMapObjectConvertItemModel"); overlays register with
          -- the full "/Game/....WBP_Foo_C" path, and FindAllOf given that form returns nothing
          -- -- silently, forever. Measured 2026-07-30: a disposed workspace page sat adoptable
          -- through ~27 consecutive ticks of this poll and was never seen; every adoption in
          -- the logs traces to NotifyOnNewObject instead. The poll was a no-op since the day
          -- it was written, which also explains why nobody ever saw its CDO-rejection lines.
          local found = safe(function() return FindAllOf(className) end) or {}
          -- a real page class has a handful of instances; dozens = a torn registry, walk nothing
          if #found > 64 then return end
          for _, w in ipairs(found) do
            local a = UI.adoptable(w) and UI.addr(w)
            -- RE-ADOPT WHEN THE OBJECT AT A KNOWN ADDRESS IS A DIFFERENT PAGE (virtualbjorn,
            -- merged 2026-07-28). "not insts[a]" alone treats the address as the identity, which
            -- is the assumption phase 3 spent a whole merge dismantling for buttons: UE recycles
            -- allocator addresses, so a NEW page can land on one we already hold an instance for.
            -- We would then keep refreshing a dead instance and never build on the live page.
            -- Comparing the frozen objectKey distinguishes them.
            local key = a and UI.objectKey(w, a)
            local existing = a and insts[a]
            -- RE-ADOPT A DISPOSED INSTANCE WHOSE PAGE STILL EXISTS (2026-07-30). Palworld's
            -- IngameMenu pages fire Destruct on every CLOSE and Construct on every OPEN while
            -- the UWidget lives on -- so the Destruct hook above disposed the overlay on the
            -- first bench close, and this condition ("same page, already have it") then refused
            -- to ever adopt it again. Every later open ran against the corpse: refresh stopped,
            -- and clicks on a still-visible button dispatched nowhere. THIS single line was the
            -- mechanism behind Standing Orders' "the SO chip works once and never again",
            -- misdiagnosed four releases running -- proven by the orphaned-click report
            -- ("0 live overlay(s), 1 disposed", 2026-07-30 20:10). A disposed instance for a
            -- page that is alive and adoptable is precisely a page that came back.
            if a and key and (not existing or existing.disposed or existing.menuKey ~= key) then pcall(make, w) end
          end
        end
      end)
      ExecuteWithDelay(2000, adoptTick)
    end
    pcall(function() ExecuteWithDelay(1500, adoptTick) end)
  end

  pcall(function()
    NotifyOnNewObject(class, function(menu) pcall(make, menu) end)
  end)

  -- ARM THE DESTRUCT HOOK, AND VERIFY IT ARMED (virtualbjorn, merged 2026-07-28).
  --
  -- This used to be one `pcall(RegisterHook, class .. ":Destruct", fn)` whose result was never
  -- looked at. pcall succeeding only means the CALL did not raise -- RegisterHook returns nil
  -- ids when the UFunction is not loaded yet, which is entirely normal for a page class the
  -- game has not constructed once. The hook then silently never existed.
  --
  -- That was survivable when the hook only set a flag our refresh loop re-derives anyway. It is
  -- not survivable now: this hook is what purges the button registrations (phase 4), so an
  -- unarmed hook means every button of every closed page leaks until the next map change, with
  -- nothing in the log to say so. The ids are still verified -- but arming happens from
  -- make(), never on a timer: see the note above make() for the retry-spam this replaced.
  local destructArmed, destructIds = false, {}
  local function onDestruct(Context)
    -- Context:get() hands back a FRESH wrapper after the UFunction; UI.addr reads that
    -- wrapper's stored pointer without dereferencing the UObject that is tearing down.
    local m = safe(function() return Context:get() end)
    local a = m and UI.addr(m)
    local o = a and insts[a]
    if not o then return end
    o.disposed = true; gens[a] = (gens[a] or 0) + 1
    -- SAY SO. The adopt path prints one line per instance; disposal printed NOTHING, and that
    -- asymmetry is why "the overlay died on the first bench close" was invisible for five
    -- releases -- the log showed pages being born and never showed one dying. One line here
    -- would have cracked the SO-chip saga in its first session (2026-07-30). No UObject is
    -- read: the page is tearing down and only our own Lua state is touched.
    pcall(function() print("[DarnUI] " .. className .. " disposed (Destruct)\n") end)
    -- PURGE THE REGISTRATIONS TOO (2026-07-28). Marking the instance disposed stops our own
    -- refresh loop, but every button this page built stays in UI.ourButtons/buttonRefs/
    -- buttonRegs and in this scope's actionRefs/actionRegs until the next map change, each
    -- holding a strong reference to a wrapper for a widget that is being destroyed right now.
    UI.forgetScope(o.actions)
  end

  tryArmDestruct = function()
    if destructArmed then return true end
    if UI.worldIsGone() or type(_G.RegisterHook) ~= "function" then return false end
    local okHook, preId, postId = pcall(_G.RegisterHook, class .. ":Destruct", onDestruct)
    -- BOTH ids must come back. A nil id is UE4SS saying the UFunction was not resolved.
    if not (okHook and preId ~= nil and postId ~= nil) then return false end
    destructIds[1], destructIds[2] = preId, postId
    destructArmed = true
    return true
  end

  -- RE-ADOPTION IS EVENT-DRIVEN: Construct is the mirror of Destruct (2026-07-30).
  --
  -- Palworld's IngameMenu pages Slate-destruct on every CLOSE and re-construct on every OPEN
  -- while the UWidget lives on. Destruct disposes the overlay (correctly -- its buttons'
  -- registrations must not outlive the Slate tree they point into), so something must bring
  -- it BACK, and the page's own Construct event is that something: it fires exactly when the
  -- page returns, carries the page instance, and needs no poll. make() dedupes, so a page
  -- that is already live (first open: NotifyOnNewObject got there first) is a no-op here.
  --
  -- Deferred off the hook's C++ frame by a beat rather than built inline: the page is
  -- mid-construction when Construct fires, and the overlay's fast-paint burst tolerates a
  -- widget tree that populates a moment later. UI.defer drops the task on a world change, so
  -- the captured wrapper is never dereferenced across a map boundary.
  --
  -- Gated on opts.adopt: pages that are genuinely destroyed and recreated (the ESC menu) get
  -- a fresh instance through NotifyOnNewObject already; this exists for the shown/hidden
  -- pages that adopt was built for.
  if opts.adopt then
    local constructArmed = false
    tryArmConstruct = function()
      if constructArmed then return true end
      if UI.worldIsGone() or type(_G.RegisterHook) ~= "function" then return false end
      local okHook, preId, postId = pcall(_G.RegisterHook, class .. ":Construct", function(Context)
        local m = safe(function() return Context:get() end)
        if m == nil then return end
        UI.defer(100, function() pcall(make, m) end)
      end)
      if not (okHook and preId ~= nil and postId ~= nil) then return false end
      constructArmed = true
      return true
    end
  end

  return { instances = insts, destructArmed = function() return destructArmed end,
           destructHookIds = destructIds }
end

-- ---- walking a native widget's insides ------------------------------------
--
-- WHY THIS IS SAFE, given the contract at the top of this file. Two rules govern it:
--
--   READ BY PROPERTY OR BY PLAIN GETTER. GetChildrenCount() returns an int and GetChildAt()
--   returns a widget pointer. Neither is a struct OUT-PARAM getter, which is the family that
--   native-write-crashes (GetItemAndNum, GetCachedGeometry, Slot reads). A UserWidget's own
--   children hang off .WidgetTree.RootWidget, read with UI.get.
--
--   FADE, NEVER HIDE. SetVisibility on a widget living inside a native layout container forces
--   a reflow, and a reflow during a live menu is an access violation -- that is the rule that
--   cost a CTD. RenderOpacity is a PAINT property: it changes what is drawn and nothing about
--   layout, so it is the one safe way to make native chrome go away.

function UI.name(w)
  local s = nil
  pcall(function() s = w:GetFullName() end)
  return s and tostring(s) or "?"
end

-- Depth- and count-bounded so a cyclic or enormous tree cannot wedge the frame.
function UI.walkTree(root, visit, maxDepth, maxNodes)
  if not UI.alive(root) then return 0 end
  maxDepth, maxNodes = maxDepth or 8, maxNodes or 240
  local seen = 0
  local function go(w, depth)
    if not UI.alive(w) or depth > maxDepth or seen >= maxNodes then return end
    seen = seen + 1
    if visit then pcall(visit, w, depth) end
    -- a UserWidget keeps its children under WidgetTree, not on itself
    local rootW = UI.get(w, "WidgetTree.RootWidget")
    if UI.alive(rootW) then go(rootW, depth + 1) end
    local n = 0
    pcall(function() n = w:GetChildrenCount() end)
    if type(n) == "number" and n > 0 then
      for i = 0, n - 1 do
        local child = nil
        pcall(function() child = w:GetChildAt(i) end)
        if UI.alive(child) then go(child, depth + 1) end
      end
    end
  end
  go(root, 0)
  return seen
end

-- See the note above: opacity, not visibility. `alpha` defaults to 0; pass 1 to put a faded
-- widget back, which is what a REUSED widget pool needs -- a row that was a heading a moment ago
-- has to look like an ordinary row again.
function UI.fadeOut(w, alpha)
  if not UI.alive(w) then return false end
  local ok = false
  pcall(function() w:SetRenderOpacity(alpha or 0.0); ok = true end)
  return ok
end

-- Fade every descendant whose full name contains one of `names` (plain substrings, not
-- patterns). Returns how many were faded, so a caller can log "matched nothing" rather than
-- silently doing nothing -- a decoration list that stops matching after a game patch should be
-- visible in the log, not just visible on screen.
-- Split out so the matching itself is testable without a game: over-matching here would not
-- tidy a button, it would erase one, so which names hit and which are left alone is pinned.
function UI.decorMatch(fullName, names)
  if not (fullName and names) then return false end
  for _, pat in ipairs(names) do
    if fullName:find(pat, 1, true) then return true end
  end
  return false
end

function UI.fadeDecor(root, names, alpha)
  if not names or #names == 0 then return 0 end
  local n = 0
  UI.walkTree(root, function(w)
    if UI.decorMatch(UI.name(w), names) then
      if UI.fadeOut(w, alpha) then n = n + 1 end
    end
  end)
  return n
end

-- WHAT IS ACTUALLY INSIDE ONE OF THESE? Read-only dump, for finding the name of a piece of
-- native chrome so it can be listed in UI.buttonDecor. Never left running in a release path --
-- it is a few hundred log lines.
function UI.dumpTree(root, logf, label)
  if not (UI.alive(root) and logf) then return 0 end
  logf("widget tree dump: %s", tostring(label or UI.name(root)))
  local n = UI.walkTree(root, function(w, d)
    logf("  %s%s", string.rep("| ", d), UI.name(w))
  end)
  logf("widget tree dump: %d node(s)", n)
  return n
end

-- DECORATION TO SUPPRESS ON EVERY BUTTON WE CLONE.
--
-- The ESC-menu blueprint brings four corner marks (Images named Dot_0..Dot_3). At its native
-- size they read as a deliberate accent; on a button stretched to a full row they read as stray
-- white pixels, which is how they were reported in play on 2026-07-30.
--
-- A NAME, NOT A POLICY. Nothing applies this for you: pass it to UI.fadeDecor on the specific
-- buttons where the marks read as stray pixels -- a button stretched across a full row -- and
-- leave the rest alone. At its native size the decoration is a deliberate accent, and a button
-- whose state the player reads (a selected tab, an armed toggle) should keep every visual it has.
--
-- Named from a UI.dumpTree of the real blueprint, never guessed: Base, Frame, FocusFrame and
-- Text_Main are the button ITSELF and are deliberately absent from this list -- see UI.decorMatch
-- and its tests, which pin exactly that split.
UI.buttonDecor = { ".Dot_" }

-- ORPHANED-CLICK REPORTING. A consumer sets UI.orphanLog to its own log function to hear about
-- a click that landed on one of OUR buttons and matched no action. Off unless set, because the
-- kit has no logger of its own and must not print into somebody else's stream uninvited.
UI.orphanLog = nil
UI.orphanSeen = {}

-- RESTYLE A LABEL AFTER IT IS BUILT. Both of these exist because a fixed widget POOL reuses the
-- same label for different jobs -- row 3 is a section heading on one page and an order on the
-- next -- so the style has to be a property you can set, not something decided at construction.
--
-- TEXT COLOUR IS NOT IMAGE COLOUR. A TextBlock wants an FSlateColor
-- ({ SpecifiedColor = ..., ColorUseRule = 0 }); an Image wants a plain FLinearColor. Passing the
-- image form to a TextBlock silently does nothing, which is why UI.goldTint (an image helper)
-- must not be reached for here.
function UI.textTint(w, rgba)
  if not UI.alive(w) then return end
  pcall(function()
    w:SetColorAndOpacity({ SpecifiedColor = { R = rgba.R or 1, G = rgba.G or 1,
                                              B = rgba.B or 1, A = rgba.A or 1 },
                           ColorUseRule = 0 })
  end)
end

-- READ, MUTATE, WRITE BACK. The Font property is a struct; setting w.Font.Size directly writes to
-- a temporary copy and is silently lost, so the whole struct has to go back through SetFont.
function UI.textSize(w, size)
  if not UI.alive(w) or not size then return end
  pcall(function()
    local f = w.Font
    f.Size = size
    w:SetFont(f)
  end)
end

-- Darn "prestige gold" tint, reused by the ESC badge + inventory star.
function UI.goldTint(w) if UI.alive(w) then pcall(function() w:SetColorAndOpacity({ R = 1.0, G = 0.78, B = 0.28, A = 1.0 }) end) end end

-- Reusable option-tile popup for an overlay surface -- the exact discipline the
-- prestige badge + inventory star both needed (and each got wrong independently
-- before this was factored out):
--   * build tiles ONLY on open, and ONLY from a NON-EMPTY option set
--   * NEVER cache an empty popup (a poll before the data is ready must not wedge it)
--   * route tile clicks back through the overlay's OWN click dispatch
-- Layout stays the caller's -- position(tile, i) pins the i-th tile however it likes
-- (canvas SetPosition, bottom-right anchor, ...). opts:
--   options()          -> { {value,label}, ... } offerable NOW (empty => don't build)
--   size = {w, h[, z]}    tile dimensions (z default 55)
--   position(tile, i)     position the i-th tile (called on build AND every open)
--   onPick(value)         a tile was chosen
-- Returns p with: p:toggle() / p:open() / p:close() / p:isOpen() / p:reset(), and
-- p:route(action) -- call it from the overlay onClick; true if it consumed the click.
-- ---- UI.card: the dashboard tile, as a reusable component ------------------
-- A TITLED PANEL WITH A HEADLINE AND SOME QUIET LINES UNDER IT. Standing Orders' Home
-- dashboard invented this shape, and then a second page in the same mod wanted it -- which is
-- when it stopped being that mod's business. It had become two hand-written layouts and two
-- hand-written fill sites, and only one of the two was written correctly. The bug that
-- produced -- a page showing another page's numbers, silently -- is the exact failure a
-- component prevents, because there is only ever one way to put text into one.
--
-- BUILT ONCE, FILLED MANY TIMES. UI.card constructs; card:set injects content and card:place
-- decides geometry, and neither ever builds a widget. Rebuilding widgets inside a live menu is
-- where this family of mods' crashes come from, so the component makes the cheap thing the
-- easy thing: a caller that only calls set/place cannot churn widgets even by accident.
--
-- THE CALLER OWNS THE GRID -- how many columns, how tall, where they start. That is page
-- policy and differs per page. The card owns everything inside its own rectangle.
function UI.card(o, host, opts)
    if not (o and UI.alive(host)) then return nil end
    opts = opts or {}
    local c = { o = o }
    local dim = opts.bg or { R = 0.008, G = 0.02, B = 0.045, A = 0.55 }
    c.bg   = o:boxIn(host, 0, 0, 10, 10, dim, 2)
    -- the header band: a textured image over a flat fallback box, so a host without the
    -- texture degrades to a plain band rather than to nothing
    c.head = o:boxIn(host, 0, 0, 10, 34, { R = 0, G = 0, B = 0, A = 0.30 }, 2)
    local tree = UI.alive(o.menu) and o.menu.WidgetTree or nil
    c.headTex = (UI.mkImage and tree) and UI.mkImage(tree) or nil
    if c.headTex then o:placeIn(host, c.headTex, 0, 0, 10, 34, 2) end
    c.bar  = o:boxIn(host, 0, 0, 10, 3, opts.accent or { R = 0.5, G = 0.5, B = 0.5, A = 1 }, 4)
    -- THE WHOLE CARD IS THE BUTTON. A tile with a small hit area in one corner is a tile
    -- players report as unclickable. The action belongs to the caller, so a card that is only
    -- ever read simply passes none and gets no button at all.
    if opts.action then
        c.btn = o:button("", opts.action)
        if c.btn then
            o:placeIn(host, c.btn, 0, 0, 10, 10, 3)
            pcall(function()
                if opts.decor then UI.fadeDecor(c.btn, opts.decor) end
                if opts.hdrHide then UI.fadeDecor(c.btn, opts.hdrHide, 0.10) end
            end)
        end
    end
    c.title = o:labelIn(host, opts.title or "", 0, 0, 10, 20, 14, 0.92, 5)
    c.icon  = (UI.mkImage and tree) and UI.mkImage(tree) or nil
    if c.icon then o:placeIn(host, c.icon, 0, 0, 22, 22, 5) end
    c.big  = o:labelIn(host, "", 0, 0, 10, 46, 30, 1.0, 5)
    c.lines = {}
    for i = 1, 4 do
        c.lines[i] = o:labelIn(host, "", 0, 0, 10, 20, 13, 0.8, 5)
        pcall(function()
            UI.textTint(c.lines[i], opts.quiet or { R = 0.72, G = 0.80, B = 0.90, A = 0.85 })
        end)
    end

    -- EVERY WIDGET IN ONE LIST, so show/hide cannot forget one. A hand-written enumeration
    -- beside the build is exactly the thing that drifts away from it.
    c.all = {}
    for _, w in ipairs({ c.bg, c.head, c.headTex, c.bar, c.btn, c.title, c.icon, c.big,
                         c.lines[1], c.lines[2], c.lines[3], c.lines[4] }) do
        c.all[#c.all + 1] = w
    end
    for _, w in ipairs(c.all) do UI.setVis(w, UI.VIS.HIDE) end

    -- THE ONE WAY TO PUT TEXT IN A CARD. These are TextBlocks, so SetText -- never
    -- UI.setLabel, which writes a BUTTON's Text_Main inside a pcall and is a silent no-op on
    -- anything else. That mistake cost a page that convincingly showed another page's
    -- content; one setter is how it stops being possible to make twice.
    local function put(w, s)
        if UI.alive(w) then pcall(function() w:SetText(FText(tostring(s or ""))) end) end
    end

    function c:set(d)
        d = d or {}
        if d.title ~= nil then put(self.title, d.title) end
        if d.value ~= nil then put(self.big, d.value) end
        if d.lines ~= nil then
            for i = 1, 4 do put(self.lines[i], d.lines[i]) end
        end
        if d.accent and UI.alive(self.bar) then
            pcall(function() self.bar:SetColorAndOpacity(d.accent) end)
        end
        -- TEXTURES ARE SET ON CHANGE, not per fill: SetBrushFromTexture every pass is a native
        -- write per card per repaint for a picture that never changes.
        -- icon = false means THIS CARD HAS NO BADGE, which is a different statement from
        -- "the texture is missing" and has to survive show(): a card whose caller passes no
        -- icon must not have one revealed for it. Tracked here so no caller ever reaches past
        -- set/place/show to a widget of its own.
        if d.icon ~= nil and self.iconTex ~= d.icon then
            self.iconTex = d.icon
            self.noIcon = (d.icon == false or d.icon == nil) and true or nil
            if UI.alive(self.icon) and d.icon and UI.alive(d.icon) then
                pcall(function() self.icon:SetBrushFromTexture(d.icon, false) end)
            end
        end
        if d.headTexture ~= nil and self.headBrush ~= d.headTexture then
            self.headBrush = d.headTexture
            if UI.alive(self.headTex) and d.headTexture and UI.alive(d.headTexture) then
                pcall(function() self.headTex:SetBrushFromTexture(d.headTexture, false) end)
            end
        end
        return self
    end

    -- GEOMETRY. The style numbers are the ones that genuinely differ between pages: a card
    -- showing a COUNT wants its value set large, a card showing a SENTENCE does not, and a
    -- sentence set at a count's size wraps straight out of its own box.
    function c:place(x, y, w, h, style)
        style = style or {}
        local pad  = style.pad or 16
        local vy   = style.valueY or 42
        local vh   = style.valueH or 46
        local ly   = style.linesY or (vy + vh + 4)
        local step = style.lineStep or 26
        local lh   = style.lineH or 20
        UI.canvasMove(self.bg, x, y);      UI.canvasResize(self.bg, w, h)
        UI.canvasMove(self.head, x, y);    UI.canvasResize(self.head, w, 34)
        UI.canvasMove(self.headTex, x, y); UI.canvasResize(self.headTex, w, 34)
        UI.canvasMove(self.bar, x, y);     UI.canvasResize(self.bar, w, 3)
        UI.canvasMove(self.btn, x, y);     UI.canvasResize(self.btn, w, h)
        UI.canvasMove(self.title, x + pad, y + 14)
        UI.canvasResize(self.title, w - pad - 40, 20)
        UI.canvasMove(self.icon, x + w - 38, y + 14); UI.canvasResize(self.icon, 22, 22)
        UI.canvasMove(self.big, x + pad, y + vy);     UI.canvasResize(self.big, w - 2 * pad, vh)
        for i = 1, 4 do
            UI.canvasMove(self.lines[i], x + pad, y + ly + (i - 1) * step)
            UI.canvasResize(self.lines[i], w - 2 * pad, lh)
        end
        return self
    end

    -- SHOW OR HIDE THE WHOLE CARD. Everything but the button is PASSIVE, never SHOW: a
    -- hit-testable label sitting over a button eats that button's clicks, which is how a
    -- whole list once became unpressable.
    function c:show(on, headerTextured)
        for _, w in ipairs(self.all) do
            if w ~= self.btn then
                UI.setVis(w, on and UI.VIS.PASSIVE or UI.VIS.HIDE)
            end
        end
        UI.setVis(self.btn, on and UI.VIS.SHOW or UI.VIS.HIDE)
        if self.noIcon then UI.setVis(self.icon, UI.VIS.HIDE) end
        -- the flat band shows only when the texture is not carrying the header
        if headerTextured ~= nil then
            UI.setVis(self.headTex, (on and headerTextured) and UI.VIS.PASSIVE or UI.VIS.HIDE)
            UI.setVis(self.head, (on and not headerTextured) and UI.VIS.PASSIVE or UI.VIS.HIDE)
        end
        return self
    end

    -- DID EVERY PART SURVIVE CONSTRUCTION? A card with a nil label silently drops whatever is
    -- written to it, so a caller filling a grid asks this once rather than inferring it from
    -- a page that merely looks half-finished.
    function c:whole()
        if not (UI.alive(self.bg) and UI.alive(self.title) and UI.alive(self.big)) then
            return false
        end
        for i = 1, 4 do
            if not UI.alive(self.lines[i]) then return false end
        end
        return true
    end

    return c
end

function UI.tilePopup(o, opts)
  local W, H, Z = opts.size[1], opts.size[2], opts.size[3] or 55
  local p = { isopen = false, tiles = nil }
  local function build()
    local tiles = {}
    for i, opt in ipairs(opts.options() or {}) do
      local tile = o:button(opt.label, { __tilepop = p, value = opt.value })
      if tile then
        UI.setVis(tile, UI.VIS.HIDE)
        o:place(tile, 0, 0, W, H, Z)   -- add to the overlay canvas; position() pins it
        opts.position(tile, i)
        tiles[#tiles + 1] = tile
      end
    end
    if #tiles > 0 then p.tiles = tiles end   -- never cache an empty popup
  end
  function p:isOpen() return self.isopen end
  function p:close()
    self.isopen = false
    for _, t in ipairs(self.tiles or {}) do UI.setVis(t, UI.VIS.HIDE) end
  end
  function p:open()
    self.isopen = true
    if not (self.tiles and #self.tiles > 0) then build() end
    for i, t in ipairs(self.tiles or {}) do opts.position(t, i); UI.setVis(t, UI.VIS.SHOW) end
  end
  function p:toggle() if self.isopen then self:close() else self:open() end end
  function p:reset() self:close(); self.tiles = nil end   -- drop cache -> next open rebuilds (options changed)
  function p:route(action)
    if type(action) == "table" and action.__tilepop == p then
      opts.onPick(action.value); self:close(); return true
    end
    return false
  end
  return p
end

-- Journal-style, scrollable generic selector. This deliberately recreates the
-- presentation from safe primitives instead of borrowing WBP_Option_Note:
-- no native Journal state is modified and the caller retains ordinary action
-- dispatch through UI.nativeButton.
--
-- Required: opts.menu, widgetTree, parent(CanvasPanel), actions, items
--   items = { { label = "Mod name", action = { type = "tab", index = 1 } }, ... }
-- Optional: x/y/width/height/rowH/header/z/textTemplate/countText/onCreateRow
-- Returns c with .root/.scroll/.canvas/.buttons/.viewH and:
--   c:setSelected(index), c:focus(index), c:remove()
-- ONE SCROLLBOX RECIPE, not five.
--
-- ScrollBox -> SizeBox -> CanvasPanel is the only shape that scrolls in this stack: UE4SS
-- exposes no wheel key at all (the mouse table is left / right / middle-BUTTON and X1/X2), so
-- a ScrollBox ANCESTOR is the sole route to wheel input and no keybind can substitute. That
-- recipe had been hand-written in four places -- selectorList below, the dropdown, and two
-- lists in DarnMenu -- and StandingOrders was about to become the fifth. Same class of
-- duplication as the weapon-library lookup that silently lost a whole family's XP: four
-- copies, and only the one you happen to be looking at ever gets the fix.
--
-- contentH IS WHAT MAKES IT SCROLL. The content must be TALLER than the viewport or the
-- engine has nothing to move; passing contentH <= h yields a ScrollBox that simply sits there.
-- Callers that virtualise (a fixed row pool with the canvas counter-translated) pass the
-- VIRTUAL height here and move the canvas themselves.
--
-- Returns scroll, sizeBox, canvas -- place children on the CANVAS. Everything is torn down
-- together by removing the scroll box, so callers only need to track that one.
function UI.scrollHost(tree, parent, x, y, w, h, contentH, z)
  if not (tree and parent) then return nil end
  local scroll  = UI.construct("/Script/UMG.ScrollBox", tree)
  local sizeBox = UI.construct("/Script/UMG.SizeBox", tree)
  local canvas  = UI.construct("/Script/UMG.CanvasPanel", tree)
  if not (UI.alive(scroll) and UI.alive(sizeBox) and UI.alive(canvas)) then
    UI.remove(scroll); return nil
  end
  if not UI.canvasAdd(parent, scroll, x, y, w, h, z or 1) then
    UI.remove(scroll); return nil
  end
  local ok = pcall(function()
    scroll:AddChild(sizeBox)
    sizeBox:SetWidthOverride(w)
    sizeBox:SetHeightOverride(math.max(h, tonumber(contentH) or h))
    sizeBox:AddChild(canvas)
  end)
  if not ok then UI.remove(scroll); return nil end
  return scroll, sizeBox, canvas
end

function UI.selectorList(opts)
  opts = opts or {}
  local menu, tree, parent, actions = opts.menu, opts.widgetTree, opts.parent, opts.actions
  local items = opts.items or {}
  if not (UI.alive(menu) and UI.alive(tree) and UI.alive(parent) and type(actions) == "table") then
    return nil
  end

  local x, y = opts.x or 0, opts.y or 0
  local width, height = opts.width or 300, opts.height or 620
  local rowH, headerH = opts.rowH or 56, (opts.header == false) and 0 or 54
  local c = { buttons = {}, separators = {}, viewH = math.max(80, height - headerH) }
  local function countText(index)
    if type(opts.countText) == "function" then
      local text = safe(function() return opts.countText(index, #items) end)
      if text ~= nil then return tostring(text) end
    end
    return tostring(index or 0) .. "/" .. tostring(#items)
  end
  local root = UI.construct("/Script/UMG.CanvasPanel", tree)
  local scroll = UI.construct("/Script/UMG.ScrollBox", tree)
  local sizeBox = UI.construct("/Script/UMG.SizeBox", tree)
  local canvas = UI.construct("/Script/UMG.CanvasPanel", tree)
  if not (root and scroll and sizeBox and canvas)
      or not UI.canvasAdd(parent, root, x, y, width, height, opts.z or 1) then
    UI.remove(root)
    return nil
  end
  c.root, c.scroll, c.canvas = root, scroll, canvas

  -- PALETTE. Deliberately the family's existing one, not a new accent: panels are
  -- white at A=0.06, rules white at A=0.22, row separators white at A=0.14, and text
  -- keeps the native colour it inherits from the template TextBlock. A selector that
  -- introduces its own colour reads as a different mod's widget sitting in the menu.
  local background = UI.mkImage(tree)
  if background then
    pcall(function() background:SetColorAndOpacity({ R = 1, G = 1, B = 1, A = 0.06 }) end)
    UI.setVis(background, UI.VIS.PASSIVE)
    UI.canvasAdd(root, background, 0, 0, width, height, 0)
    c.background = background
  end

  if headerH > 0 then
    -- No colour override on the title: mkText copies font AND colour off the native
    -- template, so it matches every other heading in the host menu for free.
    local title = UI.mkText(tree, opts.textTemplate, opts.header or "Items", 18)
    local count = UI.mkText(tree, opts.textTemplate, countText(0), 16, 0.55)
    local rule = UI.mkImage(tree)
    if title then
      UI.setVis(title, UI.VIS.PASSIVE)
      UI.canvasAdd(root, title, 14, 8, width - 110, 30, 2)
    end
    if count then
      UI.setVis(count, UI.VIS.PASSIVE)
      UI.canvasAdd(root, count, width - 88, 9, 74, 28, 2)
    end
    if rule then
      pcall(function() rule:SetColorAndOpacity({ R = 1, G = 1, B = 1, A = 0.22 }) end)
      UI.setVis(rule, UI.VIS.PASSIVE)
      UI.canvasAdd(root, rule, 10, 43, width - 30, 2, 2)
    end
    c.title, c.count, c.rule = title, count, rule
  end

  if not UI.canvasAdd(root, scroll, 0, headerH, width, c.viewH, 1) then
    UI.remove(root)
    return nil
  end
  local ok = pcall(function()
    scroll:AddChild(sizeBox)
    sizeBox:SetWidthOverride(width - 18)
    sizeBox:SetHeightOverride(math.max(c.viewH, #items * rowH + 4))
    sizeBox:AddChild(canvas)
  end)
  if not ok then UI.remove(root); return nil end

  for i, item in ipairs(items) do
    local label = type(item) == "table" and item.label or tostring(item)
    local action = type(item) == "table" and item.action or nil
    local btn = UI.nativeButton(menu, label or "", actions, action)
    if not btn then
      -- forgetButton, not `actions[a] = nil`: the action is one of FIVE tables the button is
      -- registered in, and dropping only the action leaks the other four (see its comment).
      for _, made in ipairs(c.buttons) do UI.forgetButton(made, actions) end
      UI.remove(root)
      return nil
    end
    UI.canvasAdd(canvas, btn, 8, (i - 1) * rowH + 2, width - 34, rowH - 6, 2)
    c.buttons[i] = btn
    if type(opts.onCreateRow) == "function" then
      pcall(opts.onCreateRow, btn, item, i)
    end

    local sep = UI.mkImage(tree)
    if sep then
      pcall(function() sep:SetColorAndOpacity({ R = 1, G = 1, B = 1, A = 0.14 }) end)
      UI.setVis(sep, UI.VIS.PASSIVE)
      UI.canvasAdd(canvas, sep, 8, i * rowH - 2, width - 34, 2, 3)
      c.separators[i] = sep
    end
  end

  function c:setSelected(index)
    for i, btn in ipairs(c.buttons) do UI.selected(btn, i == index) end
    if UI.alive(c.count) then
      pcall(function() c.count:SetText(FText(countText(index))) end)
    end
  end
  function c:focus(index) UI.focus(c.buttons[index]) end
  function c:remove() UI.remove(c.root) end
  if opts.selected ~= nil then c:setSelected(opts.selected) end
  return c
end

-- Scroll a hand-built ScrollBox so `focusedWidget` is visible -- but ONLY when it's
-- currently OUTSIDE the viewport, so manual mouse/scrollbar scrolling that keeps it on
-- screen is not fought. When it IS off-screen (keyboard/controller nav ran past the
-- edge), center it so nav never dead-ends at the last visible row. `viewH` = the scroll
-- viewport height; `rowH` (optional, default 40) the row size used for the bottom edge.
-- Reads the widget's REAL canvas-slot Y (ScrollWidgetIntoView is unreliable on our
-- hand-built ScrollBox -> SizeBox -> Canvas). All native touches alive-gated + pcall'd.
function UI.scrollFocusIntoView(sb, focusedWidget, viewH, rowH)
  if not (UI.alive(sb) and UI.alive(focusedWidget)) then return end
  rowH = rowH or 40
  pcall(function()
    local pos = focusedWidget.Slot and focusedWidget.Slot:GetPosition()
    local y = pos and pos.Y
    if type(y) ~= "number" then return end
    local cur = sb:GetScrollOffset() or 0
    if y < cur or (y + rowH) > (cur + viewH) then   -- off-screen: center it (clamp low; ScrollBox clamps high)
      local off = y + 20 - viewH / 2
      if off < 0 then off = 0 end
      sb:SetScrollOffset(off)
    end
  end)
end

-- A predictive / filter-as-you-type dropdown shared across a set of edit boxes: the
-- FOCUSED box gets a scrollable, capped suggestion list. Encapsulates build-on-change,
-- the entry cap, keep-alive while its OWN scrollbar is dragged, and grace teardown on
-- blur. The caller owns the fields, the values, and the pick action.
--   opts.menu, opts.widgetTree, opts.actions   host menu, its WidgetTree, click-action map
--   opts.alive()  -> bool          false stops the poll (page closed / disposed)
--   opts.boxes()  -> { { box=<editbox>, values={<string>,...}, canvas=<CanvasPanel>, x, y, meta }, ... }
--                    the currently-eligible boxes; the focused one gets the dropdown
--   opts.pickType                  .type placed on each suggestion button; your click
--                                  handler reads action.box / action.value / action.meta
--   opts.cap(40) pollMs(200) rowH(38) maxH(300) width(320)
-- Returns c: c:start()/c:stop()/c:clear(); c:dropdown()/c:canvas()/c:viewH() so the caller
-- can fold the open dropdown into its own focus-scroll (UI.scrollFocusIntoView).
function UI.suggestList(opts)
  local menu, tree, actions = opts.menu, opts.widgetTree, opts.actions
  -- CAP 40, NOT 250. The viewport is maxH/rowH = 300/38 ~= 8 rows, so a cap of 250 built
  -- up to 250 native buttons to show eight. On the 144-value TestBed page every add-to-list
  -- pick therefore cost ~144 button destroys + a full panel rebuild + ~144 fresh button
  -- constructs, because clearPred resets activeBox/lastText and rebuildPanel hands the poll
  -- a NEW empty box, which re-matches everything. ~300 native widget operations per click,
  -- inside the ESC menu -- and the one lever this codebase has ever proven against the ESC
  -- open/close AV (crash ledger, reading 0x78) is INJECT FEWER WIDGETS. 40 still gives five
  -- screens of scroll, and matches this cap's own stated rationale: typing narrows the list.
  -- Pre-existing (the cap has been 250 since suggestList shipped); CONFIRMED as the cause of
  -- the 2026-07-27 freeze. Precedence: an explicit opts value wins (a consumer knows its own
  -- list), then the player's shared/DarnUI_user.lua, then the default.
  -- READ THE CONFIG WHERE IT IS USED, NOT HERE (fixed 2026-07-27, reported in play).
  -- These were captured once, at CREATION -- and the controller is created once per menu
  -- instance and then reused (`inst.predSuggest = inst.predSuggest or UI.suggestList{...}`),
  -- so changing the setting and pressing Apply did nothing until the instance was replaced.
  -- The settings page said "applies the next time a control is drawn", which was a promise
  -- the code did not keep. UI.config re-reads the file per call precisely so the value can
  -- be fetched at the point of use; capturing it up here threw that away.
  local rowH, width = opts.rowH or 38, opts.width or 320
  local function cfgCap()  return opts.cap  or UI.config("suggestCap") end
  local function cfgPoll() return opts.pollMs or UI.config("suggestPollMs") end
  -- height follows the row count the player asked for, so "show me more at once" is one
  -- setting rather than two that have to agree
  local function cfgMaxH() return opts.maxH or (rowH * UI.config("suggestRows")) end
  local c, st = { token = 0 }, {}   -- st: activeBox,lastText,dropdown,canvas,widgets,blur,scrollAt,viewH

  local function removeButtons()
    -- Forget BEFORE removing, while the widget is still readable -- forgetButton(widget, ...)
    -- can then revalidate the registration instead of trusting a bare address. This runs every
    -- time a dropdown closes, so a partial cleanup here leaks on every normal interaction.
    for _, w in ipairs(st.widgets or {}) do
      UI.forgetButton(w, actions)
      UI.remove(w)
    end
    st.widgets = {}
  end
  function c:clear()
    removeButtons()
    st.activeBox, st.lastText, st.blur = nil, nil, 0
    st.dropdown, st.canvas, st.viewH, st.scrollAt = nil, nil, nil, nil
  end
  function c:dropdown() return st.dropdown end
  function c:canvas() return st.canvas end
  function c:viewH() return st.viewH or cfgMaxH() end
  -- after the caller commits a single-value pick INTO a box, call this so the poll
  -- treats that text as already-shown and does NOT immediately reopen the dropdown
  -- (leave + return to reopen -> it then shows the full list).
  function c:markPicked(box, value) st.activeBox, st.lastText = box, tostring(value) end

  local function build(pb)
    -- fetched per BUILD so an Apply takes effect at the next dropdown open, which is what
    -- the settings page promises
    local cap, maxH = cfgCap(), cfgMaxH()
    local text = (UI.editText(pb.box) or ""):gsub("^%s*(.-)%s*$", "%1")
    if pb.box == st.activeBox and text == st.lastText then return end
    st.activeBox, st.lastText = pb.box, text
    removeButtons(); st.dropdown = nil
    -- empty box OR an already-complete value -> whole list (so a prior pick can be
    -- CHANGED, not "limited"); otherwise substring filter.
    local low, exact = text:lower(), false
    for _, v in ipairs(pb.values or {}) do if v == text then exact = true; break end end
    local matches = {}
    for _, v in ipairs(pb.values or {}) do
      if text == "" or exact or v:lower():find(low, 1, true) then
        matches[#matches + 1] = v
        if #matches >= cap then break end   -- perf cap; scroll + typing cover longer lists
      end
    end
    if #matches == 0 then return end
    -- scrollable dropdown: ScrollBox -> SizeBox(full height) -> canvas -> buttons.
    local fullH = #matches * rowH + 4
    local dd = UI.construct("/Script/UMG.ScrollBox", tree); if not dd then return end
    UI.canvasAdd(pb.canvas, dd, pb.x, pb.y + 40, width, math.min(maxH, fullH), 20)
    st.widgets[#st.widgets + 1] = dd
    st.dropdown, st.viewH = dd, math.min(maxH, fullH)
    local sb, cv = UI.construct("/Script/UMG.SizeBox", tree), UI.construct("/Script/UMG.CanvasPanel", tree)
    if not (sb and cv) then return end
    st.canvas = cv
    pcall(function() dd:AddChild(sb); sb:SetWidthOverride(width - 20); sb:SetHeightOverride(fullH); sb:AddChild(cv) end)
    for i, v in ipairs(matches) do
      local b = UI.nativeButton(menu, v, actions, { type = opts.pickType, box = pb.box, value = v, meta = pb.meta })
      if b then UI.canvasAdd(cv, b, 0, (i - 1) * rowH, width - 20, 36, 1); st.widgets[#st.widgets + 1] = b end
    end
  end

  local function poll(tok)
    if c.token ~= tok then c:clear(); return end
    -- Stand down BEFORE opts.alive(), which reaches into the menu: during teardown
    -- that read is exactly what we must not do. Pause, do not stop -- rescheduling
    -- means the loop heals itself when the world comes back.
    if UI.worldIsGone() then ExecuteWithDelay(cfgPoll(), function() poll(tok) end); return end
    if not opts.alive() then c:clear(); return end
    pcall(function()
      local focused = nil
      for _, pb in ipairs(opts.boxes() or {}) do
        if UI.alive(pb.box) and safe(function() return pb.box:HasKeyboardFocus() end) == true then focused = pb; break end
      end
      if not focused then
        -- keep the dropdown alive while focus/hover is inside it OR while its scrollbar
        -- is being dragged (a changing scroll offset is the reliable "still interacting"
        -- signal -- a drag blurs the box and registers as neither focus nor hover).
        local keep = false
        if st.dropdown and UI.alive(st.dropdown) then
          local off = safe(function() return st.dropdown:GetScrollOffset() end)
          local scrolling = (type(off) == "number" and off ~= st.scrollAt); st.scrollAt = off
          keep = scrolling
            or safe(function() return st.dropdown:HasFocusedDescendants() end) == true
            or safe(function() return st.dropdown:IsHovered() end) == true
            or safe(function() return st.dropdown:HasKeyboardFocus() end) == true
        end
        if keep then st.blur = 0
        elseif st.activeBox then
          st.blur = (st.blur or 0) + 1     -- grace: let a click (mouse-UP) land before teardown
          if st.blur >= 6 then c:clear() end
        end
        return
      end
      st.blur = 0
      build(focused)
    end)
    ExecuteWithDelay(cfgPoll(), function() poll(tok) end)
  end

  function c:start() c.token = c.token + 1; poll(c.token) end
  function c:stop() c.token = c.token + 1; c:clear() end
  return c
end

-- ---------------------------------------------------------------------------
-- MAP-BOUNDARY STAND-DOWN
-- ---------------------------------------------------------------------------
-- Every polling loop in this kit runs on a timer, and a timer that fires while the
-- engine is tearing a world down touches objects that are half-dead. UI.alive() does
-- NOT save you there: IsValid() stays true for an object whose children are already
-- nulled -- proven three times (the stale-cleanup CTD, the tab-bounce CTD, and the
-- lingering-menu AVs). The only real protection is to stop polling before teardown.
--
-- UE4SS gives us the boundary directly: RegisterLoadMapPreHook fires as the map goes
-- away, PostHook when the next one is up. The callbacks here touch NO UObject -- they
-- only set a boolean -- so the guard cannot itself become what it is guarding against.
--
-- DUAL RE-ARM, deliberately: if the post-hook never fires we would leave every poll
-- dead until relaunch, silently -- the exact failure mode that has cost the most time
-- on this project. So the flag is ALSO cleared by UI.worldBack(), which the menu
-- injection path calls on every ESC open. Two independent ways back means one failing
-- is survivable.
-- worldGone now lives on `runtime` (see the scheduler above) so that invalidating the world
-- also cancels every pending task. Kept as one source of truth rather than two flags that can
-- disagree -- which is exactly the class of bug this whole merge is about.
local mapHooksArmed = false

function UI.worldIsGone() return runtime.worldGone end
function UI.worldBack() restoreWorld() end   -- second re-arm path (call on injection)

-- Idempotent; safe to call from every mod that loads the kit.
function UI.armMapBoundary(logf)
  if mapHooksArmed then return true end
  mapHooksArmed = true
  local okPre = type(_G.RegisterLoadMapPreHook) == "function"
    and pcall(_G.RegisterLoadMapPreHook, function() invalidateWorld() end)
  local okPost = type(_G.RegisterLoadMapPostHook) == "function"
    and pcall(_G.RegisterLoadMapPostHook, function() restoreWorld() end)
  -- If the hooks are unavailable we must NOT latch: behave exactly as before rather
  -- than risk standing everything down with no way back.
  if not okPre then restoreWorld() end
  if logf then logf(string.format("map-boundary hooks: pre=%s post=%s",
    tostring(okPre == true), tostring(okPost == true))) end
  return okPre == true
end

-- ---------------------------------------------------------------------------
-- BACKSPACE-CLOSE GUARD -- the IsEnableCancelAction gate
-- ---------------------------------------------------------------------------
-- Backspace (and gamepad B) is the game's global "cancel" action. On an ESC-menu
-- widget it runs PalUserWidgetStackableUI:Close and DESTROYS the whole menu --
-- even while you are typing in an injected text field, because the key is dual-
-- routed: UMG focus edits the text AND the cancel action closes the menu.
-- A UE4SS post-hook on Close CANNOT veto this (a post-hook can't stop a native
-- UFunction from running -- proven live), so the input has to be stopped before
-- it ever reaches the cancel action.
-- GROUND TRUTH (CXXHeaderDump): UWBP_MenuESC_C : UPalUserWidgetOverlayUI, which
-- carries `bool IsEnableCancelAction` (the gate for the cancel action) alongside
-- SEPARATE bind handles -- CancelInputHandle (backspace/B) and EscInputHandle
-- (ESC). Clearing the bool therefore kills backspace-to-close while ESC still
-- exits, which is the UX we want: deliberate exit only. The editable text keeps
-- receiving Backspace and deletes characters normally.
-- Cancel-action types (Pal_enums.hpp EPalOverlayUICancelActionType). The reason
-- this matters: CommonCancel and Esc are SEPARATE types on the same widget, so the
-- backspace path can be suppressed on its own.

-- Suppress / restore the CommonCancel (Backspace, gamepad-B) action on `menu`.
-- Returns: boolReadback, okBoolWrite, okCall, callErr -- each lever reported
-- separately, since a pcall that swallows "no such UFunction" would otherwise look
-- identical to a lever that ran and simply didn't help.
--
-- THREE MECHANISMS WERE MEASURED LIVE (2026-07-25); read this before changing it:
--  1. `IsEnableCancelAction = false` -- INERT. The log caught the host closing with
--     the gate reading false on BOTH widgets and drift=0: the property is written and
--     held, and the cancel->Close path ignores it. It is kept below only as
--     bookkeeping (it also drives the on-screen action-bar prompt).
--  2. `ClearCancelAction()` -- WORKS, but is DESTRUCTIVE AND TYPE-AGNOSTIC: it takes
--     out the Esc path too, and ResetCancelAction() does NOT put the host's close
--     binding back. Result: ESC stopped dismissing the menu at all (Close kept firing
--     on the child while the host stayed up), recoverable only by relaunching. NEVER
--     call it on the host.
--  3. `OverrideCancelActionByType(CommonCancel, ...)` -- what we use: it replaces ONE
--     type's handler with a no-op and leaves Esc untouched by construction.
-- Restore is ResetCancelAction(). If that ever fails to restore, the failure mode is
-- benign (backspace-to-close stays off; ESC is untouched and the menu still exits) --
-- unlike mechanism 2, which left the menu unexitable.
function UI.setCancelAction(menu, enabled)
  if not UI.alive(menu) then return nil, false, false, "dead menu" end
  local okBool = pcall(function() menu.IsEnableCancelAction = enabled end)
  local okCall, callErr
  if enabled then
    -- DELIBERATELY NOTHING. ResetCancelAction() does not restore the binding, it
    -- destroys what's left of it -- that is what killed ESC (isolated in round 5,
    -- where Reset ran ALONE and ESC broke anyway). Unregistering is one-way; the
    -- trade is that Backspace stops backing out of this menu instance, while ESC --
    -- the thing that actually matters -- survives untouched.
    okCall, callErr = true, nil
  else
    -- SURGICAL SUPPRESSION. CancelInputHandle (Backspace / gamepad-B) and
    -- EscInputHandle are SEPARATE FPalUIActionBindData handles (4-byte opaque IDs) on
    -- the widget. Unregistering the cancel handle by value therefore cannot affect
    -- ESC -- unlike ClearCancelAction(), which is type-agnostic and took ESC with it.
    -- And UnregisterActionBinding takes a STRUCT, not a delegate, so unlike the whole
    -- Override/Register family it is genuinely callable from UE4SS Lua.
    local h = safe(function() return menu.CancelInputHandle end)
    if h ~= nil then
      okCall, callErr = pcall(function() menu:UnregisterActionBinding(h) end)
    end
    -- FALL BACK to the proven suppressor if the surgical path is unavailable, so a
    -- failure here can never cost us the one behaviour we know works.
    if not okCall then
      local fbErr
      okCall, fbErr = pcall(function() menu:ClearCancelAction() end)
      callErr = "unregister failed (" .. tostring(callErr) .. ") -> ClearCancelAction fallback"
        .. (okCall and "" or (" ALSO failed: " .. tostring(fbErr)))
    end
  end
  return safe(function() return menu.IsEnableCancelAction end), okBool, okCall, callErr
end

-- ---------------------------------------------------------------------------
-- ASSERT that ESC closes the menu
-- ---------------------------------------------------------------------------
-- Suppressing backspace costs us the host's own close binding: ClearCancelAction()
-- and ResetCancelAction() are BOTH one-way doors, and with Lua delegates unavailable
-- (`[push_delegateproperty] Error` -- UE4SS cannot pass a Lua function where a
-- delegate is expected, which rules out OverrideCancelAction*/RegisterActionBinding*
-- entirely) there is no API to put the binding back. So stop trying to PRESERVE ESC
-- and ASSERT it instead: one global Escape keybind that closes the menu outright.
-- `Close()` takes no delegate, so unlike every callback API it is genuinely callable.
-- Only fires for menus we actually clobbered (shouldClose), so an untouched menu
-- keeps its native behaviour and the ESC press that OPENS a fresh menu can't race it.
local escArmed, escTargets, escBusy = false, {}, false
UI.escDebug = false   -- set true to trace ESC handling

local function runEscClose()
  -- RE-ENTRY GUARD. The ESC menu open/close race is a known engine-side crash under
  -- menu churn (see the crash ledger: two AV-reading-0x78 CTDs from it before any of
  -- this existed), and a keybind lets the player drive that churn far faster than the
  -- UI ever could -- a second Close landing while the first is still tearing down is
  -- exactly the shape that AVs. One close in flight at a time; the flag clears on the
  -- game thread once the close has actually been issued.
  if escBusy then return end
  local live, fired = {}, false
  for _, e in ipairs(escTargets) do
    if UI.alive(e.menu) then
      live[#live + 1] = e
      -- NOTE: do NOT gate on IsInViewport(). The ESC menu lives in a HUD widget STACK,
      -- not the viewport, so IsInViewport() returns FALSE for it (measured) -- an
      -- earlier version gated on that and silently skipped every close, which is why
      -- ESC looked like a dead no-op. shouldClose() is the real gate.
      if not fired and (e.shouldClose == nil or e.shouldClose()) then
        fired, escBusy = true, true
        -- MUST HOP TO THE GAME THREAD. A RegisterKeyBind callback runs on UE4SS's own
        -- thread, and Close() mutates live widget state -- calling it directly from
        -- the keybind CRASHED the game. RULE FOR EVERY FUTURE KEYBIND: never touch a
        -- UObject inside a RegisterKeyBind callback -- marshal it back first.
        local menuRef = e.menu
        local ok = pcall(function()
          ExecuteInGameThread(function()
            -- close ONE host only: closing several stackable widgets in a single frame
            -- is extra churn for no benefit -- the host dismisses the whole stack.
            local done = false
            for _, cn in ipairs(UI.CANCEL_STACK_CLASSES) do
              if done then break end
              for _, w in ipairs(safe(function() return FindAllOf(cn) end) or {}) do
                if UI.alive(w) and pcall(function() w:Close() end) then done = true; break end
              end
            end
            if not done and UI.alive(menuRef) then pcall(function() menuRef:Close() end) end
            escBusy = false
            if UI.escDebug then print("[DarnUI] esc-assert: closed=" .. tostring(done) .. "\n") end
          end)
        end)
        if not ok then escBusy = false end   -- never latch busy on a failed dispatch
      end
    end
  end
  escTargets = live   -- drop entries whose menu died
end

-- entry = { menu = <widget>, shouldClose = function() -> bool }
function UI.assertEscCloses(entry)
  if not (entry and UI.alive(entry.menu)) then return false end
  for _, e in ipairs(escTargets) do              -- idempotent per menu
    if UI.addr(e.menu) == UI.addr(entry.menu) then return escArmed end
  end
  escTargets[#escTargets + 1] = entry
  if escArmed then return true end
  local k = safe(function() return Key.ESCAPE end)
  if k == nil then return false end
  escArmed = pcall(function() RegisterKeyBind(k, function() pcall(runEscClose) end) end) == true
  return escArmed
end

-- THE WIDGET YOU INJECT INTO IS NOT THE ONE THAT CLOSES (measured 2026-07-25).
-- Our page lives on WBP_MenuESC_C, but Backspace closes its HOST: the live log
-- showed `Close class=WBP_InGameMainMenu_C ourMenu=false gate=false drift=0` --
-- i.e. the gate on our own menu was correctly held shut (and never drifted), and
-- the game closed the PARENT anyway. Both are UPalUserWidgetOverlayUI subclasses,
-- so both carry the gate; only the ancestor's actually owns the cancel input.
-- Hence: gate the whole stack, not just the widget we injected into.
UI.CANCEL_STACK_CLASSES = { "WBP_InGameMainMenu_C" }

-- Holds the cancel action OFF across the menu stack while ANY of the caller's edit
-- boxes has keyboard focus, and restores it the moment none does.
--   opts.menu     host menu (a UPalUserWidgetOverlayUI subclass, e.g. WBP_MenuESC_C)
--   opts.boxes()  -> { <editbox>, ... }   edit widgets to watch; rows of the shape
--                    { box = <editbox> } are accepted too, so a caller can pass its
--                    existing field rows straight through
--   opts.alive()  -> bool (optional)      false stops the poll (page closed/disposed)
--   opts.alsoGate  class names to gate alongside opts.menu (default CANCEL_STACK_CLASSES)
--   opts.pollMs (50)
-- Returns c: c:start() / c:stop(). ALWAYS :stop() on close AND on dispose --
-- leaving a live menu with the gate off breaks backspace-to-close until relaunch.
function UI.editCloseGuard(opts)
  -- 50ms, not 150: the hold below re-disables the gate every tick, so the poll
  -- interval IS the width of the window in which a re-enabled gate can eat a
  -- Backspace. Tighter poll = smaller hole.
  local menu, pollMs = opts.menu, opts.pollMs or 50
  local c = { token = 0 }
  local lastWant = nil
  local cache = nil   -- resolved gate targets; FindAllOf is too costly per tick

  -- our menu PLUS every live instance of the ancestor classes that own the cancel
  -- input. Re-resolved on focus transitions only (the stack is stable mid-type).
  local function targets(refresh)
    if cache and not refresh then return cache end
    local out = {}
    if UI.alive(menu) then out[#out + 1] = menu end
    for _, cn in ipairs(opts.alsoGate or UI.CANCEL_STACK_CLASSES) do
      for _, w in ipairs(safe(function() return FindAllOf(cn) end) or {}) do
        if UI.alive(w) and UI.addr(w) ~= UI.addr(menu) then out[#out + 1] = w end
      end
    end
    cache = out
    return out
  end

  local function poll(tok)
    if c.token ~= tok then return end
    -- Same stand-down as suggestList: before any read of the menu, and paused rather
    -- than stopped. c:stop() here would also try to restore the cancel binding on a
    -- half-dead widget, which is the worst thing to do mid-teardown.
    if UI.worldIsGone() then ExecuteWithDelay(pollMs, function() poll(tok) end); return end
    if not UI.alive(menu) or (opts.alive and not opts.alive()) then c:stop(); return end
    pcall(function()
      local focused = false
      for _, b in ipairs(opts.boxes() or {}) do
        local box = b
        if type(b) == "table" and b.box ~= nil then box = b.box end   -- row form; UObjects are userdata
        if UI.alive(box) and safe(function() return box:HasKeyboardFocus() end) == true then
          focused = true; break
        end
      end
      local want = not focused

      if want ~= lastWant then
        -- FOCUS TRANSITION. The first suppression is IRREVERSIBLE (nothing restores the
        -- cancel binding), and it takes ESC with it because ESC and Backspace are the
        -- same action on the host -- so tell the caller, which then owns ESC via
        -- UI.assertEscCloses from this point on.
        if not want and not c.clobbered then
          c.clobbered = true
          if opts.onClobber then pcall(opts.onClobber) end
        end
        for _, t in ipairs(targets(true)) do
          local got, okBool, okCall, callErr = UI.setCancelAction(t, want)
          if opts.debug then
            print(string.format(
              "[DarnUI] cancel-gate: %s focused=%s want=%s now=%s | boolWrite=%s bindingCall=%s%s\n",
              tostring(safe(function() return t:GetClass():GetFName():ToString() end)),
              tostring(focused), tostring(want), tostring(got), tostring(okBool),
              okCall == nil and "off" or tostring(okCall),
              callErr and (" err=" .. tostring(callErr)) or ""))
          end
        end
      end
      lastWant = want
    end)
    ExecuteWithDelay(pollMs, function() poll(tok) end)
  end

  -- gate values as the GAME sees them, per target: "WBP_MenuESC_C=false,..." (diagnostics)
  function c:gate()
    local parts = {}
    for _, t in ipairs(targets()) do
      parts[#parts + 1] = string.format("%s=%s",
        tostring(safe(function() return t:GetClass():GetFName():ToString() end)),
        tostring(safe(function() return t.IsEnableCancelAction end)))
    end
    return table.concat(parts, ",")
  end
  function c:start()
    lastWant, cache = nil, nil
    c.token = c.token + 1
    poll(c.token)
  end
  function c:stop()
    c.token = c.token + 1          -- stale loops self-cancel
    lastWant = nil
    -- "Restore" is a no-op by design: nothing puts the cancel binding back (see
    -- setCancelAction). We leave it cleared and let UI.assertEscCloses own the exit.
    for _, t in ipairs(targets()) do UI.setCancelAction(t, true) end
    -- NO TAB BOUNCE HERE. :stop() is called from closePage, the STALE-MENU SWEEP and
    -- the Destruct hook -- i.e. on menus that are dying or already lingering. Calling
    -- ChangeTab there CRASHED the game: EXCEPTION_ACCESS_VIOLATION reading 0x78 (a
    -- NULL member read -- the tabset internals are torn down before the widget itself
    -- goes). UI.alive() does NOT protect you: IsValid() is still true for a
    -- mid-teardown widget whose children have already been nulled. This is the vault's
    -- existing law (never mutate a lingering/swept menu -- RemoveFromParent and
    -- SetVisibility AV'd the same way); a tab rebuild is far heavier than either.
    -- The bounce may ONLY run on a live, verifiably-open page. See the blur path.
    cache = nil
  end
  return c
end


-- ---------------------------------------------------------------------------
-- Register this kit's own DarnMenu page (shared/DarnUI_user.lua).
--
-- REGISTERED BY THE KIT, not by the DarnUI mod: consumers vendor this file and no longer
-- depend on the DarnUI item, so a page registered over there would be missing for almost
-- everyone who has the kit. DarnMenu is documented on both stores as a platform with no
-- settings of its own, so this goes through the same public schema door any third-party mod
-- uses -- the setting belongs to the kit that owns it.
--
-- Every vendored copy runs this, so it can be written more than once per launch. The
-- content is identical, and the write is SKIPPED when the file already matches, so the
-- second consumer costs one read and nothing else. No DarnMenu dependency: if DarnMenu is
-- absent this leaves a file nothing reads, which is harmless.
--
-- SEVERAL COPIES WRITING THE SAME TWO FILES IS THE HARD PART (virtualbjorn, merged 2026-07-28).
-- "Every vendored copy runs this" means several Lua states race on shared/DarnMenu_schema_index
-- .lua at startup -- and that file is the registry DarnMenu reads to build Mod Options, so a
-- lost write does not lose OUR page, it loses SOMEONE ELSE'S. The previous code opened it "w",
-- which truncates the only copy to nothing before writing a byte. This project has already paid
-- for that exact shape once, in store.lua (see its 1.4.4 note: remove-then-rename lost every
-- weapon in every world). The writer below is the same compare-and-swap contract writers.lua
-- uses, and it is exposed as UI._registration so test-darnui.js can prove it against a real
-- filesystem rather than by reading.
local registrationNonce = tostring({}):gsub("[^%w]", "")
local registrationCounter = 0

-- Returns body,"ok" | nil,"missing" | nil,"unreadable". The three are NOT interchangeable:
-- "missing" is a legitimate first-run state, "unreadable" must never be overwritten.
local function registrationRead(path)
  local f, err, code = io.open(path, "rb")
  if not f then
    local missing = code == 2 or code == 3
      or tostring(err or ""):lower():find("not found", 1, true) ~= nil
      or tostring(err or ""):lower():find("no such file", 1, true) ~= nil
    return nil, missing and "missing" or "unreadable"
  end
  local ok, body = pcall(function() return f:read("*a") end)
  pcall(function() f:close() end)
  if not ok or body == nil then return nil, "unreadable" end
  return body, "ok"
end

local function registrationRename(from, to)
  local ok, result = pcall(os.rename, from, to)
  return ok and result ~= nil
end

local function registrationRemove(path)
  pcall(os.remove, path)
end

-- A per-state unique temp name. Two vendored copies must not collide on one .tmp, or the
-- loser's half-written bytes become the winner's install.
local function registrationTemp(path)
  for _ = 1, 32 do
    registrationCounter = registrationCounter + 1
    local candidate = path .. ".tmp.DarnUI." .. registrationNonce .. "." .. registrationCounter
    local _, status = registrationRead(candidate)
    if status == "missing" then return candidate end
  end
end

-- Transactionally replace `path` only if its bytes/status still match what the caller read.
-- Returns false,"conflict" when another startup writer won the race -- the caller re-reads and
-- retries, so the two registrations merge instead of one erasing the other.
local function registrationWrite(path, body, expectedBody, expectedStatus)
  local tmp = registrationTemp(path)
  if not tmp then return false, "temporary-name failure" end
  local f = io.open(tmp, "wb")
  if not f then return false, "temporary-open failure" end
  -- write, flush AND close are all checked. A silent failure in any of them is how a save path
  -- reports success while the bytes are still in a buffer that never reached the disk.
  local wrote, writeResult = pcall(function()
    local result = f:write(body)
    if result == nil then error("write failed") end
    local flushed = f:flush()
    if flushed == nil then error("flush failed") end
    return true
  end)
  local closed, closeResult = pcall(function() return f:close() end)
  if not wrote or writeResult ~= true or not closed or closeResult == nil then
    registrationRemove(tmp)
    return false, "temporary-write failure"
  end

  local current, status = registrationRead(path)
  if status ~= expectedStatus or current ~= expectedBody then
    registrationRemove(tmp)
    return false, "conflict"
  end

  if status == "missing" then
    if registrationRename(tmp, path) then return true end
    registrationRemove(tmp)
    return false, "install failure"
  end
  if status ~= "ok" then
    registrationRemove(tmp)
    return false, "unsafe existing file"
  end

  local backup = path .. ".bak"
  local _, backupStatus = registrationRead(backup)
  if backupStatus ~= "ok" and backupStatus ~= "missing" then
    registrationRemove(tmp)
    return false, "unreadable backup"
  end

  local held
  if backupStatus == "ok" then
    held = registrationTemp(backup .. ".previous")
    if not held or not registrationRename(backup, held) then
      registrationRemove(tmp)
      return false, "backup parking failure"
    end
  end
  -- Narrow the compare/swap race: backup preparation can take long enough for another Lua state
  -- to publish a newer primary. Re-check immediately before moving the live file; never park
  -- bytes we did not base this write on.
  local latest, latestStatus = registrationRead(path)
  if latestStatus ~= expectedStatus or latest ~= expectedBody then
    if held then registrationRename(held, backup) end
    registrationRemove(tmp)
    return false, "conflict"
  end
  if not registrationRename(path, backup) then
    if held then registrationRename(held, backup) end
    registrationRemove(tmp)
    return false, "primary parking failure"
  end
  -- Close the remaining compare/rename race: verify the bytes actually parked, not only the
  -- bytes observed immediately before the rename. If another Lua state published in that gap,
  -- restore its file and retry from fresh input.
  local parked, parkedStatus = registrationRead(backup)
  if parkedStatus ~= "ok" or parked ~= expectedBody then
    local restoredPrimary = registrationRename(backup, path)
    local restoredBackup = true
    if restoredPrimary and held then restoredBackup = registrationRename(held, backup) end
    registrationRemove(tmp)
    if not restoredPrimary then return false, "conflict rollback failure" end
    if not restoredBackup then return false, "backup restore failure" end
    return false, "conflict"
  end
  if not registrationRename(tmp, path) then
    registrationRename(backup, path)
    if held then registrationRename(held, backup) end
    registrationRemove(tmp)
    return false, "install failure"
  end
  if held then registrationRemove(held) end
  return true
end

-- Exposed for tests ONLY. Nothing in the kit calls through this table; it exists so the
-- contract above can be exercised against a real filesystem the way writers.lua is.
UI._registration = { read = registrationRead, write = registrationWrite, temp = registrationTemp }

pcall(function()
  local shared = (debug.getinfo(1, "S").source:gsub("^@", ""):gsub("[^/\\]+$", "")) .. "../../shared/"
  local schema = [[-- DarnUI -- auto-generated by the DarnUI kit; edit through ESC > Mod Options.
return {
  schemaVersion = 2,
  tab = "DarnUI", order = 90, target = "DarnUI_user",
  live = true,
  note = "Limits for the shared widget kit that other Darn mods draw with. These apply the "
      .. "next time a control is drawn -- no relaunch needed.",
  defaults = { suggestCap = 40, suggestRows = 8, suggestPollMs = 200 },
  sections = {
    { title = "Type-to-search dropdowns", options = {
        { path = "suggestCap", label = "Most suggestions to offer at once", kind = "number",
          min = 5, max = 60, step = 5,
          help = "How many matches a dropdown offers at once. Each one is a real button the "
              .. "game has to build, and building a lot of them is genuinely unsafe: 250 was "
              .. "the old default and could freeze or crash the game while scrolling. The "
              .. "ceiling is deliberately low. Type a few letters to narrow a long list "
              .. "instead -- that is what the filter is for." },
        { path = "suggestRows", label = "Rows visible before scrolling", kind = "number",
          min = 3, max = 30, step = 1,
          help = "How tall the dropdown is. Does not change how many are built -- that is the "
              .. "setting above." },
        { path = "suggestPollMs", label = "Typing response (ms)", kind = "number",
          min = 80, max = 2000, step = 20,
          help = "How often a focused box is checked for new text. Lower feels snappier and "
              .. "costs a little more; higher is calmer." },
    }},
  },
}
]]
  local p = shared .. "DarnMenu_schema_DarnUI.lua"
  -- Bounded retries: a "conflict" means another vendored copy published between our read and
  -- our swap, so re-read and try again. Anything else is a real error -- stop rather than spin.
  for _ = 1, 3 do
    local current, status = registrationRead(p)
    if current == schema then break end        -- another consumer already wrote it
    if status ~= "ok" and status ~= "missing" then break end
    local ok, reason = registrationWrite(p, schema, current, status)
    if ok then break end
    if reason ~= "conflict" then break end
  end
  -- Do not register in the index unless our page file is actually installed, or Mod Options
  -- lists a tab whose schema cannot be loaded.
  if registrationRead(p) ~= schema then return end

  -- Merge our name into the index without disturbing another startup writer. Same CAS loop.
  local indexPath = shared .. "DarnMenu_schema_index.lua"
  for _ = 1, 3 do
    local raw, status = registrationRead(indexPath)
    if status ~= "ok" and status ~= "missing" then break end
    -- A process interruption can occur after primary -> .bak but before temp -> primary. Recover
    -- the complete registry from that backup instead of treating the missing primary as an empty
    -- index and overwriting it with only DarnUI -- that would drop every other mod's page.
    local sourceRaw = raw
    if status == "missing" then
      local backupRaw, backupStatus = registrationRead(indexPath .. ".bak")
      if backupStatus == "ok" then sourceRaw = backupRaw end
    end
    local names, seen = {}, {}
    if sourceRaw ~= nil then
      local source = sourceRaw
      if source:sub(1, 3) == "\239\187\191" then source = source:sub(4) end   -- strip a UTF-8 BOM
      local chunk = load(source, "@" .. indexPath, "t", _ENV)
      if not chunk then break end
      local ok, value = pcall(chunk)
      if not ok or type(value) ~= "table" then break end
      -- Walk with `next`, not ipairs: a hand-edited index with a hole would make ipairs stop
      -- early and we would write back a TRUNCATED registry. Collect every integer key, sort,
      -- and keep only well-formed names.
      local indexed = {}
      for key, name in next, value do
        if type(key) == "number" and key >= 1 and key % 1 == 0 then
          indexed[#indexed + 1] = { key = key, name = name }
        end
      end
      table.sort(indexed, function(a, b) return a.key < b.key end)
      for _, item in ipairs(indexed) do
        local name = item.name
        if type(name) == "string" and name:match("^[%w_%-]+$") and not seen[name] then
          seen[name] = true
          names[#names + 1] = name
        end
      end
    end
    if not seen["DarnUI"] then names[#names + 1] = "DarnUI" end
    if status == "ok" and seen["DarnUI"] then break end   -- already listed: nothing to write
    local parts = {}
    for _, name in ipairs(names) do parts[#parts + 1] = string.format("%q", name) end
    local body = "return { " .. table.concat(parts, ", ") .. " }\n"
    local ok, reason = registrationWrite(indexPath, body, raw, status)
    if ok or reason ~= "conflict" then break end
  end
end)

-- ============================================================================
-- UI.takeover -- hand a whole native page over to your own content
-- ============================================================================
-- Squeezing an overlay into a corner of someone else's page is a losing game: the game's
-- panels are CENTRED and scale with the viewport, so the gutter you laid out in shrinks on a
-- smaller screen and your content lands on top of theirs (Standing Orders, 2026-07-27).
--
-- DarnMenu solved this long ago for the ESC menu -- collapse the page's own canvases, show
-- your page, put everything back on close -- but that logic lived inside DarnMenu where no
-- other mod could reach it. Per the standing rule (reusable UI belongs in DarnUI), it lives
-- here now.
--
-- WHAT MAKES THE RESTORE SAFE, learned the hard way across this family:
--   * HIDE, never RemoveFromParent. Detaching the game's widgets is what wedges its menus.
--   * Record each widget's EXACT prior visibility. A native canvas commonly sits at
--     SelfHitTestInvisible (4) while perfectly visible; restoring it as Visible (0) makes it
--     hit-testable and it starts eating clicks meant for the page behind it.
--   * Only hide what was actually SHOWING. Restoring something the game deliberately hid is
--     how you make another mod's page reappear over yours.
--   * Never touch a child we did not put there beyond its visibility.
--
-- Usage:
--   local page = UI.takeover(o)          -- o is an overlay host from UI.overlay
--   page:add(w)                          -- w belongs to the page: hidden until open
--   page:keep(w)                         -- w stays as it is (your entry button)
--   page:open() / page:close() / page:isOpen()
function UI.children(panel)
  local out = {}
  if not UI.alive(panel) then return out end
  local n = safe(function() return panel:GetChildrenCount() end) or 0
  for i = 0, n - 1 do
    local ch = safe(function() return panel:GetChildAt(i) end)
    if UI.alive(ch) then out[#out + 1] = ch end
  end
  return out
end

function UI.takeover(o)
  local t = { mine = {}, kept = {}, closedOnly = {}, hidden = nil, opened = false }

  local function known(w)
    local a = UI.addr(w); if not a then return true end
    for _, x in ipairs(t.mine) do if UI.addr(x) == a then return true end end
    for _, x in ipairs(t.kept) do if UI.addr(x) == a then return true end end
    return false
  end

  function t:add(w)
    if UI.alive(w) then t.mine[#t.mine + 1] = w; UI.setVis(w, UI.VIS.HIDE) end
    return w
  end
  function t:keep(w) if UI.alive(w) then t.kept[#t.kept + 1] = w end return w end
  -- Shown ONLY while the page is closed -- the button that opens it. Keeping it visible over
  -- the page it opened is just a second copy of the title in the corner.
  function t:whenClosed(w)
    if UI.alive(w) then
      t.kept[#t.kept + 1] = w
      t.closedOnly[#t.closedOnly + 1] = w
      UI.setVis(w, t.opened and UI.VIS.HIDE or UI.VIS.SHOW)
    end
    return w
  end
  function t:isOpen() return t.opened end

  function t:open()
    if t.opened then return true end
    if not UI.alive(o.canvas) then return false end
    -- Snapshot BEFORE hiding anything, so a failure part-way through still has a full record
    -- to restore from.
    t.hidden = {}
    for _, ch in ipairs(UI.children(o.canvas)) do
      if not known(ch) and UI.isVisible(ch) then
        t.hidden[#t.hidden + 1] = { w = ch, vis = safe(function() return ch.Visibility end) }
      end
    end
    for _, rec in ipairs(t.hidden) do UI.setVis(rec.w, UI.VIS.HIDE) end
    for _, w in ipairs(t.mine) do UI.setVis(w, UI.VIS.SHOW) end
    for _, w in ipairs(t.closedOnly) do UI.setVis(w, UI.VIS.HIDE) end
    t.opened = true
    return true
  end

  function t:close()
    if not t.opened then return end
    for _, w in ipairs(t.mine) do UI.setVis(w, UI.VIS.HIDE) end
    -- restore the EXACT value we found, not SHOW
    for _, rec in ipairs(t.hidden or {}) do UI.setVis(rec.w, rec.vis or UI.VIS.SHOW) end
    t.hidden = nil
    for _, w in ipairs(t.closedOnly) do UI.setVis(w, UI.VIS.SHOW) end
    t.opened = false
  end

  -- THE PAGE MUST NOT OUTLIVE ITS HOST. If the player closes the game's screen while our page
  -- is up, the game will show its own canvases again next time -- but our widgets would still
  -- be marked visible and would come back on top of them. Overlays call this from refresh.
  function t:syncTo(onScreen)
    if t.opened and not onScreen then t:close() end
  end

  return t
end

-- ============================================================================
-- EXTRACTED FROM STANDING ORDERS (Maiq, 2026-08-10: "keep SO mostly about
-- orders and less about UI management"). Three proven pieces, lifted verbatim
-- in behavior; SO's names delegate here so its call sites did not churn.
-- ============================================================================

-- ONCE-PER-DISTINCT-MESSAGE gate (SO's paneFaults pattern): a 1 Hz fault must
-- not flood the log, but the FIRST occurrence must always be seen. `store` is
-- caller-owned so scopes stay independent.
function UI.once(store, key)
  if store[key] then return false end
  store[key] = true
  return true
end

-- TEXTURE LOADER with the GC-survival rules Standing Orders paid for:
--   * ImportFileAsTexture2D textures are UNROOTED until their first bind; GC
--     can eat any of them in that window, so liveness samples ONE texture per
--     bind generation (`sentinels`), not just the earliest-bound one.
--   * a failed import retries on a TTL, never per call.
--   * ensure() returns (cache, reimported): on reimported=true the CALLER must
--     reset its bind caches so dead brushes rebind -- the loader cannot know
--     what was bound where.
-- spec: { dir = "<abs path ending in />", prefix = "badge_", names = {...},
--         sentinels = {...}, ttl = 3 }
function UI.texLoader(spec)
  local L = { cache = nil, at = -1e9, spec = spec }
  function L:alive()
    local c = self.cache
    if not c then return false end
    for _, nm in ipairs(self.spec.sentinels or {}) do
      if not UI.alive(c[nm]) then return false end
    end
    return next(c) ~= nil
  end
  function L:import()
    local cache = {}
    pcall(function()
      local rl = StaticFindObject("/Script/Engine.Default__KismetRenderingLibrary")
      local layout = FindFirstOf("WBP_PalOverallUILayout_C")
      if not (UI.alive(rl) and UI.alive(layout)) then return end
      for _, nm in ipairs(self.spec.names) do
        local t = rl:ImportFileAsTexture2D(layout,
                    self.spec.dir .. (self.spec.prefix or "") .. nm .. ".png")
        if UI.alive(t) then cache[nm] = t end
      end
    end)
    if next(cache) == nil then return nil end
    return cache
  end
  function L:ensure()
    if self:alive() then return self.cache, false end
    if (os.clock() - self.at) < (self.spec.ttl or 3) then return nil, false end
    self.at = os.clock()
    self.cache = self:import()
    return self.cache, self.cache ~= nil
  end
  return L
end

-- THE GUARDED-WALK GATE (SO's bench-snapshot cadence, CTDs #18-21): an engine
-- walk from a timer is legal only when ALL of it holds -- the interval elapsed,
-- walkSafe passes, and the world epoch has been stable for `settle` consecutive
-- asks (LoadMap-post is not "streaming finished"). `veto` lets the caller add
-- its own stand-down (SO passes its collapse-streak read). ok() self-stamps on
-- a pass, so callers cannot forget the interval.
function UI.walkGate(opts)
  local g = { at = -1e9, epoch = nil, n = 0,
              interval = (opts and opts.interval) or 3,
              settle = (opts and opts.settle) or 3 }
  function g:ok(veto)
    if (os.clock() - self.at) < self.interval then return false end
    if UI.walkSafe and not UI.walkSafe() then return false end
    local ep = UI.worldEpoch and UI.worldEpoch()
    if ep ~= nil then
      if ep ~= self.epoch then
        self.epoch, self.n = ep, 0
        return false
      end
      self.n = self.n + 1
      if self.n < self.settle then return false end
    end
    if veto then return false end
    self.at = os.clock()
    return true
  end
  return g
end


-- ============================================================ JOB DRIVER (2026-08-12)
-- One registration for the whole session. LoopInGameThreadAfterFrames(1, fn) is registered at
-- LuaMod.cpp:4684 in the UE4SS build this game runs (source on disk at modding\ue4ss-build,
-- commit c838a8ac, matching the SHA the client logs at boot); the loop re-arms in C++ with no
-- new registry reference, so this costs ONE ref forever instead of two per timer. It runs
-- inside engine_tick_hook -- the game thread, once per frame -- and needs no widget and no
-- world, which is what makes it usable from mod load.
--
-- WHY A BUDGET IS NOT OPTIONAL. The install lease of 2026-08-04 records the verdict on the
-- last attempt to move timer work onto frames: "almost unplayable" stutter, because the
-- trampoline put every timer BODY in a game frame. It named the fix in advance -- a
-- game-thread heartbeat scheduler WITH A PER-FRAME BUDGET -- and this is it. The drain stops
-- when the budget is spent and leaves the rest for the next frame, so a slow job costs a
-- fraction of one frame instead of the whole thing.
--
-- FAIL CLOSED. If the driver cannot arm, _jobsEnabled goes back to false and every timer keeps
-- running on the legacy engine. A scheduler that silently accepts jobs it will never run is
-- worse than one that was never turned on.
do
  local BUDGET_MS = 2      -- soft ceiling per frame; ~12% of a 16.7ms frame
  local armed = false

  -- HEALTH LINE. The scheduler's failure mode is not a crash, it is a queue that stops
  -- draining -- jobs accepted, never run, every timer in the mod silently dead. That looks
  -- exactly like "nothing happened", which is unfalsifiable from play. So it reports: pending
  -- should hover near zero and NEVER climb without bound. A rising `pending` is the whole
  -- signature, and one line a minute is cheap enough to leave on.
  -- Unconditional on purpose (the vault's rule: a flag-gated log is why a field report came
  -- back with no evidence) but rate-limited to once a minute, and it names its own high-water
  -- mark so a spike that has since drained is still visible after the fact.
  local lastStat, peak, drains, ranTotal = 0, 0, 0, 0
  local function reportStats(now)
    local st = UI.jobStats and UI.jobStats() or nil
    if type(st) ~= "table" then return end
    if (st.pending or 0) > peak then peak = st.pending end
    if (now - lastStat) < 60 then return end
    lastStat = now
    print(string.format("[Darn] jobs pending=%d peak=%d ran=%d drains=%d dt=%.1fms\n",
                        st.pending or 0, peak, ranTotal, drains, (st.dt or 0)))
  end

  local function drainOnce()
    -- The deadline is re-read per drain rather than captured, so a config change takes effect
    -- on the next frame without re-arming anything.
    local deadline = (tonumber(UI.config and UI.config("jobBudgetMs")) or BUDGET_MS)
    local started = nil
    drains = drains + 1
    -- COUNT WHAT THE DRAIN REPORTS, not how often the budget predicate fired. The first cut
    -- inferred it from predicate calls, which the `next(jobs)==nil` fast path skips entirely --
    -- so `ran` read 0 whenever the queue was HEALTHY, exactly backwards, and a zero in a health
    -- line invites the wrong conclusion. drainJobs already returns (ran, more); read it.
    local okD, ranN = pcall(UI.drainJobs, nil, function()
      -- Predicate budget: the drain asks after each job whether it may run another. Cheap by
      -- design -- two os.clock reads -- because it is consulted per job, every frame.
      local now = os.clock()
      if started == nil then started = now; return true end
      return ((now - started) * 1000) < deadline
    end)
    if okD then ranTotal = ranTotal + (tonumber(ranN) or 0) end
    pcall(reportStats, os.clock())
  end

  if type(_G.LoopInGameThreadAfterFrames) == "function" then
    armed = pcall(_G.LoopInGameThreadAfterFrames, 1, function()
      -- Never let a drain error escape into C++: an error crossing the engine_tick_hook
      -- boundary is a fastfail, not a traceback.
      pcall(drainOnce)
    end)
  end

  UI._jobsEnabled = armed == true
  UI._jobDriver   = armed and "LoopInGameThreadAfterFrames(1)" or "none (legacy timers)"
end

return UI
