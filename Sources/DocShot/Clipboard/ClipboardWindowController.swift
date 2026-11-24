import AppKit
import SwiftUI

/// The DocShot window (plan section 3), opened from the menu bar or Control+Option+Command+V.
/// An ordinary window, not a floating panel. Escape closes it and focus goes back to the app
/// the user was in (C0 finding: `NSApp.activate()` and `activate()` on that app both work from
/// a menu bar app).
@MainActor
final class ClipboardWindowController: NSObject, NSWindowDelegate {
    static let shared = ClipboardWindowController()

    private var window: NSWindow?
    private var previousApp: NSRunningApplication?
    private var keyMonitor: Any?

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
        if let front = NSWorkspace.shared.frontmostApplication,
           front.bundleIdentifier != Bundle.main.bundleIdentifier {
            previousApp = front
        }

        let window = self.window ?? makeWindow()
        self.window = window
        ClipboardHistoryController.shared.refreshAccessState()
        NSApp.activate()
        window.makeKeyAndOrderFront(nil)
        installKeyMonitor()
    }

    func close() {
        window?.close() // windowWillClose hands focus back
    }

    /// After copying an item: close, so the user is back in their app ready to press Cmd+V.
    func closeAfterCopy() {
        close()
    }

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
            controller: ClipboardHistoryController.shared,
            onCopied: { [weak self] in self?.closeAfterCopy() }
        ))
        window.center()
        window.setFrameAutosaveName("DocShotClipboardWindow")
        return window
    }

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let window = self.window, event.window === window else { return event }
            // Escape closes. Keyboard navigation and Return to paste arrive in C3.
            if event.keyCode == 53, event.modifierFlags.intersection(.deviceIndependentFlagsMask).isEmpty {
                self.close()
                return nil
            }
            return event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
    }

    func windowWillClose(_ notification: Notification) {
        removeKeyMonitor()
        returnFocus()
    }

    private func returnFocus() {
        guard let app = previousApp, !app.isTerminated else { return }
        previousApp = nil
        app.activate()
    }
}
