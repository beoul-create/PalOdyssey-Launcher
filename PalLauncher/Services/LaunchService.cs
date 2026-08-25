using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.IO;
using System.Text;
using System.Threading.Tasks;
using PalLauncher.Models;
using PalLauncher.Services.Interfaces;

namespace PalLauncher.Services
{
    public class LaunchService : ILaunchService
    {
        private readonly ILogService _logService;
        private readonly ICrashLogService? _crashLogService;
        private Process? _runningClientProcess;
        private Process? _runningServerProcess;
        private Process? _runningTunnelProcess;
        private GameProcessState _currentState = new();

        public GameProcessState CurrentState => _currentState;
        public bool IsGameRunning => IsClientRunning;

        public bool IsServerRunning => (_runningServerProcess != null && !_runningServerProcess.HasExited) ||
                                       GetActiveServerProcesses().Count > 0;

        public bool IsClientRunning => (_runningClientProcess != null && !_runningClientProcess.HasExited) ||
                                       GetActiveClientProcesses().Count > 0;

        public static List<Process> GetActiveServerProcesses()
        {
            var results = new List<Process>();
            string[] targetNames = { "PalServer", "PalServer-Win64-Shipping", "PalServer-Win64-Shipping-Cmd" };
            foreach (var name in targetNames)
            {
                try
                {
                    var procs = Process.GetProcessesByName(name);
                    foreach (var p in procs)
                    {
                        if (!p.HasExited)
                        {
                            results.Add(p);
                        }
                    }
                }
                catch { }
            }
            return results;
        }

        public static List<Process> GetActiveClientProcesses()
        {
            var results = new List<Process>();
            string[] targetNames = { "Palworld", "Palworld-Win64-Shipping" };
            foreach (var name in targetNames)
            {
                try
                {
                    var procs = Process.GetProcessesByName(name);
                    foreach (var p in procs)
                    {
                        if (!p.HasExited)
                        {
                            results.Add(p);
                        }
                    }
                }
                catch { }
            }
            return results;
        }

        public event EventHandler<GameProcessState>? ProcessStateChanged;
        public event EventHandler<int>? ProcessExited;

        public LaunchService(ILogService logService, ICrashLogService? crashLogService = null)
        {
            _logService = logService;
            _crashLogService = crashLogService;
        }

        private CancellationTokenSource? _serverLogCts;

        public string BuildServerCommandLineArguments(LauncherConfig config)
        {
            var args = new List<string>();
            int gamePort = (config.ServerPort > 0 && config.ServerPort != 8212 && config.ServerPort != 8215) ? config.ServerPort : 8211;
            args.Add($"-port={gamePort}");
            args.Add($"-publicport={gamePort}");
            args.Add("-queryport=27016");
            args.Add("-publicqueryport=27016");
            args.Add("-players=32");
            args.Add("-log");
            args.Add("-useperfthreads");
            args.Add("-NoAsyncLoadingThread");
            args.Add("-USEALLAVAILABLECORES");
            args.Add("-malloc=system");
            args.Add("-NoVerifyGC");
            return string.Join(" ", args);
        }

        public string BuildCommandLineArguments(LauncherConfig config)
        {
            var args = new List<string>();

            // 1. Suppress engine crash popup dialogs & unattended execution
            args.Add("-NoCrashReporter");

            // 2. Resource & Performance Optimization Flags
            args.Add("-USEALLAVAILABLECORES");
            args.Add("-useperfthreads");
            args.Add("-malloc=system");
            args.Add("-NoVerifyGC");

            // 3. Predefined Performance & Engine Flags
            if (config.UseDirectX11) args.Add("-dx11");
            if (config.NoSplash) args.Add("-nosplash");
            if (config.UseHighPriority) args.Add("-high");
            if (config.WindowedMode) args.Add("-windowed");

            // 4. Custom User Startup Flags
            if (!string.IsNullOrWhiteSpace(config.CustomArguments))
            {
                args.Add(config.CustomArguments.Trim());
            }

            return string.Join(" ", args);
        }

