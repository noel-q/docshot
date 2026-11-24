import AppKit
import SwiftUI

/// A borderless panel that can take keyboard focus without activating DocShot, so the app the
/// user was in stays frontmost while the thumbnail is up.
final class PreviewThumbnailPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class PreviewThumbnailModel: ObservableObject {
    @Published var isBusy = false
}

/// Shows the small preview after a screenshot (plan section 7, C0.6). The capture state stays
/// `.editing` while the thumbnail is up, so every guard that applies to the editor (the discard
/// prompt before a new capture, recording blocked) applies here too.
@MainActor
public final class PreviewThumbnailController: NSObject {
    public static let shared = PreviewThumbnailController()

    public private(set) var currentPanel: NSPanel?
    private var image: CGImage?
    private var focusReturnApp: NSRunningApplication?
    private var keyMonitor: Any?
    private let model = PreviewThumbnailModel()

    public var isShowing: Bool { currentPanel != nil }

    /// A copy or save is in flight, including while the save panel is open. A new capture must
    /// not start then, or the old save could finish the new capture.
    public var isBusy: Bool { model.isBusy }

    private override init() {
        super.init()
    }

    /// - Parameters:
    ///   - screen: the display the screenshot came from; the panel sits in its bottom-right corner.
    ///   - focusReturnApp: the app that was frontmost when the capture started. Focus goes back to
    ///     it after anything that has to bring DocShot forward (the save panel, an error alert).
    public func present(image: CGImage, on screen: NSScreen?, focusReturnApp: NSRunningApplication?) {
        dismiss()

        self.image = image
        self.focusReturnApp = focusReturnApp
        model.isBusy = false

        let targetScreen = screen ?? NSScreen.main
        let visibleFrame = targetScreen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1200, height: 800)
        let imageSize = PreviewThumbnailLayout.imageSize(
            forPixelSize: CGSize(width: image.width, height: image.height),
            backingScale: targetScreen?.backingScaleFactor ?? 2
        )
        let frame = PreviewThumbnailLayout.panelFrame(imageSize: imageSize, visibleFrame: visibleFrame)

        let panel = PreviewThumbnailPanel(
            contentRect: frame,
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.title = "DocShot Preview"
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.becomesKeyOnlyIfNeeded = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]

        let view = PreviewThumbnailView(image: image, imageSize: imageSize, model: model) { [weak self] action in
            self?.perform(action)
        }
        panel.contentView = NSHostingView(rootView: view)

