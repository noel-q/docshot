import Foundation
import CoreGraphics

/// What one recording session captures.
///
/// A target is resolved once, before the stream starts, and stays immutable for the lifetime of
/// that session. Recording never re-derives its bounds from a moving selection.
public enum RecordingTarget: Equatable, Sendable {
    /// A single application window, identified by the ID window discovery reported.
    ///
    /// `boundsInCG` is the bounds observed at selection time. It is used for the confirmation UI
    /// and as a fallback size; the live `SCWindow` is re-resolved immediately before capture, so
    /// a window that moved or closed in between is caught rather than recorded at stale bounds.
    case window(id: CGWindowID, boundsInCG: CGRect)

    /// A rectangle lying wholly within one display.
    ///
    /// `rectInDisplay` is in points, relative to that display's top-left origin — the same
    /// convention `SCStreamConfiguration.sourceRect` uses. `outputSize` is the exact pixel size
    /// the recording must have; R1 preserves it rather than rounding it to convenient values.
    case region(displayID: CGDirectDisplayID, rectInDisplay: CGRect, outputSize: CGSize)
}

/// Why a selection cannot become a recording target.
///
/// Every case is user-visible: R1 explains the limitation instead of silently cropping,
/// stretching, or recording something other than what was selected.
public enum RecordingTargetRejection: Error, Equatable, Sendable {
    /// The region overlaps more than one display. Multi-display recording is deferred.
    case spansMultipleDisplays
    /// The region is not wholly contained by any single display.
    case noContainingDisplay
    /// The region is smaller than the encoder can usefully record.
    case tooSmall
    /// The region's geometry is not finite or has no area.
    case invalidGeometry
    /// The selected window no longer exists, or is no longer shareable.
    case windowUnavailable

    public var message: String {
        switch self {
        case .spansMultipleDisplays:
            return "DocShot records a region on one display at a time. Select a region that stays within a single display."
        case .noContainingDisplay:
            return "The selected region must lie entirely within one display."
        case .tooSmall:
            return "The selected region is too small to record. Select at least \(Int(RecordingRegionPlan.minimumSideInPoints)) × \(Int(RecordingRegionPlan.minimumSideInPoints)) points."
        case .invalidGeometry:
            return "The selected region does not describe a valid rectangle."
        case .windowUnavailable:
            return "That window is no longer available to record. Select it again."
        }
    }
}