        public async Task<bool> LaunchGameAsync(LauncherConfig config, GamePathInfo pathInfo)
        {
            bool launchServer = config.LaunchMode.Equals("Server", StringComparison.OrdinalIgnoreCase) || config.LaunchServerWithGame;
            bool launchClient = !config.LaunchMode.Equals("Server", StringComparison.OrdinalIgnoreCase);

            if (launchClient && IsClientRunning)
            {
                _logService.LogWarning("Palworld game client is already running.", "Launcher");
                return false;
            }

            if (!launchClient && launchServer && IsServerRunning)
            {
                _logService.LogWarning("Palworld dedicated server is already running.", "Launcher");
                return false;
            }

            if (!pathInfo.IsValid)
            {
                _logService.LogError("Cannot launch: Palworld installation path is invalid or not detected.", "Launcher");
                return false;
            }

            return await Task.Run(() =>
            {
                try
                {
                    bool serverLaunched = false;
                    bool clientLaunched = false;

                    // 1. Launch Dedicated Server if requested and available
                    if (launchServer)
                    {
                        // Check if an existing PalServer instance is already running
                        Process? existingServer = null;
                        if (_runningServerProcess != null && !_runningServerProcess.HasExited)
                        {
                            existingServer = _runningServerProcess;
                        }
                        else
                        {
                            var activeServers = Process.GetProcesses().Where(p =>
                                p.ProcessName.Equals("PalServer", StringComparison.OrdinalIgnoreCase) ||
                                p.ProcessName.Equals("PalServer-Win64-Shipping-Cmd", StringComparison.OrdinalIgnoreCase) ||
                                p.ProcessName.Equals("PalServer-Win64-Shipping", StringComparison.OrdinalIgnoreCase)).ToList();
                            if (activeServers.Any())
                            {
                                existingServer = activeServers.First();
                            }
                        }

                        if (existingServer != null)
                        {
                            _runningServerProcess = existingServer;
                            serverLaunched = true;
                            _logService.LogInfo($"Palworld Dedicated Server is already active (PID: {existingServer.Id}). Skipping duplicate server spawn.", "PalServer");
                            StartPlayitTunnel(config);
                        }
                        else
                        {
                            string serverExe = "";
                            string serverRoot = Directory.Exists(Path.Combine(pathInfo.GameRootPath, "..", "PalServer"))
                                ? Path.GetFullPath(Path.Combine(pathInfo.GameRootPath, "..", "PalServer"))
                                : pathInfo.GameRootPath;

                            string shippingCmd = Path.Combine(serverRoot, "Pal", "Binaries", "Win64", "PalServer-Win64-Shipping-Cmd.exe");
                            string shippingExe = Path.Combine(serverRoot, "Pal", "Binaries", "Win64", "PalServer-Win64-Shipping.exe");
                            string rootServerExe = Path.Combine(serverRoot, "PalServer.exe");

                            bool isDirectEngineBinary = false;
                            if (File.Exists(rootServerExe))
                            {
                                serverExe = rootServerExe;
                            }
                            else if (File.Exists(shippingCmd))
                            {
                                serverExe = shippingCmd;
                                isDirectEngineBinary = true;
                            }
                            else if (File.Exists(shippingExe))
                            {
                                serverExe = shippingExe;
                                isDirectEngineBinary = true;
                            }
                            else if (File.Exists(pathInfo.ServerExecutablePath))
                            {
                                serverExe = pathInfo.ServerExecutablePath;
                            }

                            if (File.Exists(serverExe))
                            {
                                // Apply automatic server stability optimizations & backup pruning
                                try
                                {
                                    var saveService = new PalSaveService(_logService);
                                    _ = saveService.ApplyServerStabilityAndNetworkOptimizationsAsync(serverRoot);
                                    _ = saveService.PruneExcessBackupsAsync(maxBackupsToKeep: 24);
                                }
                                catch { }

                                string serverArgs = BuildServerCommandLineArguments(config);
                                if (isDirectEngineBinary)
                                {
                                    serverArgs = "Pal " + serverArgs;
                                }
                                string serverWorkDir = isDirectEngineBinary ? (Path.GetDirectoryName(serverExe) ?? serverRoot) : serverRoot;

                                _logService.LogInfo($"Launching PalServer: {Path.GetFileName(serverExe)} args: '{serverArgs}'", "PalServer");

                                var sStartInfo = new ProcessStartInfo
                                {
                                    FileName = serverExe,
                                    Arguments = serverArgs,
                                    WorkingDirectory = serverWorkDir,
                                    UseShellExecute = true,
                                    WindowStyle = ProcessWindowStyle.Minimized
                                };

                                var sProcess = new Process
                                {
                                    StartInfo = sStartInfo,
                                    EnableRaisingEvents = true
                                };

                                if (sProcess.Start())
                                {
                                    serverLaunched = true;
                                    _runningServerProcess = sProcess;

                                    // Continually poll for spawned child engine process (PalServer-Win64-Shipping-Cmd.exe)
                                    Task.Run(async () =>
                                    {
                                        for (int i = 0; i < 10; i++)
                                        {
                                            await Task.Delay(1000);
                                            var procs = GetActiveServerProcesses();
                                            var actualServer = procs.FirstOrDefault(p => p.ProcessName.Contains("Shipping", StringComparison.OrdinalIgnoreCase));
                                            if (actualServer != null)
                                            {
                                                _runningServerProcess = actualServer;
                                                try
                                                {
                                                    actualServer.EnableRaisingEvents = true;
                                                    actualServer.Exited += (aeSender, aeE) =>
                                                    {
                                                        if (GetActiveServerProcesses().Count == 0)
                                                        {
                                                            _logService.LogInfo($"Dedicated server engine process (PID: {actualServer.Id}) terminated.", "PalServer");
                                                            StopPlayitTunnel();
                                                            UpdateProcessState();
                                                        }
                                                    };
                                                }
                                                catch { }
                                                break;
                                            }
                                        }
                                    });

                                    sProcess.Exited += (s, e) =>
                                    {
                                        Task.Delay(3000).ContinueWith(_ =>
                                        {
                                            if (GetActiveServerProcesses().Count == 0)
                                            {
                                                _logService.LogInfo($"Dedicated server process (PID: {sProcess.Id}) terminated.", "PalServer");
                                                StopPlayitTunnel();
                                                UpdateProcessState();
                                            }
                                        });
                                    };

                                    _serverLogCts?.Cancel();
                                    _serverLogCts = new CancellationTokenSource();
                                    StartServerLogFileTailer(serverRoot, _serverLogCts.Token);

                                    _logService.LogSuccess($"Palworld Dedicated Server online on port {config.ServerPort} (PID: {sProcess.Id})", "PalServer");
                                    StartPlayitTunnel(config);
                                }
                            }
                        }
                    }

                    // 2. Launch Game Client if requested
                    if (launchClient)
                    {
                        string clientExe;
                        if (!string.IsNullOrEmpty(pathInfo.ShippingExecutablePath) && File.Exists(pathInfo.ShippingExecutablePath))
                        {
                            clientExe = pathInfo.ShippingExecutablePath;
                        }
                        else if (!string.IsNullOrEmpty(pathInfo.ClientExecutablePath) && File.Exists(pathInfo.ClientExecutablePath))
                        {
                            clientExe = pathInfo.ClientExecutablePath;
                        }
                        else
                        {
                            clientExe = Path.Combine(pathInfo.GameRootPath, config.GameExecutableName);
                        }

                        if (File.Exists(clientExe))
                        {
                            string clientArgs = BuildCommandLineArguments(config);
                            string clientWorkDir = Path.GetDirectoryName(clientExe) ?? pathInfo.GameRootPath;

                            // 2a. Purge any stale Unreal Engine crash logs so the game never prompts about previous crashes
                            PurgeStaleCrashFlags(pathInfo.GameRootPath);

                            // 2b. Ensure direct raw mouse input (2000Hz-8000Hz) is configured if enabled
                            if (config.EnableRawInputOptimization)
                            {
                                EnsureDirectRawInputConfig(config, pathInfo.GameRootPath);
                            }

                            // 2c. Inject steam_appid.txt (AppId: 1623730) into game root and Win64 binaries directory
                            try
                            {
                                string appIdContent = "1623730";
                                string appIdPath1 = Path.Combine(clientWorkDir, "steam_appid.txt");
                                string appIdPath2 = Path.Combine(pathInfo.GameRootPath, "steam_appid.txt");
                                string appIdPath3 = Path.Combine(pathInfo.GameRootPath, @"Pal\Binaries\Win64\steam_appid.txt");

                                if (!File.Exists(appIdPath1)) File.WriteAllText(appIdPath1, appIdContent);
                                if (!File.Exists(appIdPath2)) File.WriteAllText(appIdPath2, appIdContent);
                                if (Directory.Exists(Path.GetDirectoryName(appIdPath3)) && !File.Exists(appIdPath3))
                                {
                                    File.WriteAllText(appIdPath3, appIdContent);
                                }
                            }
                            catch { }

                            // 2d. Ensure Steam client is running beforehand so Steamworks API and EOS auth subsystems bind automatically
                            bool isSteamRunning = Process.GetProcessesByName("steam").Length > 0;
                            if (!isSteamRunning)
                            {
                                _logService.LogInfo("Steam is not currently running. Starting Steam client to initialize EOS and Online Subsystem auth tokens...", "Launcher");
                                try
                                {
                                    Process.Start(new ProcessStartInfo
                                    {
                                        FileName = "steam://open/main",
                                        UseShellExecute = true
                                    });
                                    Thread.Sleep(2000);
                                }
                                catch (Exception ex)
                                {
                                    _logService.LogWarning($"Could not auto-start Steam: {ex.Message}", "Launcher");
                                }
                            }

                            // 2e. Launch Palworld directly with SteamAppId environment variables (Bypasses Steam custom argument prompt while binding full EOS/Steam DRM Auth)
                            _logService.LogInfo($"Launching Palworld Client directly: {Path.GetFileName(clientExe)} args: '{clientArgs}'", "Launcher");

                            var cStartInfo = new ProcessStartInfo
                            {
                                FileName = clientExe,
                                Arguments = clientArgs,
                                WorkingDirectory = clientWorkDir,
                                UseShellExecute = false
                            };

                            // Inject Steam App IDs into process environment
                            cStartInfo.EnvironmentVariables["SteamAppId"] = "1623730";
                            cStartInfo.EnvironmentVariables["SteamGameId"] = "1623730";
                            cStartInfo.EnvironmentVariables["SteamOverlayGameId"] = "1623730";

                            var cProcess = new Process
                            {
                                StartInfo = cStartInfo,
                                EnableRaisingEvents = true
                            };

                            cProcess.Exited += async (s, e) =>
                            {
                                int exitCode = -1;
                                try { exitCode = cProcess.ExitCode; } catch { }
                                _logService.LogInfo($"Game client process (PID: {cProcess.Id}) closed (ExitCode: {exitCode}).", "Launcher");
                                UpdateProcessState();

                                if (exitCode != 0 && _crashLogService != null)
                                {
                                    try
                                    {
                                        await Task.Delay(1200); // Allow Unreal CrashReporter to finish writing files
                                        var crash = await _crashLogService.GetLatestCrashReportAsync(pathInfo.GameRootPath);
                                        if (crash != null && (DateTime.Now - crash.Timestamp).TotalMinutes < 2)
                                        {
                                            _logService.LogError($"[CRASH DETECTED] {crash.PrimaryModule}: {crash.ErrorMessage}", "CrashWatcher");
                                            if (!string.IsNullOrEmpty(crash.SuggestedFix))
                                            {
                                                _logService.LogWarning($"[CRASH ADVICE] {crash.SuggestedFix}", "CrashWatcher");
                                            }
                                        }
                                    }
                                    catch { }
                                }
                            };

                            if (cProcess.Start())
                            {
                                _runningClientProcess = cProcess;
                                clientLaunched = true;
                                _logService.LogSuccess($"Palworld Client launched successfully with Steamworks API & EOS Auth bindings! (PID: {cProcess.Id})", "Launcher");
                            }
                        }
                    }

                    UpdateProcessState();
                    return serverLaunched || clientLaunched;
                }
                catch (Exception ex)
                {
                    _logService.LogError("Exception occurred during unified launch.", "Launcher", ex);
                    return false;
                }
            });
        }

