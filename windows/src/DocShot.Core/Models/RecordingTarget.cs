using DocShot.Core.Primitives;

namespace DocShot.Core.Models;

/// <summary>
/// What one recording session captures. Resolved once, before the stream starts, and stays
/// immutable for the lifetime of that session - recording never re-derives its bounds from a
/// moving selection.
/// </summary>
public abstract record RecordingTarget
{
    /// <summary>
    /// A single application window, identified by the HWND window discovery reported.
    /// </summary>
    /// <remarks>
    /// <paramref name="BoundsInScreen"/> is the bounds observed at selection time, used for the
    /// confirmation UI and as a fallback size. The live window must be re-resolved immediately
    /// before capture (matching the macOS live-<c>SCWindow</c>-resolution discipline), so a window
    /// that moved or closed in between is caught rather than recorded at stale bounds.
    /// </remarks>
    public sealed record Window(nint Id, RectD BoundsInScreen) : RecordingTarget;

    /// <summary>
    /// A rectangle lying wholly within one display.
    /// </summary>
    /// <remarks>
    /// <paramref name="RectInDisplay"/> is relative to that display's top-left origin.
    /// <paramref name="OutputSize"/> is the exact pixel size the recording must have; the odd-
    /// dimension-preserving decision the macOS R1 milestone made (never round, ever) carries over
    /// unchanged - see <c>docs/RECORDING_ARCHITECTURE.md</c> in the macOS project.
    /// </remarks>
    public sealed record Region(uint DisplayId, RectD RectInDisplay, SizeD OutputSize) : RecordingTarget;

    private RecordingTarget() { }
}

/// <summary>
/// Why a selection cannot become a recording target. Every case is user-visible: the app explains
/// the limitation instead of silently cropping, stretching, or recording something other than
/// what was selected.
/// </summary>
public abstract record RecordingTargetRejection
{
    /// <summary>The region overlaps more than one display. Multi-display recording is deferred.</summary>
    public sealed record SpansMultipleDisplays : RecordingTargetRejection;

    /// <summary>The region is not wholly contained by any single display.</summary>
    public sealed record NoContainingDisplay : RecordingTargetRejection;

    /// <summary>The region is smaller than the encoder can usefully record.</summary>
    public sealed record TooSmall : RecordingTargetRejection;

    /// <summary>The region's geometry is not finite or has no area.</summary>
    public sealed record InvalidGeometry : RecordingTargetRejection;

    /// <summary>The selected window no longer exists, or is no longer capturable.</summary>
    public sealed record WindowUnavailable : RecordingTargetRejection;

    private RecordingTargetRejection() { }

    public const double MinimumSideInPoints = 20;

    public string Message => this switch
    {
        SpansMultipleDisplays =>
            "DocShot records a region on one display at a time. Select a region that stays within a single display.",
        NoContainingDisplay =>
            "The selected region must lie entirely within one display.",
        TooSmall =>
            $"The selected region is too small to record. Select at least {(int)MinimumSideInPoints} × {(int)MinimumSideInPoints} points.",
        InvalidGeometry =>
            "The selected region does not describe a valid rectangle.",
        WindowUnavailable =>
            "That window is no longer available to record. Select it again.",
        _ => "The selection could not be recorded."
    };
}
