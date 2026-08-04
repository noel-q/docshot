using DocShot.Core.Primitives;

namespace DocShot.Core.Models;

/// <summary>A pixel position inside a captured image, origin at the image's top-left pixel.</summary>
public readonly record struct PixelCoordinate(int X, int Y);

/// <summary>
/// Pure coordinate-conversion helpers.
/// </summary>
/// <remarks>
/// The macOS version also carries <c>cocoaToCGPoint</c>/<c>cgToCocoaPoint</c> conversions, because
/// AppKit's coordinate system is Y-up from the bottom-left of the main screen while Core Graphics
/// (and the captured image) is Y-down from the top-left - two coexisting systems need a bridge.
/// Windows has no equivalent split: screen coordinates, window coordinates, and image pixel rows
/// all agree on Y-down from the top-left, so that bridge simply has no Windows counterpart and is
/// not ported. <c>CropImage</c> and image-based pixel sampling are also not ported here for the
/// same reason as <see cref="ColorSample"/>: they need a concrete decoded-image type that belongs
/// in <c>DocShot.Platform</c>.
/// </remarks>
public static class DisplayGeometry
{
    /// <summary>Scales a rectangle by a scale factor (e.g. a display's DPI scale).</summary>
    public static RectD ScaleRect(RectD rect, double scale) =>
        new(rect.X * scale, rect.Y * scale, rect.Width * scale, rect.Height * scale);

    /// <summary>Normalises a rectangle so width and height are non-negative.</summary>
    public static RectD NormalizeRect(RectD rect)
    {
        var x = rect.X;
        var y = rect.Y;
        var w = rect.Width;
        var h = rect.Height;

        if (w < 0)
        {
            x += w;
            w = Math.Abs(w);
        }
        if (h < 0)
        {
            y += h;
            h = Math.Abs(h);
        }
        return new RectD(x, y, w, h);
    }

    /// <summary>
    /// Converts a point in global screen space to a pixel coordinate inside a single display's
    /// captured image. <c>pixel = floor((globalPoint - displayOrigin) * imageScale)</c>.
    /// Subtracting the display origin before scaling keeps a display placed left of or above the
    /// primary display (negative origin) correct.
    /// </summary>
    /// <param name="imageScale">
    /// The scale of the image being sampled, not necessarily the display's own DPI scale. Passing
    /// the wrong scale silently returns the wrong pixel - callers must pass the scale the image
    /// was actually captured at.
    /// </param>
    /// <returns><c>null</c> when the point falls outside the display or the inputs are not finite.</returns>
    public static PixelCoordinate? PixelCoordinateForGlobalPoint(
        PointD point,
        RectD displayFrame,
        double imageScale)
    {
        if (!double.IsFinite(point.X) || !double.IsFinite(point.Y) ||
            !double.IsFinite(displayFrame.X) || !double.IsFinite(displayFrame.Y) ||
            !double.IsFinite(displayFrame.Width) || !double.IsFinite(displayFrame.Height) ||
            !double.IsFinite(imageScale) || imageScale <= 0 ||
            displayFrame.Width <= 0 || displayFrame.Height <= 0)
        {
            return null;
        }

        var relativeX = point.X - displayFrame.X;
        var relativeY = point.Y - displayFrame.Y;

        if (relativeX < 0 || relativeY < 0 ||
            relativeX >= displayFrame.Width || relativeY >= displayFrame.Height)
        {
            return null;
        }

        return new PixelCoordinate(
            (int)Math.Floor(relativeX * imageScale),
            (int)Math.Floor(relativeY * imageScale));
    }
}
