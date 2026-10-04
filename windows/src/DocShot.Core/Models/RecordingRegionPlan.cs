using DocShot.Core.Primitives;

namespace DocShot.Core.Models;

/// <summary>
/// Decides whether a selected region can be recorded, and how it maps onto one display's capture
/// source rectangle.
/// </summary>
/// <remarks>
/// A region records only when it lies wholly within a single display. Anything else is rejected
/// with a reason the UI shows, because the alternatives - cropping to one display or stretching a
/// composite - would record something the user did not select. The output pixel size is
/// <c>points x that display's scale</c>, rounded to the nearest whole pixel and otherwise
/// preserved exactly; odd dimensions are kept, matching the macOS R1 decision not to round them
/// away.
/// </remarks>
public abstract record RecordingRegionPlan
{
    public sealed record Ok(uint DisplayId, RectD SourceRectInPoints, SizeD OutputPixelSize) : RecordingRegionPlan;
    public sealed record Rejected(RecordingTargetRejection Reason) : RecordingRegionPlan;

    private RecordingRegionPlan() { }

    /// <summary>Smallest region side accepted, in points.</summary>
    public const double MinimumSideInPoints = 16;

    /// <param name="rect">The selection in global screen space (origin top-left, Y down).</param>
    /// <param name="displays">Every connected display, at its own scale.</param>
    public static RecordingRegionPlan Make(RectD rect, IReadOnlyList<DisplayDescriptor> displays)
    {
        var normalized = DisplayGeometry.NormalizeRect(rect);

        if (!double.IsFinite(normalized.X) || !double.IsFinite(normalized.Y) ||
            !double.IsFinite(normalized.Width) || !double.IsFinite(normalized.Height) ||
            normalized.Width <= 0 || normalized.Height <= 0)
        {
            return new Rejected(new RecordingTargetRejection.InvalidGeometry());
        }

        if (normalized.Width < MinimumSideInPoints || normalized.Height < MinimumSideInPoints)
        {
            return new Rejected(new RecordingTargetRejection.TooSmall());
        }

        var usableDisplays = displays.Where(d => d.IsValid).ToList();

        // Mirrored displays can share a frame. Lowest display ID wins so the plan is deterministic.
        var containing = usableDisplays
            .Where(d => d.FrameInScreen.Contains(normalized))
            .OrderBy(d => d.DisplayId)
            .ToList();

        if (containing.Count == 0)
        {
            var overlapping = usableDisplays.Where(d => d.FrameInScreen.Intersects(normalized)).ToList();
            return new Rejected(overlapping.Count > 1
                ? new RecordingTargetRejection.SpansMultipleDisplays()
                : new RecordingTargetRejection.NoContainingDisplay());
        }

        var display = containing[0];
        var sourceRect = new RectD(
            normalized.X - display.FrameInScreen.X,
            normalized.Y - display.FrameInScreen.Y,
            normalized.Width,
            normalized.Height);

        var pixelWidth = Math.Round(normalized.Width * display.Scale);
        var pixelHeight = Math.Round(normalized.Height * display.Scale);

        if (pixelWidth < 1 || pixelHeight < 1)
        {
            return new Rejected(new RecordingTargetRejection.TooSmall());
        }

        return new Ok(display.DisplayId, sourceRect, new SizeD(pixelWidth, pixelHeight));
    }

    /// <summary>The recording target this plan describes, or <c>null</c> when the selection was rejected.</summary>
    public RecordingTarget? Target => this is Ok ok
        ? new RecordingTarget.Region(ok.DisplayId, ok.SourceRectInPoints, ok.OutputPixelSize)
        : null;

    public RecordingTargetRejection? RejectionReason => this is Rejected r ? r.Reason : null;
}
