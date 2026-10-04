using System.Runtime.InteropServices;
using DocShot.Core.Services;

namespace DocShot.Platform;

internal sealed class MediaFoundationVideoWriter : IDisposable
{
    private const int MF_VERSION = 0x00020070;
    private const int MF_SDK_VERSION = 0x0002;
    private const int MF_API_VERSION = 0x0070;
    private const int MFSTARTUP_NOSOCKET = 0x1;
    private const int MFVideoInterlace_Progressive = 2;

    private static readonly Guid MFMediaTypeVideo = new("73646976-0000-0010-8000-00aa00389b71");
    private static readonly Guid MFVideoFormatH264 = new("34363248-0000-0010-8000-00aa00389b71");
    private static readonly Guid MFVideoFormatRgb32 = new("00000016-0000-0010-8000-00aa00389b71");
    private static readonly Guid MF_MT_MAJOR_TYPE = new("48eba18e-f8c9-4687-bf11-0a74c9f96a8f");
    private static readonly Guid MF_MT_SUBTYPE = new("f7e34c9a-42e8-4714-b74b-cb29d72c35e5");
    private static readonly Guid MF_MT_INTERLACE_MODE = new("e2724bb8-e676-4806-b4b2-a8d6efb44ccd");
    private static readonly Guid MF_MT_FRAME_SIZE = new("1652c33d-d6b2-4012-b834-72030849a37d");
    private static readonly Guid MF_MT_FRAME_RATE = new("c459a2e8-3d2c-4e44-b132-fee5156c7bb0");
    private static readonly Guid MF_MT_PIXEL_ASPECT_RATIO = new("c6376a1e-8d0a-4027-be45-6d9a0ad39bb6");
    private static readonly Guid MF_MT_ALL_SAMPLES_INDEPENDENT = new("c9173739-5e56-461c-b713-46fb995cb95f");
    private static readonly Guid MF_MT_AVG_BITRATE = new("20332624-fb0d-4d9e-bd0d-cbf6786c102e");
    private static readonly Guid MF_MT_DEFAULT_STRIDE = new("644b4e48-1e02-4516-b0eb-c01ca9d49ac6");

    private readonly IMFSinkWriter _writer;
    private readonly int _width;
    private readonly int _height;
    private readonly int _frameDurationHns;
    private readonly uint _streamIndex;
    private bool _finalized;

    public MediaFoundationVideoWriter(Uri outputUrl, int width, int height, int framesPerSecond)
    {
        if (width <= 0 || height <= 0) throw new ArgumentOutOfRangeException(nameof(width));
        if (framesPerSecond <= 0) throw new ArgumentOutOfRangeException(nameof(framesPerSecond));

        _width = width;
        _height = height;
        _frameDurationHns = 10_000_000 / framesPerSecond;

        ThrowIfFailed(MFStartup(MF_VERSION, MFSTARTUP_NOSOCKET), "MFStartup");
        ThrowIfFailed(MFCreateSinkWriterFromURL(outputUrl.LocalPath, nint.Zero, null, out _writer), "MFCreateSinkWriterFromURL");

        var outputType = CreateVideoType(MFVideoFormatH264, width, height, framesPerSecond);
        outputType.SetUINT32(MF_MT_AVG_BITRATE, BitrateFor(width, height, framesPerSecond));
        ThrowIfFailed(_writer.AddStream(outputType, out _streamIndex), "IMFSinkWriter.AddStream");

        var inputType = CreateVideoType(MFVideoFormatRgb32, width, height, framesPerSecond);
        inputType.SetUINT32(MF_MT_DEFAULT_STRIDE, width * 4);
        inputType.SetUINT32(MF_MT_ALL_SAMPLES_INDEPENDENT, 1);
        ThrowIfFailed(_writer.SetInputMediaType(_streamIndex, inputType, null), "IMFSinkWriter.SetInputMediaType");
        ThrowIfFailed(_writer.BeginWriting(), "IMFSinkWriter.BeginWriting");
    }

    public void WriteFrame(CapturedImage image, long frameIndex)
    {
        if (_finalized) throw new InvalidOperationException("Cannot write after finalizing the recording.");
        if (image.PixelWidth != _width || image.PixelHeight != _height)
        {
            throw new InvalidOperationException($"Frame size {image.PixelWidth}x{image.PixelHeight} did not match writer size {_width}x{_height}.");
        }

        var byteCount = image.Bgra32Pixels.Length;
        ThrowIfFailed(MFCreateMemoryBuffer(byteCount, out var buffer), "MFCreateMemoryBuffer");
        nint data = nint.Zero;
        try
        {
            ThrowIfFailed(buffer.Lock(out data, out _, out _), "IMFMediaBuffer.Lock");
            Marshal.Copy(image.Bgra32Pixels, 0, data, byteCount);
            ThrowIfFailed(buffer.Unlock(), "IMFMediaBuffer.Unlock");
            data = nint.Zero;
            ThrowIfFailed(buffer.SetCurrentLength(byteCount), "IMFMediaBuffer.SetCurrentLength");

            ThrowIfFailed(MFCreateSample(out var sample), "MFCreateSample");
            try
            {
                ThrowIfFailed(sample.AddBuffer(buffer), "IMFSample.AddBuffer");
                ThrowIfFailed(sample.SetSampleTime(frameIndex * _frameDurationHns), "IMFSample.SetSampleTime");
                ThrowIfFailed(sample.SetSampleDuration(_frameDurationHns), "IMFSample.SetSampleDuration");
                ThrowIfFailed(_writer.WriteSample(_streamIndex, sample), "IMFSinkWriter.WriteSample");
            }
            finally
            {
                Marshal.FinalReleaseComObject(sample);
            }
        }
        finally
        {
            if (data != nint.Zero) _ = buffer.Unlock();
            Marshal.FinalReleaseComObject(buffer);
        }
    }

