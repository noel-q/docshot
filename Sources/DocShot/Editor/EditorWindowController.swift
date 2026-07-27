import SwiftUI
import AppKit

@MainActor
public final class EditorWindowController: NSObject, NSWindowDelegate {
    public static let shared = EditorWindowController()
    
    public private(set) var currentWindow: NSWindow?
    private var viewModel: EditorViewModel?
    private var isClosing = false
    
    private override init() {
        super.init()
    }
    
    public func presentEditor(with baseImage: CGImage) {
        // If an editor window is already open, close it cleanly first
        if currentWindow != nil {
            closeEditor()
        }
        
        let vm = EditorViewModel(baseImage: baseImage)
        self.viewModel = vm
        
        let editorView = EditorView(viewModel: vm) { [weak self] in
            self?.closeEditor()
        }
        
        let hostingView = NSHostingView(rootView: editorView)
        
        let imageWidth = CGFloat(baseImage.width)
        let imageHeight = CGFloat(baseImage.height)
        
        // Target screen bounds
        let screenFrame = NSScreen.main?.visibleFrame ?? NSRect(x: 0, y: 0, width: 1200, height: 800)
        let maxWidth = screenFrame.width * 0.85
        let maxHeight = screenFrame.height * 0.85
        
        let targetWidth = min(max(imageWidth + 40, 750), maxWidth)
        let targetHeight = min(max(imageHeight + 100, 550), maxHeight)
        
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: targetWidth, height: targetHeight),
            styleMask: [.titled, .closable, .resizable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        
        window.title = "DocShot Editor"
        window.center()
        window.contentView = hostingView
        window.isReleasedWhenClosed = false
        window.delegate = self
        
        NSApp.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        
        self.currentWindow = window
    }
    
    public func closeEditor() {
        guard !isClosing, let window = currentWindow else { return }
        isClosing = true
        
        window.delegate = nil
        window.orderOut(nil)
        window.close()
        
        self.currentWindow = nil
        self.viewModel = nil
        self.isClosing = false
        
        CaptureCoordinator.shared.finishEditing()
    }
    
    public func windowWillClose(_ notification: Notification) {
        closeEditor()
    }
}
