using System;
using DocShot.Core.Services;
using DocShot.Core.Fakes;

namespace DocShot.App.Services;

/// <summary>
/// Central service provider for DocShot.App. Holds references to DocShot.Core.Services interfaces.
/// In Debug mode, defaults to DocShot.Core.Fakes for fast UI development.
/// Can be swapped to real DocShot.Platform implementations when PR #6/Platform work lands.
/// </summary>
public static class AppServices
{
    public static IWindowDiscoveryService WindowDiscovery { get; set; }
    public static IScreenCaptureService ScreenCapture { get; set; }
    public static IPermissionService Permission { get; set; }
    public static IHotkeyService Hotkey { get; set; }
    public static IPasteboardWriter Pasteboard { get; set; }
    public static IFileWriter FileWriter { get; set; }
    public static IRecordingSessionFactory RecordingSessionFactory { get; set; }
    public static ITemporaryRecordingStore TempStore { get; set; }
    public static IMovieSaving MovieSaving { get; set; }
    public static IGifExporting GifExporting { get; set; }

    public static bool IsUsingFakes { get; private set; } = true;

    static AppServices()
    {
        // Default startup initialization with Fakes
        WindowDiscovery = new FakeWindowDiscoveryService();
        ScreenCapture = new FakeScreenCaptureService();
        Permission = new FakePermissionService();
        Hotkey = new FakeHotkeyService();
        Pasteboard = new FakePasteboardWriter();
        FileWriter = new FakeFileWriter();
        RecordingSessionFactory = new FakeRecordingSessionFactory();
        TempStore = new FakeTemporaryRecordingStore();
        MovieSaving = new FakeMovieSaving();
        GifExporting = new FakeGifExporting();
        IsUsingFakes = true;
    }

    public static void ResetToFakes()
    {
        WindowDiscovery = new FakeWindowDiscoveryService();
        ScreenCapture = new FakeScreenCaptureService();
        Permission = new FakePermissionService();
        Hotkey = new FakeHotkeyService();
        Pasteboard = new FakePasteboardWriter();
        FileWriter = new FakeFileWriter();
        RecordingSessionFactory = new FakeRecordingSessionFactory();
        TempStore = new FakeTemporaryRecordingStore();
        MovieSaving = new FakeMovieSaving();
        GifExporting = new FakeGifExporting();
        IsUsingFakes = true;
    }

    public static void UsePlatformServices()
    {
        WindowDiscovery = new DocShot.Platform.WindowDiscoveryService();
        ScreenCapture = new DocShot.Platform.GdiScreenCaptureService();
        Permission = new DocShot.Platform.WindowsPermissionService();
        Hotkey = new DocShot.Platform.HotkeyService();
        TempStore = new DocShot.Platform.TemporaryRecordingStore();
        // Keep fake output writers if needed or fallback
        if (Pasteboard == null) Pasteboard = new FakePasteboardWriter();
        if (FileWriter == null) FileWriter = new FakeFileWriter();
        IsUsingFakes = false;
    }
}
