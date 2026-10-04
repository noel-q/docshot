namespace DocShot.Core.Models;

/// <summary>
/// Why a recording could not start, continue, finish, or be saved. Distinguished so the UI can
/// say something actionable and so cleanup can tell "no stream ever existed" from "a stream
/// produced a file that must now be deleted".
/// </summary>
public abstract record RecordingFailure
{
    /// <summary>No native OS permission gate exists for the Windows capture APIs currently planned
    /// (see <c>docs/WINDOWS_PORT_PLAN.md</c>); retained for parity in case a picker-gated fallback
    /// path needs it.</summary>
    public sealed record PermissionDenied : RecordingFailure;

    public sealed record InvalidTarget(RecordingTargetRejection Rejection) : RecordingFailure;

    /// <summary>The stream could not be constructed or started. No usable media exists.</summary>
    public sealed record StreamStart(string Detail) : RecordingFailure;

    /// <summary>A running stream stopped on its own: a capture-item-closed event, display change, etc.</summary>
    public sealed record StreamInterrupted(string Detail) : RecordingFailure;

    /// <summary>Stopping failed, so the file cannot be trusted.</summary>
    public sealed record StopFailed(string Detail) : RecordingFailure;

    /// <summary>The writer failed, produced no frames, or produced an asset that does not validate.</summary>
    public sealed record Writer(string Detail) : RecordingFailure;

    /// <summary>The finished recording could not be written to the user's chosen destination. The
    /// temporary file is retained so the user can retry or discard.</summary>
    public sealed record OutputSave(string Detail) : RecordingFailure;

    private RecordingFailure() { }

    public string Message => this switch
    {
        PermissionDenied =>
            "DocShot needs screen-capture access to record. Grant access, then try again.",
        InvalidTarget t => t.Rejection.Message,
        StreamStart t => $"Recording could not start: {t.Detail}",
        StreamInterrupted t => $"Recording stopped unexpectedly: {t.Detail}",
        StopFailed t => $"Recording could not be finished: {t.Detail}",
        Writer t => $"The recording could not be written: {t.Detail}",
        OutputSave t => $"The recording could not be saved: {t.Detail}",
        _ => "Unknown recording failure."
    };

    /// <summary>True when the failure left no media worth keeping, so cleanup is unconditional.</summary>
    public bool DiscardsTemporaryMedia => this is not OutputSave;
}
