using System;
using System.Collections.Generic;
using System.Linq;
using DocShot.App.Views;
using DocShot.Core.Primitives;

namespace DocShot.App.Services;

public record DpiSpikeResult(
    DisplayMonitorInfo Monitor,
    RectD TestPhysicalRect,
    RectD ConvertedDipRect,
    RectD RoundTrippedPhysicalRect,
    bool Passed,
    double MaxPixelError);

public class OverlayWindowManager
{
    private readonly List<OverlayWindow> _overlayWindows = new();

    public IReadOnlyList<OverlayWindow> ActiveWindows => _overlayWindows;

    public void ShowOverlays()
    {
        CloseOverlays();

        var monitors = DisplayMonitorHelper.GetMonitors();
        foreach (var monitor in monitors)
        {
            var window = new OverlayWindow(monitor);
            _overlayWindows.Add(window);
            window.Show();
        }
    }

    public void CloseOverlays()
    {
        foreach (var win in _overlayWindows)
        {
            try
            {
                win.Close();
            }
            catch
            {
                // Ignore if already closed
            }
        }
        _overlayWindows.Clear();
    }

    /// <summary>
    /// Executes an automated programmatic DPI round-trip test across all connected monitors with their actual scale factors.
    /// Proves that a physical source pixel rectangle converts to DIPs and back to physical source pixels with zero pixel error.
    /// </summary>
    public static List<DpiSpikeResult> RunAutomatedDpiSpikeTest()
    {
        var monitors = DisplayMonitorHelper.GetMonitors();
        var results = new List<DpiSpikeResult>();

        foreach (var monitor in monitors)
        {
            // Test 3 representative rectangles on each monitor:
            // 1. Full monitor bounds
            // 2. Center 50% region
            // 3. Odd-dimension offset region (tests non-integer DIP boundaries e.g. on 150% scaling)
            var testCases = new List<RectD>
            {
                new RectD(0, 0, Math.Round(monitor.PhysicalBounds.Width), Math.Round(monitor.PhysicalBounds.Height)),
                new RectD(Math.Round(monitor.PhysicalBounds.Width * 0.25), Math.Round(monitor.PhysicalBounds.Height * 0.25), Math.Round(monitor.PhysicalBounds.Width * 0.5), Math.Round(monitor.PhysicalBounds.Height * 0.5)),
                new RectD(107, 83, 499, 311)
            };

            foreach (var testRect in testCases)
            {
                bool passed = monitor.VerifyRoundTrip(testRect, out var roundTrippedPhys, out var intermediateDip);

                double errX = Math.Abs(testRect.X - roundTrippedPhys.X);
                double errY = Math.Abs(testRect.Y - roundTrippedPhys.Y);
                double errW = Math.Abs(testRect.Width - roundTrippedPhys.Width);
                double errH = Math.Abs(testRect.Height - roundTrippedPhys.Height);
                double maxError = Math.Max(Math.Max(errX, errY), Math.Max(errW, errH));

                results.Add(new DpiSpikeResult(
                    monitor,
                    testRect,
                    intermediateDip,
                    roundTrippedPhys,
                    passed,
                    maxError));
            }
        }

        return results;
    }
}
