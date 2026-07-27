import AppKit
import SwiftUI

@MainActor
public final class VideoEditorWindowController: NSObject, NSWindowDelegate {
    public static let shared = VideoEditorWindowController()

    public private(set) var window: NSWindow?
    private var viewModel: VideoEditorViewModel?
    private var onCloseHandler: (() -> Void)?

    public var currentWindow: NSWindow? { window }

    public func showEditor(recording: TemporaryRecording, onClose: (() -> Void)? = nil) {
        let project = VideoProject(recording: recording)
        showEditor(project: project, onClose: onClose)
    }

    public func showEditor(project: VideoProject, onClose: (() -> Void)? = nil) {
        self.onCloseHandler = onClose

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

        let editorView = VideoEditorView(viewModel: vm) { [weak self] in
            self?.closeEditor()
        }

        window.contentView = NSHostingView(rootView: editorView)
        self.window = window

        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    public func closeEditor() {
        guard let window else { return }
        window.orderOut(nil)
        window.close()
        self.window = nil
        self.viewModel = nil

        let handler = onCloseHandler
        self.onCloseHandler = nil
        handler?()
    }

    public func windowWillClose(_ notification: Notification) {
        self.window = nil
        self.viewModel = nil
        let handler = onCloseHandler
        self.onCloseHandler = nil
        handler?()
    }
}