    public void FinalizeFile()
    {
        if (_finalized) return;
        _finalized = true;
        ThrowIfFailed(_writer.Finalize_(), "IMFSinkWriter.Finalize");
    }

    public void Dispose()
    {
        Marshal.FinalReleaseComObject(_writer);
        MFShutdown();
    }

    private static IMFMediaType CreateVideoType(Guid subtype, int width, int height, int framesPerSecond)
    {
        ThrowIfFailed(MFCreateMediaType(out var type), "MFCreateMediaType");
        type.SetGUID(MF_MT_MAJOR_TYPE, MFMediaTypeVideo);
        type.SetGUID(MF_MT_SUBTYPE, subtype);
        type.SetUINT32(MF_MT_INTERLACE_MODE, MFVideoInterlace_Progressive);
        SetAttributeRatio(type, MF_MT_FRAME_SIZE, width, height);
        SetAttributeRatio(type, MF_MT_FRAME_RATE, framesPerSecond, 1);
        SetAttributeRatio(type, MF_MT_PIXEL_ASPECT_RATIO, 1, 1);
        return type;
    }

    private static void SetAttributeRatio(IMFAttributes attributes, Guid key, int numerator, int denominator)
    {
        var value = ((ulong)(uint)numerator << 32) | (uint)denominator;
        attributes.SetUINT64(key, value);
    }

    private static int BitrateFor(int width, int height, int fps)
    {
        var pixelsPerSecond = width * height * fps;
        return Math.Clamp(pixelsPerSecond / 4, 2_000_000, 12_000_000);
    }

    private static void ThrowIfFailed(int hr, string label)
    {
        if (hr < 0) Marshal.ThrowExceptionForHR(hr, new IntPtr(-1));
    }

    [DllImport("mfplat.dll")]
    private static extern int MFStartup(int version, int flags);

    [DllImport("mfplat.dll")]
    private static extern int MFShutdown();

    [DllImport("mfplat.dll")]
    private static extern int MFCreateMediaType(out IMFMediaType mediaType);

    [DllImport("mfplat.dll")]
    private static extern int MFCreateMemoryBuffer(int maxLength, out IMFMediaBuffer buffer);

    [DllImport("mfplat.dll")]
    private static extern int MFCreateSample(out IMFSample sample);

    [DllImport("mfreadwrite.dll", CharSet = CharSet.Unicode)]
    private static extern int MFCreateSinkWriterFromURL(string outputUrl, nint byteStream, IMFAttributes? attributes, out IMFSinkWriter sinkWriter);

