using System.Windows;
using System.Windows.Controls;
using PalLauncher.ViewModels;
using UserControl = System.Windows.Controls.UserControl;

namespace PalLauncher.Views
{
    public partial class SettingsView : UserControl
    {
        public SettingsView()
        {
            InitializeComponent();
        }

        private void OnClientModeChecked(object sender, RoutedEventArgs e)
        {
            if (DataContext is SettingsViewModel vm)
            {
                vm.LaunchMode = "Client";
            }
        }

        private void OnServerModeChecked(object sender, RoutedEventArgs e)
        {
            if (DataContext is SettingsViewModel vm)
            {
                vm.LaunchMode = "Server";
            }
        }
    }
}
