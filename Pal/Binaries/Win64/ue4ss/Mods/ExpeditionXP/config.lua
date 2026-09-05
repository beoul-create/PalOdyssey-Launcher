-- ============================================================================
--  Expedition XP -- 2x Double Buffed Progression Configuration
-- ============================================================================
return {
  -- Main Lever: Doubled from 1.0 to 2.0 (grants 2 full levels worth of exp per run)
  bandPct = 2.0,

  -- Minimum floor: Doubled from 0.15 to 0.30 (guaranteed 30% of next level)
  minPctOfLevel = 0.30,

  -- Catch-up bonus for lower level pals doubled
  bandUnderBonus = 2.0,

  -- Breadth of full payout window
  bandWidth = 12,

  -- Smooth decay for over-leveled pals
  overDecay = 0.10,

  -- Scaler for unmapped custom expeditions (doubled from 120 to 240)
  xpPerAnchorLevel = 240,

  -- Direct XP writing independent of server world penalties
  respectServerExpRate = false,
}
