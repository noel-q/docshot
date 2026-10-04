using DocShot.Core.Models;
using DocShot.Core.Primitives;
using Xunit;

namespace DocShot.Core.Tests;

public class SnapshotPlanTests
{
    private static DisplayDescriptor MakeDisplay(uint id, double width, double height, double scale = 1.0) =>
        new(id, new RectD(0, 0, width, height), scale);

    [Fact]
    public void Displays_that_fit_within_the_budget_are_all_included()
    {
        var displays = new List<DisplayDescriptor> { MakeDisplay(1, 1920, 1080), MakeDisplay(2, 1920, 1080) };

        var plan = SnapshotPlan.Make(displays);

        Assert.Equal(2, plan.Included.Count);
        Assert.Empty(plan.Excluded);
    }

    [Fact]
    public void A_display_that_does_not_fit_is_skipped_entirely_never_downscaled()
    {
        // One huge display that alone exceeds the budget, plus a small one that fits comfortably.
        var huge = MakeDisplay(1, 20000, 20000, scale: 2.0); // far past the 134,217,728 pixel budget
        var small = MakeDisplay(2, 1920, 1080);

        var plan = SnapshotPlan.Make([huge, small]);

        Assert.Single(plan.Excluded);
        Assert.Equal(1u, plan.Excluded[0].DisplayId);
        Assert.Single(plan.Included);
        Assert.Equal(2u, plan.Included[0].DisplayId);
    }

    [Fact]
    public void Largest_first_ordering_means_a_big_display_is_not_starved_by_smaller_ones()
    {
        // Two displays that individually fit, but not both together; largest must win.
        var big = MakeDisplay(1, 10000, 10000); // 100,000,000 px
        var alsoFitsAlone = MakeDisplay(2, 6000, 6000); // 36,000,000 px - together they exceed the budget

        var plan = SnapshotPlan.Make([alsoFitsAlone, big]); // supplied smaller-first

        Assert.Contains(plan.Included, d => d.DisplayId == 1);
        Assert.DoesNotContain(plan.Included, d => d.DisplayId == 2);
    }

    [Fact]
    public void Invalid_descriptors_are_always_excluded()
    {
        var invalid = new DisplayDescriptor(1, new RectD(0, 0, 0, 0), 1.0);

        var plan = SnapshotPlan.Make([invalid]);

        Assert.Empty(plan.Included);
        Assert.Single(plan.Excluded);
    }

    [Fact]
    public void Included_and_excluded_preserve_the_callers_original_order()
    {
        var displays = new List<DisplayDescriptor>
        {
            MakeDisplay(3, 1920, 1080),
            MakeDisplay(1, 1920, 1080),
            MakeDisplay(2, 1920, 1080)
        };

        var plan = SnapshotPlan.Make(displays);

        Assert.Equal(new uint[] { 3, 1, 2 }, plan.Included.Select(d => d.DisplayId));
    }

    [Fact]
    public void Includes_checks_by_display_id()
    {
        var plan = SnapshotPlan.Make([MakeDisplay(7, 1920, 1080)]);
        Assert.True(plan.Includes(7));
        Assert.False(plan.Includes(8));
    }
}
