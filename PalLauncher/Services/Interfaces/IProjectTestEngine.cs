using System;
using System.Threading.Tasks;
using PalLauncher.Models;

namespace PalLauncher.Services.Interfaces
{
    public interface IProjectTestEngine
    {
        Task<ProjectTestReport> RunCompleteProjectTestSuiteAsync(IProgress<string>? progress = null, string? customGamePath = null);
        string GenerateConsensusMarkdownReport(ProjectTestReport report);
    }
}
