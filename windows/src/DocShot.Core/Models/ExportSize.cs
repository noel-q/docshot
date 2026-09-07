using DocShot.Core.Primitives;

namespace DocShot.Core.Models;

/// <summary>Why a requested export size could not be turned into concrete output pixel dimensions.</summary>
public abstract record ExportSizeError
{
    /// <summary>The image being exported reported non-positive or non-finite pixel dimensions.</summary>
    public sealed record InvalidSourceSize : ExportSizeError;

    /// <summary>The requested percentage or pixel dimensions were non-positive or non-finite.</summary>
    public sealed record InvalidRequestedSize : ExportSizeError;

    /// <summary>The requested dimensions would allocate more decoded pixels than DocShot permits.</summary>
    public sealed record ExceedsMemoryBudget(long RequestedPixelCount, long BudgetPixelCount) : ExportSizeError;

    private ExportSizeError() { }

    public string Message => this switch
    {
        InvalidSourceSize => "The screenshot has no valid pixel dimensions to resize from.",
        InvalidRequestedSize => "Enter a size larger than zero.",
        ExceedsMemoryBudget e => $"That size needs {e.RequestedPixelCount} pixels, above DocShot's {e.BudgetPixelCount} pixel export limit.",
        _ => "Unknown export size error."
    };
}

/// <summary>
/// An explicit output size for an export. Resizing is applied only at Copy/Save; the editor
/// always keeps the capture at its native resolution.
/// </summary>
public abstract record ExportSize
{
    /// <summary>Export at the flattened image's own pixel dimensions. No resampling occurs.</summary>
    public sealed record Native : ExportSize;

    /// <summary>Export at a percentage of the flattened image, where 100 is native size.</summary>
    public sealed record Percent(double Value) : ExportSize;

    /// <summary>Export at explicit pixel dimensions.</summary>
    public sealed record Pixels(double Width, double Height) : ExportSize;

    private ExportSize() { }

    public static readonly ExportSize NativeSize = new Native();

    /// <summary>Decoded-pixel memory budget for a single export (512 MB at 4 bytes per pixel).</summary>
    public const long MemoryBudgetBytes = 512L * 1024 * 1024;
    public const long BytesPerPixel = 4;

    /// <summary>Largest number of output pixels an export may allocate: 134,217,728 (~11,585 x 11,585).</summary>
    public const long MaximumPixelCount = MemoryBudgetBytes / BytesPerPixel;

    public bool IsNative => this is Native;

    /// <summary>
    /// Turns this size into concrete output pixel dimensions for a given flattened source size.
    /// Dimensions are rounded half-away-from-zero and never fall below 1px. <see cref="Native"/>
    /// is always accepted: the image already exists at that size, so it is not subject to the
    /// export memory budget.
    /// </summary>
    public Result<SizeD, ExportSizeError> Resolve(SizeD sourceSize)
    {
        var sourceWidth = sourceSize.Width;
        var sourceHeight = sourceSize.Height;

        if (!double.IsFinite(sourceWidth) || !double.IsFinite(sourceHeight) || sourceWidth <= 0 || sourceHeight <= 0)
        {
            return Result<SizeD, ExportSizeError>.Failure(new ExportSizeError.InvalidSourceSize());
        }

        double requestedWidth;
        double requestedHeight;

        switch (this)
        {
            case Native:
                return Result<SizeD, ExportSizeError>.Success(
                    new SizeD(RoundedPixels(sourceWidth), RoundedPixels(sourceHeight)));

            case Percent p:
                if (!double.IsFinite(p.Value) || p.Value <= 0)
                {
                    return Result<SizeD, ExportSizeError>.Failure(new ExportSizeError.InvalidRequestedSize());
                }
                requestedWidth = sourceWidth * p.Value / 100.0;
                requestedHeight = sourceHeight * p.Value / 100.0;
                break;

            case Pixels px:
                if (!double.IsFinite(px.Width) || !double.IsFinite(px.Height) || px.Width <= 0 || px.Height <= 0)
                {
                    return Result<SizeD, ExportSizeError>.Failure(new ExportSizeError.InvalidRequestedSize());
                }
                requestedWidth = px.Width;
                requestedHeight = px.Height;
                break;

            default:
                throw new InvalidOperationException("Unreachable ExportSize case.");
        }

        var outputWidth = RoundedPixels(requestedWidth);
        var outputHeight = RoundedPixels(requestedHeight);
        var pixelCount = outputWidth * outputHeight;

        if (pixelCount > MaximumPixelCount)
        {
            var reported = pixelCount < long.MaxValue ? (long)pixelCount : long.MaxValue;
            return Result<SizeD, ExportSizeError>.Failure(
                new ExportSizeError.ExceedsMemoryBudget(reported, MaximumPixelCount));
        }

        return Result<SizeD, ExportSizeError>.Success(new SizeD(outputWidth, outputHeight));
    }

    /// <summary>Rounds a pixel dimension half-away-from-zero and clamps it to at least one pixel.</summary>
    public static double RoundedPixels(double value)
    {
        if (!double.IsFinite(value)) return 1;
        return Math.Max(1, Math.Round(value, MidpointRounding.AwayFromZero));
    }

    /// <summary>The height that preserves <paramref name="sourceSize"/>'s aspect ratio for a chosen output width.</summary>
    public static double? AspectLockedHeight(double width, SizeD sourceSize)
    {
        if (!double.IsFinite(width) || width <= 0 ||
            !double.IsFinite(sourceSize.Width) || !double.IsFinite(sourceSize.Height) ||
            sourceSize.Width <= 0 || sourceSize.Height <= 0)
        {
            return null;
        }
        return RoundedPixels(width * sourceSize.Height / sourceSize.Width);
    }

    /// <summary>The width that preserves <paramref name="sourceSize"/>'s aspect ratio for a chosen output height.</summary>
    public static double? AspectLockedWidth(double height, SizeD sourceSize)
    {
        if (!double.IsFinite(height) || height <= 0 ||
            !double.IsFinite(sourceSize.Width) || !double.IsFinite(sourceSize.Height) ||
            sourceSize.Width <= 0 || sourceSize.Height <= 0)
        {
            return null;
        }
        return RoundedPixels(height * sourceSize.Width / sourceSize.Height);
    }
}

/// <summary>
/// A minimal success/failure result type, standing in for Swift's <c>Result</c>. Not a general
/// utility library - just enough to keep <see cref="ExportSize.Resolve"/> a faithful port.
/// </summary>
public readonly struct Result<TValue, TError>
{
    public bool IsSuccess { get; }
    private readonly TValue? _value;
    private readonly TError? _error;

    private Result(bool isSuccess, TValue? value, TError? error)
    {
        IsSuccess = isSuccess;
        _value = value;
        _error = error;
    }

    public static Result<TValue, TError> Success(TValue value) => new(true, value, default);
    public static Result<TValue, TError> Failure(TError error) => new(false, default, error);

    public TValue Value => IsSuccess ? _value! : throw new InvalidOperationException("Result has no value.");
    public TError Error => !IsSuccess ? _error! : throw new InvalidOperationException("Result has no error.");
}
