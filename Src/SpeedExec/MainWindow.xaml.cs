using Microsoft.Win32;
using System;
using System.Collections.Generic;
using System.Diagnostics;
using System.Globalization;
using System.IO;
using System.Linq;
using System.Text;
using System.Text.Json;
using System.Threading;
using System.Threading.Tasks;
using System.Windows;
using System.Windows.Controls;
using System.Windows.Controls.Primitives;
using System.Windows.Input;
using System.Windows.Media;
using System.Windows.Media.Animation;
using System.Windows.Media.Imaging;
using System.Windows.Threading;

namespace SpeedExecutor
{
    

    

    


    public partial class MainWindow : Window
    {
        private readonly List<ScriptFile> _allFiles = new List<ScriptFile>();
        private readonly Dictionary<string, ImageSource> _iconCache = new Dictionary<string, ImageSource>();
        private string _scriptsFolder;
        private string _lastFileSignature;
        private bool _chatBusy;
        private bool _chatWarmed;
        private bool _exiting;
        private bool _attached;
        private bool _aiReady;
        private bool _profileLoading;
        private bool _loadingBusy;
        private readonly HashSet<uint> _seenInjectPids = new HashSet<uint>();
        private RobloxProfile.Info _profile;
        private BitmapImage _avatar;

        private void PlayInjectSound()
        {
            Task.Run(() =>
            {
                try
                {
                    var asm = System.Reflection.Assembly.GetExecutingAssembly();
                    using (var stream = asm.GetManifestResourceStream("SpeedExec.inject.wav"))
                    {
                        if (stream == null) return;
                        var player = new System.Media.SoundPlayer(stream);
                        player.PlaySync();
                    }
                }
                catch { }
            });
        }

        public MainWindow()
        {
            InitializeComponent();
            try { Config.Load(); } catch { }
            DashboardBtn.wowcoolSideBarBtn();
            EditorBtn.wowcoolSideBarBtn();
            ScriptHubBtn.wowcoolSideBarBtn();
            SettingsBtn.wowcoolSideBarBtn();
            ChatBtn.wowcoolSideBarBtn();

            ExecuteBtn.epicbtn();
            ClearBtn.epicbtn();
            OpenFileBtn.epicbtn();
            SaveFileBtn.epicbtn();
            AttachBtn.epicbtn();

            ExecuteBtn.hoverGrow();
            AttachBtn.hoverAttachShake();

            ExitBtn.epicbtn();
            MinimizeBtn.epicbtn();

            KillRblxBtn.epicbtn();
            RestartBtn.epicbtn();

            DashboardBorder.Visibility = Visibility.Visible;
            EditorBorder.Visibility = Visibility.Hidden;
            ScriptHubBorder.Visibility = Visibility.Hidden;
            SettingsBorder.Visibility = Visibility.Hidden;
            ChatBorder.Visibility = Visibility.Hidden;

            BuildChangelog();
            UpdateDashboard();

            InitAutoSave();
            WebRelated();
        }

        private DispatcherTimer _autoSaveTimer;

        private void InitAutoSave()
        {
            _autoSaveTimer = new DispatcherTimer();
            _autoSaveTimer.Interval = TimeSpan.FromSeconds(5);
            _autoSaveTimer.Tick += async (s, e) =>
            {
                await SaveStateAndTabsAsync();
            };
            _autoSaveTimer.Start();
        }

        public async Task SaveStateAndTabsAsync()
        {
            try
            {
                Config.SaveSettings();

                if (Editor != null && Editor.CoreWebView2 != null)
                {
                    string tabsJson = await Editor.ExecuteScriptAsync("JSON.stringify(exportTabs())");
                    if (!string.IsNullOrEmpty(tabsJson) && tabsJson != "null")
                    {
                        string rawJson = System.Text.Json.JsonSerializer.Deserialize<string>(tabsJson);
                        if (!string.IsNullOrEmpty(rawJson))
                        {
                            string tabsPath = System.IO.Path.Combine(Installer.ConfigDir(), "tabs.txt");
                            System.IO.File.WriteAllText(tabsPath, rawJson);
                        }
                    }
                }
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine("AutoSave error: " + ex.Message);
            }
        }

        private async Task LoadSavedTabsAsync()
        {
            try
            {
                string tabsPath = System.IO.Path.Combine(Installer.ConfigDir(), "tabs.txt");
                if (System.IO.File.Exists(tabsPath))
                {
                    string jsonContent = System.IO.File.ReadAllText(tabsPath);
                    if (!string.IsNullOrWhiteSpace(jsonContent))
                    {
                        string jsonEscaped = System.Text.Json.JsonSerializer.Serialize(jsonContent);
                        await Editor.ExecuteScriptAsync($"openTabs(JSON.parse({jsonEscaped}))");
                    }
                }
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine("LoadSavedTabs error: " + ex.Message);
            }
        }

        public async void WebRelated()
        {
            string editorPath = new Uri($"file:///{System.IO.Path.Combine(Directory.GetCurrentDirectory(), "Editor", "monaco.html")}").ToString();

            await Editor.EnsureCoreWebView2Async(null);
            Editor.DefaultBackgroundColor = System.Drawing.Color.Transparent;
            Editor.CoreWebView2.Navigate(editorPath);
            Editor.NavigationCompleted += async (s, e) =>
            {
                if (e.IsSuccess)
                {
                    await LoadSavedTabsAsync();
                }
            };

            await ScriptHub.EnsureCoreWebView2Async(null);
            ScriptHub.DefaultBackgroundColor = System.Drawing.Color.Transparent;
            ScriptHub.CoreWebView2.Navigate("https://v0-speedexecutor-scripthub.vercel.app/");
        }



        private void TitleBar_MouseLeftButtonDown(object sender, MouseButtonEventArgs e)
        {
            if (e.ChangedButton != MouseButton.Left) return;
            if (e.ButtonState != MouseButtonState.Pressed) return;
            try { DragMove(); } catch { }
        }

        private void ResizeGrip_DragDelta(object sender, DragDeltaEventArgs e)
        {
            double w = (double.IsNaN(Width) ? ActualWidth : Width) + e.HorizontalChange;
            double h = (double.IsNaN(Height) ? ActualHeight : Height) + e.VerticalChange;
            Width = Math.Max(MinWidth, w);
            Height = Math.Max(MinHeight, h);
        }

        private void DashboardBtn_Click(object sender, RoutedEventArgs e)
        {
            Animations.Ind(Indicator, Indicator.Margin, new Thickness(5, 17, 47, 401));

            DashboardBorder.Visibility = Visibility.Visible;
            EditorBorder.Visibility = Visibility.Hidden;
            ScriptHubBorder.Visibility = Visibility.Hidden;
            SettingsBorder.Visibility = Visibility.Hidden;
            ChatBorder.Visibility = Visibility.Hidden;

            if (_attached && _profile == null) _ = LoadProfileAsync();
            UpdateDashboard();
        }

        private void EditorBtn_Click(object sender, RoutedEventArgs e)
        {
            Animations.Ind(Indicator, Indicator.Margin, new Thickness(5, 57, 47, 361));

            DashboardBorder.Visibility = Visibility.Hidden;
            EditorBorder.Visibility = Visibility.Visible;
            ScriptHubBorder.Visibility = Visibility.Hidden;
            SettingsBorder.Visibility = Visibility.Hidden;
            ChatBorder.Visibility = Visibility.Hidden;
        }

