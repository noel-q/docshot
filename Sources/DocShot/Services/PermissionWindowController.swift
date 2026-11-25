import SwiftUI
import AppKit

/// The screen recording permission window in Quiet (agreed 25 November 2026): the guide's
/// compact panel, three numbered steps, one accent button that moves from Open System Settings
/// to Restart DocShot. Return presses it; Escape cancels.
@MainActor
public final class PermissionAlertModel: ObservableObject {
    @Published public var statusMessage: String?
    @Published public var statusIsError = false
    /// System Settings was opened from here, so Restart DocShot is now the next step.
    @Published public var openedSettings = false
    /// macOS reports the permission as on.
    @Published public var granted = false
}

public struct PermissionAlertView: View {
    @ObservedObject private var themeController = ThemeController.shared
    @ObservedObject public var model: PermissionAlertModel
    public var onOpenSettings: () -> Void
    public var onRestart: () -> Void
    public var onCancel: () -> Void

    static let width: CGFloat = 460

    public init(
        model: PermissionAlertModel,
        onOpenSettings: @escaping () -> Void,
        onRestart: @escaping () -> Void,
        onCancel: @escaping () -> Void
    ) {
        self.model = model
        self.onOpenSettings = onOpenSettings
        self.onRestart = onRestart
        self.onCancel = onCancel
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: Quiet.Space.s4) {
            HStack(alignment: .center, spacing: Quiet.Space.s4) {
                Image(nsImage: NSApp.applicationIconImage)
                    .resizable()
                    .frame(width: Quiet.Space.s12, height: Quiet.Space.s12)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: Quiet.Space.s1) {
                    Text("Allow screen recording")
                        .font(Quiet.Font.title3)
                        .foregroundStyle(Quiet.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text("DocShot needs it to see windows and capture the screen. Nothing leaves this Mac.")
                        .font(Quiet.Font.nativeBody)
                        .foregroundStyle(Quiet.inkMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            SettingsGroup(title: "Three steps") {
                SettingsRow(title: "1. Open System Settings", detail: "Privacy & Security, then Screen & System Audio Recording.") {
                    stepButton("Open", isNext: !model.openedSettings, action: onOpenSettings)
                }
                SettingsDivider()
                SettingsRow(title: "2. Switch DocShot on", detail: "If DocShot is not in the list, add it with the + button.") {
                    EmptyView()
                }
                SettingsDivider()
                SettingsRow(title: "3. Restart DocShot", detail: "macOS lets DocShot use the permission after a restart.") {
                    stepButton("Restart", isNext: model.openedSettings, action: onRestart)
                }
            }

            // Always two lines high, so the panel never changes size as messages come and go.
            Text(model.statusMessage ?? "DocShot checks again when you come back to it.")
                .font(Quiet.Font.caption)
                .foregroundStyle(model.statusIsError ? Quiet.danger : Quiet.inkMuted)
                .lineLimit(2, reservesSpace: true)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Quiet.Space.s1)
                .accessibilityAddTraits(.updatesFrequently)

            HStack {
                Spacer(minLength: 0)
                Button(action: onCancel) {
                    HStack(spacing: Quiet.Space.s1) {
                        KeyHint(keys: "esc")
                        Text("Cancel").font(Quiet.Font.caption).foregroundStyle(Quiet.inkMuted)
                    }
                }
                .buttonStyle(.plain)
                .help("Cancel (esc)")
                .accessibilityLabel("Cancel")
            }
        }
        .padding(Quiet.Space.s6)
        .frame(width: Self.width, alignment: .topLeading)
        .fixedSize(horizontal: false, vertical: true)
        .background(Quiet.canvas)
        .clipShape(RoundedRectangle(cornerRadius: Quiet.Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Quiet.Radius.lg, style: .continuous).strokeBorder(Quiet.line, lineWidth: 1))
        .ignoresSafeArea()
    }

    /// The next step's button takes the accent and Return; the other stays neutral.
    @ViewBuilder
    private func stepButton(_ title: String, isNext: Bool, action: @escaping () -> Void) -> some View {
        if isNext {
            Button(action: action) {
                AccentButtonLabel("\(title)  ↵")
            }
            .buttonStyle(.borderedProminent)
            .tint(Quiet.accent)
            .help("\(title) (Return)")
            .accessibilityLabel(title)
        } else {
            Button(title, action: action)
        }
    }
}

/// A borderless panel that still takes the keyboard.
final class PermissionPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
public final class PermissionWindowController: NSObject {
    public static let shared = PermissionWindowController()

    static let identifier = NSUserInterfaceItemIdentifier("DocShotPermission")

