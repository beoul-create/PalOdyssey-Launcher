-- ============================================================================
--  Weapon Proficiency  -  CONFIGURATION
--  The more you use a weapon, the higher its proficiency, and the more damage it does.
--  Proficiency is tracked PER WEAPON and persists across sessions.
--  Edit the values below to tune the mod. Most knobs apply live via the in-game
--  Mod Options menu (see main.lua's LIVE_KEYS); a few still need a relaunch.
-- ============================================================================

local Config = {

  -- ---- DAMAGE / MAGAZINE --------------------------------------------------

  applyDamage   = true,  -- true = weapons hit harder as they level. false = level & show progress only.
  dmgMult       = 1.0,   -- scales the damage BONUS (not base damage): 0.5 = half growth,
                         -- 2 = double, 0 = flat damage forever. Editable in-game (Mod Options).
  xpMult        = 1.0,   -- weapon XP gain multiplier: 2 = level twice as fast. In-game too.
  applyDurability = true, -- weapons last longer as they level (cap = durabilityMaxMult)
  progressScope = "instance", -- "instance" = each physical weapon its own career (GUID);
                              -- "model" = all copies of a weapon share one career

  -- Keep a weapon boosted after you put it away, instead of restoring vanilla on swap.
  -- AttackValue is a per-MODEL asset shared by every copy of a weapon, so this is what
  -- makes the bonus reach the ones in your bags rather than only the one in your hands;
  -- durability follows because the stowed weapon keeps its enlarged bar. It matters most
  -- for anything that keeps fighting after you swap away -- Terraprisma summons burn the
  -- blade's durability the whole time they are out.
  --
  -- IGNORED under progressScope = "instance", and deliberately: two copies of one model
  -- can sit at different levels there while sharing one AttackValue, so a boost left on
  -- would pay whichever copy you drew next. Switch the scope to "model" to use this.
  --
  -- The trade: boosted values are no longer tidied up on swap, so weapons keep them if
  -- the mod is removed. Set false to go back to restore-on-swap.
  persistBoost  = true,

  -- UNINSTALL PREP. Stops all boosting and instead puts every weapon you own back to its
  -- stock damage, magazine and durability -- including the ones you are not holding, which
  -- is the point: nothing is tidied up on a swap any more, so removing the mod would
  -- otherwise leave its numbers behind. Turn it on, load in, wait a few seconds, and read
  -- the RESTORE-TO-STOCK lines in the log; each weapon reports once. Then quit and remove
  -- the mod. Durability keeps its fill percentage rather than being topped up, so this is
  -- not a free repair. Safe to leave on -- it is idempotent -- but nothing scales while it
  -- is, and your levels and prestige are untouched either way.
  restoreToStock = false,
  levelUpToasts = true,  -- pop a toast on weapon level-up
  bootReport    = true,  -- write crossover-report.txt + XOVER log lines at startup
  targetXp      = true,  -- big enemies pay more XP; false = every hit pays the same
  measureHps    = false,
  probeAttribution = false,

  -- SWARM DAMAGE PROBE. Answers one question: does a Terraprisma summon read the
  -- weapon's AttackValue on every hit, or snapshot it when summoned? The summons
  -- outlive a weapon swap; the LA boost does not, because swapping restores the
  -- vanilla value. Per-hit means the bonus is gone the moment you swap, which is the
  -- normal way the weapon is used. Snapshot means it is kept.
  --
  -- HOW TO RUN IT: turn this on, summon, swap to a gun, and DO NOT ATTACK -- every
  -- damage event logged is then a swarm hit. Do that once with a leveled Terraprisma
  -- and once with a low one. Same dmg both times = the boost never reached the swarm.
  -- Log-only, pure reads, uncapped while on; turn it off when the answer is in.
  probeSwarmDamage = false,
  -- swarmAttribution / swarmFlurryOverride are GONE (2026-08-19). Both tuned a heuristic that
  -- guessed which of two wt=3 emitters had fired. AttackStaticItemID names the source outright,
  -- so there is nothing left to tune and no "old behaviour" worth restoring: the old behaviour
  -- credited 232 of 252 drone kills to whatever weapon happened to be in hand.
  dmgCurve      = "target", -- "target" = boost every weapon UP to an absolute DPS-by-level
                         -- curve read off the bow unlockables (see P.CURVE in progression.lua),
                         -- never below its natural DPS, plateauing at the top anchor. This is
                         -- the calibrated model. "geo"/"linear" are the old base*ratio curves.
                         -- (dmgPower below is IGNORED in target mode -- the curve sets the shape.)
  tierEdge      = 0.05,  -- TECH TIER debuff per tier, "target" mode only (2026-07-28). Tier is
                         -- the DECADE of a weapon's tech level: 0-9 = T1 ... 70-80 = T8, and
                         -- each tier aims 5% lower than the one above. This is what makes a late
                         -- unlock actually better: before it, a Makeshift Handgun and a Beam
                         -- Launcher both converged on the identical ceiling.
                         -- 0 = no tier effect (every tech level converges, the old behaviour).
                         -- NOTE this does NOT separate weapons inside one decade -- the Handgun
                         -- (tech 28) and Makeshift Handgun (tech 24) are both T3 by design.
  gradeEdge     = 0,     -- RARITY EDGE per grade, in "target" mode only (1.4.4). The ladder
                         -- is a shared DPS destination, so base damage cancels out of the
                         -- result and every rarity of a weapon used to end on the identical
                         -- number. Each grade below Legendary now aims this much lower than
                         -- the ladder, anchored so LEGENDARY sits exactly on it:
                         --   Legendary x1.00  Epic x0.943  Rare x0.890  Fine x0.840  Common x0.792
                         -- i.e. a Legendary finishes ~26% above a Common of the same weapon.
                         --
                         -- SET TO 0 on 2026-07-28. gradeEdge was a WORKAROUND for the old
                         -- absolute-ladder model, where `base` cancelled out of the result
                         -- completely and every rarity landed on the identical number at EVERY
                         -- level. The unlock-anchored model does not have that property --
                         -- damage is base^(1-f) * (dest/hps)^f, so base only cancels at exactly
                         -- f=1 (the top anchor). A Legendary therefore starts 2.5x a Common of
                         -- the same family (the real vanilla base ratio, doing the work by
                         -- itself) and the gap closes smoothly to parity at cap.
                         -- Mikey's design call: "balance the legendary curve for the family and
                         -- then pass that curve down. The lower base damage on the other models
                         -- balances itself." Restore 0.06 to make rarity a permanent gap again.
  dmgPower      = 3.0,   -- BACK-LOADS the damage. The level fraction is raised to this
                         -- before the curve applies: the ceiling is unchanged, the shape
                         -- moves. Measured on MakeshiftShotgun_3 (ratio 15.2x, maxLv 80):
                         --        Lv18    Lv30    Lv40    Lv60     Lv80
                         --   1.0  +84%   +177%   +290%   +669%   +1417%   (stock: strong immediately)
                         --   2.0  +15%    +47%    +97%   +362%   +1417%
                         --   3.0   +3%    +15%    +40%   +215%   +1417%   <-- here
                         -- At 3.0 a weapon is nearly flat until the 40s, so the buff
                         -- arrives when you need it rather than at Lv18. Pairs with
                         -- capToPlayerLevel: a Lv30 player tops out around +15%.
  applyMagazine = true,  -- auto firearms get a bigger magazine as they level.
  magFraction   = 0.35,  -- the magazine reaches its maximum at 35% of the weapon's max level, then holds
                         -- while damage keeps climbing. Lower = the magazine bonus arrives sooner.
  magStep       = 2,     -- the magazine grows by this many rounds per upgrade (not smoothly).
  magMaxMultiplier = 1,  -- magazine ceiling multiplier. 1 = vanilla cap. Raise it (e.g. 2, 3, 5...) to let
                         -- weapons keep scaling their magazine much larger with proficiency. It multiplies
                         -- EACH weapon's own max magazine and is still paced over that weapon's own level
                         -- range, so weapons with fewer proficiency levels stay balanced (they reach the
                         -- bigger magazine in proportion to their grind, not all at once).
  magMaxAbsolute = 0,    -- OFF (was 600 -- the stock "MagazineOP" preset, and it was nonsense here).
                         -- 600 overwrote EVERY auto weapon's ceiling: a 46-round endgame Plasma Rifle and
                         -- a 17-round Makeshift both landed on 600 rounds by weapon Lv28, and a 2-shell
                         -- double-barrel became a 600-shell double-barrel. It erased the entire 15->46
                         -- magazine progression the game ships with, and handed the STARTER gun the bigger
                         -- multiple (35x vs 13x). We scaled damage carefully by rarity and tier and then
                         -- left magazines a free-for-all.
                         -- 0 = each weapon uses its OWN magMax from weapondata, which is now derived the
                         -- same way the damage caps are: aim at the endgame variant's ceiling for that
                         -- weapon TYPE, scaled by rarity and tier, and never more than a rarity-scaled
                         -- multiple of the weapon's own base (2.0x common -> 3.6x legendary) so a
                         -- semi-auto stays a semi-auto instead of becoming an assault rifle.

  -- ---- XP / GRIND ---------------------------------------------------------
  -- One landed hit = `xpPerHit` XP. Each weapon type levels at its own pace; the knobs below set it.

  xpPerHit   = 1,

  -- CLIENT-COMPLETE (2026-07-20). Counting runs on UPalUtility:MakeDamageInfo,
  -- which fires per landed hit. A shotgun blast is several pellet-hits in one
  -- frame; collapse them to one counted shot within this window (and credit the
  -- shot for its proj pellets, matching the server's per-pellet total). Only
  -- weapons with proj>1 dedupe, so single-projectile autos/bows are unaffected.
  -- Set 0 to count every event (server-faithful per-pellet).
  pelletDedupeMs = 60,

  -- SANITY CAP (2026-08-08): a MEASURED weapon's hit credits are budgeted at its
  -- measured rate x sanityHpsFactor (burst headroom over the reload-averaged
  -- sustained hps). Estimates ("est") prove nothing and pass free.
  -- REPORTS, does not confiscate (2026-08-19). Built for one thing -- the swarm pouring
  -- rifle-typed hits into the Vortex Beater's record before routing existed -- and in every
  -- archived session it ever fired, that is what it caught. Attribution reads the attack's own
  -- source item now, so a firing can only mean a double-count, a stale measurement, or an
  -- unattributed damage source, and none of those are worth eating a player's progress over.
  -- Set sanityHpsEnforce = true to go back to discarding the excess.
  sanityHps = true,
  sanityHpsEnforce = false,
  sanityHpsFactor = 3,

  -- CENSUS LOOT-BURST STAND-DOWN (2026-08-08, the paint-walk CTD experiment): skip the
  -- nameplate census while OLF reports a pickup burst (shared/olf-activity.txt fresh).
  -- See the census block in main.lua. false = census runs regardless (pre-experiment).
  censusPauseOnLoot = true,
  -- and while MOVING FAST (2026-08-09, churn crash #13 died mid flying combat): above
  -- this speed (uu/s) the world is streaming hard and the census does not write.
  -- 800 ~ mounted sprint; flying mounts cruise well above. 0 = off.
  censusPauseSpeed = 800,

  -- CLIENT durability perk (damage.lua, gated by APPLY_DURABILITY). Durability
  -- now CURVES with proficiency like damage and magazine, instead of a flat jump:
  --   durMult = 1 + (level/maxLv) * (durabilityMaxMult - 1)
  -- monotonic, x1 at Lv0, reaching the cap below at max level (maxLv, =80 under
  -- the player curve). Uses the same row.level / row.hud.maxLv the HUD reads.
  -- Durability lives on the per-instance dynamic data; the true base is captured
  -- once (pre-write) into the store row (durBase) so it never poisons across
  -- sessions. Only weapons with a store row (i.e. leveled) get the perk.
  durabilityMaxMult = 3.0,  -- cap reached at max level (x3 MaxDurability at Lv=maxLv)

  -- ---- SERVER-SIDE DURABILITY -------------------------------------------------
  -- These are read ONLY by the server half (see side.lua). On a client install they
  -- do nothing at all.
  --
  -- On a dedicated server the client's MaxDurability write never crosses the wire --
  -- measured 2026-08-18, server held 6000 while the client held 15015 on the same
  -- weapon at the same instant. The bar you actually consume is the server's, so the
  -- write has to happen there.
  --
  -- STAGE 1: this is an acceptance test, not the finished feature. It asks one
  -- question -- does a server-side write survive equipping, repairing and a world
  -- load, or does the game re-derive MaxDurability from item save data? Until that
  -- is answered there is no point picking a number, so the multiplier is FLAT and
  -- nothing consults proficiency. If the bar holds, the level source is next.
  --
  -- IT APPLIES TO EVERY WEAPON ON THE SERVER, not just yours -- there is no owner
  -- filter yet. On a shared server every player gets the same bar while this is on.
  serverDurability = true,

  -- Flat multiplier for the test. Defaults to durabilityMaxMult (what a max-level
  -- weapon would have earned) so the effect is large enough to be unmistakable in
  -- game and in the log.
  serverDurabilityMult = nil,

  -- First pass waits out world streaming: a FindAllOf walk during it reads a garbage
  -- pointer through every guard. Then a single repeating pass catches newly equipped
  -- weapons and re-asserts against anything that overwrites us.
  serverDurabilityFirstMs = 20000,
  serverDurabilityEveryMs = 5000,

  -- ---- THE PROFICIENCY CHANNEL (rpc.lua) ------------------------------------
  -- The server owns durability but not your level. This channel carries one number
  -- per weapon from the client that already knows it, so the server can run the same
  -- curve instead of the flat multiplier above.
  --
  -- BOTH DEFAULT OFF because the call shape is new to this codebase. PalPriority
  -- proves the channel exists; it does not prove our use of it. Turn on rpcApply
  -- first and read the [LA/rpc] first-arrival line -- that is what establishes how
  -- the parameters actually arrive. Only then is rpcSend worth switching on.
  --
  -- A weapon the channel never mentions keeps the flat multiplier, so leaving these
  -- off is exactly the behaviour you have today.
  rpcApply = true,   -- SERVER: act on reported levels (off = log arrivals only)
  rpcSend  = true,   -- CLIENT: send this player's levels to the server

  -- Max level the durability curve ramps to; matches the client's HUD maxLv.
  durabilityMaxLevel = 80,

  -- Overrides side.lua's install-path verdict: "client", "server", or nil for auto.
  -- Only needed for a layout it did not predict; the boot line prints what it chose.
  side = nil,
  durabilityMult    = 3.0,  -- back-compat alias: used as the cap if durabilityMaxMult is absent

  -- Mirror the PLAYER's exp curve for weapon levels (measured from the game:
  -- Lv2=50 ... Lv80=4,296,550, total 45.8M -- an ~86,000x backoff). Rescaled to
  -- each weapon's hoursByTier budget, so the SHAPE is the player's but the total
  -- stays sane. Gives every weapon 80 levels, like a character. false = stock
  -- flat cost (65 xp/level from Lv1 to Lv400).
  -- START-LEVEL MODEL. A weapon is "born" at its unlock level with 0% bonus and spreads
  -- its full ratio over the levels remaining, so crafting is never a downgrade and a late
  -- weapon does not hand you its power for free.
  --
  -- THIS COMMENT SAID "(OFF)" AND EXPLAINED WHY, LONG AFTER IT WAS TURNED ON -- and it
  -- justified that with "the start values are my invention, derived from tier". They are
  -- not: 186 rows carry startSrc="paldb", 79 "tech" and 26 "drop". Nothing is left of the
  -- T7->1 guess the note was worried about. Both halves of it were false.
  --
  -- The original concern was real at the time: the true numbers live in `LevelCap` on
  -- FPalTechnologyDataTableRowBase, and reading them means marshalling a UDataTable of
  -- FTableRowBase structs across the Lua boundary -- the thing that hard-crashed the server
  -- on 2026-07-16. They were sourced externally instead, which is why this could be turned
  -- on without ever making that call.
  --
  -- See startCapLevel below: a late unlock is CLAMPED, because a weapon born at its true
  -- level 77 has no room to earn under capToPlayerLevel.
  useStartLevel = true,   -- ON: unlock-anchored curves (0% at tech level, climb from there)
  -- THE LATEST LEVEL A WEAPON MAY BE BORN AT (2026-08-20, Maiq's call).
  --
  -- `start` is the tech unlock level, and a late one leaves no room to play. The Drone
  -- Launcher unlocks at 77: with capToPlayerLevel on, a level-77 player's copy sat at level
  -- 77 against a cap of 77, so addXp returned on every hit and 12,962 landed shots earned
  -- exactly nothing. It could not level and could not prestige -- inert by arithmetic.
  --
  -- Clamping the birth level gives it runway: born at 60 it climbs 60 -> 77 under the same
  -- player cap, and prestige (which wants at least the wielder's level) becomes reachable.
  --
  -- IT RE-ANCHORS THE CURVE TOO, deliberately. `start` is also the damage curve's origin --
  -- f = (level - start) / (maxLv - start) -- so a weapon whose tech sits above the clamp is
  -- crafted part-grown rather than at 0%. The CEILING is untouched; only how much of it you
  -- hold on day one. A knowing trade against "a late-game weapon does not hand you its power
  -- for free": a weapon that cannot earn at all is the worse outcome.
  --
  -- `tech` keeps the RAW unlock level, so tier maths is unaffected.
  startCapLevel = 60,

  -- Scope progress to the world you are playing (each server its own careers).
  -- The store has ALWAYS been bucketed per world; the bucket never resolved, because
  -- the world id came from PalWorldSaveGame -- a server-side object a dedicated-server
  -- client never sees -- so every server and single-player shared one "default" bucket.
  -- OFF leaves that shared bucket exactly as it was, so an update changes nothing for
  -- an existing player. Turning it ON moves the shared bucket into the FIRST world that
  -- resolves and leaves every other world empty, which is why the option confirms first.
  -- Defaults ON for a fresh install and OFF for anyone grandfathered in; resolved once
  -- at first boot and written to the user file, so it never re-decides.
  scopeToServer = false,

  -- Clamp the APPLIED bonus to the wielder's level. Distinct from capToPlayerLevel
  -- below, which only discards XP at award time and so cannot touch a weapon that is
  -- already past you -- a Lv80 bow still pays a Lv13 character its full Lv80 bonus.
  -- ON computes the bonus from min(weapon level, wielder level + capExtra). The weapon
  -- KEEPS its earned level in the store and on the HUD; only the payout is clamped.
  capBonusToPlayerLevel = false,

  capToPlayerLevel = true,  -- a weapon may not reach or exceed its wielder's level.
                            -- At/above the cap, XP is DISCARDED (it does not bank) --
                            -- so idling at the cap earns nothing and you cannot
                            -- out-level your gear. Same rule as LevelLock.
  -- THE DROP CURVE (2026-08-20). Earning and cost are both the game's own numbers:
  --     xp per hit      = dropExp / hps        (a second of fire pays the target's worth)
  --     cost of level L = xpSecondsPerLevel x GetDropExpBase(L)
  -- Both grow ~7% per level, so pacing is flat by construction -- one minute per level
  -- against same-level enemies at any level. Boss Rush pays x10 because that is its real
  -- multiplier, measured, not a tuned constant.
  --
  -- Replaces: refDropExp and its clamps, xpTune, hoursByTier, curvePower, xpStep,
  -- grindPower and xpPerHit. Those all existed to reconcile a fixed reference with a
  -- career-long range; there is no fixed reference now. OFF falls back to usePlayerCurve.
  useDropCurve      = true,
  -- Scale weapon xp by the world's own ExpRate. GetDropExp returns the RAW table value and
  -- the game applies the rate when it grants exp, so without this a 0.2x server pays the
  -- player a fifth while paying weapons full -- they would level five times faster than the
  -- person holding them. ON matches the pacing the drop curve is for; OFF is the old
  -- behaviour, for anyone who wants weapon progress independent of a harsh server rate.
  respectServerExpRate = true,
  expRateOverride      = nil,   -- set a number to pin the rate by hand when the client cannot
                                -- read it (the boot line says which happened)
  xpSecondsPerLevel = 60,   -- Maiq's calibration: lv40 weapon, lv40 enemy, one level/minute

  usePlayerCurve = true,
  curvePower     = 0.5,   -- how closely to mirror the player curve's SHAPE.
                          --   1.00 = exact  -> Lv20 in ~1.3 min (too fast: the raw curve
                          --                    spends only 0.12% of its total on Lv2-20)
                          --   0.50 = default-> Lv20 in ~21 min, 282x backoff
                          --   0.35          -> Lv20 in ~46 min,  53x backoff
                          -- Lower = flatter = early levels cost more, late levels less.

  -- ---- TARGET SCALING (added 2026-07-16) ---------------------------------
  -- Per-hit XP scaled by WHAT you shot: xp = xpPerHit * targetMult.
  -- targetMult = GetDropExp(target.level, target.species) / refDropExp, clamped.
  -- So a Lamball trickles and an Alpha pays, while keeping per-HIT credit --
  -- which means a Pal landing the finish still pays your weapon, and swapping
  -- weapons mid-fight credits each one for its own hits.
  --
  -- refDropExp IS A GUESS until we see real numbers. The mod logs the first 30
  -- observed dropExp values as [DROPEXP] lines -- read those, then set this so a
  -- typical mob lands near x1.0 and hoursByTier still means what it says.
  -- Record what each species+level is actually WORTH, from play. Written once per
  -- species+level on the drop-exp cache miss, so it costs nothing per hit. Answers the
  -- question refDropExp has been guessing at since July -- and whether a target's worth
  -- grows with its level, which decides whether a level-70 weapon levels in a minute or
  -- in forty-five. Report: Mods/shared/WeaponProficiency-dropexp.txt
  dropExpReport = true,

  targetScaling = {
    enabled    = true,
    refDropExp = 60,    -- CALIBRATED 2026-07-16: chicken=11-15, dragon=595 (54x spread).
                        -- 60 puts an ordinary mob near x1 and a dragon near x8 (clamped).
    min        = 0.02,  -- was 0.25 -- which inflated a chicken (true ratio x0.04) by ~6x
                        -- and left mercy-farming viable. 0.02 makes chickens near-worthless.
    max        = 8.0,   -- ceiling: one boss should not max a weapon
    nonPalXp   = 0,     -- hits on scenery/buildings/players (no exp value). 0 = no free grinding
  },
  shotgunXpMult = 2,   -- shotguns earn 2x XP per hit (their pellets spread the damage, so they need it).
  launcherXpMult = 8,  -- explosive launchers (Rocket/Missile/Grenade/Drone) earn XP per SHOT, not per hit,
                       -- and their ammo is rare — without this they'd need ~22 shots/level (never levels).
                       -- 8 ≈ 2-3 shots/level. Raise to level faster, lower to make it a longer grind.
  xpStep     = 0.13,   -- overall firearm pace. Higher = longer grind to max level.
  grindPower = 0.4,    -- 0 = every gun grinds the same; 1 = weaker guns grind noticeably longer.

  -- Single-shot weapons (bows, crossbows, snipers, launchers, ...) level over a target real-time by tier
  -- (weaker/earlier tiers take longer), converted into shots by a per-type rate.
  singleShot = {
    hoursByTier = { T1 = 2, T2 = 3, T3 = 4, T4 = 6, T5 = 8, T6 = 11, T7 = 15 },
  },

  -- Per-weapon-type pace. g = relative grind factor (higher = more hits per level). src/xp/hoursByTier
  -- control how each type earns and paces its XP; leave these unless you want to rebalance a whole class.
  types = {
    Handgun        = { g = 1.0, src = "ranged", xp = "firearm" },
    AssaultRifle   = { g = 1.6, src = "ranged", xp = "firearm" },
    Shotgun        = { g = 0.8, src = "ranged", xp = "firearm" },
    SniperRifle    = { g = 0.5, src = "ranged", xp = "firearm" },
    RocketLauncher = { g = 0.4, src = "ranged", xp = "firearm" },
    MissileLauncher= { g = 0.4, src = "ranged", xp = "firearm" },
    GrenadeLauncher= { g = 0.5, src = "ranged", xp = "firearm" },
    Grenade        = { g = 0.6, src = "ranged", xp = "firearm" },
    GatlingGun     = { g = 3.0, src = "ranged", xp = "firearm" },
    FlameThrower   = { g = 3.0, src = "ranged", xp = "firearm" },
    LaserRifle     = { g = 1.0, src = "ranged", xp = "firearm" },
    Bow            = { g = 0.7, src = "ranged", xp = "firearm" },
    BowGun         = { g = 0.8, src = "ranged", xp = "firearm" },
    SubmachineGun  = { g = 2.2, src = "ranged", xp = "firearm" },
    DroneLauncher  = { g = 0.6, src = "ranged", xp = "firearm" },
    -- gathering tools and blades level over a target real-time by tier:
    Pickaxe        = { g = 1.0, src = "mining",   xp = "timed", hoursByTier = { T1 = 2, T2 = 3, T3 = 4, T4 = 5, T5 = 6, T6 = 7, T7 = 8 } },
    Axe            = { g = 1.0, src = "chopping", xp = "timed", hoursByTier = { T1 = 2, T2 = 3, T3 = 4, T4 = 5, T5 = 6, T6 = 7, T7 = 8 } },
    Sword          = { g = 1.0, src = "combat", xp = "timed", xpStep = 1.4, hoursByTier = { T7 = 30, T6 = 25 } },
    Katana         = { g = 1.0, src = "combat", xp = "timed", xpStep = 1.4, hoursByTier = { T7 = 30, T6 = 25 } },
    Melee          = { g = 1.0, src = "combat", xp = "timed", xpStep = 1.4, hoursByTier = { T7 = 30, T6 = 25 } },
    -- Butcher (Meat Cleaver) is in ignoreTypes below -- it never earns -- but the type is
    -- declared so it routes as the swung melee tool it is instead of silently falling back
    -- to "ranged" (an undeclared type is how a family stops being counted; pathway-check).
    Butcher        = { g = 1.0, src = "combat", xp = "timed" },
  },
  defaultType = { g = 1.0, src = "ranged", xp = "firearm" },

  -- TYPES THE MOD IGNORES COMPLETELY. specFor() returns nil for these, so they get
  -- no XP, no damage buff, no magazine, no HUD -- as if they were not in weapondata.
  -- Pickaxes and axes are TOOLS. The stock mod tracked them anyway and the result was
  -- backwards: proficiency wrote AttackValue, so a well-used pickaxe hit HARDER while
  -- mining exactly as slowly as before. The reward for mining should be mining, and
  -- this mod has no hook for gather speed. So: stay out of it.
  -- (Keep them in weapondata -- deleting rows loses the base/cap data. Flip to false
  --  here if tools should ever earn again.)
  ignoreTypes = { Pickaxe = true, Axe = true, Butcher = true },  -- Butcher = the Meat Cleaver (Maiq 2026-08-07: a butchering tool needs no tuning warning)

  -- ---- SAFETY: TESTED WEAPONS ONLY (whitelist) ----------------------------
  -- ON by default. The mod only applies to weapons whose damage rate was actually
  -- MEASURED and a curve built for them (weapondata hpsSrc ~= "est"). A weapon whose
  -- rate is only ESTIMATED (hpsSrc="est") has a guessed curve that can scale its
  -- damage wrong and interact badly, so by default it is left completely VANILLA --
  -- no XP, no damage/magazine/durability change, no HUD -- until it has been measured.
  -- (Each such weapon logs its model key once, e.g. "[Arsenal] UNTESTED Musket_3 ...".)
  --
  -- Want the mod on an untested weapon anyway? You have to opt in, one of three ways:
  untestedToast = true,            -- when you equip a weapon that is left vanilla ONLY because
                                   -- its damage rate was never measured, say so once per weapon
                                   -- (per session) and name the setting that opts it in. Players
                                   -- kept asking why a weapon "does nothing"; silence with false.
  -- UNSUPPORTED = weapons from OTHER mods (the Terraria crossover set). Separate from
  -- "untested": untested is a vanilla weapon we have not measured yet and is fixable by
  -- measuring it; unsupported is not vanilla Palworld at all, appears on no data source we
  -- can verify against, and its stats move when that mod updates. Curves ARE built for them,
  -- so turning this on behaves sensibly -- it is off by default, not unimplemented.
  applyUnsupported   = false,
  unsupportedAllow   = {},         -- enable specific modded models: { ["YakushimaBlade005"] = true }
  skipUntestedWeapons = true,      -- master safety. Set to FALSE to apply to EVERY weapon in the library (old behavior).
  untestedAllow      = {},         -- enable specific models: { ["Musket_3"] = true, ["Musket_4"] = true }
  untestedAllowTypes = {},         -- enable a whole type:    { Musket = true }

  -- ---- PRESTIGE -----------------------------------------------------------
  -- When a weapon reaches its cap you can PRESTIGE it (ESC > Mod Options > the
  -- Prestige panel): its level resets to start and one PERMANENT point is banked
  -- into a stat you choose. Prestige is unbounded, but each point stretches the
  -- next climb (prestigeGrindMult), so it self-paces. Points persist per weapon.
  prestigeEnabled = true,      -- master on/off for the whole prestige system
  prestigeToasts  = true,      -- celebrate a prestige with a toast
  prestigeHudSummary = true,   -- aim panel shows the cumulative effect of banked points
                               -- ("\226\152\1333  +3% dmg  +2 mag"); same line tops the menu's
                               -- Prestige panel. Off = stars only, as before.

  -- WHEN a weapon may prestige:
  prestigeRequireMaxLevel = false, -- true = must hit the weapon's TRUE max (Lv 80) first.
                                   -- false = may prestige once it has climbed prestigeMinClimb
                                   --         levels above its base/unlock level (pre-max allowed).
  prestigeMinClimb = 15,       -- (when not requiring max) levels above base before prestige unlocks.
                               --   e.g. a bow that unlocks at Lv3 becomes eligible at Lv18.

  -- Per-POINT bonus for each category (all permanent, stack additively):
  -- THE TWO DAMAGE LEVERS ARE DELIBERATELY EQUAL (2026-08-20, Maiq's call).
  --
  -- They were both 1% and therefore the same stat with two names: +Base adds 1% of base,
  -- which the curve then multiplies to 1% of total, and +% adds 1% of total directly. A
  -- choice between identical options is not a choice. Maiq's own config had raised +Base to
  -- 5% and left +% at the 1% default, which made the pair worse than either alone -- there
  -- was nothing meaningful for the multiplier to multiply.
  --
  -- Matched at 5% they COMPOUND, which is the point: base points raise the floor the curve
  -- stands on, percent points scale everything above it including that raised floor. On a
  -- Vortex Beater at cap, 10 of each is +1,888 damage against +866 for the old lopsided
  -- split. Committing to one weapon is what earns that.
  --
  -- 5% also puts damage on terms with its neighbours: +Level Cap is 5%/pt and +Durability
  -- 10%/pt, against damage's old 1% -- two of five slots were spending a whole prestige
  -- cycle on almost nothing.
  prestigeDamagePerPt = 0.05,  -- +Base Damage:  +5% of BASE damage per point (rounded up, so >= +1)
  prestigePctPerPt    = 0.05,  -- +% Damage:     x1.05 per point on the TOTAL (compounds with the curve)
  prestigeMagPerPt    = 1,     -- +Magazine:     +1 magazine per point (auto weapons only)
  prestigeDurPerPt    = 0.10,  -- +Durability:   +10% MaxDurability per point
  prestigeCapStepPct  = 0.05,  -- +Level Cap %:  +5% of base max level per point (extra levels
                               --   the weapon may climb, past the wielder-level clamp too)

  -- Grind pacing: each banked point multiplies every level's XP cost by this.
  -- 1.2 => each point adds 20%; 3 points ~1.7x, 5 points ~2.5x. 1.0 disables it.
  -- +50% PER POINT (2026-08-20, Maiq's call). It has been 1.2 since prestige shipped in
  -- 1.6.0 -- never 1.5, despite the recollection -- and 1.2 was set against an economy where
  -- a boss paid like one and a half chickens, so the penalty multiplied a cost nobody could
  -- reach anyway. Levelling works now, so the brake has to actually brake.
  -- LINEAR, not compounding: 1 + 0.5 x points. Four points = 3x, ten = 6x, twenty = 11x.
  prestigeGrindMult = 1.5,

  -- Per-FAMILY availability. Categories are auto-derived first -- {dmg,dur,cap}
  -- everywhere, plus mag ONLY where the weapon actually grows a magazine (so bows
  -- and melee never offer +Magazine with no config). An entry here MASKS that for
  -- a weapon family (keyed by its type), e.g. force a category off/on:
  --   prestigeByFamily = { Bow = { mag = false }, Rocket = { mag = false } },
  prestigeByFamily = {},

  -- ---- HUD / QUALITY OF LIFE ----------------------------------------------
  -- (level-up toasts: see levelUpToasts above)

  panelAutoHide = true,   -- weapon panel sleeps when idle; false = classic always-shown.
  panelIdleSec = 2,       -- (only when panelAutoHide) seconds without a shot/hit
                          -- before the panel hides; the next one wipes it back in.
                          -- 2 matches the vanilla weapon wheel's own linger.
  panelOpacity = 100,     -- how solid OUR panel draws (10-100). The panel is a
                          -- CUSTOM DarnToasts surface, so its style is OUR
                          -- config, not the Toasts page's (channel model, 2.0).
  -- WHERE the weapon panel sits. Same reason as panelOpacity: a custom surface
  -- keeps a PRIVATE config, so the DarnToasts page cannot move it and neither can
  -- ToastLib_config -- these are the only knobs that work. All four apply LIVE.
  -- (Reported on Nexus: users tried the Toasts config and the global anchor and
  -- nothing moved, because the position used to be hardcoded here in the mod.)
  panelAnchor  = "right", -- "left" | "center" | "right" -- which edge to sit against
  panelXOffset = 16,      -- px from that edge (center: nudge off middle)
  panelYFrac   = 0.545,   -- vertical spot as a fraction of screen height (0 top, 1 bottom)
  panelYOffset = 0,       -- px added after panelYFrac, for fine tuning
  nameplateInfo = true,   -- EXPERIMENT: append "Lv N  +X%" to the vanilla lower-right
                          -- weapon nameplate (the hotbar's weapon name band).
  dataValidate = true,    -- boot-time truth pass: compare weapondata's base/mag/dur
                          -- against the game's OWN item definitions and auto-correct
                          -- (in memory) any scraped/guessed value that drifted. Every
                          -- correction is logged [DATA]. false = trust the library file.
  -- Save progress at most this often (ms), and only if something changed.
  -- Time-based (not per-event) so freshness never depends on rate of fire; each
  -- save is a few hundred bytes written to .tmp and swapped in, so 1s is cheap.
  saveIntervalMs = 1000,
}

return Config
