using System.Windows;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using PalLauncher.ViewModels;

namespace PalLauncher.Views
{
    public partial class MainWindow : Window
    {
        public MainWindow(MainViewModel viewModel)
        {
            InitializeComponent();
            DataContext = viewModel;

            Loaded += async (s, e) =>
            {
                await viewModel.InitializeAsync();
            };
        }

        private void OnNavTabChecked(object sender, RoutedEventArgs e)
        {
            if (sender is System.Windows.Controls.RadioButton rb && rb.CommandParameter is string viewName && DataContext is MainViewModel vm)
            {
                vm.ActiveView = viewName;
            }
        }

        private void OnNavTabClick(object sender, RoutedEventArgs e)
        {
            if (sender is System.Windows.Controls.RadioButton rb && rb.CommandParameter is string viewName && DataContext is MainViewModel vm)
            {
                vm.ActiveView = viewName;
            }
        }

        private void OnTitleBarMouseDown(object sender, MouseButtonEventArgs e)
        {
            if (e.ChangedButton == MouseButton.Left)
            {
                if (e.ClickCount == 2)
                {
                    WindowState = WindowState == WindowState.Maximized ? WindowState.Normal : WindowState.Maximized;
                }
                else
                {
                    DragMove();
                }
            }
        }
    }
}
