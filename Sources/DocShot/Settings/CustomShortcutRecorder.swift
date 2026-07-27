import AppKit
import Carbon
import SwiftUI

struct CustomShortcutRecorder: View {
    let currentShortcut: HotkeyPreset
    let onSave: (UInt32, UInt32, String) -> Void

    @Environment(\.dismiss) private var dismiss
    @State private var captured: CapturedShortcut?
    @State private var validationMessage: String?

    private struct CapturedShortcut: Equatable {
        let keyCode: UInt32
        let modifiers: UInt32
        let keyDisplay: String

        var display: String {
            HotkeyDisplay.shortcut(modifiers: modifiers, keyDisplay: keyDisplay)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("Set Custom Capture Shortcut")
                .font(.headline)

            Text("Press one key with one or two modifiers. A custom shortcut can contain at most three keys in total.")
                .font(.subheadline)
                .foregroundColor(.secondary)

            ShortcutCaptureField(
                display: captured?.display ?? currentShortcut.shortcutDisplay,
                onCapture: { keyCode, modifiers, keyDisplay in
                    captured = CapturedShortcut(
                        keyCode: keyCode,
                        modifiers: modifiers,
                        keyDisplay: keyDisplay
                    )
                    validationMessage = nil
                },
                onInvalid: { validationMessage = $0 }
            )
            .frame(height: 44)

            if let validationMessage {
                Text(validationMessage)
                    .font(.footnote)
                    .foregroundColor(.red)
            }

            HStack {
                Spacer()
                Button("Cancel") { dismiss() }
                Button("Use Shortcut") {
                    guard let captured else { return }
                    onSave(captured.keyCode, captured.modifiers, captured.keyDisplay)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(captured == nil)
            }
        }
        .padding(20)
        .frame(width: 440)
    }
}

private struct ShortcutCaptureField: NSViewRepresentable {
    let display: String
    let onCapture: (UInt32, UInt32, String) -> Void
    let onInvalid: (String) -> Void

    func makeNSView(context: Context) -> ShortcutCaptureNSView {
        let view = ShortcutCaptureNSView()
        view.onCapture = onCapture
        view.onInvalid = onInvalid
        return view
    }

    func updateNSView(_ nsView: ShortcutCaptureNSView, context: Context) {
        nsView.display = display
        nsView.onCapture = onCapture
        nsView.onInvalid = onInvalid
        nsView.needsDisplay = true
    }
}

private final class ShortcutCaptureNSView: NSView {
    var display = ""
    var onCapture: ((UInt32, UInt32, String) -> Void)?
    var onInvalid: ((String) -> Void)?

    override var acceptsFirstResponder: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self)
        }
    }

    override func draw(_ dirtyRect: NSRect) {
        NSColor.controlBackgroundColor.setFill()
        NSBezierPath(roundedRect: bounds, xRadius: 8, yRadius: 8).fill()

        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 16, weight: .medium),
            .foregroundColor: NSColor.labelColor
        ]
        let size = (display as NSString).size(withAttributes: attributes)
        (display as NSString).draw(
            at: CGPoint(x: (bounds.width - size.width) / 2, y: (bounds.height - size.height) / 2),
            withAttributes: attributes
        )
    }

    override func keyDown(with event: NSEvent) {
        let activeModifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
        let modifierCount = [
            activeModifiers.contains(.command),
            activeModifiers.contains(.option),
            activeModifiers.contains(.control),
            activeModifiers.contains(.shift)
        ].filter { $0 }.count

        guard modifierCount > 0, modifierCount <= 2 else {
            onInvalid?("Use one or two modifiers with a single key.")
            return
        }

        guard activeModifiers.intersection([.command, .option, .control]).isEmpty == false else {
            onInvalid?("Include Command, Option, or Control so normal typing is not captured.")
            return
        }

        guard let characters = event.charactersIgnoringModifiers,
              characters.count == 1,
              characters.unicodeScalars.allSatisfy({ $0.value >= 0x20 && $0.value != 0x7F }) else {
            onInvalid?("Choose a letter, number, or symbol key.")
            return
        }

        let modifiers = carbonModifiers(from: activeModifiers)
        onCapture?(UInt32(event.keyCode), modifiers, characters.uppercased())
    }

    private func carbonModifiers(from flags: NSEvent.ModifierFlags) -> UInt32 {
        var result: UInt32 = 0
        if flags.contains(.command) { result |= UInt32(cmdKey) }
        if flags.contains(.option) { result |= UInt32(optionKey) }
        if flags.contains(.control) { result |= UInt32(controlKey) }
        if flags.contains(.shift) { result |= UInt32(shiftKey) }
        return result
    }
}
