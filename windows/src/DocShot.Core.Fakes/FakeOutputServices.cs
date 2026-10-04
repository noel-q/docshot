using DocShot.Core.Services;

namespace DocShot.Core.Fakes;

/// <summary>
/// Records the last PNG written instead of touching the real Windows clipboard, so App's "Copy"
/// button can be tested (including its success/failure UI state) without a live clipboard.
/// </summary>
public sealed class FakePasteboardWriter : IPasteboardWriter
{
    public byte[]? LastWritten { get; private set; }
    public bool AlwaysFail { get; set; }

    public bool WritePng(byte[] data)
    {
        if (AlwaysFail) return false;
        LastWritten = data;
        return true;
    }
}

/// <summary>Writes to a real file under a fakes-only scratch directory - never the user's actual chosen destination.</summary>
public sealed class FakeFileWriter : IFileWriter
{
    public void Write(byte[] data, Uri destination)
    {
        var path = destination.IsAbsoluteUri ? destination.LocalPath : destination.ToString();
        var directory = Path.GetDirectoryName(path);
        if (!string.IsNullOrEmpty(directory)) Directory.CreateDirectory(directory);
        File.WriteAllBytes(path, data);
    }
}