        currentPanel = panel
        // Rises 8 points and fades in over dur-base by moving the window itself, so the
        // system shadow follows (Reduce Motion: fade only).
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        panel.alphaValue = 0
        if !reduceMotion {
            panel.setFrameOrigin(NSPoint(x: frame.minX, y: frame.minY - Quiet.Space.s2))
        }
        panel.orderFrontRegardless()
        panel.makeKey()
        installKeyMonitor()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = QuietTokens.durBase
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1) // ease-out
            panel.animator().alphaValue = 1
            if !reduceMotion {
                panel.animator().setFrameOrigin(frame.origin)
            }
        }
    }

    /// Closes the panel without finishing the capture. Callers decide what happens to the
    /// capture state.
    public func dismiss() {
        removeKeyMonitor()
        if let panel = currentPanel {
            // Leaves at once (plan point 5): a fading panel would keep the keyboard and take
            // clicks while it faded, so a quick Cmd+V after Copy could land nowhere.
            panel.orderOut(nil)
            panel.close()
        }
        currentPanel = nil
        image = nil
        model.isBusy = false
    }

    // MARK: - Actions

    private func perform(_ action: PreviewThumbnailAction) {
        guard !model.isBusy, let image else { return }

        switch action {
        case .discard:
            finishCapture()
        case .edit:
            // The editor takes over the same capture, so the state stays `.editing`;
            // closing the editor finishes it.
            dismiss()
            EditorWindowController.shared.presentEditor(with: image)
        case .copy:
            copy(image)
        case .save:
            save(image)
        }
    }

    private func copy(_ image: CGImage) {
        model.isBusy = true
        Task {
            let data = await ExportService.shared.exportPNG(
                baseImage: image, annotations: [], cropRect: nil, exportSize: .native
            )
            model.isBusy = false
            if let data, OutputService.shared.copyToClipboard(pngData: data) {
                finishCapture()
            } else {
                showError("Failed to copy screenshot to the clipboard.")
            }
        }
    }

    private func save(_ image: CGImage) {
        model.isBusy = true
        Task {
            guard let data = await ExportService.shared.exportPNG(
                baseImage: image, annotations: [], cropRect: nil, exportSize: .native
            ) else {
                model.isBusy = false
                showError("Failed to render the screenshot.")
                return
            }

            // The save panel needs DocShot in front; focus goes back once it is done.
            NSApp.activate(ignoringOtherApps: true)
            let result = await OutputService.shared.saveWithPanel(pngData: data, parentWindow: nil)
            model.isBusy = false

            switch result {
            case .saved:
                finishCapture()
            case .cancelled:
                resumeAfterInterruption()
            case .failed(let message):
                showError(message)
            }
        }
    }

    /// Ends the capture from the thumbnail. If anything brought DocShot forward on the way
    /// (the save panel, an alert, the new-capture prompt), focus goes back to the app the user
    /// was in; otherwise that app never lost it.
    private func finishCapture() {
        let docShotWasActive = NSApp.isActive
        dismiss()
        CaptureCoordinator.shared.finishEditing()
        if docShotWasActive {
            returnFocus()
        }
    }

    /// Reports a failure and leaves the thumbnail up, so the capture is not lost.
    private func showError(_ message: String) {
        // Busy while the alert is modal, so a capture request beeps instead of stacking a
        // prompt and an overlay underneath it.
        model.isBusy = true
        defer { model.isBusy = false }
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.alertStyle = .warning
        alert.messageText = "DocShot"
        alert.informativeText = message
        alert.addButton(withTitle: "OK")
        alert.runModal()
        resumeAfterInterruption()
    }

    /// After something brought DocShot forward and was dismissed without ending the capture
    /// (a cancelled save panel, an error alert, a cancelled new-capture prompt): hand focus
    /// back to the user's app and give the thumbnail its keys again.
    public func resumeAfterInterruption() {
        returnFocus()
        currentPanel?.makeKey()
    }

    private func returnFocus() {
        guard let app = focusReturnApp, !app.isTerminated else { return }
        app.activate()
    }

    // MARK: - Keys

    private func installKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self,
                  let panel = self.currentPanel,
                  event.window === panel,
                  !self.model.isBusy else {
                return event
            }
            let modifiers = event.modifierFlags
            let action = PreviewThumbnailKeyCommand.resolve(
                characters: event.charactersIgnoringModifiers,
                keyCode: event.keyCode,
                hasCommand: modifiers.contains(.command),
                hasOtherModifiers: !modifiers.intersection([.option, .control, .shift]).isEmpty
            )
            guard let action else { return event }
            self.perform(action)
            return nil
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
        }
        keyMonitor = nil
    }
}

/// The preview thumbnail in Quiet (pilot step 3, 24 November 2026): a floating `surface` panel
/// with `radius-lg` corners and the system shadow; the capture itself, which shows an Edit pill
/// under the pointer; one accent button, Copy, labelled with its key; and Save, Edit and Discard
/// as icons with their keys under them. It rises 8 points and fades in over `dur-base` (a fade
/// only under Reduce Motion).
struct PreviewThumbnailView: View {
    /// Redraws this view when the colour theme changes (C0.7).
    @ObservedObject var themeController = ThemeController.shared
    let image: CGImage
    let imageSize: CGSize
    @ObservedObject var model: PreviewThumbnailModel
    let onAction: (PreviewThumbnailAction) -> Void

