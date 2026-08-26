-- ============================================================================
--  Living Arsenal -- main.lua (ORCHESTRATOR)
--
--  Weapons earn XP from the local player's own hits and grow damage, magazine
--  and durability as they level. Damage and magazine are client-side and stay
--  that way: ranged & melee damage are client-computed in Palworld, so the
--  client authors the damage packet and the server accepts it, identically in
--  single-player and on a dedicated server.
--
--  DURABILITY IS THE EXCEPTION, measured 2026-08-18. MaxDurability replicates
--  DOWN and never travels up, so on a dedicated server the client's durability
--  write is a number on the client and nothing else. That one field is handled
--  by the server half (see the side split below).
--  The parts:
--    counting.lua  -- counts THIS player's own hits, levels, owns the store
--    damage.lua    -- writes the equipped weapon's damage/mag/durability
--    progression.lua / weapondata.lua -- curves + the per-model base library
--  On-screen progress is the DarnToasts sticky panel (no built-in HUD).
--  Progress persists in Mods/shared/ so mod updates never touch it.
-- ============================================================================

-- Validation switch: true = hits/levels are logged but NOT saved (one-session
-- check that the hook fires once per hit). Validated + LIVE since 2026-07-20.
-- ============================================================================
--  SIDE SPLIT -- one package, two halves, neither running on the wrong machine.
--
--  Everything below this branch is client code: HUD, DarnUI, keybinds, toasts,
--  the options page, the store. None of it has any business on a dedicated
--  server, and the early return is what keeps it off -- the requires below this
--  point never execute there.
--
--  side.lua decides from the install path alone. Reading the net driver or
--  IsStandalone to answer the same question is a standing prohibition in this
--  codebase (it has crashed it before), and the path answer needs no engine
--  contact at all.
--
--  The server half is deliberately small: MaxDurability is the only field the
--  server owns outright, so it is the only thing there.
-- ============================================================================
local Side = require("side")
if Side.isServer() then
  print(string.format("[Arsenal] server half -- side=%s (%s) path=%s\n",
    Side.name(), Side.why(), Side.path()))
  local okSrv, srv = pcall(require, "server_durability")
  if okSrv and type(srv) == "table" then srv.start()
  else print("[Arsenal] server half FAILED to load: " .. tostring(srv) .. "\n") end
  return
end

local SHADOW = false

local Darn = require("darn")
local safe = Darn.safe
local alive = Darn.alive
local log  = Darn.logger("[Arsenal]")

local function safe_loadfile(path)
  if not path or type(path) ~= "string" then return nil end
  local f = io.open(path, "rb")
  if not f then return nil end
  local content = f:read("*a")
  f:close()
  if not content or content == "" then return nil end
  local chunk, err = load(content, "@" .. path, "t")
  return chunk, err
end

local cfg      = require("config")
-- user overrides (survive updates; the DarnMenu options page writes here):
-- Mods/shared/WeaponProficiency_user.lua returning a table of keys to change
Darn.overlay(cfg, "WeaponProficiency_user", log)
-- flat menu key -> nested config (DarnMenu writes flat keys only)
if type(cfg.targetXp) == "boolean" and type(cfg.targetScaling) == "table" then
  cfg.targetScaling.enabled = cfg.targetXp
end
-- keys newer than config.lua seed here: the live watcher only accepts a change
-- when the runtime type already matches, so a nil would eat the FIRST Apply
if type(cfg.barColor) ~= "string" then cfg.barColor = "gold" end
-- LAB FEATURES (ship OFF, by order): the XP-bar-only style and cursor
-- positioning are not ready for players; the sentinel file (or an explicit
-- labFeatures=true in the user file) arms them on a dev install. Everything
-- they saved (style, offsets) stays in the config either way.
if cfg.labFeatures ~= true then
  local lf = io.open(tostring(Darn.dir or "") .. "../../shared/WeaponProficiency_lab.txt", "r")
  if lf then lf:close(); cfg.labFeatures = true end
end
local A        = require("adapters")
local P        = require("progression")
local Store    = require("store")
local Counting = require("counting")
local Damage   = require("damage")

local WD       = require("weapondata")

-- ---- Darn family glue: toasts, sticky weapon panel, menu page ---------------
-- Missing DarnToasts costs the PANEL + toasts, not the mod (weapons still level).
local ToastLib, DARN = Darn.toastlib(log,
  "DarnToasts not found -- no weapon panel or toasts (subscribe to DarnToasts to restore them)")
-- CHANNEL/CUSTOM split (DarnToasts 2.0): level-up toasts ride the DEFAULT
-- CHANNEL (DarnToasts styles/positions/mutes them); the weapon panel is a
-- CUSTOM SURFACE -- author-positioned beside the weapon scroll, styled by OUR
-- config only (panelOpacity), untouched by the Toasts page.
local Toast = ToastLib.new("WeaponProficiency")
-- Position comes from OUR config, not a literal: a custom surface keeps a private
-- config table (never the shared file, never watched from the Toasts side), so
-- hardcoding it here left users with no way to move the panel at all -- they tried
-- ToastLib_config and the Toasts page's anchor and nothing happened (Nexus report).
-- EVERY STYLE KEEPS ITS OWN SAVED POSITION -- switching skins never drags the
-- previous skin's placement along. Integrated additionally pins its width to
-- the weapon card and anchors right.
local function stylePos(forStyle)
  local S = forStyle or cfg.panelStyle or "panel"
  if S == "bare" and cfg.labFeatures ~= true then S = "panel" end
  if S == "bare" then
    return { anchor = "right",
             xOffset = tonumber(cfg.intXOffset) or 20,
             yFrac   = tonumber(cfg.intYFrac) or 0.86,
             yOffset = tonumber(cfg.intYOffset) or 0,
             width   = tonumber(cfg.intWidth) or 150,
             style   = "bare" }
  elseif S == "pill" then
    return { anchor = cfg.panelAnchor or "right",
             xOffset = tonumber(cfg.pillXOffset) or 16,
             yFrac   = tonumber(cfg.pillYFrac) or 0.78,
             yOffset = tonumber(cfg.pillYOffset) or 0,
             width   = false,
             style   = "pill" }
  elseif S == "native" then
    return { anchor = cfg.panelAnchor or "right",
             xOffset = tonumber(cfg.stripXOffset) or 16,
             yFrac   = tonumber(cfg.stripYFrac) or 0.78,
             yOffset = tonumber(cfg.stripYOffset) or 0,
             width   = false,
             style   = "native" }
  end
  return { anchor = cfg.panelAnchor or "right",
           xOffset = tonumber(cfg.panelXOffset) or 16,
           yFrac   = tonumber(cfg.panelYFrac) or 0.78,
           yOffset = tonumber(cfg.panelYOffset) or 0,
           width   = false,
           style   = "panel" }
end
local Panel = (ToastLib.custom
  and ToastLib.custom("WeaponProficiency", stylePos()))
  or Toast   -- pre-2.0 DarnToasts installed: 1.x combined behavior still works

-- ---- INTEGRATED XP BAR: a UMG widget on the player HUD itself ---------------
-- The HUD-canvas layer every toast draws on paints UNDER the game's UI, so a
-- bar meant to sit ON the weapon card must be a widget in the HUD's own tree,
-- above it. Host named by the HUDTREE probe: WBP_PlayerUI_C, the persistent
-- in-game HUD. Bottom-right anchored in design units, so it tracks the weapon
-- card at any resolution. A missing DarnUI costs only the bar.
local HudBar = { w = 150 }
local UIB
do
  local okUIb, kit = pcall(Darn.requireUI)
  if okUIb and kit and kit.overlay then
    UIB = kit
    local function anchorBar(img, wd)
      local xOff = tonumber(cfg.intXOffset) or 12
      local yOff = tonumber(cfg.intYOffset) or 42
      local w    = tonumber(cfg.intWidth) or 150
      pcall(function()
        img.Slot:SetAnchors({ Minimum = { X = 1, Y = 1 }, Maximum = { X = 1, Y = 1 } })
        img.Slot:SetAlignment({ X = 0, Y = 1 })
        img.Slot:SetPosition({ X = -(xOff + w), Y = -yOff })
        img.Slot:SetSize({ X = wd, Y = 6 })
      end)
    end
    HudBar.anchorBar = anchorBar   -- posTick's sizing preview lives outside this block
    -- XP bar palette, shared by the bar-only fill and the panel styles' bar
    HudBar.COLORS = {
      gold    = { 1.0,  0.82, 0.25 },
      sky     = { 0.35, 0.75, 1.0  },
      emerald = { 0.35, 0.95, 0.5  },
      crimson = { 1.0,  0.35, 0.3  },
      white   = { 0.95, 0.95, 0.95 },
      violet  = { 0.75, 0.5,  1.0  },
    }
    function HudBar.color()
      return HudBar.COLORS[tostring(cfg.barColor or "gold")] or HudBar.COLORS.gold
    end
    function HudBar.tint()
      if not UIB.alive(HudBar.fill) then return end
      local c = HudBar.color()
      pcall(function()
        HudBar.fill:SetColorAndOpacity({ R = c[1], G = c[2], B = c[3], A = 0.95 })
      end)
    end
    if cfg.labFeatures == true then
    pcall(function()
      UIB.overlay({
        -- canvas name mined from WBP_PlayerUI.uasset's name map (repak +
        -- strings scan) -- the pak is the widget-name oracle, no guessing
        class = "WBP_PlayerUI_C", canvas = "CanvasPanel_Root",
        pollMs = 1000, buildDelayMs = 800, adopt = true,
        build = function(o)
          -- host=false in the field: "CanvasPanel_0" was a guessed name and the
          -- probe disproved it. SELF-HEAL: the tree's root widget usually IS the
          -- canvas -- use it when it is one; otherwise log the real children so
          -- the next fix is a fact, not another guess.
          if not o.host then
            pcall(function()
              local tree = o.menu and o.menu.WidgetTree
              local root = tree and tree.RootWidget
              local rn = tostring(root and root:GetFullName() or "nil")
              if root and rn:find("CanvasPanel") then
                o.host = root
                log("[hudbar] named canvas missing -- adopted the ROOT canvas: " .. rn)
              else
                log("[hudbar] host canvas not found; root = " .. rn)
                local cnt = (root and root.GetChildrenCount)
                            and root:GetChildrenCount() or 0
                for i = 0, math.min(cnt - 1, 11) do
                  local ch = root:GetChildAt(i)
                  log("[hudbar]   root child " .. i .. ": "
                      .. tostring(ch and ch:GetFullName() or "nil"))
                end
              end
            end)
            if not o.host then return end
          end
          HudBar.w = tonumber(cfg.intWidth) or 150
          HudBar.track = o:boxIn(o.host, 0, 0, HudBar.w, 6,
                                 { R = 0, G = 0, B = 0, A = 0.55 }, 30)
          local bc = HudBar.color and HudBar.color() or { 1.0, 0.82, 0.25 }
          HudBar.fill  = o:boxIn(o.host, 0, 0, 1, 6,
                                 { R = bc[1], G = bc[2], B = bc[3], A = 0.95 }, 31)
          if HudBar.track then anchorBar(HudBar.track, HudBar.w) end
          if HudBar.fill then anchorBar(HudBar.fill, 1) end
          UIB.setVis(HudBar.track, UIB.VIS.HIDE)
          UIB.setVis(HudBar.fill, UIB.VIS.HIDE)
          -- the positioning-mode grab handle lives on the VIEWPORT layer, above
          -- every menu -- the in-canvas version sat beneath the pause menu's
          -- own buttons and could not be clicked. AddToViewport(10000) +
          -- SetPositionInViewport is the same technique SpeedHUD and the
          -- breeding planner ship with; click dispatch is by button identity,
          -- so the parent does not matter. A stale handle from a previous
          -- world is removed first (viewport widgets outlive the HUD).
          if HudBar.grabBtn then
            pcall(function() HudBar.grabBtn:RemoveFromParent() end)
            HudBar.grabBtn = nil
          end
          HudBar.grabBtn = o:button("XP bar -- click to grab", { type = "hudbarGrab" })
          if HudBar.grabBtn then
            pcall(function()
              HudBar.grabBtn:AddToViewport(10000)
              HudBar.grabBtn:SetDesiredSizeInViewport({ X = HudBar.w, Y = 30 })
            end)
            UIB.setVis(HudBar.grabBtn, UIB.VIS.HIDE)
          end
          -- the WIDTH handle: same layer, same click-to-grab/click-to-place
          -- flow, parked at the bar's left edge; dragging it moves the left
          -- edge while the right edge stays anchored
          if HudBar.sizeBtn then
            pcall(function() HudBar.sizeBtn:RemoveFromParent() end)
            HudBar.sizeBtn = nil
          end
          HudBar.sizeBtn = o:button("resize", { type = "hudbarSize" })
          if HudBar.sizeBtn then
            pcall(function()
              HudBar.sizeBtn:AddToViewport(10000)
              HudBar.sizeBtn:SetDesiredSizeInViewport({ X = 64, Y = 30 })
            end)
            UIB.setVis(HudBar.sizeBtn, UIB.VIS.HIDE)
          end
          -- the log must say whether widgets actually LANDED -- "built" with a
          -- nil host printed success while nothing was placed
          log("[hudbar] build pass: host=" .. tostring(o.host ~= nil)
              .. " track=" .. tostring(HudBar.track ~= nil)
              .. " fill=" .. tostring(HudBar.fill ~= nil)
              .. " grab=" .. tostring(HudBar.grabBtn ~= nil)
              .. " (x=" .. tostring(cfg.intXOffset or 12)
              .. " y=" .. tostring(cfg.intYOffset or 42) .. " w=" .. HudBar.w .. ")")
        end,
        onClick = function(_, action)
          if action.type == "hudbarGrab" and HudBar.grabToggle then
            HudBar.grabToggle()
          elseif action.type == "hudbarSize" and HudBar.sizeToggle then
            HudBar.sizeToggle()
          end
        end,
      })
    end)
    end   -- labFeatures: without the flag the HUD overlay never arms
    function HudBar.reanchor()
      if not (UIB.alive(HudBar.track) and UIB.alive(HudBar.fill)) then return end
      HudBar.w = tonumber(cfg.intWidth) or 150
      anchorBar(HudBar.track, HudBar.w)
      anchorBar(HudBar.fill, math.max(1, HudBar.lastFillW or 1))
      HudBar.tint()   -- reanchor is the live-apply hook; color rides it
    end
  end
