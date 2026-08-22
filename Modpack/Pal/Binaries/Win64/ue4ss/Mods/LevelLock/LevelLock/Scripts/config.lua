local Config = {

    -- Tower level caps. Change these to whatever you want.
    -- Game's boss levels are in parentheses for reference (Palworld 1.0 = 9 towers,
    -- level cap 80). Defaults ramp a little above each boss level and end at 80.
    Tower1_Cap = 15,   -- Zoe & Grizzbolt        (boss 10)
    Tower2_Cap = 30,   -- Lily & Lyleen          (boss 20)
    Tower3_Cap = 45,   -- Axel & Orserk          (boss 30)
    Tower4_Cap = 50,   -- Marcus & Faleris       (boss 40)
    Tower5_Cap = 55,   -- Victor & Shadowbeak    (boss 50)
    Tower6_Cap = 62,   -- Saya & Selyne          (boss 55)
    Tower7_Cap = 68,   -- Bjorn & Bastigor       (boss 60)
    Tower8_Cap = 74,   -- Auri & Shaolong        (boss 68)
    Tower9_Cap = 80,   -- Zenara & Astralym      (boss 80, game max)

    -- For existing saves. How many towers have you already beaten? (0-9)
    TowersAlreadyCleared = 0,

    -- false = one shared cap for everyone (default)
    -- true  = each player tracks their own cap, must be in the arena to get credit
    PerPlayerProgress = false,

    -- Also cap your PALS at the same tower gate (players are ALWAYS capped).
    -- Pal levels are never lowered - this only stops them gaining past the cap.
    LockPartyPals = true,   -- cap pals in your party        (they gain combat XP)
    LockBasePals  = true,   -- cap pals working at base camps (they gain work XP)

    -- How a shared base-camp pal is capped in PER-PLAYER mode. Only matters when
    -- PerPlayerProgress = true AND LockBasePals = true. A base camp belongs to the
    -- whole guild (base pals have no individual owner), so when members have
    -- different caps this decides which one a base pal obeys.
    -- Valid values (keep the quotes):
    --   "highest" -> the most-progressed member's cap  (default; base keeps pace, never held back)
    --   "lowest"  -> the least-progressed member's cap (strictest; base waits for everyone)
    --   "off"     -> don't cap base pals at all in per-player mode
    -- In SHARED mode this is ignored (there's one cap, which base pals just use).
    BaseCapPolicy = "highest",

    -- Rested XP. Normally XP earned at the cap is simply thrown away. With this
    -- on, it is banked instead, and paid back out as a bonus once the cap lifts.
    -- Banking is always 1:1, so you can never get back more than the cap took
    -- from you - this cannot make you level faster than playing uncapped.
    RestedXp = true,

    -- How fast the bank pays out, as a percentage of the XP you earn.
    -- 100 = every 10 XP earned pays 20 (10 of it from the bank).
    -- 200 = every 10 XP earned pays 30. Range 10-200, anything else is clamped.
    -- This only changes the PACE of the payout, never the total.
    RestXpPayout = 100,

    -- HARD MODE. Replaces the nine tower gates with fifteen, adding the six raid
    -- bosses as gates of their own. Every raid has to be beaten to progress, and
    -- the caps below are tighter than normal mode's the whole way up.
    HardMode = false,

    -- The hard-mode ladder. Each value is the cap while that gate is still
    -- standing, so Hard1_Cap is your cap until Zoe dies. The gate's own level is
    -- in brackets - raids get 6 to 10 levels of headroom, because a gate you
    -- cannot out-level is a dead end rather than a challenge.
    Hard1_Cap  = 15,  -- Tower 1 - Zoe & Grizzbolt        (10)
    Hard2_Cap  = 25,  -- Tower 2 - Lily & Lyleen          (20)
    Hard3_Cap  = 35,  -- Tower 3 - Axel & Orserk          (30)
    Hard4_Cap  = 45,  -- RAID    - Bellanoir              (35)
    Hard5_Cap  = 48,  -- Tower 4 - Marcus & Faleris       (40)
    Hard6_Cap  = 52,  -- RAID    - Bellanoir Libero       (45)
    Hard7_Cap  = 55,  -- Tower 5 - Victor & Shadowbeak    (50)
    Hard8_Cap  = 58,  -- RAID    - Moon Lord              (50)
    Hard9_Cap  = 62,  -- Tower 6 - Saya & Selyne          (55)
    Hard10_Cap = 65,  -- RAID    - Blazamut Ryu           (55)
    Hard11_Cap = 68,  -- Tower 7 - Bjorn & Bastigor       (60)
    Hard12_Cap = 71,  -- RAID    - Xenolord               (65)
    Hard13_Cap = 74,  -- Tower 8 - Auri & Shaolong        (68)
    Hard14_Cap = 76,  -- RAID    - Hartalis               (70)
    Hard15_Cap = 80,  -- Tower 9 - Zenara & Astralym      (80, game max)

    -- SPHERE TIER LOCK. Stops you using a Pal Sphere your level has not unlocked:
    -- the throw bounces with the game's own "too weak" message and the sphere is
    -- used up, as a failed catch always does. Reads your LEVEL, not your tower
    -- cap, so it only ever blocks spheres you could not have crafted yourself.
    -- Unlock levels: Pal 2, Mega 14, Giga 20, Hyper 27, Ultra 35, Legendary 44,
    -- Ultimate 51, Exotic 58, Sol 67, Ancient 74.
    LockSphereTier = false,

    -- Where to keep the progress file. Leave empty and the mod finds it: a
    -- dedicated server writes to its own Pal\Saved folder (the one holding
    -- SaveGames), a normal game writes to %LOCALAPPDATA%\Pal\Saved. Set a folder
    -- here only if you want it somewhere specific - your backup folder, say. The
    -- folder must already exist; the mod will not create it. Either slash works.
    -- Example: ProgressDir = "C:/palserver/backups",
    ProgressDir = "",

    -- Troubleshooting. Leave OFF for normal play. Turn ON only if something's
    -- wrong and you want to send us logs for a bug report: it writes verbose
    -- output to UE4SS.log (and the console) and binds F9 to print your current
    -- level, cap, and cleared towers.
    Debug = false,

    EnableNotifications = true,
}

return Config
