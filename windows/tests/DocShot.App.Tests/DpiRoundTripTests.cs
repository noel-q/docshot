using System;
using DocShot.App.Services;
using DocShot.Core.Primitives;
using Xunit;

namespace DocShot.App.Tests;

public class DpiRoundTripTests
{
    [Theory]
    [InlineData(1.0, 1920, 1080)]
    [InlineData(1.25, 2560, 1440)]
    [InlineData(1.50, 2560, 1440)]
    [InlineData(1.75, 3840, 2160)]
    [InlineData(2.00, 3840, 2160)]
    public void Physical_to_DIP_and_back_round_trips_with_zero_error(double scaleFactor, double widthPx, double heightPx)
    {
        var physicalBounds = new RectD(0, 0, widthPx, heightPx);
        var dipBounds = new RectD(0, 0, widthPx / scaleFactor, heightPx / scaleFactor);

        var monitor = new DisplayMonitorInfo(
            IntPtr.Zero,
            "TEST_DISPLAY",
            true,
            physicalBounds,
            dipBounds,
            scaleFactor,
            (uint)(96 * scaleFactor),
            (uint)(96 * scaleFactor));

        // Test full screen
        Assert.True(monitor.VerifyRoundTrip(physicalBounds, out var rtPhys1, out _));
        Assert.Equal(physicalBounds.Width, rtPhys1.Width, 3);
        Assert.Equal(physicalBounds.Height, rtPhys1.Height, 3);

        // Test center selection
        var centerPhysical = new RectD(widthPx * 0.25, heightPx * 0.25, widthPx * 0.5, heightPx * 0.5);
        Assert.True(monitor.VerifyRoundTrip(centerPhysical, out var rtPhys2, out _));
        Assert.Equal(centerPhysical.Width, rtPhys2.Width, 3);

        // Test arbitrary selection
        var arbitraryPhysical = new RectD(100, 150, 400, 300);
        Assert.True(monitor.VerifyRoundTrip(arbitraryPhysical, out var rtPhys3, out _));
        Assert.Equal(arbitraryPhysical.Width, rtPhys3.Width, 3);
    }

    [Fact]
    [System.Runtime.Versioning.SupportedOSPlatform("windows")]
    public void Multi_monitor_enumeration_returns_valid_displays()
    {
        var monitors = DisplayMonitorHelper.GetMonitors();
        Assert.NotEmpty(monitors);

        foreach (var mon in monitors)
        {
            Assert.True(mon.ScaleFactor >= 1.0, $"Scale factor for {mon.DeviceName} should be >= 1.0, but was {mon.ScaleFactor}");
            Assert.True(mon.PhysicalBounds.Width > 0, $"Width for {mon.DeviceName} should be > 0");
            Assert.True(mon.PhysicalBounds.Height > 0, $"Height for {mon.DeviceName} should be > 0");
        }
    }

    [Fact]
    public void Automated_DPI_spike_test_passes_across_all_configured_monitors()
    {
        var results = OverlayWindowManager.RunAutomatedDpiSpikeTest();
        Assert.NotEmpty(results);

        foreach (var res in results)
        {
            Assert.True(res.Passed, $"DPI spike test failed for {res.Monitor.DeviceName} ({res.Monitor.ScaleFactor * 100}% scale). Max Error: {res.MaxPixelError:F4} px");
            Assert.True(res.MaxPixelError < 0.001, $"Pixel error exceeded threshold: {res.MaxPixelError}");
        }
    }
}
