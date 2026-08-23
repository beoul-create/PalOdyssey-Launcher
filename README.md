# ⚡ PalOdyssey: Next-Gen Palworld Launcher & Unified Modpack

[![Platform: Windows](https://img.shields.io/badge/Platform-Windows%2010%2F11-0078D6?style=for-the-badge&logo=windows)](https://microsoft.com)
[![Framework: .NET 8 WPF](https://img.shields.io/badge/Framework-.NET%208%20WPF-512BD4?style=for-the-badge&logo=dotnet)](https://dotnet.microsoft.com)
[![Unreal Engine: 5.1](https://img.shields.io/badge/Engine-Unreal%20Engine%205.1-313131?style=for-the-badge&logo=unrealengine)](https://unrealengine.com)
[![Modding: UE4SS 3.0.1](https://img.shields.io/badge/Modding-UE4SS%203.0.1%20C%2B%2B%20%26%20Lua-FF6F00?style=for-the-badge)](https://github.com/UE4SS-RE/RE-UE4SS)
[![Networking: Zero-IP Exposure](https://img.shields.io/badge/Security-Zero--IP%20Exposure%20(Playit%20%2B%20DuckDNS)-00F0FF?style=for-the-badge)](https://playit.gg)

**PalOdyssey** is a production-grade game launcher, auto-calibrating performance profiler, and synchronized modpack ecosystem engineered specifically for modded **Palworld** expeditions and dedicated server infrastructure.

---

## 📑 Table of Contents
- [🌟 Core Launcher Features](#-core-launcher-features)
- [📦 Complete Unified Modpack Roster (26+ Mods)](#-complete-unified-modpack-roster-26-mods)
- [⚙️ In-Game Mod Menu (`ESC → Mod Options`)](#️-in-game-mod-menu-esc--mod-options)
- [⚡ 1-Click Hardware Auto-Calibration & Presets](#-1-click-hardware-auto-calibration--presets)
- [🛡️ Zero-IP Exposure Networking (Playit.gg + DuckDNS)](#️-zero-ip-exposure-networking-playitgg--duckdns)
- [🚀 Installation & Setup Guide](#-installation--setup-guide)
  - [Client Installation (Players)](#client-installation-players)
  - [Dedicated Server Setup (Hosts)](#dedicated-server-setup-hosts)
- [🛠️ Developer & Modding Architecture](#️-developer--modding-architecture)
- [❓ FAQ & Troubleshooting](#-faq--troubleshooting)

---

## 🌟 Core Launcher Features

### 1. ⚡ 1-Click Auto-Calibrate & Hardware Optimization Engine
- **Hardware Detection**: Probes logical/physical CPU cores, system RAM, and GPU VRAM tiers using Windows Management Instrumentation (`WMI`) and hardware APIs.
- **Empirical Stress Benchmarking**: Runs real-time multithreaded compute throughput and memory allocation tests to classify your PC into **Efficiency (APU)**, **Balanced (Mid-Range)**, or **Ultra (Enthusiast)**.
- **Automated Configuration**: Applies optimal launch flags (`-USEALLAVAILABLECORES`, `-malloc=system`, `-dx11`/`-dx12`, `-high`, `-lowmemory`) and writes calibrated task graph worker thread limits directly into mod configurations.

### 2. 🔄 Remote Manifest & Automated Modpack Sync (`UpdateService.cs`)
- **Remote GitHub Manifest**: Synchronizes with remote `version.json` manifests to pull the latest core binaries, UE4SS mods, and content paks.
- **SHA-256 Integrity Verification**: Fast multi-threaded checksum inspection verifies every `.pak` and `.dll` to automatically repair corrupted or outdated files.
- **Dual Target Mirroring**: One-click deployment to either local game clients or sibling `PalServer` roots via `Deploy-Modpack.ps1`.

### 3. 🎮 Discord Rich Presence Integration (`DiscordRpcService.cs`)
- **Real-Time Activity Broadcast**: Displays rich in-game activity badges on Discord (`⚡ PalOdyssey Expedition • Exploring Realm • 15 Mods Active`).
- **Resilient Named Pipe Architecture**: Connects across `\\.\pipe\discord-ipc-0` through `\\.\pipe\discord-ipc-9` with automatic reconnect and state caching.

### 4. 📡 Remote Host Management Daemon & Liveboard (`RemoteServerDaemon.cs`)
- **RESTful Liveboard API**: Built-in lightweight HTTP server providing real-time player counts, uptime, and server health status to the launcher dashboard.
- **Smart Idle Auto-Shutdown**: Automatically monitors active player connections and gracefully suspends the dedicated server when empty to conserve host CPU and electricity.
- **Secure Remote Wake**: Protected with token-authenticated remote start hooks (`X-PalOdyssey-Key`).

---

## 📦 Complete Unified Modpack Roster (26+ Mods)

The modpack features a curated, highly optimized suite of client and server mods:

| Mod Name | Side / Authority | Purpose & Functional Description |
| :--- | :--- | :--- |
| **`StuckPalRescuer`** | **Client & Server** | Continuously monitors base camp worker Pals. If a Pal gets stuck in geometry or pathfinding loops for >18s, automatically teleports them back to the Palbox in pristine condition. Prevents AI tick rate spikes and base starvation loops. |
| **`RemoveModWarning`** | **Client** | Suppresses and auto-dismisses the third-party mods detected modal pop-up on the title screen for a clean, instant game boot. |
| **`QuickDeposit`** | **Client** | Press **`G`** inside your base to automatically deposit all matching item stacks from your inventory into nearby chests. |
| **`PalClearVision`** | **Client** | Removes the washed-out milky grey atmospheric fog layer, disables chromatic aberration and film grain noise, and extends shadow draw distance. |
| **`WeaponProficiency`** | **Client & Server** | Weapon mastery progression. Client authors damage scaling while server-authoritative RPCs synchronize `MaxDurability` across network boundaries. |
| **`ExpeditionXP`** | **Server-Authoritative** | Host-authoritative experience multiplier and expedition progression tuner. |
| **`LevelLock`** | **Server-Authoritative** | Enforces milestone-based level caps across guilds to ensure balanced multiplayer progression. |
| **`PalworldTuner`** | **Client & Server** | Gameplay multipliers for inventory carry weight, fast travel tech points, and boss unlocks. |
| **`PalOdysseyOptimizer`**| **Client & Server** | Dynamic memory allocator, ambient actor tick throttler, and particle culling engine. |
| **`RamTrimMod`** | **Client & Server** | Scheduled working-set memory trimming to prevent Unreal Engine 5 VRAM/RAM accumulation over long sessions. |
| **`DarnMenu`** | **Client** | In-game mod configuration framework accessible via **`ESC → Mod Options`**. |
| **`DarnToasts`** | **Client** | Sleek unobtrusive notification toast framework for in-game mod alerts. |
| **`Keybinds`** | **Client** | Centralized hotkey dispatcher for mod utilities. |
| **`PalSchema`** | **Core Framework** | High-performance reflection and schema metadata provider for Palworld C++ objects. |
| **`BPModLoaderMod`** | **Core Framework** | LogicMods and Blueprint mod loader injector. |
| **`BPML_GenericFunctions`**| **Core Framework** | Blueprint math and helper library. |
| **`Catch All PREDATOR Bosses`**| **Pak Mod** | Expands capture mechanics to include legendary predator boss encounters. |

---

## ⚙️ In-Game Mod Menu (`ESC → Mod Options`)

All client-configurable mods are natively registered with **DarnMenu**. You can adjust settings live without relaunching the game:

1. Press **`ESC` ➔ Mod Options** while in-game.
2. Select any registered tab:
   - **`Stuck Pal Rescuer`**: Toggle automated rescue, adjust scan frequency (3–60s), and set stuck timeout threshold.
   - **`Visual Clarity`**: Toggle fog removal, chromatic aberration removal, film grain, and shadow distance scaling.
   - **`Quick Deposit`**: Customize deposit keybind (`G`) and chest scan radius (500–5000 units).
   - **`Palworld Tuner`**: Adjust carry weight multipliers and technology point rewards.
   - **`Weapon Proficiency`**: Toggle damage bonuses, durability scaling, and network RPC synchronization.
   - **`Performance & RAM`**: Configure RAM trim intervals (15–300s) and UE5 garbage collection cycles.

---

## ⚡ 1-Click Hardware Auto-Calibration & Presets

The launcher analyzes your PC and automatically configures one of three optimized hardware profiles:

```
[Hardware Profile Evaluation]
 ├── Tier 1: Efficiency / Handheld (4 Cores, 8GB RAM, <4GB VRAM) ──► Preset: efficiency_max  (40-60 FPS)
 ├── Tier 2: Balanced Gaming       (6 Cores, 16GB RAM, 6-8GB VRAM) ─► Preset: balanced        (60-85 FPS)
 └── Tier 3: Ultra / Enthusiast    (8+ Cores, 32GB+ RAM, 12GB+ VRAM) ─► Preset: ultra_optimal  (90-120+ FPS)
```

### Empirical Benchmark Summary

| Hardware Tier | Target Resolution & Rendering | Applied Arguments | Memory & Task Graph Tuning |
| :--- | :--- | :--- | :--- |
| **Tier 1: Efficiency** | 1080p FSR/DLSS Performance (DX11) | `-lowmemory -USEALLAVAILABLECORES -dx11` | GC Interval: 45s • RAM Trim: 2m • SigScanner: 4 Threads |
| **Tier 2: Balanced** | 1080p/1440p Balanced (DX11) | `-malloc=system -useperfthreads -USEALLAVAILABLECORES -dx11` | GC Interval: 60s • RAM Trim: 4m • SigScanner: 8 Threads |
| **Tier 3: Ultra** | 1440p/4K DLSS Quality / TSR (DX12) | `-malloc=system -useperfthreads -high -NoAsyncLoadingThread` | GC Interval: 90s • RAM Trim: 3m • SigScanner: 16 Threads |

---

## 🛡️ Zero-IP Exposure Networking (Playit.gg + DuckDNS)

PalOdyssey uses **Anycast proxy tunneling** to ensure server hosts never expose their home IP address or location:

```
[Player Client]
       │
       ▼
 [palodyssey.duckdns.org:57294]  (DuckDNS Hostname)
       │
       ▼
 [147.185.221.230:57294]         (Playit.gg Anycast Proxy Datacenter)
       │
       ▼ (Encrypted UDP Tunnel)
 [Local playit.exe Agent]        (Host PC Background Agent)
       │
       ▼
 [127.0.0.1:8211]                (Local Palworld Dedicated Server)
```

- **Home IP Protection**: Players connect exclusively to the Anycast proxy. Running `ping` or `nslookup` on `palodyssey.duckdns.org` only shows Playit's datacenter IP.
- **DDoS Mitigation**: Malicious traffic is absorbed at the Anycast edge without impacting residential internet bandwidth.
- **Zero Port Forwarding**: The local `playit.exe` agent creates an outbound tunnel, eliminating the need to open ports on your home router.

---

## 🚀 Installation & Setup Guide

### Client Installation (Players)

1. **Download & Launch**:
   - Clone or download the repository.
   - Run `PalLauncher.exe` (or launch via `run-dev.ps1`).
2. **Auto-Detect Game Path**:
   - The launcher automatically detects your Steam Palworld installation (`C:\SteamLibrary\steamapps\common\Palworld`).
3. **1-Click Auto-Calibration**:
   - Navigate to **Launch Settings** ➔ Click **`⚡ AUTO-CALIBRATE & OPTIMIZE RIG`**.
4. **Deploy & Play**:
   - Click **`Launch Expedition`** on the Dashboard. The launcher checks file checksums, deploys the modpack, and connects to the server!

---

### Dedicated Server Setup (Hosts)

1. **Deploy Server Modpack**:
   - Open PowerShell as Administrator and run:
     ```powershell
     powershell.exe -ExecutionPolicy Bypass -File .\Deploy-Modpack.ps1
     ```
   - This automatically configures `PalServer` with headless server mods (`StuckPalRescuer`, `WeaponProficiency`, `LevelLock`, `ExpeditionXP`, `PalOdysseyOptimizer`, and memory cleaners).
2. **Start the Playit Tunnel Agent**:
   - Run `.\tools\playit\playit.exe` to start your secure proxy tunnel.
3. **Launch the Dedicated Server**:
   - In the launcher, switch **Launch Mode** to **Dedicated Server** and click **Start Server**.

---

## 🛠️ Developer & Modding Architecture

```
c:\PalOddessey\
├── PalLauncher.sln                  # .NET 8 Solution
├── PalLauncher\                     # WPF MVVM Application
│   ├── Converters\                  # XAML Value Converters
│   ├── Models\                      # Data Contracts & Configs
│   ├── Services\                    # Core Services (Launch, Update, RPC, Specs, Daemon)
│   ├── ViewModels\                  # MVVM ViewModels
│   ├── Views\                       # Cyberpunk Glassmorphic Views
│   └── Assets\                      # 4K Launcher Icons & Badges
├── PalLauncher.Tests\               # xUnit Diagnostic & Benchmark Suite (36 Tests)
├── Modpack\Pal\                     # Master Modpack Staging Root
│   ├── Binaries\Win64\ue4ss\Mods\   # 26+ Lua & C++ Mods
│   │   ├── shared\                  # DarnMenu Schemas & Libs
│   │   ├── StuckPalRescuer\         # Pal AI Rescue Engine
│   │   ├── RemoveModWarning\        # Title Screen Warning Suppressor
│   │   ├── QuickDeposit\            # Base Chest Auto-Stack
│   │   └── PalClearVision\          # Visual De-Fogger & Post-Process
│   └── Content\Paks\~mods\          # Pak Mods
├── Deploy-Modpack.ps1               # Automated Deployment Script
└── tools\playit\                    # Playit.gg Tunnel Agent
```

---

## ❓ FAQ & Troubleshooting

#### Q: How do I open the In-Game Mod Menu?
> **A:** Press **`ESC` ➔ Mod Options** anywhere in-game. You will see configuration tabs for all active mods.

#### Q: My Pal is stuck on a roof or cliff. What should I do?
> **A:** `StuckPalRescuer` automatically detects stuck Pals and teleports them back to the Palbox after ~18 seconds. You can lower this threshold in **`ESC ➔ Mod Options ➔ Stuck Pal Rescuer`**.

#### Q: How do I change the Quick Deposit hotkey?
> **A:** Go to **`ESC ➔ Mod Options ➔ Quick Deposit`** and select your preferred keybind (default is `G`).

#### Q: How do I export diagnostic logs for support?
> **A:** In the launcher, navigate to the **Activity Logs** tab and click **`Export Logs`** or **`Copy to Clipboard`**.

---

**Developed with ❤️ for the PalOdyssey Community.**
