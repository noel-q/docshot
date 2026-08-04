using System;
using System.Drawing;
using System.Windows;
using System.Windows.Controls;
using H.NotifyIcon;
using DocShot.App.Services;
using DocShot.App.Views;

namespace DocShot.App;

public partial class App : Application
{
    private TaskbarIcon? _notifyIcon;
    private readonly OverlayWindowManager _overlayManager = new();
    private SettingsWindow? _settingsWindow;

    protected override void OnStartup(StartupEventArgs e)
    {
        base.OnStartup(e);

        // Initialize NotifyIcon system tray icon
        _notifyIcon = new TaskbarIcon
        {
            ToolTipText = "DocShot — Screen Capture & Annotation",
            ContextMenu = (ContextMenu)FindResource("TrayContextMenu")
        };

        // Use built-in system icon or custom generated icon
        using var iconStream = typeof(App).Assembly.GetManifestResourceStream("DocShot.App.app.ico");
        if (iconStream != null)
        {
            _notifyIcon.Icon = new Icon(iconStream);
        }
        else
        {
            // System application icon fallback
            _notifyIcon.Icon = SystemIcons.Application;
        }

        _notifyIcon.TrayLeftMouseDown += (s, args) => MenuTakeScreenshot_Click(s, args);

        // Register default global capture hotkey (ID 101)
        AppServices.Hotkey.Register(101, 0x0002 | 0x0004, 0x53); // Ctrl + Shift + S
        AppServices.Hotkey.HotkeyPressed += OnHotkeyPressed;

        // Check if started with --spike flag to automatically launch settings/diagnostics
        if (e.Args.Length > 0 && e.Args[0] == "--spike")
        {
            ShowSettingsWindow();
        }
    }

    private void OnHotkeyPressed(int hotkeyId)
    {
        Dispatcher.Invoke(() =>
        {
            if (hotkeyId == 101)
            {
                _overlayManager.ShowOverlays();
            }
        });
    }

    private void MenuTakeScreenshot_Click(object? sender, RoutedEventArgs e)
    {
        _overlayManager.ShowOverlays();
    }

    private void MenuRunDpiSpike_Click(object? sender, RoutedEventArgs e)
    {
        ShowSettingsWindow();
        _settingsWindow?.RunSpikeTestButton_Click(sender!, e);
    }

    private void MenuSettings_Click(object? sender, RoutedEventArgs e)
    {
        ShowSettingsWindow();
    }

    private void ShowSettingsWindow()
    {
        if (_settingsWindow == null || !_settingsWindow.IsLoaded)
        {
            _settingsWindow = new SettingsWindow();
            _settingsWindow.Closed += (s, args) => _settingsWindow = null;
            _settingsWindow.Show();
        }
        else
        {
            _settingsWindow.Activate();
        }
    }

    private void MenuExit_Click(object? sender, RoutedEventArgs e)
    {
        _overlayManager.CloseOverlays();
        _notifyIcon?.Dispose();
        Shutdown();
    }

    protected override void OnExit(ExitEventArgs e)
    {
        _notifyIcon?.Dispose();
        base.OnExit(e);
    }
}
