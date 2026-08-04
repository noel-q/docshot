namespace DocShot.Core.Models;

/// <summary>
/// Which capture actions the app offers, given what the two coordinators are currently doing.
/// </summary>
/// <remarks>
/// Only one DocShot capture activity may exist at a time. Rather than teaching either coordinator
/// about the other, the app-level menu and the global hotkey consult this pure policy, so
/// screenshot capture keeps working exactly as it did before recording existed.
/// </remarks>
public sealed record CaptureActivityPolicy(
    bool AllowsScreenshotCapture,
    bool AllowsRecordingCapture,
    bool AllowsStopRecording)
{
    public static CaptureActivityPolicy Evaluate(CaptureState captureState, RecordingState recordingState)
    {
        // Screenshot capture owns its own state guards (including the editor discard prompt); the
        // only new rule is that it may not begin while a recording activity is live.
        var screenshotAllowed = !recordingState.IsActive;

        var screenshotIdle = captureState is CaptureState.Idle or CaptureState.Cancelled;

        var stopAllowed = recordingState is RecordingState.Starting or RecordingState.Recording;

        return new CaptureActivityPolicy(
            AllowsScreenshotCapture: screenshotAllowed,
            AllowsRecordingCapture: screenshotIdle && recordingState is RecordingState.Idle,
            AllowsStopRecording: stopAllowed);
    }
}
