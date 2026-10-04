using DocShot.Core.Models;
using DocShot.Core.Primitives;
using Xunit;

namespace DocShot.Core.Tests;

public class AnnotationTests
{
    [Fact]
    public void Arrow_bounding_box_covers_both_endpoints_with_a_minimum_hit_area()
    {
        var arrow = new AnnotationShape.Arrow(new PointD(10, 10), new PointD(50, 40));
        var box = arrow.BoundingBox;

        Assert.Equal(10, box.X);
        Assert.Equal(10, box.Y);
        Assert.Equal(40, box.Width);
        Assert.Equal(30, box.Height);
    }

    [Fact]
    public void Arrow_bounding_box_has_a_minimum_size_for_near_horizontal_or_vertical_arrows()
    {
        // A perfectly horizontal arrow would otherwise have zero height and be impossible to hit-test.
        var arrow = new AnnotationShape.Arrow(new PointD(0, 0), new PointD(100, 0));
        var box = arrow.BoundingBox;

        Assert.True(box.Height >= 10);
    }

    [Fact]
    public void Rectangle_bounding_box_is_normalized()
    {
        var rectangle = new AnnotationShape.Rectangle(new RectD(50, 50, -20, -20), IsFilled: false);
        var box = rectangle.BoundingBox;

        Assert.Equal(30, box.X);
        Assert.Equal(30, box.Y);
        Assert.Equal(20, box.Width);
        Assert.Equal(20, box.Height);
    }

    [Fact]
    public void Highlighter_bounding_box_covers_every_point()
    {
        var highlighter = new AnnotationShape.Highlighter([new PointD(0, 0), new PointD(30, 5), new PointD(10, 40)]);
        var box = highlighter.BoundingBox;

        Assert.Equal(0, box.X);
        Assert.Equal(0, box.Y);
        Assert.Equal(30, box.Width);
        Assert.Equal(40, box.Height);
    }

    [Fact]
    public void Translate_moves_an_arrow_by_the_delta()
    {
        var arrow = new AnnotationShape.Arrow(new PointD(0, 0), new PointD(10, 10));
        var moved = Assert.IsType<AnnotationShape.Arrow>(arrow.Translated(new SizeD(5, -5)));

        Assert.Equal(new PointD(5, -5), moved.Start);
        Assert.Equal(new PointD(15, 5), moved.End);
    }

    [Fact]
    public void Translate_moves_every_point_of_a_highlighter_stroke()
    {
        var highlighter = new AnnotationShape.Highlighter([new PointD(0, 0), new PointD(10, 10)]);
        var moved = Assert.IsType<AnnotationShape.Highlighter>(highlighter.Translated(new SizeD(2, 3)));

        Assert.Equal(new PointD(2, 3), moved.Points[0]);
        Assert.Equal(new PointD(12, 13), moved.Points[1]);
    }

    [Fact]
    public void AnnotationItem_translated_only_moves_its_shape_and_keeps_identity()
    {
        var item = new AnnotationItem(new AnnotationShape.Rectangle(new RectD(0, 0, 10, 10), true), RgbaColor.Blue, 4.0);
        var moved = item.Translated(new SizeD(5, 5));

        Assert.Equal(item.Id, moved.Id);
        Assert.Equal(item.Color, moved.Color);
        Assert.Equal(item.StrokeWidth, moved.StrokeWidth);
        var rect = Assert.IsType<AnnotationShape.Rectangle>(moved.Shape);
        Assert.Equal(new RectD(5, 5, 10, 10), rect.Rect);
    }
}
