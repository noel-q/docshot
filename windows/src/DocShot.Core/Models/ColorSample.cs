namespace DocShot.Core.Models;

/// <summary>
/// A single sampled screen pixel, held as 8-bit sRGB components.
/// </summary>
/// <remarks>
/// Direct port of the macOS <c>ColorSample</c>: pure data and pure math, no capture, no clipboard,
/// no history. The image-sampling side (macOS's <c>PixelSampler</c>, which reads a pixel out of a
/// real <c>CGImage</c>) is deliberately not ported here - it needs a concrete decoded-image type,
/// which belongs in <c>DocShot.Platform</c> once a bitmap library (most likely SkiaSharp) is
/// chosen, not in this dependency-free project.
/// </remarks>
public readonly record struct ColorSample(byte Red, byte Green, byte Blue)
{
    public readonly record struct Hsl(int Hue, int Saturation, int Lightness);

    /// <summary>Uppercase <c>#RRGGBB</c>. Screen captures are opaque, so no alpha is reported.</summary>
    public string HexString => $"#{Red:X2}{Green:X2}{Blue:X2}";

    public string RgbString => $"rgb({Red}, {Green}, {Blue})";

    public string HslString
    {
        get
        {
            var hsl = Hsl_;
            return $"hsl({hsl.Hue}, {hsl.Saturation}%, {hsl.Lightness}%)";
        }
    }

    /// <summary>
    /// Converts the stored sRGB components to HSL, rounded to integers. Hue is undefined for
    /// achromatic colours and reported as 0. A hue that rounds up to 360 wraps back to 0, so the
    /// reported range is always 0...359.
    /// </summary>
    public Hsl Hsl_
    {
        get
        {
            var r = Red / 255.0;
            var g = Green / 255.0;
            var b = Blue / 255.0;

            var max = Math.Max(r, Math.Max(g, b));
            var min = Math.Min(r, Math.Min(g, b));
            var delta = max - min;
            var lightness = (max + min) / 2.0;

            if (delta <= 0)
            {
                return new Hsl(0, 0, (int)Math.Round(lightness * 100));
            }

            var saturation = lightness > 0.5
                ? delta / (2.0 - max - min)
                : delta / (max + min);

            double hue;
            if (max == r) hue = (g - b) / delta;
            else if (max == g) hue = 2.0 + (b - r) / delta;
            else hue = 4.0 + (r - g) / delta;

            hue *= 60.0;
            if (hue < 0) hue += 360.0;

            var roundedHue = (int)Math.Round(hue);
            if (roundedHue >= 360) roundedHue -= 360;

            return new Hsl(roundedHue, (int)Math.Round(saturation * 100), (int)Math.Round(lightness * 100));
        }
    }
}
