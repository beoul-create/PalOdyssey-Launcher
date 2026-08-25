# 🛠️ PalOdyssey Maintainer & Developer Guide

This document is a navigation guide for maintaining the **PalOdyssey Launcher**, distinguishing what files are deployed to **GitHub / Players** versus what is used for **Local Development & Server Hosting**.

---

## 📂 Project Organization Matrix

| Directory / File | Category | Purpose | Push to GitHub? |
| :--- | :--- | :--- | :---: |
| **`Modpack/`** | 🌐 **Distribution** | Mod files, UE4SS, Lua configs, & `version.json`. The launcher downloads mods directly from GitHub using this path. | **YES** (Crucial) |
| **`PalLauncher/`** | 🌐 **Source Code** | C# .NET 8 WPF application source code. | **YES** |
| **`PalLauncher.sln`** | 🌐 **Solution** | Visual Studio solution file for building. | **YES** |
| **`PalOdyssey-Launcher-v2.0.0.zip`** | 🌐 **Release Package** | Pre-packaged executable archive for players to download. | **YES** |
| **`README.md`** | 🌐 **Documentation** | Player quick-start guide, mod settings, and troubleshooting. | **YES** |
| **`DEVELOPMENT.md`** | 🌐 **Documentation** | Developer workflow guide (this file). | **YES** |
| **`dev-tools/`** | 🛠️ **Development** | Developer runners (`run-dev.bat`), test runners (`run-tests.bat`), and packagers. | **YES** |
| **`PalLauncher.Tests/`** | 🛠️ **Testing** | 89 automated unit, integration, and regression tests. | **YES** |
| **`server-tools/`** | 🖥️ **Server Hosting** | 24/7 PM2 bot runners, task schedulers, and dedicated server deployers. | **YES** |
| **`tools/playit/`** | 🖥️ **Network Tools** | Tunneling binary for co-op server hosting. | **YES** |
| `bot_token.txt` | 🔒 **Local Secret** | Discord bot token for the 24/7 daemon. | ❌ (Ignored in `.gitignore`) |
| `publish/`, `bin/`, `obj/` | ⚙️ **Build Output** | Intermediate build binaries. | ❌ (Ignored in `.gitignore`) |

---

## 🔄 Common Workflows

### 1. 📦 Adding or Updating Mods for Players

When you add a new mod or update an existing mod for your community:

1. **Place Mod Files**:
   - Put UE4SS mods in `Modpack/Pal/Binaries/Win64/ue4ss/Mods/<ModName>/`
   - Put Pak mods in `Modpack/Pal/Content/Paks/~mods/<ModName>.pak`
2. **Update `Modpack/version.json`**:
   - Increment the modpack `version` string (e.g. `"1.5.5"`).
   - Add or update the file entry under `"files"` with its relative path and SHA-256 checksum.
3. **Verify Integrity**:
   - Run `dev-tools/run-tests.bat` to ensure manifest checksum verification passes.
4. **Push to GitHub**:
   ```bash
   git add Modpack/
   git commit -m "Update modpack to v1.5.5"
   git push origin main
   ```
   > ⚡ **Live Auto-Update**: Once pushed to GitHub, players' launchers will immediately notify them of the update and download the new files automatically!

---

### 2. 💻 Modifying Launcher Code & Testing

When making improvements, UI tweaks, or bug fixes to the launcher:

1. **Launch in Dev Mode**:
   - Double-click [`dev-tools/run-dev.bat`](file:///c:/PalOddessey/dev-tools/run-dev.bat) to build and run with live hot-reloading/debug output.
   - Or open [`PalLauncher.sln`](file:///c:/PalOddessey/PalLauncher.sln) in Visual Studio.
2. **Run Test Suite**:
   - Double-click [`dev-tools/run-tests.bat`](file:///c:/PalOddessey/dev-tools/run-tests.bat).
   - Verify all 89 unit and integration tests pass.

---

### 3. 🚀 Packaging a New Release for Players

When you are ready to distribute a new launcher version:

1. **Build and Zip**:
   - Double-click [`dev-tools/package-release.bat`](file:///c:/PalOddessey/dev-tools/package-release.bat).
   - This automatically compiles a clean Release build and creates the fresh `PalOdyssey-Launcher-v2.0.0.zip`.
2. **Commit & Push**:
   ```bash
   git add PalLauncher/ PalOdyssey-Launcher-v2.0.0.zip
   git commit -m "Release launcher v2.0.0"
   git push origin main
   ```

---

### 4. 🤖 Running the 24/7 Discord Bot & Realm Host

For hosting the server liveboard, Discord bot, and economy sync:

* **PM2 Daemon (Recommended for Background 24/7)**:
  - Start: Double-click [`server-tools/start-pm2.bat`](file:///c:/PalOddessey/server-tools/start-pm2.bat)
  - View Live Logs: Double-click [`server-tools/status-pm2.bat`](file:///c:/PalOddessey/server-tools/status-pm2.bat)
  - Stop: Double-click [`server-tools/stop-pm2.bat`](file:///c:/PalOddessey/server-tools/stop-pm2.bat)
* **Windows Task Scheduler (Auto-start on Windows boot)**:
  - Double-click [`server-tools/setup-24-7-task.bat`](file:///c:/PalOddessey/server-tools/setup-24-7-task.bat)
* **Syncing Local Server**:
  - Double-click [`server-tools/deploy-modpack.bat`](file:///c:/PalOddessey/server-tools/deploy-modpack.bat) to synchronize mod files to your local PalServer directory.
