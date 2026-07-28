namespace DocShot.Core.Models;

/// <summary>
/// Why an edit was refused. Every mutation on <see cref="VideoProject"/> either applies completely
/// or throws a <see cref="VideoProjectException"/> wrapping one of these and leaves the project
/// untouched, so a rejected edit can never leave a half-applied timeline behind.
/// </summary>
public abstract record VideoProjectError
{
    public sealed record UnknownSegment(Guid Id) : VideoProjectError;
    public sealed record UnknownAnnotation(Guid Id) : VideoProjectError;

    /// <summary>The range is not finite, is negative, or is shorter than <see cref="VideoTimeRange.MinimumDuration"/>.</summary>
    public sealed record InvalidTimeRange : VideoProjectError;

    public sealed record RangeOutsideSource(double SourceDuration) : VideoProjectError;
    public sealed record TimeOutsideTimeline(double TimelineDuration) : VideoProjectError;

    /// <summary>A split at (or within the minimum duration of) a segment edge would produce an empty piece.</summary>
    public sealed record SplitAtSegmentBoundary : VideoProjectError;

    /// <summary>The timeline must always render something.</summary>
    public sealed record CannotRemoveLastSegment : VideoProjectError;

    public sealed record InvalidSegmentPosition : VideoProjectError;

    /// <summary>The annotation's visible range does not overlap the segment it is attached to.</summary>
    public sealed record AnnotationOutsideSegment : VideoProjectError;

    private VideoProjectError() { }

    public string Message => this switch
    {
        UnknownSegment => "That clip is no longer part of the timeline.",
        UnknownAnnotation => "That annotation is no longer part of the project.",
        InvalidTimeRange => $"A clip must be at least {VideoTimeRange.MinimumDuration:F2} seconds long.",
        RangeOutsideSource e => $"That range falls outside the recording, which is {e.SourceDuration:F2} seconds long.",
        TimeOutsideTimeline e => $"That time falls outside the timeline, which is {e.TimelineDuration:F2} seconds long.",
        SplitAtSegmentBoundary => $"Split further from the edge of the clip: both halves need to be at least {VideoTimeRange.MinimumDuration:F2} seconds.",
        CannotRemoveLastSegment => "A project needs at least one clip. Discard the recording instead.",
        InvalidSegmentPosition => "That is not a valid position in the timeline.",
        AnnotationOutsideSegment => "An annotation has to be visible somewhere inside the clip it belongs to.",
        _ => "Unknown video project error."
    };
}

/// <summary>The exception type <see cref="VideoProject"/>'s mutating methods throw, carrying a <see cref="VideoProjectError"/>.</summary>
public sealed class VideoProjectException(VideoProjectError error) : Exception(error.Message)
{
    public VideoProjectError Error { get; } = error;
}
