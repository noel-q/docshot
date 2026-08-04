namespace DocShot.Core.Models;

/// <summary>A half-open time range, in seconds: <c>[Start, Start + Duration)</c>.</summary>
/// <remarks>
/// Seconds rather than a media-timeline type, so the whole project model stays pure and portable.
/// Conversion to a concrete timeline unit happens once, at the export boundary - see the (not yet
/// ported) export service, which will be Media Foundation-based and lives in
/// <c>DocShot.Platform</c>.
/// </remarks>
public readonly record struct VideoTimeRange(double Start, double Duration)
{
    /// <summary>
    /// The shortest range the editor will create. Anything below this is a mis-drag rather than an
    /// intended edit, and a zero-length segment would export as nothing at all.
    /// </summary>
    public const double MinimumDuration = 0.05;

    public static VideoTimeRange Between(double start, double end) => new(start, end - start);

    public double End => Start + Duration;

    /// <summary>Finite, non-negative, and long enough to be a deliberate edit.</summary>
    public bool IsValid =>
        double.IsFinite(Start) && double.IsFinite(Duration) && Start >= 0 && Duration >= MinimumDuration;

    /// <summary>
    /// Finite and non-negative, but allowed to be shorter than <see cref="MinimumDuration"/>.
    /// Derived ranges - an annotation clipped by a split, for instance - can legitimately end up
    /// very short. Only ranges the user asks for directly must clear <see cref="IsValid"/>.
    /// </summary>
    public bool IsWellFormed =>
        double.IsFinite(Start) && double.IsFinite(Duration) && Start >= 0 && Duration > 0;

    public bool Contains(double time) => time >= Start && time < End;

    public bool Intersects(VideoTimeRange other) => Start < other.End && other.Start < End;

    /// <summary>The overlap with another range, or <c>null</c> when they do not overlap at all.</summary>
    public VideoTimeRange? Intersection(VideoTimeRange other)
    {
        var lower = Math.Max(Start, other.Start);
        var upper = Math.Min(End, other.End);
        if (upper <= lower) return null;
        return new VideoTimeRange(lower, upper - lower);
    }

    public VideoTimeRange Shifted(double offset) => new(Start + offset, Duration);
}
