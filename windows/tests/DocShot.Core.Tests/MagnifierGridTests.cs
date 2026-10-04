using DocShot.Core.Models;
using Xunit;

namespace DocShot.Core.Tests;

public class MagnifierGridTests
{
    private static IReadOnlyList<IReadOnlyList<ColorSample?>> MakeFullGrid(ColorSample fill)
    {
        var rows = new List<IReadOnlyList<ColorSample?>>();
        for (var r = 0; r < MagnifierGrid.Dimension; r++)
        {
            var row = new List<ColorSample?>();
            for (var c = 0; c < MagnifierGrid.Dimension; c++)
            {
                row.Add(fill);
            }
            rows.Add(row);
        }
        return rows;
    }

    [Fact]
    public void CenterSample_returns_the_pixel_at_the_middle_of_a_full_grid()
    {
        var sample = new ColorSample(10, 20, 30);
        var grid = new MagnifierGrid(MakeFullGrid(sample), new PixelCoordinate(100, 100));

        Assert.Equal(sample, grid.CenterSample);
    }

    [Fact]
    public void CenterSample_returns_null_when_the_grid_is_smaller_than_expected()
    {
        var rows = new List<IReadOnlyList<ColorSample?>> { new List<ColorSample?> { new ColorSample(1, 1, 1) } };
        var grid = new MagnifierGrid(rows, new PixelCoordinate(0, 0));

        Assert.Null(grid.CenterSample);
    }

    [Fact]
    public void CenterSample_can_itself_be_null_representing_an_out_of_bounds_pixel()
    {
        var rows = new List<IReadOnlyList<ColorSample?>>();
        for (var r = 0; r < MagnifierGrid.Dimension; r++)
        {
            var row = new List<ColorSample?>();
            for (var c = 0; c < MagnifierGrid.Dimension; c++)
            {
                var isCenter = r == MagnifierGrid.CenterIndex && c == MagnifierGrid.CenterIndex;
                row.Add(isCenter ? null : new ColorSample(5, 5, 5));
            }
            rows.Add(row);
        }
        var grid = new MagnifierGrid(rows, new PixelCoordinate(0, 0));

        Assert.Null(grid.CenterSample);
    }
}
