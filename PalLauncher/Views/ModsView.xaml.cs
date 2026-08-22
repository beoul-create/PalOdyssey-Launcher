using System.Windows;
using System.Windows.Controls;
using PalLauncher.ViewModels;

namespace PalLauncher.Views
{
    public partial class ModsView : UserControl
    {
        public ModsView()
        {
            InitializeComponent();
        }

        private void OnFilterAllClicked(object sender, RoutedEventArgs e)
        {
            if (DataContext is ModsViewModel vm)
            {
                vm.SelectedFilter = "All";
            }
        }

        private void OnFilterUpdatesClicked(object sender, RoutedEventArgs e)
        {
            if (DataContext is ModsViewModel vm)
            {
                vm.SelectedFilter = "Updates";
            }
        }

        private void OnFilterRequiredClicked(object sender, RoutedEventArgs e)
        {
            if (DataContext is ModsViewModel vm)
            {
                vm.SelectedFilter = "Required";
            }
        }
    }
}
