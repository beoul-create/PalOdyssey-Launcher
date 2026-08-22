using System;
using System.Threading.Tasks;
using PalLauncher.Models;

namespace PalLauncher.Services.Interfaces
{
    public interface ICrashLogService
    {
        Task<CrashReportInfo?> GetLatestCrashReportAsync(string? gameRootPath = null);
        Task<string?> GetLatestUe4ssLogAsync(string? gameRootPath = null, int maxLines = 100);
        Task<string?> GetLatestEngineLogAsync(string? gameRootPath = null, int maxLines = 100);
        string GenerateDiagnosticSummary(CrashReportInfo? crash, string? ue4ssLog, string? engineLog);
        string GetCrashesDirectoryPath();
        string GetLauncherLogsDirectoryPath();
    }
}
