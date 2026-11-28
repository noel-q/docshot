import SwiftUI
import AppKit

/// The guide in Quiet (onboarding plan, agreed 25 November 2026): a compact borderless panel
/// with five short pages. Next is the one accent button; Return goes on, Escape skips. Every
/// setting it shows is the same control Settings uses, writing the same place.
@MainActor
final class OnboardingModel: ObservableObject {
    @Published var page: OnboardingPage = .welcome
    /// Which way the last change went, so pages slide in from the side they come from.
    @Published var forward = true
}

public struct OnboardingView: View {
    @ObservedObject private var themeController = ThemeController.shared
    @ObservedObject var model: OnboardingModel
    let onNext: () -> Void
    let onBack: () -> Void
    let onSkip: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    public var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            progress
                .padding(.horizontal, Quiet.Space.s6)
                .padding(.top, Quiet.Space.s6)

            // Scrolls only if a page outgrows the panel (a folder row and a message on Ready).
            ScrollView {
                ZStack(alignment: .topLeading) {
                    pageContent(model.page)
                        .id(model.page)
                        .transition(pageTransition)
                }
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .padding(.horizontal, Quiet.Space.s6)
                .padding(.vertical, Quiet.Space.s4)
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .clipped()

            footer
                .padding(.horizontal, Quiet.Space.s6)
                .padding(.bottom, Quiet.Space.s6)
        }
        .frame(width: OnboardingLayout.width, height: OnboardingLayout.height)
        .background(Quiet.canvas)
        .clipShape(RoundedRectangle(cornerRadius: Quiet.Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Quiet.Radius.lg, style: .continuous).strokeBorder(Quiet.line, lineWidth: 1))
        .ignoresSafeArea()
    }

    /// Pages fade and move a short way from the side they come from; Reduce Motion: fade only.
    private var pageTransition: AnyTransition {
        guard !reduceMotion else { return .opacity }
        let shift = Quiet.Space.s6
        return .asymmetric(
            insertion: .opacity.combined(with: .offset(x: model.forward ? shift : -shift)),
            removal: .opacity.combined(with: .offset(x: model.forward ? -shift : shift))
        )
    }

    // MARK: Progress and footer

    /// Neutral steps: the current one in `ink`, the rest in `ink-faint`.
    private var progress: some View {
        HStack(spacing: Quiet.Space.s2) {
            HStack(spacing: Quiet.Space.s1) {
                ForEach(OnboardingPage.allCases, id: \.self) { page in
                    Capsule()
                        .fill(page == model.page ? Quiet.ink : Quiet.inkFaint)
                        .frame(width: page == model.page ? Quiet.Space.s6 : Quiet.Space.s2, height: Quiet.Space.s1)
                }
            }
            .animation(reduceMotion ? nil : Quiet.Motion.base, value: model.page)
            Spacer(minLength: 0)
            Text(model.page.progressText)
                .font(Quiet.Font.caption)
                .foregroundStyle(Quiet.inkMuted)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(model.page.progressText)")
    }

    private var footer: some View {
        HStack(spacing: Quiet.Space.s3) {
            if model.page.previous != nil {
                Button("Back", action: onBack)
                    .help("Back (←)")
            }
            Spacer(minLength: 0)
            if !model.page.isLast {
                Button(action: onSkip) {
                    HStack(spacing: Quiet.Space.s1) {
                        KeyHint(keys: "esc")
                        Text("Skip").font(Quiet.Font.caption).foregroundStyle(Quiet.inkMuted)
                    }
                }
                .buttonStyle(.plain)
                .help("Skip the guide (esc)")
                .accessibilityLabel("Skip the guide")
            }
            Button(action: onNext) {
                AccentButtonLabel("\(model.page.nextTitle)  ↵")
            }
            .buttonStyle(.borderedProminent)
            .tint(Quiet.accent)
            .controlSize(.large)
            .help("\(model.page.nextTitle) (Return)")
            .accessibilityLabel(model.page.nextTitle)
        }
    }

    // MARK: Pages

    @ViewBuilder
    private func pageContent(_ page: OnboardingPage) -> some View {
        VStack(alignment: .leading, spacing: Quiet.Space.s4) {
            switch page {
            case .welcome: WelcomePage()
            case .screenshots: ScreenshotsPage()
            case .recording: RecordingPage()
            case .clipboard: ClipboardPage()
            case .ready: ReadyPage()
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
    }
}

/// A page's title and one or two lines under it.
private struct PageHeading: View {
    let page: OnboardingPage
    let text: String

    var body: some View {
        VStack(alignment: .leading, spacing: Quiet.Space.s2) {
            Text(page.title)
                .font(Quiet.Font.title3)
                .foregroundStyle(Quiet.ink)
                .accessibilityAddTraits(.isHeader)
            Text(text)
                .font(Quiet.Font.nativeBody)
                .foregroundStyle(Quiet.inkMuted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// A row naming an action, with its key on the right.
private struct KeyRow: View {
    let title: String
    var detail: String?
    let keys: String

    var body: some View {
        SettingsRow(title: title, detail: detail) {
            KeyHint(keys: keys)
        }
    }
}

private struct WelcomePage: View {
    @ObservedObject private var hotkeys = HotkeyService.shared

    var body: some View {
        HStack(alignment: .center, spacing: Quiet.Space.s4) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: QuietTokens.space16, height: QuietTokens.space16)
                .accessibilityHidden(true)
            PageHeading(
                page: .welcome,
                text: "DocShot waits in the menu bar. Nothing is saved or sent anywhere until you choose."
            )
        }
        SettingsGroup(title: "Your shortcuts", note: "They work from any app. Change them in Settings, under Shortcuts.") {
            KeyRow(title: "Take a screenshot", keys: hotkeys.binding(for: .screenshot).shortcutDisplay)
            SettingsDivider()
            KeyRow(title: "Record the screen", detail: "Press again to stop.", keys: hotkeys.binding(for: .record).shortcutDisplay)
            SettingsDivider()
            KeyRow(title: "Open clipboard history", keys: hotkeys.binding(for: .openWindow).shortcutDisplay)
        }
    }
}

private struct ScreenshotsPage: View {
    @ObservedObject private var hotkeys = HotkeyService.shared

    var body: some View {
        PageHeading(
            page: .screenshots,
            text: "Press \(hotkeys.binding(for: .screenshot).shortcutDisplay), then click a window or drag over an area. Escape cancels."
        )
        SettingsGroup(
            title: "Then a preview shows in the corner",
            note: "Edit adds arrows, boxes, text and highlights, hides private details, and crops."
        ) {
            ForEach(Array(PreviewThumbnailAction.displayOrder.enumerated()), id: \.offset) { index, action in
                if index > 0 { SettingsDivider() }
                KeyRow(title: action.title, keys: action.keyHint)
            }
        }
    }
}

private struct RecordingPage: View {
    @ObservedObject private var hotkeys = HotkeyService.shared

    var body: some View {
        let record = hotkeys.binding(for: .record).shortcutDisplay
        PageHeading(
            page: .recording,
            text: "Press \(record), click a window or drag over an area on one display, then press Return to start."
        )
        SettingsGroup(title: "While it records", note: "Nothing is kept until you choose.") {
            KeyRow(title: "Stop", detail: "Or the Stop button in the small panel that shows while recording, or Stop Recording in the menu.", keys: record)
            SettingsDivider()
            SettingsRow(title: "Sound", detail: "Change it in Settings, under Capture.") {
                Text(RecordingCoordinator.shared.selectedAudioDescription)
                    .font(Quiet.Font.caption)
                    .foregroundStyle(Quiet.inkMuted)
            }
            SettingsDivider()
            SettingsRow(
                title: "When it ends",
                detail: "Save as MP4, edit it, export a GIF (up to 15 seconds) or discard it."
            ) {
                EmptyView()
            }
        }
    }
}

private struct ClipboardPage: View {
    @ObservedObject private var history = ClipboardHistoryController.shared
    @ObservedObject private var hotkeys = HotkeyService.shared

    var body: some View {
        PageHeading(
            page: .clipboard,
            text: "DocShot can remember what you copy, so you can paste it again later. It stays on this Mac, and it is off until you switch it on."
        )
        SettingsGroup(
            title: "Clipboard history",
            note: "Copies that apps mark as passwords are never kept. Limits and apps to leave out are in Settings, under Clipboard."
        ) {
            SettingsToggleRow(
                title: "Keep clipboard history",
                isOn: Binding(get: { history.isEnabled }, set: { history.setEnabled($0) })
            )
            SettingsDivider()
            KeyRow(title: "Open history", keys: hotkeys.binding(for: .openWindow).shortcutDisplay)
        }
    }
}

private struct ReadyPage: View {
    @ObservedObject private var launchAtLoginService = LaunchAtLoginService.shared

    var body: some View {
        PageHeading(page: .ready, text: "You can change all of this later in Settings.")
        SavingSettingsGroup()
        SettingsGroup(title: "Startup") {
            SettingsToggleRow(
                title: "Open at login",
                detail: launchAtLoginService.errorMessage,
                detailIsError: launchAtLoginService.errorMessage != nil,
                isOn: Binding(get: { launchAtLoginService.isEnabled }, set: { launchAtLoginService.setEnabled($0) })
            )
        }
        .onAppear { launchAtLoginService.refresh() }
    }
}

// MARK: - Window

/// A borderless panel that still takes the keyboard.
final class OnboardingPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

@MainActor
public final class OnboardingWindowController: NSObject {
    public static let shared = OnboardingWindowController()

    static let identifier = NSUserInterfaceItemIdentifier("DocShotOnboarding")
    static let completedKey = "hasCompletedOnboarding"

    let model = OnboardingModel()
    private var panel: OnboardingPanel?
    private var keyMonitor: Any?
    /// Counts shows, so a fade-out that a new show interrupted does not hide the panel.
    private var showCount = 0
    /// Fading out: it no longer counts as showing.
    private var isClosing = false
    /// Where the guide is going: the page last asked for, which `model.page` reaches on the
    /// next turn of the run loop. Next and Back count from here, so quick presses add up.
    private var target: OnboardingPage = .welcome

    /// Where "finished the guide" is kept: the real preferences, or in a debug run on a scratch
    /// store (`DOCSHOT_DEBUG_STORE`), scratch preferences.
    static var preferences: UserDefaults {
#if DEBUG
        if let folder = ProcessInfo.processInfo.environment["DOCSHOT_DEBUG_STORE"], !folder.isEmpty,
           let scratch = UserDefaults(suiteName: "DocShotDebugStore") {
            return scratch
        }
#endif
        return .standard
    }

    var isShowing: Bool { panel?.isVisible == true && !isClosing }

    private override init() {
        super.init()
    }

    public func showOnboardingIfNeeded() {
        if !Self.preferences.bool(forKey: Self.completedKey) {
            showOnboarding()
        }
    }

    public func showOnboarding() {
        if let panel, panel.isVisible, !isClosing {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
            return
        }
        showCount += 1
        isClosing = false
        model.forward = true
        model.page = .welcome
        target = .welcome

        let panel = self.panel ?? makePanel()
        self.panel = panel
        let visible = Self.screenUnderPointer?.visibleFrame ?? NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        let frame = OnboardingLayout.frame(within: visible)
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        // Rises 8 points and fades in (Reduce Motion: fade only).
        panel.setFrame(reduceMotion ? frame : frame.offsetBy(dx: 0, dy: -Quiet.Space.s2), display: false)
        panel.alphaValue = 0
        panel.ignoresMouseEvents = false
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = QuietTokens.durBase
            context.timingFunction = Quiet.Motion.easeOutCurve
            panel.animator().alphaValue = 1
            if !reduceMotion { panel.animator().setFrame(frame, display: true) }
        }
    }

    public func closeOnboarding() {
        removeKeyMonitor()
        guard let panel, panel.isVisible, !isClosing else { return }
        isClosing = true
        let shown = showCount
        // It stops taking clicks and keys at once; the fade is only the look.
        panel.ignoresMouseEvents = true
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = QuietTokens.durFast
            context.timingFunction = Quiet.Motion.easeOutCurve
            panel.animator().alphaValue = 0
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                // Shown again while fading out: leave it.
                guard let self, self.showCount == shown else { return }
                self.isClosing = false
                panel.orderOut(nil)
            }
        })
    }

    /// Next, or on the last page, finish.
    func next() {
        guard let next = target.next else { return finish() }
        go(to: next)
    }

    func back() {
        guard let previous = target.previous else { return }
        go(to: previous)
    }

    /// Skip or finish: the guide is done and does not open again on its own.
    func finish() {
        Self.preferences.set(true, forKey: Self.completedKey)
        closeOnboarding()
    }

#if DEBUG
    /// The debug hook's page selection.
    func select(_ page: OnboardingPage) {
        if !isShowing { showOnboarding() }
        go(to: page)
    }
#endif

    /// The direction first, then the page on the next turn of the run loop, so the page
    /// leaving slides the right way too.
    private func go(to page: OnboardingPage) {
        guard page != target else { return }
        model.forward = page.rawValue > target.rawValue
        target = page
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
                withAnimation(reduceMotion ? Quiet.Motion.fade : Quiet.Motion.base) {
                    self.model.page = page
                }
            }
        }
    }

    private func makePanel() -> OnboardingPanel {
        let panel = OnboardingPanel(
            contentRect: NSRect(x: 0, y: 0, width: OnboardingLayout.width, height: OnboardingLayout.height),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.identifier = Self.identifier
        panel.title = "Welcome to DocShot"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = false
        panel.isMovableByWindowBackground = true
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        let host = NSHostingView(rootView: OnboardingView(
            model: model,
            onNext: { [weak self] in self?.next() },
            onBack: { [weak self] in self?.back() },
            onSkip: { [weak self] in self?.finish() }
        ))
        // The panel keeps its own size; the content never resizes it.
        host.sizingOptions = []
        panel.contentView = host
        return panel
    }

    private static var screenUnderPointer: NSScreen? {
        let mouse = NSEvent.mouseLocation
        return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
    }

    // MARK: Keys

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, let panel = self.panel, event.window === panel, panel.attachedSheet == nil, !self.isClosing else { return event }
            let modifiers = event.modifierFlags.intersection([.command, .option, .control])
            if modifiers == .command, event.charactersIgnoringModifiers?.lowercased() == "w" {
                // Like the old close button: closes without marking the guide done.
                self.closeOnboarding()
                return nil
            }
            guard let key = OnboardingKey.action(keyCode: event.keyCode, hasCommandOptionOrControl: !modifiers.isEmpty) else {
                return event
            }
            // A held key does not run through the pages or skip the guide.
            if event.isARepeat { return nil }
            // With keyboard navigation on, the arrows belong to a focused control (the
            // segmented "When you save" choice).
            if key == .back || event.keyCode == OnboardingKey.rightArrowKeyCode,
               panel.firstResponder is NSControl || panel.firstResponder is NSText {
                return event
            }
            switch key {
            case .next: self.next()
            case .back: self.back()
            case .skip: self.finish()
            }
            return nil
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }
}
