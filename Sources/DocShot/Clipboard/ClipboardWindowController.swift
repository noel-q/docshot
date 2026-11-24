import AppKit
import ClipboardKit
import SwiftUI

/// The DocShot clipboard panel (plan section 3; compact panels, 24 November 2026), opened from
/// the menu bar or its shortcut: a borderless rounded panel at the normal window level. Return or a click pastes into the app the user was
/// in; Escape closes and focus goes back there (C3 plan, decisions 1, 4 and 9).
@MainActor
final class ClipboardWindowController: NSObject, NSWindowDelegate {
    static let shared = ClipboardWindowController()

    let model = ClipboardWindowModel(controller: .shared)
    private var window: NSWindow?
    /// The app to paste into and to return to: the last other app made active.
    private var previousApp: NSRunningApplication?
    private var keyMonitor: Any?
    private var activationObserver: NSObjectProtocol?
    /// A choice is being copied and pasted; a second Return or click waits for it.
    private var isChoosing = false
#if DEBUG
    /// What the last choice did, for the debug hooks (debug builds only).
    private(set) var lastPasteReport = "none"
    var debugPreviousApp: String? { previousApp?.bundleIdentifier }
    func debugSetPreviousApp(_ app: NSRunningApplication) { previousApp = app }
    var debugWindow: NSWindow? { window }
#endif

    var isShowing: Bool { window?.isVisible == true }

    /// The shortcut opens the window, or closes it when it is already in front.
    func toggle() {
        if let window, window.isVisible, window.isKeyWindow, NSApp.isActive {
            close()
        } else {
            show()
        }
    }

    func show() {
        // On open, the front app is the one the user was in, even a menu bar app such as a
        // launcher; later activations count only for ordinary apps (see watchActivations).
        if let front = NSWorkspace.shared.frontmostApplication,
           front.processIdentifier != ProcessInfo.processInfo.processIdentifier {
            previousApp = front
        }
        watchActivations()

        let window = self.window ?? makeWindow()
        let wasShowing = window.isVisible
        self.window = window
        let history = ClipboardHistoryController.shared
        history.refreshAccessState()
        history.refreshPasteAccess()
        history.clearNotice()
        model.reset()
        if !wasShowing { place(window) }
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        installKeyMonitor()
    }

    func close() {
        window?.close() // windowWillClose hands focus back
    }

    // MARK: - Choosing an item

    /// Return or a click: copy, close, and paste into the previous app when allowed.
    func choose(_ item: ClipItem) {
        guard !isChoosing else { return }
        isChoosing = true
        let history = ClipboardHistoryController.shared
        let target = previousApp.flatMap { $0.isTerminated ? nil : $0 }
        let outcome = history.pasteOutcome(hasPreviousApp: target != nil)
        Task {
            guard await history.copyBack(item) else { // stays open; the problem shows
                self.isChoosing = false
                return
            }
            close()
            self.isChoosing = false
#if DEBUG
            self.lastPasteReport = "\(outcome) target=\(target?.bundleIdentifier ?? "none")"
#endif
            switch outcome {
            case .pasteIntoPreviousApp:
                let started = ContinuousClock.now
                guard let target, await PasteKeystroke.waitUntilFrontmost(target) else {
#if DEBUG
                    self.lastPasteReport += " never frontmost"
#endif
                    // The app did not come back in time: the item is on the clipboard, so a beep
                    // says to press Cmd+V rather than pasting into whatever is in front.
                    NSSound.beep()
                    return
                }
                let frontAfter = ContinuousClock.now - started
                // Apps built on web views (Electron, such as Claude) put focus back in their text
                // field some time after they come to the front; a keystroke before that is lost.
                let focused = await PasteKeystroke.waitForFocusedElement(in: target)
                try? await Task.sleep(for: .milliseconds(50))
                // Pasting into whatever replaced the target meanwhile would be worse than not pasting.
                guard NSWorkspace.shared.frontmostApplication?.processIdentifier == target.processIdentifier else {
#if DEBUG
                    self.lastPasteReport += " left the front before the keystroke"
#endif
                    NSSound.beep()
                    return
                }
                let posted = PasteKeystroke.postCommandV()
#if DEBUG
                self.lastPasteReport += " frontmost after \(frontAfter) focused=\(focused) after \(ContinuousClock.now - started) posted=\(posted) key=\(PasteKeystroke.keyCodeForV())"
#endif
            case .copyOnly(let askForAccess):
                if askForAccess {
                    history.markAccessRequested()
                    AccessibilityAccess.request()
                }
            }
        }
    }

