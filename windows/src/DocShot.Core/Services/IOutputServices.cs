namespace DocShot.Core.Services;

/// <summary>Writes a flattened PNG to the system clipboard.</summary>
/// <remarks>
/// The Windows implementation (in <c>DocShot.Platform</c>) must register and write the
/// <c>"PNG"</c> clipboard format explicitly - there is no built-in constant for it the way
/// <c>NSPasteboard.PasteboardType.png</c> exists on macOS - and should also offer a CF_DIB/
/// CF_BITMAP fallback for consumers that only read legacy bitmap formats. See the clipboard row
/// in <c>docs/WINDOWS_PORT_PLAN.md</c>'s platform mapping table.
/// </remarks>
public interface IPasteboardWriter
{
    bool WritePng(byte[] data);
}

/// <summary>Writes bytes to a destination the user chose explicitly (never a silently-chosen path).</summary>
public interface IFileWriter
{
    void Write(byte[] data, Uri destination);
}