        private void ScriptHubBtn_Click(object sender, RoutedEventArgs e)
        {
            Animations.Ind(Indicator, Indicator.Margin, new Thickness(5, 97, 47, 321));

            DashboardBorder.Visibility = Visibility.Hidden;
            EditorBorder.Visibility = Visibility.Hidden;
            ScriptHubBorder.Visibility = Visibility.Visible;
            SettingsBorder.Visibility = Visibility.Hidden;
            ChatBorder.Visibility = Visibility.Hidden;
        }

        private void SettingsBtn_Click(object sender, RoutedEventArgs e)
        {
            Animations.Ind(Indicator, Indicator.Margin, new Thickness(5, 137, 47, 281));

            DashboardBorder.Visibility = Visibility.Hidden;
            EditorBorder.Visibility = Visibility.Hidden;
            ScriptHubBorder.Visibility = Visibility.Hidden;
            SettingsBorder.Visibility = Visibility.Visible;
            ChatBorder.Visibility = Visibility.Hidden;
        }

        private void ChatBtn_Click(object sender, RoutedEventArgs e)
        {
            Animations.Ind(Indicator, Indicator.Margin, new Thickness(5, 177, 47, 241));

            DashboardBorder.Visibility = Visibility.Hidden;
            EditorBorder.Visibility = Visibility.Hidden;
            ScriptHubBorder.Visibility = Visibility.Hidden;
            SettingsBorder.Visibility = Visibility.Hidden;
            ChatBorder.Visibility = Visibility.Visible;
            WarmChat();
            ChatInput.Focus();
        }

        private void MinimizeBtn_Click(object sender, RoutedEventArgs e)
        {
            this.WindowState = WindowState.Minimized;
        }

        private async void ExitBtn_Click(object sender, RoutedEventArgs e)
        {
            if (_exiting) return;
            _exiting = true;

            Editor.Visibility = Visibility.Hidden;
            ScriptHub.Visibility = Visibility.Hidden;
            _ = Animations.FadeOut(this.MainBorder, 0.7);
            await Task.Delay(750);
            Environment.Exit(0);
        }

        private void Window_Loaded(object sender, RoutedEventArgs e)
        {
            _scriptsFolder = System.IO.Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "Scripts");
            if (!Directory.Exists(_scriptsFolder))
                Directory.CreateDirectory(_scriptsFolder);

            InitFileWatcher();
            LoadFiles();
            _ = Animations.FadeIn(this.MainBorder, 0.7);

            Bridge.ConsoleLine += OnBridgeConsoleLine;
            Bridge.ConsoleCleared += OnBridgeConsoleCleared;
            Bridge.SetClipboard = text => {
                try { Dispatcher.Invoke(() => Clipboard.SetText(text ?? "")); } catch { }
            };
            Bridge.GetClipboard = () => {
                string r = "";
                try { Dispatcher.Invoke(() => r = Clipboard.GetText()); } catch { }
                return r;
            };
            AppendConsole("SpeedExecutor console ready.");
        }

        private void OnBridgeConsoleLine(string line)
        {
            try { Dispatcher.BeginInvoke(new Action(() => AppendConsole(line))); } catch { }
        }

        private void OnBridgeConsoleCleared()
        {
            try { Dispatcher.BeginInvoke(new Action(() => { try { ConsoleBox.Clear(); } catch { } })); } catch { }
        }

        private void AppendConsole(string line)
        {
            try
            {
                if (line == null) return;
                if (ConsoleBox.Text.Length > 200000)
                    ConsoleBox.Text = ConsoleBox.Text.Substring(ConsoleBox.Text.Length - 100000);
                ConsoleBox.AppendText(line + Environment.NewLine);
                ConsoleBox.ScrollToEnd();
            }
            catch { }
        }

        private void ConsoleCopyBtn_Click(object sender, RoutedEventArgs e)
        {
            try { if (!string.IsNullOrEmpty(ConsoleBox.Text)) Clipboard.SetText(ConsoleBox.Text); } catch { }
        }

        private void ConsoleClearBtn_Click(object sender, RoutedEventArgs e)
        {
            try { ConsoleBox.Clear(); } catch { }
        }

        private DispatcherTimer _refreshTimer;

        public void InitFileWatcher()
        {
            _refreshTimer = new DispatcherTimer();
            _refreshTimer.Interval = TimeSpan.FromSeconds(3);
            _refreshTimer.Tick += (s, e) => LoadFiles();
            _refreshTimer.Start();
        }

        private void LoadFiles()
        {
            try
            {
                var paths = Directory.GetFiles(_scriptsFolder, "*.*")
                    .Where(f => f.EndsWith(".txt", StringComparison.OrdinalIgnoreCase) ||
                                f.EndsWith(".lua", StringComparison.OrdinalIgnoreCase) ||
                                f.EndsWith(".luau", StringComparison.OrdinalIgnoreCase))
                    .OrderBy(f => System.IO.Path.GetFileName(f), StringComparer.OrdinalIgnoreCase)
                    .ToList();

                var signature = new StringBuilder();
                var files = new List<ScriptFile>(paths.Count);

                foreach (var path in paths)
                {
                    signature.Append(path).Append('|')
                             .Append(File.GetLastWriteTimeUtc(path).Ticks).Append(';');

                    files.Add(new ScriptFile
                    {
                        FullPath = path,
                        Name = System.IO.Path.GetFileName(path),
                        Icon = GetIconFor(path)
                    });
                }

                string sig = signature.ToString();
                if (sig == _lastFileSignature) return;
                _lastFileSignature = sig;

                _allFiles.Clear();
                _allFiles.AddRange(files);
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine("Error loading files: " + ex.Message);
            }

            ApplyFilter();
        }

        private ImageSource GetIconFor(string filePath)
        {
            string key = System.IO.Path.GetExtension(filePath)?.ToLowerInvariant() ?? "";
            if (_iconCache.TryGetValue(key, out var cached)) return cached;

            var icon = GetFileIcon(filePath);
            _iconCache[key] = icon;
            return icon;
        }

        private ImageSource GetFileIcon(string filePath)
        {
            try
            {
                var drawingVisual = new DrawingVisual();
                using (var drawingContext = drawingVisual.RenderOpen())
                {
                    var gradBrush = new LinearGradientBrush(
                        Color.FromRgb(255, 255, 255),
                        Color.FromRgb(150, 150, 150), 
                        45.0);

                    var moonBrush = new LinearGradientBrush(
                        Color.FromRgb(200, 200, 200),
                        Color.FromRgb(255, 255, 255),
                        45.0);

                    var glowBrush = new RadialGradientBrush(
                        Color.FromArgb(80, 135, 206, 250),
                        Color.FromArgb(0, 135, 206, 250));
                    glowBrush.Center = new Point(0.5, 0.5);
                    glowBrush.GradientOrigin = new Point(0.5, 0.5);
                    glowBrush.RadiusX = 0.8;
                    glowBrush.RadiusY = 0.8;

                    drawingContext.DrawEllipse(glowBrush, null, new Point(8, 8), 9, 9);

                    drawingContext.DrawEllipse(gradBrush, null, new Point(8, 8), 7, 7);

                    drawingContext.DrawEllipse(moonBrush, null, new Point(12, 4), 3, 3);
                }

                var bitmap = new RenderTargetBitmap(16, 16, 96, 96, PixelFormats.Pbgra32);
                bitmap.Render(drawingVisual);
                return bitmap;
            }
            catch
            {
                

                var drawingVisual = new DrawingVisual();
                using (var drawingContext = drawingVisual.RenderOpen())
                {
                    drawingContext.DrawEllipse(Brushes.Gray, null, new Point(8, 8), 7, 7);
                }
                var bitmap = new RenderTargetBitmap(16, 16, 96, 96, PixelFormats.Pbgra32);
                bitmap.Render(drawingVisual);
                return bitmap;
            }
        }


