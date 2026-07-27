import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Owns the recording activity end to end: its own overlays, monitors, Escape registration,
/// session generation, and temporary media.
///
/// It is deliberately parallel to `CaptureCoordinator` rather than part of it. Screenshot capture
/// keeps its one-shot image API and its own state machine; nothing here changes them. Every
/// transition decision is delegated to `RecordingStateReducer`, so this type performs effects and
/// never invents a rule of its own.
@MainActor
public final class RecordingCoordinator: ObservableObject {
    public static let shared = RecordingCoordinator()

    @Published public private(set) var state: RecordingState = .idle
    @Published public var hoveredWindow: WindowInfo?
    /// The selection awaiting Record/Cancel, in global Cocoa coordinates.
    @Published public private(set) var pendingSelectionCocoaRect: CGRect?
    /// Why a selection was refused. Shown on the overlay; the session stays open.
    @Published public private(set) var noticeMessage: String?

    private var reducer = RecordingStateReducer()

    private let store: any TemporaryRecordingStore
    private let sessionFactory: any RecordingSessionFactory
    private let movieSaver: any MovieSaving
    private let gifExporter = GIFExportService()

    private var session: (any RecordingSession)?
    private var activeOutputURL: URL?

    private var overlayWindows: [SelectionOverlayWindow] = []
    private var eligibleWindows: [WindowInfo] = []
    private var mouseMonitor: Any?
    private var keyMonitor: Any?
    private var mainScreenHeight: CGFloat = 0
    private var noticeGeneration = 0
    private let statusPanel = RecordingStatusPanelController()
    private var interruptionObservers: [NSObjectProtocol] = []

    /// Escape while the permission probe is still running: there is no DocShot window yet to
    /// receive the key, so it needs a temporary global registration exactly as capture does.
    public var escapeSession = PendingEscapeSession(handler: HotkeyService.shared)

    public init(
        store: any TemporaryRecordingStore,
        sessionFactory: any RecordingSessionFactory,
        movieSaver: any MovieSaving
    ) {
        self.store = store
        self.sessionFactory = sessionFactory
        self.movieSaver = movieSaver
    }

    private convenience init() {
        let store = FileManagerTemporaryRecordingStore()
        self.init(
            store: store,
            sessionFactory: ScreenCaptureKitRecordingSessionFactory(),
            movieSaver: SavePanelMovieSaver(store: store)
        )
    }

    // MARK: - Public actions

    public func startRecording() {
        send(.requestRecording)
    }

    public func stopRecording() {
        send(.stopRequested)
    }

    public func cancelSelection() {
        send(.selectionCancelled)
    }

    public func confirmRecord() {
        send(.confirmRecord)
    }

    public func confirmCancel() {
        send(.confirmCancel)
    }

    /// The R3 setting is read only after the user has explicitly armed a recording. It defaults
    /// to off and never triggers a prompt merely because Settings is displayed.
    public var selectedAudioDescription: String {
        UserDefaults.standard.bool(forKey: "DocShotRecordSystemAudio") ? "System audio" : "Audio off"
    }

    /// Removes temporary recordings left behind by a previous run that ended abnormally.
    /// Only DocShot's own temporary directory is touched.
    public func purgeOrphanTemporaries() {
        store.purgeOwnedTemporaries()
    }

    /// Synchronous teardown for app termination: effects dispatched onto a Task would never run.
    public func terminateCleanup() {
        let pendingURL = activeOutputURL
        send(.appWillTerminate)
        if let pendingURL {
            store.removeIfPresent(pendingURL)
        }
        store.purgeOwnedTemporaries()
        activeOutputURL = nil
        statusPanel.hide()
        endInterruptionMonitoring()
    }

    // MARK: - Selection callbacks

    func selectWindow(_ window: WindowInfo) {
        guard state == .selecting else { return }
        switch RecordingSelectionAdapter.target(forWindow: window) {
        case .success(let target):
            pendingSelectionCocoaRect = DisplayGeometry.cgToCocoaRect(
                window.boundsInCG,
                mainScreenHeight: mainScreenHeight
            )
            send(.targetSelected(target, session: reducer.generation))
        case .failure(let rejection):
            send(.targetRejected(rejection, session: reducer.generation))
        }
    }

