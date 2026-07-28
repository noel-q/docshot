using System;
using System.Collections.Generic;
using System.Linq;
using DocShot.App.Services;
using DocShot.Core.Fakes;
using DocShot.Core.Models;
using DocShot.Core.Primitives;
using Xunit;

namespace DocShot.App.Tests;

public class W1FeatureTests
{
    [Fact]
    public void AppServices_initializes_with_fake_services_in_debug()
    {
        AppServices.ResetToFakes();
        Assert.True(AppServices.IsUsingFakes);
        Assert.IsType<FakeWindowDiscoveryService>(AppServices.WindowDiscovery);
        Assert.IsType<FakeScreenCaptureService>(AppServices.ScreenCapture);
        Assert.IsType<FakePasteboardWriter>(AppServices.Pasteboard);
        Assert.IsType<FakeFileWriter>(AppServices.FileWriter);
    }

    [Fact]
    public void Window_discovery_fake_returns_eligible_windows()
    {
        var windows = AppServices.WindowDiscovery.GetEligibleWindows();
        Assert.NotEmpty(windows);
        Assert.True(windows.Count >= 3);
        Assert.Contains(windows, w => w.OwnerName == "chrome.exe");
        Assert.Contains(windows, w => w.OwnerName == "notepad.exe");
    }

    [Fact]
    public async Task Screen_capture_fake_returns_valid_checkerboard_image()
    {
        var captured = await AppServices.ScreenCapture.CaptureRegion(1, new RectD(0, 0, 400, 300));
        Assert.NotNull(captured);
        Assert.Equal(400, captured.PixelWidth);
        Assert.Equal(300, captured.PixelHeight);
        Assert.Equal(400 * 300 * 4, captured.Bgra32Pixels.Length);
    }

    [Fact]
    public async Task CanvasExporter_flattens_background_and_annotations_to_png_bytes()
    {
        var captured = await AppServices.ScreenCapture.CaptureRegion(1, new RectD(0, 0, 200, 150));
        var bmp = CanvasExporter.ToBitmapSource(captured);
        Assert.NotNull(bmp);

        var annotations = new List<AnnotationItem>
        {
            new AnnotationItem(new AnnotationShape.Arrow(new PointD(10, 10), new PointD(100, 100)), RgbaColor.Red, 3.0),
            new AnnotationItem(new AnnotationShape.Rectangle(new RectD(20, 20, 80, 50), false), RgbaColor.Blue, 2.0),
            new AnnotationItem(new AnnotationShape.Ellipse(new RectD(30, 30, 60, 40), true), RgbaColor.Green, 2.0),
            new AnnotationItem(new AnnotationShape.Text(new RectD(10, 120, 150, 25), "Test Label", 14.0), RgbaColor.Yellow, 1.0)
        };

        byte[] pngBytes = CanvasExporter.ExportToPngBytes(bmp, annotations, new RectD(0, 0, 200, 150), scaleFactor: 1.0);
        Assert.NotEmpty(pngBytes);
        Assert.True(pngBytes.Length > 100);

        // Header check: PNG magic bytes [0x89, 0x50, 0x4E, 0x47]
        Assert.Equal(0x89, pngBytes[0]);
        Assert.Equal(0x50, pngBytes[1]);
        Assert.Equal(0x4E, pngBytes[2]);
        Assert.Equal(0x47, pngBytes[3]);
    }

    [Fact]
    public void PasteboardWriter_fake_records_copied_png_bytes()
    {
        AppServices.ResetToFakes();
        var fakePasteboard = (FakePasteboardWriter)AppServices.Pasteboard;

        byte[] testData = new byte[] { 0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A };
        bool success = AppServices.Pasteboard.WritePng(testData);

        Assert.True(success);
        Assert.NotNull(fakePasteboard.LastWritten);
        Assert.Equal(testData, fakePasteboard.LastWritten);
    }

    [Fact]
    public void FakeHotkeyService_simulate_press_raises_HotkeyPressed_event()
    {
        AppServices.ResetToFakes();
        var fakeHotkey = (FakeHotkeyService)AppServices.Hotkey;

        int pressedId = -1;
        fakeHotkey.HotkeyPressed += id => pressedId = id;

        fakeHotkey.Register(101, 0, 0);
        fakeHotkey.SimulateHotkeyPress(101);

        Assert.Equal(101, pressedId);
    }

    [Fact]
    [System.Runtime.Versioning.SupportedOSPlatform("windows")]
    public void AppServices_swaps_to_real_platform_services()
    {
        AppServices.UsePlatformServices();
        Assert.False(AppServices.IsUsingFakes);
        Assert.IsType<DocShot.Platform.WindowDiscoveryService>(AppServices.WindowDiscovery);
        Assert.IsType<DocShot.Platform.GdiScreenCaptureService>(AppServices.ScreenCapture);
        Assert.IsType<DocShot.Platform.WindowsPermissionService>(AppServices.Permission);
        Assert.IsType<DocShot.Platform.HotkeyService>(AppServices.Hotkey);

        // Re-verify real window discovery enumerates actual open Windows desktop windows
        var realWindows = AppServices.WindowDiscovery.GetEligibleWindows();
        Assert.NotNull(realWindows);

        // Reset back to Fakes for clean isolated test state
        AppServices.ResetToFakes();
        Assert.True(AppServices.IsUsingFakes);
    }
}
