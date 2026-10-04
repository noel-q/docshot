using DocShot.Core.Primitives;

namespace DocShot.Core.Models;

/// <summary>
/// One piece of the source recording, placed on the timeline. A segment never owns media of its
/// own: it is a range into the single source file. Trimming and splitting only move those ranges
/// around, which is what makes the whole editor non-destructive - the original file is never
/// rewritten, and nothing is exported until the caller asks.
/// </summary>
public sealed record VideoSegment(Guid Id, VideoTimeRange SourceRange)
{
    public VideoSegment(VideoTimeRange sourceRange) : this(Guid.NewGuid(), sourceRange) { }

    public double Duration => SourceRange.Duration;
}

/// <summary>
/// An annotation overlay, visible for part of the recording.
/// </summary>
/// <remarks>
/// The visible window is stored in <b>source</b> time, not timeline time - the decision the rest
/// of the model follows from. An arrow points at something on screen, so when a segment is
/// trimmed, split, or reordered, the annotation stays attached to the frames it was drawn over
/// instead of sliding onto unrelated content. <see cref="SegmentId"/> scopes the annotation to one
/// segment, so deleting a clip deletes its annotations and the same source frames appearing twice
/// on the timeline do not silently share overlays.
/// </remarks>
public sealed record VideoAnnotation(Guid Id, Guid SegmentId, VideoTimeRange SourceRange, AnnotationItem Item)
{
    public VideoAnnotation(Guid segmentId, VideoTimeRange sourceRange, AnnotationItem item)
        : this(Guid.NewGuid(), segmentId, sourceRange, item) { }
}

/// <summary>
/// A non-destructive edit of one completed temporary recording.
/// </summary>
/// <remarks>
/// <b>Deliberate difference from the macOS port source.</b> The macOS <c>VideoProject</c> is a
/// Swift <c>struct</c> with <c>mutating func ... throws</c> methods that mutate in place; a caller
/// copies the value first (<c>var candidate = current</c>) so a rejected edit can be discarded by
/// simply not committing the copy. C# has no equivalent low-cost struct-copy-of-a-collection
/// semantics - copying a struct that holds a <c>List&lt;T&gt;</c> copies the reference, not the
/// list, so the same pattern would let a "discarded" edit mutate the original anyway. Instead,
/// every edit method here returns a **new** <see cref="VideoProject"/> and never touches the
/// instance it was called on; an invalid edit throws <see cref="VideoProjectException"/> before
/// constructing anything. That makes "a rejected edit cannot leave a half-applied timeline" true
/// by construction rather than by discipline, and makes <see cref="VideoProjectHistory"/>'s
/// snapshot stack trivially correct: every entry in it is permanently immutable once created.
/// </remarks>
public sealed class VideoProject : IEquatable<VideoProject>
{
    public Uri SourceUrl { get; }
    public double SourceDuration { get; }
    public SizeD SourcePixelSize { get; }
    public bool HasSourceAudio { get; }

    private readonly List<VideoSegment> _segments;
    private readonly List<VideoAnnotation> _annotations;

    public IReadOnlyList<VideoSegment> Segments => _segments;
    public IReadOnlyList<VideoAnnotation> Annotations => _annotations;

    private const double Epsilon = 0.0001;

    public VideoProject(
        Uri sourceUrl,
        double sourceDuration,
        SizeD sourcePixelSize,
        bool hasSourceAudio,
        IEnumerable<VideoSegment>? segments = null,
        IEnumerable<VideoAnnotation>? annotations = null)
    {
        SourceUrl = sourceUrl;
        SourceDuration = sourceDuration;
        SourcePixelSize = sourcePixelSize;
        HasSourceAudio = hasSourceAudio;
        _segments = segments?.ToList() ?? [new VideoSegment(new VideoTimeRange(0, Math.Max(sourceDuration, 0)))];
        _annotations = annotations?.ToList() ?? [];
    }

