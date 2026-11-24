import AppKit
import ClipboardKit
import SwiftUI

/// The DocShot window (plan section 3), opened from the menu bar or Control+Option+Command+V.
/// An ordinary window, not a floating panel. Return or a click pastes into the app the user was
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
        self.window = window
        let history = ClipboardHistoryController.shared
        history.refreshAccessState()
        history.refreshPasteAccess()
        history.clearNotice()
        model.reset()
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
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 420, height: 560),
            styleMask: [.titled, .closable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "DocShot"
        window.isReleasedWhenClosed = false
        window.minSize = NSSize(width: 340, height: 360)
        window.delegate = self
        window.contentView = NSHostingView(rootView: ClipboardHistoryView(
            model: model,
            controller: ClipboardHistoryController.shared,
            onChoose: { [weak self] item in self?.choose(item) }
        ))
        window.center()
        window.setFrameAutosaveName("DocShotClipboardWindow")
        return window
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
