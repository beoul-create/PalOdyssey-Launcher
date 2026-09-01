using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Linq;
using System.Runtime.InteropServices;
using System.Text.RegularExpressions;
using System.Threading;
using System.Threading.Tasks;
using Microsoft.Win32;

namespace PalLauncher.Services
{
    public class GameProcessService
    {
        public const string PalworldAppId = "1623730";
        public const string PalServerAppId = "2394010";
        public const string ExecutableRelativePath = @"Pal\Binaries\Win64\Palworld-Win64-Shipping.exe";
        public const string ServerExecutableRelativePath = @"Pal\Binaries\Win64\PalServer-Win64-Shipping.exe";
        public const string MainProcessName = "Palworld-Win64-Shipping";
        public const string AlternateProcessName = "Palworld";
        public const string ServerProcessName = "PalServer-Win64-Shipping";
        public const string AlternateServerProcessName = "PalServer";

        private Process? _serverProcess;

        public event Action? GameStarted;
        public event Action? GameExited;
        public event Action<bool>? ServerStateChanged;

        public bool IsGameRunning { get; private set; }
        public bool IsServerRunning
        {
            get
            {
                if (_serverProcess != null && !_serverProcess.HasExited) return true;
                try
                {
                    return AnyProcessRunning(ServerProcessName) || AnyProcessRunning(AlternateServerProcessName);
                }
                catch
                {
                    return false;
                }
            }
        }

        private static bool AnyProcessRunning(string processName)
        {
            var processes = Process.GetProcessesByName(processName);
            try
            {
                return processes.Any(process => !process.HasExited);
            }
            finally
            {
                foreach (var process in processes) process.Dispose();
            }
        }

        public string? DetectGamePath() => DetectGameDirectory();

        public string? DetectServerPath(string? explicitPath = null)
        {
            // 1. Check user-configured explicit path
            if (!string.IsNullOrWhiteSpace(explicitPath) && Directory.Exists(explicitPath))
            {
                if (File.Exists(Path.Combine(explicitPath, "PalServer.exe")) ||
                    File.Exists(Path.Combine(explicitPath, ServerExecutableRelativePath)))
                    return explicitPath;
            }

            // 2. Check Steam libraries
            var steamPath = GetSteamInstallPath();
            if (!string.IsNullOrEmpty(steamPath) && Directory.Exists(steamPath))
            {
                var serverCandidates = new[]
                {
                    Path.Combine(steamPath, "steamapps", "common", "PalServer"),
                    Path.Combine(steamPath, "steamapps", "common", "Palworld Dedicated Server")
                };

                foreach (var sc in serverCandidates)
                {
                    if (IsValidServerDirectory(sc)) return sc;
                }

                string libraryFoldersVdf = Path.Combine(steamPath, "steamapps", "libraryfolders.vdf");
                if (File.Exists(libraryFoldersVdf))
                {
                    var extraLibraries = ParseLibraryFolders(libraryFoldersVdf);
                    foreach (var lib in extraLibraries)
                    {
                        var libCandidates = new[]
                        {
                            Path.Combine(lib, "steamapps", "common", "PalServer"),
                            Path.Combine(lib, "steamapps", "common", "Palworld Dedicated Server")
                        };

                        foreach (var sc in libCandidates)
                        {
                            if (IsValidServerDirectory(sc)) return sc;
                        }
                    }
                }
            }

            // 3. Fallback: Search standard drive paths
            var standardServerPaths = new[]
            {
                @"C:\SteamLibrary\steamapps\common\PalServer",
                @"C:\Program Files (x86)\Steam\steamapps\common\PalServer",
                @"C:\Program Files\Steam\steamapps\common\PalServer",
                @"C:\PalworldServer",
                @"D:\SteamLibrary\steamapps\common\PalServer",
                @"D:\Steam\steamapps\common\PalServer",
                @"D:\PalworldServer",
                @"E:\SteamLibrary\steamapps\common\PalServer",
                @"E:\PalworldServer",
                @"F:\SteamLibrary\steamapps\common\PalServer"
            };

            foreach (var path in standardServerPaths)
            {
                if (IsValidServerDirectory(path))
                    return path;
            }

            // 4. Fallback: Check if PalServer.exe exists in game client directory
            var clientPath = DetectGameDirectory();
            if (!string.IsNullOrWhiteSpace(clientPath) && IsValidServerDirectory(clientPath))
            {
                return clientPath;
            }

            return null;
        }

        public bool IsValidServerDirectory(string? path)
        {
            if (string.IsNullOrWhiteSpace(path) || !Directory.Exists(path))
                return false;

            return File.Exists(Path.Combine(path, "PalServer.exe")) ||
                   File.Exists(Path.Combine(path, ServerExecutableRelativePath));
        }

