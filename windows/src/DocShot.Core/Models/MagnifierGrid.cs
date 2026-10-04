namespace DocShot.Core.Models;

/// <summary>
/// A fixed 11x11 grid of sampled pixels surrounding a target pixel coordinate.
/// </summary>
/// <remarks>
/// Out-of-bounds pixels (e.g. near the edges of a display) are represented as <c>null</c>
/// elements within the 11x11 matrix, preserving the 11x11 structure with checkerboard padding
/// rather than clipping or altering grid dimensions. The pixel-sampling method that builds one of
/// these from a real image (macOS's <c>PixelSampler.sampleGrid</c>) is not ported here - it needs
/// a concrete decoded-image type, which belongs in <c>DocShot.Platform</c> once a bitmap library
/// is chosen. See the equivalent note on <c>Models/ColorSample.cs</c>.
/// </remarks>
public sealed class MagnifierGrid : IEquatable<MagnifierGrid>
{
    public const int Dimension = 11;
    public const int Radius = 5;
    public const int CenterIndex = 5; // Index 5 in 0...10 is the center.

    /// <summary>11 rows by 11 columns of pixel samples, indexed [row][column]. Row 0 is top
    /// (y - 5), column 0 is left (x - 5). The center pixel is at [5][5].</summary>
    public IReadOnlyList<IReadOnlyList<ColorSample?>> Pixels { get; }

    public PixelCoordinate CenterCoordinate { get; }

    public MagnifierGrid(IReadOnlyList<IReadOnlyList<ColorSample?>> pixels, PixelCoordinate centerCoordinate)
    {
        Pixels = pixels;
        CenterCoordinate = centerCoordinate;
    }

    public ColorSample? CenterSample
    {
        get
        {
            if (Pixels.Count <= CenterIndex) return null;
            var row = Pixels[CenterIndex];
            if (row.Count <= CenterIndex) return null;
            return row[CenterIndex];
        }
    }

    public bool Equals(MagnifierGrid? other)
    {
        if (other is null) return false;
        if (ReferenceEquals(this, other)) return true;
        if (CenterCoordinate != other.CenterCoordinate) return false;
        if (Pixels.Count != other.Pixels.Count) return false;
        for (var i = 0; i < Pixels.Count; i++)
        {
            if (!Pixels[i].SequenceEqual(other.Pixels[i])) return false;
        }
        return true;
    }

    public override bool Equals(object? obj) => Equals(obj as MagnifierGrid);
    public override int GetHashCode() => HashCode.Combine(CenterCoordinate, Pixels.Count);
}
