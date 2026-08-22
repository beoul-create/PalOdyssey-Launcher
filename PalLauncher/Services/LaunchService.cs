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
        private Process? _runningClientProcess;
        private Process? _runningServerProcess;
        private GameProcessState _currentState = new();

        public GameProcessState CurrentState => _currentState;
        public bool IsGameRunning => (_runningClientProcess != null && !_runningClientProcess.HasExited) ||
                                     (_runningServerProcess != null && !_runningServerProcess.HasExited);

        public bool IsServerRunning => _runningServerProcess != null && !_runningServerProcess.HasExited;
        public bool IsClientRunning => _runningClientProcess != null && !_runningClientProcess.HasExited;

        public event EventHandler<GameProcessState>? ProcessStateChanged;
        public event EventHandler<int>? ProcessExited;

        public LaunchService(ILogService logService)
        {
            _logService = logService;
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
            return string.Join(" ", args);
        }

        public string BuildCommandLineArguments(LauncherConfig config)
        {
            var args = new List<string>();

            // 1. Client Auto-Join Argument if enabled
            if (config.AutoJoinServer && !string.IsNullOrWhiteSpace(config.ServerIp))
            {
                string ipArg = $"{config.ServerIp}:{config.ServerPort}";
                args.Add(ipArg);
            }

            // 2. Predefined Performance & Engine Flags
            if (config.UseDirectX11)
            {
                args.Add("-dx11");
            }

            if (config.UseAllCores)
            {
                args.Add("-USEALLAVAILABLECORES");
            }

            if (config.NoSplash)
            {
                args.Add("-nosplash");
            }

            if (config.WindowedMode)
            {
                args.Add("-windowed");
            }

            if (config.UseHighPriority)
            {
                args.Add("-high");
            }

            // 3. Custom User Arguments
            if (!string.IsNullOrWhiteSpace(config.CustomArguments))
            {
                args.Add(config.CustomArguments.Trim());
            }

            return string.Join(" ", args);
        }

        public async Task<bool> LaunchGameAsync(LauncherConfig config, GamePathInfo pathInfo)
        {
            if (IsGameRunning)
            {
                _logService.LogWarning("Game/Server process is already running.", "Launcher");
                return false;
            }

            if (!pathInfo.IsValid)
            {
                _logService.LogError("Cannot launch: Palworld installation path is invalid or not detected.", "Launcher");
                return false;
            }

            bool launchServer = config.LaunchMode.Equals("Server", StringComparison.OrdinalIgnoreCase) || config.LaunchServerWithGame;
            bool launchClient = !config.LaunchMode.Equals("Server", StringComparison.OrdinalIgnoreCase);

            return await Task.Run(() =>
            {
                try
                {
                    bool serverLaunched = false;
                    bool clientLaunched = false;

                    // 1. Launch Dedicated Server if requested and available
                    if (launchServer)
                    {
                        string serverExe = pathInfo.ServerExecutablePath;
                        if (!File.Exists(serverExe))
                        {
                            serverExe = Path.Combine(pathInfo.GameRootPath, config.ServerExecutableName);
                        }
                        if (!File.Exists(serverExe))
                        {
                            string shippingServer = Path.Combine(pathInfo.GameRootPath, "Pal", "Binaries", "Win64", "PalServer-Win64-Shipping.exe");
                            if (File.Exists(shippingServer)) serverExe = shippingServer;
                        }

                        if (File.Exists(serverExe))
                        {
                            string serverArgs = BuildServerCommandLineArguments(config);
                            string serverWorkDir = Path.GetDirectoryName(serverExe) ?? pathInfo.GameRootPath;

                            _logService.LogInfo($"Launching PalServer: {Path.GetFileName(serverExe)} args: '{serverArgs}'", "PalServer");

                            var sStartInfo = new ProcessStartInfo
                            {
                                FileName = serverExe,
                                Arguments = serverArgs,
                                WorkingDirectory = serverWorkDir,
                                UseShellExecute = false,
                                CreateNoWindow = true,
                                RedirectStandardOutput = true,
                                RedirectStandardError = true
                            };

                            var sProcess = new Process
                            {
                                StartInfo = sStartInfo,
                                EnableRaisingEvents = true
                            };

                            sProcess.OutputDataReceived += (s, e) =>
                            {
                                if (!string.IsNullOrWhiteSpace(e.Data)) ParseAndLogServerOutput(e.Data);
                            };

                            sProcess.ErrorDataReceived += (s, e) =>
                            {
                                if (!string.IsNullOrWhiteSpace(e.Data))
                                {
                                    if (e.Data.Contains("error", StringComparison.OrdinalIgnoreCase) || e.Data.Contains("fatal", StringComparison.OrdinalIgnoreCase))
                                        _logService.LogError(e.Data, "PalServer");
                                    else
                                        _logService.LogWarning(e.Data, "PalServer");
                                }
                            };

                            sProcess.Exited += (s, e) =>
                            {
                                _logService.LogInfo($"Dedicated server process (PID: {sProcess.Id}) terminated.", "PalServer");
                                UpdateProcessState();
                            };

                            if (sProcess.Start())
                            {
                                sProcess.BeginOutputReadLine();
                                sProcess.BeginErrorReadLine();
                                _runningServerProcess = sProcess;
                                serverLaunched = true;

                                _serverLogCts?.Cancel();
                                _serverLogCts = new CancellationTokenSource();
                                StartServerLogFileTailer(pathInfo.GameRootPath, _serverLogCts.Token);

                                _logService.LogSuccess($"Palworld Dedicated Server online on port {config.ServerPort} (PID: {sProcess.Id})", "PalServer");
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

                            // Ensure steam_appid.txt exists to bypass Steam argument verification dialog
                            try
                            {
                                string appIdContent = "1623730";
                                string appIdPath1 = Path.Combine(clientWorkDir, "steam_appid.txt");
                                string appIdPath2 = Path.Combine(pathInfo.GameRootPath, "steam_appid.txt");
                                if (!File.Exists(appIdPath1)) File.WriteAllText(appIdPath1, appIdContent);
                                if (!File.Exists(appIdPath2)) File.WriteAllText(appIdPath2, appIdContent);
                            }
                            catch { }

                            _logService.LogInfo($"Launching Palworld Client: {Path.GetFileName(clientExe)} args: '{clientArgs}'", "Launcher");

                            var cStartInfo = new ProcessStartInfo
                            {
                                FileName = clientExe,
                                Arguments = clientArgs,
                                WorkingDirectory = clientWorkDir,
                                UseShellExecute = false
                            };

                            var cProcess = new Process
                            {
                                StartInfo = cStartInfo,
                                EnableRaisingEvents = true
                            };

                            cProcess.Exited += (s, e) =>
                            {
                                _logService.LogInfo($"Game client process (PID: {cProcess.Id}) closed.", "Launcher");
                                UpdateProcessState();
                            };

                            if (cProcess.Start())
                            {
                                _runningClientProcess = cProcess;
                                clientLaunched = true;
                                _logService.LogSuccess($"Palworld Client launched successfully! (PID: {cProcess.Id})", "Launcher");
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
            bool isRunning = IsGameRunning;
            int clientPid = (_runningClientProcess != null && !_runningClientProcess.HasExited) ? _runningClientProcess.Id : 0;
            int serverPid = (_runningServerProcess != null && !_runningServerProcess.HasExited) ? _runningServerProcess.Id : 0;

            _currentState = new GameProcessState
            {
                IsRunning = isRunning,
                IsClientRunning = clientPid > 0,
                IsServerRunning = serverPid > 0,
                ProcessId = clientPid > 0 ? clientPid : serverPid,
                ServerProcessId = serverPid,
                StartTime = isRunning ? (_currentState.StartTime ?? DateTime.Now) : null,
                Mode = (clientPid > 0 && serverPid > 0) ? "Client + Server" : (serverPid > 0 ? "Server" : "Client")
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
    }
}