    /// Cmd+C: copy and close; the user pastes.
    func copyOnly(_ item: ClipItem) {
        Task {
            if await ClipboardHistoryController.shared.copyBack(item) {
                close()
            }
        }
    }

    // MARK: - Window

    private func makeWindow() -> NSWindow {
        let panel = ClipboardPanel(
            contentRect: NSRect(x: 0, y: 0, width: ClipboardPanelLayout.listWidth, height: ClipboardPanelLayout.height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        // The thumbnail's style (compact panels, decision 1): no title bar, the SwiftUI content
        // draws the rounded shape, and the system draws the shadow around it.
        panel.title = "DocShot Clipboard"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isMovableByWindowBackground = true
        panel.isReleasedWhenClosed = false
        // Behaves like the window it replaces: stays open when another app is used, so the
        // previous-app tracking (C3 plan, decision 9) still works.
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.delegate = self
        let host = NSHostingView(rootView: ClipboardHistoryView(
            model: model,
            controller: ClipboardHistoryController.shared,
            onChoose: { [weak self] item in self?.choose(item) },
            onClose: { [weak self] in self?.close() },
            onTogglePreview: { [weak self] in self?.togglePreview() }
        ))
        // The panel's size is DocShot's to animate; the content must not force it (it would
        // snap the panel wide the moment the preview pane is laid out).
        host.sizingOptions = []
        panel.contentView = host
        return panel
    }

    // MARK: - Place and size (compact panels, decisions 2 and 3)

    /// The clipboard controller's preferences (scratch ones in a debug run on a scratch store).
    private var panelSettings: ClipboardSettings { ClipboardHistoryController.shared.preferences }
    /// Counts DocShot's own moves of the panel; a drag is remembered only when none is running.
    /// A counter, not a flag, so an older animation finishing cannot clear a newer one's mark.
    private var animationsRunning = 0
    /// Where the panel's left edge was before the preview pushed it left, to go back on folding.
    private var minXBeforePreview: CGFloat?

    /// The screen the pointer is on: the one in use. NSMouseInRect counts the screen's edges.
    private static var screenInUse: NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
    }

    private func place(_ window: NSWindow) {
        let visible = (Self.screenInUse ?? window.screen)?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = ClipboardPanelLayout.frame(
            visible: visible, savedOrigin: panelSettings.panelOrigin, showingPreview: model.showPreview
        )
        minXBeforePreview = nil
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        // Rises 8 points and fades in over dur-base, moving the window itself so the shadow
        // follows (Reduce Motion: fade only).
        window.setFrame(reduceMotion ? frame : frame.offsetBy(dx: 0, dy: -Quiet.Space.s2), display: false)
        window.alphaValue = 0
        animate(window, reduceMotion: false) {
            window.animator().alphaValue = 1
            if !reduceMotion { window.animator().setFrame(frame, display: true) }
        }
    }

    /// Runs one of DocShot's own panel animations over dur-base with Quiet's ease-out.
    private func animate(_ window: NSWindow, reduceMotion: Bool, changes: @escaping () -> Void,
                         completion: (@MainActor () -> Void)? = nil) {
        animationsRunning += 1
        let done: @MainActor () -> Void = { [weak self] in
            self?.animationsRunning -= 1
            completion?()
        }
        if reduceMotion {
            changes()
            done()
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = QuietTokens.durBase
            context.timingFunction = Quiet.Motion.easeOutCurve
            changes()
        }, completionHandler: {
            MainActor.assumeIsolated { done() }
        })
    }

