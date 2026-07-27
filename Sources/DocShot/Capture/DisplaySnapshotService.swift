import Foundation
import CoreGraphics
import AppKit
import ScreenCaptureKit

/// Why a single display's snapshot could not be taken. A snapshot failure costs sampling on
/// that display only; selection and capture continue unaffected.
public enum SnapshotError: Error, Equatable, Sendable {
    case displayNotFound
    case captureFailed(String)
}

/// Captures one frozen image per display, before any DocShot overlay exists, so the colour
/// readout samples the real screen rather than DocShot's own dimming scrim.
///
/// Nothing here writes to the clipboard, to disk, or to user defaults. Snapshots are held only
/// for the lifetime of a selection session and released when the overlays close.
@MainActor
public final class DisplaySnapshotService: ObservableObject {
    public static let shared = DisplaySnapshotService()

    public typealias CaptureHandler = @Sendable (DisplayDescriptor) async throws -> CGImage

    private let captureHandler: CaptureHandler

    /// Bumped by every new request and by every cancel, so results from a superseded or
    /// cancelled run are discarded instead of repopulating the selection UI.
    private var generation: Int = 0

    /// Interlock: snapshots are refused while any overlay is on screen. Ordering already
    /// guarantees this, and this makes a regression fail loudly instead of silently capturing
    /// the overlay.
    public private(set) var isSelectionOverlayVisible = false

    @Published public private(set) var snapshots: [DisplaySnapshot] = []
    public private(set) var unavailableDescriptors: [DisplayDescriptor] = []
    public private(set) var lastPlan: SnapshotPlan?

    public init(captureHandler: @escaping CaptureHandler = DisplaySnapshotService.captureDisplayExcludingDocShot) {
        self.captureHandler = captureHandler
    }

    // MARK: - Session control

    public func setSelectionOverlayVisible(_ visible: Bool) {
        isSelectionOverlayVisible = visible
    }

    /// Captures snapshots for every display the budget allows.
    /// - Returns: `true` if the results were applied, `false` if the run was cancelled,
    ///   superseded, or refused because an overlay was already visible.
    @discardableResult
    public func captureSnapshots(for displays: [DisplayDescriptor]) async -> Bool {
        guard !isSelectionOverlayVisible else { return false }

        generation += 1
        let requestGeneration = generation
        let plan = SnapshotPlan.make(for: displays)
        let handler = captureHandler

        var captured: [DisplaySnapshot] = []

        await withTaskGroup(of: CaptureOutcome.self) { group in
            for descriptor in plan.included {
                group.addTask {
                    do {
                        let image = try await handler(descriptor)
                        return CaptureOutcome(descriptor: descriptor, image: image)
                    } catch {
                        // A display that fails to capture loses sampling only; selection continues.
                        return CaptureOutcome(descriptor: descriptor, image: nil)
                    }
                }
            }

            for await outcome in group {
                if let image = outcome.image {
                    captured.append(DisplaySnapshot(descriptor: outcome.descriptor, image: image))
                }
            }
        }

        // A cancel while capture was in flight must not resurrect the selection UI.
        guard requestGeneration == generation else { return false }

        let capturedIDs = Set(captured.map(\.descriptor.displayID))
        self.snapshots = captured.sorted { $0.descriptor.displayID < $1.descriptor.displayID }
        self.unavailableDescriptors = displays.filter { !capturedIDs.contains($0.displayID) }
        self.lastPlan = plan
        return true
    }

    /// Invalidates any in-flight capture and drops everything already captured.
    public func cancelPending() {
        generation += 1
        releaseSnapshots()
    }

    /// Frees snapshot memory. Called when a selection session ends by any route.
    public func releaseSnapshots() {
        snapshots = []
        unavailableDescriptors = []
        lastPlan = nil
    }

    // MARK: - Sampling

    public func snapshot(containing point: CGPoint) -> DisplaySnapshot? {
        snapshots.first { $0.contains(globalPoint: point) }
    }

    public func sample(atGlobalPoint point: CGPoint) -> ColorSample? {
        snapshot(containing: point)?.sample(atGlobalPoint: point)
    }

    // MARK: - Connected displays

    /// Describes every connected screen in global Core Graphics space, at its own backing scale.
    public static func descriptorsForConnectedScreens() -> [DisplayDescriptor] {
        let mainScreenHeight = NSScreen.main?.frame.height ?? 0

        return NSScreen.screens.compactMap { screen in
            guard let displayID = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? CGDirectDisplayID else {
                return nil
            }

            return DisplayDescriptor(
                displayID: displayID,
                frameInCG: DisplayGeometry.cocoaToCGRect(screen.frame, mainScreenHeight: mainScreenHeight),
                scale: screen.backingScaleFactor
            )
        }
    }

    // MARK: - Default capture

    private struct CaptureOutcome: @unchecked Sendable {
        let descriptor: DisplayDescriptor
        let image: CGImage?
    }

    /// Captures one display with every DocShot window excluded from the content filter. Ordering
    /// already guarantees no overlay exists yet; this also keeps an open editor, settings, or
    /// permission window out of the snapshot.
    public static let captureDisplayExcludingDocShot: CaptureHandler = { descriptor in
        let shareable = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)

        guard let display = shareable.displays.first(where: { $0.displayID == descriptor.displayID }) else {
            throw SnapshotError.displayNotFound
        }

        let ownProcessID = ProcessInfo.processInfo.processIdentifier
        let ownApplications = shareable.applications.filter { $0.processID == ownProcessID }

        let filter = SCContentFilter(
            display: display,
            excludingApplications: ownApplications,
            exceptingWindows: []
        )

        let configuration = SCStreamConfiguration()
        configuration.width = descriptor.pixelWidth
        configuration.height = descriptor.pixelHeight
        configuration.showsCursor = false

        return try await SCScreenshotManager.captureImage(contentFilter: filter, configuration: configuration)
    }
}