end
function HudBar.show(frac)
  if not (UIB and UIB.alive(HudBar.track) and UIB.alive(HudBar.fill)) then
    if UIB and not HudBar._saidDead then
      HudBar._saidDead = true
      log("[hudbar] show requested but widgets are missing/dead (track="
          .. tostring(HudBar.track ~= nil) .. " alive="
          .. tostring(HudBar.track ~= nil and UIB.alive(HudBar.track)) .. ")")
    end
    return
  end
  if not HudBar._saidShown then
    HudBar._saidShown = true
    log("[hudbar] visible (first show this session)")
  end
  local fw = math.max(1, math.floor((HudBar.w or 150)
              * math.max(0, math.min(1, tonumber(frac) or 0))))
  if fw ~= HudBar.lastFillW then
    HudBar.lastFillW = fw
    pcall(function() HudBar.fill.Slot:SetSize({ X = fw, Y = 6 }) end)
  end
  UIB.setVis(HudBar.track, UIB.VIS.PASSIVE)
  UIB.setVis(HudBar.fill, UIB.VIS.PASSIVE)
end
function HudBar.hide()
  if not UIB then return end
  if HudBar.posOn and HudBar.posOn() then return end   -- positioning pins the bar visible
  UIB.setVis(HudBar.track, UIB.VIS.HIDE)
  UIB.setVis(HudBar.fill, UIB.VIS.HIDE)
end

-- CARD MIRROR. The Integrated bar dresses the game's weapon cluster, so it must
-- appear and FADE with it -- the cluster's own linger is shorter than the
-- panel's idle window, and a bar floating over a faded card reads as detached.
-- The gauge widget the nameplate census already holds sits inside the cluster
-- subtree: IsVisible catches visibility flips, the ancestor RenderOpacity
-- product catches animated fades. Argless getters only; the first failure
-- disables the mirror for the session and the bar falls back to the idle
-- window. State transitions log (first dozen) so the fade mechanism this build
-- actually uses is on record.
HudBar.cardRef = nil
HudBar.mirrorOff = false
function HudBar.cardState()
  if HudBar.mirrorOff then return true, 1 end
  local gw = HudBar.cardRef
  if not alive(gw) then return true, 1 end
  local ok, vis, eff = pcall(function()
    local v = gw:IsVisible()
    local node, e, depth = gw, 1.0, 0
    while node ~= nil and depth < 10 do
      local o = node:GetRenderOpacity()
      if type(o) == "number" then e = e * o end
      node = safe(function() return node:GetParent() end)
      depth = depth + 1
    end
    return v == true, e
  end)
  if not ok then
    local msg = tostring(vis)
    if msg:find("nullptr", 1, true) then
      -- the census-held wrapper decayed between passes (alive() can pass on a
      -- wrapper whose object is gone): drop it, the next census hands over a
      -- fresh one. Transient, NOT a capability failure -- the 21:02 session
      -- lost the whole mirror to its first decayed wrapper.
      HudBar.cardRef = nil
      return true, 1
    end
    HudBar.mirrorOff = true
    log("[hudbar] card mirror disabled this session: " .. msg)
    return true, 1
  end
  return vis, eff or 1
end
function HudBar.followCard(frac)
  if HudBar.posOn and HudBar.posOn() then
    -- positioning pins the bar visible and opaque regardless of the card
    HudBar.show(frac)
    safe(function() HudBar.track:SetRenderOpacity(1.0); HudBar.fill:SetRenderOpacity(1.0) end)
    return
  end
  local vis, eff = HudBar.cardState()
  local up = vis and eff > 0.05
  if up ~= HudBar._mirrorWas and (HudBar._mirrorLogs or 0) < 12 then
    HudBar._mirrorWas = up
    HudBar._mirrorLogs = (HudBar._mirrorLogs or 0) + 1
    log(string.format("[hudmirror] card %s (vis=%s eff=%.2f)",
        up and "up" or "faded", tostring(vis), eff))
  end
  if up then
    HudBar.show(frac)
    safe(function() HudBar.track:SetRenderOpacity(eff); HudBar.fill:SetRenderOpacity(eff) end)
  else
    HudBar.hide()
  end
end