        private void ApplyFilter()
        {
            string filter = SearchTextBox?.Text?.ToLowerInvariant() ?? "";

            var filtered = (string.IsNullOrEmpty(filter)
                ? _allFiles
                : _allFiles.Where(f => f.Name.ToLowerInvariant().Contains(filter))).ToList();

            FileListView.ItemsSource = filtered;

            if (FilesEmptyText != null)
                FilesEmptyText.Visibility = filtered.Count == 0 ? Visibility.Visible : Visibility.Collapsed;

            UpdateDashboard();
        }

        private void SearchTextBox_TextChanged(object sender, TextChangedEventArgs e)
        {
            if (SearchPlaceholder != null)
                SearchPlaceholder.Visibility = string.IsNullOrEmpty(SearchTextBox.Text)
                    ? Visibility.Visible
                    : Visibility.Collapsed;

            ApplyFilter();
        }

        private async void FileListView_MouseDoubleClick(object sender, System.Windows.Input.MouseButtonEventArgs e)
        {
            if (FileListView.SelectedItem is ScriptFile selectedFile)
            {
                try
                {
                    string content = File.ReadAllText(selectedFile.FullPath);

                    if (Editor != null && Editor.CoreWebView2 != null)
                    {
                        string escapedContent = JsonSerializer.Serialize(content);
                        await Editor.CoreWebView2.ExecuteScriptAsync($"setValue({escapedContent})");
                    }
                    else
                    {
                        System.Diagnostics.Debug.WriteLine("Editor is not ready. Please wait for initialization.");
                    }
                }
                catch (Exception ex)
                {
                    System.Diagnostics.Debug.WriteLine("Error reading file: " + ex.Message);
                }
            }
        }

        public async void SetEditorContent(string content)
        {
            await Editor.CoreWebView2.ExecuteScriptAsync($"setValue({System.Text.Json.JsonSerializer.Serialize(content)})");
        }

        private async Task<string> GetEditorValueAsync()
        {
            string raw = await Editor.ExecuteScriptAsync("getValue();");
            if (string.IsNullOrEmpty(raw)) return "";

            try
            {
                return JsonSerializer.Deserialize<string>(raw) ?? "";
            }
            catch
            {
                return raw.Trim('"');
            }
        }

        private async Task SetEditorValueAsync(string value)
        {
            await Editor.ExecuteScriptAsync($"setValue({JsonSerializer.Serialize(value ?? "")});");
        }

        private async void ExecuteBtn_Click(object sender, RoutedEventArgs e)
        {
            string why;
            if (!Executor.Reattach(out why))
            {
                SetStatusCircle(false);
                return;
            }
            Executor.EnsureBridge();
            if (!Executor.IsInjected())
            {
                SetStatusCircle(false);
                return;
            }
            string editorcontent = await GetEditorValueAsync();
            if (string.IsNullOrEmpty(editorcontent)) return;
            string log;
            bool ok = Executor.Execute(editorcontent, out log);
            if (!ok) AppendConsole(log);
            SetStatusCircle(ok);
        }

        private async void ClearBtn_Click(object sender, RoutedEventArgs e)
        {
            await SetEditorValueAsync("");
        }

        private async void OpenFileBtn_Click(object sender, RoutedEventArgs e)
        {
            OpenFileDialog ofd = new OpenFileDialog()
            {
                Filter = "Open File|*.txt;*.lua;*.luau",
                Title = "Open a file"
            };
            if (ofd.ShowDialog() == true)
            {
                string fileContent = File.ReadAllText(ofd.FileName);
                await SetEditorValueAsync(fileContent);
            }
        }

        private async void SaveFileBtn_Click(object sender, RoutedEventArgs e)
        {
            string code = await GetEditorValueAsync();

            SaveFileDialog sfd = new SaveFileDialog()
            {
                Filter = "Save File|*.txt;*.lua;*.luau",
                Title = "Save file"
            };
            if (sfd.ShowDialog() == true)
            {
                File.WriteAllText(sfd.FileName, code);
            }
        }

        private void AttachBtn_Click(object sender, RoutedEventArgs e)
        {
            _ = ShowClientsOverlay();
        }

        private void DashAttachBtn_Click(object sender, RoutedEventArgs e)
        {
            _ = ShowClientsOverlay();
        }
        // ── Clients sidebar overlay ────────────────────────────────────────
        private bool _clientsOpen;
        private bool _clientsBusy;
        private readonly System.Collections.ObjectModel.ObservableCollection<ClientVm> _injectedClients
            = new System.Collections.ObjectModel.ObservableCollection<ClientVm>();
        private readonly System.Collections.ObjectModel.ObservableCollection<ClientVm> _notInjectedClients
            = new System.Collections.ObjectModel.ObservableCollection<ClientVm>();

        /// <summary>
        /// One Roblox instance shown in the Clients panel. Implements
        /// INotifyPropertyChanged so the row updates in place while injecting
        /// rather than being torn down and rebuilt.
        /// </summary>
        public sealed class ClientVm : System.ComponentModel.INotifyPropertyChanged
        {
            public event System.ComponentModel.PropertyChangedEventHandler PropertyChanged;
            private void Raise(string p) => PropertyChanged?.Invoke(this,
                new System.ComponentModel.PropertyChangedEventArgs(p));

            public uint Pid { get; }
            public string PidLabel => "PID · " + Pid;

            public ClientVm(uint pid) { Pid = pid; }

            private string _name = "Loading…";
            public string Name { get => _name; set { _name = value; Raise(nameof(Name)); } }

            private System.Windows.Media.ImageSource _avatar;
            public System.Windows.Media.ImageSource Avatar
            { get => _avatar; set { _avatar = value; Raise(nameof(Avatar)); } }

            private bool _injected;
            public bool Injected
            {
                get => _injected;
                set
                {
                    _injected = value;
                    Raise(nameof(Injected));
                    Raise(nameof(StatusText));
                    Raise(nameof(StatusBg));
                    Raise(nameof(StatusFg));
                }
            }

            private string _actionText = "Inject";
            public string ActionText
            { get => _actionText; set { _actionText = value; Raise(nameof(ActionText)); } }

            private bool _canInject = true;
            public bool CanInject
            { get => _canInject; set { _canInject = value; Raise(nameof(CanInject)); } }

            private string _statusOverride;
            public string StatusOverride
            {
                get => _statusOverride;
                set
                {
                    _statusOverride = value;
                    Raise(nameof(StatusText));
                    Raise(nameof(StatusBg));
                    Raise(nameof(StatusFg));
                }
            }

            public string StatusText =>
                _statusOverride ?? (Injected ? "Injected" : "Not injected");

            public System.Windows.Media.Brush StatusBg => Brush(
                _statusOverride != null ? "#FF3A2E12" : Injected ? "#FF203019" : "#FF2D2D30");

            public System.Windows.Media.Brush StatusFg => Brush(
                _statusOverride != null ? "#FFE8A800" : Injected ? "#FF7BC96F" : "#FF969696");