    /// <summary>Opens a finished recording for editing. The initial timeline is the whole clip, untouched.</summary>
    public VideoProject(TemporaryRecording recording)
        : this(recording.Url, recording.Duration, recording.PixelSize, recording.HasAudio) { }

    private VideoProject(VideoProject source, List<VideoSegment> segments, List<VideoAnnotation> annotations)
    {
        SourceUrl = source.SourceUrl;
        SourceDuration = source.SourceDuration;
        SourcePixelSize = source.SourcePixelSize;
        HasSourceAudio = source.HasSourceAudio;
        _segments = segments;
        _annotations = annotations;
    }

    // MARK: - Timeline queries

    public double TimelineDuration => _segments.Sum(s => s.Duration);

    /// <summary>True when the project would export exactly the source, byte-for-byte identical in content.</summary>
    public bool IsUnedited =>
        _annotations.Count == 0
        && _segments.Count == 1
        && _segments[0].SourceRange.Start == 0
        && Math.Abs(_segments[0].SourceRange.Duration - SourceDuration) < Epsilon;

    /// <summary>
    /// Cheap pre-flight check before handing this project to a real exporter. Mirrors macOS's
    /// <c>VideoProjectExportError.emptyTimeline</c> case (see the portability audit in
    /// <c>windows/docs/PARITY_CHECKLIST.md</c> §4) - genuinely encoder-specific failures
    /// (unreadable source, composition failure, encode failure) still belong in
    /// <c>DocShot.Platform</c>'s exporter, not here; this only catches the one thing Core already
    /// knows for certain before an encoder ever gets involved.
    /// </summary>
    public void ValidateForExport()
    {
        if (TimelineDuration <= Epsilon) throw new VideoProjectException(new VideoProjectError.EmptyTimeline());
    }

    public VideoSegment? Segment(Guid id) => _segments.FirstOrDefault(s => s.Id == id);

    /// <summary>Where a segment begins on the timeline, or <c>null</c> if it is not in this project.</summary>
    public double? TimelineStart(Guid segmentId)
    {
        double offset = 0;
        foreach (var segment in _segments)
        {
            if (segment.Id == segmentId) return offset;
            offset += segment.Duration;
        }
        return null;
    }

    /// <summary>Which segment is playing at a timeline position, and how far into it that is.</summary>
    public (VideoSegment Segment, double LocalTime)? SegmentAtTimelineTime(double time)
    {
        if (time < 0) return null;
        double offset = 0;
        foreach (var segment in _segments)
        {
            if (time < offset + segment.Duration) return (segment, time - offset);
            offset += segment.Duration;
        }
        return null;
    }

    /// <summary>The source-asset time a timeline position reads from.</summary>
    public double? SourceTimeAtTimelineTime(double time)
    {
        var hit = SegmentAtTimelineTime(time);
        if (hit is not { } h) return null;
        return h.Segment.SourceRange.Start + h.LocalTime;
    }

    public IEnumerable<VideoAnnotation> AnnotationsForSegment(Guid segmentId) =>
        _annotations.Where(a => a.SegmentId == segmentId);

    /// <summary>
    /// The overlays visible at a timeline position, in insertion order. This is the one query an
    /// exporter needs per frame, and the reason annotations are anchored in source time: the
    /// mapping is a lookup, never a re-derivation of edit history.
    /// </summary>
    public IReadOnlyList<AnnotationItem> ActiveAnnotationsAtTimelineTime(double time)
    {
        var hit = SegmentAtTimelineTime(time);
        if (hit is not { } h) return [];
        var sourceTime = h.Segment.SourceRange.Start + h.LocalTime;
        return _annotations
            .Where(a => a.SegmentId == h.Segment.Id && a.SourceRange.Contains(sourceTime))
            .Select(a => a.Item)
            .ToList();
    }

    // MARK: - Segment mutations

