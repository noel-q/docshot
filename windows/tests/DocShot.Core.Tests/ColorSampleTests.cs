using DocShot.Core.Models;
using Xunit;

namespace DocShot.Core.Tests;

public class ColorSampleTests
{
    [Fact]
    public void Hex_string_is_uppercase_RRGGBB()
    {
        var sample = new ColorSample(255, 0, 128);
        Assert.Equal("#FF0080", sample.HexString);
    }

    [Fact]
    public void Rgb_string_matches_components()
    {
        var sample = new ColorSample(10, 20, 30);
        Assert.Equal("rgb(10, 20, 30)", sample.RgbString);
    }

    [Fact]
    public void Pure_red_converts_to_expected_hsl()
    {
        var sample = new ColorSample(255, 0, 0);
        var hsl = sample.Hsl_;
        Assert.Equal(0, hsl.Hue);
        Assert.Equal(100, hsl.Saturation);
        Assert.Equal(50, hsl.Lightness);
    }

    [Fact]
    public void Achromatic_grey_has_zero_hue_and_saturation()
    {
        var sample = new ColorSample(128, 128, 128);
        var hsl = sample.Hsl_;
        Assert.Equal(0, hsl.Hue);
        Assert.Equal(0, hsl.Saturation);
    }

    [Fact]
    public void White_and_black_resolve_to_expected_lightness()
    {
        Assert.Equal(100, new ColorSample(255, 255, 255).Hsl_.Lightness);
        Assert.Equal(0, new ColorSample(0, 0, 0).Hsl_.Lightness);
    }

    [Fact]
    public void Hue_never_reports_360_it_wraps_to_zero()
    {
        // Pure red with a hue calculation that rounds up to 360 must wrap to 0, not report 360,
        // so the documented range 0...359 holds for every input.
        var sample = new ColorSample(255, 1, 1);
        Assert.InRange(sample.Hsl_.Hue, 0, 359);
    }
}
