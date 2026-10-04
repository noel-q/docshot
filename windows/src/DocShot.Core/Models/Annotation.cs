using DocShot.Core.Primitives;

namespace DocShot.Core.Models;

public enum RedactionStyle
{
    Blur,
    Pixelate
}

/// <summary>
/// A colour, held as normalised (0...1) RGBA components.
/// </summary>
/// <remarks>
/// The macOS <c>CodableColor</c> also carries an <c>NSColor</c>/SwiftUI <c>Color</c> bridge
/// constructor. That bridge is deliberately not ported here: converting to/from
/// <c>System.Windows.Media.Color</c> needs WindowsBase, which is a <c>net8.0-windows</c>-only
/// dependency (see <c>Primitives/Geometry.cs</c> for the same reasoning). That conversion belongs
/// in <c>DocShot.App</c>, as a small extension method next to wherever WPF colours are used.
/// </remarks>
public readonly record struct RgbaColor(double R, double G, double B, double A = 1.0)
{
    public static readonly RgbaColor Red = new(0.9, 0.2, 0.2);
    public static readonly RgbaColor Green = new(0.2, 0.8, 0.3);
    public static readonly RgbaColor Blue = new(0.2, 0.5, 0.9);
    public static readonly RgbaColor Yellow = new(0.95, 0.8, 0.1);
    public static readonly RgbaColor Orange = new(0.95, 0.5, 0.1);
    public static readonly RgbaColor White = new(1.0, 1.0, 1.0);
    public static readonly RgbaColor Black = new(0.0, 0.0, 0.0);
    public static readonly RgbaColor HighlighterYellow = new(1.0, 0.9, 0.0, 0.4);
}

/// <summary>
/// One annotation's shape and geometry, as a closed hierarchy of sealed records - C# has no
/// built-in discriminated union yet, so this is the idiomatic stand-in for Swift's
/// <c>enum AnnotationType</c> with associated values. Pattern-match with a <c>switch</c>
/// expression, exactly as the macOS code switches over the Swift enum.
/// </summary>
public abstract record AnnotationShape
{
    public sealed record Arrow(PointD Start, PointD End) : AnnotationShape;
    public sealed record Rectangle(RectD Rect, bool IsFilled) : AnnotationShape;
    public sealed record Ellipse(RectD Rect, bool IsFilled) : AnnotationShape;
    public sealed record Text(RectD Rect, string TextValue, double FontSize) : AnnotationShape;
    public sealed record Highlighter(IReadOnlyList<PointD> Points) : AnnotationShape;
    public sealed record Redaction(RectD Rect, RedactionStyle Style) : AnnotationShape;

    private AnnotationShape() { }

    /// <summary>Bounding rectangle for selection hit-testing and dragging.</summary>
    public RectD BoundingBox => this switch
    {
        Arrow a => BoundingBoxOfArrow(a),
        Rectangle r => DisplayGeometry.NormalizeRect(r.Rect),
        Ellipse e => DisplayGeometry.NormalizeRect(e.Rect),
        Redaction rd => DisplayGeometry.NormalizeRect(rd.Rect),
        Text t => DisplayGeometry.NormalizeRect(t.Rect),
        Highlighter h => BoundingBoxOfHighlighter(h),
        _ => RectD.Zero
    };

    private static RectD BoundingBoxOfArrow(Arrow a)
    {
        var minX = Math.Min(a.Start.X, a.End.X);
        var maxX = Math.Max(a.Start.X, a.End.X);
        var minY = Math.Min(a.Start.Y, a.End.Y);
        var maxY = Math.Max(a.Start.Y, a.End.Y);
        return new RectD(minX, minY, Math.Max(maxX - minX, 10), Math.Max(maxY - minY, 10));
    }

    private static RectD BoundingBoxOfHighlighter(Highlighter h)
    {
        if (h.Points.Count == 0) return RectD.Zero;
        var minX = h.Points[0].X; var maxX = h.Points[0].X;
        var minY = h.Points[0].Y; var maxY = h.Points[0].Y;
        foreach (var p in h.Points)
        {
            minX = Math.Min(minX, p.X); maxX = Math.Max(maxX, p.X);
            minY = Math.Min(minY, p.Y); maxY = Math.Max(maxY, p.Y);
        }
        return new RectD(minX, minY, Math.Max(maxX - minX, 10), Math.Max(maxY - minY, 10));
    }

    /// <summary>Returns a copy of this shape moved by a delta offset.</summary>
    public AnnotationShape Translated(SizeD delta) => this switch
    {
        Arrow a => new Arrow(
            new PointD(a.Start.X + delta.Width, a.Start.Y + delta.Height),
            new PointD(a.End.X + delta.Width, a.End.Y + delta.Height)),
        Rectangle r => new Rectangle(Translate(r.Rect, delta), r.IsFilled),
        Ellipse e => new Ellipse(Translate(e.Rect, delta), e.IsFilled),
        Text t => new Text(Translate(t.Rect, delta), t.TextValue, t.FontSize),
        Highlighter h => new Highlighter(h.Points.Select(p => new PointD(p.X + delta.Width, p.Y + delta.Height)).ToList()),
        Redaction rd => new Redaction(Translate(rd.Rect, delta), rd.Style),
        _ => this
    };

    private static RectD Translate(RectD rect, SizeD delta) =>
        new(rect.X + delta.Width, rect.Y + delta.Height, rect.Width, rect.Height);
}

public sealed record AnnotationItem(
    Guid Id,
    AnnotationShape Shape,
    RgbaColor Color,
    double StrokeWidth = 3.0)
{
    public AnnotationItem(AnnotationShape shape, RgbaColor? color = null, double strokeWidth = 3.0)
        : this(Guid.NewGuid(), shape, color ?? RgbaColor.Red, strokeWidth) { }

    public RectD BoundingBox => Shape.BoundingBox;

    /// <summary>Returns a copy of this annotation moved by a delta offset.</summary>
    public AnnotationItem Translated(SizeD delta) => this with { Shape = Shape.Translated(delta) };
}
