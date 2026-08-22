using System;
using System.ComponentModel;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using PalLauncher.ViewModels;

namespace PalLauncher.Views
{
    public partial class MainWindow : Window
    {
        private int _currentTabIndex = 0;

        public MainWindow(MainViewModel viewModel)
        {
            InitializeComponent();
            DataContext = viewModel;

            viewModel.PropertyChanged += OnViewModelPropertyChanged;

            Loaded += async (s, e) =>
            {
                TriggerHologramEntrance(ViewDashboard, slideFromRight: true);
                await viewModel.InitializeAsync();
            };
        }

        private void OnViewModelPropertyChanged(object? sender, PropertyChangedEventArgs e)
        {
            if (e.PropertyName == nameof(MainViewModel.ActiveView))
            {
                Dispatcher.InvokeAsync(ApplyHolographicTabTransition);
            }
        }

        private void ApplyHolographicTabTransition()
        {
            if (DataContext is not MainViewModel vm) return;

            int newIndex = vm.ActiveView switch
            {
                "Dashboard" => 0,
                "Mods" => 1,
                "Settings" => 2,
                "Logs" => 3,
                _ => 0
            };

            if (newIndex == _currentTabIndex) return;

            bool slideFromRight = newIndex > _currentTabIndex;
            _currentTabIndex = newIndex;

            FrameworkElement? targetView = newIndex switch
            {
                0 => ViewDashboard,
                1 => ViewMods,
                2 => ViewSettings,
                3 => ViewLogs,
                _ => ViewDashboard
            };

            if (targetView != null)
            {
                TriggerHologramEntrance(targetView, slideFromRight);
            }
        }

        private static void TriggerHologramEntrance(FrameworkElement targetElement, bool slideFromRight)
        {
            var transformGroup = new TransformGroup();
            var scale = new ScaleTransform(0.95, 0.95, 450, 300);
            var translate = new TranslateTransform(slideFromRight ? 70 : -70, 0);
            var skew = new SkewTransform(slideFromRight ? -1.5 : 1.5, 0);

            transformGroup.Children.Add(scale);
            transformGroup.Children.Add(translate);
            transformGroup.Children.Add(skew);

            targetElement.RenderTransform = transformGroup;

            var storyboard = new Storyboard();

            // Holographic Fading Beam
            var fadeAnim = new DoubleAnimation
            {
                From = 0.0,
                To = 1.0,
                Duration = TimeSpan.FromMilliseconds(320),
                EasingFunction = new CubicEase { EasingMode = EasingMode.EaseOut }
            };
            Storyboard.SetTarget(fadeAnim, targetElement);
            Storyboard.SetTargetProperty(fadeAnim, new PropertyPath("Opacity"));

            // Rotating Horizontal Panel Slide
            var slideAnim = new DoubleAnimation
            {
                From = slideFromRight ? 60 : -60,
                To = 0,
                Duration = TimeSpan.FromMilliseconds(360),
                EasingFunction = new QuinticEase { EasingMode = EasingMode.EaseOut }
            };
            Storyboard.SetTarget(slideAnim, targetElement);
            Storyboard.SetTargetProperty(slideAnim, new PropertyPath("RenderTransform.Children[1].X"));

            // Depth Scale Expansion
            var scaleAnimX = new DoubleAnimation
            {
                From = 0.95,
                To = 1.0,
                Duration = TimeSpan.FromMilliseconds(360),
                EasingFunction = new QuinticEase { EasingMode = EasingMode.EaseOut }
            };
            Storyboard.SetTarget(scaleAnimX, targetElement);
            Storyboard.SetTargetProperty(scaleAnimX, new PropertyPath("RenderTransform.Children[0].ScaleX"));

            var scaleAnimY = new DoubleAnimation
            {
                From = 0.95,
                To = 1.0,
                Duration = TimeSpan.FromMilliseconds(360),
                EasingFunction = new QuinticEase { EasingMode = EasingMode.EaseOut }
            };
            Storyboard.SetTarget(scaleAnimY, targetElement);
            Storyboard.SetTargetProperty(scaleAnimY, new PropertyPath("RenderTransform.Children[0].ScaleY"));

            // Rotating Skew Rest
            var skewAnim = new DoubleAnimation
            {
                From = slideFromRight ? -1.5 : 1.5,
                To = 0.0,
                Duration = TimeSpan.FromMilliseconds(360),
                EasingFunction = new QuadraticEase { EasingMode = EasingMode.EaseOut }
            };
            Storyboard.SetTarget(skewAnim, targetElement);
            Storyboard.SetTargetProperty(skewAnim, new PropertyPath("RenderTransform.Children[2].AngleX"));

            storyboard.Children.Add(fadeAnim);
            storyboard.Children.Add(slideAnim);
            storyboard.Children.Add(scaleAnimX);
            storyboard.Children.Add(scaleAnimY);
            storyboard.Children.Add(skewAnim);

            storyboard.Begin();
        }

        private void OnNavTabChecked(object sender, RoutedEventArgs e)
        {
            if (sender is RadioButton rb && rb.CommandParameter is string viewName && DataContext is MainViewModel vm)
            {
                vm.ActiveView = viewName;
            }
        }

        private void OnNavTabClick(object sender, RoutedEventArgs e)
        {
            if (sender is RadioButton rb && rb.CommandParameter is string viewName && DataContext is MainViewModel vm)
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
