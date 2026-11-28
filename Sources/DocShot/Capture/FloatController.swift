import AppKit
import SwiftUI

/// Float (C4b; plan section 7): an image in its own small window above other windows. Images are
/// held in memory only: nothing is written to disk, and nothing survives quit. Works with
/// history off.
@MainActor
final class FloatController: NSObject, NSWindowDelegate {
    static let shared = FloatController()

    private var panels: [FloatPanel] = []
    private var keyMonitor: Any?

    var count: Int { panels.count }

    nonisolated static func image(fromPNG data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// Floats `image` near the centre of the screen the pointer is on.
    func float(_ image: CGImage) {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let size = FloatLayout.size(
            pixelSize: CGSize(width: image.width, height: image.height),
            backingScale: screen?.backingScaleFactor ?? 2,
            visible: visible
        )
        let frame = FloatLayout.frame(size: size, visible: visible, index: panels.count)

        let panel = FloatPanel(contentRect: frame, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.image = image
        panel.title = "Floating image"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        let host = NSHostingView(rootView: FloatView(image: image) { [weak self, weak panel] in
            guard let panel else { return }
            self?.remove(panel)
        })
        host.sizingOptions = []
        panel.contentView = host
        panels.append(panel)
        installKeyMonitor()

        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.alphaValue = 0
        if !reduceMotion { panel.setFrame(frame.offsetBy(dx: 0, dy: -Quiet.Space.s2), display: false) }
        panel.orderFrontRegardless()
        panel.makeKey()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = QuietTokens.durBase
            context.timingFunction = Quiet.Motion.easeOutCurve
            panel.animator().alphaValue = 1
            if !reduceMotion { panel.animator().setFrame(frame, display: true) }
        }
    }

    func remove(_ panel: FloatPanel) {
        panel.orderOut(nil)
        panel.image = nil
        panels.removeAll { $0 === panel }
        if panels.isEmpty { removeKeyMonitor() }
    }

    func windowWillClose(_ notification: Notification) {
        if let panel = notification.object as? FloatPanel { remove(panel) }
    }

    /// Cmd+C copies the image in front; Escape and Cmd+W remove it.
    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let panel = event.window as? FloatPanel, self.panels.contains(where: { $0 === panel }) else {
                return event
            }
            let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
            let letter = ClipboardKeys.commandLetter(
                keyCode: event.keyCode, characters: event.characters,
                charactersIgnoringModifiers: event.charactersIgnoringModifiers
            )
            if event.keyCode == ClipboardKeys.escape && flags.isEmpty || flags == .command && letter == "w" {
                self.remove(panel)
                return nil
            }
            if flags == .command && letter == "c", let image = panel.image {
                if let png = ClipboardHistoryController.pngData(image), OutputService.shared.copyToClipboard(pngData: png) {
                    return nil
                }
                NSSound.beep()
                return nil
            }
            return event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }
}

/// A floating image's window: takes the keyboard for Cmd+C and Escape without taking the app
/// forward.
final class FloatPanel: NSPanel {
    var image: CGImage?
    override var canBecomeKey: Bool { true }
}

/// The image, with a close button on hover (Quiet: radius-md, a hairline edge).
private struct FloatView: View {
    let image: CGImage
    let onClose: () -> Void
    @State private var hovering = false

    var body: some View {
        ZStack(alignment: .topLeading) {
            Image(decorative: image, scale: 1)
                .resizable()
                .interpolation(.high)
                .aspectRatio(contentMode: .fill)
            if hovering {
                Button(action: onClose) {
                    Image(systemName: "xmark")
                        .font(Quiet.Font.caption.weight(.semibold))
                        .foregroundStyle(Quiet.ink)
                        .frame(width: Quiet.Space.s6, height: Quiet.Space.s6)
                        .background(Circle().fill(Quiet.surface))
                        .overlay(Circle().strokeBorder(Quiet.line, lineWidth: 1))
                }
                .buttonStyle(.plain)
                .padding(Quiet.Space.s2)
                .help("Remove (esc)")
                .accessibilityLabel("Remove floating image")
                .transition(.opacity)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipShape(RoundedRectangle(cornerRadius: Quiet.Radius.md, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Quiet.Radius.md, style: .continuous).strokeBorder(Quiet.line, lineWidth: 1))
        .onHover { inside in
            withAnimation(Quiet.Motion.fade) { hovering = inside }
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Floating image. Command C copies it, Escape removes it.")
    }
}
