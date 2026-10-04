using System.Runtime.InteropServices;
using DocShot.Core.Primitives;
using DocShot.Core.Services;

namespace DocShot.Platform;

/// <summary>
/// Win32 still-capture fallback. WGC remains the intended primary path for production capture
/// because it handles hardware-accelerated and UWP content reliably; this fallback is useful for
/// early W1 wiring and older environments.
/// </summary>
public sealed class GdiScreenCaptureService : IScreenCaptureService
{
    public Task<CapturedImage> CaptureWindow(nint windowId)
    {
        if (!TryGetVisibleWindowBounds(windowId, out var rect))
        {
            throw new InvalidOperationException("Could not resolve the requested window bounds.");
        }

        return Task.FromResult(CaptureScreenRect(rect.Left, rect.Top, rect.Right - rect.Left, rect.Bottom - rect.Top));
    }

    public Task<CapturedImage> CaptureRegion(uint displayId, RectD rectInDisplay)
    {
        var x = checked((int)Math.Round(rectInDisplay.X));
        var y = checked((int)Math.Round(rectInDisplay.Y));
        var width = Math.Max(1, checked((int)Math.Round(rectInDisplay.Width)));
        var height = Math.Max(1, checked((int)Math.Round(rectInDisplay.Height)));
        return Task.FromResult(CaptureScreenRect(x, y, width, height));
    }

    private static CapturedImage CaptureScreenRect(int x, int y, int width, int height)
    {
        var screenDc = NativeMethods.GetDC(nint.Zero);
        if (screenDc == nint.Zero) throw new InvalidOperationException("Could not get the screen device context.");

        var memoryDc = nint.Zero;
        var bitmap = nint.Zero;
        var oldObject = nint.Zero;
        try
        {
            memoryDc = NativeMethods.CreateCompatibleDC(screenDc);
            bitmap = NativeMethods.CreateCompatibleBitmap(screenDc, width, height);
            if (memoryDc == nint.Zero || bitmap == nint.Zero)
            {
                throw new InvalidOperationException("Could not create capture bitmap.");
            }

            oldObject = NativeMethods.SelectObject(memoryDc, bitmap);
            var copied = NativeMethods.BitBlt(memoryDc, 0, 0, width, height, screenDc, x, y, NativeMethods.SRCCOPY | NativeMethods.CAPTUREBLT);
            if (!copied) throw new InvalidOperationException("BitBlt failed while capturing the requested rectangle.");

            var pixels = ReadBgraPixels(memoryDc, bitmap, width, height);
            return new CapturedImage(pixels, width, height, 1.0);
        }
        finally
        {
            if (oldObject != nint.Zero) _ = NativeMethods.SelectObject(memoryDc, oldObject);
            if (bitmap != nint.Zero) _ = NativeMethods.DeleteObject(bitmap);
            if (memoryDc != nint.Zero) _ = NativeMethods.DeleteDC(memoryDc);
            _ = NativeMethods.ReleaseDC(nint.Zero, screenDc);
        }
    }

    private static byte[] ReadBgraPixels(nint deviceContext, nint bitmap, int width, int height)
    {
        var info = new NativeMethods.BitmapInfo
        {
            Header = new NativeMethods.BitmapInfoHeader
            {
                Size = Marshal.SizeOf<NativeMethods.BitmapInfoHeader>(),
                Width = width,
                Height = -height,
                Planes = 1,
                BitCount = 32,
                Compression = NativeMethods.BI_RGB,
            },
        };

        var pixels = new byte[width * height * 4];
        var lines = NativeMethods.GetDIBits(deviceContext, bitmap, 0, (uint)height, pixels, ref info, NativeMethods.DIB_RGB_COLORS);
        if (lines == 0) throw new InvalidOperationException("GetDIBits failed while reading captured pixels.");
        return pixels;
    }

    private static bool TryGetVisibleWindowBounds(nint hwnd, out NativeMethods.Win32Rect rect)
    {
        var hr = NativeMethods.DwmGetWindowAttribute(hwnd, NativeMethods.DWMWA_EXTENDED_FRAME_BOUNDS, out rect, Marshal.SizeOf<NativeMethods.Win32Rect>());
        if (hr == 0 && rect.Right > rect.Left && rect.Bottom > rect.Top) return true;

        return NativeMethods.GetWindowRect(hwnd, out rect);
    }
}

internal static partial class NativeMethods
{
    internal const uint SRCCOPY = 0x00CC0020;
    internal const uint CAPTUREBLT = 0x40000000;
    internal const uint BI_RGB = 0;
    internal const uint DIB_RGB_COLORS = 0;

    [DllImport("user32.dll")]
    internal static extern nint GetDC(nint hwnd);

    [DllImport("user32.dll")]
    internal static extern int ReleaseDC(nint hwnd, nint hdc);

    [DllImport("gdi32.dll")]
    internal static extern nint CreateCompatibleDC(nint hdc);

    [DllImport("gdi32.dll")]
    internal static extern nint CreateCompatibleBitmap(nint hdc, int width, int height);

    [DllImport("gdi32.dll")]
    internal static extern nint SelectObject(nint hdc, nint obj);

    [DllImport("gdi32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool DeleteObject(nint obj);

    [DllImport("gdi32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool DeleteDC(nint hdc);

    [DllImport("gdi32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool BitBlt(nint dest, int xDest, int yDest, int width, int height, nint source, int xSource, int ySource, uint rasterOperation);

    [DllImport("gdi32.dll")]
    internal static extern int GetDIBits(nint hdc, nint bitmap, uint startScan, uint scanLines, byte[] bits, ref BitmapInfo bitmapInfo, uint usage);

    [StructLayout(LayoutKind.Sequential)]
    internal struct BitmapInfo
    {
        internal BitmapInfoHeader Header;
        internal uint Colors;
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct BitmapInfoHeader
    {
        internal int Size;
        internal int Width;
        internal int Height;
        internal ushort Planes;
        internal ushort BitCount;
        internal uint Compression;
        internal uint SizeImage;
        internal int XPelsPerMeter;
        internal int YPelsPerMeter;
        internal uint ClrUsed;
        internal uint ClrImportant;
    }
}
