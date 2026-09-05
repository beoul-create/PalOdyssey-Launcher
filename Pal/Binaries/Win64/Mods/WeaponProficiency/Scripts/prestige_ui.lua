-- ===========================================================================
--  prestige_ui.lua -- Living Arsenal's IN-GAME prestige surfaces:
--    * ESC-menu prestige BADGE  (bottom-right of the pause menu, above Block List)
--    * INVENTORY equipment STAR  (golden * on the eligible weapon's slot)
--  Both are built on DarnUI's UI.overlay (safe injection host) + UI.tilePopup (the
--  shared "click -> option tiles -> pick" helper). They read/write THIS mod's OWN
--  prestige bridge file (status <- us, request -> us); our prestigeSync tick applies
--  a queued request once via seq/ack.
--
--  These used to live in DarnMenu. They moved here on purpose: the config platform
--  should have NO awareness of prestige -- DarnUI is the only shared piece. The
--  caller pcall-requires this file, so a missing DarnUI costs ONLY the badge/star.
-- ===========================================================================
-- DarnUI's kit via the shared bootstrap (adds ../../DarnUI/Scripts to package.path
-- then requires "ui" -- each UE4SS mod has its own path, so this can't be skipped).
-- Errors if DarnUI isn't installed; the caller pcall-requires this file, so a
-- missing dep costs only these surfaces.
local UI = require("darn").requireUI()

local M = {}

local STAT_OPTIONS = {
  { value = "dmg", label = "+Base Damage" }, { value = "pct", label = "+% Damage" },
  { value = "mag", label = "+Magazine" },    { value = "dur", label = "+Durability" },
  { value = "cap", label = "+Level Cap %" },
}

