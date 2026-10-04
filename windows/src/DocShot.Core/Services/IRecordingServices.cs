using DocShot.Core.Models;

namespace DocShot.Core.Services;

/// <summary>
/// One recording session. The <c>DocShot.Platform</c> implementation owns exactly one
/// <c>Windows.Graphics.Capture</c> frame pool and one Media Foundation sink writer per session -
/// see the recording-capture and MP4-encode rows in the platform mapping table.
/// </summary>
public interface IRecordingSession
{
    Task Start(RecordingTarget target, RecordingOptions options, Uri outputUrl, CancellationToken cancellationToken = default);
    Task<TemporaryRecording> Stop(CancellationToken cancellationToken = default);
    Task Cancel();
}

public interface IRecordingSessionFactory
{
    IRecordingSession MakeSession();
}

/// <summary>
/// Owns DocShot's private temporary-recordings directory. The Windows equivalent of
/// <c>%TEMP%\DocShot-Recordings</c>, swept at launch and on every terminal path - see
/// <c>docs/WINDOWS_PORT_PLAN.md</c> §2.
/// </summary>
public interface ITemporaryRecordingStore
{
    Uri MakeMp4Url();
    void RemoveIfPresent(Uri url);
    void Move(Uri source, Uri destination);
}

/// <summary>Presents a native Save dialog (<c>SaveFileDialog</c>) for a finished recording.</summary>
public interface IMovieSaving
{
    Task<SaveResult> Save(TemporaryRecording recording);
}

/// <summary>
/// Converts a finished MP4 to the GIF profile in <see cref="GifProfile"/>. Consumes a finished
/// <see cref="TemporaryRecording"/>, never a live stream.
/// </summary>
public interface IGifExporting
{
    Task<TemporaryRecording> ExportGif(TemporaryRecording recording, GifProfile profile, CancellationToken cancellationToken = default);
}