    func selectRegion(_ cocoaRect: CGRect) {
        guard state == .selecting else { return }
        switch RecordingSelectionAdapter.target(
            forCocoaRegion: cocoaRect,
            mainScreenHeight: mainScreenHeight
        ) {
        case .success(let target):
            pendingSelectionCocoaRect = DisplayGeometry.normalizeRect(cocoaRect)
            send(.targetSelected(target, session: reducer.generation))
        case .failure(let rejection):
            send(.targetRejected(rejection, session: reducer.generation))
        }
    }

    // MARK: - Reducer plumbing

    private func send(_ event: RecordingEvent) {
        let effects = reducer.apply(event)
        state = reducer.state
        updateR2Surfaces()
        for effect in effects {
            perform(effect)
        }
    }

    /// R2 keeps the activity visible without relying on the selection surface. The R1 window and
    /// region filters exclude DocShot itself, so this app-owned panel is absent from video pixels.
    private func updateR2Surfaces() {
        switch state {
        case .starting, .recording, .stopping, .awaitingOutput:
            statusPanel.show(coordinator: self)
        case .idle, .permissionRequired, .selecting, .awaitingConfirmation, .exportingGIF, .failed:
            statusPanel.hide()
        }

        switch state {
        case .starting, .recording, .stopping:
            beginInterruptionMonitoringIfNeeded()
        case .idle, .permissionRequired, .selecting, .awaitingConfirmation, .awaitingOutput,
             .exportingGIF, .failed:
            endInterruptionMonitoring()
        }
    }