        private void UpdateProcessState()
        {
            bool serverRunning = IsServerRunning;
            bool clientRunning = IsClientRunning;
            bool isRunning = clientRunning || serverRunning;

            int clientPid = (_runningClientProcess != null && !_runningClientProcess.HasExited)
                ? _runningClientProcess.Id
                : (GetActiveClientProcesses().Count > 0 ? GetActiveClientProcesses()[0].Id : 0);

            int serverPid = (_runningServerProcess != null && !_runningServerProcess.HasExited)
                ? _runningServerProcess.Id
                : (GetActiveServerProcesses().Count > 0 ? GetActiveServerProcesses()[0].Id : 0);

            _currentState = new GameProcessState
            {
                IsRunning = isRunning,
                IsClientRunning = clientRunning,
                IsServerRunning = serverRunning,
                ProcessId = clientPid > 0 ? clientPid : serverPid,
                ServerProcessId = serverPid,
                StartTime = isRunning ? (_currentState.StartTime ?? DateTime.Now) : null,
                Mode = (clientRunning && serverRunning) ? "Client + Server" : (serverRunning ? "Server" : "Client")
            };

            ProcessStateChanged?.Invoke(this, _currentState);
            if (!isRunning)
            {
                ProcessExited?.Invoke(this, 0);
            }
        }

