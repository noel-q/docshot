import AppKit
import CoreGraphics

/// Turns what the user selected on the overlay into a recording target, reusing the screenshot
/// pipeline's window discovery and coordinate helpers through a read-only seam.
///
/// Nothing here mutates screenshot state, and neither `WindowDiscoveryService` nor
/// `DisplayGeometry` learns anything about recording.
@MainActor
enum RecordingSelectionAdapter {
    /// Eligible windows, with DocShot's own windows already excluded by discovery.
    static func eligibleWindows() -> [WindowInfo] {
        WindowDiscoveryService.shared.getEligibleWindows()
    }

    static func target(forWindow window: WindowInfo) -> Result<RecordingTarget, RecordingTargetRejection> {
        guard window.boundsInCG.width >= 1, window.boundsInCG.height >= 1 else {
            return .failure(.windowUnavailable)
        }
        return .success(.window(id: window.id, boundsInCG: window.boundsInCG))
    }

    /// - Parameter cocoaRect: the dragged rectangle in global Cocoa coordinates.
    static func target(
        forCocoaRegion cocoaRect: CGRect,
        mainScreenHeight: CGFloat
    ) -> Result<RecordingTarget, RecordingTargetRejection> {
        let globalRectInCG = DisplayGeometry.cocoaToCGRect(cocoaRect, mainScreenHeight: mainScreenHeight)
        let plan = RecordingRegionPlan.make(
            globalRectInCG: globalRectInCG,
            displays: DisplaySnapshotService.descriptorsForConnectedScreens()
        )

        if let target = plan.target {
            return .success(target)
        }
        return .failure(plan.rejection ?? .invalidGeometry)
    }
}
