using System;
using System.Globalization;
using System.Windows;
using System.Windows.Data;

namespace PalLauncher.Converters
{
    public class BooleanToVisibilityConverter : IValueConverter
    {
        public bool Invert { get; set; }
        public bool UseHidden { get; set; }

        public object Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
        {
            bool boolVal = false;
            if (value is bool b)
            {
                boolVal = b;
            }

            if (Invert)
            {
                boolVal = !boolVal;
            }

            if (boolVal)
            {
                return Visibility.Visible;
            }

            return UseHidden ? Visibility.Hidden : Visibility.Collapsed;
        }

        public object ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture)
        {
            if (value is Visibility vis)
            {
                bool isVisible = vis == Visibility.Visible;
                return Invert ? !isVisible : isVisible;
            }
            return false;
        }
    }
}
