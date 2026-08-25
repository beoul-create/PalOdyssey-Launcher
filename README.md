# ⚡ PalOdyssey Launcher

[![Platform: Windows](https://img.shields.io/badge/Platform-Windows%2010%2F11-0078D6?style=for-the-badge&logo=windows)](https://microsoft.com)
[![Framework: .NET 8 WPF](https://img.shields.io/badge/Framework-.NET%208%20WPF-512BD4?style=for-the-badge&logo=dotnet)](https://dotnet.microsoft.com)
[![Unreal Engine: 5.1](https://img.shields.io/badge/Game-Palworld%20(UE%205.1)-313131?style=for-the-badge&logo=unrealengine)](https://unrealengine.com)
[![Modding: UE4SS 3.0.1](https://img.shields.io/badge/Modpack-UE4SS%203.0.1%20Integrated-FF6F00?style=for-the-badge)](https://github.com/UE4SS-RE/RE-UE4SS)

**PalOdyssey Launcher** is a custom 1-click game launcher, auto-updater, server companion, and resource optimizer built specifically for **Palworld**. It automatically manages, installs, and tunes your modpack so you can jump straight into the realm with peak framerates, low memory footprint, crystal-clear visuals, and zero manual file copying.

---

## ⚡ Quick Start: How to Play

Getting started takes less than 60 seconds:

1. **Download the Launcher**:
   - Download **`PalOdyssey-Launcher-v2.0.0.zip`** from this repository (or from [Releases](https://github.com/beoul-create/PalOdyssey-Launcher/releases)).
   - Extract the zip folder anywhere on your PC.
2. **Launch `PalLauncher.exe`**:
   - Double-click **`PalLauncher.exe`** inside the extracted folder.
   - The launcher will start immediately and automatically detect your Steam Palworld installation.
3. **1-Click Auto-Calibrate**:
   - Go to the **Launch Settings** tab ➔ Click **`⚡ AUTO-CALIBRATE & OPTIMIZE RIG`** to automatically configure the best performance settings for your hardware.
4. **Launch Expedition**:
   - Click the glowing **`Launch Expedition`** button on the Dashboard. The launcher automatically verifies mod integrity, purges stale logs, applies updates, and launches your game!

---

## 🌟 What the Launcher Has

### 🚀 1. Hardware Auto-Calibrator (`Auto-Optimize Rig`)
- **Instant System Benchmark**: Probes your CPU cores, RAM, and GPU to determine your system's ideal performance tier (**Efficiency APU**, **Balanced Gaming**, or **Ultra Enthusiast**).
- **Auto-Configured Startup Flags**: Automatically applies multithreading (`-USEALLAVAILABLECORES`, `-useperfthreads`), memory allocators (`-malloc=system`), and DirectX settings tailored specifically for your hardware.
- **Zero Stutter Engine**: Tunes background worker threads and texture streaming so you get maximum FPS and smooth frametimes.

### 🔋 2. Resource Consumption & Memory Optimizer
- **Background Throttling (`t.UnfocusedMaxFPS=30`)**: Automatically lowers framerate to 30 FPS when Alt-Tabbed or minimized, slashing idle GPU and CPU usage by **~70%**.
- **Texture Streaming & VRAM Bounds**: Enforces dynamic texture streaming pool limits (`r.Streaming.PoolSize=2560`), saving **2GB to 4GB of RAM/VRAM** and eliminating memory leaks during long play sessions.
- **Aggressive Garbage Collection**: Purges dead entity allocations every 45 seconds with amortized frame slices to prevent micro-stutter spikes.
- **Automated Crash Trace Purging**: Sweeps stale error dumps before startup to ensure a clean, popup-free launch every time.

### 🌐 3. Real-Time Server Liveboard & Roster
- **Live Player List**: Displays currently connected player usernames, levels, ping, and server capacity with a fast 3-second live refresh.
- **Server Health & Metrics**: Displays live server status, port status, and memory stats directly on the launcher dashboard.

### 🔄 4. Seamless Modpack Auto-Updater
- **Zero Manual Copying**: Never worry about extracting `.zip` files or copying files into `~mods` folders.
- **SHA-256 Checksum Verification**: Automatically detects outdated or corrupted files and updates them in seconds with streaming progress bars.
- **Mod Manager Tab**: View all installed mods, check their verification status, and toggle individual mods on or off.

### 🎮 5. Discord Rich Presence
- **Live Status Badges**: Shows your friends when you are preparing in the launcher or actively playing in the realm (`⚡ PalOdyssey Expedition • Exploring Realm • Active Mods`).
- **Custom Game Branding**: Connects directly to Discord with high-resolution activity icons and live session timers.

### 🎨 6. Futuristic Cyberpunk UI
- **Glassmorphic Theme**: Sleek dark-mode aesthetic with neon cyan and electric violet glow accents.
- **Real-Time Activity Console**: Built-in colored logging terminal (`Info`, `Success`, `Warning`, `Error`) with 1-click log export for quick troubleshooting.

---

## 📦 What's Inside the Modpack?

When you launch through PalOdyssey, you get an out-of-the-box enhanced Palworld experience:

* 🧬 **Azomer's Passive Skill Expansion (APSE) & ChazzBuffs**:
  - Deeply expands passive skills, custom items, Silvegis boss spawns, and Flames of Palpagos skill matrices loaded through PalSchema.
  - Full balance buffs and enhanced partner skills for Lunaris, Mossanda, Xenogard, Menasting, LegendDeer, Pupperai, Splatterina, and more.
* 📦 **Palbox Search Plus & Quick Filter**: Adds real-time text searching (by Name, Element, or Passive Skill) and 1-click sorting directly into the Palbox storage grid.
* 🖥️ **Clean HUD & Pristine Reticles**: Permanently removes version and build watermarks from the viewport, providing high-contrast precision aim reticles (Dot, Minimal Crosshair, Circle-Dot).
* ✨ **Shining Luckies Visual Indicator**: Adds a magical shimmer and star-glint particle aura to Lucky / Rare Pals so they stand out in dense foliage and nighttime biomes.
* 🐾 **Stuck Pal Rescuer**: Automatically rescues base camp Pals that get stuck in building geometry or pathfinding loops and teleports them back to the Palbox so your base workers never starve or bug out.
* 🌄 **PalClearVision Visual & Rendering Suite**:
  - **Atmospheric Clarity**: Removes washed-out grey fog veil, chromatic aberration, and film grain for razor-sharp visuals.
  - **Better Night Light & Atmosphere**: Luminous, atmospheric nighttime moonlight and campfire radiance without washed-out grays.
  - **Enhanced LOD & Draw Distance**: Extends Level-of-Detail transition distance to eliminate mesh pop-in while flying.
  - **Ultra-Wide 21:9 & 32:9 HUD Fix**: Eliminates FOV warping and HUD element stretching on widescreen monitors.
  - **Async Texture Streaming**: Pre-allocates texture mips during zone transitions to eliminate micro-stutters.
* 📥 **Quick Deposit (`G` Key)**: Press **`G`** inside your base to automatically deposit all matching items from your inventory into nearby storage containers.
* ⚔️ **Weapon Proficiency & Mastery**: Earn weapon experience as you fight to level up damage bonuses and increase weapon durability.
* 👑 **Catch All Predator Bosses**: Unlocks capture mechanics for legendary predator boss encounters.
* 🧹 **RAM Trim & Working Set Sweep**: Native memory compacting engine that regularly cleans accumulated memory bloat during extended sessions.
* 📸 **Cinematic FreeCam & Super-Res Photo Studio**:
  - **`F8` — 360° Detached FreeCam**: Detach the camera from the player pawn and fly anywhere in 3D space to frame cinematic shots.
  - **`F9` — Time Freeze / Slow-Motion**: Pause world time mid-action or mid-jump to set up action shots.
  - **`F10` — Clean Viewport / Hide HUD**: 1-click toggle to remove all UI overlays.
  - **`F11` — Super-Resolution Screenshot**: Captures uncompressed supersampled screenshots straight to disk.

---

## ⚙️ In-Game Mod Menu (`ESC → Mod Options`)

You can customize mod settings live while playing without restarting your game:

1. Press **`ESC` ➔ Mod Options** anywhere in-game.
2. Adjust your settings:
   - **Cinematic Studio**: View and configure hotkeys for FreeCam (`F8`), Time Freeze (`F9`), Clean HUD (`F10`), and High-Res Capture (`F11`).
   - **Palbox Search**: Toggle text search, element filtering, passive skill queries, and quick sort.
   - **HUD & Reticles**: Toggle watermark removal, compass simplification, and choose between Dot, Minimal Crosshair, or Circle-Dot aim reticles with custom color contrast.
   - **Shining Luckies**: Adjust shimmer radiance intensity (Subtle, Moderate, Vibrant) and star-glint trails.
   - **Visual Clarity & Lighting**: Toggle fog removal, better night light, LOD draw distance, ultrawide fixes, and async texture streaming.
   - **Stuck Pal Rescuer**: Change scan frequency or stuck timeout threshold.
   - **Quick Deposit**: Change deposit hotkey (default `G`) and chest scan radius.
   - **Palworld Tuner**: Adjust inventory carry weight multipliers.
   - **Weapon Proficiency**: Toggle damage and durability scaling.
   - **Performance & RAM**: Configure memory trim intervals and garbage collection frequency.

---

## 🖥️ Recommended Hardware Presets

| Your Hardware | Recommended Preset | Target Performance | What Auto-Calibrate Applies |
| :--- | :--- | :--- | :--- |
| **Integrated Graphics / APU / 8GB RAM** (Intel Iris, AMD Vega, Steam Deck) | **Efficiency Max** | 40 – 60 FPS (FSR/DLSS Perf) | `-lowmemory -USEALLAVAILABLECORES -dx11`<br>Lightweight particle budgets & fast GC. |
| **Mid-Range Gaming PC / 16GB RAM** (GTX 1660, RTX 2060 / 3060, RX 6600) | **Balanced Gaming** | 60 – 85 FPS (1080p/1440p) | `-malloc=system -useperfthreads -USEALLAVAILABLECORES -dx11`<br>System heap allocation & ultra-stable frametimes. |
| **High-End Enthusiast / 32GB+ RAM** (RTX 3080 / 4070 / 4080 / 4090) | **Ultra / Enthusiast** | 90 – 120+ FPS (1440p/4K) | `-malloc=system -useperfthreads -high -NoAsyncLoadingThread`<br>DX12 Async Compute & high task graph dispatch. |

---

## ❓ FAQ & Troubleshooting

#### Q: Do I need to manually install UE4SS or other mod loaders?
> **A:** No! The launcher bundles and installs the entire UE4SS 3.0.1 framework and all required mod files automatically.

#### Q: How do I change mod settings in-game?
> **A:** Press **`ESC` ➔ Mod Options** while in-game to open the mod menu.

#### Q: The game won't launch or says path not found?
> **A:** In the launcher, go to **Launch Settings**, click **Browse**, and select your Palworld install folder (e.g. `C:\SteamLibrary\steamapps\common\Palworld`).

#### Q: How do I share logs if I encounter an issue?
> **A:** Open the **Activity Logs** tab in the launcher and click **`Export Logs`** or **`Copy to Clipboard`**.

---

**Developed with ❤️ for the Palworld & PalOdyssey Community.**


