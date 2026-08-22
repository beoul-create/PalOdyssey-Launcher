using System;
using System.IO;
using System.Threading.Tasks;
using PalLauncher.Models;
using PalLauncher.Services;
using PalLauncher.ViewModels;
using Xunit;

namespace PalLauncher.Tests
{
    public class CrashDiagnosticsTests : IDisposable
    {
        private readonly string _tempDir;
        private readonly LogService _logService;
        private readonly CrashLogService _crashService;

        public CrashDiagnosticsTests()
        {
            _tempDir = Path.Combine(Path.GetTempPath(), "PalLauncherCrashTests_" + Guid.NewGuid().ToString("N"));
            Directory.CreateDirectory(_tempDir);

            _logService = new LogService();
            _crashService = new CrashLogService(_logService);
        }

        public void Dispose()
        {
            try
            {
                if (Directory.Exists(_tempDir))
                {
                    Directory.Delete(_tempDir, true);
                }
            }
            catch { }
        }

        [Fact]
        public void CrashLogService_DiagnosesUE4SSExceptionCorrectly()
        {
            // Simulate Crash Directory Structure
            string crashDir = Path.Combine(_tempDir, "UECC-Windows-TEST12345");
            Directory.CreateDirectory(crashDir);

            string sampleXml = @"<?xml version=""1.0"" encoding=""UTF-8""?>
<FGenericCrashContext>
	<RuntimeProperties>
		<CrashGUID>UECC-Windows-TEST12345</CrashGUID>
		<ErrorMessage>Unhandled Exception: 0xe06d7363</ErrorMessage>
		<EngineVersion>5.1.1-0+++UE5+Release-5.1</EngineVersion>
		<Threads>
			<Thread>
				<CallStack>KERNELBASE + c187a VCRUNTIME140 + 55a9 UE4SS + 87c60c Palworld-Win64-Shipping</CallStack>
				<IsCrashed>true</IsCrashed>
				<ThreadName>GameThread</ThreadName>
			</Thread>
		</Threads>
	</RuntimeProperties>
</FGenericCrashContext>";

            File.WriteAllText(Path.Combine(crashDir, "CrashContext.runtime-xml"), sampleXml);

            // Test parsing logic through diagnostic generation
            var report = new CrashReportInfo
            {
                CrashGuid = "UECC-Windows-TEST12345",
                ErrorMessage = "Unhandled Exception: 0xe06d7363",
                CallStack = "KERNELBASE + c187a VCRUNTIME140 + 55a9 UE4SS + 87c60c",
                CrashedThreadName = "GameThread",
                EngineVersion = "5.1.1"
            };

            string summary = _crashService.GenerateDiagnosticSummary(report, "[Lua] Loaded mod ExpeditionXP", null);

            Assert.Contains("PALODYSSEY CRASH DIAGNOSTIC REPORT", summary);
            Assert.Contains("0xe06d7363", summary);
            Assert.Contains("UE4SS", summary);
        }

        [Fact]
        public void LogsViewModel_CrashFilter_ShowsCrashEntries()
        {
            var logService = new LogService();
            logService.ClearLogs();

            logService.LogInfo("Normal info", "Launcher");
            logService.LogError("UE4SS exception caught", "CrashDiagnostics");
            logService.LogError("Game crashed on boot", "CrashWatcher");

            var logsVm = new LogsViewModel(logService);
            logsVm.SelectedFilter = "Crash";

            Assert.Equal(2, logsVm.FilteredLogsView.Cast<object>().Count());
        }
    }
}
