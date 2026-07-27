import AppKit
import SwiftUI

@MainActor
public final class CaptureCoordinator: ObservableObject {
    public static let shared = CaptureCoordinator()
    
    @Published public private(set) var state: CaptureState = .idle
    @Published public var hoveredWindow: WindowInfo?
    @Published public var permissionDeniedReason: String?
    @Published public var errorMessage: String?
    
    /// Colour under the cursor during selection. Separate observable so readout updates do not
    /// invalidate the whole overlay on every mouse event.
    public let colorReadout = ColorReadoutModel()

    private var overlayWindows: [SelectionOverlayWindow] = []
    private var eligibleWindows: [WindowInfo] = []
    private var mouseMonitor: Any?
    private var keyMonitor: Any?

    /// Identifies one selection session. Bumped on cancel so snapshot results that arrive late
    /// cannot reopen or update a selection the user already dismissed.
    private var selectionGeneration = 0
    private var isRefreshingSnapshots = false

    /// Owns the temporary global Escape registration used while a snapshot is pending.
    /// Injectable so the lifecycle can be tested without registering a real system hotkey.
    public var escapeSession = PendingEscapeSession(handler: HotkeyService.shared)
    
    private init() {
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleAppDidBecomeActive),
            name: NSApplication.didBecomeActiveNotification,
            object: nil
        )
    }
    
    @objc private func handleAppDidBecomeActive() {
        Task { @MainActor in
            let hasAccess = PermissionService.shared.hasScreenCaptureAccess()
            if self.state == .permissionRequired {
                if hasAccess {
                    self.state = .idle
                    self.permissionDeniedReason = nil
                    PermissionWindowController.shared.closePermissionAlert()
                } else {
                    self.state = .idle
                    self.permissionDeniedReason = nil
                }
            }
        }
    }
    
    public func startCapture() {
        switch state {
        case .idle, .cancelled:
            beginCaptureRequest()
        case .editing:
            confirmDiscardAndStartNewCapture()
        case .permissionRequired, .selecting, .capturing:
            return
        }
    }

    /// Starts a capture only after the caller has established that no editor work will be lost.
    private func beginCaptureRequest() {

        state = .capturing
        Task { [weak self] in
            guard let self else { return }

            // Prefer the ScreenCaptureKit probe to the legacy Core Graphics
            // preflight. The probe performs no persisted capture; it only
            // validates the API that will perform the selected capture.
            let coreGraphicsAccess = PermissionService.shared.hasScreenCaptureAccess()
            let screenCaptureKitAccess = coreGraphicsAccess
                ? true
                : await PermissionService.shared.canCaptureWithScreenCaptureKit()
            if screenCaptureKitAccess {
                await self.beginSelection()
                return
            }

            PermissionService.shared.requestScreenCaptureAccess()
            if await PermissionService.shared.canCaptureWithScreenCaptureKit() {
                await self.beginSelection()
            } else {
                self.showPermissionRequired()
            }
        }
    }

    /// A new capture replaces the current editor session, so require an explicit confirmation
    /// before closing it. Cancelling this alert intentionally leaves the editor untouched.
    private func confirmDiscardAndStartNewCapture() {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Discard Current Edits?"
        alert.informativeText = "Starting a new capture will discard the screenshot and annotations currently open in DocShot."
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Start New Capture")

        guard alert.runModal() == .alertSecondButtonReturn else { return }

        EditorWindowController.shared.closeEditor()
        beginCaptureRequest()
    }

    private func showPermissionRequired() {
        self.state = .permissionRequired
        self.permissionDeniedReason = "DocShot requires Screen Recording permission to select windows or screen regions. Please grant access in System Settings."
        PermissionWindowController.shared.showPermissionAlert(onDismiss: { [weak self] in
            self?.state = .idle
            self?.permissionDeniedReason = nil
        })
    }

    private func beginSelection() async {
        // 1. Discover eligible windows
        self.eligibleWindows = WindowDiscoveryService.shared.getEligibleWindows()
        self.state = .selecting

        guard let mainScreen = NSScreen.main else {
            self.state = .idle
            return
        }
        let mainScreenHeight = mainScreen.frame.height

        selectionGeneration += 1
        let generation = selectionGeneration

        // 2. Monitors go up before the snapshot so Escape can cancel while it is still pending.
        //    A local monitor only sees events routed to DocShot, so Escape is *also* registered
        //    as a temporary global hotkey: until the overlay exists there is no DocShot window
        //    to receive the key. It is released below on every path.
        setupMonitors(mainScreenHeight: mainScreenHeight)
        let escapeToken = escapeSession.begin { [weak self] in
            self?.cancelCapture()
        }
        defer { escapeSession.end(token: escapeToken) }

        // 3. Snapshot every display *before* creating any overlay. The overlay dims the screen,
        //    so a snapshot taken afterwards would report darkened colours.
        await DisplaySnapshotService.shared.captureSnapshots(
            for: DisplaySnapshotService.descriptorsForConnectedScreens()
        )

        // 4. If the user cancelled while the snapshot was in flight, stay cancelled.
        guard generation == selectionGeneration, state == .selecting else {
            DisplaySnapshotService.shared.cancelPending()
            return
        }

        // 5. Only now do overlays exist.
        presentOverlays(mainScreenHeight: mainScreenHeight)
    }

    private func presentOverlays(mainScreenHeight: CGFloat) {
        var newOverlays: [SelectionOverlayWindow] = []

        for screen in NSScreen.screens {
            let overlay = SelectionOverlayWindow(contentRect: screen.frame, screen: screen)

            let hostView = NSHostingView(
                rootView: SelectionOverlayView(
                    coordinator: self,
                    readout: colorReadout,
                    screenFrame: screen.frame,
                    mainScreenHeight: mainScreenHeight,
                    onCancel: { [weak self] in
                        self?.cancelCapture()
                    },
                    onSelectWindow: { [weak self] window in
                        self?.performWindowCapture(window)
                    },
                    onSelectRegion: { [weak self] cocoaRect in
                        self?.performRegionCapture(cocoaRect, mainScreenHeight: mainScreenHeight)
                    }
                )
            )

            overlay.contentView = hostView
            overlay.makeKeyAndOrderFront(nil)
            newOverlays.append(overlay)
        }

        self.overlayWindows = newOverlays
        DisplaySnapshotService.shared.setSelectionOverlayVisible(true)
    }

    /// Re-captures every display without ending the selection session, for when the screen has
    /// changed since the overlay opened. Overlays are hidden for the duration so the refreshed
    /// snapshot cannot contain them.
    private func refreshSnapshots(mainScreenHeight: CGFloat) {
        guard state == .selecting, !overlayWindows.isEmpty, !isRefreshingSnapshots else { return }

        isRefreshingSnapshots = true
        let generation = selectionGeneration

        for overlay in overlayWindows {
            overlay.orderOut(nil)
        }
        DisplaySnapshotService.shared.setSelectionOverlayVisible(false)
        colorReadout.clear()

        Task { [weak self] in
            guard let self else { return }

            // Overlays are hidden for the re-capture, so Escape again needs a global route.
            let escapeToken = self.escapeSession.begin { [weak self] in
                self?.cancelCapture()
            }
            defer { self.escapeSession.end(token: escapeToken) }

            CATransaction.flush()
            try? await Task.sleep(nanoseconds: 50_000_000)

            await DisplaySnapshotService.shared.captureSnapshots(
                for: DisplaySnapshotService.descriptorsForConnectedScreens()
            )

            self.isRefreshingSnapshots = false

            guard generation == self.selectionGeneration, self.state == .selecting else {
                DisplaySnapshotService.shared.cancelPending()
                return
            }

            for overlay in self.overlayWindows {
                overlay.makeKeyAndOrderFront(nil)
            }
            DisplaySnapshotService.shared.setSelectionOverlayVisible(true)
        }
    }

    public func cancelCapture() {
        // Invalidate first: a snapshot still in flight must not reopen the selection UI.
        selectionGeneration += 1
        isRefreshingSnapshots = false
        escapeSession.endAll()
        DisplaySnapshotService.shared.cancelPending()

        closeOverlays()
        removeMonitors()
        self.hoveredWindow = nil
        self.state = .idle
    }

    public func closeOverlays() {
        for overlay in overlayWindows {
            overlay.orderOut(nil)
            overlay.close()
        }
        overlayWindows.removeAll()
        removeMonitors()
        escapeSession.endAll()

        // Snapshots live only as long as the selection session that created them.
        DisplaySnapshotService.shared.setSelectionOverlayVisible(false)
        DisplaySnapshotService.shared.releaseSnapshots()
        colorReadout.clear()
    }
    
    private func setupMonitors(mainScreenHeight: CGFloat) {
        removeMonitors()
        
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            if event.keyCode == 53 { // ESC
                self?.cancelCapture()
                return nil
            }
            if event.keyCode == 15, event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty { // R
                self?.refreshSnapshots(mainScreenHeight: mainScreenHeight)
                return nil
            }
            return event
        }

        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            guard let self = self, self.state == .selecting else { return event }
            let mouseLocationInCocoa = NSEvent.mouseLocation
            let mouseLocationInCG = DisplayGeometry.cocoaToCGPoint(mouseLocationInCocoa, mainScreenHeight: mainScreenHeight)

            let hovered = self.eligibleWindows.first { win in
                win.boundsInCG.contains(mouseLocationInCG)
            }

            if self.hoveredWindow != hovered {
                self.hoveredWindow = hovered
            }

            // Sampling reads the frozen snapshot in memory: no capture, no async work,
            // and no publish unless the resolved pixel actually changed.
            let snapshotService = DisplaySnapshotService.shared
            self.colorReadout.update(
                globalPoint: mouseLocationInCG,
                snapshots: snapshotService.snapshots,
                unavailableDescriptors: snapshotService.unavailableDescriptors
            )

            return event
        }
    }
    
    private func removeMonitors() {
        if let monitor = mouseMonitor {
            NSEvent.removeMonitor(monitor)
            mouseMonitor = nil
        }
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }
    
    private func performWindowCapture(_ window: WindowInfo) {
        self.state = .capturing
        closeOverlays()
        
        Task {
            CATransaction.flush()
            try? await Task.sleep(nanoseconds: 50_000_000)
            
            do {
                let cgImage = try await ScreenCaptureService.shared.captureWindow(windowID: window.id, boundsInCG: window.boundsInCG)
                openEditor(with: cgImage)
            } catch {
                self.handleCaptureError("Failed to capture window: \(error.localizedDescription)")
            }
        }
    }
    
    private func performRegionCapture(_ cocoaRect: CGRect, mainScreenHeight: CGFloat) {
        self.state = .capturing
        closeOverlays()
        
        let cgRect = DisplayGeometry.cocoaToCGRect(cocoaRect, mainScreenHeight: mainScreenHeight)
        
        Task {
            CATransaction.flush()
            try? await Task.sleep(nanoseconds: 50_000_000)
            
            do {
                let cgImage = try await ScreenCaptureService.shared.captureRegion(cgRect)
                openEditor(with: cgImage)
            } catch {
                self.handleCaptureError("Failed to capture region: \(error.localizedDescription)")
            }
        }
    }
    
    private func handleCaptureError(_ message: String) {
        self.errorMessage = message
        self.state = .idle
        
        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Screen Capture Failed"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
    }
    
    private func openEditor(with image: CGImage) {
        self.state = .editing
        EditorWindowController.shared.presentEditor(with: image)
    }
    
    public func finishEditing() {
        self.state = .idle
        self.hoveredWindow = nil
    }
}