            private static System.Windows.Media.Brush Brush(string hex)
            {
                var b = new System.Windows.Media.SolidColorBrush(
                    (System.Windows.Media.Color)System.Windows.Media.ColorConverter.ConvertFromString(hex));
                b.Freeze();
                return b;
            }
        }

        private void ClientsRefresh_Click(object sender, RoutedEventArgs e) => RefreshClientsList();

        private void ClientsClose_Click(object sender, RoutedEventArgs e) => _ = HideClientsOverlay();

        public async System.Threading.Tasks.Task ShowClientsOverlay()
        {
            if (_clientsOpen || _loadingBusy) return;
            _clientsOpen = true;

            if (InjectedItems.ItemsSource == null)
            {
                InjectedItems.ItemsSource = _injectedClients;
                NotInjectedItems.ItemsSource = _notInjectedClients;
            }

            // Blur everything behind the panel. WebView2 is HWND-hosted so a WPF
            // BlurEffect can't reach it — hide the two web views for the duration
            // so no crisp Monaco pokes through the blurred surface.
            MainContent.Effect = new System.Windows.Media.Effects.BlurEffect
            {
                Radius = 20,
                KernelType = System.Windows.Media.Effects.KernelType.Gaussian,
                RenderingBias = System.Windows.Media.Effects.RenderingBias.Performance
            };
            MainContent.IsHitTestVisible = false;
            try { Editor.Visibility = Visibility.Hidden; } catch { }
            try { ScriptHub.Visibility = Visibility.Hidden; } catch { }

            ClientsOverlay.Visibility = Visibility.Visible;
            ClientsOverlay.Opacity = 0;
            ClientsSidebarSlide.X = 380;

            RefreshClientsList();

            var fade = new System.Windows.Media.Animation.DoubleAnimation(0, 1,
                TimeSpan.FromMilliseconds(200))
            {
                EasingFunction = new System.Windows.Media.Animation.QuadraticEase
                { EasingMode = System.Windows.Media.Animation.EasingMode.EaseOut }
            };
            ClientsOverlay.BeginAnimation(UIElement.OpacityProperty, fade);

            // Slight overshoot on the way in so it feels physical instead of linear.
            var slide = new System.Windows.Media.Animation.DoubleAnimation(380, 0,
                TimeSpan.FromMilliseconds(380))
            {
                EasingFunction = new System.Windows.Media.Animation.BackEase
                {
                    EasingMode = System.Windows.Media.Animation.EasingMode.EaseOut,
                    Amplitude = 0.25
                }
            };
            ClientsSidebarSlide.BeginAnimation(TranslateTransform.XProperty, slide);
            await System.Threading.Tasks.Task.Delay(380);
        }

        public async System.Threading.Tasks.Task HideClientsOverlay()
        {
            if (!_clientsOpen) return;
            _clientsOpen = false;

            var slide = new System.Windows.Media.Animation.DoubleAnimation(
                ClientsSidebarSlide.X, 380, TimeSpan.FromMilliseconds(280))
            {
                EasingFunction = new System.Windows.Media.Animation.CubicEase
                { EasingMode = System.Windows.Media.Animation.EasingMode.EaseIn }
            };
            ClientsSidebarSlide.BeginAnimation(TranslateTransform.XProperty, slide);

            var fade = new System.Windows.Media.Animation.DoubleAnimation(1, 0,
                TimeSpan.FromMilliseconds(280))
            {
                EasingFunction = new System.Windows.Media.Animation.QuadraticEase
                { EasingMode = System.Windows.Media.Animation.EasingMode.EaseIn }
            };
            fade.Completed += (s, e) =>
            {
                ClientsOverlay.Visibility = Visibility.Collapsed;
                MainContent.Effect = null;
                MainContent.IsHitTestVisible = true;
                try { Editor.Visibility = Visibility.Visible; } catch { }
                try { ScriptHub.Visibility = Visibility.Visible; } catch { }
            };
            ClientsOverlay.BeginAnimation(UIElement.OpacityProperty, fade);
            await System.Threading.Tasks.Task.Delay(290);
        }

        private void RefreshClientsList()
        {
            var pids = Multi.AllRoblox();
            ClientsInstanceCount.Text = pids.Count + (pids.Count == 1 ? " Instance" : " Instances");

            // Drop rows whose process is gone.
            foreach (var vm in _injectedClients.Where(v => !pids.Contains(v.Pid)).ToList())
                _injectedClients.Remove(vm);
            foreach (var vm in _notInjectedClients.Where(v => !pids.Contains(v.Pid)).ToList())
                _notInjectedClients.Remove(vm);

            foreach (var vm in _injectedClients.ToList())
            {
                if (!IsStillInjected(vm.Pid))
                {
                    vm.Injected = false;
                    vm.ActionText = "Inject";
                    vm.CanInject = true;
                    vm.StatusOverride = null;
                    _seenInjectPids.Remove(vm.Pid);
                    _injectedClients.Remove(vm);
                    if (!_notInjectedClients.Any(v => v.Pid == vm.Pid))
                        _notInjectedClients.Add(vm);
                }
            }

            foreach (uint pid in pids)
            {
                if (_injectedClients.Any(v => v.Pid == pid)) continue;
                if (_notInjectedClients.Any(v => v.Pid == pid)) continue;
                var vm = new ClientVm(pid);
                _notInjectedClients.Add(vm);
                _ = HydrateClientAsync(vm);
            }

            UpdateClientsSectionCounts();
        }

        private bool IsStillInjected(uint pid)
        {
            try
            {
                if (Mem.Pid != pid) return true;
                if (Executor.DatamodelName != "Ugc") return false;
                return Executor.IsInjected();
            }
            catch { return true; }
        }

        private void UpdateClientsSectionCounts()
        {
            InjectedCountLabel.Text = _injectedClients.Count.ToString();
            NotInjectedCountLabel.Text = _notInjectedClients.Count.ToString();
            InjectedEmpty.Visibility = _injectedClients.Count == 0
                ? Visibility.Visible : Visibility.Collapsed;
            NotInjectedEmpty.Visibility = _notInjectedClients.Count == 0
                ? Visibility.Visible : Visibility.Collapsed;
        }

        private async System.Threading.Tasks.Task HydrateClientAsync(ClientVm vm)
        {
            try
            {
                // RobloxProfile.FindUserId inspects the currently attached client
                // rather than taking a pid, so with several instances open only
                // the attached one resolves a real name; the rest stay generic.
                long uid = await System.Threading.Tasks.Task.Run(() => RobloxProfile.FindUserId());
                if (uid == 0) { vm.Name = "Roblox " + vm.Pid; return; }

                var info = await RobloxProfile.FetchAsync(uid);
                vm.Name = info?.Name ?? ("Roblox " + vm.Pid);
                try { vm.Avatar = await RobloxProfile.FetchAvatarAsync(uid); } catch { }
            }
            catch { vm.Name = "Roblox " + vm.Pid; }
        }

        private void ClientInject_Click(object sender, RoutedEventArgs e)
        {
            if ((sender as FrameworkElement)?.Tag is ClientVm vm)
                _ = InjectClientAsync(vm);
        }

