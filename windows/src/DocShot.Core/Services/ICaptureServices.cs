using DocShot.Core.Models;

namespace DocShot.Core.Services;

/// <summary>
/// Discovers eligible windows to capture/record, filtering out DocShot's own windows, cloaked/
/// virtual-desktop windows, and shell surfaces. Windows equivalent of the macOS
/// <c>WindowDiscoveryService</c>'s <c>CGWindowListCopyWindowInfo</c> filtering, using
/// <c>EnumWindows</c> + <c>DwmGetWindowAttribute(DWMWA_CLOAKED)</c> instead - see the window
/// discovery row in <c>docs/WINDOWS_PORT_PLAN.md</c>'s platform mapping table.
/// </summary>
public interface IWindowDiscoveryService
{
    IReadOnlyList<WindowInfo> GetEligibleWindows(IReadOnlySet<nint>? excludedWindowIds = null);
}

/// <summary>Captures a single still frame of a window or display region.</summary>
public interface IScreenCaptureService
{
    Task<CapturedImage> CaptureWindow(nint windowId);
    Task<CapturedImage> CaptureRegion(uint displayId, DocShot.Core.Primitives.RectD rectInDisplay);
}

/// <summary>
/// A captured still image's raw pixel data and the scale it was captured at. Deliberately not a
/// concrete bitmap type (no <c>SkiaSharp</c>/WIC dependency in <c>DocShot.Core</c>) - callers in
/// <c>DocShot.Platform</c>/<c>DocShot.App</c> wrap this in whatever bitmap type they use for
/// rendering.
/// </summary>
public sealed record CapturedImage(byte[] Bgra32Pixels, int PixelWidth, int PixelHeight, double Scale);

/// <summary>
/// Whether the app is allowed to capture the screen right now.
/// </summary>
/// <remarks>
/// Windows has no persistent, revocable, TCC-style permission gate for a desktop app capturing a
/// window/monitor it already has a handle for - see the permission row in
/// <c>docs/WINDOWS_PORT_PLAN.md</c>. This interface is retained for structural parity with the
/// macOS coordinator and to leave room for a picker-gated fallback path (pre-1903 Windows, or a
/// packaged/sandboxed distribution with different capture entitlements); expect its Windows
/// implementation to be close to a no-op returning "always granted" on typical desktop installs.
/// </remarks>
public interface IPermissionService
{
    bool HasScreenCaptureAccess();
    Task<bool> RequestScreenCaptureAccess();
}

/// <summary>
/// Registers/unregisters the global capture and recording hotkeys. Windows equivalent of the
/// macOS Carbon-based <c>HotkeyService</c>, implemented via <c>RegisterHotKey</c>/
/// <c>UnregisterHotKey</c> on a hidden message-only window handling <c>WM_HOTKEY</c>.
/// </summary>
public interface IHotkeyService
{
    bool Register(int id, uint modifiers, uint virtualKeyCode);
    void Unregister(int id);
}