    [ComImport]
    [Guid("2cd2d921-c447-44a7-a13c-4adabfc247e3")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IMFAttributes
    {
        void GetItem(Guid guidKey, nint pValue);
        void GetItemType(Guid guidKey, out int pType);
        void CompareItem(Guid guidKey, nint value, out bool result);
        void Compare(IMFAttributes theirs, int matchType, out bool result);
        void GetUINT32(Guid guidKey, out int value);
        void GetUINT64(Guid guidKey, out ulong value);
        void GetDouble(Guid guidKey, out double value);
        void GetGUID(Guid guidKey, out Guid value);
        void GetStringLength(Guid guidKey, out int length);
        void GetString(Guid guidKey, char[] value, int size, out int length);
        void GetAllocatedString(Guid guidKey, out nint value, out int length);
        void GetBlobSize(Guid guidKey, out int size);
        void GetBlob(Guid guidKey, byte[] buffer, int bufferSize, out int blobSize);
        void GetAllocatedBlob(Guid guidKey, out nint buffer, out int size);
        void GetUnknown(Guid guidKey, Guid riid, out nint unknown);
        void SetItem(Guid guidKey, nint value);
        void DeleteItem(Guid guidKey);
        void DeleteAllItems();
        void SetUINT32(Guid guidKey, int value);
        void SetUINT64(Guid guidKey, ulong value);
        void SetDouble(Guid guidKey, double value);
        void SetGUID(Guid guidKey, Guid value);
        void SetString(Guid guidKey, [MarshalAs(UnmanagedType.LPWStr)] string value);
        void SetBlob(Guid guidKey, byte[] buffer, int bufferSize);
        void SetUnknown(Guid guidKey, [MarshalAs(UnmanagedType.IUnknown)] object unknown);
        void LockStore();
        void UnlockStore();
        void GetCount(out int count);
        void GetItemByIndex(int index, out Guid guidKey, nint value);
        void CopyAllItems(IMFAttributes dest);
    }

    [ComImport]
    [Guid("44ae0fa8-ea31-4109-8d2e-4cae4997c555")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IMFMediaType : IMFAttributes;

    [ComImport]
    [Guid("3137f1cd-fe5e-4805-a5d8-fb477448cb3d")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IMFSinkWriter
    {
        [PreserveSig] int AddStream(IMFMediaType targetMediaType, out uint streamIndex);
        [PreserveSig] int SetInputMediaType(uint streamIndex, IMFMediaType inputMediaType, IMFAttributes? encodingParameters);
        [PreserveSig] int BeginWriting();
        [PreserveSig] int WriteSample(uint streamIndex, IMFSample sample);
        [PreserveSig] int SendStreamTick(uint streamIndex, long timestamp);
        [PreserveSig] int PlaceMarker(uint streamIndex, nint context);
        [PreserveSig] int NotifyEndOfSegment(uint streamIndex);
        void Flush(uint streamIndex);
        [PreserveSig] int Finalize_();
        void GetServiceForStream(uint streamIndex, Guid service, Guid riid, out nint ppvObject);
        void GetStatistics(uint streamIndex, nint statistics);
    }

    [ComImport]
    [Guid("c40a00f2-b93a-4d80-ae8c-5a1c634f58e4")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IMFSample
    {
        void GetItem(Guid guidKey, nint pValue);
        void GetItemType(Guid guidKey, out int pType);
        void CompareItem(Guid guidKey, nint value, out bool result);
        void Compare(IMFAttributes theirs, int matchType, out bool result);
        void GetUINT32(Guid guidKey, out int value);
        void GetUINT64(Guid guidKey, out ulong value);
        void GetDouble(Guid guidKey, out double value);
        void GetGUID(Guid guidKey, out Guid value);
        void GetStringLength(Guid guidKey, out int length);
        void GetString(Guid guidKey, char[] value, int size, out int length);
        void GetAllocatedString(Guid guidKey, out nint value, out int length);
        void GetBlobSize(Guid guidKey, out int size);
        void GetBlob(Guid guidKey, byte[] buffer, int bufferSize, out int blobSize);
        void GetAllocatedBlob(Guid guidKey, out nint buffer, out int size);
        void GetUnknown(Guid guidKey, Guid riid, out nint unknown);
        void SetItem(Guid guidKey, nint value);
        void DeleteItem(Guid guidKey);
        void DeleteAllItems();
        void SetUINT32(Guid guidKey, int value);
        void SetUINT64(Guid guidKey, ulong value);
        void SetDouble(Guid guidKey, double value);
        void SetGUID(Guid guidKey, Guid value);
        void SetString(Guid guidKey, [MarshalAs(UnmanagedType.LPWStr)] string value);
        void SetBlob(Guid guidKey, byte[] buffer, int bufferSize);
        void SetUnknown(Guid guidKey, [MarshalAs(UnmanagedType.IUnknown)] object unknown);
        void LockStore();
        void UnlockStore();
        void GetCount(out int count);
        void GetItemByIndex(int index, out Guid guidKey, nint value);
        void CopyAllItems(IMFAttributes dest);
        void GetSampleFlags(out int flags);
        void SetSampleFlags(int flags);
        void GetSampleTime(out long time);
        [PreserveSig] int SetSampleTime(long time);
        void GetSampleDuration(out long duration);
        [PreserveSig] int SetSampleDuration(long duration);
        void GetBufferCount(out int bufferCount);
        void GetBufferByIndex(int index, out IMFMediaBuffer buffer);
        void ConvertToContiguousBuffer(out IMFMediaBuffer buffer);
        [PreserveSig] int AddBuffer(IMFMediaBuffer buffer);
        void RemoveBufferByIndex(int index);
        void RemoveAllBuffers();
        void GetTotalLength(out int totalLength);
        void CopyToBuffer(IMFMediaBuffer buffer);
    }

    [ComImport]
    [Guid("045fa593-8799-42b8-bc8d-8968c6453507")]
    [InterfaceType(ComInterfaceType.InterfaceIsIUnknown)]
    private interface IMFMediaBuffer
    {
        [PreserveSig] int Lock(out nint buffer, out int maxLength, out int currentLength);
        [PreserveSig] int Unlock();
        void GetCurrentLength(out int currentLength);
        [PreserveSig] int SetCurrentLength(int currentLength);
        void GetMaxLength(out int maxLength);
    }
}
