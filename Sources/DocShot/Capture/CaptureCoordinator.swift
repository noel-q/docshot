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
    /// A Space change arrived while a refresh was running: refresh once more when it ends.
    private var needsRefreshAgain = false
    private let spaceObserver = SpaceChangeObserver()

    /// The app that was frontmost when the capture was requested. The preview thumbnail hands
    /// focus back to it after anything that brings DocShot forward.
    private var focusReturnApp: NSRunningApplication?

    /// The "Discard current …?" prompt is up. A second capture request while it is modal
    /// must not stack another prompt on top.
    private var isConfirmingDiscard = false

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
            recordFocusReturnApp()
            beginCaptureRequest()
        case .editing:
            // A press that only beeps must not touch the recorded app either.
            guard !isConfirmingDiscard, !PreviewThumbnailController.shared.isBusy else {
                NSSound.beep()
                return
            }
            recordFocusReturnApp()
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

    /// Nil when DocShot itself is in front (Settings or the editor open, say): then there is
    /// no other app to hand focus back to, and an older one must not be reused.
    private func recordFocusReturnApp() {
        let frontmost = NSWorkspace.shared.frontmostApplication
        focusReturnApp = frontmost?.processIdentifier == ProcessInfo.processInfo.processIdentifier
            ? nil
            : frontmost
    }

    /// A new capture replaces the current editor session, so require an explicit confirmation
    /// before closing it. Cancelling this alert intentionally leaves the editor untouched.
    private func confirmDiscardAndStartNewCapture() {
        isConfirmingDiscard = true
        defer { isConfirmingDiscard = false }

        NSApp.activate(ignoringOtherApps: true)

        let thumbnailShowing = PreviewThumbnailController.shared.isShowing

        let alert = NSAlert()
        alert.alertStyle = .warning
        if thumbnailShowing {
            alert.messageText = "Discard Current Screenshot?"
            alert.informativeText = "Starting a new capture will discard the screenshot waiting in the DocShot preview."
        } else {
            alert.messageText = "Discard Current Edits?"
            alert.informativeText = "Starting a new capture will discard the screenshot and annotations currently open in DocShot."
        }
        alert.addButton(withTitle: "Cancel")
        alert.addButton(withTitle: "Start New Capture")

        guard alert.runModal() == .alertSecondButtonReturn else {
            // Cancel leaves the capture where it was. With the thumbnail up, focus goes back to
            // the user's app and the thumbnail gets its keys again; the editor stays as before.
            if thumbnailShowing {
                PreviewThumbnailController.shared.resumeAfterInterruption()
            }
            return
        }

        if thumbnailShowing {
            PreviewThumbnailController.shared.dismiss()
            finishEditing()
        }
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

        // 5. The user switched Space while the picture was taken: take it again on the new one.
        while needsRefreshAgain {
            needsRefreshAgain = false
            await DisplaySnapshotService.shared.captureSnapshots(
                for: DisplaySnapshotService.descriptorsForConnectedScreens()
            )
            guard generation == selectionGeneration, state == .selecting else {
                DisplaySnapshotService.shared.cancelPending()
                return
            }
            eligibleWindows = WindowDiscoveryService.shared.getEligibleWindows()
        }

        // 6. Only now do overlays exist.
        presentOverlays(mainScreenHeight: mainScreenHeight)
    }

    /// `markReady` false leaves the snapshot service told that no overlay is up, so a picture
    /// for the colour readout can still be taken after the selector appears. DocShot's windows
    /// are excluded from that picture, so the selector's dimming is never in it.
    private func presentOverlays(mainScreenHeight: CGFloat, fadeIn: Bool = false, markReady: Bool = true) {
        var newOverlays: [SelectionOverlayWindow] = []
        let fades = fadeIn && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion

        for screen in NSScreen.screens {
            let overlay = SelectionOverlayWindow(contentRect: screen.frame, screen: screen, staysOnItsSpace: true)

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
            if fades { overlay.alphaValue = 0 }
            overlay.makeKeyAndOrderFront(nil)
            newOverlays.append(overlay)
        }

        self.overlayWindows = newOverlays
        if markReady {
            DisplaySnapshotService.shared.setSelectionOverlayVisible(true)
        }

        if fades {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = QuietTokens.durFast
                context.timingFunction = Quiet.Motion.easeOutCurve
                for overlay in newOverlays { overlay.animator().alphaValue = 1 }
            }
        }
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
                self.needsRefreshAgain = false
                DisplaySnapshotService.shared.cancelPending()
                return
            }

            // The windows may have changed too (another Space is in front), so the highlight
            // and the window capture must use the new list, not the one from the first press.
            self.eligibleWindows = WindowDiscoveryService.shared.getEligibleWindows()
            self.updateHoveredWindow(mainScreenHeight: mainScreenHeight)

            if self.needsRefreshAgain {
                // The Space changed while this picture was taken: move to the new Space.
                self.needsRefreshAgain = false
                self.handleSpaceChange(mainScreenHeight: mainScreenHeight)
                return
            }

            for overlay in self.overlayWindows {
                overlay.makeKeyAndOrderFront(nil)
            }
            DisplaySnapshotService.shared.setSelectionOverlayVisible(true)
        }
    }

    /// The user moved to another Space while the selector was open. The old selector stays on
    /// the Space it opened on (it slid away with it), so nothing is hidden or reshown on screen:
    /// read the new Space's windows, fade a new selector in, then take its picture.
    private func handleSpaceChange(mainScreenHeight: CGFloat) {
        guard state == .selecting else { return }
        if isRefreshingSnapshots || overlayWindows.isEmpty {
            // Still taking a picture (the first one, or a refresh): take another after it.
            needsRefreshAgain = true
            return
        }
        isRefreshingSnapshots = true
        let generation = selectionGeneration

        for overlay in overlayWindows {
            overlay.orderOut(nil)
            overlay.close()
        }
        overlayWindows.removeAll()
        hoveredWindow = nil
        DisplaySnapshotService.shared.setSelectionOverlayVisible(false)
        colorReadout.clear()

        // The selector shows the live screen; the picture only feeds the colour readout. So the
        // new selector appears at once with the new Space's windows, and the picture follows.
        eligibleWindows = WindowDiscoveryService.shared.getEligibleWindows()
        presentOverlays(mainScreenHeight: mainScreenHeight, fadeIn: true, markReady: false)
        updateHoveredWindow(mainScreenHeight: mainScreenHeight)

        Task { [weak self] in
            guard let self else { return }
            await DisplaySnapshotService.shared.captureSnapshots(
                for: DisplaySnapshotService.descriptorsForConnectedScreens()
            )
            self.isRefreshingSnapshots = false

            guard generation == self.selectionGeneration, self.state == .selecting else {
                self.needsRefreshAgain = false
                DisplaySnapshotService.shared.cancelPending()
                return
            }
            DisplaySnapshotService.shared.setSelectionOverlayVisible(true)

            if self.needsRefreshAgain {
                // The Space changed again while this picture was taken.
                self.needsRefreshAgain = false
                self.handleSpaceChange(mainScreenHeight: mainScreenHeight)
            }
        }
    }

    private func updateHoveredWindow(mainScreenHeight: CGFloat) {
        let location = DisplayGeometry.cocoaToCGPoint(NSEvent.mouseLocation, mainScreenHeight: mainScreenHeight)
        let hovered = eligibleWindows.first { $0.boundsInCG.contains(location) }
        if hoveredWindow != hovered {
            hoveredWindow = hovered
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

        spaceObserver.start { [weak self] in
            self?.handleSpaceChange(mainScreenHeight: mainScreenHeight)
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
        spaceObserver.stop()
        needsRefreshAgain = false
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
                let primaryHeight = NSScreen.screens.first?.frame.height ?? 0
                let cocoaRect = DisplayGeometry.cgToCocoaRect(window.boundsInCG, mainScreenHeight: primaryHeight)
                presentCapture(cgImage, capturedRect: cocoaRect)
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
                presentCapture(cgImage, capturedRect: cocoaRect)
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
    
    /// A finished screenshot goes to the preview thumbnail first (C0.6). The state is
    /// `.editing` until the thumbnail or the editor it opens is done with the capture.
    private func presentCapture(_ image: CGImage, capturedRect: CGRect) {
        self.state = .editing
        // Captures (C4): kept while history is on; the editor adds its marks when it closes.
        captureRecording = Task { @MainActor in
            await ClipboardHistoryController.shared.recordScreenshot(image)
        }
        let centre = CGPoint(x: capturedRect.midX, y: capturedRect.midY)
        let screen = NSScreen.screens.first { $0.frame.contains(centre) } ?? NSScreen.main
        PreviewThumbnailController.shared.present(image: image, on: screen, focusReturnApp: focusReturnApp)
    }
    
    public func finishEditing() {
        self.state = .idle
        self.hoveredWindow = nil
    }

    /// Storing the screenshot being handled now in Captures (C4); its value is the entry's id,
    /// nil when Captures keeps nothing. The editor waits for it when it closes, so its marks
    /// always go to this capture.
    public private(set) var captureRecording: Task<UUID?, Never>?

    /// A screenshot reopened from Captures: the editor owns the screen like a fresh capture,
    /// so a new capture waits until it closes. False while a capture or recording is under way.
    public func beginReopenedEditing() -> Bool {
        guard state == .idle || state == .cancelled,
              !RecordingCoordinator.shared.state.isActive else { return false }
        captureRecording = nil
        state = .editing
        return true
    }
}
