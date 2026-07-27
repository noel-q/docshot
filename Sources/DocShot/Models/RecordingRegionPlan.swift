import Foundation
import CoreGraphics

/// Decides whether a selected region can be recorded, and how it maps onto one display's
/// ScreenCaptureKit source rectangle.
///
/// R1 records a region only when it lies wholly within a single display. Anything else is
/// rejected with a reason the UI shows, because the alternatives — cropping to one display or
/// stretching a composite — would record something the user did not select.
///
/// The output pixel size is `points × that display's scale`, rounded to the nearest whole pixel
/// and otherwise preserved exactly. Odd dimensions are kept: the selected size is the promise.
public enum RecordingRegionPlan: Equatable, Sendable {
    case ok(displayID: CGDirectDisplayID, sourceRectInPoints: CGRect, outputPixelSize: CGSize)
    case rejected(RecordingTargetRejection)

    /// Smallest region side R1 accepts, in points.
    public static let minimumSideInPoints: CGFloat = 16

    /// - Parameters:
    ///   - globalRectInCG: the selection in global Core Graphics space (origin top-left of the
    ///     main display, Y down), as produced by `DisplayGeometry.cocoaToCGRect`.
    ///   - displays: every connected display, at its own backing scale.
    public static func make(
        globalRectInCG rect: CGRect,
        displays: [DisplayDescriptor]
    ) -> RecordingRegionPlan {
        let normalized = DisplayGeometry.normalizeRect(rect)

        guard normalized.origin.x.isFinite, normalized.origin.y.isFinite,
              normalized.width.isFinite, normalized.height.isFinite,
              normalized.width > 0, normalized.height > 0 else {
            return .rejected(.invalidGeometry)
        }

        guard normalized.width >= minimumSideInPoints, normalized.height >= minimumSideInPoints else {
            return .rejected(.tooSmall)
        }

        let usableDisplays = displays.filter(\.isValid)

        // Mirrored displays can share a frame. Lowest display ID wins so the plan is deterministic.
        let containing = usableDisplays
            .filter { $0.frameInCG.contains(normalized) }
            .sorted { $0.displayID < $1.displayID }

        guard let display = containing.first else {
            let overlapping = usableDisplays.filter { !$0.frameInCG.intersection(normalized).isNull }
            return .rejected(overlapping.count > 1 ? .spansMultipleDisplays : .noContainingDisplay)
        }

        let sourceRect = CGRect(
            x: normalized.origin.x - display.frameInCG.origin.x,
            y: normalized.origin.y - display.frameInCG.origin.y,
            width: normalized.width,
            height: normalized.height
        )

        let pixelWidth = (normalized.width * display.scale).rounded()
        let pixelHeight = (normalized.height * display.scale).rounded()

        guard pixelWidth >= 1, pixelHeight >= 1 else {
            return .rejected(.tooSmall)
        }

        return .ok(
            displayID: display.displayID,
            sourceRectInPoints: sourceRect,
            outputPixelSize: CGSize(width: pixelWidth, height: pixelHeight)
        )
    }

    /// The recording target this plan describes, or `nil` when the selection was rejected.
    public var target: RecordingTarget? {
        guard case .ok(let displayID, let sourceRect, let outputSize) = self else { return nil }
        return .region(displayID: displayID, rectInDisplay: sourceRect, outputSize: outputSize)
    }

    public var rejection: RecordingTargetRejection? {
        guard case .rejected(let reason) = self else { return nil }
        return reason
    }
}
