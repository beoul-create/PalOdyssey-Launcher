using System;
using System.Diagnostics;
using System.IO;
using PalLauncher.Services.Interfaces;

namespace PalLauncher.Services
{
    public class WindowsTaskSchedulerService
    {
        private const string TaskName = "PalOdyssey-24x7-Daemon";
        private readonly ILogService? _logService;

        public WindowsTaskSchedulerService(ILogService? logService = null)
        {
            _logService = logService;
        }

        public bool Is24x7TaskRegistered()
        {
            try
            {
                var psi = new ProcessStartInfo
                {
                    FileName = "schtasks.exe",
                    Arguments = $"/query /tn \"{TaskName}\"",
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true
                };

                using var proc = Process.Start(psi);
                if (proc == null) return false;

                proc.WaitForExit(3000);
                return proc.ExitCode == 0;
            }
            catch (Exception ex)
            {
                _logService?.LogWarning($"Error querying Windows Task Scheduler: {ex.Message}", "Daemon");
                return false;
            }
        }

        public (bool Success, string Message) Register24x7Task()
        {
            try
            {
                string exePath = Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "PalLauncher.exe");
                if (!File.Exists(exePath))
                {
                    string altExe = Path.Combine(@"C:\PalOddessey", "PalLauncher.exe");
                    if (File.Exists(altExe))
                    {
                        exePath = altExe;
                    }
                }

                string taskRun = $"\\\"{exePath}\\\" --daemon";
                var psi = new ProcessStartInfo
                {
                    FileName = "schtasks.exe",
                    Arguments = $"/create /tn \"{TaskName}\" /tr \"{taskRun}\" /sc ONLOGON /rl HIGHEST /f",
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true
                };

                using var proc = Process.Start(psi);
                if (proc == null) return (false, "Could not start schtasks process.");

                string stdOut = proc.StandardOutput.ReadToEnd();
                string stdErr = proc.StandardError.ReadToEnd();
                proc.WaitForExit(5000);

                if (proc.ExitCode == 0)
                {
                    _logService?.LogSuccess($"Successfully registered 24/7 background task: {TaskName}", "Daemon");
                    return (true, "24/7 Windows Scheduled Task registered successfully (starts on login with highest privileges).");
                }
                else
                {
                    string err = !string.IsNullOrWhiteSpace(stdErr) ? stdErr : stdOut;
                    _logService?.LogWarning($"Failed to register task: {err}", "Daemon");
                    return (false, $"Registration failed: {err.Trim()}");
                }
            }
            catch (Exception ex)
            {
                _logService?.LogError("Exception registering 24/7 task", "Daemon", ex);
                return (false, $"Error: {ex.Message}");
            }
        }

        public (bool Success, string Message) Unregister24x7Task()
        {
            try
            {
                var psi = new ProcessStartInfo
                {
                    FileName = "schtasks.exe",
                    Arguments = $"/delete /tn \"{TaskName}\" /f",
                    UseShellExecute = false,
                    CreateNoWindow = true,
                    RedirectStandardOutput = true,
                    RedirectStandardError = true
                };

                using var proc = Process.Start(psi);
                if (proc == null) return (false, "Could not start schtasks process.");

                string stdOut = proc.StandardOutput.ReadToEnd();
                string stdErr = proc.StandardError.ReadToEnd();
                proc.WaitForExit(5000);

                if (proc.ExitCode == 0)
                {
                    _logService?.LogSuccess($"Successfully removed 24/7 background task: {TaskName}", "Daemon");
                    return (true, "24/7 Windows Scheduled Task successfully removed.");
                }
                else
                {
                    string err = !string.IsNullOrWhiteSpace(stdErr) ? stdErr : stdOut;
                    _logService?.LogWarning($"Failed to remove task: {err}", "Daemon");
                    return (false, $"Unregistration failed: {err.Trim()}");
                }
            }
            catch (Exception ex)
            {
                _logService?.LogError("Exception unregistering 24/7 task", "Daemon", ex);
                return (false, $"Error: {ex.Message}");
            }
        }
    }
}