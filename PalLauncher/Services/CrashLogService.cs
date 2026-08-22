using System;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.RegularExpressions;
using System.Threading.Tasks;
using System.Xml.Linq;
using PalLauncher.Models;
using PalLauncher.Services.Interfaces;

namespace PalLauncher.Services
{
    public class CrashLogService : ICrashLogService
    {
        private readonly ILogService _logService;

        public CrashLogService(ILogService logService)
        {
            _logService = logService;
        }

        public string GetCrashesDirectoryPath()
        {
            string localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
            return Path.Combine(localAppData, "Pal", "Saved", "Crashes");
        }

        public string GetLauncherLogsDirectoryPath()
        {
            string appData = Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData);
            return Path.Combine(appData, "PalLauncher", "logs");
        }

        public async Task<CrashReportInfo?> GetLatestCrashReportAsync(string? gameRootPath = null)
        {
            return await Task.Run(() =>
            {
                try
                {
                    string crashesDir = GetCrashesDirectoryPath();
                    if (!Directory.Exists(crashesDir)) return null;

                    var dirInfo = new DirectoryInfo(crashesDir);
                    var latestDir = dirInfo.GetDirectories()
                        .OrderByDescending(d => d.LastWriteTime)
                        .FirstOrDefault();

                    if (latestDir == null) return null;

                    string xmlPath = Path.Combine(latestDir.FullName, "CrashContext.runtime-xml");
                    if (!File.Exists(xmlPath)) return null;

                    var report = new CrashReportInfo
                    {
                        CrashGuid = latestDir.Name,
                        FolderPath = latestDir.FullName,
                        Timestamp = latestDir.LastWriteTime
                    };

                    string xmlContent = File.ReadAllText(xmlPath, Encoding.UTF8);

                    // Parse ErrorMessage
                    var errMatch = Regex.Match(xmlContent, @"<ErrorMessage>(.*?)</ErrorMessage>", RegexOptions.Singleline);
                    if (errMatch.Success)
                    {
                        report.ErrorMessage = errMatch.Groups[1].Value.Trim();
                    }

                    // Parse EngineVersion
                    var engineMatch = Regex.Match(xmlContent, @"<EngineVersion>(.*?)</EngineVersion>", RegexOptions.Singleline);
                    if (engineMatch.Success)
                    {
                        report.EngineVersion = engineMatch.Groups[1].Value.Trim();
                    }

                    // Parse Crashed Thread CallStack
                    var threadMatch = Regex.Match(xmlContent, @"<Thread>.*?<CallStack>(.*?)</CallStack>.*?<IsCrashed>true</IsCrashed>.*?<ThreadName>(.*?)</ThreadName>.*?</Thread>", RegexOptions.Singleline);
                    if (threadMatch.Success)
                    {
                        report.CallStack = CleanCallStack(threadMatch.Groups[1].Value.Trim());
                        report.CrashedThreadName = threadMatch.Groups[2].Value.Trim();
                    }
                    else
                    {
                        // Fallback to PCallStack
                        var pStackMatch = Regex.Match(xmlContent, @"<PCallStack>(.*?)</PCallStack>", RegexOptions.Singleline);
                        if (pStackMatch.Success)
                        {
                            report.CallStack = CleanCallStack(pStackMatch.Groups[1].Value.Trim());
                        }
                    }

                    // Determine Primary Module and Suggested Fix
                    AnalyzeCrashRootCause(report);

                    return report;
                }
                catch (Exception ex)
                {
                    _logService.LogWarning("Failed to parse latest crash context.", "CrashDiagnostics", ex.Message);
                    return null;
                }
            });
        }

        private static string CleanCallStack(string raw)
        {
            if (string.IsNullOrWhiteSpace(raw)) return string.Empty;
            return raw.Replace("&gt;", ">")
                      .Replace("&lt;", "<")
                      .Replace("&amp;", "&")
                      .Trim();
        }

        private static void AnalyzeCrashRootCause(CrashReportInfo report)
        {
            string stack = report.CallStack.ToLowerInvariant();
            string err = report.ErrorMessage.ToLowerInvariant();

            if (stack.Contains("ue4ss") || err.Contains("ue4ss"))
            {
                report.PrimaryModule = "UE4SS Injector";
                if (err.Contains("0xe06d7363") || stack.Contains("vcruntime140"))
                {
                    report.SuggestedFix = "UE4SS RHI or Cache Mismatch: Invalidate cache (UseCache=0), ensure GraphicsAPI matches engine (dx12), and remove stale MemberVariableLayout.ini.";
                }
                else
                {
                    report.SuggestedFix = "Lua Hook or Mod Exception: Check UE4SS.log for failed Lua module requires or invalid function hooks.";
                }
            }
            else if (stack.Contains("d3d12") || stack.Contains("dxgi") || stack.Contains("nvgpucomp") || stack.Contains("nvd3dumx"))
            {
                report.PrimaryModule = "DirectX 12 / NVIDIA Driver";
                report.SuggestedFix = "GPU Device Removed / Shader Timeout: Lower graphics preset or launch with -dx11 / update NVIDIA GPU drivers.";
            }
            else if (err.Contains("c0000005") || stack.Contains("access_violation"))
            {
                report.PrimaryModule = "Engine Memory / Access Violation";
                report.SuggestedFix = "Corrupted asset or null pointer dereference: Verify Palworld game files in Steam and check active .pak mods.";
            }
            else if (stack.Contains("palworld-win64-shipping"))
            {
                report.PrimaryModule = "Palworld Engine GameThread";
                report.SuggestedFix = "Native Game Crash: Check Pal.log in Saved/Logs or launch with -USEALLAVAILABLECORES -NoAsyncLoadingThread.";
            }
            else
            {
                report.PrimaryModule = "General System / Runtime";
                report.SuggestedFix = "Review active mods in Mods tab and verify GameUserSettings.ini scalability settings.";
            }
        }

