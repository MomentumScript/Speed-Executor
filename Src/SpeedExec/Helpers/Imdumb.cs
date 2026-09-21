using System;
using System.Linq;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Shapes;

public static class Helper
{
    

    

    

    

    public static void wowcoolSideBarBtn(this RadioButton radioButton)
    {
        var canvas = radioButton.Content as Canvas;
        if (canvas == null) return;

        

        var lightPaths = canvas.Children
                               .OfType<Path>()
                               .Where(p => p.Opacity < 1)
                               .ToList();

        if (!lightPaths.Any()) return;

        void AnimateOpacity(double target, double durationMs = 200)
        {
            foreach (var path in lightPaths)
            {
                var anim = new DoubleAnimation(target, TimeSpan.FromMilliseconds(durationMs));
                path.BeginAnimation(UIElement.OpacityProperty, anim);
            }
        }

        

        double initialOpacity = radioButton.IsChecked == true ? 0.8 : 0.4;
        foreach (var path in lightPaths)
            path.Opacity = initialOpacity;

        

        radioButton.Checked += (s, e) => AnimateOpacity(0.8);
        radioButton.Unchecked += (s, e) => AnimateOpacity(0.4);

        

        radioButton.MouseEnter += (s, e) => AnimateOpacity(0.6, 100);
        radioButton.MouseLeave += (s, e) =>
        {
            var target = radioButton.IsChecked == true ? 0.8 : 0.4;
            AnimateOpacity(target, 100);
        };

        

        var group = canvas.RenderTransform as TransformGroup;
        if (group == null)
        {
            group = new TransformGroup();
            group.Children.Add(new ScaleTransform(1, 1));
            group.Children.Add(new RotateTransform(0));
            canvas.RenderTransform = group;
        }
        canvas.RenderTransformOrigin = new Point(0.5, 0.5);

        ScaleTransform scale = null;
        RotateTransform rotate = null;
        foreach (var t in group.Children)
        {
            if (scale == null && t is ScaleTransform s) scale = s;
            else if (rotate == null && t is RotateTransform r) rotate = r;
        }
        if (scale == null) { scale = new ScaleTransform(1, 1); group.Children.Add(scale); }
        if (rotate == null) { rotate = new RotateTransform(0); group.Children.Add(rotate); }

        void AnimateIcon(double scaleTo, double angleTo, double ms)
        {
            var ease = new QuadraticEase { EasingMode = EasingMode.EaseOut };
            scale.BeginAnimation(ScaleTransform.ScaleXProperty,
                new DoubleAnimation(scaleTo, TimeSpan.FromMilliseconds(ms)) { EasingFunction = ease });
            scale.BeginAnimation(ScaleTransform.ScaleYProperty,
                new DoubleAnimation(scaleTo, TimeSpan.FromMilliseconds(ms)) { EasingFunction = ease });
            rotate.BeginAnimation(RotateTransform.AngleProperty,
                new DoubleAnimation(angleTo, TimeSpan.FromMilliseconds(ms)) { EasingFunction = ease });
        }

        radioButton.MouseEnter += (s, e) => AnimateIcon(1.15, 360, 300);
        radioButton.MouseLeave += (s, e) => AnimateIcon(1.0, 0, 250);
    }

    public static void epicbtn(this Button button)
    {
        epicbtn(button,
            Color.FromRgb(80, 84, 90),    

            Color.FromRgb(120, 124, 130), 

            Color.FromRgb(200, 200, 200)); 

    }

    

    

    public static void epicbtn(this Button button, Color idle, Color hover, Color pressed)
    {
        var canvas = button.Content as Canvas;
        if (canvas == null) return;

        

        var paths = canvas.Children.OfType<Path>().ToList();
        if (!paths.Any()) return;

        

        Brush idleBrush = new SolidColorBrush(idle);
        Brush hoverBrush = new SolidColorBrush(hover);
        Brush pressedBrush = new SolidColorBrush(pressed);

        void AnimateBrush(Brush target, double durationMs = 200)
        {
            

            foreach (var path in paths)
            {
                

                var anim = new ColorAnimation
                {
                    To = ((SolidColorBrush)target).Color,
                    Duration = TimeSpan.FromMilliseconds(durationMs),
                    EasingFunction = new QuadraticEase { EasingMode = EasingMode.EaseOut }
                };

                

                if (path.Fill is SolidColorBrush scb && !scb.IsFrozen)
                {
                    scb.BeginAnimation(SolidColorBrush.ColorProperty, anim);
                }
                

                else
                {
                    var newBrush = new SolidColorBrush(((SolidColorBrush)idleBrush).Color);
                    path.Fill = newBrush;
                    newBrush.BeginAnimation(SolidColorBrush.ColorProperty, anim);
                }
            }
        }

        

        AnimateBrush(idleBrush, 0);

        

        button.MouseEnter += (s, e) => AnimateBrush(hoverBrush, 150);
        button.MouseLeave += (s, e) => AnimateBrush(idleBrush, 200);

        

        button.PreviewMouseDown += (s, e) => AnimateBrush(pressedBrush, 100);
        button.PreviewMouseUp += (s, e) => AnimateBrush(hoverBrush, 150);
    }

    

    

