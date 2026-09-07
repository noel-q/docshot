using System;
using System.Collections.Generic;
using System.Runtime.InteropServices;
using DocShot.Core.Primitives;

namespace DocShot.App.Services;

public record DisplayMonitorInfo(
    IntPtr HMonitor,
    string DeviceName,
    bool IsPrimary,
    RectD PhysicalBounds,
    RectD DipBounds,
    double ScaleFactor,
    uint DpiX,
    uint DpiY)
{
    /// <summary>
    /// Converts a local overlay DIP rectangle on this monitor to physical source pixels on this monitor.
    /// </summary>
    public RectD DipToPhysical(RectD dipRect)
    {
        double px = Math.Round(dipRect.X * ScaleFactor);
        double py = Math.Round(dipRect.Y * ScaleFactor);
        double pw = Math.Round(dipRect.Width * ScaleFactor);
        double ph = Math.Round(dipRect.Height * ScaleFactor);
        return new RectD(px, py, pw, ph);
    }

    /// <summary>
    /// Converts a physical source pixel rectangle on this monitor to local overlay DIP coordinates.
    /// </summary>
    public RectD PhysicalToDip(RectD physicalRect)
    {
        double dx = physicalRect.X / ScaleFactor;
        double dy = physicalRect.Y / ScaleFactor;
        double dw = physicalRect.Width / ScaleFactor;
        double dh = physicalRect.Height / ScaleFactor;
        return new RectD(dx, dy, dw, dh);
    }

    /// <summary>
    /// Performs a round-trip conversion: Physical Source Pixels -> DIPs -> Physical Source Pixels.
    /// Returns true if the round-tripped physical rectangle matches the original physical rectangle.
    /// </summary>
    public bool VerifyRoundTrip(RectD originalPhysical, out RectD roundTrippedPhysical, out RectD intermediateDip)
    {
        intermediateDip = PhysicalToDip(originalPhysical);
        roundTrippedPhysical = DipToPhysical(intermediateDip);
        return Math.Abs(originalPhysical.X - roundTrippedPhysical.X) < 0.001 &&
               Math.Abs(originalPhysical.Y - roundTrippedPhysical.Y) < 0.001 &&
               Math.Abs(originalPhysical.Width - roundTrippedPhysical.Width) < 0.001 &&
               Math.Abs(originalPhysical.Height - roundTrippedPhysical.Height) < 0.001;
    }
}

public static class DisplayMonitorHelper
{
    private const int MDT_EFFECTIVE_DPI = 0;
    private static readonly IntPtr DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2 = new IntPtr(-4);

    [DllImport("user32.dll")]
    private static extern bool SetProcessDpiAwarenessContext(IntPtr dpiContext);

    public static void EnsureDpiAwareness()
    {
        try
        {
            SetProcessDpiAwarenessContext(DPI_AWARENESS_CONTEXT_PER_MONITOR_AWARE_V2);
        }
        catch { }
    }

    [StructLayout(LayoutKind.Sequential)]
    private struct RECT
    {
        public int Left;
        public int Top;
        public int Right;
        public int Bottom;
    }

    private delegate bool MonitorEnumProc(IntPtr hMonitor, IntPtr hdcMonitor, ref RECT lprcMonitor, IntPtr dwData);

    [DllImport("user32.dll")]
    private static extern bool EnumDisplayMonitors(IntPtr hdc, IntPtr lprcClip, MonitorEnumProc lpfnEnum, IntPtr dwData);

    [DllImport("shcore.dll")]
    private static extern int GetDpiForMonitor(IntPtr hMonitor, int dpiType, out uint dpiX, out uint dpiY);

    [StructLayout(LayoutKind.Sequential, CharSet = CharSet.Auto)]
    private struct MONITORINFOEX
    {
        public int cbSize;
        public RECT rcMonitor;
        public RECT rcWork;
        public uint dwFlags;
        [MarshalAs(UnmanagedType.ByValTStr, SizeConst = 32)]
        public string szDevice;
    }

    private const uint MONITORINFOF_PRIMARY = 0x00000001;

    [DllImport("user32.dll", CharSet = CharSet.Auto)]
    private static extern bool GetMonitorInfo(IntPtr hMonitor, ref MONITORINFOEX lpmi);

    public static IReadOnlyList<DisplayMonitorInfo> GetMonitors()
    {
        EnsureDpiAwareness();
        var monitors = new List<DisplayMonitorInfo>();

        EnumDisplayMonitors(IntPtr.Zero, IntPtr.Zero, (IntPtr hMon, IntPtr hdc, ref RECT r, IntPtr data) =>
        {
            var mi = new MONITORINFOEX();
            mi.cbSize = Marshal.SizeOf(typeof(MONITORINFOEX));
            bool isPrimary = false;
            string deviceName = "Display";

            if (GetMonitorInfo(hMon, ref mi))
            {
                isPrimary = (mi.dwFlags & MONITORINFOF_PRIMARY) != 0;
                deviceName = mi.szDevice ?? "Display";
            }

            uint dpiX = 96, dpiY = 96;
            try
            {
                GetDpiForMonitor(hMon, MDT_EFFECTIVE_DPI, out dpiX, out dpiY);
            }
            catch
            {
                // Fallback for pre-Win8.1 if shcore fails
                dpiX = 96;
                dpiY = 96;
            }

            double scaleFactor = dpiX / 96.0;
            double physX = mi.rcMonitor.Left;
            double physY = mi.rcMonitor.Top;
            double physW = mi.rcMonitor.Right - mi.rcMonitor.Left;
            double physH = mi.rcMonitor.Bottom - mi.rcMonitor.Top;

            var physicalBounds = new RectD(physX, physY, physW, physH);

            // In WPF PerMonitorV2, DipBounds are calculated by dividing Virtual Screen coordinates by scaleFactor
            var dipBounds = new RectD(
                physX / scaleFactor,
                physY / scaleFactor,
                physW / scaleFactor,
                physH / scaleFactor
            );

            monitors.Add(new DisplayMonitorInfo(
                hMon,
                deviceName,
                isPrimary,
                physicalBounds,
                dipBounds,
                scaleFactor,
                dpiX,
                dpiY));

            return true;
        }, IntPtr.Zero);

        return monitors;
    }
}
