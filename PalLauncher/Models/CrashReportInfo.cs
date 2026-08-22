using System;
using System.Collections.Generic;

namespace PalLauncher.Models
{
    public class CrashReportInfo
    {
        public string CrashGuid { get; set; } = string.Empty;
        public string FolderPath { get; set; } = string.Empty;
        public DateTime Timestamp { get; set; }
        public string ErrorMessage { get; set; } = string.Empty;
        public string ExceptionCode { get; set; } = string.Empty;
        public string CrashedThreadName { get; set; } = "GameThread";
        public string CallStack { get; set; } = string.Empty;
        public string EngineVersion { get; set; } = string.Empty;
        public string PrimaryModule { get; set; } = string.Empty;
        public string SuggestedFix { get; set; } = string.Empty;
        public bool HasCrashData => !string.IsNullOrEmpty(ErrorMessage) || !string.IsNullOrEmpty(CallStack);
    }
}
