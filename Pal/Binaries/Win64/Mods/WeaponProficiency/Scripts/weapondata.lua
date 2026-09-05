-- ============================================================================
--  weapondata.lua -- the AUTHORITATIVE per-model base LIBRARY. Every field here
--  is a COLD table value, immune to our runtime writes -- which is exactly why
--  damage (base) and magazine (mag/magMax) never compounded. Bases: base=AttackValue,
--  mag/magMax=magazine, and (2026-07-20) dur=DT_ItemData Durability.
--
--  startSrc = where `start` (the level a weapon's proficiency BEGINS at) came from:
--    "tech"  = read off the in-game tech tree. Ground truth; never overwrite.
--    "paldb" = scraped "Technology Lv. N" from paldb.cc. 14/14 against in-game checks.
--    "drop"  = the item has NO tech level because it is not crafted -- a raid/dungeon
--              drop -- so `start` is an AVAILABILITY anchor chosen by Mikey, not a
--              scraped fact. (Legendary Meowmere: Moon Lord raid, boss Lv50,
--              recommended Lv60; Mikey set 55 on 2026-07-28.) Never overwrite from a
--              scrape: a scrape can only ever fail to find these.
--    absent  = a tier-derived GUESS, still unverified. Do not trust it.
--
--  dur = per-model VANILLA MaxDurability base (the DT_ItemData "Durability" field).
--  SOURCE: paldb.cc weapon pages (Palworld Database Wiki, extracted from
--  DT_ItemDataTable / DA_StaticItemDataAsset), harvested 2026-07-20 per internal id
--  and per rarity variant. Coverage: 267 of 318 rows carry a real value. The 51
--  without `dur` are, by design, non-applicable or unsourceable:
--    * Pickaxe/Axe tools (11) -- ignored by the mod anyway (cfg.ignoreTypes);
--    * Grenades/ThrowStone (11) -- consumables, no durability field;
--    * the Terraria-crossover MOD set (27: Yakushima* = Meowmere/Terra Blade/
--      Terraprisma/Excalibur/Nightglow/Vortex Beater) -- not vanilla, not on paldb;
--    * BelieverFatCane, PenguinLauncher (2) -- vanilla but paldb lists no durability.
--  A row with no `dur` gets NO durability boost (damage.lua logs it once). To fill a
--  gap, add `dur=<n>` from an authoritative source (see DURABILITY-DUMP.md).
--  NEVER derive dur by observing the live static/dynamic value: durability persists
--  per-instance, so observing a prior boost re-multiplies it (poison-cache). This
--  cold library is the sole base and OVERRIDES the (contaminated) runtime read.
-- ============================================================================
local M = { WEAPONS = {} }
local W = M.WEAPONS
W["AssaultRifle_Default1"]={t="AssaultRifle",hps=5.38,proj=1,base=320,mag=20,tier="T4",start=45,startSrc="paldb",maxLv=300,cap=1278,magMax=40,mode="auto",name="Assault Rifle",hpsSrc="family",dur=3000}
W["AssaultRifle_Default2"]={t="AssaultRifle",hps=5.38,proj=1,base=400,mag=24,tier="T4",start=45,startSrc="paldb",maxLv=300,cap=1492,magMax=53,mode="auto",name="Assault Rifle",hpsSrc="family",dur=3000}
W["AssaultRifle_Default3"]={t="AssaultRifle",hps=5.38,proj=1,base=448,mag=26,tier="T4",start=45,startSrc="paldb",maxLv=300,cap=1705,magMax=61,mode="auto",name="Assault Rifle",hpsSrc="meas",dur=4000}
W["AssaultRifle_Default4"]={t="AssaultRifle",hps=5.38,proj=1,base=512,mag=28,tier="T4",start=45,startSrc="paldb",maxLv=300,cap=1918,magMax=69,mode="auto",name="Assault Rifle",hpsSrc="family",dur=5000}
W["AssaultRifle_Default5"]={t="AssaultRifle",hps=5.38,proj=1,base=560,mag=30,tier="T4",start=45,startSrc="paldb",maxLv=300,cap=2131,magMax=76,mode="auto",name="Assault Rifle",hpsSrc="family",dur=6000}
W["Axe_Steal"]={t="Axe",hps=1.4,proj=1,base=120,mag=0,tier="T3",start=44,startSrc="paldb",maxLv=80,cap=120,magMax=0,mode="melee",name="Pal Metal Axe",hpsSrc="est"}
W["Axe_Tier_00"]={t="Axe",hps=1.4,proj=1,base=20,mag=0,tier="T7",start=1,startSrc="paldb",maxLv=800,cap=66,magMax=0,mode="melee",name="Stone Axe",hpsSrc="est"}
W["Axe_Tier_01"]={t="Axe",hps=1.4,proj=1,base=30,mag=0,tier="T5",start=11,startSrc="paldb",maxLv=400,cap=67,magMax=0,mode="melee",name="Metal Axe",hpsSrc="est"}
W["Axe_Tier_02"]={t="Axe",hps=1.4,proj=1,base=60,mag=0,tier="T4",start=34,startSrc="paldb",maxLv=300,cap=68,magMax=0,mode="melee",name="Refined Metal Axe",hpsSrc="est"}
W["Axe_Tier_03"]={t="Axe",hps=1.4,proj=1,base=75,mag=0,tier="T4",start=24,maxLv=300,cap=75,magMax=0,mode="melee",name="Axe4",hpsSrc="est"}
W["Bat"]={t="Melee",hps=1.4,proj=1,base=25,mag=0,tier="T7",start=1,startSrc="paldb",maxLv=800,cap=825,magMax=0,mode="melee",name="Wooden Club",hpsSrc="est",dur=150}
W["Bat2"]={t="Melee",hps=1.4,proj=1,base=50,mag=0,tier="T7",start=7,startSrc="paldb",maxLv=800,cap=825,magMax=0,mode="melee",name="Bat",hpsSrc="est",dur=150}
W["Bat3"]={t="Melee",hps=1.4,proj=1,base=500,mag=0,tier="T4",start=40,startSrc="paldb",maxLv=300,cap=859,magMax=0,mode="melee",name="Metal Bat",hpsSrc="est",dur=500}
W["Bat3_2"]={t="Melee",hps=1.4,proj=1,base=550,mag=0,tier="T4",start=40,startSrc="paldb",maxLv=300,cap=1002,magMax=0,mode="melee",name="Metal Bat",hpsSrc="est",dur=750}
W["Bat3_3"]={t="Melee",hps=1.4,proj=1,base=600,mag=0,tier="T4",start=40,startSrc="paldb",maxLv=300,cap=1146,magMax=0,mode="melee",name="Metal Bat",hpsSrc="est",dur=1000}
W["Bat3_4"]={t="Melee",hps=1.4,proj=1,base=650,mag=0,tier="T4",start=40,startSrc="paldb",maxLv=300,cap=1289,magMax=0,mode="melee",name="Metal Bat",hpsSrc="est",dur=1500}
W["Bat3_5"]={t="Melee",hps=1.4,proj=1,base=750,mag=0,tier="T4",start=40,startSrc="paldb",maxLv=300,cap=1432,magMax=0,mode="melee",name="Metal Bat",hpsSrc="est",dur=2000}
W["BeamLauncher"]={t="RocketLauncher",hps=0.16,proj=1,base=14000,mag=0,tier="T1",start=80,startSrc="paldb",maxLv=100,cap=14000,magMax=0,mode="single",name="Beam Launcher",hpsSrc="est",dur=3500}
W["BeamLauncher_2"]={t="RocketLauncher",hps=0.16,proj=1,base=14700,mag=0,tier="T1",start=80,startSrc="paldb",maxLv=100,cap=14700,magMax=0,mode="single",name="Beam Launcher",hpsSrc="est",dur=5250}
W["BeamLauncher_3"]={t="RocketLauncher",hps=0.16,proj=1,base=15400,mag=0,tier="T1",start=80,startSrc="paldb",maxLv=100,cap=15400,magMax=0,mode="single",name="Beam Launcher",hpsSrc="est",dur=7000}
W["BeamLauncher_4"]={t="RocketLauncher",hps=0.16,proj=1,base=16100,mag=0,tier="T1",start=80,startSrc="paldb",maxLv=100,cap=16100,magMax=0,mode="single",name="Beam Launcher",hpsSrc="est",dur=10500}
W["BeamLauncher_5"]={t="RocketLauncher",hps=0.16,proj=1,base=16800,mag=0,tier="T1",start=80,startSrc="paldb",maxLv=100,cap=16800,magMax=0,mode="single",name="Beam Launcher",hpsSrc="est",dur=14000}
W["BeamSword"]={t="Sword",hps=1.4,proj=1,base=930,mag=0,tier="T3",start=57,startSrc="paldb",maxLv=80,cap=1396,magMax=0,mode="melee",name="Beam Sword",hpsSrc="est",dur=500}
W["BeamSword_2"]={t="Sword",hps=1.4,proj=1,base=1023,mag=0,tier="T3",start=57,startSrc="paldb",maxLv=80,cap=1629,magMax=0,mode="melee",name="Beam Sword",hpsSrc="est",dur=750}
W["BeamSword_3"]={t="Sword",hps=1.4,proj=1,base=1116,mag=0,tier="T3",start=57,startSrc="paldb",maxLv=80,cap=1862,magMax=0,mode="melee",name="Beam Sword",hpsSrc="est",dur=1000}
W["BeamSword_4"]={t="Sword",hps=1.4,proj=1,base=1209,mag=0,tier="T3",start=57,startSrc="paldb",maxLv=80,cap=2095,magMax=0,mode="melee",name="Beam Sword",hpsSrc="est",dur=1500}
W["BeamSword_5"]={t="Sword",hps=1.4,proj=1,base=1395,mag=0,tier="T3",start=57,startSrc="paldb",maxLv=80,cap=2328,magMax=0,mode="melee",name="Beam Sword",hpsSrc="est",dur=2000}
W["BelieverFatCane"]={t="Melee",hps=1.4,proj=1,base=100,mag=0,tier="T7",start=1,maxLv=800,cap=825,magMax=0,mode="melee",name="Believer Fat Cane",hpsSrc="est"}
W["BowGun"]={t="BowGun",hps=0.38,proj=1,base=280,mag=1,tier="T5",start=13,startSrc="tech",maxLv=400,cap=280,magMax=1,mode="single",name="Crossbow",hpsSrc="family",dur=300}
W["BowGun_2"]={t="BowGun",hps=0.38,proj=1,base=364,mag=1,tier="T5",start=13,startSrc="tech",maxLv=400,cap=364,magMax=1,mode="single",name="Crossbow",hpsSrc="family",dur=800}
W["BowGun_3"]={t="BowGun",hps=0.38,proj=1,base=406,mag=1,tier="T5",start=13,startSrc="tech",maxLv=400,cap=406,magMax=1,mode="single",name="Crossbow",hpsSrc="family",dur=1000}
W["BowGun_4"]={t="BowGun",hps=0.38,proj=1,base=448,mag=1,tier="T5",start=13,startSrc="tech",maxLv=400,cap=448,magMax=1,mode="single",name="Crossbow",hpsSrc="meas",dur=1200}
W["BowGun_5"]={t="BowGun",hps=0.38,proj=1,base=490,mag=1,tier="T5",start=13,startSrc="tech",maxLv=400,cap=490,magMax=1,mode="single",name="Crossbow",hpsSrc="family",dur=1400}
W["Bow_Fifth"]={t="Bow",hps=2.9,proj=5,base=30,mag=1,tier="T7",start=1,maxLv=800,cap=2640,magMax=1,mode="single",name="Five Shot Bow",hpsSrc="est",dur=350}
W["Bow_Fire"]={t="Bow",hps=0.58,proj=1,base=65,mag=1,tier="T7",start=1,maxLv=800,cap=13204,magMax=1,mode="single",name="Fire Bow",hpsSrc="est",dur=150}
W["Bow_Poison"]={t="Bow",hps=0.58,proj=1,base=65,mag=1,tier="T7",start=1,maxLv=800,cap=13204,magMax=1,mode="single",name="Poison Bow",hpsSrc="est",dur=150}
W["Bow_Triple"]={t="Bow",hps=1.78,proj=3,base=40,mag=1,tier="T7",start=10,startSrc="tech",maxLv=800,cap=4401,magMax=1,mode="single",name="Three Shot Bow",hpsSrc="meas",dur=250}
W["BronzeSword"]={t="Sword",hps=1.63,proj=1,base=180,mag=0,tier="T5",start=17,startSrc="paldb",maxLv=400,cap=1353,magMax=0,mode="melee",name="Primitive Sword",hpsSrc="meas",dur=500}
W["ChargeLaserRifle"]={t="LaserRifle",hps=0.22,proj=1,base=12500,mag=6,tier="T2",start=65,startSrc="paldb",maxLv=200,cap=12500,magMax=6,mode="single",name="Charge Rifle",hpsSrc="est",dur=200}
W["ChargeLaserRifle_2"]={t="LaserRifle",hps=0.22,proj=1,base=13125,mag=7,tier="T2",start=65,startSrc="paldb",maxLv=200,cap=13125,magMax=7,mode="single",name="Charge Rifle",hpsSrc="est",dur=300}
W["ChargeLaserRifle_3"]={t="LaserRifle",hps=0.22,proj=1,base=13750,mag=8,tier="T2",start=65,startSrc="paldb",maxLv=200,cap=13750,magMax=8,mode="single",name="Charge Rifle",hpsSrc="est",dur=400}
W["ChargeLaserRifle_4"]={t="LaserRifle",hps=0.22,proj=1,base=14375,mag=9,tier="T2",start=65,startSrc="paldb",maxLv=200,cap=14375,magMax=9,mode="single",name="Charge Rifle",hpsSrc="est",dur=600}
W["ChargeLaserRifle_5"]={t="LaserRifle",hps=0.22,proj=1,base=15000,mag=10,tier="T2",start=65,startSrc="paldb",maxLv=200,cap=15000,magMax=10,mode="single",name="Charge Rifle",hpsSrc="est",dur=800}
W["CompoundBow"]={t="Bow",hps=0.58,proj=1,base=1100,mag=1,tier="T4",start=42,startSrc="paldb",maxLv=300,cap=13752,magMax=1,mode="single",name="Compound Bow",hpsSrc="family",dur=400}
W["CompoundBow_2"]={t="Bow",hps=0.58,proj=1,base=1265,mag=1,tier="T4",start=42,startSrc="paldb",maxLv=300,cap=16044,magMax=1,mode="single",name="Compound Bow",hpsSrc="family",dur=600}
W["CompoundBow_3"]={t="Bow",hps=0.58,proj=1,base=1375,mag=1,tier="T4",start=42,startSrc="paldb",maxLv=300,cap=18336,magMax=1,mode="single",name="Compound Bow",hpsSrc="meas",dur=800}
W["CompoundBow_4"]={t="Bow",hps=0.58,proj=1,base=1485,mag=1,tier="T4",start=42,startSrc="paldb",maxLv=300,cap=20628,magMax=1,mode="single",name="Compound Bow",hpsSrc="family",dur=1200}
W["CompoundBow_5"]={t="Bow",hps=0.58,proj=1,base=1650,mag=1,tier="T4",start=42,startSrc="paldb",maxLv=300,cap=22920,magMax=1,mode="single",name="Compound Bow",hpsSrc="family",dur=1600}
W["DoubleBarrelShotgun"]={t="Shotgun",hps=5.24,proj=9,base=190,mag=2,tier="T4",start=39,startSrc="tech",maxLv=300,cap=802,magMax=4,mode="auto",name="Double-Barreled Shotgun",hpsSrc="family",dur=200}
W["DoubleBarrelShotgun_2"]={t="Shotgun",hps=5.24,proj=9,base=285,mag=2,tier="T4",start=39,startSrc="tech",maxLv=300,cap=935,magMax=5,mode="auto",name="Double-Barreled Shotgun",hpsSrc="meas",dur=400}
W["DoubleBarrelShotgun_3"]={t="Shotgun",hps=5.24,proj=9,base=323,mag=2,tier="T4",start=39,startSrc="tech",maxLv=300,cap=1069,magMax=6,mode="auto",name="Double-Barreled Shotgun",hpsSrc="family",dur=500}
W["DoubleBarrelShotgun_4"]={t="Shotgun",hps=5.24,proj=9,base=361,mag=2,tier="T4",start=39,startSrc="tech",maxLv=300,cap=1203,magMax=6,mode="auto",name="Double-Barreled Shotgun",hpsSrc="family",dur=600}
W["DoubleBarrelShotgun_5"]={t="Shotgun",hps=5.24,proj=9,base=399,mag=2,tier="T4",start=39,startSrc="tech",maxLv=300,cap=1337,magMax=7,mode="auto",name="Double-Barreled Shotgun",hpsSrc="family",dur=800}
-- DroneLauncher hps MEASURED 2026-08-19 from the attribution probe's own per-hit timestamps
-- (n=2564): peak 103 hits in a 1.0s sliding window = 103.0 hits/s, filed as 103.4 so both swarm
-- weapons share one number -- 0.4% apart is far inside the sample noise. paldb's 0.27 was the
-- LAUNCHER's trigger rate, not the drones' output, and 1/hps is the xp divisor.
-- xpTune 3.34 = 103.4/30.97, the peak-to-combat correction; see the Terraprisma rows. hps stays
-- the PEAK because it is the sanity ceiling and (for laddered weapons) the curve basis -- putting
-- a combat rate here scaled the Terraprisma 899x, caught by test-lacurve.
W["DroneLauncher"]={t="DroneLauncher",hps=103.4,proj=1,base=200,mag=0,tier="T1",start=77,startSrc="paldb",maxLv=100,cap=200,magMax=0,xpTune=3.34,mode="single",name="Drone Launcher",hpsSrc="meas",dur=6500}
W["DroneLauncher_2"]={t="DroneLauncher",hps=103.4,proj=1,base=210,mag=0,tier="T1",start=77,startSrc="paldb",maxLv=100,cap=210,magMax=0,xpTune=3.34,mode="single",name="Drone Launcher",hpsSrc="family",dur=9750}
W["DroneLauncher_3"]={t="DroneLauncher",hps=103.4,proj=1,base=220,mag=0,tier="T1",start=77,startSrc="paldb",maxLv=100,cap=220,magMax=0,xpTune=3.34,mode="single",name="Drone Launcher",hpsSrc="family",dur=13000}
W["DroneLauncher_4"]={t="DroneLauncher",hps=103.4,proj=1,base=230,mag=0,tier="T1",start=77,startSrc="paldb",maxLv=100,cap=230,magMax=0,xpTune=3.34,mode="single",name="Drone Launcher",hpsSrc="family",dur=19500}
W["DroneLauncher_5"]={t="DroneLauncher",hps=103.4,proj=1,base=240,mag=0,tier="T1",start=77,startSrc="paldb",maxLv=100,cap=240,magMax=0,xpTune=3.34,mode="single",name="Drone Launcher",hpsSrc="family",dur=26000}
W["ElecBaton"]={t="Melee",hps=1.4,proj=1,base=10,mag=0,tier="T5",start=22,startSrc="paldb",maxLv=400,cap=846,magMax=0,mode="melee",name="Stun Baton",hpsSrc="est",dur=300}
W["ElectricArcAssaultRifle"]={t="AssaultRifle",hps=3.6,proj=1,base=1860,mag=38,tier="T1",start=78,startSrc="paldb",maxLv=100,cap=1860,magMax=48,mode="auto",name="Plasma Rifle",hpsSrc="est",dur=25000}
W["ElectricArcAssaultRifle_2"]={t="AssaultRifle",hps=3.6,proj=1,base=1953,mag=40,tier="T1",start=78,startSrc="paldb",maxLv=100,cap=1953,magMax=56,mode="auto",name="Plasma Rifle",hpsSrc="est",dur=37500}
W["ElectricArcAssaultRifle_3"]={t="AssaultRifle",hps=3.6,proj=1,base=2046,mag=42,tier="T1",start=78,startSrc="paldb",maxLv=100,cap=2046,magMax=64,mode="auto",name="Plasma Rifle",hpsSrc="est",dur=50000}
W["ElectricArcAssaultRifle_4"]={t="AssaultRifle",hps=3.6,proj=1,base=2139,mag=44,tier="T1",start=78,startSrc="paldb",maxLv=100,cap=2139,magMax=72,mode="auto",name="Plasma Rifle",hpsSrc="est",dur=75000}
W["ElectricArcAssaultRifle_5"]={t="AssaultRifle",hps=3.6,proj=1,base=2232,mag=46,tier="T1",start=78,startSrc="paldb",maxLv=100,cap=2232,magMax=80,mode="auto",name="Plasma Rifle",hpsSrc="est",dur=100000}
W["EnergyRocketLauncher"]={t="RocketLauncher",hps=0.16,proj=1,base=10000,mag=2,tier="T3",start=61,startSrc="paldb",maxLv=80,cap=10000,magMax=2,mode="single",name="Plasma Cannon",hpsSrc="est",dur=300}
W["EnergyRocketLauncher_2"]={t="RocketLauncher",hps=0.16,proj=1,base=11000,mag=2,tier="T3",start=61,startSrc="paldb",maxLv=80,cap=11407,magMax=2,mode="single",name="Plasma Cannon",hpsSrc="est",dur=450}
W["EnergyRocketLauncher_3"]={t="RocketLauncher",hps=0.16,proj=1,base=11500,mag=2,tier="T3",start=61,startSrc="paldb",maxLv=80,cap=13036,magMax=2,mode="single",name="Plasma Cannon",hpsSrc="est",dur=600}
W["EnergyRocketLauncher_4"]={t="RocketLauncher",hps=0.16,proj=1,base=12000,mag=2,tier="T3",start=61,startSrc="paldb",maxLv=80,cap=14666,magMax=2,mode="single",name="Plasma Cannon",hpsSrc="est",dur=900}
W["EnergyRocketLauncher_5"]={t="RocketLauncher",hps=0.16,proj=1,base=13000,mag=2,tier="T3",start=61,startSrc="paldb",maxLv=80,cap=16296,magMax=2,mode="single",name="Plasma Cannon",hpsSrc="est",dur=1200}
W["EnergyShotgun"]={t="Shotgun",hps=4.05,proj=9,base=402,mag=10,tier="T2",start=63,startSrc="paldb",maxLv=200,cap=827,magMax=20,mode="auto",name="Energy Shotgun",hpsSrc="est",dur=300}
W["EnergyShotgun_2"]={t="Shotgun",hps=4.05,proj=9,base=422,mag=11,tier="T2",start=63,startSrc="paldb",maxLv=200,cap=965,magMax=26,mode="auto",name="Energy Shotgun",hpsSrc="est",dur=450}
W["EnergyShotgun_3"]={t="Shotgun",hps=4.05,proj=9,base=442,mag=12,tier="T2",start=63,startSrc="paldb",maxLv=200,cap=1103,magMax=34,mode="auto",name="Energy Shotgun",hpsSrc="est",dur=600}
W["EnergyShotgun_4"]={t="Shotgun",hps=4.05,proj=9,base=462,mag=13,tier="T2",start=63,startSrc="paldb",maxLv=200,cap=1241,magMax=42,mode="auto",name="Energy Shotgun",hpsSrc="est",dur=900}
W["EnergyShotgun_5"]={t="Shotgun",hps=4.05,proj=9,base=482,mag=14,tier="T2",start=63,startSrc="paldb",maxLv=200,cap=1379,magMax=50,mode="auto",name="Energy Shotgun",hpsSrc="est",dur=1200}
W["FlameThrower"]={t="FlameThrower",hps=3.89,proj=1,base=636,mag=100,tier="T3",start=52,startSrc="paldb",maxLv=80,cap=636,magMax=100,mode="auto",name="Flamethrower",hpsSrc="family",dur=6000}
W["FlameThrower_2"]={t="FlameThrower",hps=3.89,proj=1,base=731,mag=100,tier="T3",start=52,startSrc="paldb",maxLv=80,cap=731,magMax=102,mode="auto",name="Flamethrower",hpsSrc="family",dur=9000}
W["FlameThrower_3"]={t="FlameThrower",hps=3.89,proj=1,base=795,mag=100,tier="T3",start=52,startSrc="paldb",maxLv=80,cap=795,magMax=116,mode="auto",name="Flamethrower",hpsSrc="meas",dur=12000}
W["FlameThrower_4"]={t="FlameThrower",hps=3.89,proj=1,base=858,mag=100,tier="T3",start=52,startSrc="paldb",maxLv=80,cap=858,magMax=131,mode="auto",name="Flamethrower",hpsSrc="family",dur=18000}
W["FlameThrower_5"]={t="FlameThrower",hps=3.89,proj=1,base=954,mag=100,tier="T3",start=52,startSrc="paldb",maxLv=80,cap=954,magMax=146,mode="auto",name="Flamethrower",hpsSrc="family",dur=24000}
W["FragGrenade"]={t="Grenade",hps=0.27,proj=1,base=750,mag=0,tier="T5",start=25,startSrc="paldb",maxLv=400,cap=2256,magMax=0,mode="single",name="Frag Grenade",hpsSrc="est"}
W["FragGrenade_Dark"]={t="Grenade",hps=0.27,proj=1,base=750,mag=0,tier="T5",start=40,startSrc="paldb",maxLv=400,cap=2256,magMax=0,mode="single",name="Dark Grenade",hpsSrc="est"}
W["FragGrenade_Dragon"]={t="Grenade",hps=0.27,proj=1,base=750,mag=0,tier="T5",start=42,startSrc="paldb",maxLv=400,cap=2256,magMax=0,mode="single",name="Dragon Grenade",hpsSrc="est"}
W["FragGrenade_Elec"]={t="Grenade",hps=0.27,proj=1,base=750,mag=0,tier="T5",start=27,startSrc="paldb",maxLv=400,cap=2256,magMax=0,mode="single",name="Shock Grenade",hpsSrc="est"}
W["FragGrenade_Fire"]={t="Grenade",hps=0.27,proj=1,base=750,mag=0,tier="T5",start=31,startSrc="paldb",maxLv=400,cap=2256,magMax=0,mode="single",name="Incendiary Grenade",hpsSrc="est"}
W["FragGrenade_Ground"]={t="Grenade",hps=0.27,proj=1,base=750,mag=0,tier="T5",start=38,startSrc="paldb",maxLv=400,cap=2256,magMax=0,mode="single",name="Ground Grenade",hpsSrc="est"}
W["FragGrenade_Ice"]={t="Grenade",hps=0.27,proj=1,base=750,mag=0,tier="T5",start=29,startSrc="paldb",maxLv=400,cap=2256,magMax=0,mode="single",name="Ice Grenade",hpsSrc="est"}
W["FragGrenade_Leaf"]={t="Grenade",hps=0.27,proj=1,base=750,mag=0,tier="T5",start=35,startSrc="paldb",maxLv=400,cap=2256,magMax=0,mode="single",name="Grass Grenade",hpsSrc="est"}
W["FragGrenade_Super"]={t="Grenade",hps=0.27,proj=1,base=4000,mag=0,tier="T5",start=53,startSrc="paldb",maxLv=400,cap=4000,magMax=0,mode="single",name="Frag Grenade Mk2",hpsSrc="est"}
W["FragGrenade_Water"]={t="Grenade",hps=0.27,proj=1,base=750,mag=0,tier="T5",start=33,startSrc="paldb",maxLv=400,cap=2256,magMax=0,mode="single",name="Water Grenade",hpsSrc="est"}
W["GatlingGun"]={t="GatlingGun",hps=10.26,proj=1,base=375,mag=100,tier="T7",start=54,startSrc="paldb",maxLv=800,cap=379,magMax=100,mode="auto",name="Gatling Gun",hpsSrc="meas",dur=6000}
W["GatlingGun_2"]={t="GatlingGun",hps=10.26,proj=1,base=431,mag=100,tier="T7",start=54,startSrc="paldb",maxLv=800,cap=442,magMax=100,mode="auto",name="Gatling Gun",hpsSrc="fam",dur=9000}
W["GatlingGun_3"]={t="GatlingGun",hps=10.26,proj=1,base=468,mag=100,tier="T7",start=54,startSrc="paldb",maxLv=800,cap=505,magMax=110,mode="auto",name="Gatling Gun",hpsSrc="fam",dur=12000}
W["GatlingGun_4"]={t="GatlingGun",hps=10.26,proj=1,base=506,mag=100,tier="T7",start=54,startSrc="paldb",maxLv=800,cap=568,magMax=124,mode="auto",name="Gatling Gun",hpsSrc="fam",dur=18000}
W["GatlingGun_5"]={t="GatlingGun",hps=10.26,proj=1,base=562,mag=100,tier="T7",start=54,startSrc="paldb",maxLv=800,cap=631,magMax=138,mode="auto",name="Gatling Gun",hpsSrc="fam",dur=24000}
W["GrenadeLauncher"]={t="GrenadeLauncher",hps=0.27,proj=1,base=3000,mag=5,tier="T3",start=53,startSrc="paldb",maxLv=80,cap=4694,magMax=10,mode="auto",name="Grenade Launcher",hpsSrc="est",dur=600}
W["GrenadeLauncher_2"]={t="GrenadeLauncher",hps=0.27,proj=1,base=3450,mag=5,tier="T3",start=53,startSrc="paldb",maxLv=80,cap=5476,magMax=12,mode="auto",name="Grenade Launcher",hpsSrc="est",dur=900}
W["GrenadeLauncher_3"]={t="GrenadeLauncher",hps=0.27,proj=1,base=3750,mag=5,tier="T3",start=53,startSrc="paldb",maxLv=80,cap=6259,magMax=14,mode="auto",name="Grenade Launcher",hpsSrc="est",dur=1200}
W["GrenadeLauncher_4"]={t="GrenadeLauncher",hps=0.27,proj=1,base=4050,mag=5,tier="T3",start=53,startSrc="paldb",maxLv=80,cap=7041,magMax=16,mode="auto",name="Grenade Launcher",hpsSrc="est",dur=1800}
W["GrenadeLauncher_5"]={t="GrenadeLauncher",hps=0.27,proj=1,base=4500,mag=5,tier="T3",start=53,startSrc="paldb",maxLv=80,cap=7824,magMax=18,mode="auto",name="Grenade Launcher",hpsSrc="est",dur=2400}
W["GuidedMissileLauncher"]={t="MissileLauncher",hps=0.16,proj=1,base=5900,mag=1,tier="T3",start=56,startSrc="paldb",maxLv=80,cap=5900,magMax=1,mode="single",name="Guided Missile Launcher",hpsSrc="est",dur=300}
W["GuidedMissileLauncher_2"]={t="MissileLauncher",hps=0.16,proj=1,base=6785,mag=1,tier="T3",start=56,startSrc="paldb",maxLv=80,cap=6785,magMax=1,mode="single",name="Guided Missile Launcher",hpsSrc="est",dur=450}
W["GuidedMissileLauncher_3"]={t="MissileLauncher",hps=0.16,proj=1,base=7375,mag=1,tier="T3",start=56,startSrc="paldb",maxLv=80,cap=7375,magMax=1,mode="single",name="Guided Missile Launcher",hpsSrc="est",dur=600}
W["GuidedMissileLauncher_4"]={t="MissileLauncher",hps=0.16,proj=1,base=7965,mag=1,tier="T3",start=56,startSrc="paldb",maxLv=80,cap=7965,magMax=1,mode="single",name="Guided Missile Launcher",hpsSrc="est",dur=900}
W["GuidedMissileLauncher_5"]={t="MissileLauncher",hps=0.16,proj=1,base=8850,mag=1,tier="T3",start=56,startSrc="paldb",maxLv=80,cap=8850,magMax=1,mode="single",name="Guided Missile Launcher",hpsSrc="est",dur=1200}
W["HandGun_Default"]={t="Handgun",hps=1.95,proj=1,base=250,mag=8,tier="T5",start=28,startSrc="tech",maxLv=400,cap=846,magMax=16,mode="auto",name="Handgun",hpsSrc="meas",dur=400}
W["HandGun_Default_2"]={t="Handgun",hps=1.95,proj=1,base=437,mag=10,tier="T5",start=28,startSrc="tech",maxLv=400,cap=987,magMax=24,mode="auto",name="Handgun",hpsSrc="meas",dur=1200}
W["HandGun_Default_3"]={t="Handgun",hps=1.95,proj=1,base=500,mag=12,tier="T5",start=28,startSrc="tech",maxLv=400,cap=1128,magMax=34,mode="auto",name="Handgun",hpsSrc="meas",dur=1600}
W["HandGun_Default_4"]={t="Handgun",hps=1.95,proj=1,base=562,mag=14,tier="T5",start=28,startSrc="tech",maxLv=400,cap=1269,magMax=45,mode="auto",name="Handgun",hpsSrc="meas",dur=2000}
W["HandGun_Default_5"]={t="Handgun",hps=1.95,proj=1,base=625,mag=16,tier="T5",start=28,startSrc="tech",maxLv=400,cap=1410,magMax=56,mode="auto",name="Handgun",hpsSrc="meas",dur=2400}
W["HandgunShield"]={t="Handgun",hps=1.17,proj=1,base=250,mag=20,tier="T5",start=15,maxLv=400,cap=846,magMax=34,mode="auto",name="Ballistic Shield",hpsSrc="derived",dur=400}
W["Katana"]={t="Katana",hps=1.59,proj=1,base=780,mag=0,tier="T3",start=44,startSrc="paldb",maxLv=80,cap=780,magMax=0,mode="melee",name="Katana",hpsSrc="measured",dur=500}
W["Katana_2"]={t="Katana",hps=1.59,proj=1,base=858,mag=0,tier="T3",start=44,startSrc="paldb",maxLv=80,cap=858,magMax=0,mode="melee",name="Katana",hpsSrc="measured",dur=750}
W["Katana_3"]={t="Katana",hps=1.59,proj=1,base=936,mag=0,tier="T3",start=44,startSrc="paldb",maxLv=80,cap=936,magMax=0,mode="melee",name="Katana",hpsSrc="measured",dur=1000}
W["Katana_4"]={t="Katana",hps=1.59,proj=1,base=1014,mag=0,tier="T3",start=44,startSrc="paldb",maxLv=80,cap=1021,magMax=0,mode="melee",name="Katana",hpsSrc="measured",dur=1500}
W["Katana_5"]={t="Katana",hps=1.59,proj=1,base=1170,mag=0,tier="T3",start=44,startSrc="paldb",maxLv=80,cap=1170,magMax=0,mode="melee",name="Katana",hpsSrc="measured",dur=2000}
W["LaserGatlingGun"]={t="GatlingGun",hps=10.26,proj=1,base=530,mag=100,tier="T7",start=59,startSrc="paldb",maxLv=800,cap=530,magMax=100,mode="auto",name="Laser Gatling Gun",hpsSrc="fam",dur=8000}
W["LaserGatlingGun_2"]={t="GatlingGun",hps=10.26,proj=1,base=583,mag=100,tier="T7",start=59,startSrc="paldb",maxLv=800,cap=583,magMax=100,mode="auto",name="Laser Gatling Gun",hpsSrc="fam",dur=12000}
W["LaserGatlingGun_3"]={t="GatlingGun",hps=10.26,proj=1,base=609,mag=100,tier="T7",start=59,startSrc="paldb",maxLv=800,cap=609,magMax=110,mode="auto",name="Laser Gatling Gun",hpsSrc="fam",dur=16000}
W["LaserGatlingGun_4"]={t="GatlingGun",hps=10.26,proj=1,base=636,mag=100,tier="T7",start=59,startSrc="paldb",maxLv=800,cap=636,magMax=124,mode="auto",name="Laser Gatling Gun",hpsSrc="fam",dur=24000}
W["LaserGatlingGun_5"]={t="GatlingGun",hps=10.26,proj=1,base=689,mag=100,tier="T7",start=59,startSrc="paldb",maxLv=800,cap=689,magMax=138,mode="auto",name="Laser Gatling Gun",hpsSrc="fam",dur=32000}
W["LaserMiningTool"]={t="Pickaxe",hps=1.4,proj=1,base=250,mag=0,tier="T3",start=54,startSrc="paldb",maxLv=80,cap=250,magMax=0,mode="melee",name="Plasma Multicutter",hpsSrc="est"}
W["LaserRifle"]={t="LaserRifle",hps=2.23,proj=1,base=1250,mag=30,tier="T3",start=51,startSrc="paldb",maxLv=80,cap=8730,magMax=44,mode="auto",name="Laser Rifle",hpsSrc="family",dur=3000}
W["LaserRifle_2"]={t="LaserRifle",hps=2.23,proj=1,base=1437,mag=30,tier="T3",start=51,startSrc="paldb",maxLv=80,cap=10185,magMax=51,mode="auto",name="Laser Rifle",hpsSrc="meas",dur=4500}
W["LaserRifle_3"]={t="LaserRifle",hps=2.23,proj=1,base=1562,mag=30,tier="T3",start=51,startSrc="paldb",maxLv=80,cap=11640,magMax=58,mode="auto",name="Laser Rifle",hpsSrc="family",dur=6000}
W["LaserRifle_4"]={t="LaserRifle",hps=2.23,proj=1,base=1687,mag=30,tier="T3",start=51,startSrc="paldb",maxLv=80,cap=13095,magMax=65,mode="auto",name="Laser Rifle",hpsSrc="family",dur=9000}
W["LaserRifle_5"]={t="LaserRifle",hps=2.23,proj=1,base=1875,mag=30,tier="T3",start=51,startSrc="paldb",maxLv=80,cap=14550,magMax=73,mode="auto",name="Laser Rifle",hpsSrc="family",dur=12000}
W["Launcher_Default"]={t="RocketLauncher",hps=0.16,proj=1,base=10000,mag=1,tier="T3",start=65,startSrc="paldb",maxLv=80,cap=10000,magMax=1,mode="single",name="Rocket Launcher",hpsSrc="est",dur=300}
W["Launcher_Default_2"]={t="RocketLauncher",hps=0.16,proj=1,base=11000,mag=1,tier="T3",start=65,startSrc="paldb",maxLv=80,cap=11407,magMax=1,mode="single",name="Rocket Launcher",hpsSrc="est",dur=800}
W["Launcher_Default_3"]={t="RocketLauncher",hps=0.16,proj=1,base=12000,mag=1,tier="T3",start=65,startSrc="paldb",maxLv=80,cap=13036,magMax=1,mode="single",name="Rocket Launcher",hpsSrc="est",dur=1000}
W["Launcher_Default_4"]={t="RocketLauncher",hps=0.16,proj=1,base=13000,mag=1,tier="T3",start=65,startSrc="paldb",maxLv=80,cap=14666,magMax=1,mode="single",name="Rocket Launcher",hpsSrc="est",dur=1200}
W["Launcher_Default_5"]={t="RocketLauncher",hps=0.16,proj=1,base=14000,mag=1,tier="T3",start=65,startSrc="paldb",maxLv=80,cap=16296,magMax=1,mode="single",name="Rocket Launcher",hpsSrc="est",dur=1400}
W["Launcher_Meteor"]={t="RocketLauncher",hps=0.16,proj=1,base=2000,mag=1,tier="T4",start=38,startSrc="tech",maxLv=300,cap=9626,magMax=1,mode="single",name="Meteor Launcher",hpsSrc="est",dur=300}
W["Launcher_Meteor_5"]={t="RocketLauncher",hps=0.16,proj=1,base=10500,mag=1,tier="T4",start=38,startSrc="tech",maxLv=300,cap=16044,magMax=1,mode="single",name="Meteor Launcher",hpsSrc="est",dur=450}
W["MakeshiftAssaultRifle"]={t="AssaultRifle",hps=3.6,proj=1,base=170,mag=15,tier="T5",start=31,startSrc="tech",maxLv=400,cap=1258,magMax=30,mode="auto",name="Makeshift Assault Rifle",hpsSrc="family",dur=1500}
W["MakeshiftAssaultRifle_2"]={t="AssaultRifle",hps=3.6,proj=1,base=204,mag=17,tier="T5",start=31,startSrc="tech",maxLv=400,cap=1468,magMax=41,mode="auto",name="Makeshift Assault Rifle",hpsSrc="meas",dur=2250}
W["MakeshiftAssaultRifle_3"]={t="AssaultRifle",hps=3.6,proj=1,base=229,mag=19,tier="T5",start=31,startSrc="tech",maxLv=400,cap=1678,magMax=53,mode="auto",name="Makeshift Assault Rifle",hpsSrc="family",dur=3000}
W["MakeshiftAssaultRifle_4"]={t="AssaultRifle",hps=3.6,proj=1,base=255,mag=21,tier="T5",start=31,startSrc="tech",maxLv=400,cap=1888,magMax=67,mode="auto",name="Makeshift Assault Rifle",hpsSrc="family",dur=4500}
W["MakeshiftAssaultRifle_5"]={t="AssaultRifle",hps=3.6,proj=1,base=297,mag=23,tier="T5",start=31,startSrc="tech",maxLv=400,cap=2098,magMax=75,mode="auto",name="Makeshift Assault Rifle",hpsSrc="family",dur=6000}
W["MakeshiftHandgun"]={t="Handgun",hps=0.94,proj=1,base=320,mag=6,tier="T5",tierAdj=-1,start=24,startSrc="tech",maxLv=400,cap=846,magMax=12,mode="auto",name="Makeshift Handgun",hpsSrc="family",dur=300}
W["MakeshiftHandgun_2"]={t="Handgun",hps=0.94,proj=1,base=560,mag=6,tier="T5",tierAdj=-1,start=24,startSrc="tech",maxLv=400,cap=987,magMax=14,mode="auto",name="Makeshift Handgun",hpsSrc="meas",dur=600}
W["MakeshiftHandgun_3"]={t="Handgun",hps=0.94,proj=1,base=640,mag=6,tier="T5",tierAdj=-1,start=24,startSrc="tech",maxLv=400,cap=1128,magMax=17,mode="auto",name="Makeshift Handgun",hpsSrc="family",dur=900}
W["MakeshiftHandgun_4"]={t="Handgun",hps=0.94,proj=1,base=720,mag=6,tier="T5",tierAdj=-1,start=24,startSrc="tech",maxLv=400,cap=1269,magMax=19,mode="auto",name="Makeshift Handgun",hpsSrc="family",dur=1200}
W["MakeshiftHandgun_5"]={t="Handgun",hps=0.94,proj=1,base=800,mag=6,tier="T5",tierAdj=-1,start=24,startSrc="tech",maxLv=400,cap=1410,magMax=22,mode="auto",name="Makeshift Handgun",hpsSrc="family",dur=1500}
W["MakeshiftShotgun"]={t="Shotgun",hps=2.63,proj=9,base=215,mag=1,tier="T5",start=30,startSrc="tech",maxLv=400,cap=789,magMax=1,mode="single",name="Makeshift Shotgun",hpsSrc="family",dur=200}
W["MakeshiftShotgun_2"]={t="Shotgun",hps=2.63,proj=9,base=258,mag=1,tier="T5",start=30,startSrc="tech",maxLv=400,cap=921,magMax=1,mode="single",name="Makeshift Shotgun",hpsSrc="family",dur=300}
W["MakeshiftShotgun_3"]={t="Shotgun",hps=2.63,proj=9,base=290,mag=1,tier="T5",start=30,startSrc="tech",maxLv=400,cap=1052,magMax=1,mode="single",name="Makeshift Shotgun",hpsSrc="meas",dur=400}
W["MakeshiftShotgun_4"]={t="Shotgun",hps=2.63,proj=9,base=322,mag=1,tier="T5",start=30,startSrc="tech",maxLv=400,cap=1184,magMax=1,mode="single",name="Makeshift Shotgun",hpsSrc="family",dur=600}
W["MakeshiftShotgun_5"]={t="Shotgun",hps=2.63,proj=9,base=376,mag=1,tier="T5",start=30,startSrc="tech",maxLv=400,cap=1316,magMax=1,mode="single",name="Makeshift Shotgun",hpsSrc="family",dur=800}
W["MakeshiftSubmachineGun"]={t="SubmachineGun",hps=4.45,proj=1,base=100,mag=24,tier="T5",start=26,startSrc="tech",maxLv=400,cap=895,magMax=45,mode="auto",name="Makeshift SMG",hpsSrc="meas",dur=1000}
W["MakeshiftSubmachineGun_2"]={t="SubmachineGun",hps=4.45,proj=1,base=120,mag=26,tier="T5",start=26,startSrc="tech",maxLv=400,cap=1044,magMax=53,mode="auto",name="Makeshift SMG",hpsSrc="meas",dur=1500}
W["MakeshiftSubmachineGun_3"]={t="SubmachineGun",hps=4.45,proj=1,base=135,mag=28,tier="T5",start=26,startSrc="tech",maxLv=400,cap=1193,magMax=60,mode="auto",name="Makeshift SMG",hpsSrc="meas",dur=2000}
W["MakeshiftSubmachineGun_4"]={t="SubmachineGun",hps=4.45,proj=1,base=150,mag=30,tier="T5",start=26,startSrc="tech",maxLv=400,cap=1342,magMax=68,mode="auto",name="Makeshift SMG",hpsSrc="meas",dur=3000}
W["MakeshiftSubmachineGun_5"]={t="SubmachineGun",hps=4.45,proj=1,base=175,mag=32,tier="T5",start=26,startSrc="tech",maxLv=400,cap=1491,magMax=75,mode="auto",name="Makeshift SMG",hpsSrc="meas",dur=4000}
W["MeatCutterKnife"]={t="Butcher",hps=1.4,proj=1,base=25,mag=0,tier="T7",start=12,startSrc="paldb",maxLv=800,cap=825,magMax=0,mode="melee",name="Meat Cleaver",hpsSrc="est",dur=300}
W["MultiGuidedMissileLauncher"]={t="MissileLauncher",hps=0.16,proj=1,base=5900,mag=4,tier="T3",start=33,maxLv=80,cap=5900,magMax=4,mode="single",name="Multi Guided Missile Launcher",hpsSrc="est",dur=300}
W["MultiGuidedMissileLauncher_2"]={t="MissileLauncher",hps=0.16,proj=1,base=6785,mag=4,tier="T3",start=33,maxLv=80,cap=6785,magMax=4,mode="single",name="Multi Guided Missile Launcher",hpsSrc="est",dur=450}
W["MultiGuidedMissileLauncher_3"]={t="MissileLauncher",hps=0.16,proj=1,base=7375,mag=4,tier="T3",start=33,maxLv=80,cap=7375,magMax=4,mode="single",name="Multi Guided Missile Launcher",hpsSrc="est",dur=600}
W["MultiGuidedMissileLauncher_4"]={t="MissileLauncher",hps=0.16,proj=1,base=7965,mag=4,tier="T3",start=33,maxLv=80,cap=7965,magMax=4,mode="single",name="Multi Guided Missile Launcher",hpsSrc="est",dur=900}
W["MultiGuidedMissileLauncher_5"]={t="MissileLauncher",hps=0.16,proj=1,base=8850,mag=4,tier="T3",start=33,maxLv=80,cap=8850,magMax=4,mode="single",name="Multi Guided Missile Launcher",hpsSrc="est",dur=1200}
W["Musket"]={t="SniperRifle",hps=0.16,proj=1,base=1000,mag=1,tier="T5",start=21,startSrc="tech",maxLv=400,cap=1302,magMax=1,mode="single",name="Musket",hpsSrc="family",dur=200}
W["Musket_2"]={t="SniperRifle",hps=0.16,proj=1,base=1400,mag=1,tier="T5",start=21,startSrc="tech",maxLv=400,cap=1519,magMax=1,mode="single",name="Musket",hpsSrc="meas",dur=400}
W["Musket_3"]={t="SniperRifle",hps=0.16,proj=1,base=1600,mag=1,tier="T5",start=21,startSrc="tech",maxLv=400,cap=1737,magMax=1,mode="single",name="Musket",hpsSrc="family",dur=500}
W["Musket_4"]={t="SniperRifle",hps=0.16,proj=1,base=1800,mag=1,tier="T5",start=21,startSrc="tech",maxLv=400,cap=1954,magMax=1,mode="single",name="Musket",hpsSrc="family",dur=600}
W["Musket_5"]={t="SniperRifle",hps=0.16,proj=1,base=2000,mag=1,tier="T5",start=21,startSrc="tech",maxLv=400,cap=2171,magMax=1,mode="single",name="Musket",hpsSrc="family",dur=800}
W["OctaviaRevolver"]={t="Handgun",hps=2.25,proj=1,base=250,mag=0,tier="T4",start=32,startSrc="tech",maxLv=300,cap=859,magMax=0,mode="auto",name="Marksman Revolver",hpsSrc="est",dur=400}
W["OctaviaRevolver_2"]={t="Handgun",hps=2.25,proj=1,base=437,mag=0,tier="T4",start=32,startSrc="tech",maxLv=300,cap=1002,magMax=0,mode="auto",name="Marksman Revolver",hpsSrc="est",dur=1200}
W["OctaviaRevolver_3"]={t="Handgun",hps=2.25,proj=1,base=500,mag=0,tier="T4",start=32,startSrc="tech",maxLv=300,cap=1146,magMax=0,mode="auto",name="Marksman Revolver",hpsSrc="est",dur=1600}
W["OctaviaRevolver_4"]={t="Handgun",hps=2.25,proj=1,base=562,mag=0,tier="T4",start=32,startSrc="tech",maxLv=300,cap=1289,magMax=0,mode="auto",name="Marksman Revolver",hpsSrc="est",dur=2000}
W["OctaviaRevolver_5"]={t="Handgun",hps=2.25,proj=1,base=625,mag=0,tier="T4",start=32,startSrc="tech",maxLv=300,cap=1432,magMax=0,mode="auto",name="Marksman Revolver",hpsSrc="est",dur=2400}
W["OctaviaShotgun"]={t="Shotgun",hps=4.05,proj=9,base=230,mag=0,tier="T3",start=56,startSrc="paldb",maxLv=80,cap=814,magMax=0,mode="auto",name="Core Eject Shotgun",hpsSrc="est",dur=150}
W["OctaviaShotgun_2"]={t="Shotgun",hps=4.05,proj=9,base=402,mag=0,tier="T3",start=56,startSrc="paldb",maxLv=80,cap=950,magMax=0,mode="auto",name="Core Eject Shotgun",hpsSrc="est",dur=225}
W["OctaviaShotgun_3"]={t="Shotgun",hps=4.05,proj=9,base=460,mag=0,tier="T3",start=56,startSrc="paldb",maxLv=80,cap=1086,magMax=0,mode="auto",name="Core Eject Shotgun",hpsSrc="est",dur=300}
W["OctaviaShotgun_4"]={t="Shotgun",hps=4.05,proj=9,base=517,mag=0,tier="T3",start=56,startSrc="paldb",maxLv=80,cap=1222,magMax=0,mode="auto",name="Core Eject Shotgun",hpsSrc="est",dur=450}
W["OctaviaShotgun_5"]={t="Shotgun",hps=4.05,proj=9,base=575,mag=0,tier="T3",start=56,startSrc="paldb",maxLv=80,cap=1358,magMax=0,mode="auto",name="Core Eject Shotgun",hpsSrc="est",dur=600}
W["OldRevolver"]={t="Handgun",hps=0.78,proj=1,base=600,mag=6,tier="T4",start=33,startSrc="tech",maxLv=300,cap=859,magMax=12,mode="auto",name="Old Revolver",hpsSrc="meas",dur=400}
W["OldRevolver_2"]={t="Handgun",hps=0.78,proj=1,base=1050,mag=6,tier="T4",start=33,startSrc="tech",maxLv=300,cap=1050,magMax=14,mode="auto",name="Old Revolver",hpsSrc="meas",dur=600}
W["OldRevolver_3"]={t="Handgun",hps=0.78,proj=1,base=1200,mag=6,tier="T4",start=33,startSrc="tech",maxLv=300,cap=1200,magMax=17,mode="auto",name="Old Revolver",hpsSrc="meas",dur=800}
W["OldRevolver_4"]={t="Handgun",hps=0.78,proj=1,base=1350,mag=6,tier="T4",start=33,startSrc="tech",maxLv=300,cap=1350,magMax=19,mode="auto",name="Old Revolver",hpsSrc="meas",dur=1200}
W["OldRevolver_5"]={t="Handgun",hps=0.78,proj=1,base=1500,mag=6,tier="T4",start=33,startSrc="tech",maxLv=300,cap=1500,magMax=22,mode="auto",name="Old Revolver",hpsSrc="meas",dur=1600}
W["OverheatRifle"]={t="AssaultRifle",hps=3.6,proj=1,base=1225,mag=0,tier="T2",start=64,startSrc="paldb",maxLv=200,cap=1319,magMax=0,mode="auto",name="Overheat Rifle",hpsSrc="est",dur=3000}
W["OverheatRifle_2"]={t="AssaultRifle",hps=3.6,proj=1,base=1286,mag=0,tier="T2",start=64,startSrc="paldb",maxLv=200,cap=1538,magMax=0,mode="auto",name="Overheat Rifle",hpsSrc="est",dur=3000}
W["OverheatRifle_3"]={t="AssaultRifle",hps=3.6,proj=1,base=1347,mag=0,tier="T2",start=64,startSrc="paldb",maxLv=200,cap=1758,magMax=0,mode="auto",name="Overheat Rifle",hpsSrc="est",dur=4000}
W["OverheatRifle_4"]={t="AssaultRifle",hps=3.6,proj=1,base=1408,mag=0,tier="T2",start=64,startSrc="paldb",maxLv=200,cap=1978,magMax=0,mode="auto",name="Overheat Rifle",hpsSrc="est",dur=5000}
W["OverheatRifle_5"]={t="AssaultRifle",hps=3.6,proj=1,base=1470,mag=0,tier="T2",start=64,startSrc="paldb",maxLv=200,cap=2198,magMax=0,mode="auto",name="Overheat Rifle",hpsSrc="est",dur=6000}
W["PalDopingShot"]={t="Handgun",hps=1.01,proj=1,base=250,mag=8,tier="T5",start=25,startSrc="paldb",maxLv=400,cap=846,magMax=16,mode="auto",name="Boost Gun",hpsSrc="derived",dur=400}
W["PalDopingShot_2"]={t="Handgun",hps=1.01,proj=1,base=250,mag=8,tier="T2",start=63,startSrc="paldb",maxLv=200,cap=1034,magMax=19,mode="auto",name="Megaboost Gun",hpsSrc="derived",dur=400}
W["PalDopingShot_3"]={t="Handgun",hps=1.01,proj=1,base=250,mag=8,tier="T5",start=25,startSrc="paldb",maxLv=400,cap=1128,magMax=22,mode="auto",name="Boost Gun",hpsSrc="derived",dur=400}
W["PenguinLauncher"]={t="RocketLauncher",hps=0.16,proj=1,base=10000,mag=1,tier="T3",start=33,maxLv=80,cap=10000,magMax=1,mode="single",name="Penguin Launcher",hpsSrc="est"}
W["Pickaxe_Steal"]={t="Pickaxe",hps=1.4,proj=1,base=120,mag=0,tier="T3",start=44,startSrc="paldb",maxLv=80,cap=145,magMax=0,mode="melee",name="Pal Metal Pickaxe",hpsSrc="est"}
W["Pickaxe_Tier_00"]={t="Pickaxe",hps=1.4,proj=1,base=20,mag=0,tier="T7",start=1,startSrc="paldb",maxLv=800,cap=137,magMax=0,mode="melee",name="Stone Pickaxe",hpsSrc="est"}
W["Pickaxe_Tier_01"]={t="Pickaxe",hps=1.4,proj=1,base=30,mag=0,tier="T5",start=11,startSrc="paldb",maxLv=400,cap=141,magMax=0,mode="melee",name="Metal Pickaxe",hpsSrc="est"}
W["Pickaxe_Tier_02"]={t="Pickaxe",hps=1.4,proj=1,base=60,mag=0,tier="T4",start=34,startSrc="paldb",maxLv=300,cap=143,magMax=0,mode="melee",name="Refined Metal Pickaxe",hpsSrc="est"}
W["Pickaxe_Tier_03"]={t="Pickaxe",hps=1.4,proj=1,base=75,mag=0,tier="T4",start=24,maxLv=300,cap=143,magMax=0,mode="melee",name="Pickaxe",hpsSrc="est"}
W["PumpActionShotgun"]={t="Shotgun",hps=7.61,proj=9,base=220,mag=8,tier="T4",start=43,startSrc="paldb",maxLv=300,cap=802,magMax=16,mode="auto",name="Pump-Action Shotgun",hpsSrc="family",dur=150}
W["PumpActionShotgun_2"]={t="Shotgun",hps=7.61,proj=9,base=275,mag=9,tier="T4",start=43,startSrc="paldb",maxLv=300,cap=935,magMax=22,mode="auto",name="Pump-Action Shotgun",hpsSrc="meas",dur=500}
W["PumpActionShotgun_3"]={t="Shotgun",hps=7.61,proj=9,base=308,mag=10,tier="T4",start=43,startSrc="paldb",maxLv=300,cap=1069,magMax=28,mode="auto",name="Pump-Action Shotgun",hpsSrc="family",dur=600}
W["PumpActionShotgun_4"]={t="Shotgun",hps=7.61,proj=9,base=352,mag=11,tier="T4",start=43,startSrc="paldb",maxLv=300,cap=1203,magMax=35,mode="auto",name="Pump-Action Shotgun",hpsSrc="family",dur=700}
W["PumpActionShotgun_5"]={t="Shotgun",hps=7.61,proj=9,base=385,mag=12,tier="T4",start=43,startSrc="paldb",maxLv=300,cap=1337,magMax=43,mode="auto",name="Pump-Action Shotgun",hpsSrc="family",dur=800}
W["RecurveBow"]={t="Bow",hps=0.58,proj=1,base=40,mag=1,tier="T7",start=1,maxLv=800,cap=13204,magMax=1,mode="single",name="Recurve Bow",hpsSrc="est",dur=200}
W["SFBow"]={t="Bow",hps=0.58,proj=1,base=5800,mag=1,tier="T3",start=57,startSrc="paldb",maxLv=80,cap=13968,magMax=1,mode="single",name="Advanced Bow",hpsSrc="est",dur=500}
W["SFBow_2"]={t="Bow",hps=0.58,proj=1,base=6670,mag=1,tier="T3",start=57,startSrc="paldb",maxLv=80,cap=16296,magMax=1,mode="single",name="Advanced Bow",hpsSrc="est",dur=750}
W["SFBow_3"]={t="Bow",hps=0.58,proj=1,base=7250,mag=1,tier="T3",start=57,startSrc="paldb",maxLv=80,cap=18624,magMax=1,mode="single",name="Advanced Bow",hpsSrc="est",dur=1000}
W["SFBow_4"]={t="Bow",hps=0.58,proj=1,base=7830,mag=1,tier="T3",start=57,startSrc="paldb",maxLv=80,cap=20952,magMax=1,mode="single",name="Advanced Bow",hpsSrc="est",dur=1500}
W["SFBow_5"]={t="Bow",hps=0.58,proj=1,base=8700,mag=1,tier="T3",start=57,startSrc="paldb",maxLv=80,cap=23280,magMax=1,mode="single",name="Advanced Bow",hpsSrc="est",dur=2000}
-- SkyBow = the MECHANICAL BOW (2026-08-08, Nightcodex's "mechanical bow does not level up":
-- it had NO ROW at all -- unknown weapon, so the untested toggle never mattered). Stats from
-- DT_ItemDataTable (PAV 20000-24000, dur 2000-8000); unlock 67 per the vault's confirmed
-- tech levels. It IS the bow ladder's endpoint weapon, so like the Terraprisma its natural
-- damage sits above the ladder top: cap=base, no boost, levels for the record. hps est from
-- the single-shot bow family; measure to lift the gate.
W["SemiAutoRifle"]={t="AssaultRifle",hps=1.55,proj=1,base=1150,mag=8,tier="T4",start=41,startSrc="paldb",maxLv=300,cap=1278,magMax=16,mode="auto",name="Semi-Auto Rifle",hpsSrc="family",dur=1000}
W["SemiAutoRifle_2"]={t="AssaultRifle",hps=1.55,proj=1,base=1265,mag=9,tier="T4",start=41,startSrc="paldb",maxLv=300,cap=1492,magMax=22,mode="auto",name="Semi-Auto Rifle",hpsSrc="family",dur=1500}
W["SemiAutoRifle_3"]={t="AssaultRifle",hps=1.55,proj=1,base=1380,mag=10,tier="T4",start=41,startSrc="paldb",maxLv=300,cap=1705,magMax=28,mode="auto",name="Semi-Auto Rifle",hpsSrc="family",dur=2000}
W["SemiAutoRifle_4"]={t="AssaultRifle",hps=1.55,proj=1,base=1495,mag=11,tier="T4",start=41,startSrc="paldb",maxLv=300,cap=1918,magMax=35,mode="auto",name="Semi-Auto Rifle",hpsSrc="family",dur=3000}
W["SemiAutoRifle_5"]={t="AssaultRifle",hps=1.55,proj=1,base=1610,mag=12,tier="T4",start=41,startSrc="paldb",maxLv=300,cap=2131,magMax=43,mode="auto",name="Semi-Auto Rifle",hpsSrc="meas",dur=4000}
W["SemiAutoShotgun"]={t="Shotgun",hps=9.64,proj=9,base=195,mag=10,tier="T3",start=47,startSrc="tech",maxLv=80,cap=814,magMax=20,mode="auto",name="Semi-Auto Shotgun",hpsSrc="family",dur=300}
W["SemiAutoShotgun_2"]={t="Shotgun",hps=9.64,proj=9,base=214,mag=11,tier="T3",start=47,startSrc="tech",maxLv=80,cap=950,magMax=26,mode="auto",name="Semi-Auto Shotgun",hpsSrc="family",dur=450}
W["SemiAutoShotgun_3"]={t="Shotgun",hps=9.64,proj=9,base=234,mag=12,tier="T3",start=47,startSrc="tech",maxLv=80,cap=1086,magMax=34,mode="auto",name="Semi-Auto Shotgun",hpsSrc="meas",dur=600}
W["SemiAutoShotgun_4"]={t="Shotgun",hps=9.64,proj=9,base=253,mag=13,tier="T3",start=47,startSrc="tech",maxLv=80,cap=1222,magMax=42,mode="auto",name="Semi-Auto Shotgun",hpsSrc="family",dur=900}
W["SemiAutoShotgun_5"]={t="Shotgun",hps=9.64,proj=9,base=282,mag=14,tier="T3",start=47,startSrc="tech",maxLv=80,cap=1358,magMax=50,mode="auto",name="Semi-Auto Shotgun",hpsSrc="family",dur=1200}
W["SingleShotRifle"]={t="SniperRifle",hps=0.42,proj=1,base=1100,mag=1,tier="T4",start=36,startSrc="tech",maxLv=300,cap=1323,magMax=1,mode="single",name="Single-Shot Rifle",hpsSrc="meas",dur=1000}
W["SingleShotRifle_2"]={t="SniperRifle",hps=0.42,proj=1,base=1650,mag=1,tier="T4",start=36,startSrc="tech",maxLv=300,cap=1650,magMax=1,mode="single",name="Single-Shot Rifle",hpsSrc="family",dur=2000}
W["SingleShotRifle_3"]={t="SniperRifle",hps=0.42,proj=1,base=1870,mag=1,tier="T4",start=36,startSrc="tech",maxLv=300,cap=1870,magMax=1,mode="single",name="Single-Shot Rifle",hpsSrc="family",dur=2500}
W["SingleShotRifle_4"]={t="SniperRifle",hps=0.42,proj=1,base=2090,mag=1,tier="T4",start=36,startSrc="tech",maxLv=300,cap=2090,magMax=1,mode="single",name="Single-Shot Rifle",hpsSrc="family",dur=3000}
W["SingleShotRifle_5"]={t="SniperRifle",hps=0.42,proj=1,base=2310,mag=1,tier="T4",start=36,startSrc="tech",maxLv=300,cap=2310,magMax=1,mode="single",name="Single-Shot Rifle",hpsSrc="family",dur=4000}
W["SkyAssaultRifle"]={t="AssaultRifle",hps=6.17,proj=1,base=1615,mag=30,tier="T1",start=70,startSrc="paldb",maxLv=100,cap=1615,magMax=48,mode="auto",name="Heavy Assault Rifle",hpsSrc="family",dur=5500}
W["SkyAssaultRifle_2"]={t="AssaultRifle",hps=6.17,proj=1,base=1695,mag=34,tier="T1",start=70,startSrc="paldb",maxLv=100,cap=1695,magMax=56,mode="auto",name="Heavy Assault Rifle",hpsSrc="meas",dur=8250}
W["SkyAssaultRifle_3"]={t="AssaultRifle",hps=6.17,proj=1,base=1776,mag=38,tier="T1",start=70,startSrc="paldb",maxLv=100,cap=1785,magMax=64,mode="auto",name="Heavy Assault Rifle",hpsSrc="family",dur=11000}
W["SkyAssaultRifle_4"]={t="AssaultRifle",hps=6.17,proj=1,base=1857,mag=42,tier="T1",start=70,startSrc="paldb",maxLv=100,cap=2008,magMax=72,mode="auto",name="Heavy Assault Rifle",hpsSrc="family",dur=16500}
W["SkyAssaultRifle_5"]={t="AssaultRifle",hps=6.17,proj=1,base=1938,mag=46,tier="T1",start=70,startSrc="paldb",maxLv=100,cap=2232,magMax=80,mode="auto",name="Heavy Assault Rifle",hpsSrc="family",dur=22000}
W["SkyBeamSword"]={t="Sword",hps=1.73,proj=1,base=2000,mag=0,tier="T1",start=73,startSrc="paldb",maxLv=100,cap=2000,magMax=0,mode="melee",name="Laser Sword",hpsSrc="family",dur=1200}
W["SkyBeamSword_2"]={t="Sword",hps=1.73,proj=1,base=2100,mag=0,tier="T1",start=73,startSrc="paldb",maxLv=100,cap=2100,magMax=0,mode="melee",name="Laser Sword",hpsSrc="family",dur=1800}
W["SkyBeamSword_3"]={t="Sword",hps=1.73,proj=1,base=2200,mag=0,tier="T1",start=73,startSrc="paldb",maxLv=100,cap=2200,magMax=0,mode="melee",name="Laser Sword",hpsSrc="meas",dur=2400}
W["SkyBeamSword_4"]={t="Sword",hps=1.73,proj=1,base=2300,mag=0,tier="T1",start=73,startSrc="paldb",maxLv=100,cap=2300,magMax=0,mode="melee",name="Laser Sword",hpsSrc="family",dur=3600}
W["SkyBeamSword_5"]={t="Sword",hps=1.73,proj=1,base=2400,mag=0,tier="T1",start=73,startSrc="paldb",maxLv=100,cap=2400,magMax=0,mode="melee",name="Laser Sword",hpsSrc="family",dur=4800}
W["SkyBow"]={t="Bow",hps=0.56,proj=1,base=20000,mag=1,tier="T1",start=67,startSrc="tech",maxLv=100,cap=20000,magMax=1,mode="single",name="Mechanical Bow",hpsSrc="family",dur=2000}
W["SkyBow_2"]={t="Bow",hps=0.56,proj=1,base=21000,mag=1,tier="T1",start=67,startSrc="tech",maxLv=100,cap=21000,magMax=1,mode="single",name="Mechanical Bow",hpsSrc="meas",dur=3000}
W["SkyBow_3"]={t="Bow",hps=0.56,proj=1,base=22000,mag=1,tier="T1",start=67,startSrc="tech",maxLv=100,cap=22000,magMax=1,mode="single",name="Mechanical Bow",hpsSrc="family",dur=4000}
W["SkyBow_4"]={t="Bow",hps=0.56,proj=1,base=23000,mag=1,tier="T1",start=67,startSrc="tech",maxLv=100,cap=23000,magMax=1,mode="single",name="Mechanical Bow",hpsSrc="family",dur=6000}
W["SkyBow_5"]={t="Bow",hps=0.56,proj=1,base=24000,mag=1,tier="T1",start=67,startSrc="tech",maxLv=100,cap=24000,magMax=1,mode="single",name="Mechanical Bow",hpsSrc="family",dur=8000}
W["SkyGrenadeLauncher"]={t="GrenadeLauncher",hps=0.27,proj=1,base=6722,mag=8,tier="T1",start=72,startSrc="paldb",maxLv=100,cap=6722,magMax=16,mode="auto",name="Tactical Grenade Launcher",hpsSrc="est",dur=800}
W["SkyGrenadeLauncher_2"]={t="GrenadeLauncher",hps=0.27,proj=1,base=7058,mag=10,tier="T1",start=72,startSrc="paldb",maxLv=100,cap=7058,magMax=24,mode="auto",name="Tactical Grenade Launcher",hpsSrc="est",dur=1200}
W["SkyGrenadeLauncher_3"]={t="GrenadeLauncher",hps=0.27,proj=1,base=7394,mag=10,tier="T1",start=72,startSrc="paldb",maxLv=100,cap=7394,magMax=28,mode="auto",name="Tactical Grenade Launcher",hpsSrc="est",dur=1600}
W["SkyGrenadeLauncher_4"]={t="GrenadeLauncher",hps=0.27,proj=1,base=7730,mag=12,tier="T1",start=72,startSrc="paldb",maxLv=100,cap=7730,magMax=32,mode="auto",name="Tactical Grenade Launcher",hpsSrc="est",dur=2400}
W["SkyGrenadeLauncher_5"]={t="GrenadeLauncher",hps=0.27,proj=1,base=8066,mag=12,tier="T1",start=72,startSrc="paldb",maxLv=100,cap=8066,magMax=36,mode="auto",name="Tactical Grenade Launcher",hpsSrc="est",dur=3200}
W["SkyShotgun"]={t="Shotgun",hps=9.31,proj=9,base=1167,mag=12,tier="T1",start=69,startSrc="paldb",maxLv=100,cap=1167,magMax=24,mode="auto",name="Prototype Shotgun",hpsSrc="family",dur=6000}
W["SkyShotgun_2"]={t="Shotgun",hps=9.31,proj=9,base=1225,mag=14,tier="T1",start=69,startSrc="paldb",maxLv=100,cap=1225,magMax=34,mode="auto",name="Prototype Shotgun",hpsSrc="meas",dur=9000}
W["SkyShotgun_3"]={t="Shotgun",hps=9.31,proj=9,base=1283,mag=16,tier="T1",start=69,startSrc="paldb",maxLv=100,cap=1283,magMax=45,mode="auto",name="Prototype Shotgun",hpsSrc="family",dur=12000}
W["SkyShotgun_4"]={t="Shotgun",hps=9.31,proj=9,base=1342,mag=18,tier="T1",start=69,startSrc="paldb",maxLv=100,cap=1342,magMax=58,mode="auto",name="Prototype Shotgun",hpsSrc="family",dur=18000}
W["SkyShotgun_5"]={t="Shotgun",hps=9.31,proj=9,base=1400,mag=20,tier="T1",start=69,startSrc="paldb",maxLv=100,cap=1400,magMax=72,mode="auto",name="Prototype Shotgun",hpsSrc="family",dur=24000}
W["SkySubmachineGun"]={t="SubmachineGun",hps=6.36,proj=1,base=907,mag=42,tier="T1",start=68,startSrc="paldb",maxLv=100,cap=952,magMax=48,mode="auto",name="Combat SMG",hpsSrc="est",dur=8000}
W["SkySubmachineGun_2"]={t="SubmachineGun",hps=6.36,proj=1,base=1088,mag=44,tier="T1",start=68,startSrc="paldb",maxLv=100,cap=1110,magMax=56,mode="auto",name="Combat SMG",hpsSrc="est",dur=12000}
W["SkySubmachineGun_3"]={t="SubmachineGun",hps=6.36,proj=1,base=1224,mag=46,tier="T1",start=68,startSrc="paldb",maxLv=100,cap=1269,magMax=64,mode="auto",name="Combat SMG",hpsSrc="est",dur=16000}
W["SkySubmachineGun_4"]={t="SubmachineGun",hps=6.36,proj=1,base=1360,mag=48,tier="T1",start=68,startSrc="paldb",maxLv=100,cap=1428,magMax=72,mode="auto",name="Combat SMG",hpsSrc="est",dur=24000}
W["SkySubmachineGun_5"]={t="SubmachineGun",hps=6.36,proj=1,base=1587,mag=50,tier="T1",start=68,startSrc="paldb",maxLv=100,cap=1587,magMax=80,mode="auto",name="Combat SMG",hpsSrc="est",dur=32000}
W["SniperRifle_Default"]={t="SniperRifle",hps=0.24,proj=1,base=1000,mag=4,tier="T7",start=1,maxLv=800,cap=1270,magMax=4,mode="single",name="Sniper Rifle",hpsSrc="est",dur=500}
W["Spear"]={t="Melee",hps=1.4,proj=1,base=35,mag=0,tier="T7",start=3,startSrc="paldb",maxLv=800,cap=825,magMax=0,mode="melee",name="Stone Spear",hpsSrc="est",dur=200}
W["Spear_2"]={t="Melee",hps=1.4,proj=1,base=80,mag=0,tier="T5",start=13,startSrc="paldb",maxLv=400,cap=987,magMax=0,mode="melee",name="Metal Spear",hpsSrc="est",dur=250}
W["Spear_3"]={t="Melee",hps=1.4,proj=1,base=310,mag=0,tier="T4",start=34,startSrc="paldb",maxLv=300,cap=1146,magMax=0,mode="melee",name="Refined Metal Spear",hpsSrc="est",dur=300}
W["Spear_ForestBoss"]={t="Melee",hps=1.4,proj=1,base=860,mag=0,tier="T4",start=24,maxLv=300,cap=860,magMax=0,mode="melee",name="Lily's Spear",hpsSrc="est",dur=500}
W["Spear_ForestBoss2"]={t="Melee",hps=1.4,proj=1,base=1200,mag=0,tier="T2",start=42,maxLv=200,cap=1200,magMax=0,mode="melee",name="Enhanced Lily's Spear",hpsSrc="est",dur=600}
W["Spear_ForestBoss2_5"]={t="Melee",hps=1.4,proj=1,base=1500,mag=0,tier="T2",start=42,maxLv=200,cap=1500,magMax=0,mode="melee",name="Enhanced Lily's Spear",hpsSrc="est",dur=2400}
W["Spear_ForestBoss_5"]={t="Melee",hps=1.4,proj=1,base=1075,mag=0,tier="T4",start=24,maxLv=300,cap=1432,magMax=0,mode="melee",name="Lily's Spear",hpsSrc="est",dur=2000}
W["Spear_QueenBee"]={t="Melee",hps=1.4,proj=1,base=150,mag=0,tier="T7",start=1,maxLv=800,cap=825,magMax=0,mode="melee",name="Elizabee's Staff",hpsSrc="est",dur=300}
W["Spear_SoldierBee"]={t="Melee",hps=1.4,proj=1,base=150,mag=0,tier="T7",start=1,maxLv=800,cap=825,magMax=0,mode="melee",name="Beegarde's Spear",hpsSrc="est",dur=400}
W["SubmachineGun"]={t="SubmachineGun",hps=7.4,proj=1,base=130,mag=24,tier="T4",start=37,startSrc="tech",maxLv=300,cap=909,magMax=46,mode="auto",name="SMG",hpsSrc="family",dur=2000}
W["SubmachineGun_2"]={t="SubmachineGun",hps=7.4,proj=1,base=156,mag=26,tier="T4",start=37,startSrc="tech",maxLv=300,cap=1060,magMax=53,mode="auto",name="SMG",hpsSrc="meas",dur=3000}
W["SubmachineGun_3"]={t="SubmachineGun",hps=7.4,proj=1,base=175,mag=28,tier="T4",start=37,startSrc="tech",maxLv=300,cap=1212,magMax=61,mode="auto",name="SMG",hpsSrc="family",dur=4000}
W["SubmachineGun_4"]={t="SubmachineGun",hps=7.4,proj=1,base=195,mag=30,tier="T4",start=37,startSrc="tech",maxLv=300,cap=1364,magMax=69,mode="auto",name="SMG",hpsSrc="family",dur=6000}
W["SubmachineGun_5"]={t="SubmachineGun",hps=7.4,proj=1,base=227,mag=32,tier="T4",start=37,startSrc="tech",maxLv=300,cap=1515,magMax=76,mode="auto",name="SMG",hpsSrc="family",dur=8000}
W["Sword"]={t="Sword",hps=1.4,proj=1,base=360,mag=0,tier="T5",start=29,startSrc="paldb",maxLv=400,cap=1353,magMax=0,mode="melee",name="Sword",hpsSrc="est",dur=500}
W["Sword_2"]={t="Sword",hps=1.4,proj=1,base=396,mag=0,tier="T5",start=29,startSrc="paldb",maxLv=400,cap=1579,magMax=0,mode="melee",name="Sword",hpsSrc="est",dur=750}
W["Sword_3"]={t="Sword",hps=1.4,proj=1,base=432,mag=0,tier="T5",start=29,startSrc="paldb",maxLv=400,cap=1804,magMax=0,mode="melee",name="Sword",hpsSrc="est",dur=1000}
W["Sword_4"]={t="Sword",hps=1.4,proj=1,base=468,mag=0,tier="T5",start=29,startSrc="paldb",maxLv=400,cap=2030,magMax=0,mode="melee",name="Sword",hpsSrc="est",dur=1500}
W["Sword_5"]={t="Sword",hps=1.4,proj=1,base=540,mag=0,tier="T5",start=29,startSrc="paldb",maxLv=400,cap=2256,magMax=0,mode="melee",name="Sword",hpsSrc="est",dur=2000}
W["ThrowStone"]={t="Grenade",hps=0.27,proj=1,base=50,mag=0,tier="T5",start=15,maxLv=400,cap=2256,magMax=0,mode="single",name="Throw Stone",hpsSrc="est"}
W["Torch"]={t="Melee",hps=1.4,proj=1,base=10,mag=0,tier="T7",start=1,startSrc="paldb",maxLv=800,cap=825,magMax=0,mode="melee",name="Hand-Held Torch",hpsSrc="est",dur=100}
W["WeakerBow"]={t="Bow",hps=0.54,proj=1,base=65,mag=1,tier="T7",start=3,startSrc="tech",maxLv=800,cap=13204,magMax=1,mode="single",name="Old Bow",hpsSrc="meas",dur=150}
W["WeakerBow_2"]={t="Bow",hps=0.54,proj=1,base=130,mag=1,tier="T7",start=3,startSrc="tech",maxLv=800,cap=15405,magMax=1,mode="single",name="Old Bow",hpsSrc="meas",dur=400}
W["WeakerBow_3"]={t="Bow",hps=0.54,proj=1,base=169,mag=1,tier="T7",start=3,startSrc="tech",maxLv=800,cap=17606,magMax=1,mode="single",name="Old Bow",hpsSrc="meas",dur=500}
W["WeakerBow_4"]={t="Bow",hps=0.54,proj=1,base=208,mag=1,tier="T7",start=3,startSrc="tech",maxLv=800,cap=19807,magMax=1,mode="single",name="Old Bow",hpsSrc="meas",dur=600}
W["WeakerBow_5"]={t="Bow",hps=0.54,proj=1,base=247,mag=1,tier="T7",start=3,startSrc="tech",maxLv=800,cap=22008,magMax=1,mode="single",name="Old Bow",hpsSrc="meas",dur=700}
W["WidePenetrateShotgun"]={t="Shotgun",hps=24.37,proj=6,base=508,mag=30,tier="T1",start=75,startSrc="paldb",maxLv=100,cap=840,magMax=48,mode="auto",name="Beam Scatter",hpsSrc="family",dur=950}
W["WidePenetrateShotgun_2"]={t="Shotgun",hps=24.37,proj=6,base=533,mag=32,tier="T1",start=75,startSrc="paldb",maxLv=100,cap=980,magMax=56,mode="auto",name="Beam Scatter",hpsSrc="family",dur=1425}
W["WidePenetrateShotgun_3"]={t="Shotgun",hps=24.37,proj=6,base=558,mag=34,tier="T1",start=75,startSrc="paldb",maxLv=100,cap=1120,magMax=64,mode="auto",name="Beam Scatter",hpsSrc="family",dur=1900}
W["WidePenetrateShotgun_4"]={t="Shotgun",hps=24.37,proj=6,base=584,mag=36,tier="T1",start=75,startSrc="paldb",maxLv=100,cap=1260,magMax=72,mode="auto",name="Beam Scatter",hpsSrc="family",dur=2850}
W["WidePenetrateShotgun_5"]={t="Shotgun",hps=24.37,proj=6,base=609,mag=38,tier="T1",start=75,startSrc="paldb",maxLv=100,cap=1400,magMax=80,mode="auto",name="Beam Scatter",hpsSrc="meas",dur=3800}
W["YakushimaBlade"]={t="Sword",hps=1.4,proj=1,base=200,mag=0,tier="T5",start=30,startSrc="tech",maxLv=400,cap=1353,magMax=0,mode="melee",name="Meowmere",hpsSrc="est",unsupported=true}
W["YakushimaBlade002"]={t="Sword",hps=10.26,proj=2,base=425,mag=0,tier="T4",start=45,startSrc="drop",maxLv=300,cap=1375,magMax=0,mode="melee",name="Terra Blade",hpsSrc="meas",unsupported=true}
W["YakushimaBlade002_2"]={t="Sword",hps=10.26,proj=2,base=467,mag=0,tier="T4",start=45,startSrc="drop",maxLv=300,cap=1604,magMax=0,mode="melee",name="Terra Blade",hpsSrc="family",unsupported=true}
W["YakushimaBlade002_3"]={t="Sword",hps=10.26,proj=2,base=510,mag=0,tier="T4",start=45,startSrc="drop",maxLv=300,cap=1833,magMax=0,mode="melee",name="Terra Blade",hpsSrc="family",unsupported=true}
W["YakushimaBlade002_4"]={t="Sword",hps=10.26,proj=2,base=552,mag=0,tier="T4",start=45,startSrc="drop",maxLv=300,cap=2062,magMax=0,mode="melee",name="Terra Blade",hpsSrc="family",unsupported=true}
W["YakushimaBlade002_5"]={t="Sword",hps=10.26,proj=2,base=637,mag=0,tier="T4",start=45,startSrc="drop",maxLv=300,cap=2292,magMax=0,mode="melee",name="Terra Blade",hpsSrc="family",unsupported=true}
W["YakushimaBlade003"]={t="Sword",hps=103.4,proj=1,base=90,mag=0,tier="T4",start=45,startSrc="drop",maxLv=300,cap=1375,magMax=0,xpTune=3.34,mode="melee",name="Terraprisma",hpsSrc="family",unsupported=true}
W["YakushimaBlade003_2"]={t="Sword",hps=103.4,proj=1,base=100,mag=0,tier="T4",start=45,startSrc="drop",maxLv=300,cap=1604,magMax=0,xpTune=3.34,mode="melee",name="Terraprisma",hpsSrc="meas",unsupported=true}
W["YakushimaBlade003_3"]={t="Sword",hps=103.4,proj=1,base=110,mag=0,tier="T4",start=45,startSrc="drop",maxLv=300,cap=1833,magMax=0,xpTune=3.34,mode="melee",name="Terraprisma",hpsSrc="family",unsupported=true}
W["YakushimaBlade003_4"]={t="Sword",hps=103.4,proj=1,base=125,mag=0,tier="T4",start=45,startSrc="drop",maxLv=300,cap=2062,magMax=0,xpTune=3.34,mode="melee",name="Terraprisma",hpsSrc="family",unsupported=true}
W["YakushimaBlade003_5"]={t="Sword",hps=103.4,proj=1,base=150,mag=0,tier="T4",start=45,startSrc="drop",maxLv=300,cap=2292,magMax=0,xpTune=3.34,mode="melee",name="Terraprisma",hpsSrc="family",unsupported=true}
W["YakushimaBlade004"]={t="Sword",hps=2.98,proj=1,base=360,mag=0,tier="T4",start=45,startSrc="drop",maxLv=300,cap=1375,magMax=0,mode="melee",name="Excalibur",hpsSrc="family",unsupported=true}
W["YakushimaBlade004_2"]={t="Sword",hps=2.98,proj=1,base=396,mag=0,tier="T4",start=45,startSrc="drop",maxLv=300,cap=1604,magMax=0,mode="melee",name="Excalibur",hpsSrc="family",unsupported=true}
W["YakushimaBlade004_3"]={t="Sword",hps=2.98,proj=1,base=432,mag=0,tier="T4",start=45,startSrc="drop",maxLv=300,cap=1833,magMax=0,mode="melee",name="Excalibur",hpsSrc="family",unsupported=true}
W["YakushimaBlade004_4"]={t="Sword",hps=2.98,proj=1,base=468,mag=0,tier="T4",start=45,startSrc="drop",maxLv=300,cap=2062,magMax=0,mode="melee",name="Excalibur",hpsSrc="meas",unsupported=true}
W["YakushimaBlade004_5"]={t="Sword",hps=2.98,proj=1,base=540,mag=0,tier="T4",start=45,startSrc="drop",maxLv=300,cap=2292,magMax=0,mode="melee",name="Excalibur",hpsSrc="family",unsupported=true}
W["YakushimaBlade005"]={t="Sword",hps=1.4,proj=1,base=222,mag=0,tier="T5",start=55,startSrc="drop",maxLv=400,cap=1353,magMax=0,mode="melee",name="Legendary Meowmere",hpsSrc="est",unsupported=true}
W["YakushimaGun001"]={t="Handgun",hps=11.12,proj=1,base=300,mag=0,tier="T4",start=45,startSrc="drop",maxLv=300,cap=859,magMax=0,mode="auto",name="Vortex Beater",hpsSrc="family",unsupported=true}
W["YakushimaGun001_2"]={t="Handgun",hps=11.12,proj=1,base=330,mag=0,tier="T4",start=45,startSrc="drop",maxLv=300,cap=1002,magMax=0,mode="auto",name="Vortex Beater",hpsSrc="meas",unsupported=true}
W["YakushimaGun001_3"]={t="Handgun",hps=11.12,proj=1,base=360,mag=0,tier="T4",start=45,startSrc="drop",maxLv=300,cap=1146,magMax=0,mode="auto",name="Vortex Beater",hpsSrc="family",unsupported=true}
W["YakushimaGun001_4"]={t="Handgun",hps=11.12,proj=1,base=390,mag=0,tier="T4",start=45,startSrc="drop",maxLv=300,cap=1289,magMax=0,mode="auto",name="Vortex Beater",hpsSrc="family",unsupported=true}
W["YakushimaGun001_5"]={t="Handgun",hps=11.12,proj=1,base=450,mag=0,tier="T4",start=45,startSrc="drop",maxLv=300,cap=1432,magMax=0,mode="auto",name="Vortex Beater",hpsSrc="family",unsupported=true}
W["YakushimaLantern001"]={t="Melee",hps=4.7,proj=3,base=50,mag=0,tier="T4",start=45,startSrc="drop",maxLv=300,cap=859,magMax=0,mode="melee",name="Nightglow",hpsSrc="meas",unsupported=true}
W["YakushimaLantern001_2"]={t="Melee",hps=4.7,proj=3,base=60,mag=0,tier="T4",start=45,startSrc="drop",maxLv=300,cap=1002,magMax=0,mode="melee",name="Nightglow",hpsSrc="family",unsupported=true}
W["YakushimaLantern001_3"]={t="Melee",hps=4.7,proj=3,base=70,mag=0,tier="T4",start=45,startSrc="drop",maxLv=300,cap=1146,magMax=0,mode="melee",name="Nightglow",hpsSrc="family",unsupported=true}
W["YakushimaLantern001_4"]={t="Melee",hps=4.7,proj=3,base=80,mag=0,tier="T4",start=45,startSrc="drop",maxLv=300,cap=1289,magMax=0,mode="melee",name="Nightglow",hpsSrc="family",unsupported=true}
W["YakushimaLantern001_5"]={t="Melee",hps=4.7,proj=3,base=100,mag=0,tier="T4",start=45,startSrc="drop",maxLv=300,cap=1432,magMax=0,mode="melee",name="Nightglow",hpsSrc="family",unsupported=true}
return M