    /// Cmd+Y or the footer hint: slide the preview pane out to the right, or fold it away.
    /// The content changes first and the panel's edge animates on the next turn of the run
    /// loop, never the other way round: a layout change during a window animation cuts it
    /// short (traced frame by frame, 24 November 2026). Widening reveals the new pane; narrowing
    /// lets the pane fade out quickly and the panel close over the space it left. Ignored while
    /// the panel is still rising in or already resizing.
    func togglePreview() {
        guard let window, window.isVisible, animationsRunning == 0 else { return }
        let showing = !model.showPreview
        let visible = window.screen?.visibleFrame ?? (Self.screenInUse?.visibleFrame ?? window.frame)
        var target = ClipboardPanelLayout.resized(
            window.frame, toWidth: ClipboardPanelLayout.width(showingPreview: showing), within: visible
        )
        if showing {
            // Remember the left edge in case widening near the right of the screen moves it.
            minXBeforePreview = window.frame.minX
        } else if let minX = minXBeforePreview {
            // Folding goes back to where the panel was before the preview pushed it left.
            target.origin.x = min(max(minX, visible.minX), visible.maxX - target.width)
            minXBeforePreview = nil
        }
        model.showPreview = showing
        animationsRunning += 1 // held across the hop to the next turn of the run loop
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.animationsRunning -= 1
                self.animate(window, reduceMotion: NSWorkspace.shared.accessibilityDisplayShouldReduceMotion) {
                    if NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
                        window.setFrame(target, display: true)
                    } else {
                        window.animator().setFrame(target, display: true)
                    }
                }
            }
        }
    }

    /// Saves where the user left the panel. Only drags call this, never DocShot's own moves.
    private func rememberPlace(_ origin: CGPoint) {
        panelSettings.panelOrigin = origin
    }

    func windowDidMove(_ notification: Notification) {
        guard animationsRunning == 0, let window else { return }
        rememberPlace(window.frame.origin)
        // A drag sets a new home for the left edge.
        minXBeforePreview = nil
    }

    func windowWillClose(_ notification: Notification) {
        model.cancelSearch()
        removeKeyMonitor()
        stopWatchingActivations()
        ClipboardHistoryController.shared.releaseSearchIndex()
        returnFocus()
    }

    private func returnFocus() {
        guard let app = previousApp, !app.isTerminated else { return }
        previousApp = nil
        app.activate()
    }

    /// An ordinary app other than DocShot: not a helper or system agent that takes focus briefly.
    private static func canReceivePaste(_ app: NSRunningApplication) -> Bool {
        app.processIdentifier != ProcessInfo.processInfo.processIdentifier && app.activationPolicy == .regular
    }

    // MARK: - Previous app (C3 plan, decision 9)

    /// While the window is open, the last other app made active becomes the one to paste into.
    private func watchActivations() {
        guard activationObserver == nil else { return }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main
        ) { [weak self] notification in
            let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            MainActor.assumeIsolated {
                guard let self, let app, Self.canReceivePaste(app) else { return }
                self.previousApp = app
            }
        }
    }

    private func stopWatchingActivations() {
        if let activationObserver {
            NSWorkspace.shared.notificationCenter.removeObserver(activationObserver)
        }
        activationObserver = nil
    }

    // MARK: - Keys (C3 plan, decision 4)

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.window, event.window === window else { return event }
            return self.handle(event, in: window) ? nil : event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
    }

    /// True when the key was used here; false lets the search field have it.
    private func handle(_ event: NSEvent, in window: NSWindow) -> Bool {
        let fieldEditor = window.firstResponder as? NSTextView
        let action = ClipboardKeys.action(
            keyCode: event.keyCode, modifiers: event.modifierFlags, characters: event.characters,
            charactersIgnoringModifiers: event.charactersIgnoringModifiers,
            hasMarkedText: fieldEditor?.hasMarkedText() == true,
            hasTextSelection: (fieldEditor?.selectedRange().length ?? 0) > 0,
            queryIsEmpty: model.query.isEmpty
        )
        let history = ClipboardHistoryController.shared
        // History off: only Escape is ours; Return reaches the Turn On button.
        if !history.isEnabled, action != .close, action != .clearSearch { return false }
        switch action {
        case .passThrough:
            return false
        case .close:
            close()
        case .clearSearch:
            model.query = ""
        case .up:
            model.moveSelection(by: -1)
        case .down:
            model.moveSelection(by: 1)
        case .togglePreview:
            togglePreview()
        case .pick(let number):
            Task {
                guard let item = await self.model.settledRow(number), self.isShowing else { return }
                self.model.select(item.id)
                self.choose(item)
            }
        case .choose, .copy, .togglePin, .delete:
            // Act on the list the search is about to show, not the one before it.
            Task {
                // Closed meanwhile (Escape straight after Return): do nothing.
                guard let item = await self.model.settledSelection(), self.isShowing else { return }
                switch action {
                case .choose: self.choose(item)
                case .copy: self.copyOnly(item)
                case .togglePin: history.togglePin(item)
                default: history.delete(item)
                }
            }
        }
        return true
    }
}

/// A borderless panel that still takes the keyboard (the search field) and stays at the normal
/// window level, so it behaves like a window, not an overlay.
final class ClipboardPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}