        private void ParseAndLogServerOutput(string rawLine)
        {
            if (string.IsNullOrWhiteSpace(rawLine)) return;

            string line = rawLine.Trim();

            if (line.Contains("[Error]", StringComparison.OrdinalIgnoreCase) ||
                line.Contains("Fatal error", StringComparison.OrdinalIgnoreCase) ||
                line.Contains("Assertion failed", StringComparison.OrdinalIgnoreCase))
            {
                _logService.LogError(line, "PalServer");
            }
            else if (line.Contains("[Warning]", StringComparison.OrdinalIgnoreCase) ||
                     line.Contains("LogSockets: Warning", StringComparison.OrdinalIgnoreCase))
            {
                _logService.LogWarning(line, "PalServer");
            }
            else if (line.Contains("Steam Dedicated Server API", StringComparison.OrdinalIgnoreCase) ||
                     line.Contains("Server has started", StringComparison.OrdinalIgnoreCase) ||
                     line.Contains("Listening on port", StringComparison.OrdinalIgnoreCase) ||
                     line.Contains("Init: World", StringComparison.OrdinalIgnoreCase))
            {
                _logService.LogSuccess(line, "PalServer");
            }
            else
            {
                _logService.LogInfo(line, "PalServer");
            }
        }

        private void StartServerLogFileTailer(string gameRoot, CancellationToken ct)
        {
            Task.Run(async () =>
            {
                try
                {
                    string logsDir = Path.Combine(gameRoot, "Pal", "Saved", "Logs");
                    if (!Directory.Exists(logsDir))
                    {
                        await Task.Delay(2000, ct);
                    }

                    string[] candidateLogNames = { "PalServer.log", "Pal.log", "PalServer-Win64-Shipping.log" };
                    string? targetLogFile = null;

                    // Wait up to 10 seconds for Unreal to create the log file
                    for (int i = 0; i < 10 && !ct.IsCancellationRequested; i++)
                    {
                        if (Directory.Exists(logsDir))
                        {
                            foreach (var name in candidateLogNames)
                            {
                                string candidate = Path.Combine(logsDir, name);
                                if (File.Exists(candidate))
                                {
                                    targetLogFile = candidate;
                                    break;
                                }
                            }
                        }
                        if (targetLogFile != null) break;
                        await Task.Delay(1000, ct);
                    }

                    if (targetLogFile == null || !File.Exists(targetLogFile)) return;

                    _logService.LogInfo($"Connected live log tailer to disk: {Path.GetFileName(targetLogFile)}", "PalServer");

                    using var fs = new FileStream(targetLogFile, FileMode.Open, FileAccess.Read, FileShare.ReadWrite);
                    using var reader = new StreamReader(fs, Encoding.UTF8);

                    // Move to end of existing file so we only stream new sessions
                    fs.Seek(0, SeekOrigin.End);

                    while (!ct.IsCancellationRequested)
                    {
                        string? line = await reader.ReadLineAsync(ct);
                        if (line != null)
                        {
                            if (!string.IsNullOrWhiteSpace(line))
                            {
                                ParseAndLogServerOutput(line);
                            }
                        }
                        else
                        {
                            await Task.Delay(250, ct);
                        }
                    }
                }
                catch (OperationCanceledException) { }
                catch (Exception ex)
                {
                    _logService.LogWarning("Disk log tailer stopped.", "PalServer", ex.Message);
                }
            }, ct);
        }

