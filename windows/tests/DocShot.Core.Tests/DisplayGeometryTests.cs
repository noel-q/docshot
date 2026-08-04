using DocShot.Core.Models;
using DocShot.Core.Primitives;
using Xunit;

namespace DocShot.Core.Tests;

public class DisplayGeometryTests
{
    [Fact]
    public void NormalizeRect_flips_negative_width_and_height_to_positive_with_adjusted_origin()
    {
        var rect = new RectD(100, 100, -40, -20);
        var normalized = DisplayGeometry.NormalizeRect(rect);

        Assert.Equal(60, normalized.X);
        Assert.Equal(80, normalized.Y);
        Assert.Equal(40, normalized.Width);
        Assert.Equal(20, normalized.Height);
    }

    [Fact]
    public void ScaleRect_scales_origin_and_size_together()
    {
        var rect = new RectD(10, 20, 30, 40);
        var scaled = DisplayGeometry.ScaleRect(rect, 2.0);

        Assert.Equal(new RectD(20, 40, 60, 80), scaled);
    }

    [Fact]
    public void PixelCoordinateForGlobalPoint_handles_a_display_with_negative_origin()
    {
        // A display placed left of the primary display has a negative X origin in global space.
        var displayFrame = new RectD(-1920, 0, 1920, 1080);
        var point = new PointD(-1000, 500);

        var coordinate = DisplayGeometry.PixelCoordinateForGlobalPoint(point, displayFrame, imageScale: 1.0);

        Assert.NotNull(coordinate);
        Assert.Equal(920, coordinate!.Value.X);
        Assert.Equal(500, coordinate.Value.Y);
    }

    [Fact]
    public void PixelCoordinateForGlobalPoint_applies_image_scale()
    {
        var displayFrame = new RectD(0, 0, 1000, 1000);
        var point = new PointD(100, 100);

        var coordinate = DisplayGeometry.PixelCoordinateForGlobalPoint(point, displayFrame, imageScale: 2.0);

        Assert.Equal(new PixelCoordinate(200, 200), coordinate);
    }

    [Fact]
    public void PixelCoordinateForGlobalPoint_returns_null_outside_the_display()
    {
        var displayFrame = new RectD(0, 0, 1000, 1000);
        Assert.Null(DisplayGeometry.PixelCoordinateForGlobalPoint(new PointD(-1, 500), displayFrame, 1.0));
        Assert.Null(DisplayGeometry.PixelCoordinateForGlobalPoint(new PointD(1000, 500), displayFrame, 1.0));
    }

    [Fact]
    public void PixelCoordinateForGlobalPoint_returns_null_for_non_finite_or_non_positive_inputs()
    {
        var displayFrame = new RectD(0, 0, 1000, 1000);
        Assert.Null(DisplayGeometry.PixelCoordinateForGlobalPoint(new PointD(double.NaN, 0), displayFrame, 1.0));
        Assert.Null(DisplayGeometry.PixelCoordinateForGlobalPoint(new PointD(0, 0), displayFrame, imageScale: 0));
        Assert.Null(DisplayGeometry.PixelCoordinateForGlobalPoint(new PointD(0, 0), displayFrame, imageScale: -1));
    }
}
