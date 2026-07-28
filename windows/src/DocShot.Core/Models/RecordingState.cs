namespace DocShot.Core.Models;

/// <summary>
/// Identifies one recording session. Bumped whenever a session ends by any route, so a callback
/// that arrives after the user cancelled, stopped, discarded, or quit can be recognised as stale
/// and dropped.
/// </summary>
public readonly record struct RecordingSessionId(int RawValue)
{
    public static readonly RecordingSessionId Initial = new(1);

    public RecordingSessionId Next() => new(RawValue + 1);
}

/// <summary>The outcome of an explicit Save action - a direct port of the macOS <c>OutputService.SaveResult</c>.</summary>
public abstract record SaveResult
{
    public sealed record Saved(Uri Url) : SaveResult;
    public sealed record Cancelled : SaveResult;
    public sealed record Failed(string Message) : SaveResult;

    private SaveResult() { }
}

/// <summary>
/// Every state the recording subsystem can occupy.
/// </summary>
/// <remarks>
/// <see cref="ExportingGif"/> belongs to a later GIF-export milestone and is retained here so the
/// state type is the documented one rather than a temporary subset, matching the macOS decision:
/// no early milestone emits an event that reaches it, and a reducer test should assert that stays
/// true, the same way <c>RecordingStateReducerTests</c> does on macOS.
/// </remarks>
public abstract record RecordingState
{
    public sealed record Idle : RecordingState;
    public sealed record PermissionRequired : RecordingState;

    /// <summary>Preparing to select: preflighting permission, then discovering windows and presenting
    /// overlays. Overlays exist only after permission has been resolved as granted.</summary>
    public sealed record Selecting : RecordingState;

    public sealed record AwaitingConfirmation(RecordingTarget Target) : RecordingState;
    public sealed record Starting(RecordingTarget Target) : RecordingState;
    public sealed record Recording(RecordingTarget Target, DateTimeOffset StartedAt) : RecordingState;
    public sealed record Stopping : RecordingState;
    public sealed record AwaitingOutput(TemporaryRecording Recording) : RecordingState;
    public sealed record ExportingGif(TemporaryRecording Recording) : RecordingState;
    public sealed record Failed(RecordingFailure Failure) : RecordingState;

    private RecordingState() { }

    public static readonly RecordingState IdleState = new Idle();

    /// <summary>True while a capture activity owns the screen, so the app can refuse to start a second one.</summary>
    public bool IsActive => this is not Idle;
}

/// <summary>Everything that can happen to a recording. The reducer is the only place that interprets these.</summary>
public abstract record RecordingEvent
{
    public sealed record RequestRecording : RecordingEvent;
    public sealed record PermissionResolved(bool Granted, RecordingSessionId Session) : RecordingEvent;
    public sealed record TargetSelected(RecordingTarget Target, RecordingSessionId Session) : RecordingEvent;
    public sealed record TargetRejected(RecordingTargetRejection Rejection, RecordingSessionId Session) : RecordingEvent;
    public sealed record SelectionCancelled : RecordingEvent;
    public sealed record ConfirmRecord : RecordingEvent;
    public sealed record ConfirmCancel : RecordingEvent;
    public sealed record SessionStarted(DateTimeOffset At, RecordingSessionId Session) : RecordingEvent;
    public sealed record SessionStartFailed(RecordingFailure Failure, Uri? Url, RecordingSessionId Session) : RecordingEvent;
    public sealed record StopRequested : RecordingEvent;
    public sealed record SessionStopped(TemporaryRecording Recording, RecordingSessionId Session) : RecordingEvent;
    public sealed record SessionStopFailed(RecordingFailure Failure, Uri? Url, RecordingSessionId Session) : RecordingEvent;
    public sealed record StreamFailed(RecordingFailure Failure, Uri? Url, RecordingSessionId Session) : RecordingEvent;
    public sealed record SaveRequested : RecordingEvent;
    public sealed record SaveCompleted(SaveResult Result) : RecordingEvent;
    public sealed record DiscardRequested : RecordingEvent;
    public sealed record FailureAcknowledged : RecordingEvent;
    public sealed record AppWillTerminate : RecordingEvent;

    private RecordingEvent() { }

    /// <summary>The session an event belongs to, for events that can arrive late.</summary>
    public RecordingSessionId? Session => this switch
    {
        PermissionResolved e => e.Session,
        TargetSelected e => e.Session,
        TargetRejected e => e.Session,
        SessionStarted e => e.Session,
        SessionStartFailed e => e.Session,
        SessionStopped e => e.Session,
        SessionStopFailed e => e.Session,
        StreamFailed e => e.Session,
        _ => null
    };

    /// <summary>Temporary media this event reports, whether or not the event is still current. A late
    /// event is dropped, but anything it created is still deleted.</summary>
    public Uri? TemporaryUrl => this switch
    {
        SessionStopped e => e.Recording.Url,
        SessionStartFailed e => e.Url,
        SessionStopFailed e => e.Url,
        StreamFailed e => e.Url,
        _ => null
    };
}

/// <summary>
/// Work the coordinator performs on the reducer's instruction. Effects are pure data so the whole
/// transition table - including every cleanup path - is assertable without any live capture
/// session or window.
/// </summary>
public abstract record RecordingEffect
{
    /// <summary>Check capture access. Always precedes <see cref="BeginSelection"/>; no overlay exists yet.</summary>
    public sealed record PreflightPermission(RecordingSessionId Session) : RecordingEffect;
    public sealed record PresentPermissionRequired : RecordingEffect;

    /// <summary>Discover eligible windows and present the selection overlays.</summary>
    public sealed record BeginSelection(RecordingSessionId Session) : RecordingEffect;
    public sealed record CloseOverlays : RecordingEffect;
    public sealed record PresentTargetRejection(RecordingTargetRejection Rejection) : RecordingEffect;
    public sealed record StartSession(RecordingTarget Target, RecordingSessionId Session) : RecordingEffect;
    public sealed record StopSession(RecordingSessionId Session) : RecordingEffect;
    public sealed record CancelSession(RecordingSessionId Session) : RecordingEffect;
    public sealed record RemoveTemporary(Uri Url) : RecordingEffect;

    /// <summary>Ask the user to Save or Discard. Never saves anything on its own.</summary>
    public sealed record PresentOutputChoice(TemporaryRecording Recording) : RecordingEffect;
    public sealed record PresentSavePanel(TemporaryRecording Recording) : RecordingEffect;
    public sealed record PresentFailure(RecordingFailure Failure) : RecordingEffect;

    /// <summary>A capture activity is already running; the request was refused.</summary>
    public sealed record RejectDuplicateRequest : RecordingEffect;

    private RecordingEffect() { }
}
