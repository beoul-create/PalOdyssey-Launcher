using System;
using System.Collections.Generic;
using System.IO;
using System.Text.RegularExpressions;
using Microsoft.Win32;
using PalLauncher.Services.Interfaces;

namespace PalLauncher.Services
{
    public class GamePathDetector : IGamePathDetector
    {
        private readonly ILogService _logService;
        private const string SteamAppId = "1623730";
        private const string SteamServerAppId = "2394010";

        public GamePathDetector(ILogService logService)
        {
            _logService = logService;
        }

        public GamePathInfo DetectPalworldInstallation(string? customPath = null)
        {
            _logService.LogInfo("Starting Palworld installation detection...", "PathDetector");

            // 1. Check custom path first if supplied
            if (!string.IsNullOrWhiteSpace(customPath))
            {
                var customInfo = ValidatePath(customPath);
                if (customInfo.IsValid)
                {
                    customInfo.DetectedSource = "UserConfig";
                    _logService.LogSuccess($"Palworld found at user-configured path: {customPath}", "PathDetector");
                    return customInfo;
                }
            }

            // 2. Check Steam Registry Uninstall key for Client & Dedicated Server
            try
            {
                string? registryPath = GetPathFromUninstallRegistry();
                if (!string.IsNullOrEmpty(registryPath))
                {
                    var info = ValidatePath(registryPath);
                    if (info.IsValid)
                    {
                        info.DetectedSource = "Registry (Uninstall Key)";
                        _logService.LogSuccess($"Palworld detected via Windows Registry: {registryPath}", "PathDetector");
                        return info;
                    }
                }
            }
            catch (Exception ex)
            {
                _logService.LogWarning("Registry lookup failed.", "PathDetector", ex.Message);
            }

            // 3. Check Steam Libraries via Steam Client Registry & libraryfolders.vdf
            try
            {
                var steamLibraries = GetSteamLibraryFolders();
                foreach (var lib in steamLibraries)
                {
                    string[] candidates = {
                        Path.Combine(lib, "steamapps", "common", "Palworld"),
                        Path.Combine(lib, "steamapps", "common", "PalServer")
                    };

                    foreach (var candidate in candidates)
                    {
                        var info = ValidatePath(candidate);
                        if (info.IsValid)
                        {
                            info.DetectedSource = "Steam Library VDF Scan";
                            _logService.LogSuccess($"Palworld detected in Steam library: {candidate}", "PathDetector");
                            return info;
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                _logService.LogWarning("Steam libraryfolders scanning encountered an error.", "PathDetector", ex.Message);
            }

            // 4. Common standard install locations across drives
            string[] standardLocations =
            {
                @"C:\Program Files (x86)\Steam\steamapps\common\Palworld",
                @"C:\Program Files\Steam\steamapps\common\Palworld",
                @"C:\SteamLibrary\steamapps\common\Palworld",
                @"C:\SteamLibrary\steamapps\common\PalServer",
                @"D:\SteamLibrary\steamapps\common\Palworld",
                @"D:\SteamLibrary\steamapps\common\PalServer",
                @"E:\SteamLibrary\steamapps\common\Palworld",
                @"E:\SteamLibrary\steamapps\common\PalServer",
                @"F:\SteamLibrary\steamapps\common\Palworld",
                @"F:\SteamLibrary\steamapps\common\PalServer",
                @"G:\SteamLibrary\steamapps\common\Palworld",
                @"G:\SteamLibrary\steamapps\common\PalServer",
                @"C:\XboxGames\Palworld\Content",
                @"D:\XboxGames\Palworld\Content"
            };

            foreach (var candidate in standardLocations)
            {
                var info = ValidatePath(candidate);
                if (info.IsValid)
                {
                    info.DetectedSource = "Standard Directory Scan";
                    _logService.LogSuccess($"Palworld detected at standard path: {candidate}", "PathDetector");
                    return info;
                }
            }

            _logService.LogWarning("Palworld installation could not be automatically detected.", "PathDetector");
            return new GamePathInfo
            {
                IsValid = false,
                DetectedSource = "Not Found"
            };
        }

        public GamePathInfo ValidatePath(string path)
        {
            var result = new GamePathInfo();
            if (string.IsNullOrWhiteSpace(path))
                return result;

            try
            {
                // Clean quotes or trailing separators
                path = path.Trim('\"', '\'', ' ');

                // If user pointed to an executable directly, get parent directory
                if (File.Exists(path) && (path.EndsWith(".exe", StringComparison.OrdinalIgnoreCase)))
                {
                    if (path.EndsWith("Palworld-Win64-Shipping.exe", StringComparison.OrdinalIgnoreCase))
                    {
                        // Path is in Pal/Binaries/Win64 -> root is 3 levels up
                        var p1 = Directory.GetParent(path)?.Parent?.Parent?.FullName;
                        if (p1 != null) path = p1;
                    }
                    else
                    {
                        var p = Directory.GetParent(path)?.FullName;
                        if (p != null) path = p;
                    }
                }

                if (!Directory.Exists(path))
                    return result;

                string rootExe = Path.Combine(path, "Palworld.exe");
                string shippingExe = Path.Combine(path, "Pal", "Binaries", "Win64", "Palworld-Win64-Shipping.exe");
                string serverExe = Path.Combine(path, "PalServer.exe");
                
                if (!File.Exists(serverExe))
                {
                    string shippingServer = Path.Combine(path, "Pal", "Binaries", "Win64", "PalServer-Win64-Shipping.exe");
                    if (File.Exists(shippingServer))
                    {
                        serverExe = shippingServer;
                    }
                    else
                    {
                        string siblingPalServer = Path.Combine(path, "..", "PalServer", "PalServer.exe");
                        if (File.Exists(siblingPalServer))
                        {
                            serverExe = Path.GetFullPath(siblingPalServer);
                        }
                    }
                }

                string paksDir = Path.Combine(path, "Pal", "Content", "Paks");
                string modsPaksDir = Path.Combine(paksDir, "~mods");

                bool hasClient = File.Exists(rootExe) || File.Exists(shippingExe);
                bool hasServer = File.Exists(serverExe);

                if (hasClient || hasServer)
                {
                    result.IsValid = true;
                    result.GameRootPath = path;
                    result.ClientExecutablePath = File.Exists(rootExe) ? rootExe : shippingExe;
                    result.ShippingExecutablePath = shippingExe;
                    result.ServerExecutablePath = serverExe;
                    result.PaksDirectoryPath = paksDir;
                    result.ModsPaksDirectoryPath = modsPaksDir;
                }
            }
            catch (Exception ex)
            {
                _logService.LogWarning($"Error validating path '{path}'.", "PathDetector", ex.Message);
            }

            return result;
        }

        private string? GetPathFromUninstallRegistry()
        {
            if (!OperatingSystem.IsWindows()) return null;

            string[] appIds = { SteamAppId, SteamServerAppId };

            foreach (var appId in appIds)
            {
                string keyName = $@"SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\Steam App {appId}";
                using var baseKey = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry64);
                using var subKey = baseKey.OpenSubKey(keyName);
                if (subKey != null)
                {
                    var installLoc = subKey.GetValue("InstallLocation") as string;
                    if (!string.IsNullOrEmpty(installLoc) && Directory.Exists(installLoc))
                    {
                        return installLoc;
                    }
                }

                // Also check 32-bit hive
                using var baseKey32 = RegistryKey.OpenBaseKey(RegistryHive.LocalMachine, RegistryView.Registry32);
                using var subKey32 = baseKey32.OpenSubKey(keyName);
                if (subKey32 != null)
                {
                    var installLoc = subKey32.GetValue("InstallLocation") as string;
                    if (!string.IsNullOrEmpty(installLoc) && Directory.Exists(installLoc))
                    {
                        return installLoc;
                    }
                }
            }

            return null;
        }

        private List<string> GetSteamLibraryFolders()
        {
            var libraries = new List<string>();
            if (!OperatingSystem.IsWindows()) return libraries;

            string? steamRoot = null;
            using (var key = Registry.CurrentUser.OpenSubKey(@"Software\Valve\Steam"))
            {
                steamRoot = key?.GetValue("SteamPath") as string;
            }

            if (string.IsNullOrEmpty(steamRoot) || !Directory.Exists(steamRoot))
            {
                using var key = Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Valve\Steam");
                steamRoot = key?.GetValue("InstallPath") as string;
            }

            if (!string.IsNullOrEmpty(steamRoot) && Directory.Exists(steamRoot))
            {
                libraries.Add(steamRoot);

                string vdfPath = Path.Combine(steamRoot, "steamapps", "libraryfolders.vdf");
                if (File.Exists(vdfPath))
                {
                    try
                    {
                        string content = File.ReadAllText(vdfPath);
                        var matches = Regex.Matches(content, @"""path""\s+""([^""]+)""");
                        foreach (Match m in matches)
                        {
                            if (m.Groups.Count > 1)
                            {
                                string libPath = m.Groups[1].Value.Replace(@"\\", @"\");
                                if (Directory.Exists(libPath) && !libraries.Contains(libPath))
                                {
                                    libraries.Add(libPath);
                                }
                            }
                        }
                    }
                    catch
                    {
                        // Ignore VDF parsing errors
                    }
                }
            }

            return libraries;
        }
    }
}
