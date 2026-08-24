using System;
using System.Windows.Media;
using Brush = System.Windows.Media.Brush;
using Color = System.Windows.Media.Color;

namespace PalLauncher.Models
{
    public enum LogLevel
    {
        Info,
        Success,
        Warning,
        Error
    }

    public class LogEntry
    {
        public DateTime Timestamp { get; set; } = DateTime.Now;
        public LogLevel Level { get; set; } = LogLevel.Info;
        public string Source { get; set; } = "Launcher";
        public string Message { get; set; } = string.Empty;
        public string? Details { get; set; }

        public string FormattedTimestamp => Timestamp.ToString("HH:mm:ss.fff");

        public Brush LevelColor => Level switch
        {
            LogLevel.Success => new SolidColorBrush(Color.FromRgb(0, 230, 118)),
            LogLevel.Warning => new SolidColorBrush(Color.FromRgb(255, 183, 77)),
            LogLevel.Error => new SolidColorBrush(Color.FromRgb(255, 82, 82)),
            _ => new SolidColorBrush(Color.FromRgb(144, 202, 249))
        };
    }
}
