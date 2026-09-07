using DocShot.Core.Primitives;

namespace DocShot.Core.Models;

/// <summary>
/// A finished recording that exists only in DocShot's private temporary directory.
/// </summary>
/// <remarks>
/// Not a history item and never presented as a library entry. It exists between Stop and the
/// user's explicit Save or Discard, and every terminal path removes it. Deliberately free of any
/// Media Foundation / capture types so it stays testable in <c>DocShot.Core.Tests</c> with no
/// Windows dependency at all.
/// </remarks>
public sealed record TemporaryRecording(
    Uri Url,
    double Duration,
    SizeD PixelSize,
    bool HasAudio,
    DateTimeOffset CreatedAt)
{
    /// <summary>A recording is only offered to the user when it describes real, finite media.</summary>
    public bool IsPlayable =>
        double.IsFinite(Duration) && Duration > 0
        && PixelSize.Width >= 1 && PixelSize.Height >= 1
        && double.IsFinite(PixelSize.Width) && double.IsFinite(PixelSize.Height);
}
