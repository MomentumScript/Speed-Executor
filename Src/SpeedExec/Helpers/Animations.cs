using System;
using System.Collections.Generic;
using System.Linq;
using System.Security.Cryptography;
using System.Text;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Media;
using System.Windows.Media.Animation;

    public static class Animations
    {
        static TimeSpan onesecondnhalf = TimeSpan.FromSeconds(1.5);
        static TimeSpan half = TimeSpan.FromSeconds(0.5);
        private static IEasingFunction Smooth
        {
            get;
            set;
        }
        = new QuarticEase
        {
            EasingMode = EasingMode.EaseInOut
        };

        public static void ObjectShiftPos(DependencyObject Object, Thickness Get, Thickness Set) 

        {
            var MarginstoryBoard = new Storyboard();
            ThicknessAnimation ShiftAnimation = new ThicknessAnimation()
            {
                From = Get,
                To = Set,
                Duration = onesecondnhalf, 

                EasingFunction = Smooth,
            };
            Storyboard.SetTarget(ShiftAnimation, Object);
            Storyboard.SetTargetProperty(ShiftAnimation, new PropertyPath("Margin")); ;
            MarginstoryBoard.Children.Add(ShiftAnimation);
            MarginstoryBoard.Begin();
        }

        public static void Ind(DependencyObject Object, Thickness Get, Thickness Set) 

        {
            var MarginstoryBoard1 = new Storyboard();
            ThicknessAnimation ShiftAnimation = new ThicknessAnimation()
            {
                From = Get,
                To = Set,
                Duration = half, 

                EasingFunction = Smooth,
            };
            Storyboard.SetTarget(ShiftAnimation, Object);
            Storyboard.SetTargetProperty(ShiftAnimation, new PropertyPath("Margin")); ;
            MarginstoryBoard1.Children.Add(ShiftAnimation);
            MarginstoryBoard1.Begin();
        }

        private const double DefaultDuration = 0.5;
        private const double DefaultSlideDistance = 20;

        

        public static async Task FadeIn(this FrameworkElement element, double duration = DefaultDuration)
        {
            var storyboard = new Storyboard();
            var animation = new DoubleAnimation
            {
                From = 0,
                To = 1,
                Duration = TimeSpan.FromSeconds(duration)
            };
            Storyboard.SetTargetProperty(animation, new PropertyPath(UIElement.OpacityProperty));
            storyboard.Children.Add(animation);
            await element.BeginStoryboardAsync(storyboard);
        }

        public static async Task FadeOut(this FrameworkElement element, double duration = DefaultDuration)
        {
            var storyboard = new Storyboard();
            var animation = new DoubleAnimation
            {
                From = 1,
                To = 0,
                Duration = TimeSpan.FromSeconds(duration)
            };
            Storyboard.SetTargetProperty(animation, new PropertyPath(UIElement.OpacityProperty));
            storyboard.Children.Add(animation);
            await element.BeginStoryboardAsync(storyboard);
        }

        

        public static async Task FadeInSlideDown(this FrameworkElement element, double duration = DefaultDuration, double distance = DefaultSlideDistance)
        {
            EnsureTranslateTransform(element);
            var storyboard = new Storyboard();

            AddFadeAnimation(storyboard, 0, 1, duration);
            AddSlideAnimation(storyboard, -distance, 0, duration, "Y", EasingMode.EaseOut);

            await element.BeginStoryboardAsync(storyboard);
        }

        public static async Task FadeOutSlideDown(this FrameworkElement element, double duration = DefaultDuration, double distance = DefaultSlideDistance)
        {
            EnsureTranslateTransform(element);
            var storyboard = new Storyboard();

            AddFadeAnimation(storyboard, 1, 0, duration);
            AddSlideAnimation(storyboard, 0, distance, duration, "Y", EasingMode.EaseIn);

            await element.BeginStoryboardAsync(storyboard);
        }

        

        public static async Task FadeInSlideUp(this FrameworkElement element, double duration = DefaultDuration, double distance = DefaultSlideDistance)
        {
            EnsureTranslateTransform(element);
            var storyboard = new Storyboard();

            AddFadeAnimation(storyboard, 0, 1, duration);
            AddSlideAnimation(storyboard, distance, 0, duration, "Y", EasingMode.EaseOut);

            await element.BeginStoryboardAsync(storyboard);
        }

        public static async Task FadeOutSlideUp(this FrameworkElement element, double duration = DefaultDuration, double distance = DefaultSlideDistance)
        {
            EnsureTranslateTransform(element);
            var storyboard = new Storyboard();

            AddFadeAnimation(storyboard, 1, 0, duration);
            AddSlideAnimation(storyboard, 0, -distance, duration, "Y", EasingMode.EaseIn);

            await element.BeginStoryboardAsync(storyboard);
        }

        

        public static async Task FadeInSlideLeft(this FrameworkElement element, double duration = DefaultDuration, double distance = DefaultSlideDistance)
        {
            EnsureTranslateTransform(element);
            var storyboard = new Storyboard();

            AddFadeAnimation(storyboard, 0, 1, duration);
            AddSlideAnimation(storyboard, distance, 0, duration, "X", EasingMode.EaseOut);

            await element.BeginStoryboardAsync(storyboard);
        }

        public static async Task FadeOutSlideLeft(this FrameworkElement element, double duration = DefaultDuration, double distance = DefaultSlideDistance)
        {
            EnsureTranslateTransform(element);
            var storyboard = new Storyboard();

            AddFadeAnimation(storyboard, 1, 0, duration);
            AddSlideAnimation(storyboard, 0, -distance, duration, "X", EasingMode.EaseIn);

            await element.BeginStoryboardAsync(storyboard);
        }

        

        public static async Task FadeInSlideRight(this FrameworkElement element, double duration = DefaultDuration, double distance = DefaultSlideDistance)
        {
            EnsureTranslateTransform(element);
            var storyboard = new Storyboard();

            AddFadeAnimation(storyboard, 0, 1, duration);
            AddSlideAnimation(storyboard, -distance, 0, duration, "X", EasingMode.EaseOut);

            await element.BeginStoryboardAsync(storyboard);
        }

        public static async Task FadeOutSlideRight(this FrameworkElement element, double duration = DefaultDuration, double distance = DefaultSlideDistance)
        {
            EnsureTranslateTransform(element);
            var storyboard = new Storyboard();

            AddFadeAnimation(storyboard, 1, 0, duration);
            AddSlideAnimation(storyboard, 0, distance, duration, "X", EasingMode.EaseIn);

            await element.BeginStoryboardAsync(storyboard);
        }

        

        private static void EnsureTranslateTransform(FrameworkElement element)
        {
            if (element.RenderTransform == null || !(element.RenderTransform is TranslateTransform))
            {
                element.RenderTransform = new TranslateTransform();
                element.RenderTransformOrigin = new Point(0.5, 0.5);
            }
        }

        private static void AddFadeAnimation(Storyboard storyboard, double from, double to, double duration)
        {
            var animation = new DoubleAnimation
            {
                From = from,
                To = to,
                Duration = TimeSpan.FromSeconds(duration)
            };
            Storyboard.SetTargetProperty(animation, new PropertyPath(UIElement.OpacityProperty));
            storyboard.Children.Add(animation);
        }

        private static void AddSlideAnimation(Storyboard storyboard, double from, double to, double duration, string axis, EasingMode easingMode)
        {
            var animation = new DoubleAnimation
            {
                From = from,
                To = to,
                Duration = TimeSpan.FromSeconds(duration),
                EasingFunction = new QuadraticEase { EasingMode = easingMode }
            };
            Storyboard.SetTargetProperty(animation, new PropertyPath($"(UIElement.RenderTransform).(TranslateTransform.{axis})"));
            storyboard.Children.Add(animation);
        }

        private static async Task BeginStoryboardAsync(this FrameworkElement element, Storyboard storyboard)
        {
            var completionSource = new TaskCompletionSource<bool>();

            storyboard.Completed += (s, e) => completionSource.TrySetResult(true);
            storyboard.Freeze(); 

            element.Dispatcher.Invoke(() => storyboard.Begin(element));

            await completionSource.Task;
        }



        public static void StartSpin(UIElement element, double speedSeconds = 1)
        {
            var rotate = new RotateTransform();
            element.RenderTransform = rotate;
            element.RenderTransformOrigin = new Point(0.5, 0.5);

            var animation = new DoubleAnimation
            {
                From = 0,
                To = 360,
                Duration = TimeSpan.FromSeconds(speedSeconds),
                RepeatBehavior = RepeatBehavior.Forever
            };

            rotate.BeginAnimation(RotateTransform.AngleProperty, animation);
        }

        public static void StopSpin(UIElement element)
        {
            element.RenderTransform = null;
        }

    }
