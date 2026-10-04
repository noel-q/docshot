using System.Runtime.InteropServices;
using DocShot.Core.Primitives;
using DocShot.Core.Services;
using Windows.Graphics;
using Windows.Graphics.Capture;
using Windows.Graphics.DirectX;
using Windows.Graphics.DirectX.Direct3D11;

namespace DocShot.Platform;

/// <summary>
/// Windows.Graphics.Capture still-capture path. This is the primary capture implementation because
/// WGC captures DWM-composed, hardware-accelerated, and UWP-backed windows reliably where GDI can
/// return stale or black pixels.
/// </summary>
public sealed class WgcScreenCaptureService : IScreenCaptureService
{
    private static readonly Guid IGraphicsCaptureItemGuid = new("79C3F95B-31F7-4EC2-A464-632EF5D30760");
    private static readonly Guid ID3D11Texture2DGuid = new("6F15AAF2-D208-4E89-9AB4-489535D34F9C");
    private static readonly Guid IDXGIDeviceGuid = new("54EC77FA-1377-44E6-8C32-88FD5F44C84C");
    private static readonly Guid IDirect3DDxgiInterfaceAccessGuid = new("A9B3D012-3DF2-4EE3-B8D1-8695F457D3C1");

    private readonly IScreenCaptureService _fallback;
    private readonly TimeSpan _frameTimeout;

    public WgcScreenCaptureService()
        : this(new GdiScreenCaptureService(), TimeSpan.FromSeconds(2))
    {
    }

    internal WgcScreenCaptureService(IScreenCaptureService fallback, TimeSpan frameTimeout)
    {
        _fallback = fallback;
        _frameTimeout = frameTimeout;
    }

    public async Task<CapturedImage> CaptureWindow(nint windowId)
    {
        if (!GraphicsCaptureSession.IsSupported())
        {
            return await _fallback.CaptureWindow(windowId).ConfigureAwait(false);
        }

        try
        {
            var item = CreateItemForWindow(windowId);
            var width = Math.Max(1, item.Size.Width);
            var height = Math.Max(1, item.Size.Height);
            return CaptureItem(item, 0, 0, width, height);
        }
        catch (Exception) when (WgcFallbackEnabled())
        {
            return await _fallback.CaptureWindow(windowId).ConfigureAwait(false);
        }
    }

    public async Task<CapturedImage> CaptureRegion(uint displayId, RectD rectInDisplay)
    {
        if (!GraphicsCaptureSession.IsSupported())
        {
            return await _fallback.CaptureRegion(displayId, rectInDisplay).ConfigureAwait(false);
        }

        var x = checked((int)Math.Round(rectInDisplay.X));
        var y = checked((int)Math.Round(rectInDisplay.Y));
        var width = Math.Max(1, checked((int)Math.Round(rectInDisplay.Width)));
        var height = Math.Max(1, checked((int)Math.Round(rectInDisplay.Height)));

        try
        {
            var monitor = MonitorFromRegion(displayId, x, y, width, height);
            if (monitor.Handle == nint.Zero)
            {
                return await _fallback.CaptureRegion(displayId, rectInDisplay).ConfigureAwait(false);
            }

            var item = CreateItemForMonitor(monitor.Handle);
            var sourceX = x - monitor.Bounds.Left;
            var sourceY = y - monitor.Bounds.Top;
            if (sourceX < 0 || sourceY < 0 || sourceX + width > item.Size.Width || sourceY + height > item.Size.Height)
            {
                return await _fallback.CaptureRegion(displayId, rectInDisplay).ConfigureAwait(false);
            }

            return CaptureItem(item, sourceX, sourceY, width, height);
        }
        catch (Exception) when (WgcFallbackEnabled())
        {
            return await _fallback.CaptureRegion(displayId, rectInDisplay).ConfigureAwait(false);
        }
    }

    private CapturedImage CaptureItem(GraphicsCaptureItem item, int sourceX, int sourceY, int width, int height)
    {
        using var d3d = D3D11Device.Create();
        using var framePool = Direct3D11CaptureFramePool.CreateFreeThreaded(
            d3d.Device,
            DirectXPixelFormat.B8G8R8A8UIntNormalized,
            numberOfBuffers: 1,
            item.Size);
        using var session = framePool.CreateCaptureSession(item);

        session.IsCursorCaptureEnabled = false;
        session.StartCapture();

        using var frame = WaitForFrame(framePool);
        using var surface = frame.Surface;
        var pixels = ReadTexturePixels(surface, sourceX, sourceY, width, height, d3d);
        return new CapturedImage(pixels, width, height, 1.0);
    }