        public async Task<bool> StopGameAsync()
        {
            _serverLogCts?.Cancel();
            _serverLogCts = null;

            return await Task.Run(() =>
            {
                try
                {
                    // 1. Stop Client Process
                    if (_runningClientProcess != null && !_runningClientProcess.HasExited)
                    {
                        _logService.LogInfo($"Stopping game client (PID: {_runningClientProcess.Id})...", "Launcher");
                        try
                        {
                            _runningClientProcess.CloseMainWindow();
                            if (!_runningClientProcess.WaitForExit(3000))
                            {
                                _runningClientProcess.Kill(true);
                            }
                        }
                        catch { }
                        _runningClientProcess = null;
                    }

                    // Sweep any active game client processes
                    foreach (var cp in GetActiveClientProcesses())
                    {
                        try
                        {
                            _logService.LogInfo($"Stopping active Palworld client (PID: {cp.Id})...", "Launcher");
                            cp.CloseMainWindow();
                            if (!cp.WaitForExit(1500))
                            {
                                cp.Kill(true);
                            }
                        }
                        catch { }
                    }

                    // 2. Stop Server Process
                    if (_runningServerProcess != null && !_runningServerProcess.HasExited)
                    {
                        _logService.LogInfo($"Stopping dedicated server (PID: {_runningServerProcess.Id})...", "PalServer");
                        try
                        {
                            _runningServerProcess.Kill(true);
                        }
                        catch { }
                        _runningServerProcess = null;
                    }

                    // Sweep all active dedicated server processes (including terminal / console instances)
                    foreach (var sp in GetActiveServerProcesses())
                    {
                        try
                        {
                            _logService.LogInfo($"Terminating dedicated server process (PID: {sp.Id} - {sp.ProcessName})...", "PalServer");
                            sp.Kill(true);
                        }
                        catch { }
                    }

                    // 3. Suppress and terminate any Unreal Engine CrashReportClient dialogs
                    foreach (var crp in Process.GetProcessesByName("CrashReportClient"))
                    {
                        try { crp.Kill(true); } catch { }
                    }
                    foreach (var crp in Process.GetProcessesByName("CrashReportClient-Win64-Shipping"))
                    {
                        try { crp.Kill(true); } catch { }
                    }

                    // 4. Stop Playit.gg Cloud Tunnel in sync
                    StopPlayitTunnel();

                    UpdateProcessState();
                    _logService.LogSuccess("All processes stopped.", "Launcher");
                    return true;
                }
                catch (Exception ex)
                {
                    _logService.LogError("Failed to stop processes.", "Launcher", ex);
                    return false;
                }
            });
        }

        public void PurgeStaleCrashFlags(string? gameRootPath)
        {
            try
            {
                string localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
                if (!string.IsNullOrEmpty(localAppData))
                {
                    string appDataCrashDir = Path.Combine(localAppData, "Pal", "Saved", "Crashes");
                    if (Directory.Exists(appDataCrashDir))
                    {
                        foreach (var d in Directory.GetDirectories(appDataCrashDir))
                        {
                            try { Directory.Delete(d, true); } catch { }
                        }
                        foreach (var f in Directory.GetFiles(appDataCrashDir))
                        {
                            try { File.Delete(f); } catch { }
                        }
                    }

                    string appDataLogsDir = Path.Combine(localAppData, "Pal", "Saved", "Logs");
                    if (Directory.Exists(appDataLogsDir))
                    {
                        foreach (var f in Directory.GetFiles(appDataLogsDir, "*.dmp"))
                        {
                            try { File.Delete(f); } catch { }
                        }
                    }
                }

                if (!string.IsNullOrEmpty(gameRootPath) && Directory.Exists(gameRootPath))
                {
                    string ue4ssDir = Path.Combine(gameRootPath, "Pal", "Binaries", "Win64", "ue4ss");
                    if (Directory.Exists(ue4ssDir))
                    {
                        foreach (var f in Directory.GetFiles(ue4ssDir, "*.dmp"))
                        {
                            try { File.Delete(f); } catch { }
                        }
                    }
                }
            }
            catch { }
        }

