import AppKit
import SwiftUI

public final class SelectionOverlayWindow: NSPanel {
    
    /// `staysOnItsSpace`: the screenshot selector shows a frozen picture of one Space, so it
    /// belongs to that Space and slides away with it on a swipe, like any window. The recording
    /// selector shows the live screen, so it follows the user to every Space.
    public init(contentRect: NSRect, screen: NSScreen, staysOnItsSpace: Bool = false) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        self.setFrame(contentRect, display: true)
        
        self.level = .screenSaver
        self.backgroundColor = .clear
        self.isOpaque = false
        self.hasShadow = false
        self.ignoresMouseEvents = false
        self.acceptsMouseMovedEvents = true
        self.collectionBehavior = staysOnItsSpace
            ? [.fullScreenAuxiliary, .stationary]
            : [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
    }
    
    override public var canBecomeKey: Bool {
        return true
    }
    
    override public var canBecomeMain: Bool {
        return true
    }
}