    static void IconPivot(Canvas canvas, out ScaleTransform scale, out RotateTransform rotate)
    {
        var group = canvas.RenderTransform as TransformGroup;
        if (group == null)
        {
            group = new TransformGroup();
            group.Children.Add(new ScaleTransform(1, 1));
            group.Children.Add(new RotateTransform(0));
            canvas.RenderTransform = group;
        }
        canvas.RenderTransformOrigin = new Point(0.5, 0.5);

        scale = null;
        rotate = null;
        foreach (var t in group.Children)
        {
            if (scale == null && t is ScaleTransform s) scale = s;
            else if (rotate == null && t is RotateTransform r) rotate = r;
        }
        if (scale == null) { scale = new ScaleTransform(1, 1); group.Children.Add(scale); }
        if (rotate == null) { rotate = new RotateTransform(0); group.Children.Add(rotate); }
    }

    

    public static void hoverGrow(this Button button, double scale = 1.2, double growMs = 180)
    {
        var canvas = button.Content as Canvas;
        if (canvas == null) return;
        IconPivot(canvas, out var sc, out _);

        var ease = new QuadraticEase { EasingMode = EasingMode.EaseOut };
        button.MouseEnter += (s, e) =>
        {
            sc.BeginAnimation(ScaleTransform.ScaleXProperty, new DoubleAnimation(scale, TimeSpan.FromMilliseconds(growMs)) { EasingFunction = ease });
            sc.BeginAnimation(ScaleTransform.ScaleYProperty, new DoubleAnimation(scale, TimeSpan.FromMilliseconds(growMs)) { EasingFunction = ease });
        };
        button.MouseLeave += (s, e) =>
        {
            sc.BeginAnimation(ScaleTransform.ScaleXProperty, new DoubleAnimation(1, TimeSpan.FromMilliseconds(220)) { EasingFunction = ease });
            sc.BeginAnimation(ScaleTransform.ScaleYProperty, new DoubleAnimation(1, TimeSpan.FromMilliseconds(220)) { EasingFunction = ease });
        };
    }

    

    public static void hoverAttachShake(this Button button, double scale = 1.15, double growMs = 450)
    {
        var canvas = button.Content as Canvas;
        if (canvas == null) return;
        IconPivot(canvas, out var sc, out var rot);

        var growEase = new CubicEase { EasingMode = EasingMode.EaseOut };
        button.MouseEnter += (s, e) =>
        {
            sc.BeginAnimation(ScaleTransform.ScaleXProperty, new DoubleAnimation(scale, TimeSpan.FromMilliseconds(growMs)) { EasingFunction = growEase });
            sc.BeginAnimation(ScaleTransform.ScaleYProperty, new DoubleAnimation(scale, TimeSpan.FromMilliseconds(growMs)) { EasingFunction = growEase });

            

            var shake = new DoubleAnimationUsingKeyFrames { Duration = TimeSpan.FromMilliseconds(650) };
            shake.KeyFrames.Add(new LinearDoubleKeyFrame(9, KeyTime.FromPercent(0.00)));
            shake.KeyFrames.Add(new LinearDoubleKeyFrame(-7, KeyTime.FromPercent(0.18)));
            shake.KeyFrames.Add(new LinearDoubleKeyFrame(6, KeyTime.FromPercent(0.36)));
            shake.KeyFrames.Add(new LinearDoubleKeyFrame(-4.5, KeyTime.FromPercent(0.54)));
            shake.KeyFrames.Add(new LinearDoubleKeyFrame(2.5, KeyTime.FromPercent(0.72)));
            shake.KeyFrames.Add(new LinearDoubleKeyFrame(0, KeyTime.FromPercent(1.00)));
            rot.BeginAnimation(RotateTransform.AngleProperty, shake);
        };
        button.MouseLeave += (s, e) =>
        {
            sc.BeginAnimation(ScaleTransform.ScaleXProperty, new DoubleAnimation(1, TimeSpan.FromMilliseconds(250)) { EasingFunction = growEase });
            sc.BeginAnimation(ScaleTransform.ScaleYProperty, new DoubleAnimation(1, TimeSpan.FromMilliseconds(250)) { EasingFunction = growEase });
            rot.BeginAnimation(RotateTransform.AngleProperty, new DoubleAnimation(0, TimeSpan.FromMilliseconds(150)));
        };
    }

}