        public bool EnsureDirectRawInputConfig(LauncherConfig config, string? gameRootPath)
        {
            if (!config.EnableRawInputOptimization) return false;

            try
            {
                var targetPaths = new List<string>();

                // 1. %LOCALAPPDATA%\Pal\Saved\Config\Windows\Engine.ini (and subvariants)
                string localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
                if (!string.IsNullOrEmpty(localAppData))
                {
                    string[] subfolders = { "Windows", "WindowsClient", "WindowsNoEditor" };
                    foreach (var sub in subfolders)
                    {
                        string dir = Path.Combine(localAppData, "Pal", "Saved", "Config", sub);
                        targetPaths.Add(Path.Combine(dir, "Engine.ini"));
                    }
                }

                // 2. Game directory configs if present
                if (!string.IsNullOrEmpty(gameRootPath) && Directory.Exists(gameRootPath))
                {
                    string[] subfolders = { "Windows", "WindowsClient", "WindowsNoEditor" };
                    foreach (var sub in subfolders)
                    {
                        string dir = Path.Combine(gameRootPath, "Pal", "Saved", "Config", sub);
                        targetPaths.Add(Path.Combine(dir, "Engine.ini"));
                    }
                }

                bool appliedAny = false;
                foreach (var iniPath in targetPaths)
                {
                    string? dir = Path.GetDirectoryName(iniPath);
                    if (string.IsNullOrEmpty(dir)) continue;

                    // Create or update if the directory exists or if it's the primary Windows config folder
                    bool isPrimary = dir.EndsWith(@"Pal\Saved\Config\Windows", StringComparison.OrdinalIgnoreCase);
                    if (!Directory.Exists(dir) && !isPrimary) continue;

                    if (!Directory.Exists(dir))
                    {
                        Directory.CreateDirectory(dir);
                    }

                    string content = File.Exists(iniPath) ? File.ReadAllText(iniPath) : "";
                    string updated = InjectRawInputSettingsIntoIni(content);
                    if (!string.Equals(content, updated, StringComparison.Ordinal))
                    {
                        File.WriteAllText(iniPath, updated, Encoding.UTF8);
                        appliedAny = true;
                    }
                }

                if (appliedAny)
                {
                    _logService.LogSuccess("Configured direct raw mouse input and zero smoothing in Engine.ini (2000Hz-8000Hz ready).", "InputOptimizer");
                }
                return true;
            }
            catch (Exception ex)
            {
                _logService.LogWarning("Notice during raw input Engine.ini configuration.", "InputOptimizer", ex.Message);
                return false;
            }
        }

