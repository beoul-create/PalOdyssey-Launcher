# ⚡ PalOdyssey Launcher 2.0

[![Platform: Windows](https://img.shields.io/badge/Platform-Windows%2010%2F11-0078D6?style=for-the-badge&logo=windows)](https://microsoft.com)
[![Framework: .NET 8 WPF](https://img.shields.io/badge/Framework-.NET%208%20WPF-512BD4?style=for-the-badge&logo=dotnet)](https://dotnet.microsoft.com)
[![Unreal Engine: 5.1](https://img.shields.io/badge/Game-Palworld%20(UE%205.1)-313131?style=for-the-badge&logo=unrealengine)](https://unrealengine.com)
[![Modpack: UE4SS 3.0.1](https://img.shields.io/badge/Modpack-UE4SS%203.0.1%20Integrated-FF6F00?style=for-the-badge)](https://github.com/UE4SS-RE/RE-UE4SS)
[![Release: v2.0.0](https://img.shields.io/badge/Release-v2.0.0--Astral-00E5FF?style=for-the-badge)](https://github.com/beoul-create/PalOdyssey-Launcher/releases)

**PalOdyssey Launcher 2.0** is an official custom game client, modpack auto-updater, server companion, and system optimizer built for **Palworld**. It automates game directory discovery, keeps your client synchronized with the server's 312+ mod assets, provides live server diagnostics, and integrates remote server controls.

---

## ⚡ Quick Start: How to Play

Getting into the PalOdyssey realm takes less than 60 seconds:

1. **Download the Launcher**:
   * Grab the latest **[PalOdyssey Launcher Release (`.zip`)](https://github.com/beoul-create/PalOdyssey-Launcher/releases)**.
   * Extract the `.zip` anywhere on your PC.
2. **Launch `PalLauncher.exe`**:
   * Double-click **`PalLauncher.exe`**.
   * The launcher will start immediately and automatically detect your Palworld Steam installation directory.
3. **Configure Settings (Optional)**:
   * Click the **⚙ (Gear)** icon in the top-right title bar to open the **Settings Flyout** if you wish to adjust the remote manifest URL, server API endpoint, sound effects, or Discord Rich Presence.
4. **Play Now**:
   * Click the glowing **`PLAY NOW`** button on the bottom dock. The launcher performs real-time SHA-256 integrity verification, downloads missing or updated mod files, and launches directly into Palworld!

---

## 🌟 Actual Launcher Features & Architecture

### 🚀 1. Hardware-Accelerated Glassmorphic UI
* **Custom WindowChrome Design**: Zero window-dragging lag, smooth framerates, custom title bar with minimize/close buttons, and subtle audio cues on hover and click.
* **Cinematic Ambient Video Background**: Features an embedded ambient looping background video (`background_loop.mp4`) with glassmorphic blur overlays and cyan/indigo glow auras.

### 🔄 2. High-Speed SHA-256 Delta Auto-Updater (312 Mod Files)
* **Zero Manual Installation**: UE4SS 3.0.1 binaries, Lua scripts, and client `.pak` files are managed and installed automatically.
* **Cryptographic Delta Verification**: Uses local SHA-256 hash caching (`cache.json`) to verify files in milliseconds and only downloads new or changed files from GitHub's raw CDN.
* **Live Bandwidth & Progress Ticker**: Real-time progress bar with percentage readout, download speed indicator (`MB/s`), and active file ticker.

### 🌐 3. Live Server Beacon & Ping Diagnostics
* **Realm Status Beacon**: Real-time server state monitor (`ONLINE`, `CHECKING...`, or `OFFLINE`) with color-coded beacon badges.
* **Low-Latency Ping Indicator**: Measures direct round-trip latency to the dedicated server (`palodyssey.duckdns.org`).
* **Liveboard Fallback Integration**: Reads local server state files (`liveboard_state.json`) when operating on the host machine.

### 🎛️ 4. Remote Server Controller Tray
* **Built-in Server Management**: Directly monitor and toggle the dedicated server from the launcher dashboard via the **Server Controller Tray**.
* **Remote Management Daemon Client**: Communicates securely with the local or remote daemon service using configurable API endpoints and admin secret keys.

### 🎮 5. Discord Rich Presence & Community Link
* **Live Discord Activity**: Displays live rich presence on your Discord profile while preparing or playing in the PalOdyssey realm.
* **1-Click Community Discord**: Quick-access Discord button in the title bar to connect with other players.

### 📁 6. Automatic Steam Detection & Fallback Selector
* **Smart Steam Registry Scanner**: Automatically queries Windows Registry (`HKCU\Software\Valve\Steam`) and parses `libraryfolders.vdf` to find Palworld across all SSDs and HDDs.
* **Manual Directory Browser**: Allows manual game folder selection if using custom drive mappings.

---

## 📦 What's Inside the Modpack?

When launching with PalOdyssey, you receive an expertly tuned suite of **312 mod files**:

| Mod / System | Description |
| :--- | :--- |
| 🧬 **Azomer's Passive Skill Expansion (APSE) & ChazzBuffs** | Expanded passive skill matrices, custom items, Silvegis boss spawns, and partner skill rebalancing. |
| 🐣 **Custom Subspecies Breeding** | Expanded Pal breeding combinations and custom egg item parameters. |
| ⚡ **FastConnect Integration** | Bypasses title menu connection delays for instant world entry. |
| 🎯 **CS2 Custom Crosshairs & Clean HUD** | Precision dynamic reticles (Dot, Crosshair, Circle-Dot) with watermark removal. |
| 💰 **In-Game Economy & Shop System** | Player marketplace, currency system, and custom merchant tables. |
| 🏰 **Guild Building Limits** | Fair base construction quotas and automated anti-bloat limit enforcement. |
| 👑 **World Boss Aura & SAO Death Mechanics** | Dynamic elemental aura effects on world bosses and dramatic combat indicators. |
| ✨ **Shining Luckies Indicator** | Shimmering particle trails and beacons for rare/lucky Pals. |
| 🐾 **Stuck Pal Rescuer** | Detects base worker Pals caught in collision or terrain geometry and automatically repositions them. |
| 🌄 **PalClearVision Visual Suite** | Removes muddy fog filters, enhances night lighting, corrects ultra-wide (21:9 / 32:9) HUDs, and boosts LOD draw distance. |
| ⚔️ **Weapon Proficiency & Mastery** | Weapon mastery progression, durability scaling, and combat bonuses. |
| 🧹 **RAM Trim & Borealis Engine** | Memory compacting engine and native DWMAPI hooks for smooth frametimes. |

---

## ⚙️ In-Game Mod Menu (`ESC → Mod Options`)

Customize mod options in real-time while playing:

1. Press **`ESC` ➔ Mod Options** anywhere in-game.
2. Configure settings on the fly:
   * **HUD & Crosshair**: Select reticle styles, colors, and toggle UI watermarks.
   * **Visual Clarity**: Toggle distance fog, night light radiance, and ultra-wide HUD correction.
   * **Stuck Pal Rescuer**: Adjust scan interval and teleport sensitivity.
   * **Economy & Shop**: View prices, inventory carry weight modifiers, and balance.
   * **Memory Management**: Configure RAM sweep frequency and texture pool allocations.

---

## ❓ FAQ & Troubleshooting

#### Q: Do I need to install UE4SS or extra dependencies manually?
> **A:** No. The launcher bundles the entire UE4SS 3.0.1 runtime and all 312 mod dependencies automatically.

#### Q: How do I select my game directory if Steam is on another drive?
> **A:** On the right side of the dashboard, click the **Browse...** button under *GAME DIRECTORY* and select your root Palworld folder (e.g. `D:\SteamLibrary\steamapps\common\Palworld`).

#### Q: How do I change the remote server or manifest URL?
> **A:** Click the **⚙ (Gear)** icon in the top-right title bar to open the Settings flyout, where you can configure the Remote Manifest URL, Server API endpoint, and Admin Secret Key.

---

<div align="center">
  <sub>Built with ❤️ for the <strong>PalOdyssey Community</strong>.</sub>
</div>