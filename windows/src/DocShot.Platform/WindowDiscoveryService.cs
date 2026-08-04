using System.Diagnostics;
using System.Runtime.InteropServices;
using System.Text;
using DocShot.Core.Models;
using DocShot.Core.Primitives;
using DocShot.Core.Services;

namespace DocShot.Platform;

public sealed class WindowDiscoveryService : IWindowDiscoveryService
{
    private static readonly HashSet<string> DeniedClasses = new(StringComparer.OrdinalIgnoreCase)
    {
        "Progman",
        "WorkerW",
        "Shell_TrayWnd",
        "Shell_SecondaryTrayWnd",
        "DV2ControlHost",
        "MsgrIMEWindowClass",
        "SysShadow",
    };

    private readonly int _ownProcessId;

    public WindowDiscoveryService() : this(Environment.ProcessId) { }

    internal WindowDiscoveryService(int ownProcessId)
    {
        _ownProcessId = ownProcessId;
    }

    public IReadOnlyList<WindowInfo> GetEligibleWindows(IReadOnlySet<nint>? excludedWindowIds = null)
    {
        var windows = new List<WindowInfo>();
        NativeMethods.EnumWindows((hwnd, _) =>
        {
            if (excludedWindowIds?.Contains(hwnd) == true) return true;
            if (!IsEligible(hwnd, out var info)) return true;

            windows.Add(info);
            return true;
        }, nint.Zero);

        return windows
            .OrderBy(w => w.OwnerName, StringComparer.OrdinalIgnoreCase)
            .ThenBy(w => w.Title, StringComparer.OrdinalIgnoreCase)
            .ToList();
    }

    private bool IsEligible(nint hwnd, out WindowInfo info)
    {
        info = default!;

        if (hwnd == nint.Zero) return false;
        if (!NativeMethods.IsWindowVisible(hwnd) || NativeMethods.IsIconic(hwnd)) return false;

        _ = NativeMethods.GetWindowThreadProcessId(hwnd, out var processId);
        if (processId == 0 || processId == _ownProcessId) return false;

        if (IsCloaked(hwnd)) return false;

        var className = GetClassName(hwnd);
        if (DeniedClasses.Contains(className)) return false;

        var title = GetWindowText(hwnd).Trim();
        if (string.IsNullOrWhiteSpace(title)) return false;

        if (!TryGetVisibleWindowBounds(hwnd, out var rect)) return false;
        var width = rect.Right - rect.Left;
        var height = rect.Bottom - rect.Top;
        if (width < 64 || height < 64) return false;

        info = new WindowInfo(
            hwnd,
            new RectD(rect.Left, rect.Top, width, height),
            GetProcessName(processId),
            title,
            unchecked((int)processId));
        return true;
    }

    private static bool IsCloaked(nint hwnd)
    {
        int cloaked;
        var hr = NativeMethods.DwmGetWindowAttribute(hwnd, NativeMethods.DWMWA_CLOAKED, out cloaked, sizeof(int));
        return hr == 0 && cloaked != 0;
    }

    private static bool TryGetVisibleWindowBounds(nint hwnd, out NativeMethods.Win32Rect rect)
    {
        var hr = NativeMethods.DwmGetWindowAttribute(hwnd, NativeMethods.DWMWA_EXTENDED_FRAME_BOUNDS, out rect, Marshal.SizeOf<NativeMethods.Win32Rect>());
        if (hr == 0 && rect.Right > rect.Left && rect.Bottom > rect.Top) return true;

        return NativeMethods.GetWindowRect(hwnd, out rect);
    }

    private static string GetWindowText(nint hwnd)
    {
        var length = NativeMethods.GetWindowTextLength(hwnd);
        if (length <= 0) return string.Empty;

        var builder = new StringBuilder(length + 1);
        _ = NativeMethods.GetWindowText(hwnd, builder, builder.Capacity);
        return builder.ToString();
    }

    private static string GetClassName(nint hwnd)
    {
        var builder = new StringBuilder(256);
        _ = NativeMethods.GetClassName(hwnd, builder, builder.Capacity);
        return builder.ToString();
    }

    private static string GetProcessName(uint processId)
    {
        try
        {
            using var process = Process.GetProcessById(unchecked((int)processId));
            return process.ProcessName;
        }
        catch
        {
            return $"pid:{processId}";
        }
    }
}

internal static partial class NativeMethods
{
    internal const int DWMWA_CLOAKED = 14;
    internal const int DWMWA_EXTENDED_FRAME_BOUNDS = 9;

    internal delegate bool EnumWindowsProc(nint hwnd, nint lParam);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool EnumWindows(EnumWindowsProc callback, nint lParam);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool IsWindowVisible(nint hwnd);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool IsIconic(nint hwnd);

    [DllImport("user32.dll")]
    internal static extern uint GetWindowThreadProcessId(nint hwnd, out uint processId);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    internal static extern int GetWindowText(nint hwnd, StringBuilder text, int maxCount);

    [DllImport("user32.dll")]
    internal static extern int GetWindowTextLength(nint hwnd);

    [DllImport("user32.dll", CharSet = CharSet.Unicode)]
    internal static extern int GetClassName(nint hwnd, StringBuilder className, int maxCount);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool GetWindowRect(nint hwnd, out Win32Rect rect);

    [DllImport("dwmapi.dll")]
    internal static extern int DwmGetWindowAttribute(nint hwnd, int attribute, out int value, int size);

    [DllImport("dwmapi.dll")]
    internal static extern int DwmGetWindowAttribute(nint hwnd, int attribute, out Win32Rect value, int size);

    [StructLayout(LayoutKind.Sequential)]
    internal readonly struct Win32Rect
    {
        internal Win32Rect(int left, int top, int right, int bottom)
        {
            Left = left;
            Top = top;
            Right = right;
            Bottom = bottom;
        }

        internal readonly int Left;
        internal readonly int Top;
        internal readonly int Right;
        internal readonly int Bottom;
    }
}