        public static string InjectRawInputSettingsIntoIni(string iniContent)
        {
            var lines = string.IsNullOrWhiteSpace(iniContent)
                ? new List<string>()
                : new List<string>(iniContent.Split(new[] { "\r\n", "\r", "\n" }, StringSplitOptions.None));

            // 1. Raw Input Settings
            InjectSectionIntoIniLines(lines, "[/Script/Engine.InputSettings]", new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
            {
                { "RawMouseInputEnabled", "RawMouseInputEnabled=True" },
                { "bEnableMouseSmoothing", "bEnableMouseSmoothing=False" },
                { "bViewAccelerationEnabled", "bViewAccelerationEnabled=False" },
                { "bDisableMouseAcceleration", "bDisableMouseAcceleration=True" },
                { "bUseMousePositionLocking", "bUseMousePositionLocking=True" }
            });

            // 2. Engine & Slate Hardware Cursor Fluidity (Zero-Lag UI & Menu Cursor)
            InjectSectionIntoIniLines(lines, "[/Script/Engine.Engine]", new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
            {
                { "bEnableMouseSmoothing", "bEnableMouseSmoothing=False" },
                { "bUseRawMouseInput", "bUseRawMouseInput=True" }
            });

            InjectSectionIntoIniLines(lines, "[/Script/Slate.SlateSettings]", new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
            {
                { "bUseHardwareCursor", "bUseHardwareCursor=True" },
                { "bEnableHardwareCursor", "bEnableHardwareCursor=True" },
                { "bVirtualCursor", "bVirtualCursor=False" },
                { "bAllowHardwareCursor", "bAllowHardwareCursor=True" }
            });

            // 3. Resource, Render & Zero-Latency Slate Settings
            InjectSectionIntoIniLines(lines, "[SystemSettings]", new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
            {
                { "Slate.EnableMouseSmoother", "Slate.EnableMouseSmoother=0" },
                { "Slate.EnableRenderHardwareCursor", "Slate.EnableRenderHardwareCursor=1" },
                { "Slate.UseHardwareCursor", "Slate.UseHardwareCursor=1" },
                { "Slate.AllowHardwareCursor", "Slate.AllowHardwareCursor=1" },
                { "Slate.CursorRenderRate", "Slate.CursorRenderRate=0" },
                { "Slate.SleepInterval", "Slate.SleepInterval=0" },
                { "Slate.SleepIntervalWithUserInteraction", "Slate.SleepIntervalWithUserInteraction=0" },
                { "r.Slate.EnableMouseCapture", "r.Slate.EnableMouseCapture=0" },
                { "r.OneFrameThreadLag", "r.OneFrameThreadLag=1" },
                { "r.FinishCurrentFrame", "r.FinishCurrentFrame=0" },
                { "r.GTSyncType", "r.GTSyncType=1" },
                { "t.MaxFPS", "t.MaxFPS=120" },
                { "t.UnfocusedMaxFPS", "t.UnfocusedMaxFPS=30" },
                { "r.TextureStreaming", "r.TextureStreaming=1" },
                { "r.Streaming.PoolSize", "r.Streaming.PoolSize=3072" },
                { "r.Streaming.LimitPoolSizeToVRAM", "r.Streaming.LimitPoolSizeToVRAM=1" },
                { "r.Streaming.DefragDynamicBounds", "r.Streaming.DefragDynamicBounds=1" },
                { "r.Streaming.AmortizeCPUWork", "r.Streaming.AmortizeCPUWork=1" },
                { "r.Streaming.AmortizeCPUToGPUCopy", "r.Streaming.AmortizeCPUToGPUCopy=1" },
                { "r.Streaming.FramesForFullUpdate", "r.Streaming.FramesForFullUpdate=20" },
                { "r.Streaming.MaxNumTexturesToStreamPerFrame", "r.Streaming.MaxNumTexturesToStreamPerFrame=8" },
                { "r.Streaming.HLODStrategy", "r.Streaming.HLODStrategy=1" },
                { "r.Shadow.Virtual.Enable", "r.Shadow.Virtual.Enable=0" },
                { "r.Shadow.CSM.MaxCascades", "r.Shadow.CSM.MaxCascades=2" },
                { "r.Shadow.DistanceScale", "r.Shadow.DistanceScale=0.85" },
                { "r.VolumetricFog", "r.VolumetricFog=0" },
                { "r.VolumetricFog.GridPixelSize", "r.VolumetricFog.GridPixelSize=16" },
                { "r.VolumetricFog.GridSizeZ", "r.VolumetricFog.GridSizeZ=64" },
                { "r.Lumen.Reflections.Allow", "r.Lumen.Reflections.Allow=0" },
                { "r.Lumen.ScreenProbeGather.DownsampleFactor", "r.Lumen.ScreenProbeGather.DownsampleFactor=16" },
                { "r.DepthOfFieldQuality", "r.DepthOfFieldQuality=0" },
                { "r.MotionBlurQuality", "r.MotionBlurQuality=0" },
                { "r.SceneColorFringeQuality", "r.SceneColorFringeQuality=0" },
                { "r.Tonemapper.GrainQuantization", "r.Tonemapper.GrainQuantization=0" },
                { "r.ParticleLODBias", "r.ParticleLODBias=1" },
                { "r.Emitter.FastPool", "r.Emitter.FastPool=1" },
                { "r.Shaders.Optimize", "r.Shaders.Optimize=1" },
                { "r.CreateShadersOnLoad", "r.CreateShadersOnLoad=1" },
                { "r.ShaderPipelineCache.BatchTime", "r.ShaderPipelineCache.BatchTime=2.0" },
                { "r.TSR.ShadingRejection.Flickering", "r.TSR.ShadingRejection.Flickering=1" }
            });

            // 4. Garbage Collection Settings (Fast purging & memory reduction)
            InjectSectionIntoIniLines(lines, "[/Script/Engine.GarbageCollectionSettings]", new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
            {
                { "gc.TimeBetweenPurgingPendingKillObjects", "gc.TimeBetweenPurgingPendingKillObjects=45" },
                { "gc.IncrementalBeginTimeSlice", "gc.IncrementalBeginTimeSlice=0.002" },
                { "gc.MinDesiredTimeBetweenGarbageCollections", "gc.MinDesiredTimeBetweenGarbageCollections=20" },
                { "gc.CreateGCClusters", "gc.CreateGCClusters=True" },
                { "gc.ActorClusteringEnabled", "gc.ActorClusteringEnabled=True" }
            });

            // 5. Audio Thread Settings
            InjectSectionIntoIniLines(lines, "[/Script/Engine.AudioSettings]", new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase)
            {
                { "MaxChannels", "MaxChannels=64" }
            });