    /// <summary>Replaces a segment's source range - the trim operation. Returns a new project.</summary>
    public VideoProject Trim(Guid segmentId, VideoTimeRange range)
    {
        var index = _segments.FindIndex(s => s.Id == segmentId);
        if (index < 0) throw new VideoProjectException(new VideoProjectError.UnknownSegment(segmentId));
        if (!range.IsValid) throw new VideoProjectException(new VideoProjectError.InvalidTimeRange());
        if (range.Start < 0 || range.End > SourceDuration + Epsilon)
        {
            throw new VideoProjectException(new VideoProjectError.RangeOutsideSource(SourceDuration));
        }

        var segments = CloneSegments();
        segments[index] = segments[index] with { SourceRange = range };
        var annotations = ClipAnnotations(CloneAnnotations(), segments, index);
        return new VideoProject(this, segments, annotations);
    }

    /// <summary>
    /// Splits the segment under a timeline position in two. Returns the new project and the
    /// (leading, trailing) segment IDs. The leading half keeps the original segment's identity so
    /// existing selections and undo snapshots stay meaningful; the trailing half is new.
    /// Annotations are reassigned to whichever half contains the frame they start on, and clipped
    /// to it.
    /// </summary>
    public (VideoProject Project, Guid Leading, Guid Trailing) Split(double atTimelineTime)
    {
        var hit = SegmentAtTimelineTime(atTimelineTime);
        if (hit is not { } h)
        {
            throw new VideoProjectException(new VideoProjectError.TimeOutsideTimeline(TimelineDuration));
        }
        var index = _segments.FindIndex(s => s.Id == h.Segment.Id);

        if (h.LocalTime < VideoTimeRange.MinimumDuration ||
            h.Segment.Duration - h.LocalTime < VideoTimeRange.MinimumDuration)
        {
            throw new VideoProjectException(new VideoProjectError.SplitAtSegmentBoundary());
        }

        var splitSourceTime = h.Segment.SourceRange.Start + h.LocalTime;
        var leadingRange = new VideoTimeRange(h.Segment.SourceRange.Start, h.LocalTime);
        var trailingRange = new VideoTimeRange(splitSourceTime, h.Segment.SourceRange.Duration - h.LocalTime);

        var trailing = new VideoSegment(trailingRange);
        var segments = CloneSegments();
        segments[index] = segments[index] with { SourceRange = leadingRange };
        segments.Insert(index + 1, trailing);

        var annotations = CloneAnnotations();
        for (var i = 0; i < annotations.Count; i++)
        {
            if (annotations[i].SegmentId == h.Segment.Id && annotations[i].SourceRange.Start >= splitSourceTime)
            {
                annotations[i] = annotations[i] with { SegmentId = trailing.Id };
            }
        }
        annotations = ClipAnnotations(annotations, segments, index);
        annotations = ClipAnnotations(annotations, segments, index + 1);

        return (new VideoProject(this, segments, annotations), h.Segment.Id, trailing.Id);
    }

    /// <summary>Removes a segment and every annotation attached to it. Returns a new project.</summary>
    public VideoProject RemoveSegment(Guid id)
    {
        var index = _segments.FindIndex(s => s.Id == id);
        if (index < 0) throw new VideoProjectException(new VideoProjectError.UnknownSegment(id));
        if (_segments.Count <= 1) throw new VideoProjectException(new VideoProjectError.CannotRemoveLastSegment());

        var segments = CloneSegments();
        segments.RemoveAt(index);
        var annotations = CloneAnnotations();
        annotations.RemoveAll(a => a.SegmentId == id);
        return new VideoProject(this, segments, annotations);
    }

    /// <summary>Reorders a segment. Annotations are keyed by segment, so they move with it. Returns a new project.</summary>
    public VideoProject MoveSegment(Guid id, int toIndex)
    {
        var index = _segments.FindIndex(s => s.Id == id);
        if (index < 0) throw new VideoProjectException(new VideoProjectError.UnknownSegment(id));
        if (toIndex < 0 || toIndex >= _segments.Count)
        {
            throw new VideoProjectException(new VideoProjectError.InvalidSegmentPosition());
        }
        if (toIndex == index) return this;

        var segments = CloneSegments();
        var segment = segments[index];
        segments.RemoveAt(index);
        segments.Insert(toIndex, segment);
        return new VideoProject(this, segments, CloneAnnotations());
    }