        private async System.Threading.Tasks.Task InjectClientAsync(ClientVm vm)
        {
            if (_clientsBusy || vm.Injected) return;
            _clientsBusy = true;
            try
            {
                vm.CanInject = false;
                vm.ActionText = "Fetching offsets…";
                vm.StatusOverride = "Working";

                // This is the step the earlier version skipped, which is why every
                // inject reported Failed: the backend has no offsets until we
                // fetch them for this client build and push them across.
                string version = GameVersion.Detect(vm.Pid) ?? Off.ClientVersion;
                try { await OffsetFetcher.FetchAsync(version); } catch { }
                Executor.SetOffsets(Off.OffsetsText());

                vm.ActionText = "Attaching…";

                string log = null;
                string why = null;
                bool attached = false;
                bool already = false;
                string dm = null;

                await System.Threading.Tasks.Task.Run(() =>
                {
                    attached = Executor.Reattach(out why);
                    if (!attached) return;
                    Executor.EnsureBridge();
                    dm = Executor.DatamodelName;
                    already = Executor.IsInjected();
                });

                if (!attached)
                {
                    FailRow(vm, "Attach failed: " + (why ?? "unknown reason"));
                    return;
                }
                if (dm != "Ugc")
                {
                    FailRow(vm, "Join a game first (DataModel is '"
                        + (string.IsNullOrEmpty(dm) ? "(none)" : dm) + "')");
                    return;
                }

                bool ok = already;
                if (!already)
                {
                    vm.ActionText = "Injecting…";
                    await System.Threading.Tasks.Task.Run(() =>
                    {
                        string l;
                        ok = Executor.Inject(out l);
                        log = l;
                    });
                }

                if (!ok) { FailRow(vm, log ?? "Injection failed"); return; }

                // Promote the row into the Injected section.
                vm.StatusOverride = null;
                vm.Injected = true;
                vm.ActionText = "Injected";
                vm.CanInject = false;
                _seenInjectPids.Add(vm.Pid);

                _notInjectedClients.Remove(vm);
                if (!_injectedClients.Contains(vm)) _injectedClients.Add(vm);
                UpdateClientsSectionCounts();

                SetStatusCircle(true);
                AppendConsole("Injected.");
                PlayInjectSound();

                // Let the user see it land in the Injected section, then close.
                await System.Threading.Tasks.Task.Delay(2000);
                await HideClientsOverlay();
            }
            finally { _clientsBusy = false; }
        }

        private void FailRow(ClientVm vm, string message)
        {
            vm.StatusOverride = null;
            vm.ActionText = "Retry";
            vm.CanInject = true;
            SetStatusCircle(false);
            AppendConsole("Attach failed: " + message);
        }

        private async void AttachRoblox()
        {
            if (_loadingBusy) return;

            

            

            

            uint pid = Executor.FindPid("RobloxPlayerBeta.exe");
            if (pid == 0)
            {
                AppendConsole("Attach failed: Roblox is not running");
                SetStatusCircle(false);
                return;
            }

            bool firstTime = !_seenInjectPids.Contains(pid);
            if (firstTime)
            {
                _seenInjectPids.Add(pid);
                await RunFirstInjectFlow(pid);
                return;
            }

            DoNormalAttach();
        }

        private void DoNormalAttach()
        {
            string why;
            if (!Executor.Reattach(out why))
            {
                AppendConsole("Attach failed: " + (why ?? "unknown reason"));
                SetStatusCircle(false);
                return;
            }
            Executor.EnsureBridge();
            string dmName = Executor.DatamodelName;
            if (dmName != "Ugc")
            {
                AppendConsole("Attach failed: join a game first (DataModel is '" +
                              (string.IsNullOrEmpty(dmName) ? "(none)" : dmName) + "')");
                SetStatusCircle(false);
                return;
            }
            if (Executor.IsInjected())
            {
                AppendConsole("Already injected.");
                SetStatusCircle(true);
                return;
            }
            string log;
            bool ok = Executor.Inject(out log);
            System.Diagnostics.Debug.WriteLine(log);
            AppendConsole(ok ? "Injected." : log);
            SetStatusCircle(ok);
            if (ok) PlayInjectSound();
        }

        private async Task RunFirstInjectFlow(uint pid)
        {
            _loadingBusy = true;
            try
            {
                ShowLoadingOverlay();
                await SetLoadingText("Fetching offsets...");
                await Task.Delay(120);

                await SetLoadingText("Fetching roblox version");
                string version = GameVersion.Detect(pid) ?? Off.ClientVersion;
                await Task.Delay(60);

                bool fetched = false;
                try { fetched = await OffsetFetcher.FetchAsync(version); }
                catch { fetched = false; }

                await SetLoadingText(fetched
                    ? "Offsets for " + version + " Found!"
                    : "Using bundled offsets (" + version + ")");
                await Task.Delay(180);

                

                Executor.SetOffsets(Off.OffsetsText());

                await SetLoadingText("Your in welcome!");
                await Task.Delay(160);

                

                string why = null;
                bool attached = false;
                string dmName = null;
                bool alreadyInjected = false;
                await Task.Run(() =>
                {
                    attached = Executor.Reattach(out why);
                    if (attached)
                    {
                        Executor.EnsureBridge();
                        dmName = Executor.DatamodelName;
                        alreadyInjected = Executor.IsInjected();
                    }
                });

                if (!attached)
                {
                    await SetLoadingText("Attach failed");
                    await Task.Delay(700);
                    HideLoadingOverlay();
                    AppendConsole("Attach failed: " + (why ?? "unknown reason"));
                    SetStatusCircle(false);
                    _seenInjectPids.Remove(pid);
                    return;
                }
                if (dmName != "Ugc")
                {
                    await SetLoadingText("Join a game first");
                    await Task.Delay(800);
                    HideLoadingOverlay();
                    AppendConsole("Attach failed: join a game first (DataModel is '" +
                                  (string.IsNullOrEmpty(dmName) ? "(none)" : dmName) + "')");
                    SetStatusCircle(false);
                    _seenInjectPids.Remove(pid);
                    return;
                }
                if (alreadyInjected)
                {
                    await SetLoadingText("Already injected");
                    await Task.Delay(300);
                    HideLoadingOverlay();
                    AppendConsole("Already injected.");
                    SetStatusCircle(true);
                    return;
                }

                string log = null;
                bool ok = false;
                await Task.Run(() =>
                {
                    string l;
                    ok = Executor.Inject(out l);
                    log = l;
                });

                await SetLoadingText(ok ? "Injected" : "Injection failed");
                await Task.Delay(ok ? 320 : 700);

                HideLoadingOverlay();
                AppendConsole(ok ? "Injected." : (log ?? "Injection failed"));
                SetStatusCircle(ok);
                if (ok) PlayInjectSound();
                if (!ok) _seenInjectPids.Remove(pid);
            }
            finally { _loadingBusy = false; }
        }

        private async Task SetLoadingText(string text)
        {
            LoadingText.Text = text;
            await Task.Yield();
        }

        private void ShowLoadingOverlay()
        {
            LoadingOverlay.Visibility = Visibility.Visible;
            LoadingOverlay.Opacity = 0;
            MainContent.Effect = new System.Windows.Media.Effects.BlurEffect
            {
                Radius = 14,
                KernelType = System.Windows.Media.Effects.KernelType.Gaussian,
                RenderingBias = System.Windows.Media.Effects.RenderingBias.Performance
            };
            MainContent.IsHitTestVisible = false;
            var fade = new DoubleAnimation(0, 1, TimeSpan.FromMilliseconds(180))
            {
                EasingFunction = new QuadraticEase { EasingMode = EasingMode.EaseOut }
            };
            LoadingOverlay.BeginAnimation(UIElement.OpacityProperty, fade);
        }

