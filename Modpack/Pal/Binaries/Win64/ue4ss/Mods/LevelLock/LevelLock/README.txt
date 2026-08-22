Level Lock

Caps your player level based on your tower boss progression. You can't level past the cap until you beat the next tower, forcing you to actually explore and gear up instead of accidentally out-leveling the whole game.

Any XP earned while capped is lost by default - or banked and paid back later if you turn on Rested XP (see below). Once you clear the next tower, the cap goes up and leveling resumes normally. By default only your player is capped; you can optionally cap your Pals too - party Pals and/or base-camp workers - at the same tower gate (see Configuration). Pal levels are never lowered, only held.
Level Caps (Palworld 1.0 - 9 towers, game max level 80)

    Tower 1 - Zoe & Grizzbolt (Rayne Syndicate) -> Cap: 15

    Tower 2 - Lily & Lyleen (Free Pal Alliance) -> Cap: 30

    Tower 3 - Axel & Orserk (Brothers of the Eternal Pyre) -> Cap: 45

    Tower 4 - Marcus & Faleris (PIDF) -> Cap: 50

    Tower 5 - Victor & Shadowbeak (PAL Genetic Research) -> Cap: 55

    Tower 6 - Saya & Selyne -> Cap: 62

    Tower 7 - Bjorn & Bastigor -> Cap: 68

    Tower 8 - Auri & Shaolong -> Cap: 74

    Tower 9 - Zenara & Astralym (World Tree) -> Cap: 80

All caps can be changed in Scripts/config.lua.
Requirements

    UE4SS v3.0.1 or newer

    https://github.com/UE4SS-RE/RE-UE4SS/releases

Installation

    Drop UE4SS into Palworld/Pal/Binaries/Win64/.

    Drop the LevelLock folder into Pal/Binaries/Win64/Mods/.

    Boot the game. You'll get an in-game message confirming it's working.

Note: The folder includes an enabled.txt so UE4SS should load it automatically. If you prefer the manual way, you can delete that and add LevelLock : 1 to your mods.txt instead.
Multiplayer / Dedicated Servers

Install on the host or dedicated server only. XP and tower progress are server-authoritative, so joining players don't need to install anything.

You can swap between two progression modes in the config (PerPlayerProgress):

    Shared World Cap (Default): When anyone kills a tower boss, the cap raises for everyone on the server.

    Per-Player: Everyone tracks their own caps. You get credit for a tower only if you actually take part in the fight (the mod uses the game's own participant list, so there's no standing-in-the-right-spot guesswork). If you sit out, your cap won't budge. Great for groups who actually want to earn their progression.

Co-op (Host & Play)

Just install UE4SS and the mod on the host's machine. Works out of the box.
Dedicated Servers

Install UE4SS and the mod next to the server executable (PalServer-Win64-Shipping.exe), NOT your game client.

    Important: Getting UE4SS to run properly on a dedicated server can be a headache depending on your hosting environment. That is entirely outside the scope of this mod. If your server already runs UE4SS fine, this mod will work. If it doesn't, fix your UE4SS setup first.

