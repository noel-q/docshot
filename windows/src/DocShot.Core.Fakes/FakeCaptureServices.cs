using DocShot.Core.Models;
using DocShot.Core.Primitives;
using DocShot.Core.Services;

namespace DocShot.Core.Fakes;

/// <summary>
/// Returns a fixed, plausible set of windows so App can build and test a window picker without a
/// real <c>EnumWindows</c> call. Deliberately includes windows of different sizes/positions so
/// overlay/selection UI has something non-trivial to lay out against.
/// </summary>
public sealed class FakeWindowDiscoveryService : IWindowDiscoveryService
{
    private static readonly IReadOnlyList<WindowInfo> AllWindows =
    [
        new WindowInfo(1001, new RectD(120, 90, 1280, 800), "chrome.exe", "DocShot - Google Chrome", 4242),
        new WindowInfo(1002, new RectD(200, 160, 900, 620), "notepad.exe", "changelog.txt - Notepad", 5150),
        new WindowInfo(1003, new RectD(-1500, 300, 640, 480), "calculator.exe", "Calculator", 6161),
    ];

    public IReadOnlyList<WindowInfo> GetEligibleWindows(IReadOnlySet<nint>? excludedWindowIds = null)
    {
        if (excludedWindowIds is null || excludedWindowIds.Count == 0) return AllWindows;
        return AllWindows.Where(w => !excludedWindowIds.Contains(w.Id)).ToList();
    }
}

/// <summary>
/// Produces a synthetic BGRA32 checkerboard instead of a real capture, sized to exactly match
/// what was asked for - the same "never round, match the selection exactly" discipline the real
/// WGC-backed implementation has to honour (see PR #6 in docs/WINDOWS_PORT_PLAN.md §5), so App's
/// odd-dimension-handling code gets exercised even against the fake.
/// </summary>
public sealed class FakeScreenCaptureService : IScreenCaptureService
{
    public Task<CapturedImage> CaptureWindow(nint windowId)
    {
        var window = new FakeWindowDiscoveryService().GetEligibleWindows()
            .FirstOrDefault(w => w.Id == windowId);
        var size = window is not null ? window.BoundsInScreen.Size : new SizeD(640, 480);
        return Task.FromResult(MakeCheckerboard((int)size.Width, (int)size.Height, scale: 1.0));
    }

    public Task<CapturedImage> CaptureRegion(uint displayId, RectD rectInDisplay)
    {
        var width = Math.Max(1, (int)Math.Round(rectInDisplay.Width));
        var height = Math.Max(1, (int)Math.Round(rectInDisplay.Height));
        return Task.FromResult(MakeCheckerboard(width, height, scale: 1.0));
    }

    private static CapturedImage MakeCheckerboard(int width, int height, double scale)
    {
        var pixels = new byte[width * height * 4];
        const int tile = 16;
        for (var y = 0; y < height; y++)
        {
            for (var x = 0; x < width; x++)
            {
                var dark = ((x / tile) + (y / tile)) % 2 == 0;
                var offset = (y * width + x) * 4;
                byte shade = dark ? (byte)90 : (byte)180;
                pixels[offset + 0] = shade;    // B
                pixels[offset + 1] = shade;    // G
                pixels[offset + 2] = shade;    // R
                pixels[offset + 3] = 255;      // A
            }
        }
        return new CapturedImage(pixels, width, height, scale);
    }
}

/// <summary>Windows has no revocable capture permission - always granted, matching the real implementation's expected shape.</summary>
public sealed class FakePermissionService : IPermissionService
{
    public bool HasScreenCaptureAccess() => true;
    public Task<bool> RequestScreenCaptureAccess() => Task.FromResult(true);
}

/// <summary>
/// Registers hotkeys in memory only. Set <see cref="SimulateConflictForId"/> to make one
/// registration id fail, so App can build and test its conflict/failure messaging (see
/// windows/docs/PARITY_CHECKLIST.md §3) without needing to actually collide with another app's
/// global hotkey on a real machine.
/// </summary>
public sealed class FakeHotkeyService : IHotkeyService
{
    private readonly HashSet<int> _registered = [];

    public int? SimulateConflictForId { get; set; }

    public bool Register(int id, uint modifiers, uint virtualKeyCode)
    {
        if (id == SimulateConflictForId) return false;
        _registered.Add(id);
        return true;
    }

    public void Unregister(int id) => _registered.Remove(id);

    public bool IsRegistered(int id) => _registered.Contains(id);
}
