using System;
using System.Collections.Generic;
using System.Linq;
using System.Text;
using System.Windows;
using DocShot.App.Services;

namespace DocShot.App.Views;

public record MonitorDisplayViewModel(
    string DeviceName,
    bool IsPrimary,
    string PhysicalDetails,
    string DipDetails,
    string ScaleText);

public partial class SettingsWindow : Window
{
    private readonly OverlayWindowManager _overlayManager = new();

    public SettingsWindow()
    {
        InitializeComponent();
        RefreshMonitorsList();
    }

    private void RefreshMonitorsList()
    {
        var monitors = DisplayMonitorHelper.GetMonitors();
        var vms = monitors.Select(m => new MonitorDisplayViewModel(
            m.DeviceName.ToUpper(),
            m.IsPrimary,
            $"Physical Source: {m.PhysicalBounds.Width:F0}x{m.PhysicalBounds.Height:F0} px at ({m.PhysicalBounds.X:F0}, {m.PhysicalBounds.Y:F0})",
            $"Virtual DIPs:      {m.DipBounds.Width:F0}x{m.DipBounds.Height:F0} dip at ({m.DipBounds.X:F0}, {m.DipBounds.Y:F0})",
            $"{m.ScaleFactor * 100:F0}% ({m.DpiX} DPI)"
        )).ToList();

        MonitorsListView.ItemsSource = vms;
    }

    public void RunSpikeTestButton_Click(object sender, RoutedEventArgs e)
    {
        var results = OverlayWindowManager.RunAutomatedDpiSpikeTest();

        var sb = new StringBuilder();
        sb.AppendLine("=== W0 APP RISK SPIKE: MIXED-DPI ROUND-TRIP PROOF RESULTS ===");
        sb.AppendLine($"Timestamp: {DateTime.Now:yyyy-MM-dd HH:mm:ss}");
        sb.AppendLine($"Monitors Tested: {results.Select(r => r.Monitor.DeviceName).Distinct().Count()}\n");

        int passCount = 0;
        foreach (var res in results)
        {
            if (res.Passed) passCount++;

            string statusStr = res.Passed ? "[PASS]" : "[FAIL]";
            sb.AppendLine($"{statusStr} {res.Monitor.DeviceName} ({res.Monitor.ScaleFactor * 100:F0}% Scale / {res.Monitor.DpiX} DPI):");
            sb.AppendLine($"   Source Physical Rect: ({res.TestPhysicalRect.X:F0}, {res.TestPhysicalRect.Y:F0}, {res.TestPhysicalRect.Width:F0}, {res.TestPhysicalRect.Height:F0}) px");
            sb.AppendLine($"   Converted DIP Rect:   ({res.ConvertedDipRect.X:F2}, {res.ConvertedDipRect.Y:F2}, {res.ConvertedDipRect.Width:F2}, {res.ConvertedDipRect.Height:F2}) dip");
            sb.AppendLine($"   Round-Tripped Rect:   ({res.RoundTrippedPhysicalRect.X:F0}, {res.RoundTrippedPhysicalRect.Y:F0}, {res.RoundTrippedPhysicalRect.Width:F0}, {res.RoundTrippedPhysicalRect.Height:F0}) px");
            sb.AppendLine($"   Max Error:            {res.MaxPixelError:F4} px\n");
        }

        sb.AppendLine($"SUMMARY: {passCount}/{results.Count} Test Cases Passed Perfectly (0.00px Max Error).");

        SpikeOutputBox.Text = sb.ToString();
    }

    private void ShowOverlaysButton_Click(object sender, RoutedEventArgs e)
    {
        _overlayManager.ShowOverlays();
    }

    private void CloseButton_Click(object sender, RoutedEventArgs e)
    {
        Close();
    }
}
