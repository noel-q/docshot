using DocShot.Core.Models;
using DocShot.Core.Primitives;
using Xunit;

namespace DocShot.Core.Tests;

public class VideoProjectTests
{
    private static VideoProject MakeProject(double duration = 10) =>
        new(new Uri("file:///tmp/clip.mp4"), duration, new SizeD(1280, 720), hasSourceAudio: false);

    [Fact]
    public void A_new_project_starts_as_a_single_untouched_segment()
    {
        var project = MakeProject();

        Assert.Single(project.Segments);
        Assert.Equal(10, project.TimelineDuration);
        Assert.True(project.IsUnedited);
    }

    [Fact]
    public void Trim_replaces_the_segments_range_and_does_not_touch_the_original_instance()
    {
        var project = MakeProject();
        var segmentId = project.Segments[0].Id;

        var trimmed = project.Trim(segmentId, new VideoTimeRange(1, 4));

        Assert.Equal(4, trimmed.TimelineDuration);
        Assert.Equal(10, project.TimelineDuration); // original untouched
    }

    [Fact]
    public void Trim_of_an_unknown_segment_throws_and_changes_nothing()
    {
        var project = MakeProject();
        var ex = Assert.Throws<VideoProjectException>(() => project.Trim(Guid.NewGuid(), new VideoTimeRange(0, 1)));
        Assert.IsType<VideoProjectError.UnknownSegment>(ex.Error);
    }

    [Fact]
    public void Trim_past_the_source_duration_is_rejected()
    {
        var project = MakeProject(duration: 5);
        var segmentId = project.Segments[0].Id;

        var ex = Assert.Throws<VideoProjectException>(() => project.Trim(segmentId, new VideoTimeRange(4, 10)));
        Assert.IsType<VideoProjectError.RangeOutsideSource>(ex.Error);
    }

    [Fact]
    public void Trim_clips_annotations_to_the_new_range_and_drops_ones_left_outside_it()
    {
        var project = MakeProject();
        var segmentId = project.Segments[0].Id;
        var kept = new VideoAnnotation(segmentId, new VideoTimeRange(2, 2), Sample());
        var dropped = new VideoAnnotation(segmentId, new VideoTimeRange(8, 1), Sample());
        project = project.AddAnnotation(kept).AddAnnotation(dropped);

        var trimmed = project.Trim(segmentId, new VideoTimeRange(0, 5));

        var remaining = Assert.Single(trimmed.Annotations);
        Assert.Equal(kept.Id, remaining.Id);
    }

    [Fact]
    public void Split_produces_two_segments_the_leading_half_keeps_the_original_id()
    {
        var project = MakeProject();
        var originalId = project.Segments[0].Id;

        var (split, leading, trailing) = project.Split(atTimelineTime: 4);

        Assert.Equal(2, split.Segments.Count);
        Assert.Equal(originalId, leading);
        Assert.Equal(originalId, split.Segments[0].Id);
        Assert.Equal(trailing, split.Segments[1].Id);
        Assert.Equal(4, split.Segments[0].Duration);
        Assert.Equal(6, split.Segments[1].Duration);
    }

    [Fact]
    public void Split_within_the_minimum_duration_of_an_edge_is_rejected()
    {
        var project = MakeProject();
        var ex = Assert.Throws<VideoProjectException>(() => project.Split(atTimelineTime: 0.01));
        Assert.IsType<VideoProjectError.SplitAtSegmentBoundary>(ex.Error);
    }

    [Fact]
    public void Split_reassigns_annotations_starting_at_or_after_the_cut_to_the_trailing_half()
    {
        var project = MakeProject();
        var originalId = project.Segments[0].Id;
        var beforeCut = new VideoAnnotation(originalId, new VideoTimeRange(1, 1), Sample());
        var afterCut = new VideoAnnotation(originalId, new VideoTimeRange(5, 1), Sample());
        project = project.AddAnnotation(beforeCut).AddAnnotation(afterCut);

        var (split, leading, trailing) = project.Split(atTimelineTime: 4);

        var before = split.Annotations.Single(a => a.Id == beforeCut.Id);
        var after = split.Annotations.Single(a => a.Id == afterCut.Id);
        Assert.Equal(leading, before.SegmentId);
        Assert.Equal(trailing, after.SegmentId);
    }

