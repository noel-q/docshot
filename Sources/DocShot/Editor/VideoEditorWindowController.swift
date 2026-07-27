import AppKit
import SwiftUI

public enum VideoEditorExit: Equatable, Sendable {
    /// Leave the editor without deleting the source take so the recording output choices can
    /// be shown again.
    case returnToOutputChoice
    /// The user explicitly confirmed that the temporary source take can be discarded.
    case discardRecording
    /// The edited movie reached the user-selected destination; the temporary source can close.
    case savedOutput
}

@MainActor
public final class VideoEditorWindowController: NSObject, NSWindowDelegate {
    public static let shared = VideoEditorWindowController()

    public private(set) var window: NSWindow?
    private var viewModel: VideoEditorViewModel?
    private var onExitHandler: ((VideoEditorExit) -> Void)?
    private var isClosing = false

    public var currentWindow: NSWindow? { window }

    public func showEditor(recording: TemporaryRecording, onExit: ((VideoEditorExit) -> Void)? = nil) {
        let project = VideoProject(recording: recording)
        showEditor(project: project, onExit: onExit)
    }

    public func showEditor(project: VideoProject, onExit: ((VideoEditorExit) -> Void)? = nil) {
        self.onExitHandler = onExit

        if let existingWindow = window {
            existingWindow.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let vm = VideoEditorViewModel(project: project)
        self.viewModel = vm

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.titled, .closable, .miniaturizable, .resizable],
            backing: .buffered,
            defer: false
        )
        window.title = "DocShot - Video Editor"
        window.minSize = NSSize(width: 850, height: 650)
        window.center()
        window.isReleasedWhenClosed = false
        window.backgroundColor = DesignTokens.nsGraphiteBase
        window.appearance = NSAppearance(named: .darkAqua)
        window.delegate = self

        let editorView = VideoEditorView(viewModel: vm) { [weak self] exit in
            self?.closeEditor(with: exit)
        }

        window.contentView = NSHostingView(rootView: editorView)
        self.window = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func closeEditor(with exit: VideoEditorExit) {
        guard !isClosing, let window else { return }
        isClosing = true
        window.delegate = nil
        window.orderOut(nil)
        window.close()
        self.window = nil
        self.viewModel = nil

        let handler = onExitHandler
        self.onExitHandler = nil
        isClosing = false
        handler?(exit)
    }

    /// The standard red window button must never be a destructive shortcut. The user can return
    /// to Save/Discard choices and keep the original temporary recording, or cancel this close.
    public func windowShouldClose(_ sender: NSWindow) -> Bool {
        guard !isClosing else { return true }
        guard viewModel?.isExporting != true else {
            NSSound.beep()
            return false
        }

        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "Leave Video Editor?"
        alert.informativeText = "This recording has not been saved. Return to the recording output choices to save it, export a GIF, or discard it."
        alert.addButton(withTitle: "Return to Output Choices")
        alert.addButton(withTitle: "Cancel")
        if alert.runModal() == .alertFirstButtonReturn {
            closeEditor(with: .returnToOutputChoice)
        }
        return false
    }

    public func windowWillClose(_ notification: Notification) {
        guard !isClosing else { return }
        self.window = nil
        self.viewModel = nil
        let handler = onExitHandler
        self.onExitHandler = nil
        handler?(.returnToOutputChoice)
    }
}
