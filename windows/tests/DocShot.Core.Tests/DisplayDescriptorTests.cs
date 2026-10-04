using DocShot.Core.Models;
using DocShot.Core.Primitives;
using Xunit;

namespace DocShot.Core.Tests;

public class DisplayDescriptorTests
{
    [Fact]
    public void Pixel_dimensions_scale_and_round_the_point_size()
    {
        var descriptor = new DisplayDescriptor(1, new RectD(0, 0, 1920, 1080), Scale: 2.0);

        Assert.Equal(3840, descriptor.PixelWidth);
        Assert.Equal(2160, descriptor.PixelHeight);
        Assert.Equal(3840L * 2160, descriptor.PixelCount);
    }

    [Fact]
    public void An_invalid_descriptor_reports_zero_pixels_rather_than_negative_or_nan()
    {
        var descriptor = new DisplayDescriptor(1, new RectD(0, 0, -100, 1080), Scale: 2.0);

        Assert.False(descriptor.IsValid);
        Assert.Equal(0, descriptor.PixelWidth);
        Assert.Equal(0, descriptor.PixelHeight);
        Assert.Equal(0, descriptor.PixelCount);
    }

    [Fact]
    public void ContainsGlobalPoint_respects_a_negative_origin_display()
    {
        // A display placed left of the primary display has a negative X origin in global space.
        var descriptor = new DisplayDescriptor(2, new RectD(-1920, 0, 1920, 1080), Scale: 1.0);

        Assert.True(descriptor.ContainsGlobalPoint(new PointD(-1000, 500)));
        Assert.False(descriptor.ContainsGlobalPoint(new PointD(100, 500)));
    }

    [Fact]
    public void ContainsGlobalPoint_is_false_for_a_non_finite_point_or_an_invalid_display()
    {
        var descriptor = new DisplayDescriptor(1, new RectD(0, 0, 1920, 1080), Scale: 1.0);
        Assert.False(descriptor.ContainsGlobalPoint(new PointD(double.NaN, 0)));

        var invalid = new DisplayDescriptor(1, new RectD(0, 0, 0, 1080), Scale: 1.0);
        Assert.False(invalid.ContainsGlobalPoint(new PointD(10, 10)));
    }
}
