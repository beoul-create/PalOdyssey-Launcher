using System.Windows;
using System.Windows.Controls;
using PalLauncher.ViewModels;

namespace PalLauncher.Views
{
    public partial class LogsView : UserControl
    {
        public LogsView()
        {
            InitializeComponent();
        }

        private void OnFilterAllClicked(object sender, RoutedEventArgs e)
        {
            if (DataContext is LogsViewModel vm)
            {
                vm.SelectedFilter = "All";
            }
        }

        private void OnFilterErrorsClicked(object sender, RoutedEventArgs e)
        {
            if (DataContext is LogsViewModel vm)
            {
                vm.SelectedFilter = "Errors";
            }
        }

        private void OnFilterWarningsClicked(object sender, RoutedEventArgs e)
        {
            if (DataContext is LogsViewModel vm)
            {
                vm.SelectedFilter = "Warnings";
            }
        }

        private void OnFilterServerClicked(object sender, RoutedEventArgs e)
        {
            if (DataContext is LogsViewModel vm)
            {
                vm.SelectedFilter = "Server";
            }
        }

        private void OnFilterSuccessClicked(object sender, RoutedEventArgs e)
        {
            if (DataContext is LogsViewModel vm)
            {
                vm.SelectedFilter = "Success";
            }
        }
    }
}
