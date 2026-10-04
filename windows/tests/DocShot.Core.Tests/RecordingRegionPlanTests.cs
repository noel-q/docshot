using DocShot.Core.Models;
using DocShot.Core.Primitives;
using Xunit;

namespace DocShot.Core.Tests;

public class RecordingRegionPlanTests
{
    private static readonly DisplayDescriptor Primary = new(1, new RectD(0, 0, 1920, 1080), 2.0);
    private static readonly DisplayDescriptor Secondary = new(2, new RectD(1920, 0, 1920, 1080), 1.0);

    [Fact]
    public void A_region_wholly_inside_one_display_resolves_to_that_displays_scaled_output_size()
    {
        var rect = new RectD(100, 100, 400, 300);

        var plan = RecordingRegionPlan.Make(rect, [Primary, Secondary]);

        var ok = Assert.IsType<RecordingRegionPlan.Ok>(plan);
        Assert.Equal(1u, ok.DisplayId);
        Assert.Equal(new SizeD(800, 600), ok.OutputPixelSize); // 400x300 at 2x scale
    }

    [Fact]
    public void The_source_rect_is_relative_to_the_containing_displays_own_origin()
    {
        var rect = new RectD(2000, 100, 200, 200); // inside Secondary, which starts at x=1920

        var plan = RecordingRegionPlan.Make(rect, [Primary, Secondary]);

        var ok = Assert.IsType<RecordingRegionPlan.Ok>(plan);
        Assert.Equal(2u, ok.DisplayId);
        Assert.Equal(80, ok.SourceRectInPoints.X); // 2000 - 1920
        Assert.Equal(100, ok.SourceRectInPoints.Y);
    }

    [Fact]
    public void A_region_spanning_two_displays_is_rejected_not_cropped_or_stretched()
    {
        var rect = new RectD(1800, 100, 400, 300); // straddles the 1920 boundary

        var plan = RecordingRegionPlan.Make(rect, [Primary, Secondary]);

        var rejected = Assert.IsType<RecordingRegionPlan.Rejected>(plan);
        Assert.IsType<RecordingTargetRejection.SpansMultipleDisplays>(rejected.Reason);
        Assert.Null(plan.Target);
    }

    [Fact]
    public void A_region_touching_no_display_is_rejected_as_having_no_containing_display()
    {
        var rect = new RectD(5000, 100, 400, 300);

        var plan = RecordingRegionPlan.Make(rect, [Primary, Secondary]);

        var rejected = Assert.IsType<RecordingRegionPlan.Rejected>(plan);
        Assert.IsType<RecordingTargetRejection.NoContainingDisplay>(rejected.Reason);
    }

    [Fact]
    public void A_region_below_the_minimum_side_is_rejected_as_too_small()
    {
        var rect = new RectD(100, 100, 5, 5);

        var plan = RecordingRegionPlan.Make(rect, [Primary]);

        var rejected = Assert.IsType<RecordingRegionPlan.Rejected>(plan);
        Assert.IsType<RecordingTargetRejection.TooSmall>(rejected.Reason);
    }

    [Fact]
    public void A_negative_width_or_height_selection_is_normalized_before_evaluation()
    {
        // A drag that ends up top-left of its start point produces negative width/height.
        var rect = new RectD(500, 400, -400, -300);

        var plan = RecordingRegionPlan.Make(rect, [Primary]);

        var ok = Assert.IsType<RecordingRegionPlan.Ok>(plan);
        Assert.Equal(new SizeD(800, 600), ok.OutputPixelSize);
    }

    [Fact]
    public void Odd_dimensions_are_preserved_exactly_never_rounded_to_even()
    {
        var rect = new RectD(0, 0, 401, 301); // odd in points; at 2x scale, still odd in pixels

        var plan = RecordingRegionPlan.Make(rect, [Primary]);

        var ok = Assert.IsType<RecordingRegionPlan.Ok>(plan);
        Assert.Equal(new SizeD(802, 602), ok.OutputPixelSize);
    }

    [Fact]
    public void Target_projects_a_successful_plan_into_a_RecordingTarget_Region()
    {
        var plan = RecordingRegionPlan.Make(new RectD(0, 0, 400, 300), [Primary]);

        var target = Assert.IsType<RecordingTarget.Region>(plan.Target);
        Assert.Equal(1u, target.DisplayId);
    }
}
