using System.Windows;
using System.Windows.Controls;
using PalLauncher.ViewModels;
using UserControl = System.Windows.Controls.UserControl;

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
                vm.SelectedCategory = "All";
            }
        }

        private void OnFilterCoreClicked(object sender, RoutedEventArgs e)
        {
            if (DataContext is ModsViewModel vm)
            {
                vm.SelectedCategory = "Core";
            }
        }

        private void OnFilterGameplayClicked(object sender, RoutedEventArgs e)
        {
            if (DataContext is ModsViewModel vm)
            {
                vm.SelectedCategory = "Gameplay";
            }
        }

        private void OnFilterQolClicked(object sender, RoutedEventArgs e)
        {
            if (DataContext is ModsViewModel vm)
            {
                vm.SelectedCategory = "Quality of Life";
            }
        }

        private void OnFilterVisualsClicked(object sender, RoutedEventArgs e)
        {
            if (DataContext is ModsViewModel vm)
            {
                vm.SelectedCategory = "Visuals";
            }
        }

        private void OnFilterPerformanceClicked(object sender, RoutedEventArgs e)
        {
            if (DataContext is ModsViewModel vm)
            {
                vm.SelectedCategory = "Performance";
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

        private void OnSortNameChecked(object sender, RoutedEventArgs e)
        {
            if (DataContext is ModsViewModel vm) vm.SortBy = "Name";
        }

        private void OnSortCategoryChecked(object sender, RoutedEventArgs e)
        {
            if (DataContext is ModsViewModel vm) vm.SortBy = "Category";
        }

        private void OnSortSizeChecked(object sender, RoutedEventArgs e)
        {
            if (DataContext is ModsViewModel vm) vm.SortBy = "Size";
        }

        private void OnSortStatusChecked(object sender, RoutedEventArgs e)
        {
            if (DataContext is ModsViewModel vm) vm.SortBy = "Status";
        }
    }
}