    private Direct3D11CaptureFrame WaitForFrame(Direct3D11CaptureFramePool framePool)
    {
        var deadline = DateTimeOffset.UtcNow + _frameTimeout;
        while (DateTimeOffset.UtcNow < deadline)
        {
            var frame = framePool.TryGetNextFrame();
            if (frame is not null) return frame;
            Thread.Sleep(15);
        }

        throw new TimeoutException("Windows.Graphics.Capture did not produce a frame before the timeout.");
    }

    private static byte[] ReadTexturePixels(IDirect3DSurface surface, int sourceX, int sourceY, int width, int height, D3D11Device d3d)
    {
        var sourceTexture = nint.Zero;
        var stagingTexture = nint.Zero;
        try
        {
            sourceTexture = GetTexturePointer(surface);
            var desc = D3D11.GetTextureDesc(sourceTexture);
            desc.BindFlags = 0;
            desc.MiscFlags = 0;
            desc.CpuAccessFlags = D3D11.CpuAccessRead;
            desc.Usage = D3D11.UsageStaging;

            stagingTexture = D3D11.CreateTexture2D(d3d.NativeDevice, ref desc);
            D3D11.CopyResource(d3d.NativeContext, stagingTexture, sourceTexture);

            var mapped = D3D11.MapRead(d3d.NativeContext, stagingTexture);
            try
            {
                var pixels = new byte[checked(width * height * 4)];
                for (var row = 0; row < height; row++)
                {
                    var source = mapped.Data + ((sourceY + row) * mapped.RowPitch) + (sourceX * 4);
                    Marshal.Copy(source, pixels, row * width * 4, width * 4);
                }

                return pixels;
            }
            finally
            {
                D3D11.Unmap(d3d.NativeContext, stagingTexture);
            }
        }
        finally
        {
            if (stagingTexture != nint.Zero) Marshal.Release(stagingTexture);
            if (sourceTexture != nint.Zero) Marshal.Release(sourceTexture);
        }
    }

    private static nint GetTexturePointer(IDirect3DSurface surface)
    {
        var marshaler = WinRT.MarshalInterface<IDirect3DSurface>.CreateMarshaler(surface);
        var accessGuid = IDirect3DDxgiInterfaceAccessGuid;
        var textureGuid = ID3D11Texture2DGuid;
        var surfacePtr = WinRT.MarshalInterface<IDirect3DSurface>.GetAbi(marshaler);
        Marshal.QueryInterface(surfacePtr, ref accessGuid, out var accessPtr);
        try
        {
            if (accessPtr == nint.Zero) throw new InvalidOperationException("Could not access the captured DXGI surface.");
            var access = (IDirect3DDxgiInterfaceAccess)Marshal.GetObjectForIUnknown(accessPtr);
            access.GetInterface(textureGuid, out var texture);
            if (texture == nint.Zero) throw new InvalidOperationException("Could not resolve captured surface texture.");
            return texture;
        }
        finally
        {
            if (accessPtr != nint.Zero) Marshal.Release(accessPtr);
            WinRT.MarshalInterface<IDirect3DSurface>.DisposeMarshaler(marshaler);
        }
    }

    private static GraphicsCaptureItem CreateItemForWindow(nint hwnd)
    {
        using var factory = WinRT.ActivationFactory.Get("Windows.Graphics.Capture.GraphicsCaptureItem");
        var interop = (IGraphicsCaptureItemInterop)Marshal.GetObjectForIUnknown(factory.ThisPtr);
        var iid = IGraphicsCaptureItemGuid;
        var hr = interop.CreateForWindow(hwnd, iid, out var itemPtr);
        Marshal.ThrowExceptionForHR(hr);
        return FromAbi(itemPtr);
    }

    private static GraphicsCaptureItem CreateItemForMonitor(nint monitor)
    {
        using var factory = WinRT.ActivationFactory.Get("Windows.Graphics.Capture.GraphicsCaptureItem");
        var interop = (IGraphicsCaptureItemInterop)Marshal.GetObjectForIUnknown(factory.ThisPtr);
        var iid = IGraphicsCaptureItemGuid;
        var hr = interop.CreateForMonitor(monitor, iid, out var itemPtr);
        Marshal.ThrowExceptionForHR(hr);
        return FromAbi(itemPtr);
    }