    [Fact]
    public void RemoveSegment_deletes_its_annotations_too()
    {
        var project = MakeProject();
        var (split, leading, trailing) = project.Split(atTimelineTime: 4);
        var annotation = new VideoAnnotation(trailing, new VideoTimeRange(5, 1), Sample());
        split = split.AddAnnotation(annotation);

        var removed = split.RemoveSegment(trailing);

        Assert.Single(removed.Segments);
        Assert.Empty(removed.Annotations);
    }

    [Fact]
    public void RemoveSegment_refuses_to_remove_the_last_segment()
    {
        var project = MakeProject();
        var ex = Assert.Throws<VideoProjectException>(() => project.RemoveSegment(project.Segments[0].Id));
        Assert.IsType<VideoProjectError.CannotRemoveLastSegment>(ex.Error);
    }

    [Fact]
    public void AddAnnotation_outside_its_segments_range_is_rejected()
    {
        var project = MakeProject();
        var segmentId = project.Segments[0].Id;
        var annotation = new VideoAnnotation(segmentId, new VideoTimeRange(20, 1), Sample());

        var ex = Assert.Throws<VideoProjectException>(() => project.AddAnnotation(annotation));
        Assert.IsType<VideoProjectError.AnnotationOutsideSegment>(ex.Error);
    }

    [Fact]
    public void ActiveAnnotations_returns_only_overlays_visible_at_that_timeline_position()
    {
        var project = MakeProject();
        var segmentId = project.Segments[0].Id;
        var early = new VideoAnnotation(segmentId, new VideoTimeRange(0, 2), Sample());
        var late = new VideoAnnotation(segmentId, new VideoTimeRange(5, 2), Sample());
        project = project.AddAnnotation(early).AddAnnotation(late);

        var atOne = project.ActiveAnnotationsAtTimelineTime(1);
        Assert.Single(atOne);

        var atSix = project.ActiveAnnotationsAtTimelineTime(6);
        Assert.Single(atSix);

        var atFour = project.ActiveAnnotationsAtTimelineTime(4);
        Assert.Empty(atFour);
    }

    [Fact]
    public void History_perform_records_undo_only_when_the_project_actually_changed()
    {
        var history = new VideoProjectHistory(MakeProject());
        var segmentId = history.Current.Segments[0].Id;

        // A no-op mutation (trim to the segment's own current range) must not create an undo step.
        history.Perform(p => p.Trim(segmentId, p.Segments[0].SourceRange));
        Assert.False(history.CanUndo);

        history.Perform(p => p.Trim(segmentId, new VideoTimeRange(1, 5)));
        Assert.True(history.CanUndo);
    }

    [Fact]
    public void History_undo_and_redo_restore_the_correct_snapshots()
    {
        var history = new VideoProjectHistory(MakeProject());
        var segmentId = history.Current.Segments[0].Id;

        history.Perform(p => p.Trim(segmentId, new VideoTimeRange(1, 5)));
        Assert.Equal(5, history.Current.TimelineDuration);

        Assert.True(history.Undo());
        Assert.Equal(10, history.Current.TimelineDuration);

        Assert.True(history.Redo());
        Assert.Equal(5, history.Current.TimelineDuration);
    }

    [Fact]
    public void History_perform_does_not_record_a_step_when_the_mutation_throws()
    {
        var history = new VideoProjectHistory(MakeProject());

        Assert.Throws<VideoProjectException>(() => history.Perform(p => p.RemoveSegment(Guid.NewGuid())));

        Assert.False(history.CanUndo);
    }

    private static AnnotationItem Sample() =>
        new(new AnnotationShape.Rectangle(new RectD(0, 0, 10, 10), true), RgbaColor.Red);
}