    @State private var hoveringImage = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private typealias Layout = PreviewThumbnailLayout
    /// Concentric with the panel: its radius minus the padding between them.
    private static let imageRadius = Quiet.Radius.lg - PreviewThumbnailLayout.padding

    var body: some View {
        VStack(spacing: Layout.padding) {
            capture
            buttons
                .disabled(model.isBusy)
        }
        .padding(Layout.padding)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(RoundedRectangle(cornerRadius: Quiet.Radius.lg, style: .continuous).fill(Quiet.surface))
        .overlay(RoundedRectangle(cornerRadius: Quiet.Radius.lg, style: .continuous).strokeBorder(Quiet.line, lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: Quiet.Radius.lg, style: .continuous))
    }

    private var capture: some View {
        Image(decorative: image, scale: 1)
            .resizable()
            .interpolation(.high)
            .aspectRatio(contentMode: .fit)
            .frame(width: imageSize.width, height: imageSize.height)
            .clipShape(RoundedRectangle(cornerRadius: Self.imageRadius, style: .continuous))
            .overlay {
                if hoveringImage {
                    Label("Edit", systemImage: "pencil")
                        .font(Quiet.Font.ui)
                        .foregroundStyle(Quiet.ink)
                        .padding(.horizontal, Quiet.Space.s3)
                        .padding(.vertical, Quiet.Space.s1)
                        .background(Capsule().fill(Quiet.surface))
                        .overlay(Capsule().strokeBorder(Quiet.line, lineWidth: 1))
                        .shadow(color: Quiet.controlDrop, radius: 1, y: 1) // shadow-control
                        .transition(.opacity)
                        .accessibilityHidden(true)
                }
            }
            .contentShape(Rectangle())
            .onHover { inside in
                withAnimation(reduceMotion ? nil : Quiet.Motion.instant) { hoveringImage = inside }
            }
            .onTapGesture { onAction(.edit) }
            .help("Open in the editor (⌘E)")
            .accessibilityLabel("Screenshot preview")
            .accessibilityHint("Opens the screenshot in the editor")
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { onAction(.edit) }
    }

    private var buttons: some View {
        HStack(spacing: Layout.buttonSpacing) {
            Button {
                onAction(.copy)
            } label: {
                AccentButtonLabel("Copy  \(PreviewThumbnailAction.copy.keyHint)")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .tint(Quiet.accent)
            .frame(width: Layout.copyButtonWidth)
            .help("Copy (Return or ⌘C)")
            .accessibilityLabel("Copy")

            Spacer(minLength: 0)

            ForEach(PreviewThumbnailAction.displayOrder.filter { $0 != .copy }, id: \.self) { action in
                ThumbnailIconButton(action: action) { onAction(action) }
            }
        }
        .frame(height: Layout.buttonRowHeight)
    }
}

/// Save, Edit or Discard: the icon with its key under it, a neutral hover fill.
private struct ThumbnailIconButton: View {
    let action: PreviewThumbnailAction
    let perform: () -> Void

    @State private var hovering = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: perform) {
            VStack(spacing: Quiet.Space.s1) {
                Image(systemName: action.symbolName)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundStyle(Quiet.ink)
                Text(action.keyHint)
                    .font(Quiet.Font.caption)
                    .foregroundStyle(Quiet.inkMuted)
            }
            .frame(width: PreviewThumbnailLayout.buttonWidth, height: PreviewThumbnailLayout.buttonRowHeight)
            .background(
                RoundedRectangle(cornerRadius: Quiet.Radius.sm, style: .continuous)
                    .fill(hovering ? Quiet.hover : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { inside in
            withAnimation(reduceMotion ? nil : Quiet.Motion.instant) { hovering = inside }
        }
        .help("\(action.title) (\(action.keyHint))")
        .accessibilityLabel(action.title)
    }
}