        private void HideLoadingOverlay()
        {
            var fade = new DoubleAnimation(1, 0, TimeSpan.FromMilliseconds(180))
            {
                EasingFunction = new QuadraticEase { EasingMode = EasingMode.EaseIn }
            };
            fade.Completed += (s, e) =>
            {
                LoadingOverlay.Visibility = Visibility.Collapsed;
                MainContent.Effect = null;
                MainContent.IsHitTestVisible = true;
            };
            LoadingOverlay.BeginAnimation(UIElement.OpacityProperty, fade);
        }

        


        void SetStatusCircle(bool ok)
        {
            try
            {
                _attached = ok;

                var gold = new SolidColorBrush(Color.FromRgb(232, 168, 0));
                var idle = new SolidColorBrush(Color.FromRgb(90, 90, 90));

                StatusDot.Fill = ok ? gold : idle;
                AvatarRing.Stroke = ok ? gold : new SolidColorBrush(Color.FromRgb(60, 60, 60));

                if (ok)
                {
                    if (_avatar != null)
                    {
                        SidebarAvatar.Fill = new ImageBrush(_avatar);
                        SidebarAvatarInitial.Visibility = Visibility.Collapsed;
                    }
                    if (_profile == null) _ = LoadProfileAsync();
                }
                else
                {
                    SidebarAvatar.Fill = new SolidColorBrush(Color.FromRgb(42, 42, 42));
                    SidebarAvatarInitial.Visibility = Visibility.Visible;
                }
            }
            catch { }

            UpdateDashboard();
        }

        private async Task LoadProfileAsync()
        {
            if (_profileLoading) return;
            _profileLoading = true;

            try
            {
                long userId = await Task.Run(() => RobloxProfile.FindUserId());
                if (userId == 0) return;

                var info = await RobloxProfile.FetchAsync(userId);

                if (_avatar == null)
                {
                    try { _avatar = await RobloxProfile.FetchAvatarAsync(userId); }
                    catch { }
                }

                await Dispatcher.InvokeAsync(() =>
                {
                    _profile = info;
                    ApplyProfile();
                    UpdateDashboard();
                });
            }
            catch { }
            finally { _profileLoading = false; }
        }

        private void ApplyProfile()
        {
            if (_profile == null) return;
            try
            {
                if (_avatar != null && _attached)
                {
                    SidebarAvatar.Fill = new ImageBrush(_avatar);
                    SidebarAvatarInitial.Visibility = Visibility.Collapsed;
                }

                if (SidebarAvatarInitial.Visibility == Visibility.Visible)
                    SidebarAvatarInitial.Text = _profile.Initial;

                DashAvatarInitial.Text = _profile.Initial;
            }
            catch { }
        }

        private void UpdateDashboard()
        {
            try
            {
                var gold = new SolidColorBrush(Color.FromRgb(232, 168, 0));
                var idle = new SolidColorBrush(Color.FromRgb(90, 90, 90));

                DashStatusText.Text = _attached ? "Attached" : "Not attached";
                DashStatusDot.Fill = _attached ? gold : idle;
                DashStatusPill.Background = new SolidColorBrush(_attached
                    ? Color.FromRgb(46, 38, 12)
                    : Color.FromRgb(45, 45, 48));
                DashStatusText.Foreground = new SolidColorBrush(_attached
                    ? Color.FromRgb(232, 200, 120)
                    : Color.FromRgb(176, 176, 176));
                DashAttachBtn.Content = _attached ? "Re-attach" : "Attach";

                if (_attached && _profile != null)
                {
                    DashUsername.Text = "@" + _profile.Name;
                    DashSubtitle.Text = string.IsNullOrEmpty(_profile.DisplayName) ||
                                        _profile.DisplayName == _profile.Name
                        ? "Roblox account"
                        : _profile.DisplayName;
                    DashMeta.Text = _profile.Created == default(DateTime)
                        ? "User ID " + _profile.UserId
                        : "User ID " + _profile.UserId + "   ·   Joined " +
                          _profile.Created.ToString("d MMM yyyy", CultureInfo.InvariantCulture);
                }
                else if (_attached)
                {
                    DashUsername.Text = "Reading account…";
                    DashSubtitle.Text = "Loading your Roblox profile";
                    DashMeta.Text = "";
                }
                else
                {
                    DashUsername.Text = "Not attached";
                    DashSubtitle.Text = "Attach to Roblox to load your account";
                    DashMeta.Text = "";
                }

                bool showAvatar = _attached && _avatar != null;
                DashAvatarInitial.Visibility = showAvatar ? Visibility.Collapsed : Visibility.Visible;
                DashAvatar.Fill = showAvatar
                    ? (Brush)new ImageBrush(_avatar)
                    : new SolidColorBrush(Color.FromRgb(42, 42, 42));
                DashAvatarRing.Stroke = showAvatar
                    ? gold
                    : new SolidColorBrush(Color.FromRgb(60, 60, 60));

                if (!showAvatar && _profile != null)
                    DashAvatarInitial.Text = _profile.Initial;

                DashScriptsValue.Text = _allFiles.Count.ToString(CultureInfo.InvariantCulture);
                DashScriptsHint.Text = _allFiles.Count == 1
                    ? "script in your Scripts folder"
                    : "scripts in your Scripts folder";

                DashAiValue.Text = _aiReady ? "Ready" : "Offline";
                DashAiHint.Text = string.IsNullOrWhiteSpace(ChatServerBox.Text)
                    ? "http://127.0.0.1:8080"
                    : ChatServerBox.Text.Trim();

                DashBuildValue.Text = AppInfo.Version;
                DashBuildHint.Text = "Roblox client " +
                    (string.IsNullOrEmpty(Off.ClientVersion) ? "unknown" : Off.ClientVersion);
            }
            catch { }
        }

        private void BuildChangelog()
        {
            try
            {
                DashVersion.Text = "v" + AppInfo.Version;

                var heading = (Brush)FindResource("TextPrimaryBrush");
                var body = (Brush)FindResource("TextSecondaryBrush");
                var accent = (Brush)FindResource("AccentBrush");

                foreach (var change in AppInfo.Changelog)
                {
                    ChangelogPanel.Children.Add(new TextBlock
                    {
                        Text = change.Version + "   ·   " + change.Date,
                        Foreground = heading,
                        FontSize = 12.5,
                        FontWeight = FontWeights.SemiBold,
                        Margin = new Thickness(0, 12, 0, 4)
                    });

                    foreach (string note in change.Notes)
                    {
                        var row = new Grid { Margin = new Thickness(0, 2, 0, 0) };
                        row.ColumnDefinitions.Add(new ColumnDefinition { Width = GridLength.Auto });
                        row.ColumnDefinitions.Add(new ColumnDefinition
                        {
                            Width = new GridLength(1, GridUnitType.Star)
                        });

                        var dot = new System.Windows.Shapes.Ellipse
                        {
                            Width = 4,
                            Height = 4,
                            Fill = accent,
                            VerticalAlignment = VerticalAlignment.Center,
                            Margin = new Thickness(2, 0, 0, 0)
                        };
                        Grid.SetColumn(dot, 0);
                        row.Children.Add(dot);

                        var text = new TextBlock
                        {
                            Text = note,
                            TextWrapping = TextWrapping.Wrap,
                            Foreground = body,
                            FontSize = 12,
                            Margin = new Thickness(12, 0, 0, 0)
                        };
                        Grid.SetColumn(text, 1);
                        row.Children.Add(text);

                        ChangelogPanel.Children.Add(row);
                    }
                }
            }
            catch { }
        }