        public bool StartDedicatedServer(string serverDirectory, string arguments)
        {
            if (IsServerRunning) return true;
            _serverProcess?.Dispose();
            _serverProcess = null;

            string palServerExe = Path.Combine(serverDirectory, "PalServer.exe");
            string shippingExe = Path.Combine(serverDirectory, ServerExecutableRelativePath);

            string exePath;
            string workingDir;
            string launchArgs;

            if (File.Exists(palServerExe))
            {
                exePath = palServerExe;
                workingDir = serverDirectory;
                launchArgs = string.IsNullOrWhiteSpace(arguments) 
                    ? "-useperfthreads -NoAsyncLoadingThread -USEALLAVAILABLECORES" 
                    : $"{arguments} -useperfthreads -NoAsyncLoadingThread -USEALLAVAILABLECORES";
            }
            else if (File.Exists(shippingExe))
            {
                exePath = shippingExe;
                workingDir = Path.GetDirectoryName(shippingExe) ?? serverDirectory;
                launchArgs = string.IsNullOrWhiteSpace(arguments) 
                    ? "Pal -useperfthreads -NoAsyncLoadingThread -USEALLAVAILABLECORES" 
                    : $"Pal {arguments} -useperfthreads -NoAsyncLoadingThread -USEALLAVAILABLECORES";
            }
            else
            {
                return false;
            }

            var startInfo = new ProcessStartInfo
            {
                FileName = exePath,
                Arguments = launchArgs,
                WorkingDirectory = workingDir,
                UseShellExecute = true
            };

            try
            {
                _serverProcess = Process.Start(startInfo);
                if (_serverProcess != null)
                {
                    try
                    {
                        _serverProcess.EnableRaisingEvents = true;
                        _serverProcess.Exited += (s, e) =>
                        {
                            ServerStateChanged?.Invoke(false);
                        };
                    }
                    catch { }

                    ServerStateChanged?.Invoke(true);
                    return true;
                }
            }
            catch (Exception ex)
            {
                Debug.WriteLine($"Failed to start dedicated server: {ex.Message}");
                return false;
            }

            return false;
        }

        public void StopDedicatedServer()
        {
            try
            {
                if (_serverProcess != null && !_serverProcess.HasExited)
                {
                    _serverProcess.Kill(entireProcessTree: true);
                    _serverProcess.Dispose();
                    _serverProcess = null;
                }

                // Also kill any lingering PalServer / PalServer-Win64-Shipping processes
                var processes = Process.GetProcessesByName(ServerProcessName)
                    .Concat(Process.GetProcessesByName(AlternateServerProcessName))
                    .ToArray();

                foreach (var p in processes)
                {
                    try
                    {
                        if (!p.HasExited)
                        {
                            p.Kill(entireProcessTree: true);
                        }
                    }
                    catch { }
                    finally
                    {
                        p.Dispose();
                    }
                }
            }
            catch { }
            finally
            {
                ServerStateChanged?.Invoke(false);
            }
        }

        /// <summary>
        /// Attempts to auto-detect the Palworld game installation directory via Steam Registry and VDF library files.
        /// </summary>
        public string? DetectGameDirectory()
        {
            // 1. Check Steam Registry
            var steamPath = GetSteamInstallPath();
            if (!string.IsNullOrEmpty(steamPath) && Directory.Exists(steamPath))
            {
                // Check primary library
                string primaryGameDir = Path.Combine(steamPath, "steamapps", "common", "Palworld");
                if (IsValidGameDirectory(primaryGameDir))
                    return primaryGameDir;

                // Parse libraryfolders.vdf
                string libraryFoldersVdf = Path.Combine(steamPath, "steamapps", "libraryfolders.vdf");
                if (File.Exists(libraryFoldersVdf))
                {
                    var extraLibraries = ParseLibraryFolders(libraryFoldersVdf);
                    foreach (var lib in extraLibraries)
                    {
                        string gameDir = Path.Combine(lib, "steamapps", "common", "Palworld");
                        if (IsValidGameDirectory(gameDir))
                            return gameDir;
                    }
                }
            }

            // 2. Fallback: Search common drive roots
            var standardPaths = new[]
            {
                @"C:\Program Files (x86)\Steam\steamapps\common\Palworld",
                @"C:\Program Files\Steam\steamapps\common\Palworld",
                @"C:\SteamLibrary\steamapps\common\Palworld",
                @"D:\SteamLibrary\steamapps\common\Palworld",
                @"D:\Steam\steamapps\common\Palworld",
                @"E:\SteamLibrary\steamapps\common\Palworld",
                @"E:\Steam\steamapps\common\Palworld",
                @"F:\SteamLibrary\steamapps\common\Palworld",
                @"G:\SteamLibrary\steamapps\common\Palworld"
            };

            foreach (var path in standardPaths)
            {
                if (IsValidGameDirectory(path))
                    return path;
            }

            return null;
        }

        public bool IsValidGameDirectory(string? path)
        {
            if (string.IsNullOrWhiteSpace(path) || !Directory.Exists(path))
                return false;

            string exePath = Path.Combine(path, ExecutableRelativePath);
            return File.Exists(exePath);
        }