-- ---- CURSOR POSITIONING MODE (click-grab / click-place) ---------------------
-- Field results rewrote this: the cursor-follow math WORKS (verified in play),
-- but RegisterKeyBind does NOT fire while a menu has focus (F10 lock was dead),
-- and a toggle-off lock is self-defeating (walking the cursor back to the menu
-- drags the bar along). The input path that provably works inside menus is a
-- UMG BUTTON CLICK -- so: while the mode is on, a grab button rides the bar;
-- click to grab, the bar follows the cursor, click again to place. Every
-- placement writes the config immediately.
local PosMode = { on = false, grabbed = false }
HudBar.posOn = function() return PosMode.on end
local WLL
local function posWriteBack(xOff, yOff, wOpt)
  -- the user file lives in Mods/shared beside every other config this family
  -- writes; same path derivation the stores use
  local p = tostring(Darn.dir or "") .. "../../shared/WeaponProficiency_user.lua"
  local t = {}
  local chunk = safe_loadfile(p)
  if chunk then
    local okc, v = pcall(chunk)
    if okc and type(v) == "table" then t = v end
  end
  t.intXOffset, t.intYOffset = math.floor(xOff), math.floor(yOff)
  if wOpt then t.intWidth = math.floor(wOpt) end
  -- placing LOCKS, it does not exit: the mode stays on (bar pinned visible at
  -- its new spot) until the player turns the toggle off, as its help promises
  local parts = { "return {\n" }
  for k, v in pairs(t) do
    local tv = type(v)
    if tv == "number" or tv == "boolean" then
      parts[#parts + 1] = string.format("  %s = %s,\n", k, tostring(v))
    elseif tv == "string" then
      parts[#parts + 1] = string.format("  %s = %q,\n", k, v)
    end
  end
  parts[#parts + 1] = "}\n"
  local f = io.open(p, "w")
  if not f then return false end
  f:write(table.concat(parts))
  f:close()
  return true
end
local function posGrabBtnSync(vx, vy)
  -- the grab button is a VIEWPORT-layer widget: positioned in the same
  -- viewport space the mouse reads in; visible only in positioning mode
  if not (UIB and UIB.alive(HudBar.grabBtn)) then return end
  if not PosMode.on then UIB.setVis(HudBar.grabBtn, UIB.VIS.HIDE); return end
  pcall(function()
    if vx and vy then
      HudBar.grabBtn:SetPositionInViewport({ X = vx, Y = vy }, false)
    elseif PosMode.parkVX and PosMode.parkVY then
      HudBar.grabBtn:SetPositionInViewport(
        { X = PosMode.parkVX, Y = PosMode.parkVY }, false)
    end
    HudBar.grabBtn:SetDesiredSizeInViewport({ X = HudBar.w or 150, Y = 30 })
  end)
  UIB.setVis(HudBar.grabBtn, UIB.VIS.SHOW)
  pcall(function() UIB.setLabel(HudBar.grabBtn,
      PosMode.grabbed and "click to place" or "XP bar -- click to grab") end)
end
local function posSizeBtnSync(vx, vy)
  if not (UIB and UIB.alive(HudBar.sizeBtn)) then return end
  if not PosMode.on then UIB.setVis(HudBar.sizeBtn, UIB.VIS.HIDE); return end
  pcall(function()
    if vx and vy then
      HudBar.sizeBtn:SetPositionInViewport({ X = vx, Y = vy }, false)
    elseif PosMode.parkSizeVX and PosMode.parkSizeVY then
      HudBar.sizeBtn:SetPositionInViewport(
        { X = PosMode.parkSizeVX, Y = PosMode.parkSizeVY }, false)
    end
  end)
  UIB.setVis(HudBar.sizeBtn, UIB.VIS.SHOW)
  pcall(function() UIB.setLabel(HudBar.sizeBtn,
      PosMode.sizing and "click to set" or "resize") end)
end
local function posPlace()
  -- a placement is a SAVE: numbers applied live and written to the config
  PosMode.grabbed = false
  if PosMode.lastX and PosMode.lastY then
    cfg.intXOffset = math.floor(PosMode.lastX)
    cfg.intYOffset = math.floor(PosMode.lastY)
    if HudBar.reanchor then HudBar.reanchor() end
    local okW = posWriteBack(cfg.intXOffset, cfg.intYOffset)
    log(string.format("[hudbar] position PLACED: inset %d, height %d%s",
        cfg.intXOffset, cfg.intYOffset,
        okW and " -- saved" or " -- save failed; set the sliders to these numbers"))
    pcall(function() Toast.notify(string.format(
        "XP bar placed -- inset %d, height %d", cfg.intXOffset, cfg.intYOffset),
        1.0, 0.82, 0.25) end)
  end
  posGrabBtnSync()
end
local function sizePlace()
  -- setting a width is a SAVE, same contract as placing
  PosMode.sizing = false
  if PosMode.lastW then
    cfg.intWidth = math.floor(PosMode.lastW)
    if HudBar.reanchor then HudBar.reanchor() end
    local okW = posWriteBack(tonumber(cfg.intXOffset) or 12,
                             tonumber(cfg.intYOffset) or 42, cfg.intWidth)
    log(string.format("[hudbar] width SET: %d%s", cfg.intWidth,
        okW and " -- saved" or " -- save failed; set the width slider to this number"))
    pcall(function() Toast.notify(string.format(
        "XP bar width set -- %d", cfg.intWidth), 1.0, 0.82, 0.25) end)
  end
  posSizeBtnSync()
end
function HudBar.grabToggle()
  if not PosMode.on then return end
  if PosMode.sizing then sizePlace() end   -- one grab at a time
  if PosMode.grabbed then posPlace() else PosMode.grabbed = true; posGrabBtnSync() end
end
function HudBar.sizeToggle()
  if not PosMode.on then return end
  if PosMode.grabbed then posPlace() end   -- one grab at a time
  if PosMode.sizing then sizePlace() else PosMode.sizing = true; posSizeBtnSync() end
end
local function posTick()
  if not PosMode.on then return end
  pcall(function()
    WLL = WLL or StaticFindObject("/Script/UMG.Default__WidgetLayoutLibrary")
    if not (WLL and WLL:IsValid()) then
      if not PosMode.saidFail then
        PosMode.saidFail = true
        log("[hudbar] position mode unavailable: WidgetLayoutLibrary not found")
      end
      PosMode.on = false
      return
    end
    local ctx = A.localPawn()
    if not ctx then return end
    -- the bar is pinned visible for the whole mode, parked or grabbed
    if UIB and UIB.alive(HudBar.track) then
      UIB.setVis(HudBar.track, UIB.VIS.PASSIVE)
      UIB.setVis(HudBar.fill, UIB.VIS.PASSIVE)
    end
    local vs = WLL:GetViewportSize(ctx)
    local sc = WLL:GetViewportScale(ctx)
    if not (vs and sc and sc > 0) then return end
    local W, H = vs.X / sc, vs.Y / sc
    local w = HudBar.w or 150
    if PosMode.sizing then
      local mp = WLL:GetMousePositionOnViewport(ctx)
      if not mp then return end
      -- the right edge stays anchored; the cursor drags the LEFT edge, so
      -- width = right edge minus cursor, clamped to the slider's own range
      local xOff = tonumber(cfg.intXOffset) or 12
      local newW = math.floor(math.max(60, math.min(600, (W - xOff) - mp.X)))
      PosMode.lastW = newW
      cfg.intWidth = newW               -- anchorBar reads cfg: live preview
      HudBar.w = newW
      if UIB and UIB.alive(HudBar.track) and UIB.alive(HudBar.fill)
         and HudBar.anchorBar then
        HudBar.anchorBar(HudBar.track, newW)
        HudBar.anchorBar(HudBar.fill, math.max(1, math.min(HudBar.lastFillW or 1, newW)))
      end
      pcall(function() HudBar.grabBtn:SetDesiredSizeInViewport({ X = newW, Y = 30 }) end)
      PosMode.parkVX = W - xOff - newW
      PosMode.parkVY = H - (tonumber(cfg.intYOffset) or 42) - 34
      posGrabBtnSync()                  -- move handle stays glued to the bar
      posSizeBtnSync(mp.X - 32, mp.Y - 15)
    elseif PosMode.grabbed then
      local mp = WLL:GetMousePositionOnViewport(ctx)
      if not mp then return end
      local posX = (mp.X - W) - w / 2        -- bar centered under the cursor
      local posY = (mp.Y - H) - 20           -- bar rides just above the handle
      PosMode.curX, PosMode.curY = posX, posY
      PosMode.lastX = -(posX + w)            -- back-solve the config numbers
      PosMode.lastY = -posY
      if UIB and UIB.alive(HudBar.track) and UIB.alive(HudBar.fill) then
        HudBar.track.Slot:SetPosition({ X = posX, Y = posY })
        HudBar.fill.Slot:SetPosition({ X = posX, Y = posY })
      end
      -- the placing click must land on this button, so while grabbed it sits
      -- centered ON the cursor (30px tall, cursor at its vertical middle);
      -- offset above the cursor and the click falls through to the menu
      posGrabBtnSync(mp.X - w / 2, mp.Y - 15)
      posSizeBtnSync(mp.X - w / 2 - 68, mp.Y - 15)   -- rides along, left of the bar
      if not PosMode.said then
        PosMode.said = true
        log(string.format("[hudbar] grabbed: cursor %.0f,%.0f (design %dx%d)",
            mp.X, mp.Y, W, H))
      end
    else
      -- parked: the handles sit above the bar at its CONFIGURED spot, the
      -- width handle just left of the move handle
      PosMode.parkVX = W - (tonumber(cfg.intXOffset) or 12) - w
      PosMode.parkVY = H - (tonumber(cfg.intYOffset) or 42) - 34
      PosMode.parkSizeVX = PosMode.parkVX - 68
      PosMode.parkSizeVY = PosMode.parkVY
      posGrabBtnSync()
      posSizeBtnSync()
    end
  end)
  if PosMode.on and UIB and UIB.defer then UIB.defer(50, posTick) end
end
function HudBar.posModeSync()
  local want = (cfg.panelPosMode == true) and cfg.labFeatures == true
  if want and not PosMode.on then
    PosMode.on, PosMode.said, PosMode.grabbed, PosMode.sizing = true, false, false, false
    PosMode.curX, PosMode.curY = nil, nil
    posGrabBtnSync()
    posSizeBtnSync()
    posTick()
    log("[hudbar] position mode ON -- open any menu for a cursor; click the bar to grab/place it, click 'resize' to drag its width; every click saves. Mode stays on until toggled off.")
  elseif not want and PosMode.on then
    PosMode.on, PosMode.grabbed, PosMode.sizing = false, false, false
    posGrabBtnSync()
    posSizeBtnSync()
    if HudBar.reanchor then HudBar.reanchor() end
  end
end
-- Player editing of Living Arsenal in DarnMenu disabled per server configuration
if false then
ToastLib.registerMenuSchema("WeaponProficiency", 38, [==[
-- Weapon Proficiency options page (registered by the mod; regenerated on version bump)
return {
  schemaVersion = 38,
  tab = "Living Arsenal", order = 40, target = "WeaponProficiency_user",
  live = true,
  note = "Multipliers, toggles and the panel's position/opacity apply live; the panel on/off switch, nameplate and progression scope need a relaunch.",
  applyNote = "Saved. Multipliers, toggles and the panel position are live now; panel on/off, nameplate and scope need a relaunch.",
  defaults = { darnHud = true, levelUpToasts = true, measureHps = false,
               applyDamage = true, applyMagazine = true, applyDurability = true,
               capToPlayerLevel = true, dmgMult = 1.0, xpMult = 1.0,
               durabilityMaxMult = 3.0, magMaxMultiplier = 1, curvePower = 0.5,
               targetXp = true, progressScope = "instance", persistBoost = true,
               restoreToStock = false, bootReport = true,
               panelAutoHide = true, panelIdleSec = 2, nameplateInfo = true, barColor = "gold",
               panelOnAim = true,
               panelOpacity = 100, gradeEdge = 0, tierEdge = 0.05, skipUntestedWeapons = false,
               applyUnsupported = false,
               untestedToast = true, sanityHps = true,
               panelAnchor = "right", panelXOffset = 16, panelYFrac = 0.78,
               panelYOffset = 0, panelStyle = "panel",
               intXOffset = 12, intYFrac = 0.86, intYOffset = 42, intWidth = 150, panelPosMode = false,
               pillXOffset = 16, pillYFrac = 0.78, pillYOffset = 0,
               stripXOffset = 16, stripYFrac = 0.78, stripYOffset = 0,
               prestigeEnabled = true, prestigeToasts = true, prestigeHudSummary = true, prestigeDamagePerPt = 0.01,
               prestigePctPerPt = 0.01,
               prestigeMagPerPt = 1, prestigeDurPerPt = 0.10, prestigeCapStepPct = 0.05,
               prestigeGrindMult = 1.2, prestigeRequireMaxLevel = false, prestigeMinClimb = 15 },
  sections = {
    { title = "Prestige",
      note = "Bring a weapon to its cap, then bank a permanent point into a stat. Each prestige resets that weapon's level; the climb grows a little longer each time. Only stats that make sense for the equipped weapon are offered.",
      custom = { type = "actionpanel", file = "WeaponProficiency_prestige.lua",
        statusKey = "status", requestKey = "request",
        emptyText = "Equip a weapon and bring it to its cap to prestige it.",
        options = { { value = "dmg", label = "+Base Damage" }, { value = "pct", label = "+% Damage" },
                    { value = "mag", label = "+Magazine" }, { value = "dur", label = "+Durability" },
                    { value = "cap", label = "+Level Cap %" } } } },
    { title = "Prestige settings", options = {
        { path = "prestigeHudSummary", label = "Show prestige benefits on the aim panel", kind = "bool", live = true,
          help = "Adds a row to the weapon tile listing the cumulative effect of every banked point (+dmg, +mag, +dur, +cap). The same line shows beside the weapon at the top of this page." },
        { path = "prestigeEnabled", label = "Enable prestige", kind = "bool", live = true,
          help = "master switch for the whole prestige system" },
        { path = "prestigeRequireMaxLevel", label = "Require max level", kind = "bool", live = true,
          help = "ON: a weapon must reach its true max (Lv 80) before it can prestige. OFF: it can prestige after climbing the levels below." },
        { path = "prestigeMinClimb", label = "Levels to unlock (if not max)", kind = "number",
          min = 1, max = 79, step = 1, integer = true, live = true, dependsOn = "prestigeEnabled",
          help = "levels above a weapon's base level before prestige unlocks (ignored when Require max level is ON). 15 = a Lv3 bow unlocks at Lv18" },
        { path = "prestigeDamagePerPt", label = "+Base Damage per point", kind = "number",
          min = 0, max = 1, step = 0.01, live = true, help = "0.01 = +1% of BASE damage per point, flat (rounded up)" },
        { path = "prestigePctPerPt", label = "+% Damage per point", kind = "number",
          min = 0, max = 1, step = 0.01, live = true, help = "0.01 = x1.01 per point on TOTAL scaled damage (compounds with the curve)" },
        { path = "prestigeMagPerPt", label = "+Magazine per point", kind = "number",
          min = 0, max = 20, step = 1, integer = true, live = true, help = "extra rounds per point (auto weapons)" },
        { path = "prestigeDurPerPt", label = "+Durability per point", kind = "number",
          min = 0, max = 1, step = 0.01, live = true, help = "0.10 = +10% MaxDurability per point" },
        { path = "prestigeCapStepPct", label = "+Level cap % per point", kind = "number",
          min = 0, max = 0.5, step = 0.01, live = true, help = "extra levels the weapon may climb, per point" },
        { path = "prestigeGrindMult", label = "Grind growth per point", kind = "number",
          min = 1, max = 5, step = 0.1, live = true, help = "1.2 = each prestige makes the next climb 20% longer; 1 = no escalation" },
        { path = "prestigeToasts", label = "Prestige toasts", kind = "bool", live = true },
    }},
    { title = "Display", options = {
        { path = "darnHud", label = "Weapon panel", kind = "bool", live = false,
          help = "the live progress panel beside the weapon scroll" },
        { path = "panelStyle", label = "Panel style", kind = "enum", live = true,
          dependsOn = "darnHud", values = {
            { value = "panel",  label = "Darn glass (default)" },
            { value = "pill",   label = "Classic pill" },
            { value = "native", label = "Native look (flat strip)" } },
          help = "Darn glass is a slab like the game's weapon-pickup tile. Applies live." },
        { path = "barColor", label = "XP bar color", kind = "enum", live = true,
          values = {
            { value = "gold",    label = "Gold" },
            { value = "sky",     label = "Sky blue" },
            { value = "emerald", label = "Emerald" },
            { value = "crimson", label = "Crimson" },
            { value = "white",   label = "White" },
            { value = "violet",  label = "Violet" } },
          help = "The XP bar's fill color, in every style." },
        { path = "pillYFrac", label = "Classic pill: vertical spot", kind = "number",
          min = 0, max = 1, step = 0.005, live = true, dependsOn = "panelStyle", dependsValue = "pill",
          help = "Each style keeps its own position. This one is the Classic pill's." },
        { path = "pillXOffset", label = "Classic pill: X offset (px)", kind = "number",
          min = 0, max = 2000, step = 5, integer = true, live = true, dependsOn = "panelStyle", dependsValue = "pill" },
        { path = "pillYOffset", label = "Classic pill: Y offset (px)", kind = "number",
          min = -2000, max = 2000, step = 5, integer = true, live = true, dependsOn = "panelStyle", dependsValue = "pill" },
        { path = "stripYFrac", label = "Native strip: vertical spot", kind = "number",
          min = 0, max = 1, step = 0.005, live = true, dependsOn = "panelStyle", dependsValue = "native",
          help = "Each style keeps its own position. This one is the Native strip's." },
        { path = "stripXOffset", label = "Native strip: X offset (px)", kind = "number",
          min = 0, max = 2000, step = 5, integer = true, live = true, dependsOn = "panelStyle", dependsValue = "native" },
        { path = "stripYOffset", label = "Native strip: Y offset (px)", kind = "number",
          min = -2000, max = 2000, step = 5, integer = true, live = true, dependsOn = "panelStyle", dependsValue = "native" },
        { path = "panelAutoHide", label = "Auto-hide when idle", kind = "bool",
          dependsOn = "darnHud",
          help = "panel sleeps between fights and wipes back in on your next shot; OFF = always shown" },
        { path = "panelIdleSec", label = "Idle seconds before hiding", kind = "number",
          min = 0.5, max = 30, step = 0.5, dependsOn = "panelAutoHide",
          help = "how long without a shot or hit before the panel hides" },
        { path = "panelOnAim", label = "Show while aiming", kind = "bool",
          dependsOn = "panelAutoHide",
          help = "aiming down sights brings the panel back and holds it there while you aim -- "
              .. "the moment you most want to know what the gun actually does" },
        { path = "panelOpacity", label = "Panel opacity %", kind = "number",
          min = 10, max = 100, step = 5, integer = true, live = true, dependsOn = "darnHud",
          help = "how solid the weapon panel draws -- OUR panel, so the setting lives here, not on the Toasts page" },
        { path = "nameplateInfo", label = "Level on weapon nameplate", kind = "bool", live = true,
          help = "EXPERIMENTAL: shows Lv and +dmg% on the hotbar's weapon name band" },
        { path = "levelUpToasts", label = "Level-up toasts", kind = "bool" },
    }},
    { title = "Panel position", options = {
        { path = "panelAnchor", label = "Anchor", kind = "enum", live = true, dependsOn = "darnHud",
          values = { { value = "left",   label = "Left edge" },
                     { value = "center", label = "Center" },
                     { value = "right",  label = "Right edge" } },
          help = "which edge the weapon panel sits against. Moves as soon as you press Apply" },
        { path = "panelXOffset", label = "X offset (px)", kind = "number",
          min = -2000, max = 2000, step = 10, integer = true, dependsOn = "panelStyle", dependsValue = "panel", live = true, 
          help = "distance from that edge; with Center it nudges off the middle" },
        { path = "panelYFrac", label = "Vertical spot", kind = "number",
          min = 0, max = 1, step = 0.05, live = true, dependsOn = "panelStyle", dependsValue = "panel",
          help = "0 = top of screen, 1 = bottom. Default 0.78 sits just above the weapon display, bottom right" },
        { path = "panelYOffset", label = "Y offset (px)", kind = "number",
          min = -2000, max = 2000, step = 10, integer = true, dependsOn = "panelStyle", dependsValue = "panel", live = true, 
          help = "fine tuning, applied after the vertical spot" },
    }},
    { title = "Progression", options = {
        { path = "untestedToast", label = "Warn on untuned weapons", kind = "bool", live = true,
          dependsOn = "skipUntestedWeapons",
          help = "when you equip a weapon that's left vanilla because its damage was never measured, show a one-time notice naming the setting that includes it" },
        { path = "applyUnsupported", label = "Level modded weapons", kind = "bool", live = true,
          help = "OFF (recommended): weapons added by OTHER mods -- the Terraria crossover set and anything like it -- are left fully vanilla. Their stats are on no data source we can check, and they change whenever that mod updates. Their fire rates are ESTIMATED rather than measured too, so the curve rests on a guess at both ends. ON levels them anyway, on those unverified numbers." },
        { path = "skipUntestedWeapons", label = "Tested weapons only", kind = "bool", live = true,
          help = "SAFETY (recommended ON): only scale weapons whose damage was actually measured and a curve built. Untested weapons stay fully vanilla until verified. OFF = scale every weapon in the library (may misbehave on untested ones)." },
        { path = "applyDamage", label = "Damage scaling", kind = "bool",
          help = "weapons hit harder as they level" },
        { path = "applyMagazine", label = "Magazine scaling", kind = "bool" },
        { path = "dmgMult", label = "Damage bonus multiplier", kind = "number",
          min = 0, max = 5, step = 0.1,
          help = "scales the bonus only: 0.5 = half growth, 2 = double, 0 = flat" },
        { path = "gradeEdge", label = "Rarity edge per grade", kind = "number",
          min = 0, max = 0.25, step = 0.01, live = true,
          help = "how much better each rarity ends up: 0.06 = a Legendary finishes ~26% above a Common of the same weapon. 0 = every rarity ends identical" },
        { path = "tierEdge", label = "Tech tier debuff per tier", kind = "number",
          min = 0, max = 0.15, step = 0.01, live = true,
          help = "tier = the decade of a weapon's tech level (0-9 = T1 ... 70-80 = T8). Each tier aims this much lower than the tier above, so a later unlock ends up stronger. 0 = tech level does not matter" },
        { path = "xpMult", label = "XP multiplier", kind = "number",
          min = 0.1, max = 10, step = 0.1,
          help = "2 = weapons level twice as fast" },
        { path = "capToPlayerLevel", label = "Cap to player level", kind = "bool",
          help = "a weapon cannot out-level its wielder" },
        { path = "progressScope", label = "Progression scope", kind = "enum", live = false,
          values = { { value = "instance", label = "Each weapon its own" },
                     { value = "model",    label = "All copies share" },
                     { value = "family",   label = "All rarities share" } },
          help = "Each weapon its own: this exact gun levels, and a second copy of it starts "
              .. "at zero. All copies share: every copy of that exact weapon shares one level "
              .. "-- but rarities count as different weapons, so a Legendary and an Epic of "
              .. "the same gun still level separately. All rarities share: they do not, so "
              .. "the work you put into a Common is waiting on the Legendary you loot. "
              .. "SWITCHING KEEPS YOUR PROGRESS: level, XP, "
              .. "hits and prestige stars all carry forward, but the HIGHEST of your copies "
              .. "wins each one -- prestige is carried per stat, not added up across copies, so "
              .. "two guns with 3 damage stars each become one with 3, not 6. Nothing is "
              .. "deleted: your old per-copy records stay exactly where they were, so switching "
              .. "back restores them." },
        { path = "persistBoost", label = "Keep bonuses when stowed", kind = "bool", live = false,
          help = "on: a weapon keeps its bonuses after you put it away, so every copy in your "
              .. "bags is boosted too and anything still fighting for you -- Terraprisma "
              .. "summons, most of all -- keeps the bigger durability bar while you hold "
              .. "something else. off: bonuses last only while the weapon is in your hands. "
              .. "Needs a progression scope of All copies or All rarities: with Each weapon "
              .. "its own, two copies of one weapon can be different levels but share one "
              .. "damage value, so a bonus left on would follow you onto the wrong copy. The "
              .. "trade is that bonuses are no longer cleared when you swap, so a weapon "
              .. "keeps them if you remove the mod." },
        { path = "restoreToStock", label = "Restore everything to stock", kind = "bool", live = false,
          help = "For uninstalling. Stops all scaling and puts every weapon you own back to its "
              .. "stock damage, magazine and durability -- including the ones you are not "
              .. "holding. Turn it on, play for a few seconds, then remove the mod. Your levels "
              .. "and prestige are not touched, so turning it back off restores your bonuses. "
              .. "Durability keeps its current fill, so this is not a free repair." },
        { path = "applyDurability", label = "Durability scaling", kind = "bool" },
        { path = "durabilityMaxMult", label = "Durability cap multiplier", kind = "number",
          min = 1, max = 10, step = 0.5,
          help = "how much longer a max-level weapon lasts (3 = 3x)" },
        { path = "magMaxMultiplier", label = "Magazine cap multiplier", kind = "number",
          min = 1, max = 5, step = 0.5,
          help = "raises the magazine ceiling: 1 = vanilla rarity cap" },
        { path = "curvePower", label = "XP curve shape", kind = "number",
          min = 0.1, max = 1, step = 0.05,
          help = "shape of the grind. 1 = levels rush in early then crawl late. Lower = a flatter, steadier pace. 0.5 default" },
        { path = "targetXp", label = "Enemy-based XP", kind = "bool",
          help = "big enemies pay more XP; OFF = every hit pays the same" },
    }},
    { title = "Measurement", options = {
        { path = "measureHps", label = "Fire-rate logging", kind = "bool",
          help = "one log line per shot/reload -- ON only while measuring a weapon" },
        { path = "sanityHps", label = "XP sanity cap", kind = "bool", live = true,
          help = "measured weapons cannot earn hits far beyond their measured fire rate -- excess credits (usually misattributed hits from summons or pals) are ignored" },
    }},
  },
}
]==])
end

-- LIVE SETTINGS: the whitelisted knobs below are read at use time (per tick /
-- per hit / per draw), so menu edits land without a relaunch. Deliberately NOT
-- live: darnHud + nameplateInfo (display hooks installed at boot) and
-- progressScope (re-keys the store -- switching mid-session would fork
-- progress). Those still need a relaunch.
local LIVE_KEYS = {
  dmgMult = true, xpMult = true, durabilityMaxMult = true, magMaxMultiplier = true,
  curvePower = true, targetXp = true, levelUpToasts = true, capToPlayerLevel = true,
  applyDamage = true, applyMagazine = true, applyDurability = true,
  panelAutoHide = true, panelIdleSec = true, measureHps = true, panelOpacity = true,
  panelOnAim = true,
  -- panelStyle was schema-live but ABSENT here (2026-08-10): Maiq selected
  -- Integrated and the running game ignored the Apply -- the third
  -- lists-must-agree bug of the day. A schema `live = true` without its
  -- LIVE_KEYS entry is a lie the player pays for.
  panelStyle = true, prestigeHudSummary = true,
  -- nameplateInfo IS LIVE NOW (2026-08-12). It gates the single most expensive thing this mod
  -- does -- the nameplate census, two FindAllOf walks plus a text read per row, MEASURED at
  -- 11-77ms per fire -- and since that census moved onto the game thread (for the Slate
  -- shaping-cache race) those milliseconds land in frames instead of on a background thread.
  -- Being able to trade the nameplate for smooth frames WITHOUT a relaunch is worth more than
  -- the tidiness of leaving it boot-only. It is re-read on every census pass, so live costs
  -- nothing to support. Schema `live` flipped to match -- a schema live=true without a
  -- LIVE_KEYS entry is a lie the player pays for, and so is the reverse.
  nameplateInfo = true,
  panelAnchor = true, panelXOffset = true, panelYFrac = true, panelYOffset = true,
  intXOffset = true, intYFrac = true, intYOffset = true, intWidth = true,
  barColor = true,
  panelPosMode = true,
  pillXOffset = true, pillYFrac = true, pillYOffset = true,
  stripXOffset = true, stripYFrac = true, stripYOffset = true,
  gradeEdge = true, tierEdge = true, skipUntestedWeapons = true, untestedToast = true,
  applyUnsupported = true, sanityHps = true,
  prestigeEnabled = true, prestigeToasts = true, prestigeDamagePerPt = true,
  prestigePctPerPt = true,
  prestigeMagPerPt = true, prestigeDurPerPt = true, prestigeCapStepPct = true,
  prestigeGrindMult = true, prestigeRequireMaxLevel = true, prestigeMinClimb = true,
}
-- progression.lua takes cfg per call for everything EXCEPT the rarity edge, which
-- P.multiplier reads off the module (it has no cfg upvalue). Mirror it at boot and
-- on every Apply so the menu's green dot stays honest.
-- tierEdge rides the same path for the same reason: P.multiplier reads it off the module.
-- Missing it here is how gradeEdge's menu dot went stale before -- do not add one without
-- the other.
local function syncGradeEdge()
  P.gradeEdge = tonumber(cfg.gradeEdge) or 0.06
  P.tierEdge  = tonumber(cfg.tierEdge)  or 0.05
end
syncGradeEdge()
-- P.addXp reads the grind multiplier off the module (no cfg upvalue), like gradeEdge.
local function syncPrestige()
  P.prestigeGrindMult = tonumber(cfg.prestigeGrindMult) or 1
end
syncPrestige()
-- our CUSTOM panel's style AND POSITION are OUR job (channel model): nothing on
-- the Toasts page can reach a custom surface, so if we don't push it, no one can.
-- THE FALLBACK ABOVE MUST ACTUALLY DEGRADE (2026-07-31 -- a player's whole mod was dead).
-- `Panel` falls back to `Toast` when DarnToasts is pre-2.0, and a 1.x Toast has NO
-- configure() -- so this line raised "attempt to call a nil value (field 'configure')" at
-- LOAD, from the main chunk, and Living Arsenal failed to start AT ALL. Every weapon then
-- looks untracked, which is what the report described ("the bow isn't recognized").
-- Measured from the reporter's log: DarnToasts v1.0.0 installed, LA 1.8.0+ assumed 2.1+.
--
-- A missing panel control is a COSMETIC loss (the panel sits where 1.x put it); killing the
-- mod over it is not a trade anyone would choose. Guarded, and it says so once so the player
-- knows why the position sliders do nothing and what to update.
local panelWarned = false
local function syncPanel()
  if type(Panel) ~= "table" or type(Panel.configure) ~= "function" then
    if not panelWarned then
      panelWarned = true
      log("panel position not available -- DarnToasts is older than 2.1.0 (custom surfaces). "
        .. "Everything else works; update DarnToasts to move or restyle the weapon panel.")
    end
    return
  end
  -- One source of truth per style: birth and every live Apply route through
  -- stylePos(), so a style switch restores that style's own saved place.
  local p = stylePos()
  p.opacity = tonumber(cfg.panelOpacity) or 100
  Panel.configure(p)
  -- the UMG bar re-reads its design-unit anchors on the same Apply
  if HudBar.reanchor then HudBar.reanchor() end
end
-- The bare style's surface is a 6px bar pinned to the weapon card -- no home
-- for a text sticky (the standby notice rendered skinless, half off screen,
-- bottom right). Standby/wake notices borrow the glass panel's geometry for
-- their lifetime; every dismissal path re-syncs the style's own config.
HudBar.sbConfigure = function()
  if cfg.panelStyle ~= "bare" then return end
  local p = stylePos("panel")
  p.opacity = tonumber(cfg.panelOpacity)
  pcall(function() Panel.configure(p) end)
end
syncPanel()   -- at boot...
if HudBar.posModeSync then HudBar.posModeSync() end   -- a saved ON resumes positioning
Darn.watchConfig("WeaponProficiency_user", function(u)
  local n = 0
  for k, v in pairs(u) do
    if LIVE_KEYS[k] and type(cfg[k]) == type(v) and cfg[k] ~= v then
      cfg[k] = v
      n = n + 1
    end
  end
  -- repeat the flat->nested mapping the boot overlay does
  if type(cfg.targetXp) == "boolean" and type(cfg.targetScaling) == "table" then
    cfg.targetScaling.enabled = cfg.targetXp
  end
  -- ...and live on every menu Apply (the green dots stay honest: the panel moves
  -- and restyles as you press Apply, no relaunch)
  syncPanel()
  syncGradeEdge()
  syncPrestige()
  if HudBar.posModeSync then HudBar.posModeSync() end
  if n > 0 then log("[live] " .. n .. " setting(s) applied without relaunch") end
end)

local VERSION = Darn.version()
local POLL_MS = 250

-- ---- DATA VALIDATION (1.4.0): the game is the ground truth ------------------
-- weapondata.lua began life as scrapes and guesses; the game's own item
-- definitions carry the real base damage / magazine / durability (the katana
-- saga showed what stale guesses cost). At boot, compare every library row
-- against GetStaticItemData and correct drifted values IN MEMORY (all modules
-- share the required weapondata table, so damage/XP/HUD reprice live). A game
-- patch that rebalances weapons is caught on the first boot, logged [DATA].
local function validateWeapondata()
  local mgr = safe(function() return FindFirstOf("PalItemIDManager") end)
  if not alive(mgr) then return false end
  local checked, fixed, readable, sampled = 0, 0, 0, 0
  for id, row in pairs(WD.WEAPONS) do
    local sd = safe(function() return mgr:GetStaticItemData(FName(id)) end)
    if alive(sd) then
      checked = checked + 1
      local av = safe(function() return sd.AttackValue end)
      if type(av) == "number" then
        readable = readable + 1
        -- proof-of-comparison: show the first few real reads so "0 corrected"
        -- is distinguishable from "read nothing"
        if sampled < 3 then
          sampled = sampled + 1
          log(string.format("[DATA] sample %-24s game: atk=%s mag=%s dur=%s | ours: base=%s mag=%s dur=%s",
            id, tostring(av), tostring(safe(function() return sd.MagazineSize end)),
            tostring(safe(function() return sd.Durability end)),
            tostring(row.base), tostring(row.mag), tostring(row.dur)))
        end
      end
      local function correct(field, gameVal)
        if type(gameVal) == "number" and gameVal > 0 and type(row[field]) == "number"
           and math.abs(row[field] - gameVal) > 0.5 then
          log(string.format("[DATA] %-24s %s %s -> %s (game truth)", id, field,
            tostring(row[field]), tostring(gameVal)))
          row[field] = gameVal
          fixed = fixed + 1
        end
      end
      correct("base", safe(function() return sd.AttackValue end))
      if (row.mag or 0) > 0 then
        correct("mag", safe(function() return sd.MagazineSize end))
      end
      correct("dur", safe(function() return sd.Durability end))
    end
  end
  log(string.format("[DATA] validation: %d/%d rows resolved, %d with readable combat fields, %d corrected",
    checked, (function() local n = 0; for _ in pairs(WD.WEAPONS) do n = n + 1 end; return n end)(),
    readable, fixed))
  return true
end
local valTries = 0
local function tryValidate()
  if cfg.dataValidate == false then return end
  -- boot stand-down (2026-08-03 launch-CTD family): the validator reads DataTable combat
  -- fields from a 3s-post-load timer, i.e. mid-boot-streaming. Wait out the kit's walkSafe;
  -- a standing-down attempt does not consume one of the 40 tries.
  local okUI, UIk = pcall(Darn.requireUI)
  if okUI and type(UIk) == "table" and UIk.walkSafe and not UIk.walkSafe() then
    ExecuteWithDelay(3000, tryValidate)
    return
  end
  valTries = valTries + 1
  local ok = false
  pcall(function() ok = validateWeapondata() end)
  if not ok and valTries < 40 then ExecuteWithDelay(3000, tryValidate) end
end
ExecuteWithDelay(3000, tryValidate)

-- ---- AUTO-HPS-RECALC crossover report (2026-07-21) --------------------------
-- Every damage number already derives live from weapondata hps (nat = hps*base),
-- so an hps edit reprices everything by itself at the next boot. This pass makes
-- the result VISIBLE instead of a surprise: each OWNED weapon's crossover level
-- (where its ladder passes nat -- +0% damage until then) goes to the UE4SS log,
-- and the full per-model table is rewritten to crossover-report.txt beside the
-- store. A weapon "stuck at +0%" is answered by one glance at either.
local function reportCrossovers(store)
  local w = Counting.states() and Counting.states()[Counting.worldKey()]
  if w then
    for id, st in pairs(w) do
      if type(st) == "table" and st.level ~= nil then
        local spec = Counting.specFor(id)
        if spec then
          local x = P.crossover(spec)
          local nat = math.floor((spec.hps or 0) * (spec.base or 0) + 0.5)
          local lv = st.level or 0
          if x == nil then
            log(string.format("XOVER %-26s Lv%-3d no ladder (stock damage)", Counting.staticOf(id), lv))
          elseif x == false then
            log(string.format("XOVER %-26s Lv%-3d nat %d ABOVE ladder top -- never boosted", Counting.staticOf(id), lv, nat))
          elseif math.ceil(x) > lv then
            log(string.format("XOVER %-26s Lv%-3d +0%% damage until Lv%d  (nat %d, hps %.2f %s)",
              Counting.staticOf(id), lv, math.ceil(x), nat, spec.hps or 0,
              -- through the lookup funnel, not a raw WEAPONS read: under family scope the key
              -- is "fam:AssaultRifle" and the raw read has no row to find, so the rate's
              -- provenance printed as "?" on a weapon whose rate is actually measured
              (Counting.wdLookup(id) or {}).hpsSrc or "?"))
          else
            local mult = P.multiplier(spec, lv, cfg.dmgCurve, cfg.dmgPower)
            log(string.format("XOVER %-26s Lv%-3d +%d%% damage  (crossed Lv%d, nat %d)",
              Counting.staticOf(id), lv, math.floor((mult - 1) * 100 + 0.5), math.ceil(x), nat))
          end
        end
      end
    end
  end

  local dir = tostring(store.path or ""):match("^(.*[/\\])") or ""
  local f = safe(function() return io.open(dir .. "crossover-report.txt", "w") end)
  if not f then return end
  f:write("WeaponProficiency damage-crossover report -- REGENERATED EVERY BOOT\n")
  f:write("crossover = level where the category ladder passes natural DPS (hps*base);\n")
  f:write("a weapon shows +0% damage until then. Edit hps in weapondata.lua and this\n")
  f:write("table, the log lines, and the HUD all reprice automatically at next boot.\n\n")
  local list = {}
  for id, row in pairs(WD.WEAPONS) do
    local ladder = P.LADDER[row.t]
    if ladder then
      list[#list + 1] = { id = id, row = row, ladder = ladder,
                          -- start/grade matter to crossover since it became unlock-anchored;
                          -- omitting them made this report answer for a Common at the ladder's
                          -- first anchor instead of for the row in hand.
                          x = P.crossover({ hps = row.hps, base = row.base, type = row.t,
                                            start = row.start, grade = Counting.gradeOf(id) }) }
    end
  end
  table.sort(list, function(a, b)
    if a.ladder ~= b.ladder then return a.ladder < b.ladder end
    local ax = (a.x == false) and math.huge or (a.x or -1)
    local bx = (b.x == false) and math.huge or (b.x or -1)
    if ax ~= bx then return ax < bx end
    return a.id < b.id
  end)
  local cur
  for _, e in ipairs(list) do
    if e.ladder ~= cur then cur = e.ladder; f:write(string.format("\n== %s ==\n", cur)) end
    local nat = math.floor((e.row.hps or 0) * (e.row.base or 0) + 0.5)
    local when
    if e.x == nil then when = "stock (no nat)"
    elseif e.x == false then when = "NEVER (nat above ladder top)"
    else when = string.format("dmg from Lv%d", math.ceil(e.x)) end
    f:write(string.format("%-28s unlock Lv%-3s nat %-6d %-30s (hps %.2f %s)\n",
      e.id, tostring(e.row.start or "?"), nat, when, e.row.hps or 0, e.row.hpsSrc or "?"))
  end
  f:close()
  log("crossover report written: " .. dir .. "crossover-report.txt")
end

-- ---- panel state -----------------------------------------------------------
local lastId, lastShownId = nil, nil
local seenLevel, toastText = {}, nil
local warnedNoGuid = {}
-- one heads-up per weapon MODEL per session (keyed on the static id, so swapping
-- between two copies of the same gun doesn't re-toast)
local untestedToasted = {}

-- ---- PRESTIGE BRIDGE -------------------------------------------------------
-- A single shared file DarnMenu's Prestige panel and this mod pass over: WE
-- publish `status` (which weapon, stars, whether it's at cap, allowed stats);
-- the menu writes `request = { stat, seq }` when a tile is clicked; we execute
-- it once and echo `ackSeq`. Same file both write, but only ever their own keys
-- (read-merge-write), and the seq/ack pair makes a click act exactly once.
local prestigePath = nil          -- resolved at boot from the store's shared dir
local olfActivityPath = nil       -- shared/olf-activity.txt (census loot-burst stand-down)
local lastAckSeq = nil            -- request seq we've already run this session
local lastStatusSig = nil         -- only rewrite the file when the status changes
local prestigeToastText = nil     -- set when a prestige lands; consumed by the tick
local prestigeReady = false       -- current weapon is at cap (drives the panel hint)
local lastPrestigePoll = 0        -- throttle the file I/O to ~1s

local function serLua(v)
  local t = type(v)
  if t == "string" then return string.format("%q", v) end
  if t == "number" then return (v == math.floor(v)) and string.format("%d", v) or string.format("%.10g", v) end
  if t == "boolean" then return tostring(v) end
  if t == "table" then
    local parts, n = {}, #v
    for i = 1, n do parts[#parts + 1] = serLua(v[i]) end
    for k, val in pairs(v) do
      if not (type(k) == "number" and k >= 1 and k <= n and k == math.floor(k)) then
        local key = (type(k) == "string" and k:match("^[%a_][%w_]*$")) and k or ("[" .. serLua(k) .. "]")
        parts[#parts + 1] = key .. "=" .. serLua(val)
      end
    end
    return "{" .. table.concat(parts, ",") .. "}"
  end
  return "nil"
end

local function readPrestige()
  if not prestigePath then return {} end
  local chunk = safe(function() return safe_loadfile(prestigePath) end)
  if not chunk then return {} end
  local ok, t = pcall(chunk)
  return (ok and type(t) == "table") and t or {}
end

local function writePrestige(t)
  if not prestigePath then return false end
  local tmp = prestigePath .. ".tmp"
  local f = safe(function() return io.open(tmp, "w") end); if not f then return false end
  local okW = pcall(function() f:write("return " .. serLua(t) .. "\n") end); f:close()
  if not okW then return false end
  pcall(function() os.remove(prestigePath) end)
  return pcall(function() assert(os.rename(tmp, prestigePath)) end)
end

-- IN-GAME prestige surfaces (ESC-menu badge + inventory-slot star), built on
-- DarnUI's UI.overlay. Installed ONCE at load (the overlays only fire when a menu
-- opens, long after prestigePath resolves; readPrestige/writePrestige close over
-- it). A missing/unsubscribed DarnUI must cost ONLY these surfaces, never the mod
-- -- so pcall the whole thing (prestige_ui's `require "ui"` runs at its load). The
-- Prestige tab in DarnMenu keeps working regardless (it uses the same bridge).
do
  local okPUI, PrestigeUI = pcall(require, "prestige_ui")
  if okPUI and type(PrestigeUI) == "table" and PrestigeUI.install then
    local ok, err = pcall(PrestigeUI.install, {
      Darn = Darn, log = log,
      readBridge = readPrestige, writeBridge = writePrestige,
    })
    if not ok then log("prestige UI install failed (badge/star off): " .. tostring(err)) end
  else
    log("DarnUI not available -- prestige badge/star off (Prestige tab still works)")
  end
end

-- Runs (throttled) from the tick for the currently equipped weapon.
local function prestigeSync(id, wlv)
  if not prestigePath or cfg.prestigeEnabled == false then prestigeReady = false; return end
  local file = readPrestige()
  local status = Counting.prestigeStatus(id, wlv)
  local wrote = false
  -- 1) a queued click from the menu (act once via seq/ack)
  local req = file.request
  if type(req) == "table" and tonumber(req.seq) and req.seq ~= file.ackSeq and req.seq ~= lastAckSeq then
    local ok, a, b = Counting.prestige(id, tostring(req.stat or ""), wlv)
    lastAckSeq = req.seq; file.ackSeq = req.seq
    if ok then
      prestigeToastText = string.format("%s  PRESTIGE  \226\152\133%d", tostring(b or "Weapon"), tonumber(a) or 0)
      status = Counting.prestigeStatus(id, wlv)   -- refresh after the level reset
    else
      log("prestige rejected: " .. tostring(a))
    end
    file.status = status or file.status
    writePrestige(file); wrote = true
  end
  prestigeReady = (status and status.eligible) or false
  -- 2) publish status when it changed (avoids constant disk writes)
  if status then
    local sig = table.concat({ status.weapon, status.level, tostring(status.eligible),
                               status.stars or 0, table.concat(status.allowed or {}, ",") }, "|")
    if not wrote and sig ~= lastStatusSig then
      file.status = status
      writePrestige(file)
    end
    lastStatusSig = sig
  end
end

local function checkToast(id, name, level)
  local prev = seenLevel[id]; seenLevel[id] = level
  if prev == nil then return false end
  if level <= prev then return false end
  toastText = string.format("%s  proficiency  Lv%d", name, level)
  log("*** " .. toastText .. " ***")
  return true
end


local panelWakeAt = 0             -- weapon switches also wake the panel
local prevPanelId = nil
local wcCache = nil               -- the vanilla lower-right weapon widget (revalidated)
local nameplateDumped = false     -- one-shot [NPTREE] structure dump
local npWriteAt = 0               -- throttle for [NPWRITE]; declared HERE because a bare
                                  -- assignment at the write site would compile as a global
local npDbgAt = nil               -- [NPDBG] throttle
local npCensusAt = 0              -- last nameplate census (see the gate at the census block)
local function tick()
  local tickOk, tickErr = pcall(function()
    -- boot/join stand-down (2026-08-03 launch-CTD family): this body FindAllOf-walks gauge and
    -- weapon-wheel widgets; a walk during streaming is a sentinel AV no pcall stops.
    do
      local okUI, UIk = pcall(Darn.requireUI)
      if okUI and type(UIk) == "table" and UIk.walkSafe and not UIk.walkSafe() then
        -- STANDBY RE-POST (2026-08-04, "no visual indication" persisted): the boot block's
        -- single post raced the HUD -- no HUD existed yet, and the panel surface's hook-retry
        -- backoff can stall up to ~30s. progress() re-arms the hook on every call, so
        -- re-posting every ~2s of the quiet window renders the notice the moment a HUD lives.
        if DARN and cfg.darnHud ~= false then
          cfg._sbN = (cfg._sbN or 0) + 1
          if cfg._sbN % 8 == 1 then
            if HudBar.sbConfigure then HudBar.sbConfigure() end
            pcall(function() Panel.progress("weapon", { text = "Living Arsenal standing by",
              sub = "wakes once the world settles (~1 min)", frac = 0, r = 0.6, g = 0.75, b = 1.0 }) end)
          end
          cfg._sbWakeAt = nil
        end
        return
      end
    end
    local pawn = A.localPawn()
    if not pawn then return end     -- not in world yet
    A.meleeSweep()                  -- slow-path only; internally throttled + sticky
    -- the panel is ON or OFF, period: DarnToasts present + darnHud enabled
    local showPanel = DARN and cfg.darnHud ~= false
    -- IDLE FADE (panelAutoHide checkbox): the panel hides after panelIdleSec
    -- seconds with no shot/hit and wipes back in on the next one (or a weapon
    -- switch). Unchecked = original always-shown behavior.
    -- AIMING WAKES THE PANEL (1.9.1). Zooming in is the moment you most want to know what the
    -- gun in your hands actually does, and the idle timer has usually hidden the panel by then.
    --
    -- A.isAiming() returns nil for "cannot tell on this build" -- which is NOT false. Only a real
    -- boolean is allowed to move the panel, so a build where aiming is undetectable behaves
    -- exactly as it does today rather than flickering the panel on every tick.
    if cfg.panelOnAim ~= false then
      local aiming = A.isAiming()
      -- HELD, not edge-triggered: the panel stays up for as long as you are aiming and fades on
      -- the normal timer once you come out. An edge trigger would have it vanish mid-aim after
      -- panelIdleSec, which is the opposite of what was asked for.
      if aiming == true then panelWakeAt = os.clock() end
    end
    if showPanel and cfg.panelAutoHide == true then
      local idleSec = tonumber(cfg.panelIdleSec) or 2
      if idleSec > 0 then
        local awakeAt = math.max(Counting.lastActivity() or 0, panelWakeAt)
        if (os.clock() - awakeAt) > idleSec then showPanel = false end
      end
    end

    local function hidePanel()
      if lastShownId then Panel.dismiss("weapon"); lastShownId = nil end
      HudBar.hide()
    end
    local _, id = A.getEquippedWeapon()

    -- ANY weapon that levelled, not just the one in your hands -- and drained HERE, above the
    -- "nothing equipped" return below, because that is exactly when it matters.
    --
    -- A Drone Launcher's drones keep firing after you holster it. They kept earning, kept
    -- levelling, and kept queueing -- while the tick returned early for having no weapon out,
    -- so nothing drained. The queue then emptied all at once the moment a weapon was drawn,
    -- which is why Maiq got a burst of level-ups standing in his base after the fight was over.
    --
    -- Drawing is safe here: the world-settle gate above has already passed, and this is the
    -- game thread. Nothing below this point is needed to announce a level.
    do
      local q = Counting.levelUps
      if q and #q > 0 then
        for i = 1, #q do
          local u = q[i]
          -- the equipped weapon's own level-ups are announced by checkToast further down,
          -- which knows the panel state; this is only for the ones it cannot see
          if u and cfg.levelUpToasts ~= false and u.key ~= id then
            pcall(Toast.notify, string.format("%s  Lv%d", tostring(u.name), tonumber(u.level) or 0),
                  1.0, 0.82, 0.25)
          end
          q[i] = nil
        end
      end
    end
    if not id then
      lastId = nil
      -- STANDBY HAND-OFF: at wake with nothing equipped, swap the sticky to "active" once,
      -- hold it ~6s so the transition is actually seen, then dismiss DIRECTLY -- hidePanel is
      -- lastShownId-gated and never owned the standby sticky.
      if cfg._sbN and DARN and cfg.darnHud ~= false then
        if not cfg._sbWakeAt then
          cfg._sbWakeAt = os.clock()
          if HudBar.sbConfigure then HudBar.sbConfigure() end
          pcall(function() Panel.progress("weapon", { text = "Living Arsenal active",
            sub = "draw a weapon to see its progress", frac = 0, r = 0.45, g = 1.0, b = 0.55 }) end)
        elseif os.clock() - cfg._sbWakeAt > 6 then
          pcall(function() Panel.dismiss("weapon") end)
          cfg._sbN, cfg._sbWakeAt = nil, nil
          pcall(syncPanel)   -- the standby borrowed the glass geometry; give the style back
        end
      end
      hidePanel(); return
    end
    -- STANDBY DISMISS ON FIRST RESOLVED ID (2026-08-07, Maiq: standby sticky stuck ">10
    -- minutes"). This line used to only CLEAR the bookkeeping, trusting "a real weapon owns
    -- the surface from here" -- but an id that resolves to NO spec (Plasma Multicutter =
    -- ignored Pickaxe type, GrapplingGun = unknown) returns below without ever posting a
    -- panel, so the standby sticky ("wakes once the world settles (~1 min)") was stranded
    -- on screen indefinitely while the mod was fully active. Wake at 09:28, tool in hand,
    -- panel still lying at 09:56. Dismiss it the moment ANY id resolves: a tracked weapon's
    -- panel re-posts the same surface id immediately (ToastLib resurrects a dismissing
    -- sticky in place, so this cannot flicker), and an untracked one now leaves a clean HUD.
    if cfg._sbN then
      pcall(function() Panel.dismiss("weapon") end)
      pcall(syncPanel)   -- the standby borrowed the glass geometry; give the style back
    end
    cfg._sbN, cfg._sbWakeAt = nil, nil   -- a real weapon owns the surface from here
    local spec = Counting.specFor(id)
    if not spec then
      -- HEADS-UP TOAST (a lot of players ask why a weapon "does nothing"): if this
      -- weapon is vanilla ONLY because its damage rate was never measured, say so and
      -- name the setting that opts it in. Fires from the EQUIP tick -- not from the
      -- gate itself, which also runs during the boot scan over every weapon you own
      -- and would fire a pile of toasts at login. Once per weapon model per session.
      if cfg.untestedToast ~= false then
        local u = Counting.untestedInfo and Counting.untestedInfo(id)
        if u and not untestedToasted[u.key] then
          untestedToasted[u.key] = true
          -- Two different reasons, two different fixes. Telling someone with an unsupported
          -- mod weapon to turn off "Tested weapons only" is wrong advice: that setting does
          -- not gate it, so nothing would happen and the mod would look broken.
          if u.reason == "unsupported" then
            Toast.notify(tostring(u.name) .. " is from another mod -- left vanilla, since its stats "
              .. "can't be verified. ESC > Mod Options > Living Arsenal > turn ON \"Level modded weapons\" to level it anyway.")
          else
            Toast.notify(tostring(u.name) .. " isn't tuned yet -- left vanilla. "
              .. "ESC > Mod Options > Living Arsenal > turn OFF \"Tested weapons only\" to level it anyway.")
          end
        end
      end
      hidePanel(); return
    end
    lastId = id
    if id ~= prevPanelId then prevPanelId = id; panelWakeAt = os.clock() end

    if cfg.progressScope == "instance" and not string.find(tostring(id), "@", 1, true) then
      if not warnedNoGuid[id] then
        warnedNoGuid[id] = true
        log("ERROR: cannot read per-instance GUID for " .. tostring(id) .. " -- not showing a level")
      end
      hidePanel()
      return
    end

    local st = Counting.rowFor(id)
    -- PRESTIGE bridge (throttled ~1s): publish this weapon's status for the menu
    -- panel and run any click the player queued there. May reset st.level below.
    if os.clock() - lastPrestigePoll > 1 then lastPrestigePoll = os.clock(); prestigeSync(id, A.levelOfChar(pawn)) end
    if prestigeToastText then
      if cfg.prestigeToasts ~= false then Toast.notify(prestigeToastText, 0.72, 0.5, 1.0) end
      prestigeToastText = nil
    end
    -- a virgin weapon (no store row yet) displays its tech-tree START level --
    -- careers BEGIN at the unlock level, they don't climb up from 0
    local level = (st and st.level) or (cfg.useStartLevel ~= false and (spec.start or 0)) or 0
    local xp    = (st and st.xp) or 0

    local justLeveled = checkToast(id, spec.name or id, level)
    local h = st and st.hud

    if justLeveled and cfg.levelUpToasts ~= false then Toast.notify(toastText, 1.0, 0.82, 0.25) end


    -- EXPERIMENT (Mikey 2026-07-22): hijack the vanilla lower-right weapon
    -- nameplate (WBP_Ingame_WeaponChange > selected row > Text_WeaponName) and
    -- append Lv/+dmg%. Vanilla rewrites the text on weapon switch; this tick
    -- re-writes it 250ms later. Text-only: no layout surgery, alive-gated.
    -- THROTTLED (2026-08-04, the stutter A/B): this census is two FindAllOf walks plus a
    -- text read per row, measured 11-77ms per fire, and at POLL_MS=250 it was the single
    -- biggest steady frame cost in the install. Vanilla only rewrites the text on weapon
    -- SWITCH, so the census now runs on switch (id changed) or at most once a second --
    -- fresh enough for the XP pips, a quarter of the native churn.
    -- LOOT-BURST STAND-DOWN (2026-08-08: the crash ledger's planned experiment for the
    -- paint-walk CTD class, executed after its 10th recurrence at 12:32). OLF stamps
    -- shared/olf-activity.txt on every pickup burst; while the stamp is fresh (<=5s)
    -- the census SKIPS its pass -- pickup churn is when the game rebuilds HUD rows, and
    -- suspect (a) for that class is our steady-state writes landing in a tree the paint
    -- walk is mid-descent on. The nil-gate below only helps when nils APPEAR; a
    -- stream-out between our write and the paint is invisible to us, so during loot
    -- bursts we simply do not write. Cost: pips a few seconds late after a loot spree.
    -- If the class recurs WITH this stand-down active, suspect (a) is exonerated ->
    -- third-party bisect (SmallerPlasmaMulticutter, AntiPhat). npCensusAt is NOT
    -- stamped on a paused pass, so the census fires on the first quiet tick.
    local lootPaused = false
    -- SPEED STAND-DOWN (2026-08-09, churn crash #13: paint walk died mid RIDE_FLY combat,
    -- 28s after the last loot stamp -- the loot pause never covered the OTHER churn
    -- window, and flying at speed is the classic one; every crash in the 08-07 cluster
    -- happened during streaming churn). One velocity read per pass: above the threshold
    -- the world is streaming hard under the player and the census does not write.
    if cfg.nameplateInfo ~= false and (tonumber(cfg.censusPauseSpeed) or 800) > 0 then
      local pawn = A.localPawn()
      if pawn then
        local v = safe(function() return pawn:GetVelocity() end)
        if v then
          local sp2 = (tonumber(v.X) or 0)^2 + (tonumber(v.Y) or 0)^2 + (tonumber(v.Z) or 0)^2
          local th = tonumber(cfg.censusPauseSpeed) or 800
          if sp2 > th * th then lootPaused = true end
        end
      end
    end
    if cfg.nameplateInfo ~= false and cfg.censusPauseOnLoot ~= false and olfActivityPath then
      pcall(function()
        local f = io.open(olfActivityPath)
        if f then
          local s = tonumber(f:read("*l")); f:close()
          -- 8s, was 5 (2026-08-08 18:43 crash): OLF re-stamps every 2s for the whole
          -- drop spree now, so this only needs to outlast the tail of the LAST stamp.
          if s and (os.time() - s) <= 8 then lootPaused = true end
        end
      end)
      if lootPaused and not cfg._lootPauseSaid then
        cfg._lootPauseSaid = true
        log("[NPDBG] census STAND-DOWN: loot burst in progress (olf-activity fresh) -- said once per burst")
      elseif not lootPaused then cfg._lootPauseSaid = nil end
    end
    if cfg.nameplateInfo ~= false and not lootPaused
       and (id ~= lastShownId or (os.clock() - npCensusAt) >= 1) then
      npCensusAt = os.clock()
      local function textOf(rw)
        local ct = alive(rw) and safe(function() return rw.Text_WeaponName end)
        if not alive(ct) then return nil, nil end
        local s = safe(function() return ct.Text end)
        s = s and safe(function() return s:ToString() end)
        if type(s) ~= "string" then s = safe(function() return ct:GetText():ToString() end) end
        return ct, (type(s) == "string" and s or nil)
      end
      -- v3: forget the parent wheel -- census EVERY WeaponChangeList_C row
      -- widget in existence (the collapsed hotbar band may be a standalone
      -- instance) and append to every row whose text matches the equipped
      -- weapon's display name (prefix-tolerant of our own earlier append).
      local wname = tostring((h and h.name) or spec.name or "")
      local doDbg = (not nameplateDumped) and (os.clock() - (npDbgAt or 0) > 4)
      if doDbg then npDbgAt = os.clock() end
      -- A NIL-TEXT ROW IS A HALF-BUILT TREE (2026-08-07, the 16:33 CTD: the census wrote
      -- 12 rows + gauge in the crash second with SIX rows reading nil -- the persistent
      -- HUD was still streaming in at t+70s, past every fixed boot window). A live UObject
      -- whose Text reads nil is the tree telling us construction is not finished; writing
      -- into ANY row of that tree risks the paint-walk AV. One nil aborts the whole pass --
      -- the census re-runs within a second, and pips a second late cost nothing.
      local rows, sawNil = {}, false
      for _, rw in ipairs(safe(function() return FindAllOf("WBP_Ingame_WeaponChangeList_C") end) or {}) do
        if alive(rw) then
          local rnm = safe(function() return rw:GetFName():ToString() end) or "?"
          if not rnm:find("^Default__") then
            local ct, s = textOf(rw)
            if alive(ct) and s == nil then sawNil = true end
            if doDbg then
              log(string.format("[NPDBG3] row=%s text='%s' (want '%s')", rnm, tostring(s), wname))
            end
            if alive(ct) and type(s) == "string" and wname ~= "" and
               (s == wname or s:find(wname, 1, true) == 1) then
              rows[#rows + 1] = ct
            end
          end
        end
      end
      -- THE COLLAPSED BAND over the ammo counter is NOT a wheel row: it's the
      -- player gauge's own Text_WeaponName (WBP_Ingame_PlayerGauge_Separated_C,
      -- found 2026-07-22 via the WeaponName header hunt). Target it directly.
      local gaugeMatched = false
      for _, gw in ipairs(safe(function() return FindAllOf("WBP_Ingame_PlayerGauge_Separated_C") end) or {}) do
        if alive(gw) then
          local gnm = safe(function() return gw:GetFName():ToString() end) or "?"
          if not gnm:find("^Default__") then
            local ct, s = textOf(gw)
            if alive(ct) and s == nil then sawNil = true end
            if doDbg then
              log(string.format("[NPDBG4] gauge=%s text='%s' (want '%s')", gnm, tostring(s), wname))
            end
            if alive(ct) and type(s) == "string" and wname ~= "" and
               (s == wname or s:find(wname, 1, true) == 1) then
              rows[#rows + 1] = ct
              gaugeMatched = true
              HudBar.cardRef = gw   -- the card mirror follows this widget's subtree
              -- ONE-SHOT HUD ANCESTRY PROBE. The integrated XP bar must be
              -- UMG above the weapon card -- HUD-canvas draws paint UNDER the
              -- game's UI, which is why every HUD-drawn attempt sat behind the
              -- card -- and the overlay host gets named from evidence, not
              -- guessed. Reads only, on a widget this census already holds.
              if not cfg._hudAncestryDumped then
                cfg._hudAncestryDumped = true
                pcall(function()
                  local node, depth = gw, 0
                  while node ~= nil and depth < 12 do
                    local full = safe(function() return node:GetFullName() end) or "?"
                    log(string.format("[HUDTREE %d] %s", depth, full))
                    node = safe(function() return node:GetParent() end)
                    depth = depth + 1
                  end
                end)
              end
            end
          end
        end
      end
      if doDbg then
        log(string.format("[NPDBG] matched rows=%d (gauge=%s) for '%s'", #rows, tostring(gaugeMatched), wname))
      end
      if sawNil and doDbg then log("[NPDBG] census STAND-DOWN: nil-text row(s) -- tree mid-construction, no writes this pass") end
      if #rows > 0 and not sawNil then
        if gaugeMatched and not nameplateDumped then nameplateDumped = true end   -- diagnostics off once the BAND works
        -- "58 · Old Revolver  +413%" -- level first, then name, and the damage
        -- bonus when it's earning one. The text XP pips are RETIRED in every
        -- style, by order: XP lives on the panel (or the lab bar), and the
        -- pips read as clutter on the game's own nameplate.
        local label = string.format("%d · %s", level, (h and h.name) or spec.name or tostring(id))
        if h and h.dmg and (h.dmg.pct or 0) > 0 then
          label = label .. string.format("  +%d%%", h.dmg.pct)
        end
        -- WRITE-PASS EVIDENCE (2026-08-12). nameplateDumped latches the diagnostics off once
        -- the band works -- after which this loop, the mod's OWN nominated suspect for the
        -- paint-walk CTD family, writes into native HUD rows in complete silence. Three
        -- crashes in one evening could not be attributed because of that silence: the only
        -- census line still printing was the loot stand-down, so "was it writing when it
        -- died?" had to be reconstructed from arithmetic instead of read off the log.
        -- ONE throttled line per write pass, at 5s -- enough to place the writes on the
        -- timeline, quiet enough not to repeat CTD #23 (a 2.5s watcher shipped 08-10 and
        -- crashed on the first server join; the lever is FEWER fires, never more).
        if (os.clock() - (npWriteAt or 0)) > 5 then
          npWriteAt = os.clock()
          -- string.format, NOT varargs: Darn.logger returns function(m) -- one argument, no
          -- printf. The first cut passed varargs and printed the literal "%d ... %s" for ten
          -- minutes. The timestamp still did its job, but the row count and label were lost.
          log(string.format("[NPWRITE] writing %d native nameplate row(s) -- label=%s",
                            #rows, tostring(label)))
        end
        -- MARSHAL ONLY THE WRITE (2026-08-12, second cut). SetText is a UFUNCTION: it goes
        -- through ProcessEvent and triggers a synchronous SlatePrepass -> text shaping ->
        -- FShapedTextCache mutation. Off the game thread that races the game thread's own
        -- per-frame prepass and corrupts a shared TSet (20 CTDs; proof in the crash ledger).
        --
        -- The FIRST cut moved this whole tick onto the game thread. That fixed the race and
        -- put the census's OWN cost -- two FindAllOf walks plus a text read per row, this
        -- file measured it at 11-77ms per fire -- straight into frames, up to once a second.
        -- Maiq felt it within the hour, and the install lease had already recorded the same
        -- trade going the same way for the v5 prelude ("almost unplayable").
        -- So: the WALK stays off-thread where its milliseconds are invisible, and only the
        -- write -- a handful of SetText calls on already-resolved rows -- is marshalled.
        -- alive(ct) is re-checked INSIDE the game-thread body, not out here, because these
        -- handles are captured now and dereferenced a frame later (the fire-time rule).
        local pending = rows
        local text = label
        local function writeRows()
          for _, ct in ipairs(pending) do
            if alive(ct) then pcall(function() ct:SetText(FText(text)) end) end   -- pcall won't catch a native AV on a freed widget
          end
        end
        if type(_G.ExecuteInGameThread) == "function" then
          if not pcall(_G.ExecuteInGameThread, writeRows) then writeRows() end
        else
          writeRows()
        end
      end
    end
    if showPanel then
      local sub
      if h and h.dmg then
        -- THE NUMBER, AND THE BONUS ONLY WHEN THERE IS ONE (by design). No +0%, and no
        -- explanation of why it is 0 -- a weapon below its crossover and one permanently
        -- above the ladder both simply read as their damage. The reasons are real but they
        -- belong in the boot report and crossover-report.txt, not on a line the player
        -- reads mid-fight; on the HUD they only ever drew attention to an absence.
        local dpct = h.dmg.pct or 0
        if dpct > 0 then
          sub = string.format("Dmg %d (+%d%%)", h.dmg.cur or 0, dpct)
        else
          sub = string.format("Dmg %d", h.dmg.cur or 0)
        end
        if h.mag then sub = sub .. string.format("   Mag %d", h.mag.now or 0) end
      end
      local xpNext = (h and h.xpNext) or 0
      -- prestige stars on the title; a "ready" nudge in the sub when at cap
      local stars = (h and tonumber(h.stars)) or 0
      local starTxt = (stars > 0) and ("  \226\152\133" .. stars) or ""
      if prestigeReady and cfg.prestigeEnabled ~= false then
        sub = (sub and (sub .. "   ") or "") .. "\226\152\133 Ready to prestige (Mod Options)"
      end
      -- CUMULATIVE PRESTIGE BENEFITS row (Maiq, 2026-08-07). Live from counting.lua -- the
      -- same math that applies the points -- never from the h snapshot (stale-after-retune
      -- trap). `lines = {}` (not nil) when absent: ToastLib treats nil lines as "keep what
      -- you had", so switching from a prestiged weapon to a fresh one would otherwise leave
      -- the OLD weapon's benefits row under the new weapon's name (SO's board learned this).
      local pSum = (stars > 0 and cfg.prestigeHudSummary ~= false)
                   and safe(function() return Counting.prestigeSummary(id) end) or nil
      -- INTEGRATED MODE: the UMG HudBar on the player HUD, above the weapon
      -- card. The hijacked nameplate carries identity (name, Lv, stars,
      -- +dmg%); the bar contributes exactly the XP progress. The ToastLib
      -- surface stays out of integrated mode entirely.
      local integrated = (cfg.panelStyle == "bare") and cfg.labFeatures == true
      local barC = (HudBar.color and HudBar.color()) or { 1.0, 0.82, 0.25 }
      if integrated then
        HudBar.followCard((xpNext > 0) and math.min(1, xp / xpNext) or 1)
        if lastShownId then Panel.dismiss("weapon"); lastShownId = nil end
        lastShownId = id
      else
      HudBar.hide()
      Panel.progress("weapon", {
        -- THE LIVE SPEC WINS over the stored HUD snapshot. `h` is a cache written into the store
        -- when the entry was last touched, so after a curve retune it keeps reporting the OLD
        -- ceiling forever: every hud.maxLv in the live store still said 80 while weapondata had
        -- moved handguns to 400, and a weapon at its tech start level read "Lv 28/80" (reported
        -- 2026-07-29). A cap is a property of the CURVE, not of the last time we saw the weapon.
        text = string.format("%s  Lv %d/%d%s", (h and h.name) or spec.name or id,
                             level, spec.maxLv or (h and h.maxLv) or 0, starTxt),
        -- "" not nil: the sticky updater treats nil as keep-what-you-had
        sub = sub or "",
        frac = (xpNext > 0) and math.min(1, xp / xpNext) or 1,
        -- integrated shows the BAR alone: the nameplate already carries the
        -- star count, and a floating prestige line collides with the strip
        lines = pSum and { { text = pSum } } or {},
        r = barC[1], g = barC[2], b = barC[3],
      })
      lastShownId = id
      end
    else
      hidePanel()   -- idle fade (or darnHud off): wipe out; next shot wakes it
    end
  end)
  -- A pcall that discards its error is a silent freeze (the trap list's exact words): a tick
  -- dying every 250ms with no log line presents as "LA is not working" over a healthy-looking
  -- boot banner (2026-08-04: shipped while hunting exactly that presentation). Name each
  -- DISTINCT error once; the re-arm below stays outside the guarded body so a throw can never
  -- kill the heartbeat.
  if not tickOk and tickErr ~= nil then
    local key = tostring(tickErr)
    cfg._tickErrSeen = cfg._tickErrSeen or {}
    if not cfg._tickErrSeen[key] then
      cfg._tickErrSeen[key] = true
      log("TICK ERROR (contained, logged once): " .. key)
    end
  end
  -- THIS TICK MUST RUN ON THE GAME THREAD (2026-08-12) -- the fix for a 20-instance CTD family.
  --
  -- Raw ExecuteWithDelay runs the body on UE4SS's ASYNC timer thread. The body's nameplate
  -- census calls ct:SetText() on native UTextBlocks. SetText is a UFUNCTION: it goes through
  -- UObject::ProcessEvent and triggers a SYNCHRONOUS SWidget::SlatePrepass, which measures the
  -- text -- STextBlock::ComputeDesiredSize -> shaping -> FShapedTextCache::AddShapedText ->
  -- TSet::Emplace. That cache is SHARED WITH THE GAME THREAD, which is running its own prepass
  -- every frame. Two threads emplacing into one TSet corrupts it.
  --
  -- This is measured, not theorised. In the 19:22:17 minidump the faulting registers prove the
  -- set held 2 elements with HashSize == 0 -- a state impossible after any single-threaded
  -- insert -- while the GameThread sat in the SAME TSet::Emplace on the SAME cache, stopped
  -- between AddUninitialized and ConditionalRehash. The faulting thread was UNNAMED (not the
  -- game thread) with UE4SS.dll frames just outside ProcessEvent, whose address the loader's
  -- own log confirms at module+0x364d960.
  --
  -- THE GENERAL LAW, and it is bigger than this mod: ANY engine API called from an async timer
  -- can drag hidden game-thread work along with it. SetText looks like a property write and is
  -- actually a layout pass. ExecuteInGameThreadWithDelay is present on this build (measured on
  -- the live client by DarnDriverProbe, not assumed). Fallback keeps the mod working on a
  -- loader that lacks it -- degraded to the old behaviour, never broken.
  -- BACK ON THE ASYNC THREAD, deliberately. The census body is the most expensive thing this
  -- mod does (11-77ms per fire, measured above) and it does not need a frame -- only its
  -- SetText writes do, and those are marshalled individually at the write site. Putting the
  -- whole tick on the game thread cost visible stutter for no extra safety.
  ExecuteWithDelay(POLL_MS, tick)   -- timer-check: allow walk runs off-thread; the WRITES are marshalled at the write site
end

ExecuteWithDelay(6000, function()
  pcall(function()
    log("v" .. VERSION .. " starting  (SHADOW-count=" .. tostring(SHADOW) .. ")")

    -- player curve FIRST -- counting's playercurve xp model needs it, and specFor
    -- reads cfg._playerCurve.maxLv for the 80-level denominator.
    if cfg.usePlayerCurve then
      cfg._playerCurve = A.playerCurve()
      log(cfg._playerCurve
        and ("player curve loaded: " .. cfg._playerCurve.maxLv .. " levels")
        or  "player curve UNREADABLE -- xp pacing falls back to the timed model")
    end

    local store = Store.new("WeaponProficiency-store.lua", "wpv2")
    Counting.start({ store = store, shadow = SHADOW })
    -- SAY IT WHEN THE SCOPE CHANGED. The setting is relaunch-only, so the consequence lands a
    -- session AFTER the decision -- which is exactly why it reads as data loss rather than as
    -- the merge it is. Raised here, once, on the boot after the switch: late enough that a
    -- toast is visible, early enough that it arrives before the player opens a weapon and
    -- draws his own conclusion. Guarded so it can never fire twice, and cleared either way.
    pcall(function()
      local n = Counting.scopeNotice
      if type(n) ~= "table" or not n.text then return end
      Counting.scopeNotice = nil
      log(string.format("scope switch %s -> %s announced to the player (moved=%d folded=%d)",
        tostring(n.from), tostring(n.to), tonumber(n.moved) or 0, tonumber(n.folded) or 0))
      -- Toast.notify is (msg, r, g, b) -- there is NO dwell argument, and a fifth would be
      -- silently ignored rather than rejected. Colour only; the toast keeps its normal life.
      Toast.notify(n.text, 0.72, 0.86, 1.0)
    end)
    -- The swarm router's seeding and arm-persistence lived here. Both are gone: attribution now
    -- reads AttackStaticItemID off the damage itself (adapters.careerKeyForItem), so there is no
    -- armed state to seed, persist, or nag about. The "equip the Terraprisma once to arm
    -- attribution" toast is retired with it -- there is nothing left to arm.
    -- the prestige bridge file lives in the same shared/ dir the store resolved to
    if store.path then
      prestigePath = (tostring(store.path):gsub("[^/\\]+$", "")) .. "WeaponProficiency_prestige.lua"
      olfActivityPath = (tostring(store.path):gsub("[^/\\]+$", "")) .. "olf-activity.txt"
    end
    Damage.start()          -- damage.lua has its own DRY_RUN switch (LIVE=false since 2026-07-20)
    if cfg.bootReport ~= false then pcall(function() reportCrossovers(store) end) end
    -- SAY THE QUIET PART (1.9.8): the boot stand-down keeps every native read parked for
    -- ~60-90s after launch, so the panel arrives late BY DESIGN -- and an unannounced absence
    -- reads as "the mod is broken" (their reports and our own dogfooding both).
    -- A STICKY, not a toast (Maiq caught this in review): a toast's TTL runs from ENQUEUE
    -- (ToastLib bornS = nowS() at notify), so one queued at mod load is ~40s dead before the
    -- HUD ever draws -- it can never be seen. Stickies have no TTL; this one waits for the HUD,
    -- shows while the stand-down holds, and the first real tick replaces or dismisses it.
    if DARN and cfg.darnHud ~= false then
      if HudBar.sbConfigure then HudBar.sbConfigure() end
      pcall(function() Panel.progress("weapon", {
        text = "Living Arsenal standing by", sub = "wakes once the world settles (~1 min)",
        frac = 0, r = 0.6, g = 0.75, b = 1.0 }) end)
    end
    tick()
  end)
end)
