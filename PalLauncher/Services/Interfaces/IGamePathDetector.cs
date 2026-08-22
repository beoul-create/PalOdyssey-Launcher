namespace PalLauncher.Services.Interfaces
{
    public class GamePathInfo
    {
        public bool IsValid { get; set; }
        public string GameRootPath { get; set; } = string.Empty;
        public string ClientExecutablePath { get; set; } = string.Empty;
        public string ShippingExecutablePath { get; set; } = string.Empty;
        public string ServerExecutablePath { get; set; } = string.Empty;
        public string PaksDirectoryPath { get; set; } = string.Empty;
        public string ModsPaksDirectoryPath { get; set; } = string.Empty;
        public string DetectedSource { get; set; } = "None"; // "Registry", "SteamLibrary", "DefaultScan", "UserCustom"
    }

    public interface IGamePathDetector
    {
        GamePathInfo DetectPalworldInstallation(string? customPath = null);
        GamePathInfo ValidatePath(string path);
    }
}