    private static GraphicsCaptureItem FromAbi(nint itemPtr)
    {
        try
        {
            return WinRT.MarshalInterface<GraphicsCaptureItem>.FromAbi(itemPtr);
        }
        finally
        {
            Marshal.Release(itemPtr);
        }
    }

    private static MonitorInfo MonitorFromRegion(uint displayId, int x, int y, int width, int height)
    {
        var monitors = new List<MonitorInfo>();
        NativeMethods.EnumDisplayMonitors(nint.Zero, nint.Zero, (monitor, _, rect, _) =>
        {
            monitors.Add(new MonitorInfo(monitor, new NativeMethods.Win32Rect(rect.Left, rect.Top, rect.Right, rect.Bottom)));
            return true;
        }, nint.Zero);

        if (displayId > 0 && displayId <= monitors.Count)
        {
            var requested = monitors[checked((int)displayId) - 1];
            if (Contains(requested.Bounds, x, y, width, height)) return requested;
        }

        var centerX = x + (width / 2);
        var centerY = y + (height / 2);
        return monitors.FirstOrDefault(m =>
            centerX >= m.Bounds.Left &&
            centerX < m.Bounds.Right &&
            centerY >= m.Bounds.Top &&
            centerY < m.Bounds.Bottom);
    }

    private static bool Contains(NativeMethods.Win32Rect bounds, int x, int y, int width, int height) =>
        x >= bounds.Left &&
        y >= bounds.Top &&
        x + width <= bounds.Right &&
        y + height <= bounds.Bottom;

    private static bool WgcFallbackEnabled() =>
        !string.Equals(Environment.GetEnvironmentVariable("DOCSHOT_DISABLE_WGC_FALLBACK"), "1", StringComparison.Ordinal);

    private sealed class D3D11Device : IDisposable
    {
        private D3D11Device(nint nativeDevice, nint nativeContext, IDirect3DDevice device)
        {
            NativeDevice = nativeDevice;
            NativeContext = nativeContext;
            Device = device;
        }

        internal nint NativeDevice { get; }
        internal nint NativeContext { get; }
        internal IDirect3DDevice Device { get; }

        internal static D3D11Device Create()
        {
            var hr = NativeMethods.D3D11CreateDevice(
                nint.Zero,
                D3D11.DriverTypeHardware,
                nint.Zero,
                D3D11.CreateDeviceBgraSupport,
                nint.Zero,
                0,
                D3D11.SdkVersion,
                out var device,
                nint.Zero,
                out var context);
            Marshal.ThrowExceptionForHR(hr);

            var iid = IDXGIDeviceGuid;
            Marshal.QueryInterface(device, ref iid, out var dxgiDevice);
            if (dxgiDevice == nint.Zero) throw new InvalidOperationException("Could not query the D3D device for IDXGIDevice.");

            nint direct3DDevice = nint.Zero;
            try
            {
                hr = NativeMethods.CreateDirect3D11DeviceFromDXGIDevice(dxgiDevice, out direct3DDevice);
                Marshal.ThrowExceptionForHR(hr);
                var winrtDevice = WinRT.MarshalInterface<IDirect3DDevice>.FromAbi(direct3DDevice);
                return new D3D11Device(device, context, winrtDevice);
            }
            finally
            {
                Marshal.Release(dxgiDevice);
                if (direct3DDevice != nint.Zero) Marshal.Release(direct3DDevice);
            }
        }

        public void Dispose()
        {
            Device.Dispose();
            if (NativeContext != nint.Zero) Marshal.Release(NativeContext);
            if (NativeDevice != nint.Zero) Marshal.Release(NativeDevice);
        }
    }

    private readonly record struct MonitorInfo(nint Handle, NativeMethods.Win32Rect Bounds);
}

internal static partial class NativeMethods
{
    internal delegate bool MonitorEnumProc(nint monitor, nint hdc, WgcScreenCaptureServiceNativeRect rect, nint data);

    [DllImport("user32.dll")]
    [return: MarshalAs(UnmanagedType.Bool)]
    internal static extern bool EnumDisplayMonitors(nint hdc, nint clipRect, MonitorEnumProc callback, nint data);