        private void TopMostCheckBox_Checked(object sender, RoutedEventArgs e)
        {
            this.Topmost = true;
        }

        private void TopMostCheckBox_Unchecked(object sender, RoutedEventArgs e)
        {
            this.Topmost = false;
        }

        private void KillRblxBtn_Click(object sender, RoutedEventArgs e)
        {
            try
            {
                foreach (var p in Process.GetProcessesByName("RobloxPlayerBeta"))
                {
                    try { p.Kill(); } catch { }
                }
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine(ex.Message);
            }
        }

        private void RestartBtn_Click(object sender, RoutedEventArgs e)
        {
            try
            {
                

                string exePath = Process.GetCurrentProcess().MainModule.FileName;

                

                Process.Start(exePath);

                

                Application.Current.Shutdown();
            }
            catch (Exception ex)
            {
                System.Diagnostics.Debug.WriteLine(ex.Message);
            }
        }

        


        private bool _sidebarCollapsed;

        private void SidebarToggleBtn_Click(object sender, RoutedEventArgs e)
        {
            _sidebarCollapsed = !_sidebarCollapsed;
            double width = _sidebarCollapsed ? 14 : 55;
            double left = _sidebarCollapsed ? 26 : 70;
            var dur = TimeSpan.FromMilliseconds(220);
            var ease = new QuadraticEase { EasingMode = EasingMode.EaseOut };

            SideBarBorder.BeginAnimation(FrameworkElement.WidthProperty,
                new DoubleAnimation(SideBarBorder.Width, width, dur) { EasingFunction = ease });

            ShiftLeft(TopBar, left, dur, ease);
            ShiftLeft(DashboardBorder, left, dur, ease);
            ShiftLeft(EditorBorder, left, dur, ease);
            ShiftLeft(ScriptHubBorder, left, dur, ease);
            ShiftLeft(SettingsBorder, left, dur, ease);
            ShiftLeft(ChatBorder, left, dur, ease);

            bool shown = !_sidebarCollapsed;
            var navItems = new FrameworkElement[] { Indicator, DashboardBtn, EditorBtn, ScriptHubBtn, SettingsBtn, ChatBtn, AvatarHost };
            foreach (var el in navItems)
            {
                el.BeginAnimation(UIElement.OpacityProperty,
                    new DoubleAnimation(shown ? 1 : 0, dur) { EasingFunction = ease });
                el.IsHitTestVisible = shown;
                if (el is Control c) c.IsEnabled = shown;
            }

            (FindName("RailChevronRotate") as RotateTransform)?.BeginAnimation(RotateTransform.AngleProperty,
                new DoubleAnimation(_sidebarCollapsed ? 180 : 0, dur));
        }

        private void ShiftLeft(FrameworkElement el, double left, TimeSpan dur, IEasingFunction ease)
        {
            var cur = el.Margin;
            el.BeginAnimation(FrameworkElement.MarginProperty,
                new ThicknessAnimation(new Thickness(left, cur.Top, 10, cur.Bottom), dur) { EasingFunction = ease });
        }

        private void AccentSwatch_Click(object sender, RoutedEventArgs e)
        {
            if (!(sender is Button b) || !(b.Tag is string hex)) return;
            try
            {
                var color = (Color)ColorConverter.ConvertFromString(hex);
                if (Application.Current.Resources["AccentBrush"] is SolidColorBrush brush)
                    brush.Color = color;
            }
            catch { }
        }

        private async void EditorFontApplyBtn_Click(object sender, RoutedEventArgs e)
        {
            if (!int.TryParse(EditorFontBox.Text, out int n) || n < 6 || n > 48) return;
            try
            {
                await Editor.CoreWebView2.ExecuteScriptAsync("editor.updateOptions({fontSize: " + n + "});");
            }
            catch { }
        }

        


        private void WarmChat()
        {
            if (_chatWarmed) return;
            _chatWarmed = true;
            AddChatBubble("Chat with your local AI model. I can write scripts, save them, load the editor, and run code in Roblox using tools. Start a conversation below!", false);
        }

        private void ChatClearBtn_Click(object sender, RoutedEventArgs e)
        {
            ChatPanel.Children.Clear();
            Chat.Reset();
            _chatWarmed = false;
            WarmChat();
        }

        private void ChatInput_TextChanged(object sender, TextChangedEventArgs e)
        {
            if (ChatPlaceholder != null)
                ChatPlaceholder.Visibility = string.IsNullOrEmpty(ChatInput.Text)
                    ? Visibility.Visible
                    : Visibility.Collapsed;
        }

        private void ChatInput_KeyDown(object sender, KeyEventArgs e)
        {
            if (e.Key == Key.Return && !Keyboard.IsKeyDown(Key.LeftShift) && !Keyboard.IsKeyDown(Key.RightShift))
            {
                e.Handled = true;
                _ = SendChatAsync();
            }
        }

        private async void SendChatBtn_Click(object sender, RoutedEventArgs e)
        {
            await SendChatAsync();
        }

        private void SetChatBusy(bool busy)
        {
            _chatBusy = busy;
            ChatInput.IsEnabled = !busy;
            SendChatBtn.IsEnabled = !busy;
            SetupAiBtn.IsEnabled = !busy;
            ChatClearBtn.IsEnabled = !busy;

            if (busy && ChatStatus != null)
                ChatStatus.Fill = new SolidColorBrush(Color.FromRgb(160, 130, 40));
        }

        private async Task SendChatAsync()
        {
            if (_chatBusy) return;
            string text = ChatInput.Text.Trim();
            if (text.Length == 0) return;

            Chat.BaseUrl = ChatServerBox.Text.Trim();
            Chat.Model = ChatModelBox.Text.Trim();

            SetChatBusy(true);
            AddChatBubble(text, true);
            ChatInput.Clear();

            try
            {
                if (!await EnsureAiAsync()) return;
                string answer = await Chat.Ask(text,
                    async ev => await Dispatcher.InvokeAsync(() => AddChatBubble(ev, false, true)),
                    RunChatTool);
                await Dispatcher.InvokeAsync(() =>
                {
                    AddChatBubble(string.IsNullOrWhiteSpace(answer) ? "(no response)" : answer, false);
                    SetChatStatus(true);
                });
            }
            catch (Exception ex)
            {
                await Dispatcher.InvokeAsync(() =>
                {
                    AddChatBubble("Error: " + ex.Message, false);
                    SetChatStatus(false);
                });
            }
            finally
            {
                SetChatBusy(false);
                ChatInput.Focus();
                ScrollChatEnd();
            }
        }

        private async void SetupAiBtn_Click(object sender, RoutedEventArgs e)
        {
            if (_chatBusy) return;
            Chat.BaseUrl = ChatServerBox.Text.Trim();
            Chat.Model = ChatModelBox.Text.Trim();

            SetChatBusy(true);
            try
            {
                if (await EnsureAiAsync())
                {
                    await Dispatcher.InvokeAsync(() => AddChatBubble("AI server is ready. Start chatting below.", false));
                }
            }
            finally
            {
                SetChatBusy(false);
                ChatInput.Focus();
            }
        }

