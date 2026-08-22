using System;
using System.Globalization;
using System.Windows.Data;

namespace PalLauncher.Converters
{
    public class FileSizeConverter : IValueConverter
    {
        public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
        {
            if (value == null) return "0 B";

            long bytes = 0;
            if (value is long l) bytes = l;
            else if (value is int i) bytes = i;
            else if (value is double d) bytes = (long)d;
            else if (long.TryParse(value.ToString(), out long parsed)) bytes = parsed;

            if (bytes <= 0) return "0 B";

            string[] suffixes = { "B", "KB", "MB", "GB", "TB" };
            int counter = 0;
            decimal number = bytes;
            while (Math.Round(number / 1024) >= 1)
            {
                number /= 1024;
                counter++;
            }

            return $"{number:n1} {suffixes[counter]}";
        }

        public object ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture)
        {
            throw new NotImplementedException();
        }
    }
}