    // MARK: - Annotation mutations

    public VideoProject AddAnnotation(VideoAnnotation annotation)
    {
        var segment = Segment(annotation.SegmentId)
            ?? throw new VideoProjectException(new VideoProjectError.UnknownSegment(annotation.SegmentId));
        if (!annotation.SourceRange.IsValid) throw new VideoProjectException(new VideoProjectError.InvalidTimeRange());
        if (!annotation.SourceRange.Intersects(segment.SourceRange))
        {
            throw new VideoProjectException(new VideoProjectError.AnnotationOutsideSegment());
        }

        var annotations = CloneAnnotations();
        annotations.Add(annotation);
        return new VideoProject(this, CloneSegments(), annotations);
    }

    public VideoProject RemoveAnnotation(Guid id)
    {
        var index = _annotations.FindIndex(a => a.Id == id);
        if (index < 0) throw new VideoProjectException(new VideoProjectError.UnknownAnnotation(id));

        var annotations = CloneAnnotations();
        annotations.RemoveAt(index);
        return new VideoProject(this, CloneSegments(), annotations);
    }

    /// <summary>Retimes an annotation within its current segment. Returns a new project.</summary>
    public VideoProject MoveAnnotation(Guid id, VideoTimeRange range)
    {
        var index = _annotations.FindIndex(a => a.Id == id);
        if (index < 0) throw new VideoProjectException(new VideoProjectError.UnknownAnnotation(id));
        var segment = Segment(_annotations[index].SegmentId)
            ?? throw new VideoProjectException(new VideoProjectError.UnknownSegment(_annotations[index].SegmentId));
        if (!range.IsValid) throw new VideoProjectException(new VideoProjectError.InvalidTimeRange());
        if (!range.Intersects(segment.SourceRange))
        {
            throw new VideoProjectException(new VideoProjectError.AnnotationOutsideSegment());
        }

        var annotations = CloneAnnotations();
        annotations[index] = annotations[index] with { SourceRange = range };
        return new VideoProject(this, CloneSegments(), annotations);
    }

    /// <summary>Moves an annotation to another segment, retiming it at the same time. Returns a new project.</summary>
    public VideoProject MoveAnnotation(Guid id, Guid segmentId, VideoTimeRange range)
    {
        var index = _annotations.FindIndex(a => a.Id == id);
        if (index < 0) throw new VideoProjectException(new VideoProjectError.UnknownAnnotation(id));
        var segment = Segment(segmentId) ?? throw new VideoProjectException(new VideoProjectError.UnknownSegment(segmentId));
        if (!range.IsValid) throw new VideoProjectException(new VideoProjectError.InvalidTimeRange());
        if (!range.Intersects(segment.SourceRange))
        {
            throw new VideoProjectException(new VideoProjectError.AnnotationOutsideSegment());
        }

        var annotations = CloneAnnotations();
        annotations[index] = annotations[index] with { SegmentId = segmentId, SourceRange = range };
        return new VideoProject(this, CloneSegments(), annotations);
    }

    /// <summary>Repositions an annotation's drawing without touching its timing. Returns a new project.</summary>
    public VideoProject TranslateAnnotation(Guid id, SizeD delta)
    {
        var index = _annotations.FindIndex(a => a.Id == id);
        if (index < 0) throw new VideoProjectException(new VideoProjectError.UnknownAnnotation(id));

        var annotations = CloneAnnotations();
        annotations[index] = annotations[index] with { Item = annotations[index].Item.Translated(delta) };
        return new VideoProject(this, CloneSegments(), annotations);
    }

    // MARK: - Internals

    private List<VideoSegment> CloneSegments() => [.. _segments];
    private List<VideoAnnotation> CloneAnnotations() => [.. _annotations];