    [DllImport("d3d11.dll")]
    internal static extern int D3D11CreateDevice(
        nint adapter,
        uint driverType,
        nint software,
        uint flags,
        nint featureLevels,
        uint featureLevelsCount,
        uint sdkVersion,
        out nint device,
        nint featureLevel,
        out nint immediateContext);

    [DllImport("d3d11.dll", ExactSpelling = true)]
    internal static extern int CreateDirect3D11DeviceFromDXGIDevice(nint dxgiDevice, out nint graphicsDevice);
}

[StructLayout(LayoutKind.Sequential)]
internal readonly struct WgcScreenCaptureServiceNativeRect
{
    internal readonly int Left;
    internal readonly int Top;
    internal readonly int Right;
    internal readonly int Bottom;
}

[ComImport]
[Guid("3628E81B-3CAC-4C60-B7F4-23CE0E0C3356")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
internal interface IGraphicsCaptureItemInterop
{
    [PreserveSig]
    int CreateForWindow(nint window, in Guid iid, out nint result);

    [PreserveSig]
    int CreateForMonitor(nint monitor, in Guid iid, out nint result);
}

[ComImport]
[Guid("A9B3D012-3DF2-4EE3-B8D1-8695F457D3C1")]
[InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
internal interface IDirect3DDxgiInterfaceAccess
{
    [PreserveSig]
    int GetInterface(in Guid iid, out nint p);
}

internal static class D3D11
{
    internal const uint DriverTypeHardware = 1;
    internal const uint CreateDeviceBgraSupport = 0x20;
    internal const uint SdkVersion = 7;
    internal const uint UsageStaging = 3;
    internal const uint CpuAccessRead = 0x20000;

    private delegate int CreateTexture2DDelegate(nint self, ref Texture2DDescription description, nint initialData, out nint texture);
    private delegate void GetDescDelegate(nint self, out Texture2DDescription description);
    private delegate void CopyResourceDelegate(nint self, nint destination, nint source);
    private delegate int MapDelegate(nint self, nint resource, uint subresource, uint mapType, uint mapFlags, out MappedSubresource mapped);
    private delegate void UnmapDelegate(nint self, nint resource, uint subresource);

    internal static nint CreateTexture2D(nint device, ref Texture2DDescription description)
    {
        var create = GetMethod<CreateTexture2DDelegate>(device, 5);
        var hr = create(device, ref description, nint.Zero, out var texture);
        Marshal.ThrowExceptionForHR(hr);
        return texture;
    }

    internal static Texture2DDescription GetTextureDesc(nint texture)
    {
        var getDesc = GetMethod<GetDescDelegate>(texture, 10);
        getDesc(texture, out var description);
        return description;
    }

    internal static void CopyResource(nint context, nint destination, nint source)
    {
        var copy = GetMethod<CopyResourceDelegate>(context, 47);
        copy(context, destination, source);
    }

    internal static MappedSubresource MapRead(nint context, nint resource)
    {
        var map = GetMethod<MapDelegate>(context, 14);
        var hr = map(context, resource, 0, 1, 0, out var mapped);
        Marshal.ThrowExceptionForHR(hr);
        return mapped;
    }

    internal static void Unmap(nint context, nint resource)
    {
        var unmap = GetMethod<UnmapDelegate>(context, 15);
        unmap(context, resource, 0);
    }

    private static TDelegate GetMethod<TDelegate>(nint comObject, int vtableIndex)
        where TDelegate : Delegate
    {
        var vtable = Marshal.ReadIntPtr(comObject);
        var method = Marshal.ReadIntPtr(vtable, vtableIndex * nint.Size);
        return Marshal.GetDelegateForFunctionPointer<TDelegate>(method);
    }

    [StructLayout(LayoutKind.Sequential)]
    internal struct Texture2DDescription
    {
        internal uint Width;
        internal uint Height;
        internal uint MipLevels;
        internal uint ArraySize;
        internal uint Format;
        internal SampleDescription SampleDescription;
        internal uint Usage;
        internal uint BindFlags;
        internal uint CpuAccessFlags;
        internal uint MiscFlags;
    }

    [StructLayout(LayoutKind.Sequential)]
    internal readonly struct SampleDescription
    {
        internal readonly uint Count;
        internal readonly uint Quality;
    }

    [StructLayout(LayoutKind.Sequential)]
    internal readonly struct MappedSubresource
    {
        internal readonly nint Data;
        internal readonly int RowPitch;
        internal readonly int DepthPitch;
    }
}