            return string.Join(Environment.NewLine, lines);
        }

        private static void InjectSectionIntoIniLines(List<string> lines, string sectionHeader, Dictionary<string, string> keysToSet)
        {
            int sectionIndex = -1;
            for (int i = 0; i < lines.Count; i++)
            {
                if (lines[i].Trim().Equals(sectionHeader, StringComparison.OrdinalIgnoreCase))
                {
                    sectionIndex = i;
                    break;
                }
            }

            if (sectionIndex == -1)
            {
                if (lines.Count > 0 && !string.IsNullOrWhiteSpace(lines[^1]))
                {
                    lines.Add("");
                }
                lines.Add(sectionHeader);
                foreach (var kvp in keysToSet)
                {
                    lines.Add(kvp.Value);
                }
            }
            else
            {
                int nextSectionIndex = lines.Count;
                for (int i = sectionIndex + 1; i < lines.Count; i++)
                {
                    string trimmed = lines[i].Trim();
                    if (trimmed.StartsWith("[") && trimmed.EndsWith("]"))
                    {
                        nextSectionIndex = i;
                        break;
                    }
                }

                var remaining = new Dictionary<string, string>(keysToSet, StringComparer.OrdinalIgnoreCase);
                for (int i = sectionIndex + 1; i < nextSectionIndex; i++)
                {
                    string line = lines[i].Trim();
                    int eqIndex = line.IndexOf('=');
                    if (eqIndex > 0)
                    {
                        string k = line.Substring(0, eqIndex).Trim();
                        if (remaining.TryGetValue(k, out var targetValue))
                        {
                            lines[i] = targetValue;
                            remaining.Remove(k);
                        }
                    }
                }

                int insertPos = nextSectionIndex;
                foreach (var kvp in remaining)
                {
                    lines.Insert(insertPos++, kvp.Value);
                }
            }
        }

        public string? ResolvePlayitExecutablePath()
        {
            var candidates = new List<string>
            {
                Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "tools", "playit", "playit.exe"),
                Path.Combine(Directory.GetCurrentDirectory(), "tools", "playit", "playit.exe"),
                @"C:\PalOddessey\tools\playit\playit.exe"
            };

            foreach (var c in candidates)
            {
                if (!string.IsNullOrWhiteSpace(c) && File.Exists(c))
                    return Path.GetFullPath(c);
            }
            return null;
        }

        private void StartPlayitTunnel(LauncherConfig config)
        {
            if (!config.EnablePlayitTunnel) return;

            try
            {
                StopPlayitTunnel();

                string? playitExe = ResolvePlayitExecutablePath();
                if (playitExe == null)
                {
                    _logService.LogWarning("Playit.gg executable not found in tools/playit/. Skipping cloud tunnel start.", "PlayitTunnel");
                    return;
                }

                var pStartInfo = new ProcessStartInfo
                {
                    FileName = playitExe,
                    Arguments = "start",
                    WorkingDirectory = Path.GetDirectoryName(playitExe) ?? Directory.GetCurrentDirectory(),
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true
                };

                var pProcess = new Process
                {
                    StartInfo = pStartInfo,
                    EnableRaisingEvents = true
                };

                pProcess.OutputDataReceived += (s, e) =>
                {
                    if (!string.IsNullOrWhiteSpace(e.Data))
                    {
                        _logService.LogInfo(e.Data.Trim(), "PlayitTunnel");
                    }
                };

                pProcess.ErrorDataReceived += (s, e) =>
                {
                    if (!string.IsNullOrWhiteSpace(e.Data))
                    {
                        _logService.LogWarning(e.Data.Trim(), "PlayitTunnel");
                    }
                };

                if (pProcess.Start())
                {
                    pProcess.BeginOutputReadLine();
                    pProcess.BeginErrorReadLine();
                    _runningTunnelProcess = pProcess;
                    _logService.LogSuccess($"Playit.gg Cloud Tunnel active in sync with server (PID: {pProcess.Id})", "PlayitTunnel");
                }
            }
            catch (Exception ex)
            {
                _logService.LogError("Failed to start Playit.gg cloud tunnel.", "PlayitTunnel", ex);
            }
        }

        private void StopPlayitTunnel()
        {
            try
            {
                if (_runningTunnelProcess != null && !_runningTunnelProcess.HasExited)
                {
                    _logService.LogInfo($"Stopping Playit.gg Cloud Tunnel (PID: {_runningTunnelProcess.Id})...", "PlayitTunnel");
                    try
                    {
                        _runningTunnelProcess.Kill(true);
                    }
                    catch { }
                    _runningTunnelProcess = null;
                }

                // Also sweep any orphaned playit processes
                foreach (var p in Process.GetProcessesByName("playit"))
                {
                    try { p.Kill(true); } catch { }
                }
            }
            catch { }
        }
    }
}
