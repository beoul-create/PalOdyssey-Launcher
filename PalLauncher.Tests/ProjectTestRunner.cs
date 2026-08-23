using System;
using System.IO;
using System.Text.Json;
using System.Threading.Tasks;
using PalLauncher.Models;
using PalLauncher.Services;
using PalLauncher.Services.Interfaces;
using Xunit;
using Xunit.Abstractions;

namespace PalLauncher.Tests
{
    [Collection("DaemonTests")]
    public class ProjectTestRunner
    {
        private readonly ITestOutputHelper _output;
        private readonly LogService _logService = new();

        public ProjectTestRunner(ITestOutputHelper output)
        {
            _output = output;
        }

        [Fact]
        public async Task ProjectTest_ExecuteAllSubsystems_EncompassingAllErrorsAndImprovements()
        {
            var engine = new ProjectTestEngine(_logService);

            var report = await engine.RunCompleteProjectTestSuiteAsync(
                new Progress<string>(msg => _output.WriteLine($"[ProjectTest] {msg}")),
                @"C:\SteamLibrary\steamapps\common\Palworld");

            Assert.NotNull(report);
            Assert.True(report.OverallSuccess, "Project Test should complete with 100% success rate");
            Assert.Equal(100.0, report.SystemHealthScorePercentage);
            Assert.True(report.StageResults.Count >= 6, "Must complete all 6 test phases");
            Assert.True(report.BenchmarkTelemetry.Count >= 5, "Must benchmark all 5 hardware generations");
            Assert.True(report.SynthesizedImprovements.Count >= 4, "Must synthesize improvements for all hardware classes");

            // Generate Markdown Report
            string markdown = engine.GenerateConsensusMarkdownReport(report);
            _output.WriteLine("\n" + markdown);

            // Export results to project test results artifact
            string resultsPath = @"c:\PalOddessey\project_test_results.json";
            string json = JsonSerializer.Serialize(report, new JsonSerializerOptions { WriteIndented = true });
            await File.WriteAllTextAsync(resultsPath, json);

            _output.WriteLine($"\n[PASS] Project Test Report persisted to {resultsPath}");
        }
    }
}
