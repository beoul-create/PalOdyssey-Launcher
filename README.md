# ⚡ PalOdyssey Launcher 2.0

[![Platform: Windows](https://img.shields.io/badge/Platform-Windows%2010%2F11-0078D6?style=for-the-badge&logo=windows)](https://microsoft.com)
[![Framework: .NET 8 WPF](https://img.shields.io/badge/Framework-.NET%208%20WPF-512BD4?style=for-the-badge&logo=dotnet)](https://dotnet.microsoft.com)
[![Unreal Engine: 5.1](https://img.shields.io/badge/Game-Palworld%20(UE%205.1)-313131?style=for-the-badge&logo=unrealengine)](https://unrealengine.com)
[![Modpack: UE4SS 3.0.1](https://img.shields.io/badge/Modpack-UE4SS%203.0.1%20Integrated-FF6F00?style=for-the-badge)](https://github.com/UE4SS-RE/RE-UE4SS)
[![Release: v2.0.0](https://img.shields.io/badge/Release-v2.0.0--Astral-00E5FF?style=for-the-badge)](https://github.com/beoul-create/PalOdyssey-Launcher/releases)

**PalOdyssey Launcher 2.0** is an all-in-one high-performance game client, modpack auto-updater, server companion, and system optimizer built specifically for **Palworld**. It automates game launch calibration, keeps your client synchronized with the server's 312+ mod assets, tunes memory and texture streaming for zero stutter, and features integrated remote server controls.

---

## ⚡ Quick Start: How to Play

Getting into the PalOdyssey realm takes less than a minute:

1. **Download the Launcher**:
   * Grab the latest **[PalOdyssey Launcher Release (`.zip`)](https://github.com/beoul-create/PalOdyssey-Launcher/releases)**.
   * Extract the `.zip` anywhere on your PC.
2. **Launch `PalLauncher.exe`**:
   * Double-click **`PalLauncher.exe`**.
   * The launcher automatically detects your Palworld Steam installation directory.
3. **1-Click Auto-Calibrate**:
   * On the **Dashboard** or **Launch Settings** tab, click **`⚡ AUTO-CALIBRATE & OPTIMIZE RIG`** to configure the optimal hardware thread, memory, and graphics flags for your system.
4. **Launch Expedition**:
   * Click the glowing **`Launch Expedition`** button. The launcher performs real-time SHA-256 integrity verification, applies updates, cleans stale dumps, and launches directly into the world!

---

## 🌟 Key Launcher Features

### 🚀 1. Hardware Auto-Calibrator & Engine Optimization
* **Instant Rig Benchmark**: Automatically analyzes your CPU topology, GPU tier, and physical RAM to recommend the ideal preset (**Efficiency APU**, **Balanced Gaming**, or **Ultra Enthusiast**).
* **High-Performance Command-Line Flags**: Automatically configures system heap allocation (`-malloc=system`), worker thread dispatch (`-useperfthreads`, `-USEALLAVAILABLECORES`), and DirectX acceleration.
* **Hardware-Accelerated WindowChrome UI**: Modern WPF glassmorphic design with zero window dragging lag and high-refresh-rate rendering.

### 🔋 2. Memory Compactor & Crash Prevention
* **Palworld Borealis Engine & Native DWMAPI**: Enhanced engine hooks preventing out-of-memory crashes and micro-stuttering during long multiplayer sessions.
* **Background Idle Throttling (`t.UnfocusedMaxFPS=30`)**: Drops GPU/CPU usage by **~70%** when Alt-Tabbed or minimized.
* **Dynamic Texture Pool Bounds (`r.Streaming.PoolSize=2560`)**: Prevents VRAM exhaustion and mesh popping while exploring new islands.
* **Automated Log & Crash Sweep**: Cleans old crash dumps and temp logs on every launch to keep your install folder lean and healthy.

### 🌐 3. Real-Time Server Liveboard & Remote Management
* **Instant Roster & Status**: Displays connected players, ping, server latency, and server health directly on your dashboard with a 3-second live refresh.
* **Remote Management Daemon**: Built-in background daemon integration for automated Discord liveboards, server monitoring, and RCON controls.
* **FastConnect Direct-to-World**: Instant bypass connecting you directly into the PalOdyssey server without having to browse server lobbies.

### 🔄 4. Automated Modpack Sync (312 Verified Files)
* **Zero Manual Installation**: All mod files, UE4SS binaries, scripts, and pak mods are automatically downloaded and verified via high-speed GitHub raw endpoints.
* **SHA-256 Delta Verification**: Computes cryptographic hashes of local assets and downloads only updated or missing files.
* **Mod Manager UI**: Browse installed mods, verify integrity status, and toggle individual mods on or off directly from the launcher.

### 🎮 5. Discord Rich Presence
* **Live Status**: Displays rich presence on your Discord profile (`⚡ Exploring Realm • Level & Status • PalOdyssey Expedition`).
* **High-Res Assets**: Custom Discord activity icons and live session duration timers.

---

## 📦 What's Inside the Modpack?

When launching with PalOdyssey, you receive an expertly tuned suite of **312 mod files**:

| Mod / System | Description |
| :--- | :--- |
| 🧬 **Azomer's Passive Skill Expansion (APSE) & ChazzBuffs** | Deep skill matrices, custom items, Silvegis boss spawns, and rebalanced partner skills for all primary Pals. |
| 🐣 **Custom Subspecies Breeding** | Expanded breeding combinations and custom egg item parameters. |
| ⚡ **FastConnect Integration** | Bypasses title menu connection delays for instant world entry. |
| 🎯 **CS2 Custom Crosshairs & Clean HUD** | Precision dynamic reticles (Dot, Crosshair, Circle-Dot) with watermark removal. |
| 💰 **In-Game Economy & Shop System** | Player marketplace, currency system, and custom merchant tables. |
| 🏰 **Guild Building Limits** | Fair base construction quotas and automated anti-bloat limit enforcement. |
| 👑 **World Boss Aura & SAO Death Mechanics** | Dynamic elemental aura effects on world bosses and dramatic combat indicators. |
| ✨ **Shining Luckies Indicator** | Shimmering particle trails and beacons for rare/lucky Pals. |
| 🐾 **Stuck Pal Rescuer** | Detects base worker Pals caught in collision or terrain geometry and automatically repositions them. |
| 🌄 **PalClearVision Visual Suite** | Removes muddy fog filters, enhances night lighting, corrects ultra-wide (21:9 / 32:9) HUDs, and boosts LOD draw distance. |
| ⚔️ **Weapon Proficiency & Mastery** | Weapon mastery progression, durability scaling, and combat bonuses. |
| 🧹 **RAM Trim & Working Set Sweep** | Automatic background working-set memory compacting. |

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

## 🖥️ Recommended Hardware Presets

| Hardware Tier | Recommended Preset | Target FPS | What Auto-Calibrate Configures |
| :--- | :--- | :--- | :--- |
| **APU / Integrated / 8GB RAM** *(Steam Deck, AMD Vega, Intel Iris)* | **Efficiency Max** | 40 – 60 FPS | `-lowmemory -USEALLAVAILABLECORES -dx11`<br>Lightweight particle budget, aggressive GC. |
| **Mid-Range / 16GB RAM** *(RTX 2060/3060, RX 6600)* | **Balanced Gaming** | 60 – 85 FPS | `-malloc=system -useperfthreads -USEALLAVAILABLECORES -dx11`<br>System heap allocation, locked frametimes. |
| **Enthusiast / 32GB+ RAM** *(RTX 4070/4080/4090, RX 7900)* | **Ultra Enthusiast** | 90 – 144+ FPS | `-malloc=system -useperfthreads -high -NoAsyncLoadingThread`<br>DX12 Async Compute, max streaming cache. |

---

## ❓ FAQ & Troubleshooting

#### Q: Do I need to install UE4SS or extra dependencies manually?
> **A:** No. The launcher bundles the entire UE4SS 3.0.1 runtime and all 312 mod dependencies automatically.

#### Q: How do I select my game directory if Steam is on another drive?
> **A:** In the launcher, open **Launch Settings**, click **Browse**, and select your root Palworld folder (e.g. `D:\SteamLibrary\steamapps\common\Palworld`).

#### Q: How do I export logs for support?
> **A:** Go to the **Activity Logs** tab in the launcher and click **`Export Logs`** or **`Copy to Clipboard`**.

---

<div align="center">
  <sub>Built with ❤️ for the <strong>PalOdyssey Community</strong>.</sub>
</div>