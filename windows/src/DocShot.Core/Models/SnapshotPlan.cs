namespace DocShot.Core.Models;

/// <summary>
/// Decides which displays get a snapshot within a fixed decoded-pixel budget.
/// </summary>
/// <remarks>
/// Displays are considered largest-first, so a very large display cannot be starved by smaller
/// ones enumerated ahead of it. A display that does not fit is skipped entirely: it is never
/// captured at a reduced scale, because reporting interpolated colours from a high-DPI display
/// would be worse than reporting no colour at all.
/// </remarks>
public sealed class SnapshotPlan : IEquatable<SnapshotPlan>
{
    /// <summary>Displays that will be snapshotted, in the order they were supplied.</summary>
    public IReadOnlyList<DisplayDescriptor> Included { get; }

    /// <summary>Displays that will not be snapshotted, in the order they were supplied. Sampling is
    /// reported as unavailable on these; selection and capture still work normally.</summary>
    public IReadOnlyList<DisplayDescriptor> Excluded { get; }

    /// <summary>Total decoded-pixel budget across all displays in one selection session.</summary>
    public const long MemoryBudgetBytes = 512L * 1024 * 1024;
    public const long BytesPerPixel = 4;

    /// <summary>134,217,728 pixels.</summary>
    public const long MaximumPixelCount = MemoryBudgetBytes / BytesPerPixel;

    public SnapshotPlan(IReadOnlyList<DisplayDescriptor> included, IReadOnlyList<DisplayDescriptor> excluded)
    {
        Included = included;
        Excluded = excluded;
    }

    public long TotalPixelCount => Included.Sum(d => d.PixelCount);

    public long EstimatedBytes => TotalPixelCount * BytesPerPixel;

    public bool Includes(uint displayId) => Included.Any(d => d.DisplayId == displayId);

    /// <summary>Builds the plan for a set of displays. Invalid descriptors are always excluded.</summary>
    public static SnapshotPlan Make(IReadOnlyList<DisplayDescriptor> displays)
    {
        // Largest first, with DisplayId as a tie-break so the plan is deterministic.
        var ordered = displays
            .OrderByDescending(d => d.PixelCount)
            .ThenBy(d => d.DisplayId)
            .ToList();

        var includedIds = new HashSet<uint>();
        long consumedPixels = 0;

        foreach (var descriptor in ordered)
        {
            if (!descriptor.IsValid || descriptor.PixelCount <= 0) continue;
            if (consumedPixels > MaximumPixelCount - descriptor.PixelCount) continue;

            consumedPixels += descriptor.PixelCount;
            includedIds.Add(descriptor.DisplayId);
        }

        // Report in the caller's original order; the budget decision above is order-independent.
        return new SnapshotPlan(
            displays.Where(d => includedIds.Contains(d.DisplayId)).ToList(),
            displays.Where(d => !includedIds.Contains(d.DisplayId)).ToList());
    }

    public bool Equals(SnapshotPlan? other)
    {
        if (other is null) return false;
        if (ReferenceEquals(this, other)) return true;
        return Included.SequenceEqual(other.Included) && Excluded.SequenceEqual(other.Excluded);
    }

    public override bool Equals(object? obj) => Equals(obj as SnapshotPlan);
    public override int GetHashCode() => HashCode.Combine(Included.Count, Excluded.Count);
}
