using System;
using System.Linq;
using System.Windows;
using DocShot.App.Services;

namespace DocShot.App.Views;

public partial class SettingsWindow : Window
{
    public SettingsWindow()
    {
        InitializeComponent();
        LoadMonitorsList();
        UpdateServiceModeUI();
    }

    private void LoadMonitorsList()
    {
        try
        {
            var monitors = DisplayMonitorHelper.GetMonitors();
            MonitorsListView.ItemsSource = monitors.Select(m => new
            {
                DeviceName = m.DeviceName,
                IsPrimary = m.IsPrimary,
                PhysicalDetails = $"Physical Resolution: {m.PhysicalBounds.Width} x {m.PhysicalBounds.Height} px",
                DipDetails = $"DIP Bounds: ({m.DipBounds.X:F0}, {m.DipBounds.Y:F0}) - {m.DipBounds.Width:F0} x {m.DipBounds.Height:F0}",
                ScaleText = $"{m.ScaleFactor * 100:F0}% Scale ({m.DpiX} DPI)"
            });
        }
        catch (Exception ex)
        {
            SpikeOutputBox.Text = $"Error loading monitors list: {ex.Message}";
        }
    }

    private void UpdateServiceModeUI()
    {
        if (AppServices.IsUsingFakes)
        {
            ServiceModeDesc.Text = "Currently using DocShot.Core.Fakes (In-Memory Synthetic Fakes)";
            ServiceModeDesc.Foreground = System.Windows.Media.Brushes.Orange;
            ToggleServiceModeBtn.Content = "Switch to Real Win32 Platform";
        }
        else
        {
            ServiceModeDesc.Text = "Currently using DocShot.Platform (Win32 EnumWindows/P-Invoke/GDI)";
            ServiceModeDesc.Foreground = System.Windows.Media.Brushes.LightGreen;
            ToggleServiceModeBtn.Content = "Switch to Fakes Mode";
        }
    }

    private void ToggleServiceModeBtn_Click(object sender, RoutedEventArgs e)
    {
        if (AppServices.IsUsingFakes)
        {
            AppServices.UsePlatformServices();
        }
        else
        {
            AppServices.ResetToFakes();
        }
        UpdateServiceModeUI();
    }

    public void RunSpikeTestButton_Click(object sender, RoutedEventArgs e)
    {
        SpikeOutputBox.Text = "Running multi-monitor mixed-DPI round-trip verification spike...\n\n";

        var results = OverlayWindowManager.RunAutomatedDpiSpikeTest();
        int passCount = 0;

        foreach (var res in results)
        {
            string status = res.Passed ? "[PASS]" : "[FAIL]";
            if (res.Passed) passCount++;

            SpikeOutputBox.Text += $"{status} {res.Monitor.DeviceName} ({res.Monitor.ScaleFactor * 100}% scale, {res.Monitor.DpiX} DPI):\n";
            SpikeOutputBox.Text += $"   Physical Bounds: {res.Monitor.PhysicalBounds.Width}x{res.Monitor.PhysicalBounds.Height}\n";
            SpikeOutputBox.Text += $"   DIP Bounds:      {res.Monitor.DipBounds.Width:F1}x{res.Monitor.DipBounds.Height:F1}\n";
            SpikeOutputBox.Text += $"   Max Pixel Error: {res.MaxPixelError:F6} px\n";
            SpikeOutputBox.Text += $"   Round-Trip:      {res.TestPhysicalRect.Width}x{res.TestPhysicalRect.Height} -> {res.ConvertedDipRect.Width:F2}x{res.ConvertedDipRect.Height:F2} DIP -> {res.RoundTrippedPhysicalRect.Width}x{res.RoundTrippedPhysicalRect.Height} px\n\n";
        }

        SpikeOutputBox.Text += $"SUMMARY: {passCount} of {results.Count} monitor tests PASSED with zero-pixel accuracy.";
    }

    private void ShowOverlaysButton_Click(object sender, RoutedEventArgs e)
    {
        var overlayManager = new OverlayWindowManager();
        overlayManager.ShowOverlays();
    }

    private void CloseButton_Click(object sender, RoutedEventArgs e)
    {
        Close();
    }
}
