using DocShot.Core.Models;
using DocShot.Core.Primitives;
using DocShot.Core.Services;

namespace DocShot.Core.Fakes;

/// <summary>
/// Simulates one recording session entirely in memory: no WGC frame pool, no Media Foundation
/// sink writer, no real file. <see cref="Stop"/> returns a <see cref="TemporaryRecording"/> whose
/// duration is real wall-clock time between <see cref="Start"/> and <see cref="Stop"/>, so App's
/// HUD/timer UI has something genuine to display. The returned <c>Url</c> points at a zero-byte
/// placeholder file so anything that checks <c>File.Exists</c> doesn't immediately fail - it is
/// not playable media, and nothing here pretends otherwise.
/// </summary>
public sealed class FakeRecordingSession : IRecordingSession
{
    private DateTimeOffset _startedAt;
    private RecordingOptions? _options;
    private RecordingTarget? _target;
    private Uri? _outputUrl;
    private bool _cancelled;

    public Task Start(RecordingTarget target, RecordingOptions options, Uri outputUrl, CancellationToken cancellationToken = default)
    {
        _target = target;
        _options = options;
        _outputUrl = outputUrl;
        _startedAt = DateTimeOffset.UtcNow;
        _cancelled = false;

        var path = outputUrl.IsAbsoluteUri ? outputUrl.LocalPath : outputUrl.ToString();
        try
        {
            var directory = Path.GetDirectoryName(path);
            if (!string.IsNullOrEmpty(directory)) Directory.CreateDirectory(directory);
            File.WriteAllBytes(path, []);
        }
        catch
        {
            // Best-effort only - this is a fake for UI wiring, not a real recorder. A caller that
            // needs to test genuine filesystem failure paths should not be relying on this class.
        }

        return Task.CompletedTask;
    }

    public Task<TemporaryRecording> Stop(CancellationToken cancellationToken = default)
    {
        if (_cancelled || _outputUrl is null || _options is null)
        {
            throw new InvalidOperationException("FakeRecordingSession.Stop called without a prior Start.");
        }

        var duration = Math.Max(0.05, (DateTimeOffset.UtcNow - _startedAt).TotalSeconds);
        var pixelSize = _target switch
        {
            RecordingTarget.Region region => region.OutputSize,
            RecordingTarget.Window window => window.BoundsInScreen.Size,
            _ => new SizeD(1280, 720),
        };

        return Task.FromResult(new TemporaryRecording(
            _outputUrl,
            duration,
            pixelSize,
            !_options.IsVideoOnly,
            DateTimeOffset.UtcNow));
    }

    public Task Cancel()
    {
        _cancelled = true;
        if (_outputUrl is not null)
        {
            var path = _outputUrl.IsAbsoluteUri ? _outputUrl.LocalPath : _outputUrl.ToString();
            try { if (File.Exists(path)) File.Delete(path); } catch { /* best-effort */ }
        }
        return Task.CompletedTask;
    }
}

public sealed class FakeRecordingSessionFactory : IRecordingSessionFactory
{
    public IRecordingSession MakeSession() => new FakeRecordingSession();
}

/// <summary>In-memory stand-in for %TEMP%\DocShot-Recordings - a real temp directory, but never swept against other processes' files.</summary>
public sealed class FakeTemporaryRecordingStore : ITemporaryRecordingStore
{
    private readonly string _root;

    public FakeTemporaryRecordingStore(string? root = null)
    {
        _root = root ?? Path.Combine(Path.GetTempPath(), "DocShot-Fakes");
        Directory.CreateDirectory(_root);
    }

    public Uri MakeMp4Url() => new(Path.Combine(_root, $"{Guid.NewGuid():N}.mp4"));

    public void RemoveIfPresent(Uri url)
    {
        var path = url.IsAbsoluteUri ? url.LocalPath : url.ToString();
        if (File.Exists(path)) File.Delete(path);
    }

    public void Move(Uri source, Uri destination)
    {
        var from = source.IsAbsoluteUri ? source.LocalPath : source.ToString();
        var to = destination.IsAbsoluteUri ? destination.LocalPath : destination.ToString();
        var directory = Path.GetDirectoryName(to);
        if (!string.IsNullOrEmpty(directory)) Directory.CreateDirectory(directory);
        File.Move(from, to, overwrite: true);
    }
}

/// <summary>
/// Simulates the native Save dialog by always saving to a fixed path under the fake store's root,
/// never actually prompting. Set <see cref="AlwaysCancel"/> to exercise the cancel path in App's
/// UI without a human clicking Cancel on a real dialog.
/// </summary>
public sealed class FakeMovieSaving : IMovieSaving
{
    public bool AlwaysCancel { get; set; }
    public bool AlwaysFail { get; set; }

    public Task<SaveResult> Save(TemporaryRecording recording)
    {
        if (AlwaysCancel) return Task.FromResult<SaveResult>(new SaveResult.Cancelled());
        if (AlwaysFail) return Task.FromResult<SaveResult>(new SaveResult.Failed("Simulated save failure."));

        var destination = Path.Combine(Path.GetTempPath(), "DocShot-Fakes", "Saved", $"{Guid.NewGuid():N}.mp4");
        var directory = Path.GetDirectoryName(destination);
        if (!string.IsNullOrEmpty(directory)) Directory.CreateDirectory(directory);
        var sourcePath = recording.Url.IsAbsoluteUri ? recording.Url.LocalPath : recording.Url.ToString();
        try { if (File.Exists(sourcePath)) File.Copy(sourcePath, destination, overwrite: true); else File.WriteAllBytes(destination, []); }
        catch { /* best-effort - see FakeRecordingSession */ }

        return Task.FromResult<SaveResult>(new SaveResult.Saved(new Uri(destination)));
    }
}

/// <summary>
/// Relabels a finished recording as a "GIF" without touching the guardrails a real encoder would
/// enforce (duration/size/dimensions/fps) - this exists purely so App can wire up GIF export UI,
/// not to validate GifProfile.DocShotDefault's limits. See windows/docs/PARITY_CHECKLIST.md §1.
/// </summary>
public sealed class FakeGifExporting : IGifExporting
{
    public Task<TemporaryRecording> ExportGif(TemporaryRecording recording, GifProfile profile, CancellationToken cancellationToken = default)
    {
        var gifUrl = new Uri(Path.ChangeExtension(recording.Url.IsAbsoluteUri ? recording.Url.LocalPath : recording.Url.ToString(), ".gif"));
        return Task.FromResult(recording with { Url = gifUrl, HasAudio = false });
    }
}