    /// <summary>
    /// Clips every annotation on the segment at <paramref name="segmentIndex"/> to that segment's
    /// source range, dropping any that no longer overlap it. Derived clipping is allowed to
    /// produce ranges below the authoring minimum: the alternative is deleting an overlay the user
    /// never asked to remove.
    /// </summary>
    private static List<VideoAnnotation> ClipAnnotations(
        List<VideoAnnotation> annotations,
        List<VideoSegment> segments,
        int segmentIndex)
    {
        var segment = segments[segmentIndex];
        var result = new List<VideoAnnotation>(annotations.Count);
        foreach (var annotation in annotations)
        {
            if (annotation.SegmentId != segment.Id)
            {
                result.Add(annotation);
                continue;
            }
            var clipped = annotation.SourceRange.Intersection(segment.SourceRange);
            if (clipped is { } range)
            {
                result.Add(annotation with { SourceRange = range });
            }
            // else: dropped - no longer overlaps the segment it belonged to.
        }
        return result;
    }

    public bool Equals(VideoProject? other)
    {
        if (other is null) return false;
        if (ReferenceEquals(this, other)) return true;
        return SourceUrl == other.SourceUrl
            && SourceDuration.Equals(other.SourceDuration)
            && SourcePixelSize.Equals(other.SourcePixelSize)
            && HasSourceAudio == other.HasSourceAudio
            && _segments.SequenceEqual(other._segments)
            && _annotations.SequenceEqual(other._annotations);
    }

    public override bool Equals(object? obj) => Equals(obj as VideoProject);

    public override int GetHashCode() => HashCode.Combine(SourceUrl, SourceDuration, SourcePixelSize, HasSourceAudio);

    public static bool operator ==(VideoProject? left, VideoProject? right) =>
        left is null ? right is null : left.Equals(right);

    public static bool operator !=(VideoProject? left, VideoProject? right) => !(left == right);
}

/// <summary>
/// Snapshot-based undo/redo. Because every <see cref="VideoProject"/> edit method returns a brand
/// new, permanently-immutable instance (see the remarks on <see cref="VideoProject"/>), the
/// cheapest correct history really is a stack of whole projects here too - there are no inverse
/// operations to get wrong, and a rejected mutation never enters the history at all.
/// </summary>
public sealed class VideoProjectHistory
{
    public VideoProject Current { get; private set; }
    private readonly List<VideoProject> _undoStack = [];
    private readonly List<VideoProject> _redoStack = [];

    /// <summary>How many snapshots to keep. A recording editor holds far fewer edits than a document editor.</summary>
    public int Limit { get; }

    public VideoProjectHistory(VideoProject project, int limit = 50)
    {
        Current = project;
        Limit = limit;
    }

    public bool CanUndo => _undoStack.Count > 0;
    public bool CanRedo => _redoStack.Count > 0;

    /// <summary>
    /// Applies a mutation, recording an undo step only if it succeeded and actually changed
    /// something. A throwing mutation leaves both the project and the history untouched - it
    /// propagates to the caller exactly like the macOS `rethrows` behaviour.
    /// </summary>
    public void Perform(Func<VideoProject, VideoProject> mutation)
    {
        var candidate = mutation(Current);
        if (candidate == Current) return;

        _undoStack.Add(Current);
        if (_undoStack.Count > Limit)
        {
            _undoStack.RemoveRange(0, _undoStack.Count - Limit);
        }
        _redoStack.Clear();
        Current = candidate;
    }

    public bool Undo()
    {
        if (_undoStack.Count == 0) return false;
        var previous = _undoStack[^1];
        _undoStack.RemoveAt(_undoStack.Count - 1);
        _redoStack.Add(Current);
        Current = previous;
        return true;
    }

    public bool Redo()
    {
        if (_redoStack.Count == 0) return false;
        var next = _redoStack[^1];
        _redoStack.RemoveAt(_redoStack.Count - 1);
        _undoStack.Add(Current);
        Current = next;
        return true;
    }
}
