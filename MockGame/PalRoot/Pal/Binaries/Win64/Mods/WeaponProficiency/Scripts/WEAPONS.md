# Living Arsenal — which weapons are integrated

Living Arsenal only changes a weapon when it knows how fast that weapon actually shoots.
That firing rate is measured in game, one weapon at a time, and it is what the damage and
XP curves are built from. A weapon whose rate has never been measured is **left completely
alone** — it behaves exactly as it does in vanilla Palworld.

This file is generated from the mod's own data, so it always matches what the mod will do.

- **23 weapons integrated** (96 rarity variants)
- **70 weapons not yet integrated** (185 variants) — left vanilla
- 7 weapons from other mods — off unless you ask for them

---

## Integrated weapons

These have a measured rate and a built curve. Nothing to switch on.

### AssaultRifle

- **Assault Rifle** — same weapon, another rarity of a measured one, measured in game (5 rarities)
- **Makeshift Assault Rifle** — same weapon, another rarity of a measured one, measured in game (5 rarities)
- **Semi-Auto Rifle** — same weapon, another rarity of a measured one, measured in game (5 rarities)

### Bow

- **Compound Bow** — same weapon, another rarity of a measured one, measured in game (5 rarities)
- **Old Bow** — measured in game (5 rarities)
- **Three Shot Bow** — measured in game

### BowGun

- **Crossbow** — same weapon, another rarity of a measured one, measured in game (5 rarities)

### FlameThrower

- **Flamethrower** — same weapon, another rarity of a measured one, measured in game (5 rarities)

### Handgun

- **Ballistic Shield** — derived from a measured weapon of the same type
- **Boost Gun** — derived from a measured weapon of the same type (2 rarities)
- **Handgun** — measured in game (5 rarities)
- **Makeshift Handgun** — same weapon, another rarity of a measured one, measured in game (5 rarities)
- **Megaboost Gun** — derived from a measured weapon of the same type
- **Old Revolver** — measured in game (5 rarities)

### Katana

- **Katana** — measured (5 rarities)

### Shotgun

- **Double-Barreled Shotgun** — same weapon, another rarity of a measured one, measured in game (5 rarities)
- **Makeshift Shotgun** — same weapon, another rarity of a measured one, measured in game (5 rarities)
- **Semi-Auto Shotgun** — same weapon, another rarity of a measured one, measured in game (5 rarities)

### SniperRifle

- **Musket** — same weapon, another rarity of a measured one, measured in game (5 rarities)
- **Single-Shot Rifle** — measured in game, same weapon, another rarity of a measured one (5 rarities)

### SubmachineGun

- **Makeshift SMG** — measured in game (5 rarities)
- **SMG** — same weapon, another rarity of a measured one, measured in game (5 rarities)

### Sword

- **Primitive Sword** — measured in game

---

## Not yet integrated — and how to turn one on

These are left vanilla because their firing rate has never been measured. The mod will say so
in the log the first time you use one:

```
UNTESTED Musket (Musket) left vanilla -- damage curve not measured (hpsSrc=est).
```

You can switch them on yourself. Edit `Mods/shared/WeaponProficiency_user.lua` and add any of:

```lua
return {
  -- 1. one specific weapon, by the id the log printed
  untestedAllow = { Musket = true },

  -- 2. every weapon of a type (the headings in this file)
  untestedAllowTypes = { SniperRifle = true },

  -- 3. all of them at once
  skipUntestedWeapons = false,
}
```

**What you are trading.** An unmeasured weapon uses an estimated rate, so its damage and XP
curve is a guess. It will work, but it may be too strong or too weak until the rate is measured
properly. That is the only reason these are off by default.

### Want to measure one properly?

Set `measureHps = true` in the same file and fire the weapon **three full magazines back to
back**, without pausing to re-aim. The log records every shot:

```
[Arsenal][SHOT] DoubleBarrelShotgun_2
```

The rate is: shots in the first two magazines, divided by the time from the first shot of
magazine 1 to the first shot of magazine 3. The third magazine is only there to close the
second cycle — its shots are not counted. Reloading time is part of the rate, deliberately.

Send that number along with the weapon id and it can be added to the shipped data.

### AssaultRifle (3)

Heavy Assault Rifle, Overheat Rifle, Plasma Rifle

### Axe (5)

Axe4, Metal Axe, Pal Metal Axe, Refined Metal Axe, Stone Axe

### Bow (6)

Advanced Bow, Fire Bow, Five Shot Bow, Mechanical Bow, Poison Bow, Recurve Bow

### Butcher (1)

Meat Cleaver

### DroneLauncher (1)

Drone Launcher

### GatlingGun (2)

Gatling Gun, Laser Gatling Gun

### Grenade (11)

Dark Grenade, Dragon Grenade, Frag Grenade, Frag Grenade Mk2, Grass Grenade, Ground Grenade, Ice Grenade, Incendiary Grenade, Shock Grenade, Throw Stone, Water Grenade

### GrenadeLauncher (2)

Grenade Launcher, Tactical Grenade Launcher

### Handgun (1)

Marksman Revolver

### LaserRifle (2)

Charge Rifle, Laser Rifle

### Melee (13)

Bat, Beegarde's Spear, Believer Fat Cane, Elizabee's Staff, Enhanced Lily's Spear, Hand-Held Torch, Lily's Spear, Metal Bat, Metal Spear, Refined Metal Spear, Stone Spear, Stun Baton, Wooden Club

### MissileLauncher (2)

Guided Missile Launcher, Multi Guided Missile Launcher

### Pickaxe (6)

Metal Pickaxe, Pal Metal Pickaxe, Pickaxe, Plasma Multicutter, Refined Metal Pickaxe, Stone Pickaxe

### RocketLauncher (5)

Beam Launcher, Meteor Launcher, Penguin Launcher, Plasma Cannon, Rocket Launcher

### Shotgun (5)

Beam Scatter, Core Eject Shotgun, Energy Shotgun, Prototype Shotgun, Pump-Action Shotgun

### SniperRifle (1)

Sniper Rifle

### SubmachineGun (1)

Combat SMG

### Sword (3)

Beam Sword, Laser Sword, Sword

---

## Weapons from other mods

Not part of the base game, so their stats cannot be verified at all. Off unless you ask:

```lua
return {
  applyUnsupported = true,                    -- all of them
  unsupportedAllow = { SomeWeaponId = true }, -- or just one
}
```

Meowmere, Terra Blade, Terraprisma, Excalibur, Legendary Meowmere, Vortex Beater, Nightglow
