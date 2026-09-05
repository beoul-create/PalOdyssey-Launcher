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

    -- true  = each player tracks their own cap, must be in the arena to get credit
    PerPlayerProgress = true,

    -- Also cap your PALS at the same tower gate (players are ALWAYS capped).
    LockPartyPals = true,  -- cap pals in your party        (they gain combat XP)
    LockBasePals  = true,  -- cap pals working at base camps (they gain work XP)

    -- How a shared base-camp pal is capped in PER-PLAYER mode.
    BaseCapPolicy = "highest",

    -- Rested XP banking when capped.
    RestedXp = true,

    -- How fast the bank pays out, as a percentage of the XP you earn.
    RestXpPayout = 100,

    -- HARD MODE RAID BOSSES. (Disabled as requested)
    HardMode = false,

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

    -- SPHERE TIER LOCK. Stops you using a Pal Sphere your level has not unlocked
    LockSphereTier = true,

    ProgressDir = "",

    Debug = false,

    EnableNotifications = true,
}

return Config
