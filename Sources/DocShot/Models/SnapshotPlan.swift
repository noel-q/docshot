import Foundation
import CoreGraphics

/// Decides which displays get a snapshot within a fixed decoded-pixel budget.
///
/// Displays are considered largest-first, so a very large display cannot be starved by smaller
/// ones enumerated ahead of it. A display that does not fit is skipped entirely: it is never
/// captured at a reduced scale, because reporting interpolated colours from a Retina display
/// would be worse than reporting no colour at all.
public struct SnapshotPlan: Equatable, Sendable {
    /// Displays that will be snapshotted, in the order they were supplied.
    public let included: [DisplayDescriptor]
    /// Displays that will not be snapshotted, in the order they were supplied. Sampling is
    /// reported as unavailable on these; selection and capture still work normally.
    public let excluded: [DisplayDescriptor]

    /// Total decoded-pixel budget across all displays in one selection session.
    public static let memoryBudgetBytes = 512 * 1024 * 1024
    public static let bytesPerPixel = 4
    /// 134,217,728 pixels.
    public static let maximumPixelCount = SnapshotPlan.memoryBudgetBytes / SnapshotPlan.bytesPerPixel

    public init(included: [DisplayDescriptor], excluded: [DisplayDescriptor]) {
        self.included = included
        self.excluded = excluded
    }

    public var totalPixelCount: Int {
        included.reduce(0) { $0 + $1.pixelCount }
    }

    public var estimatedBytes: Int {
        totalPixelCount * SnapshotPlan.bytesPerPixel
    }

    public func includes(_ displayID: CGDirectDisplayID) -> Bool {
        included.contains { $0.displayID == displayID }
    }

    /// Builds the plan for a set of displays. Invalid descriptors are always excluded.
    public static func make(for displays: [DisplayDescriptor]) -> SnapshotPlan {
        // Largest first, with displayID as a tie-break so the plan is deterministic.
        let ordered = displays.sorted { lhs, rhs in
            if lhs.pixelCount != rhs.pixelCount { return lhs.pixelCount > rhs.pixelCount }
            return lhs.displayID < rhs.displayID
        }

        var includedIDs: Set<CGDirectDisplayID> = []
        var consumedPixels = 0

        for descriptor in ordered {
            guard descriptor.isValid, descriptor.pixelCount > 0 else { continue }
            guard consumedPixels <= maximumPixelCount - descriptor.pixelCount else { continue }

            consumedPixels += descriptor.pixelCount
            includedIDs.insert(descriptor.displayID)
        }

        // Report in the caller's original order; the budget decision above is order-independent.
        return SnapshotPlan(
            included: displays.filter { includedIDs.contains($0.displayID) },
            excluded: displays.filter { !includedIDs.contains($0.displayID) }
        )
    }
}