    public var onDismiss: (@MainActor () -> Void)?
    private var panel: PermissionPanel?
    private var model: PermissionAlertModel?
    private var keyMonitor: Any?
    private var activeObserver: NSObjectProtocol?

    private override init() {
        super.init()
    }

    public func showPermissionAlert(onDismiss: (@MainActor () -> Void)? = nil) {
        closePermissionAlert()
        self.onDismiss = onDismiss
        let alertModel = PermissionAlertModel()
        self.model = alertModel

        let alertView = PermissionAlertView(
            model: alertModel,
            onOpenSettings: { [weak self] in self?.openSettings() },
            onRestart: { [weak self] in self?.restartIfPermissionGranted() },
            onCancel: { [weak self] in self?.closePermissionAlert() }
        )

        let host = NSHostingView(rootView: alertView)
        host.sizingOptions = []
        let size = host.fittingSize
        let panel = PermissionPanel(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.identifier = Self.identifier
        panel.title = "Allow screen recording"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.contentView = host

        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        let visible = screen?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = CGRect(
            x: (visible.midX - size.width / 2).rounded(),
            y: (visible.minY + (visible.height - size.height) * 2 / 3).rounded(),
            width: size.width, height: size.height
        )
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        // Rises 8 points and fades in (Reduce Motion: fade only).
        panel.setFrame(reduceMotion ? frame : frame.offsetBy(dx: 0, dy: -Quiet.Space.s2), display: false)
        panel.alphaValue = 0

        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        self.panel = panel
        installKeyMonitor()
        watchActivation()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = QuietTokens.durBase
            context.timingFunction = Quiet.Motion.easeOutCurve
            panel.animator().alphaValue = 1
            if !reduceMotion { panel.animator().setFrame(frame, display: true) }
        }
    }

    private func openSettings() {
        PermissionService.shared.openSystemSettingsScreenRecording()
        model?.openedSettings = true
        model?.statusIsError = false
        model?.statusMessage = "Switch DocShot on in System Settings, then come back and choose Restart."
    }

    /// Coming back to DocShot: say whether macOS shows the permission as on yet.
    private func recheck() {
        guard let model, model.openedSettings else { return }
        if PermissionService.shared.hasScreenCaptureAccess() {
            model.granted = true
            model.statusIsError = false
            model.statusMessage = "Allowed. Choose Restart to start using it."
        }
    }

    private func restartIfPermissionGranted() {
        guard PermissionService.shared.hasScreenCaptureAccess() else {
            model?.statusIsError = true
            model?.statusMessage = "macOS has not made Screen Recording permission available to DocShot yet. Enable it, then return and try again."
            return
        }

        let appURL = Bundle.main.bundleURL
        guard appURL.pathExtension == "app" else {
            model?.statusIsError = true
            model?.statusMessage = "Permission is enabled. Please quit and relaunch DocShot from Xcode so it runs as a macOS app."
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { [weak self] _, error in
            Task { @MainActor [weak self] in
                if let error {
                    self?.model?.statusIsError = true
                    self?.model?.statusMessage = "DocShot could not restart: \(error.localizedDescription)"
                } else {
                    NSApp.terminate(nil)
                }
            }
        }
    }

    public func closePermissionAlert() {
        removeKeyMonitor()
        stopWatchingActivation()
        if let panel {
            panel.orderOut(nil)
            self.panel = nil
        }
        model = nil
        let callback = onDismiss
        onDismiss = nil
        callback?()
    }

#if DEBUG
    /// The debug hook's second state, without opening System Settings.
    func debugMarkOpened() {
        model?.openedSettings = true
        model?.statusIsError = false
        model?.statusMessage = "Switch DocShot on in System Settings, then come back and choose Restart."
    }
#endif

    // MARK: Keys and coming back

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let panel = self.panel, event.window === panel, !event.isARepeat else { return event }
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            let commandW = modifiers == .command && event.charactersIgnoringModifiers?.lowercased() == "w"
            if (event.keyCode == 53 && modifiers.isEmpty) || commandW {
                self.closePermissionAlert()
                return nil
            }
            if (event.keyCode == 36 || event.keyCode == 76) && modifiers.isEmpty {
                if self.model?.openedSettings == true { self.restartIfPermissionGranted() } else { self.openSettings() }
                return nil
            }
            return event
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    private func watchActivation() {
        guard activeObserver == nil else { return }
        activeObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.recheck() }
        }
    }

    private func stopWatchingActivation() {
        if let activeObserver { NotificationCenter.default.removeObserver(activeObserver) }
        activeObserver = nil
    }
}