Configuration (Scripts/config.lua)

    Tower1_Cap to Tower9_Cap: Change the max levels to whatever you want.

    TowersAlreadyCleared: For adding this to an existing save. If the mod doesn't find a save file for your world yet, it assumes you've already beaten this many towers (0-9) so you don't get locked backwards. Once the mod creates its own save data, this setting is ignored.

    PerPlayerProgress: false for shared world cap, true for individual progression.

    LockPartyPals: false by default. Set true to also cap the Pals in your party (they gain combat XP) at the same tower gate.

    LockBasePals: false by default. Set true to also cap Pals assigned to base camps (they gain work XP).

    BaseCapPolicy: per-player mode only. A base camp is shared by the guild, so when members have different caps this decides which one a base Pal obeys: "highest" (default, never holds the base back), "lowest" (strictest), or "off" (don't cap base Pals in per-player mode).

    EnableNotifications: Toggles the in-game chat messages.

    HardMode: Off by default. Adds the six raid bosses as gates of their own - see the Hard Mode section below. Hard1_Cap to Hard15_Cap set that ladder's caps.

    LockSphereTier: Off by default. Stops you using Pal Spheres your level hasn't unlocked - see the Sphere Tier Lock section below.

    Debug: Off by default. Turn this on only if you're troubleshooting or want to send logs for a bug report - it writes verbose output to UE4SS.log and binds the F9 key to print your current level, cap, and cleared towers.

Rested XP (optional, off by default)

Set RestedXp = true and the XP the cap would have thrown away is banked instead, then paid back as a bonus on top of what you earn once the cap lifts. Banking is 1:1, so the bank can never hand back more than the cap took from you - it cannot make you level faster than playing without the mod. RestXpPayout (default 100, range 10-200) only controls how quickly the bank drains: at 100, earning 10 XP pays 20; at 200 it pays 30. Your balance is stored with your tower progress and survives restarts.

Hard Mode (optional, off by default)

Set HardMode = true and the nine tower gates become fifteen: the six raid bosses are added as gates of their own, interleaved among the towers. Every one of them has to be beaten to keep progressing, and the caps are tighter than normal mode's the whole way up.

    Cap 15 -> Tower 1 (Zoe)          Cap 25 -> Tower 2 (Lily)
    Cap 35 -> Tower 3 (Axel)         Cap 45 -> RAID: Bellanoir
    Cap 48 -> Tower 4 (Marcus)       Cap 52 -> RAID: Bellanoir Libero
    Cap 55 -> Tower 5 (Victor)       Cap 58 -> RAID: Moon Lord
    Cap 62 -> Tower 6 (Saya)         Cap 65 -> RAID: Blazamut Ryu
    Cap 68 -> Tower 7 (Bjorn)        Cap 71 -> RAID: Xenolord
    Cap 74 -> Tower 8 (Auri)         Cap 76 -> RAID: Hartalis
    Cap 80 -> Tower 9 (Zenara)

Each cap is what you're limited to while that gate is still standing. Raid gates leave you 6 to 10 levels above the boss, because a gate you can't out-level is a dead end rather than a challenge. All fifteen are editable as Hard1_Cap to Hard15_Cap.

This applies to every world you load, not one. An existing save keeps its tower clears, but expect your cap to DROP when you switch it on, because the raid gates now sit between towers you've already beaten - a save with six towers down lands at cap 45 and owes Bellanoir. Turning it back off restores the old cap exactly, and raid clears are remembered meanwhile, so you can switch back and forth without losing anything.

The "ultra" version of a raid boss counts for the same gate as the normal one, and killing a piece of Moon Lord doesn't count - only the boss itself.

Sphere Tier Lock (optional, off by default)

Set LockSphereTier = true and you can't use a Pal Sphere your level hasn't unlocked yet. Throw an Ancient sphere at level 15 and it bounces off, with the game's own "this sphere is too weak" message, and the sphere is used up the same way a failed catch always uses one.

    Pal Sphere 2    Hyper 27    Ultimate 51    Ancient 74
    Mega 14         Ultra 35    Exotic 58
    Giga 20         Legendary 44    Sol 67

These are the game's own technology requirements, so this never stops you using a sphere you could have crafted yourself - it stops you skipping ahead with spheres you found, were given, or bought. It reads your LEVEL, not your tower cap, because that's what the recipe is tied to.

Worth knowing: the catch-chance shown while aiming is worked out before the sphere leaves your hand, so it can show a high number - even 100% - on a throw this blocks. You get a chat message saying so, rate-limited so quick throws don't spam you. Turning EnableNotifications off silences it; the block still works.

If the Game Crashes

Relaunch the game and check UE4SS.log for a line starting with "[LevelLock] WARNING: the previous session ended while...". If it's there, the crash happened inside this mod - please include that exact line in your bug report. If there's no warning, the crash almost certainly wasn't Level Lock. (This works via a tiny LevelLock-sentinel.txt file the mod maintains automatically alongside the progress file - you never need to touch it.)

How Progress is Saved

Boss kills are tracked live and saved to LevelLock-progress.txt, keyed by either your worldGUID or worldGUID|playerUId depending on your mode. It survives server restarts and handles multiple worlds/players independently. It's just a plain text file, so if something ever desyncs, you can easily open it and edit the numbers manually.

The file goes wherever the game keeps its own saves, which is not the same place on every install:

    Dedicated server    <your server folder>\Pal\Saved\  - the folder that holds SaveGames
    Playing normally    %LOCALAPPDATA%\Pal\Saved\        - where the game puts SaveGames

If you're not sure which one you got, the mod prints the full path to UE4SS.log at startup: look for a line reading "[LevelLock] Progress file: ...". Want it somewhere else - a backup folder, a volume your host actually exposes? Set ProgressDir in config.lua to a folder that already exists and it goes there instead.

Server owners: earlier versions always wrote to %LOCALAPPDATA%, which on a Linux host is buried inside the Proton prefix and on a rented panel is often not exposed at all. Your progress is moved into the server folder on first launch and the old copy is left where it was, as a backup.

The file sits next to the saves rather than inside the mod folder because updating the mod - a Steam Workshop update in particular - replaces the mod folder and everything in it. Upgrading from 2.1.6 or earlier copies your existing progress across on first launch the same way. Note that config.lua cannot be moved like this, since you edit it directly: keep a copy of your settings before updating.