        private static string? GetSteamInstallPath()
        {
            if (!RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
                return null;

            try
            {
                using var key = Registry.CurrentUser.OpenSubKey(@"Software\Valve\Steam");
                if (key?.GetValue("SteamPath") is string steamPath)
                    return steamPath.Replace('/', '\\');

                using var localKey = Registry.LocalMachine.OpenSubKey(@"SOFTWARE\Valve\Steam") ??
                                     Registry.LocalMachine.OpenSubKey(@"SOFTWARE\WOW6432Node\Valve\Steam");
                if (localKey?.GetValue("InstallPath") is string installPath)
                    return installPath.Replace('/', '\\');
            }
            catch (Exception)
            {
                // Registry read permission or missing key
            }

            return null;
        }

        private static List<string> ParseLibraryFolders(string vdfPath)
        {
            var libraries = new List<string>();
            try
            {
                string text = File.ReadAllText(vdfPath);
                // Matches "path"		"D:\\SteamLibrary"
                var matches = Regex.Matches(text, @"\""path\""\s+\""([^\""]+)\""", RegexOptions.IgnoreCase);
                foreach (Match match in matches)
                {
                    if (match.Groups.Count > 1)
                    {
                        string path = match.Groups[1].Value.Replace(@"\\", @"\");
                        if (Directory.Exists(path))
                        {
                            libraries.Add(path);
                        }
                    }
                }
            }
            catch (Exception)
            {
                // Ignore parse errors
            }

            return libraries.Distinct(StringComparer.OrdinalIgnoreCase).ToList();
        }

        /// <summary>
        /// Launches the Palworld game executable directly or via Steam URI protocol, and monitors its lifecycle.
        /// </summary>
        public Task<bool> LaunchGameAsync(
            string gameDirectory,
            string? serverIp = null,
            int serverPort = 8211,
            bool useSteamProtocol = false,
            CancellationToken cancellationToken = default)
        {
            if (IsGameRunning)
                return Task.FromResult(false);

            string palworldExe = Path.Combine(gameDirectory, "Palworld.exe");
            string shippingExe = Path.Combine(gameDirectory, ExecutableRelativePath);
            string exePath = File.Exists(palworldExe) ? palworldExe : shippingExe;
            Process? gameProcess = null;

            try
            {
                if (!useSteamProtocol && File.Exists(exePath))
                {
                    // Launch with multi-threaded performance flags
                    string extraArgs = "-useperfthreads -NoAsyncLoadingThread -USEALLAVAILABLECORES";
                    string arguments = string.IsNullOrWhiteSpace(serverIp)
                        ? extraArgs
                        : $"{serverIp}:{serverPort} {extraArgs}";

                    var startInfo = new ProcessStartInfo
                    {
                        FileName = exePath,
                        Arguments = arguments,
                        WorkingDirectory = File.Exists(palworldExe) ? gameDirectory : Path.GetDirectoryName(shippingExe),
                        UseShellExecute = true
                    };

                    gameProcess = Process.Start(startInfo);
                }
                else
                {
                    // Fallback to Steam URI Protocol
                    string steamUri = $"steam://rungameid/{PalworldAppId}";
                    using var steamLauncherProcess = Process.Start(new ProcessStartInfo
                    {
                        FileName = steamUri,
                        UseShellExecute = true
                    });
                }

                IsGameRunning = true;
                GameStarted?.Invoke();

                // Monitor process in background
                _ = MonitorGameProcessAsync(gameProcess, cancellationToken);
                return Task.FromResult(true);
            }
            catch (Exception)
            {
                IsGameRunning = false;
                throw;
            }
        }

        private async Task MonitorGameProcessAsync(Process? directProcess, CancellationToken cancellationToken)
        {
            Process? detectedProcess = null;
            try
            {
                if (directProcess != null && !directProcess.HasExited)
                {
                    await directProcess.WaitForExitAsync(cancellationToken);
                }
                else
                {
                    // Wait for process to appear if launched via Steam URI
                    for (int i = 0; i < 30; i++)
                    {
                        if (cancellationToken.IsCancellationRequested) break;
                        await Task.Delay(1000, cancellationToken);

                        var processes = Process.GetProcessesByName(MainProcessName)
                            .Concat(Process.GetProcessesByName(AlternateProcessName))
                            .ToArray();

                        if (processes.Length > 0)
                        {
                            detectedProcess = processes[0];
                            foreach (var process in processes.Skip(1)) process.Dispose();
                            break;
                        }
                    }

                    if (detectedProcess != null)
                    {
                        try { detectedProcess.PriorityClass = ProcessPriorityClass.High; } catch { }
                        await detectedProcess.WaitForExitAsync(cancellationToken);
                    }
                }
            }
            catch (Exception)
            {
                // Process monitor ended or was cancelled
            }
            finally
            {
                directProcess?.Dispose();
                detectedProcess?.Dispose();
                IsGameRunning = false;
                GameExited?.Invoke();
            }
        }
    }
}
