using DocShot.Core.Services;

namespace DocShot.Platform;

public sealed class TemporaryRecordingStore : ITemporaryRecordingStore
{
    private readonly string _root;

    public TemporaryRecordingStore(string? root = null)
    {
        _root = root ?? Path.Combine(Path.GetTempPath(), "DocShot-Recordings");
        Directory.CreateDirectory(_root);
    }

    public Uri MakeMp4Url() => new(Path.Combine(_root, $"{Guid.NewGuid():N}.mp4"));

    public void RemoveIfPresent(Uri url)
    {
        var path = LocalPath(url);
        if (File.Exists(path)) File.Delete(path);
    }

    public void Move(Uri source, Uri destination)
    {
        var from = LocalPath(source);
        var to = LocalPath(destination);
        var directory = Path.GetDirectoryName(to);
        if (!string.IsNullOrEmpty(directory)) Directory.CreateDirectory(directory);
        File.Move(from, to, overwrite: true);
    }

    private static string LocalPath(Uri url) => url.IsAbsoluteUri ? url.LocalPath : url.ToString();
}
