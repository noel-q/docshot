import Foundation

/// Why an edit was refused.
///
/// Every mutation on `VideoProject` either applies completely or throws one of these and leaves the
/// project untouched, so a rejected edit can never leave a half-applied timeline behind.
public enum VideoProjectError: Error, Equatable, Sendable, LocalizedError {
    case unknownSegment(UUID)
    case unknownAnnotation(UUID)
    /// The range is not finite, is negative, or is shorter than `VideoTimeRange.minimumDuration`.
    case invalidTimeRange
    case rangeOutsideSource(sourceDuration: TimeInterval)
    case timeOutsideTimeline(timelineDuration: TimeInterval)
    /// A split at (or within the minimum duration of) a segment edge would produce an empty piece.
    case splitAtSegmentBoundary
    /// The timeline must always render something.
    case cannotRemoveLastSegment
    case invalidSegmentPosition
    /// The annotation's visible range does not overlap the segment it is attached to.
    case annotationOutsideSegment

    public var errorDescription: String? {
        switch self {
        case .unknownSegment:
            return "That clip is no longer part of the timeline."
        case .unknownAnnotation:
            return "That annotation is no longer part of the project."
        case .invalidTimeRange:
            return "A clip must be at least \(String(format: "%.2f", VideoTimeRange.minimumDuration)) seconds long."
        case .rangeOutsideSource(let sourceDuration):
            return "That range falls outside the recording, which is \(String(format: "%.2f", sourceDuration)) seconds long."
        case .timeOutsideTimeline(let timelineDuration):
            return "That time falls outside the timeline, which is \(String(format: "%.2f", timelineDuration)) seconds long."
        case .splitAtSegmentBoundary:
            return "Split further from the edge of the clip: both halves need to be at least \(String(format: "%.2f", VideoTimeRange.minimumDuration)) seconds."
        case .cannotRemoveLastSegment:
            return "A project needs at least one clip. Discard the recording instead."
        case .invalidSegmentPosition:
            return "That is not a valid position in the timeline."
        case .annotationOutsideSegment:
            return "An annotation has to be visible somewhere inside the clip it belongs to."
        }
    }
}
