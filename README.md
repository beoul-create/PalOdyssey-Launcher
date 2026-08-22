# PalOdyssey Custom Game Launcher (WPF / .NET 8)

A custom C# WPF desktop game launcher built with clean **MVVM architecture**, designed for modded Palworld expeditions and dedicated server deployment.

---

## 🌟 Key Features

### 1. Remote Manifest & Update Checker (`UpdateService.cs`)
- **Remote JSON Manifest**: Reads a remote `version.json` hosted on GitHub Raw or custom HTTP endpoints.
- **SHA-256 Checksum Verification**: Calculates local `.pak` hashes to detect missing or modified/outdated mods.
- **Direct Pak Placement**: Automatically downloads and installs `.pak` files directly into Palworld's binaries directory (`Pal\Content\Paks\` or `Pal\Content\Paks\~mods\`).
- **Streaming Progress**: Real-time download progress bar with percentage, download speed (KB/s, MB/s), and integrity verification.

### 2. Process Management & Launch Arguments (`LaunchService.cs`)
- **Automatic Path Detection**: Scans Windows Registry (Steam AppID `1623730`), Steam `libraryfolders.vdf`, and common library drives.
- **Custom Path Browser**: Folder selection dialog with fallback and path validation.
- **Dual Execution Modes**: Supports launching the **Game Client** (`Palworld.exe` / `Palworld-Win64-Shipping.exe`) or **Dedicated Server** (`PalServer.exe`).
- **Predefined Performance & Network Arguments**:
  - Auto IP joining: `<ServerIP>:<ServerPort>` (e.g. `127.0.0.1:8211`)
  - `-dx11` (DirectX 11 rendering)
  - `-USEALLAVAILABLECORES` (CPU multithreading optimization)
  - `-high` (Process priority)
  - `-nosplash` (Skip intro splash animations)
  - `-windowed` (Borderless windowed mode)
  - Custom user arguments string with **live argument preview**!
- **Lifecycle Tracking**: Monitors game running state, PID, session duration, and exit codes.

### 3. Sleek Cyberpunk / Dark UI (`MainWindow.xaml`)
- **Custom Window Chrome**: Frameless dark window with draggable header, glowing badge indicators, and window controls (minimize, maximize, close).
- **Navigation Tabs**:
  - **Dashboard**: High-level overview cards, server quick-status, and news announcements.
  - **Mods & Paks**: Visual list of all core mod paks with status tags (`Verified & Up to Date`, `Update Available`, `Missing`), single-mod updates, and batch "Update All" button.
  - **Launch Settings**: Game directory detector, client/server mode selector, performance argument checkboxes, server IP/port inputs, and manifest URL connection tester.
  - **Activity Logs**: Monospaced terminal console with color-coded severity filtering (`Info`, `Success`, `Warning`, `Error`), copy to clipboard, and folder export.
- **Prominent "Launch Expedition" Action Bar**: Big glowing gradient button with dynamic progress bar and real-time status text ("Checking for updates...", "Ready to Launch", "In Game (PID: 1234)").

---

## 📂 Project Structure

```
c:\PalOddessey\
├── PalLauncher.sln
├── PalLauncher\
│   ├── App.xaml / App.xaml.cs
│   ├── PalLauncher.csproj
│   ├── Converters\
│   │   ├── BooleanToVisibilityConverter.cs
│   │   ├── FileSizeConverter.cs
│   │   ├── ModStatusToColorConverter.cs
│   │   ├── NullOrEmptyToVisibilityConverter.cs
│   │   └── ProgressPercentageConverter.cs
│   ├── Models\
│   │   ├── LauncherConfig.cs
│   │   ├── LogEntry.cs
│   │   ├── ModInfo.cs
│   │   ├── ModManifest.cs
│   │   ├── ModStatus.cs
│   │   └── UpdateProgressInfo.cs
│   ├── Services\
│   │   ├── Interfaces\
│   │   │   ├── IConfigService.cs
│   │   │   ├── IGamePathDetector.cs
│   │   │   ├── ILaunchService.cs
│   │   │   ├── ILogService.cs
│   │   │   └── IUpdateService.cs
│   │   ├── ConfigService.cs
│   │   ├── GamePathDetector.cs
│   │   ├── LaunchService.cs
│   │   ├── LogService.cs
│   │   └── UpdateService.cs
│   ├── Styles\
│   │   ├── Colors.xaml
│   │   ├── Controls.xaml
│   │   └── Icons.xaml
│   ├── ViewModels\
│   │   ├── Common\
│   │   │   ├── AsyncRelayCommand.cs
│   │   │   ├── RelayCommand.cs
│   │   │   └── ViewModelBase.cs
│   │   ├── LogsViewModel.cs
│   │   ├── MainViewModel.cs
│   │   ├── ModsViewModel.cs
│   │   └── SettingsViewModel.cs
│   ├── Views\
│   │   ├── DashboardView.xaml / .cs
│   │   ├── LogsView.xaml / .cs
│   │   ├── MainWindow.xaml / .cs
│   │   ├── ModsView.xaml / .cs
│   │   └── SettingsView.xaml / .cs
│   └── SampleData\
│       └── version.json
├── PalLauncher.Tests\
│   ├── ConfigServiceTests.cs
│   ├── GamePathDetectorTests.cs
│   ├── IntegrationTests.cs
│   ├── LaunchServiceTests.cs
│   └── UpdateServiceTests.cs
└── MockGame\
    └── PalRoot\ (Simulated Palworld binary directory for test launch)
```

---

## 🚀 Quick Start & Building

### Build the Solution
```powershell
dotnet build PalLauncher.sln
```

### Run Unit & Integration Tests
```powershell
dotnet test PalLauncher.sln
```

### Quick Launch (Dev Mode)
- **PowerShell**: `.\run-dev.ps1`
- **Batch / Double-Click**: `run-dev.bat`

### Manual CLI Commands
```powershell
$env:DOTNET_ROOT = "$env:USERPROFILE\.dotnet"; $env:PATH = "$env:USERPROFILE\.dotnet;$env:PATH"
dotnet run --project PalLauncher\PalLauncher.csproj
```

---

## ⚙️ Manifest Format (`version.json`)

Host a JSON file on your GitHub repository (e.g. GitHub Raw) or web server:

```json
{
  "manifestVersion": "1.2.0",
  "gameVersion": "0.3.x",
  "serverName": "PalOdyssey Official Server",
  "serverAddress": "127.0.0.1",
  "serverPort": 8211,
  "newsAnnouncement": "Welcome to PalOdyssey! Make sure your core mod paks are verified.",
  "mods": [
    {
      "id": "pal-core-sync",
      "name": "PalOdyssey Core Sync Pak",
      "description": "Core network packet optimization and state synchronizer.",
      "version": "1.2.4",
      "author": "PalOdyssey Team",
      "downloadUrl": "https://raw.githubusercontent.com/PalOdyssey/mods-manifest/main/paks/PalCoreSync.pak",
      "relativeInstallPath": "Pal\\Content\\Paks\\~mods\\PalCoreSync.pak",
      "sha256": "b61ac565d08ce8e1815564695140d782d3c3442123c7bfde35179860269f5961",
      "sizeBytes": 2450000,
      "isRequired": true,
      "changelog": "v1.2.4: Fixed packet drop during dungeon instances."
    }
  ]
}
```
