import Foundation

/// A half-open time range, in seconds: `[start, start + duration)`.
///
/// Seconds rather than `CMTime` so the whole project model stays pure Foundation and runs in the
/// hostless test bundle. Conversion to `CMTime` happens once, at the export boundary, against a
/// documented timescale — see `VideoProjectExportService`.
public struct VideoTimeRange: Equatable, Sendable {
    public var start: TimeInterval
    public var duration: TimeInterval

    /// The shortest range the editor will create. Anything below this is a mis-drag rather than an
    /// intended edit, and a zero-length segment would export as nothing at all.
    public static let minimumDuration: TimeInterval = 0.05

    public init(start: TimeInterval, duration: TimeInterval) {
        self.start = start
        self.duration = duration
    }

    public static func between(start: TimeInterval, end: TimeInterval) -> VideoTimeRange {
        VideoTimeRange(start: start, duration: end - start)
    }

    public var end: TimeInterval {
        start + duration
    }

    /// Finite, non-negative, and long enough to be a deliberate edit.
    public var isValid: Bool {
        start.isFinite && duration.isFinite && start >= 0 && duration >= VideoTimeRange.minimumDuration
    }

    /// Finite and non-negative, but allowed to be shorter than `minimumDuration`.
    ///
    /// Derived ranges — an annotation clipped by a split, for instance — can legitimately end up
    /// very short. Only ranges the user asks for directly must clear `isValid`.
    public var isWellFormed: Bool {
        start.isFinite && duration.isFinite && start >= 0 && duration > 0
    }

    public func contains(_ time: TimeInterval) -> Bool {
        time >= start && time < end
    }

    public func intersects(_ other: VideoTimeRange) -> Bool {
        start < other.end && other.start < end
    }

    /// The overlap with another range, or `nil` when they do not overlap at all.
    public func intersection(_ other: VideoTimeRange) -> VideoTimeRange? {
        let lower = Swift.max(start, other.start)
        let upper = Swift.min(end, other.end)
        guard upper > lower else { return nil }
        return VideoTimeRange(start: lower, duration: upper - lower)
    }

    public func shifted(by offset: TimeInterval) -> VideoTimeRange {
        VideoTimeRange(start: start + offset, duration: duration)
    }
}
