using DocShot.Core.Primitives;

namespace DocShot.Core.Models;

/// <summary>
/// Identity and geometry of one connected display, as needed to capture and sample it.
/// </summary>
/// <remarks>
/// This is the pure half of the macOS <c>DisplaySnapshot.swift</c> file - <c>DisplayDescriptor</c>
/// carries no image and is fully portable. The other half, <c>DisplaySnapshot</c> itself (a frozen
/// image of one display plus the descriptor, released when selection overlays close so DocShot
/// never accumulates a capture history), needs a concrete decoded-image type and belongs in
/// <c>DocShot.Platform</c> once a bitmap library is chosen - see the note on <c>ColorSample</c>.
/// </remarks>
public readonly record struct DisplayDescriptor(uint DisplayId, RectD FrameInScreen, double Scale)
{
    /// <summary>A display can only be captured if its geometry is finite and positive.</summary>
    public bool IsValid =>
        double.IsFinite(FrameInScreen.X) && double.IsFinite(FrameInScreen.Y) &&
        double.IsFinite(FrameInScreen.Width) && double.IsFinite(FrameInScreen.Height) &&
        FrameInScreen.Width > 0 && FrameInScreen.Height > 0 &&
        double.IsFinite(Scale) && Scale > 0;

    public int PixelWidth => IsValid ? (int)Math.Round(FrameInScreen.Width * Scale) : 0;

    public int PixelHeight => IsValid ? (int)Math.Round(FrameInScreen.Height * Scale) : 0;

    /// <summary>Decoded pixels a snapshot of this display would occupy. Zero when the display is invalid.</summary>
    public long PixelCount => (long)PixelWidth * PixelHeight;

    public bool ContainsGlobalPoint(PointD point)
    {
        if (!IsValid || !double.IsFinite(point.X) || !double.IsFinite(point.Y)) return false;
        var relativeX = point.X - FrameInScreen.X;
        var relativeY = point.Y - FrameInScreen.Y;
        return relativeX >= 0 && relativeY >= 0
            && relativeX < FrameInScreen.Width && relativeY < FrameInScreen.Height;
    }
}