        private async Task<bool> EnsureAiAsync()
        {
            try
            {
                await AiServer.EnsureRunningAsync(Chat.BaseUrl,
                    async ev => await Dispatcher.InvokeAsync(() => AddChatBubble(ev, false, true)));
                await Dispatcher.InvokeAsync(() => SetChatStatus(true));
                return true;
            }
            catch (Exception ex)
            {
                await Dispatcher.InvokeAsync(() =>
                {
                    AddChatBubble("Error: " + ex.Message, false);
                    SetChatStatus(false);
                });
                return false;
            }
        }

        private async Task<string> RunChatTool(Chat.ToolCall call)
        {
            switch (call.Name)
            {
                case "run_lua":
                {
                    string code = Chat.Arg(call.Args, "code");
                    if (string.IsNullOrEmpty(code)) return "error: run_lua requires a 'code' argument";
                    return await Task.Run(() =>
                    {
                        string why;
                        if (!Executor.Reattach(out why)) return "error: " + why;
                        Executor.EnsureBridge();
                        bool injected = Executor.IsInjected();
                        if (!injected && Executor.DatamodelName == "Ugc")
                        {
                            string log;
                            injected = Executor.Inject(out log);
                        }
                        if (!injected) return "error: not injected into Roblox; open a game and try again";
                        string log2;
                        bool ok = Executor.Execute(code, out log2);
                        return ok ? "ok: script executed in game" : "error: " + log2;
                    });
                }
                case "attach":
                    return await Task.Run(() =>
                    {
                        string why;
                        if (!Executor.Reattach(out why)) return "error: " + why;
                        Executor.EnsureBridge();
                        if (Executor.IsInjected()) return "ok: already injected";
                        if (Executor.DatamodelName == "Ugc")
                        {
                            string log;
                            bool ok = Executor.Inject(out log);
                            return ok ? "ok: injected into Roblox" : "error: " + log;
                        }
                        return "error: not in a game yet";
                    });
                case "create_script":
                {
                    string name = Chat.Arg(call.Args, "name");
                    string code = Chat.Arg(call.Args, "code");
                    if (string.IsNullOrEmpty(name)) return "error: create_script requires a 'name' argument";
                    if (string.IsNullOrEmpty(code)) return "error: create_script requires a 'code' argument";
                    if (name.IndexOfAny(System.IO.Path.GetInvalidFileNameChars()) >= 0) return "error: invalid file name";
                    string folder = System.IO.Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "Scripts");
                    System.IO.Directory.CreateDirectory(folder);
                    string file = System.IO.Path.Combine(folder, name.IndexOf('.') >= 0 ? name : name + ".lua");
                    System.IO.File.WriteAllText(file, code);
                    return "ok: saved " + System.IO.Path.GetFileName(file);
                }
                case "set_editor":
                {
                    string code = Chat.Arg(call.Args, "code");
                    Dispatcher.Invoke(() => SetEditorSafe(code));
                    return "ok: editor updated";
                }
                case "get_editor":
                {
                    string content = await GetEditorValueSafeAsync();
                    if (string.IsNullOrWhiteSpace(content)) return "editor is empty";
                    return content.Length > 8000 ? content.Substring(0, 8000) + "\n...[truncated]" : content;
                }
                case "list_scripts":
                {
                    string folder = System.IO.Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "Scripts");
                    if (!System.IO.Directory.Exists(folder)) return "no scripts yet";
                    var names = System.IO.Directory.GetFiles(folder).Select(System.IO.Path.GetFileName);
                    var joined = string.Join("\n", names);
                    return joined.Length == 0 ? "no scripts yet" : joined;
                }
                case "read_script":
                {
                    string name = Chat.Arg(call.Args, "name");
                    if (string.IsNullOrEmpty(name)) return "error: read_script requires a 'name' argument";
                    string folder = System.IO.Path.Combine(AppDomain.CurrentDomain.BaseDirectory, "Scripts");
                    string file = System.IO.Path.Combine(folder, name.IndexOf('.') >= 0 ? name : name + ".lua");
                    if (!System.IO.File.Exists(file)) return "error: script not found: " + System.IO.Path.GetFileName(file);
                    string content = System.IO.File.ReadAllText(file);
                    return content.Length > 8000 ? content.Substring(0, 8000) + "\n...[truncated]" : content;
                }
                default:
                    return "unknown tool: " + call.Name;
            }
        }

        private void SetEditorSafe(string code)
        {
            try
            {
                if (Editor != null && Editor.CoreWebView2 != null)
                {
                    _ = SetEditorValueAsync(code);
                }
            }
            catch { }
        }

        private async Task<string> GetEditorValueSafeAsync()
        {
            if (Editor == null || Editor.CoreWebView2 == null) return "";
            var tcs = new TaskCompletionSource<string>();
            Dispatcher.Invoke(() =>
            {
                GetEditorValueAsync().ContinueWith(t =>
                    tcs.TrySetResult(t.Status == TaskStatus.RanToCompletion ? t.Result : ""), TaskScheduler.Default);
            });
            return await tcs.Task;
        }

        private void AddChatBubble(string text, bool user, bool tool = false)
        {
            double available = ChatScroll != null && ChatScroll.ActualWidth > 60
                ? ChatScroll.ActualWidth - 40
                : 640;

            var sp = new StackPanel
            {
                Margin = new Thickness(0, 5, 0, 5),
                MaxWidth = Math.Max(220, available),
                HorizontalAlignment = user ? HorizontalAlignment.Right : HorizontalAlignment.Left
            };

            var tb = new TextBlock
            {
                Text = text,
                TextWrapping = TextWrapping.Wrap,
                FontFamily = (FontFamily)FindResource("UiFont"),
                FontSize = 13
            };

            if (tool)
            {
                tb.Foreground = new SolidColorBrush(Color.FromRgb(154, 154, 154));
                tb.FontStyle = FontStyles.Italic;
                tb.FontFamily = (FontFamily)FindResource("MonoFont");
                tb.FontSize = 12.5;
            }
            else
            {
                tb.Foreground = new SolidColorBrush(user ? Color.FromRgb(255, 255, 255) : Color.FromRgb(225, 225, 225));
            }

            var border = new Border
            {
                Background = new SolidColorBrush(tool
                    ? Color.FromRgb(28, 28, 28)
                    : user ? Color.FromRgb(58, 58, 58) : Color.FromRgb(45, 45, 48)),
                CornerRadius = new CornerRadius(8),
                Padding = new Thickness(10, 7, 10, 7),
                Child = tb
            };

            sp.Children.Add(border);
            ChatPanel.Children.Add(sp);
            ScrollChatEnd();
        }

        private void ScrollChatEnd()
        {
            if (ChatScroll == null) return;
            Dispatcher.BeginInvoke(DispatcherPriority.Background, new Action(() =>
            {
                if (ChatScroll == null) return;
                ChatScroll.ScrollToEnd();
            }));
        }

        private void SetChatStatus(bool ok)
        {
            if (ChatStatus == null) return;
            try
            {
                ChatStatus.Fill = new SolidColorBrush(ok ? Color.FromRgb(232, 168, 0) : Color.FromRgb(90, 90, 90));
                _aiReady = ok;
                UpdateDashboard();
            }
            catch { }
        }
    }

    public class ScriptFile
    {
        public string FullPath { get; set; }
        public string Name { get; set; }
        public ImageSource Icon { get; set; }
    }
}
