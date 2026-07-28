namespace DocShot.Core.Primitives;

/// <summary>
/// A point in a platform-neutral 2D space, double precision.
/// </summary>
/// <remarks>
/// The macOS model leans on <c>CGPoint</c>/<c>CGRect</c>/<c>CGSize</c> throughout. Those types
/// have no cross-platform .NET equivalent that doesn't also drag in a UI framework reference:
/// <c>System.Windows.Point</c>/<c>Rect</c> live in WindowsBase, which only ships for the
/// <c>net8.0-windows</c> TFM. Referencing it here would force <c>DocShot.Core</c> onto that TFM
/// too, which is exactly the dependency this project exists to avoid - see
/// <c>DocShot.Core.csproj</c>. These three structs are the deliberately small alternative.
/// </remarks>
public readonly record struct PointD(double X, double Y)
{
    public static readonly PointD Zero = new(0, 0);
}

public readonly record struct SizeD(double Width, double Height)
{
    public static readonly SizeD Zero = new(0, 0);
}

/// <summary>
/// A rectangle with an origin and size. Unlike <c>CGRect</c>, width/height are not implicitly
/// normalised - a negative width/height is meaningful during an in-progress drag selection and
/// is normalised explicitly via <see cref="DisplayGeometry.NormalizeRect"/> where it matters.
/// </summary>
public readonly record struct RectD(double X, double Y, double Width, double Height)
{
    public RectD(PointD origin, SizeD size) : this(origin.X, origin.Y, size.Width, size.Height) { }

    public static readonly RectD Zero = new(0, 0, 0, 0);

    public double MinX => X;
    public double MinY => Y;
    public double MaxX => X + Width;
    public double MaxY => Y + Height;

    public PointD Origin => new(X, Y);
    public SizeD Size => new(Width, Height);

    /// <summary>The overlap with another rectangle, or an empty rectangle at the origin if none.</summary>
    public RectD Intersect(RectD other)
    {
        var minX = Math.Max(MinX, other.MinX);
        var minY = Math.Max(MinY, other.MinY);
        var maxX = Math.Min(MaxX, other.MaxX);
        var maxY = Math.Min(MaxY, other.MaxY);
        if (maxX <= minX || maxY <= minY) return new RectD(0, 0, 0, 0);
        return new RectD(minX, minY, maxX - minX, maxY - minY);
    }

    public bool IsEmpty => Width <= 0 || Height <= 0;
}
