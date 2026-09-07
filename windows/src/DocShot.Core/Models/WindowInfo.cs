using DocShot.Core.Primitives;

namespace DocShot.Core.Models;

/// <summary>
/// One window discovered as an eligible capture/recording target.
/// </summary>
/// <remarks>
/// <see cref="Id"/> is an <see cref="nint"/> HWND rather than macOS's <c>CGWindowID</c> (a plain
/// integer). Windows identifies windows by handle, not by a stable small integer, so callers must
/// not persist an <see cref="Id"/> across a window's lifetime the way the macOS window ID can be
/// compared cheaply - re-resolve immediately before use, same discipline the macOS recording
/// architecture already requires for its live <c>SCWindow</c> resolution.
/// </remarks>
public sealed record WindowInfo(
    nint Id,
    RectD BoundsInScreen,
    string OwnerName,
    string Title,
    int ProcessId);
