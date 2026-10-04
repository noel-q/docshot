using DocShot.Core.Models;
using DocShot.Core.Primitives;
using Xunit;

namespace DocShot.Core.Tests;

public class ExportSizeTests
{
    private static readonly SizeD Source = new(1000, 800);

    [Fact]
    public void Native_resolves_to_source_pixel_dimensions()
    {
        var result = ExportSize.NativeSize.Resolve(Source);
        Assert.True(result.IsSuccess);
        Assert.Equal(new SizeD(1000, 800), result.Value);
    }

    [Fact]
    public void Percent_scales_both_dimensions_downscale_and_upscale()
    {
        var half = new ExportSize.Percent(50).Resolve(Source);
        Assert.Equal(new SizeD(500, 400), half.Value);

        var doubled = new ExportSize.Percent(200).Resolve(Source);
        Assert.Equal(new SizeD(2000, 1600), doubled.Value);
    }

    [Fact]
    public void Explicit_pixels_resolves_to_requested_dimensions()
    {
        var result = new ExportSize.Pixels(640, 512).Resolve(Source);
        Assert.Equal(new SizeD(640, 512), result.Value);
    }

    [Fact]
    public void Fractional_results_round_half_away_from_zero_and_never_fall_below_one_pixel()
    {
        var square = new SizeD(300, 300);

        // 300 * 0.505 = 151.5 -> 152
        Assert.Equal(new SizeD(152, 152), new ExportSize.Percent(50.5).Resolve(square).Value);

        // 300 * 0.33333 = 99.999 -> 100
        Assert.Equal(new SizeD(100, 100), new ExportSize.Percent(33.333).Resolve(square).Value);

        // 100 * 0.001 = 0.1 -> clamped to 1, never zero
        Assert.Equal(new SizeD(1, 1), new ExportSize.Percent(0.1).Resolve(new SizeD(100, 100)).Value);

        Assert.Equal(new SizeD(1, 1), new ExportSize.Pixels(0.4, 0.6).Resolve(Source).Value);
    }

    [Theory]
    [MemberData(nameof(InvalidRequests))]
    public void Zero_negative_and_non_finite_requests_are_rejected(ExportSize size)
    {
        var result = size.Resolve(Source);
        Assert.False(result.IsSuccess);
        Assert.IsType<ExportSizeError.InvalidRequestedSize>(result.Error);
    }

    public static IEnumerable<object[]> InvalidRequests()
    {
        yield return [new ExportSize.Percent(0)];
        yield return [new ExportSize.Percent(-10)];
        yield return [new ExportSize.Percent(double.NaN)];
        yield return [new ExportSize.Pixels(0, 100)];
        yield return [new ExportSize.Pixels(100, -1)];
        yield return [new ExportSize.Pixels(double.PositiveInfinity, 100)];
    }

    [Fact]
    public void Invalid_source_size_is_rejected_even_for_native()
    {
        var result = ExportSize.NativeSize.Resolve(new SizeD(0, 800));
        Assert.False(result.IsSuccess);
        Assert.IsType<ExportSizeError.InvalidSourceSize>(result.Error);
    }

    [Fact]
    public void Exceeding_the_memory_budget_is_rejected_with_both_counts()
    {
        // 20000 x 20000 output pixels is far past the 134,217,728 pixel budget.
        var result = new ExportSize.Pixels(20000, 20000).Resolve(Source);
        Assert.False(result.IsSuccess);
        var error = Assert.IsType<ExportSizeError.ExceedsMemoryBudget>(result.Error);
        Assert.Equal(ExportSize.MaximumPixelCount, error.BudgetPixelCount);
        Assert.True(error.RequestedPixelCount > error.BudgetPixelCount);
    }

    [Fact]
    public void Native_is_never_subject_to_the_memory_budget()
    {
        // A vast native size still succeeds - the image already exists at that size.
        var result = ExportSize.NativeSize.Resolve(new SizeD(50000, 50000));
        Assert.True(result.IsSuccess);
    }

    [Fact]
    public void Aspect_locked_height_and_width_preserve_ratio()
    {
        var height = ExportSize.AspectLockedHeight(500, Source);
        Assert.Equal(400, height);

        var width = ExportSize.AspectLockedWidth(400, Source);
        Assert.Equal(500, width);
    }
}
