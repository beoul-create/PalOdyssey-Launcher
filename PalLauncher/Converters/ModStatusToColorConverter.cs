using System;
using System.Globalization;
using System.Windows.Data;
using System.Windows.Media;
using PalLauncher.Models;

namespace PalLauncher.Converters
{
    public class ModStatusToColorConverter : IValueConverter
    {
        private static readonly SolidColorBrush UpToDateBrush = new(Color.FromRgb(0, 230, 118)); // Neon green #00E676
        private static readonly SolidColorBrush UpdateAvailableBrush = new(Color.FromRgb(255, 145, 0)); // Neon orange #FF9100
        private static readonly SolidColorBrush MissingBrush = new(Color.FromRgb(255, 23, 68)); // Neon red #FF1744
        private static readonly SolidColorBrush DownloadingBrush = new(Color.FromRgb(0, 229, 255)); // Cyan #00E5FF
        private static readonly SolidColorBrush ErrorBrush = new(Color.FromRgb(244, 67, 54)); // Red #F44336
        private static readonly SolidColorBrush DefaultBrush = new(Color.FromRgb(160, 174, 192)); // Gray #A0AEC0

        static ModStatusToColorConverter()
        {
            UpToDateBrush.Freeze();
            UpdateAvailableBrush.Freeze();
            MissingBrush.Freeze();
            DownloadingBrush.Freeze();
            ErrorBrush.Freeze();
            DefaultBrush.Freeze();
        }

        public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
        {
            if (value is ModStatus status)
            {
                return status switch
                {
                    ModStatus.UpToDate => UpToDateBrush,
                    ModStatus.UpdateAvailable => UpdateAvailableBrush,
                    ModStatus.Missing => MissingBrush,
                    ModStatus.Downloading => DownloadingBrush,
                    ModStatus.Installing => DownloadingBrush,
                    ModStatus.Error => ErrorBrush,
                    _ => DefaultBrush
                };
            }

            return DefaultBrush;
        }

        public object ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture)
        {
            throw new NotImplementedException();
        }
    }
}