    private func beginInterruptionMonitoringIfNeeded() {
        guard interruptionObservers.isEmpty else { return }
        let center = NotificationCenter.default
        interruptionObservers = [
            center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.interruptActiveRecording("Mac went to sleep.") }
            },
            center.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
                Task { @MainActor in self?.interruptActiveRecording("Display configuration changed.") }
            }
        ]
    }

    private func endInterruptionMonitoring() {
        let center = NotificationCenter.default
        interruptionObservers.forEach(center.removeObserver)
        interruptionObservers.removeAll()
    }

    private func interruptActiveRecording(_ message: String) {
        switch state {
        case .starting, .recording, .stopping:
            send(.streamFailed(
                .streamInterrupted(message),
                url: activeOutputURL,
                session: reducer.generation
            ))
        case .idle, .permissionRequired, .selecting, .awaitingConfirmation, .awaitingOutput,
             .exportingGIF, .failed:
            break
        }
    }

    private func perform(_ effect: RecordingEffect) {
        switch effect {
        case .preflightPermission(let sessionID):
            beginPermissionPreflight(session: sessionID)

        case .presentPermissionRequired:
            PermissionWindowController.shared.showPermissionAlert(onDismiss: { [weak self] in
                self?.send(.selectionCancelled)
            })

        case .beginSelection:
            presentSelectionOverlays()

        case .closeOverlays:
            closeOverlays()

        case .presentTargetRejection(let rejection):
            showNotice(rejection.message)

        case .startSession(let target, let sessionID):
            startSession(target: target, session: sessionID)

        case .stopSession(let sessionID):
            stopSession(session: sessionID)

        case .cancelSession:
            let endingSession = session
            session = nil
            Task { await endingSession?.cancel() }

        case .removeTemporary(let url):
            store.removeIfPresent(url)
            if activeOutputURL == url {
                activeOutputURL = nil
            }

        case .presentOutputChoice(let recording):
            // Deferred so the current effect list finishes before a modal takes the main thread.
            Task { @MainActor [weak self] in
                self?.presentOutputChoice(recording)
            }

        case .presentSavePanel(let recording):
            Task { @MainActor [weak self] in
                guard let self else { return }
                let result = await self.movieSaver.save(recording, parent: nil)
                self.send(.saveCompleted(result))
            }

        case .presentFailure(let failure):
            Task { @MainActor [weak self] in
                self?.presentFailure(failure)
            }

        case .rejectDuplicateRequest:
            NSSound.beep()
        }
    }

    // MARK: - Permission

    private func beginPermissionPreflight(session sessionID: RecordingSessionID) {
        // Escape has to work while the probe runs, before any overlay exists.
        escapeSession.begin { [weak self] in
            self?.cancelSelection()
        }

        Task { @MainActor [weak self] in
            guard let self else { return }
            let granted = await RecordingCoordinator.resolveScreenCaptureAccess()
            self.send(.permissionResolved(granted: granted, session: sessionID))
        }
    }

    @MainActor
    private static func resolveScreenCaptureAccess() async -> Bool {
        if PermissionService.shared.hasScreenCaptureAccess() { return true }
        if await PermissionService.shared.canCaptureWithScreenCaptureKit() { return true }

        PermissionService.shared.requestScreenCaptureAccess()
        return await PermissionService.shared.canCaptureWithScreenCaptureKit()
    }

    // MARK: - Selection overlays

    /// Only ever reached from `.beginSelection`, which the reducer emits only after permission
    /// has been granted. No overlay is created before that.
    private func presentSelectionOverlays() {
        guard let mainScreen = NSScreen.main else {
            send(.selectionCancelled)
            return
        }
        mainScreenHeight = mainScreen.frame.height
        eligibleWindows = RecordingSelectionAdapter.eligibleWindows()

        setupMonitors()

        var newOverlays: [SelectionOverlayWindow] = []
        for screen in NSScreen.screens {
            let overlay = SelectionOverlayWindow(contentRect: screen.frame, screen: screen)
            overlay.contentView = NSHostingView(
                rootView: RecordingSelectionOverlayView(
                    coordinator: self,
                    screenFrame: screen.frame,
                    mainScreenHeight: mainScreenHeight
                )
            )
            overlay.makeKeyAndOrderFront(nil)
            newOverlays.append(overlay)
        }
        overlayWindows = newOverlays

        // The overlays now receive Escape themselves.
        escapeSession.endAll()
    }

    private func closeOverlays() {
        for overlay in overlayWindows {
            overlay.orderOut(nil)
            overlay.close()
        }
        overlayWindows.removeAll()
        removeMonitors()
        escapeSession.endAll()

        hoveredWindow = nil
        pendingSelectionCocoaRect = nil
        eligibleWindows = []
        noticeMessage = nil
    }

    private func setupMonitors() {
        removeMonitors()

        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self else { return event }
            if event.keyCode == 53 { // Escape
                switch self.state {
                case .awaitingConfirmation:
                    self.send(.confirmCancel)
                default:
                    self.send(.selectionCancelled)
                }
                return nil
            }
            if event.keyCode == 36, case .awaitingConfirmation = self.state { // Return
                self.send(.confirmRecord)
                return nil
            }
            return event
        }

        mouseMonitor = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged]) { [weak self] event in
            guard let self, self.state == .selecting else { return event }

            let locationInCG = DisplayGeometry.cocoaToCGPoint(
                NSEvent.mouseLocation,
                mainScreenHeight: self.mainScreenHeight
            )
            let hovered = self.eligibleWindows.first { $0.boundsInCG.contains(locationInCG) }
            if self.hoveredWindow != hovered {
                self.hoveredWindow = hovered
            }
            return event
        }
    }

    private func removeMonitors() {
        if let mouseMonitor {
            NSEvent.removeMonitor(mouseMonitor)
            self.mouseMonitor = nil
        }
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }

    private func showNotice(_ message: String) {
        noticeGeneration += 1
        let generation = noticeGeneration
        noticeMessage = message

        Task { @MainActor [weak self] in
            try? await Task.sleep(nanoseconds: 4_000_000_000)
            guard let self, self.noticeGeneration == generation else { return }
            self.noticeMessage = nil
        }
    }

    // MARK: - Session lifecycle

    private func startSession(target: RecordingTarget, session sessionID: RecordingSessionID) {
        Task { @MainActor [weak self] in
            guard let self else { return }

            // The overlays are already ordered out; give the window server a beat to present a
            // frame without them so they cannot appear in the first recorded samples.
            CATransaction.flush()
            try? await Task.sleep(nanoseconds: 80_000_000)

            let outputURL: URL
            do {
                outputURL = try self.store.makeMP4URL()
            } catch {
                self.send(.sessionStartFailed(
                    .writer(error.localizedDescription),
                    url: nil,
                    session: sessionID
                ))
                return
            }
            self.activeOutputURL = outputURL

            let recordingSession = self.sessionFactory.makeSession { [weak self] failure in
                Task { @MainActor in
                    self?.send(.streamFailed(failure, url: outputURL, session: sessionID))
                }
            }
            self.session = recordingSession

            let audio: RecordingAudioMode = UserDefaults.standard.bool(forKey: "DocShotRecordSystemAudio")
                ? .system : .none
            let options = RecordingOptions(
                audio: audio,
                showsCursor: ScreenCaptureService.shared.includeCursor,
                maximumFrameRate: RecordingOptions.defaultMaximumFrameRate
            )

            do {
                try await recordingSession.start(
                    target: target,
                    options: options,
                    outputURL: outputURL
                )
                self.send(.sessionStarted(at: Date(), session: sessionID))
            } catch {
                let failure = (error as? RecordingFailure)
                    ?? .streamStart(error.localizedDescription)
                self.send(.sessionStartFailed(failure, url: outputURL, session: sessionID))
            }
        }
    }

    private func stopSession(session sessionID: RecordingSessionID) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            guard let recordingSession = self.session else {
                self.send(.sessionStopFailed(
                    .stopFailed("There is no recording to stop."),
                    url: self.activeOutputURL,
                    session: sessionID
                ))
                return
            }

            do {
                let recording = try await recordingSession.stop()
                self.session = nil
                self.send(.sessionStopped(recording, session: sessionID))
            } catch {
                let failure = (error as? RecordingFailure)
                    ?? .stopFailed(error.localizedDescription)
                self.send(.sessionStopFailed(
                    failure,
                    url: self.activeOutputURL,
                    session: sessionID
                ))
            }
        }
    }

    // MARK: - Output choice

    /// The R1 output surface. Stop never saves anything on its own: the user chooses here, and
    /// nothing is written to disk or to the clipboard until they do.
    private func presentOutputChoice(_ recording: TemporaryRecording) {
        guard case .awaitingOutput = state else { return }
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .informational
        alert.messageText = "Recording Finished"
        alert.informativeText = """
            \(RecordingCoordinator.durationText(recording.duration)) · \
            \(Int(recording.pixelSize.width)) × \(Int(recording.pixelSize.height)) px

            Nothing has been saved yet. Choose where to save this recording, or discard it.
            """
        alert.addButton(withTitle: "Save MP4…")
        alert.addButton(withTitle: "Edit Recording…")
        let canExportGIF = GIFProfile.docShotR4.supports(recording)
        if canExportGIF { alert.addButton(withTitle: "Export GIF…") }
        alert.addButton(withTitle: "Discard")

        let response = alert.runModal()
        if response == .alertFirstButtonReturn {
            send(.saveRequested)
        } else if response == .alertSecondButtonReturn {
            VideoEditorWindowController.shared.showEditor(recording: recording) { [weak self] in
                self?.send(.discardRequested)
            }
        } else if canExportGIF && response == .alertThirdButtonReturn {
            exportGIF(from: recording)
        } else {
            send(.discardRequested)
        }
    }

    private func exportGIF(from recording: TemporaryRecording) {
        Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let temporaryGIF = try self.store.makeGIFURL()
                let gifURL = try await self.gifExporter.export(source: recording, destination: temporaryGIF, profile: .docShotR4)
                self.presentGIFSavePanel(gifURL: gifURL, sourceMP4: recording)
            } catch {
                self.presentGIFFailure(error.localizedDescription, recording: recording)
            }
        }
    }

    private func presentGIFSavePanel(gifURL: URL, sourceMP4: TemporaryRecording) {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.gif]
        panel.nameFieldStringValue = "DocShot Recording.gif"
        panel.canCreateDirectories = true
        let response = panel.runModal()
        guard response == .OK, let destination = panel.url else {
            store.removeIfPresent(gifURL)
            presentOutputChoice(sourceMP4)
            return
        }
        do {
            try store.move(gifURL, to: destination)
            store.removeIfPresent(sourceMP4.url)
            send(.discardRequested)
        } catch {
            store.removeIfPresent(gifURL)
            presentGIFFailure(error.localizedDescription, recording: sourceMP4)
        }
    }

    private func presentGIFFailure(_ message: String, recording: TemporaryRecording) {
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "GIF Export Unavailable"
        alert.informativeText = message
        alert.addButton(withTitle: "Save MP4…")
        alert.addButton(withTitle: "Back")
        if alert.runModal() == .alertFirstButtonReturn { send(.saveRequested) }
        else { presentOutputChoice(recording) }
    }

    private func presentFailure(_ failure: RecordingFailure) {
        NSApp.activate(ignoringOtherApps: true)

        let alert = NSAlert()
        alert.alertStyle = .critical
        alert.messageText = "Recording Failed"
        alert.informativeText = failure.errorDescription ?? "The recording could not be completed."
        alert.addButton(withTitle: "OK")
        alert.runModal()

        send(.failureAcknowledged)
    }

    static func durationText(_ duration: TimeInterval) -> String {
        let total = Int(duration.rounded())
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}
