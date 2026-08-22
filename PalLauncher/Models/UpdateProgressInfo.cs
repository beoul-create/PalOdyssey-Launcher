namespace PalLauncher.Models
{
    public class UpdateProgressInfo
    {
        public int TotalFiles { get; set; }
        public int CurrentFileIndex { get; set; }
        public string CurrentFileName { get; set; } = string.Empty;
        public long BytesDownloaded { get; set; }
        public long TotalBytes { get; set; }
        public double Percentage { get; set; }
        public double SpeedBytesPerSecond { get; set; }
        public string StatusMessage { get; set; } = string.Empty;

        public string FormattedSpeed
        {
            get
            {
                if (SpeedBytesPerSecond < 1024)
                    return $"{SpeedBytesPerSecond:F0} B/s";
                if (SpeedBytesPerSecond < 1024 * 1024)
                    return $"{SpeedBytesPerSecond / 1024:F1} KB/s";
                return $"{SpeedBytesPerSecond / (1024 * 1024):F1} MB/s";
            }
        }
    }
}
