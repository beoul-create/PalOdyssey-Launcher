# ⚡ PalOdyssey Launcher

[![Platform: Windows](https://img.shields.io/badge/Platform-Windows%2010%2F11-0078D6?style=for-the-badge&logo=windows)](https://microsoft.com)
[![Framework: .NET 8 WPF](https://img.shields.io/badge/Framework-.NET%208%20WPF-512BD4?style=for-the-badge&logo=dotnet)](https://dotnet.microsoft.com)
[![Unreal Engine: 5.1](https://img.shields.io/badge/Game-Palworld%20(UE%205.1)-313131?style=for-the-badge&logo=unrealengine)](https://unrealengine.com)
[![Modding: UE4SS 3.0.1](https://img.shields.io/badge/Modpack-UE4SS%203.0.1%20Integrated-FF6F00?style=for-the-badge)](https://github.com/UE4SS-RE/RE-UE4SS)

**PalOdyssey Launcher** is a custom 1-click game launcher, auto-updater, and performance optimizer built specifically for **Palworld**. It automatically manages, installs, and optimizes your modpack so you can jump straight into the realm with peak framerates, crystal-clear visuals, and zero manual file copying.

---

## ⚡ Quick Start: How to Install & Play

Getting started takes less than 60 seconds:

1. **Download the Launcher**:
   - Download the latest release from the [Releases](https://github.com/beoul-create/PalOdyssey-Launcher/releases) page (or clone the repository).
2. **Launch `PalLauncher.exe`**:
   - The launcher automatically detects your Steam Palworld installation.
3. **1-Click Auto-Calibrate**:
   - Go to **Launch Settings** ➔ Click **`⚡ AUTO-CALIBRATE & OPTIMIZE RIG`** to automatically configure optimal graphics and CPU flags for your PC.
4. **Launch Expedition**:
   - Click the glowing **`Launch Expedition`** button on the Dashboard. The launcher automatically verifies mod integrity, applies updates, and launches your game!

---

## 🌟 What the Launcher Has

### 🚀 1. 1-Click Hardware Auto-Calibrator (`Auto-Optimize Rig`)
- **Instant System Benchmark**: Probes your CPU cores, RAM, and GPU to determine your system's ideal performance tier (**Efficiency APU**, **Balanced Gaming**, or **Ultra Enthusiast**).
- **Auto-Configured Startup Flags**: Automatically applies multithreading (`-USEALLAVAILABLECORES`), memory allocators (`-malloc=system`), and DirectX settings (`-dx11` or `-dx12`) tailored specifically for your hardware.
- **Zero Stutter Engine**: Tunes background worker threads and texture streaming so you get maximum FPS and smooth frametimes.

### 🔄 2. Seamless Modpack Auto-Updater
- **Zero Manual Copying**: Never worry about extracting `.zip` files or copying files into `~mods` folders.
- **SHA-256 Checksum Verification**: Automatically detects outdated or corrupted files and updates them in seconds with streaming progress bars.
- **Mod Manager Tab**: View all installed mods, check their verification status, and toggle individual mods on or off.

### 🎮 3. Discord Rich Presence
- **Live Status Badges**: Shows your friends when you are preparing in the launcher or actively playing in the realm (`⚡ PalOdyssey Expedition • Exploring Realm • 15 Mods Active`).
- **Custom Game Branding**: Connects directly to Discord with high-resolution activity icons and live session timers.

### 🎨 4. Futuristic Cyberpunk UI
- **Glassmorphic Theme**: Sleek dark-mode aesthetic with neon cyan and electric violet glow accents.
- **Real-Time Activity Console**: Built-in colored logging terminal (`Info`, `Success`, `Warning`, `Error`) with 1-click log export for quick troubleshooting.

---

## 📦 What's Inside the Modpack?

When you launch through PalOdyssey, you get an out-of-the-box enhanced Palworld experience:

* 🐾 **Stuck Pal Rescuer**: Automatically rescues base camp Pals that get stuck in building geometry or pathfinding loops and teleports them back to the Palbox so your base workers never starve or bug out.
* 🌄 **Visual Clarity Engine**: Removes the washed-out milky grey atmospheric fog layer and disables chromatic aberration blur so distant landscapes and lighting look crisp, clear, and vibrant.
* 📥 **Quick Deposit (`G` Key)**: Press **`G`** inside your base to automatically deposit all matching items from your inventory into nearby storage containers.
* 🚫 **Remove Mod Warning**: Suppresses the third-party mods detected modal pop-up on the title screen for an instant, seamless game startup.
* ⚔️ **Weapon Proficiency & Mastery**: Earn weapon experience as you fight to level up damage bonuses and increase weapon durability.
* 👑 **Catch All Predator Bosses**: Unlocks capture mechanics for legendary predator boss encounters.
* 🧹 **RAM Trim & Garbage Collection**: Automatically cleans up accumulated VRAM and memory leaks during long play sessions.

---

## ⚙️ In-Game Mod Menu (`ESC → Mod Options`)

You can customize mod settings live while playing without restarting your game:

1. Press **`ESC` ➔ Mod Options** anywhere in-game.
2. Adjust your settings:
   - **Stuck Pal Rescuer**: Change scan frequency or stuck timeout threshold.
   - **Visual Clarity**: Toggle fog removal, chromatic aberration, or shadow distance.
   - **Quick Deposit**: Change deposit hotkey (default `G`) and chest scan radius.
   - **Palworld Tuner**: Adjust inventory carry weight multipliers.
   - **Weapon Proficiency**: Toggle damage and durability scaling.
   - **Performance & RAM**: Configure memory trim intervals.

---

## 🖥️ Recommended Hardware Presets

Not sure what settings are best for your PC? Here is a quick guide:

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
