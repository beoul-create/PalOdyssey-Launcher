using System;
using System.Globalization;
using System.Windows.Data;

namespace PalLauncher.Converters
{
    public class ProgressPercentageConverter : IValueConverter
    {
        public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
        {
            if (value is double d)
            {
                return $"{d:F1}%";
            }
            if (value is float f)
            {
                return $"{f:F1}%";
            }
            if (value is int i)
            {
                return $"{i}%";
            }
            return "0%";
        }

        public object ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture)
        {
            throw new NotImplementedException();
        }
    }
}