        public async Task<string?> GetLatestUe4ssLogAsync(string? gameRootPath = null, int maxLines = 100)
        {
            return await Task.Run(() =>
            {
                try
                {
                    var candidates = new List<string>();
                    if (!string.IsNullOrEmpty(gameRootPath))
                    {
                        candidates.Add(Path.Combine(gameRootPath, "Pal", "Binaries", "Win64", "UE4SS.log"));
                        candidates.Add(Path.Combine(gameRootPath, "UE4SS.log"));
                    }
                    candidates.Add(@"C:\SteamLibrary\steamapps\common\Palworld\Pal\Binaries\Win64\UE4SS.log");
                    candidates.Add(@"C:\Program Files (x86)\Steam\steamapps\common\Palworld\Pal\Binaries\Win64\UE4SS.log");

                    string? logFile = candidates.FirstOrDefault(File.Exists);
                    if (logFile == null) return null;

                    var lines = File.ReadLines(logFile).TakeLast(maxLines).ToList();
                    return string.Join(Environment.NewLine, lines);
                }
                catch (Exception ex)
                {
                    _logService.LogWarning("Failed to read UE4SS.log", "CrashDiagnostics", ex.Message);
                    return null;
                }
            });
        }

        public async Task<string?> GetLatestEngineLogAsync(string? gameRootPath = null, int maxLines = 100)
        {
            return await Task.Run(() =>
            {
                try
                {
                    string localAppData = Environment.GetFolderPath(Environment.SpecialFolder.LocalApplicationData);
                    string palLog = Path.Combine(localAppData, "Pal", "Saved", "Logs", "Pal.log");
                    if (!File.Exists(palLog)) return null;

                    var lines = File.ReadLines(palLog).TakeLast(maxLines).ToList();
                    return string.Join(Environment.NewLine, lines);
                }
                catch (Exception ex)
                {
                    _logService.LogWarning("Failed to read Pal.log", "CrashDiagnostics", ex.Message);
                    return null;
                }
            });
        }

        public string GenerateDiagnosticSummary(CrashReportInfo? crash, string? ue4ssLog, string? engineLog)
        {
            var sb = new StringBuilder();
            sb.AppendLine("================================================================================");
            sb.AppendLine("                     PALODYSSEY CRASH DIAGNOSTIC REPORT                         ");
            sb.AppendLine($"Generated: {DateTime.Now:yyyy-MM-dd HH:mm:ss}");
            sb.AppendLine("================================================================================");

            if (crash != null && crash.HasCrashData)
            {
                sb.AppendLine();
                sb.AppendLine($"[CRASH METADATA]");
                sb.AppendLine($"Crash GUID:        {crash.CrashGuid}");
                sb.AppendLine($"Timestamp:         {crash.Timestamp:yyyy-MM-dd HH:mm:ss}");
                sb.AppendLine($"Engine Version:    {crash.EngineVersion}");
                sb.AppendLine($"Primary Module:    {crash.PrimaryModule}");
                sb.AppendLine($"Crashed Thread:    {crash.CrashedThreadName}");
                sb.AppendLine($"Error Message:     {crash.ErrorMessage}");
                sb.AppendLine();
                sb.AppendLine($"[SUGGESTED RESOLUTION]");
                sb.AppendLine(crash.SuggestedFix);
                sb.AppendLine();
                sb.AppendLine($"[CALLSTACK]");
                sb.AppendLine(crash.CallStack);
            }
            else
            {
                sb.AppendLine();
                sb.AppendLine("No recent Unreal Engine crash dump found in Saved/Crashes.");
            }

            if (!string.IsNullOrWhiteSpace(ue4ssLog))
            {
                sb.AppendLine();
                sb.AppendLine("================================================================================");
                sb.AppendLine("                     UE4SS LOG (LAST 40 LINES)                                  ");
                sb.AppendLine("================================================================================");
                var ueLines = ue4ssLog.Split(new[] { "\r\n", "\r", "\n" }, StringSplitOptions.None).TakeLast(40);
                foreach (var l in ueLines) sb.AppendLine(l);
            }

            return sb.ToString();
        }
    }
}