-- deps: { Darn = <vendored darn>, log = fn, readBridge = fn()->table, writeBridge = fn(table)->bool }
function M.install(deps)
  local Darn        = deps.Darn
  local safe        = Darn.safe
  local guidStr     = Darn.guidStr
  local log         = deps.log or function() end
  local readBridge  = deps.readBridge
  local writeBridge = deps.writeBridge
  local VIS = UI.VIS

  -- prestige status ONLY when a weapon is actually eligible (safe: our own file)
  local function pbStatus()
    local data = readBridge() or {}
    local s = data.status
    if type(s) == "table" and s.eligible == true and s.weapon then return s end
    return nil
  end

  -- queue a one-shot prestige request for `stat`; our tick runs it once (seq/ack)
  local function writeRequest(stat)
    local cur = readBridge() or {}
    local prev = (type(cur.request) == "table" and tonumber(cur.request.seq)) or 0
    cur.request = { stat = stat, seq = prev + 1 }
    writeBridge(cur)
    log("[prestige] banked " .. tostring(stat))
  end

  -- the stat options offerable RIGHT NOW = STAT_OPTIONS masked by the bridge's
  -- `allowed`. Empty when the weapon isn't eligible -> tilePopup won't build.
  local function offerable()
    local allow = {}
    local st = pbStatus()
    for _, v in ipairs(st and st.allowed or {}) do allow[tostring(v)] = true end
    local out = {}
    for _, opt in ipairs(STAT_OPTIONS) do if allow[opt.value] then out[#out + 1] = opt end end
    return out
  end

  -- ============================ ESC-MENU BADGE ============================
  -- Bottom-right of the bare pause menu, calibrated to sit just above the native
  -- Block List button. Both are bottom-right-anchored in the SAME DPI-scaled design
  -- space, so a fixed design-unit inset tracks Block List on any res/aspect.
  local MENU_CLASS = "/Game/Pal/Blueprint/UI/UserInterface/ESCMenu/WBP_MenuESC.WBP_MenuESC_C"
  local PB_ANCHOR_X, PB_ANCHOR_Y = 590, 242
  local PB_BADGE_W, PB_BADGE_H = 300, 44
  local PB_TILE_W,  PB_TILE_H  = 280, 42

  -- pin a placed widget to the menu's bottom-right corner (canvas op = safe)
  local function anchorBR(w, x, y)
    if not (UI.alive(w) and w.Slot) then return end
    pcall(function()
      w.Slot:SetAnchors({ Minimum = { X = 1, Y = 1 }, Maximum = { X = 1, Y = 1 } })
      w.Slot:SetAlignment({ X = 1, Y = 1 })
      w.Slot:SetPosition({ X = -x, Y = -y })
    end)
  end

  UI.overlay({
    class = MENU_CLASS,
    canvas = "CanvasPanel_0",
    pollMs = 1000,
    -- STAND DOWN WHEN SOMETHING ELSE OWNS THE ESC SCREEN. The badge is anchored to the
    -- menu ROOT so the game hiding inner panels cannot take it away -- which also meant it
    -- floated over DarnMenu's options page (reported in play 2026-07-27). Watching the
    -- GAME's own button canvas keeps the ownership line intact: we never look at DarnMenu,
    -- only at whether the menu's own panel is still on screen. Any mod that covers the ESC
    -- menu gets the same courtesy for free.
    yieldWhenHidden = "Canvas_Buttons",
    onClick = function(o, action)
      if action.type == "pbToggle" then o.pop:toggle()   -- badge click toggles the stat tiles
      elseif o.pop then o.pop:route(action) end           -- a stat tile -> writeRequest, close
    end,
    refresh = function(o)
      local st = pbStatus()
      if not st then                                       -- ineligible -> hide badge + tiles
        if o.pbBadge then o:hide(o.pbBadge) end
        if o.pop then o.pop:close() end
        return
      end
      if not UI.alive(o.pbBadge) then                      -- build the badge once (build-hidden)
        local badge = o:button("\226\152\133 Prestige ready", { type = "pbToggle" })
        if not badge then return end
        UI.goldTint(badge); UI.setVis(badge, VIS.HIDE)
        o:place(badge, 0, 0, PB_BADGE_W, PB_BADGE_H, 60)
        o.pbBadge, o.pbSig = badge, nil
        o.pop = UI.tilePopup(o, {                          -- tiles stacked above the badge
          options = offerable,
          size = { PB_TILE_W, PB_TILE_H, 61 },
          position = function(tile, i) anchorBR(tile, PB_ANCHOR_X, PB_ANCHOR_Y + PB_BADGE_H + 8 + (i - 1) * (PB_TILE_H + 6)) end,
          onPick = writeRequest,
        })
      end
      -- rebuild the tiles if the eligible weapon / allowed set changed
      local sig = tostring(st.weapon) .. "|" .. table.concat(st.allowed or {}, ",")
      if o.pbSig ~= sig then o.pop:reset(); o.pbSig = sig end
      UI.setLabel(o.pbBadge, "\226\152\133 Prestige: " .. tostring(st.name or st.weapon))
      anchorBR(o.pbBadge, PB_ANCHOR_X, PB_ANCHOR_Y)
      o:show(o.pbBadge)
    end,
  })
  log("[prestige-badge] overlay armed on " .. MENU_CLASS)

  -- ============================ INVENTORY STAR ============================
  -- Golden * on the equipment slot holding the active weapon when it is prestige-
  -- ready. We find WHICH slot by SAFE property reads (slot.WBP_PalInGameMenuItemSlot
  -- .TargetSlot.ItemId.StaticId + DynamicId -- NOT the crashing GetItemAndNum
  -- out-param) and match the bridge's active-weapon key "StaticId@GUID".
  local INV_CLASS = "/Game/Pal/Blueprint/UI/UserInterface/MainMenu/InventoryEquipment/WBP_InventoryEquipment.WBP_InventoryEquipment_C"
  local INV_STAR_X, INV_STAR_Y0, INV_STAR_DY, INV_STAR_SZ = 20, 40, 88, 38
  local PICK_W, PICK_H = 150, 34
  local PICK_X = INV_STAR_X + INV_STAR_SZ + 8   -- picker to the RIGHT of the star (a left offset went off-screen)

  -- SAFE read of a weapon slot's key "StaticId@GUID"; returns fullKey, staticId
  local function invSlotKey(slotBtn)
    if not UI.alive(slotBtn) then return nil, nil end
    local base = "WBP_PalInGameMenuItemSlot.TargetSlot.ItemId."
    local idName = UI.get(slotBtn, base .. "StaticId")
    local sid = idName and safe(function() return tostring(idName:ToString()) end) or nil
    if not sid or sid == "" or sid == "None" then return nil, nil end
    local guid = guidStr(UI.get(slotBtn, base .. "DynamicId.LocalIdInCreatedWorld"))
    return (guid and (sid .. "@" .. guid) or sid), sid
  end

  -- index (0..5) of the weapon slot holding the active weapon (exact key, else StaticId)
  local function invMatchSlot(menu, activeKey, activeStatic)
    if activeKey and activeKey:find("@", 1, true) then
      for i = 0, 5 do
        if invSlotKey(UI.findByName(menu, "WBP_ItemSlotButton_Weapon_0" .. i)) == activeKey then return i end
      end
    end
    if activeStatic then
      for i = 0, 5 do
        local _, sid = invSlotKey(UI.findByName(menu, "WBP_ItemSlotButton_Weapon_0" .. i))
        if sid == activeStatic then return i end
      end
    end
    return nil
  end

  -- cheap 1-slot verify: does slot `idx` STILL hold the active weapon?
  local function invSlotHolds(menu, idx, activeKey, activeStatic)
    local key, sid = invSlotKey(UI.findByName(menu, "WBP_ItemSlotButton_Weapon_0" .. idx))
    if activeKey and activeKey:find("@", 1, true) then return key == activeKey end
    return sid == activeStatic
  end

  UI.overlay({
    class = INV_CLASS,
    canvas = "Canvas_EquipmentSlots",
    pollMs = 1000,
    onClick = function(o, action)
      if action.type == "star" then o.pop:toggle()   -- star click toggles the picker
      elseif o.pop then o.pop:route(action) end        -- a stat tile -> writeRequest, close
    end,
    refresh = function(o)
      local st = pbStatus()
      local activeKey = st and st.weapon and tostring(st.weapon) or nil   -- "StaticId@GUID"
      if not activeKey then                            -- ineligible -> no star + close picker
        if o.star then o:hide(o.star) end
        if o.pop then o.pop:close() end
        o.starKey = nil
        return
      end
      local activeStatic = activeKey:match("^[^@]+")
      -- CACHE: weapons rarely move slots. Reuse the cached slot after a cheap 1-slot
      -- VERIFY; full 6-slot re-scan only when the weapon changed or the slot no longer holds it.
      local idx = o.starIdx
      if o.starKey ~= activeKey or not idx or not invSlotHolds(o.menu, idx, activeKey, activeStatic) then
        idx = invMatchSlot(o.menu, activeKey, activeStatic)
        if o.starKey ~= activeKey and o.pop then o.pop:reset() end   -- weapon changed -> rebuild picker
        o.starKey = activeKey
      end
      if not idx then                                  -- its slot not found -> no star + close picker
        if o.star then o:hide(o.star) end
        if o.pop then o.pop:close() end
        o.starIdx = nil
        return
      end
      local y = INV_STAR_Y0 + idx * INV_STAR_DY
      if not UI.alive(o.star) then
        local star = o:button("\226\152\133", { type = "star" })
        if not star then return end
        UI.goldTint(star); UI.setVis(star, VIS.HIDE)
        o:place(star, INV_STAR_X, y, INV_STAR_SZ, INV_STAR_SZ, 50)
        o.star, o.starIdx = star, idx
        o.pop = UI.tilePopup(o, {                       -- picker stacked below-right of the star
          options = offerable,
          size = { PICK_W, PICK_H, 55 },
          position = function(tile, i)
            pcall(function() tile.Slot:SetPosition({ X = PICK_X, Y = INV_STAR_Y0 + (o.starIdx or 0) * INV_STAR_DY + (i - 1) * (PICK_H + 6) }) end)
          end,
          onPick = writeRequest,
        })
        log("[invstar] star -> slot " .. idx .. " (active=" .. tostring(activeStatic) .. ")")
      elseif o.starIdx ~= idx then                     -- weapon moved slots: reposition (canvas = safe)
        o.starIdx = idx
        pcall(function() o.star.Slot:SetPosition({ X = INV_STAR_X, Y = y }) end)
      end
      o:show(o.star)
    end,
  })
  log("[invstar] overlay armed on " .. INV_CLASS)
end

return M
