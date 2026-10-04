namespace DocShot.Core.Models;

/// <summary>
/// Which audio sources a recording captures.
/// </summary>
/// <remarks>
/// On Windows there is no single API that captures video and audio on one stream/one clock the
/// way ScreenCaptureKit does. <see cref="System"/> and <see cref="Microphone"/> both require a
/// parallel WASAPI capture client muxed into the same Media Foundation sink writer - see the
/// platform mapping table and risk spike W0-3 in <c>docs/WINDOWS_PORT_PLAN.md</c>. This type
/// itself does not change shape for that; the difference lives entirely in
/// <c>DocShot.Platform</c>'s implementation.
/// </remarks>
public abstract record RecordingAudioMode
{
    public sealed record None : RecordingAudioMode;
    public sealed record System : RecordingAudioMode;
    public sealed record Microphone(string? DeviceId) : RecordingAudioMode;
    public sealed record SystemAndMicrophone(string? DeviceId) : RecordingAudioMode;

    private RecordingAudioMode() { }

    public static readonly RecordingAudioMode NoAudio = new None();
}

/// <summary>How a recording is configured, decided before the stream starts.</summary>
public sealed record RecordingOptions(
    RecordingAudioMode Audio,
    bool ShowsCursor,
    int MaximumFrameRate)
{
    public const int DefaultMaximumFrameRate = 30;

    /// <summary>The only configuration the video-only milestone produces.</summary>
    public static RecordingOptions VideoOnly(bool showsCursor, int maximumFrameRate = DefaultMaximumFrameRate) =>
        new(RecordingAudioMode.NoAudio, showsCursor, maximumFrameRate);

    public bool IsVideoOnly => Audio is RecordingAudioMode.None;

    /// <summary>Whether the stream captures system audio at all.</summary>
    public bool CapturesSystemAudio => Audio is RecordingAudioMode.System or RecordingAudioMode.SystemAndMicrophone;

    /// <summary>
    /// Whether DocShot's own process audio must be kept out of the system-audio track. System
    /// audio is captured globally, for a window target as much as a display one, so without this
    /// DocShot's own alert sounds would be recorded into the user's clip.
    /// </summary>
    public bool ExcludesOwnProcessAudio => CapturesSystemAudio;
}

/// <summary>
/// The GIF export profile. GIF is a post-stop conversion of a completed MP4; these limits are
/// checked before presenting any user-facing Save panel.
/// </summary>
public sealed record GifProfile(
    double MaximumDuration,
    int FramesPerSecond,
    int MaximumLongEdge,
    long MaximumEncodedBytes)
{
    /// <summary>Owner-approved profile carried over from macOS R4: 15 seconds, 10 fps, 960 px, 10 MB.</summary>
    public static readonly GifProfile DocShotDefault = new(
        MaximumDuration: 15,
        FramesPerSecond: 10,
        MaximumLongEdge: 960,
        MaximumEncodedBytes: 10_000_000);

    public bool Supports(TemporaryRecording recording) =>
        recording.IsPlayable && recording.Duration <= MaximumDuration;
}
