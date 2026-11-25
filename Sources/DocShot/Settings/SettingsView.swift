import AppKit
import SwiftUI

/// Settings as a compact panel (compact panels, decision 4; 24 November 2026): it drops down
/// under the menu bar icon with the everyday settings, and "All settings" grows it in place
/// into the four tabs (General, Clipboard, Capture, Shortcuts). The thumbnail's style:
/// borderless, `radius-lg`, the system shadow; its fill is `canvas`, not `surface`, because
/// the groups inside are `surface` panels and need the step between them to read. Every size change eases over
/// `dur-base` (content first, then the panel's edge on the next turn of the run loop; traced).
@MainActor
enum SettingsWindowFactory {
    static let identifier = NSUserInterfaceItemIdentifier("DocShotSettings")

    /// The panel's controller, for the debug hook.
    static var controller: SettingsWindowController { .shared }
}

/// The two states the panel shows.
@MainActor
final class SettingsPanelModel: ObservableObject {
    @Published var expanded = false
    @Published var tab = 0
    /// The tallest a tab's page may be on this screen, so the tab strip never goes off it.
    @Published var pageMaxHeight = SettingsPage<EmptyView>.maxHeight

    static let tabs: [(label: String, symbol: String)] = [
        ("General", "gearshape"), ("Clipboard", "doc.on.clipboard"),
        ("Capture", "camera.viewfinder"), ("Shortcuts", "command"),
    ]
}

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    let model = SettingsPanelModel()
    private(set) var panel: SettingsPanel!
    private var host: SettingsHostingView!
    private var keyMonitor: Any?
    private var resignObserver: NSObjectProtocol?
    private var becomeActiveObserver: NSObjectProtocol?
    /// DocShot's own animations running, so a size change is never started on top of one.
    private var animationsRunning = 0
    /// A size change asked for while an animation runs; done once it ends.
    private var needsResize = false
    /// DocShot itself sent the user to System Settings: stay open until they come back, so the
    /// row shows the new permission.
    private var awayOnPurpose = false

    var isShowing: Bool { panel?.isVisible == true }

    private override init() {
        super.init()
        let panel = SettingsPanel(
            contentRect: NSRect(x: 0, y: 0, width: SettingsPanelLayout.compactWidth, height: 300),
            styleMask: [.borderless],
            backing: .buffered,
            defer: false
        )
        panel.identifier = SettingsWindowFactory.identifier
        panel.title = "DocShot Settings"
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.isReleasedWhenClosed = false
        panel.hidesOnDeactivate = false
        panel.isFloatingPanel = false
        panel.collectionBehavior = [.moveToActiveSpace, .fullScreenAuxiliary]
        panel.delegate = self
        let host = SettingsHostingView(SettingsPanelView(
            model: model,
            onExpand: { [weak self] tab in self?.expand(to: tab) },
            onCollapse: { [weak self] in self?.collapse() },
            onClose: { [weak self] in self?.close() }
        ))
        host.onIdealSizeChange = { [weak self] in self?.resize(animated: true) }
        panel.contentView = host
        self.panel = panel
        self.host = host
    }

    /// The menu's Settings... item: open compact, close it if it is in front, or bring it
    /// forward if it is open behind something.
    func toggle() {
        if isShowing && panel.isKeyWindow {
            close()
        } else if isShowing {
            NSApp.activate(ignoringOtherApps: true)
            panel.makeKeyAndOrderFront(nil)
        } else {
            show()
        }
    }

    /// Called just before DocShot opens System Settings for a permission.
    func stayOpenWhileAway() {
        guard isShowing else { return }
        awayOnPurpose = true
    }

    func show() {
        model.expanded = false
        awayOnPurpose = false
        let visible = Self.anchorScreen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? CGRect(x: 0, y: 0, width: 1440, height: 900)
        model.pageMaxHeight = SettingsPanelLayout.pageMaxHeight(within: visible, cap: SettingsPage<EmptyView>.maxHeight)
        let size = measuredSize()
        let frame = SettingsPanelLayout.frame(size: size, anchor: Self.statusItemFrame, visible: visible)
        let reduceMotion = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        // Drops 8 points down from the menu bar and fades in (Reduce Motion: fade only).
        panel.setFrame(reduceMotion ? frame : frame.offsetBy(dx: 0, dy: Quiet.Space.s2), display: false)
        panel.alphaValue = 0
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        installKeyMonitor()
        watchDeactivation()
        animate(reduceMotion: false) { [panel] in
            panel!.animator().alphaValue = 1
            if !reduceMotion { panel!.animator().setFrame(frame, display: true) }
        }
    }

    func close() {
        removeKeyMonitor()
        stopWatchingDeactivation()
        awayOnPurpose = false
        needsResize = false
        panel.orderOut(nil)
    }

    /// "All settings", or a Change... that needs a full tab: grow in place to the tabs.
    func expand(to tab: Int) {
        guard SettingsPanelModel.tabs.indices.contains(tab) else { return }
        if !isShowing { show() }
        model.tab = tab
        model.expanded = true
        resizeOnNextTurn()
    }

    func collapse() {
        model.expanded = false
        resizeOnNextTurn()
    }

    /// The debug hook's tab selection.
    func select(_ tab: Int) { expand(to: tab) }

    // MARK: Size

    /// What the content wants: its ideal size once laid out.
    private func measuredSize() -> CGSize {
        host.layoutSubtreeIfNeeded()
        let size = host.fittingSize
        return CGSize(width: max(size.width, 1), height: max(size.height, 1))
    }

    /// Content changes first; the panel's edge animates on the next turn of the run loop, so a
    /// layout pass never cuts the animation short.
    private func resizeOnNextTurn() {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated { self?.resize(animated: true) }
        }
    }

    private func resize(animated: Bool) {
        guard isShowing else { return }
        guard animationsRunning == 0 else {
            needsResize = true // done once the running animation ends
            return
        }
        needsResize = false
        let size = measuredSize()
        let visible = panel.screen?.visibleFrame ?? NSScreen.main?.visibleFrame ?? panel.frame
        let target = SettingsPanelLayout.resized(panel.frame, to: size, within: visible)
        guard target.size != panel.frame.size || target.origin != panel.frame.origin else { return }
        let reduceMotion = !animated || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        animate(reduceMotion: reduceMotion) { [panel] in
            if reduceMotion { panel!.setFrame(target, display: true) } else { panel!.animator().setFrame(target, display: true) }
        }
    }

    private func animate(reduceMotion: Bool, changes: @escaping () -> Void) {
        animationsRunning += 1
        if reduceMotion {
            changes()
            animationsRunning -= 1
            return
        }
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = QuietTokens.durBase
            context.timingFunction = Quiet.Motion.easeOutCurve
            changes()
        }, completionHandler: { [weak self] in
            MainActor.assumeIsolated {
                guard let self else { return }
                self.animationsRunning -= 1
                if self.animationsRunning == 0 && self.needsResize { self.resize(animated: true) }
            }
        })
    }

    // MARK: Where the menu bar icon is

    /// DocShot's status item, drawn in its own small window in the menu bar. With several
    /// displays each has a copy: take the one on the display the pointer is on (the user just
    /// clicked it). Nil if hidden, which places the panel at the top right of that display.
    static var statusItemFrame: CGRect? {
        let items = NSApp.windows
            .filter { String(describing: type(of: $0)).contains("StatusBar") && $0.isVisible }
            .map(\.frame)
        let mouse = NSEvent.mouseLocation
        if let screen = NSScreen.screens.first(where: { NSMouseInRect(mouse, $0.frame, false) }),
           let onScreen = items.first(where: { screen.frame.intersects($0) }) {
            return onScreen
        }
        return items.first
    }

    static var anchorScreen: NSScreen? {
        guard let anchor = statusItemFrame else {
            let mouse = NSEvent.mouseLocation
            return NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) } ?? NSScreen.main
        }
        return NSScreen.screens.first { $0.frame.intersects(anchor) } ?? NSScreen.main
    }

    // MARK: Closing

    private func installKeyMonitor() {
        guard keyMonitor == nil else { return }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, event.window === self.panel, self.panel.attachedSheet == nil else { return event }
            let modifiers = event.modifierFlags.intersection([.command, .option, .control, .shift])
            let escape = event.keyCode == 53 && modifiers.isEmpty
            let commandW = event.charactersIgnoringModifiers?.lowercased() == "w" && modifiers == .command
            guard escape || commandW else { return event }
            self.close()
            return nil
        }
    }

    private func removeKeyMonitor() {
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        keyMonitor = nil
    }

    /// Closes when the user goes to another app, like a popover, unless DocShot sent them to
    /// System Settings. DocShot's own folder picker and shortcut recorder keep it open.
    private func watchDeactivation() {
        guard resignObserver == nil else { return }
        resignObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didResignActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.awayOnPurpose else { return }
                self.close()
            }
        }
        becomeActiveObserver = NotificationCenter.default.addObserver(
            forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.awayOnPurpose = false }
        }
    }

    private func stopWatchingDeactivation() {
        if let resignObserver { NotificationCenter.default.removeObserver(resignObserver) }
        if let becomeActiveObserver { NotificationCenter.default.removeObserver(becomeActiveObserver) }
        resignObserver = nil
        becomeActiveObserver = nil
    }

    /// A click on another DocShot window closes it too. Checked on the next turn, once a sheet
    /// or modal picker that took the keyboard is in place: those keep it open.
    func windowDidResignKey(_ notification: Notification) {
        DispatchQueue.main.async { [weak self] in
            MainActor.assumeIsolated {
                guard let self, self.isShowing, !self.panel.isKeyWindow, !self.awayOnPurpose,
                      self.panel.attachedSheet == nil, NSApp.modalWindow == nil else { return }
                // DocShot no longer active: the deactivation observer decides.
                guard NSApp.isActive else { return }
                self.close()
            }
        }
    }
}

/// A borderless panel that still takes the keyboard.
final class SettingsPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { true }
}

/// The panel's content: the compact everyday settings, or the four tabs.
struct SettingsPanelView: View {
    @ObservedObject var themeController = ThemeController.shared
    @ObservedObject var model: SettingsPanelModel
    let onExpand: (Int) -> Void
    let onCollapse: () -> Void
    let onClose: () -> Void

    var body: some View {
        // One container, so the background, clip and edge are drawn once while the two states
        // cross-fade.
        ZStack(alignment: .topLeading) {
            if model.expanded {
                VStack(spacing: 0) {
                    tabStrip
                    Rectangle().fill(Quiet.line).frame(height: 1)
                    switch model.tab {
                    case 0: GeneralSettingsView()
                    case 1: ClipboardSettingsSection()
                    case 2: CaptureSettingsView()
                    default: ShortcutsSettingsView()
                    }
                }
                .transition(.opacity.animation(Quiet.Motion.fade))
            } else {
                CompactSettingsView(onExpand: onExpand, onAllSettings: { onExpand(model.tab) }, onClose: onClose)
                    .transition(.opacity.animation(Quiet.Motion.fade))
            }
        }
        .environment(\.settingsPageMaxHeight, model.pageMaxHeight)
        .fixedSize()
        .frame(minWidth: 0, maxWidth: .infinity, minHeight: 0, maxHeight: .infinity, alignment: .topLeading)
        .background(Quiet.canvas)
        .clipShape(RoundedRectangle(cornerRadius: Quiet.Radius.lg, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Quiet.Radius.lg, style: .continuous).strokeBorder(Quiet.line, lineWidth: 1))
        .ignoresSafeArea()
    }

    /// Back to the compact view, then the four tabs as one neutral segmented strip.
    private var tabStrip: some View {
        HStack(spacing: Quiet.Space.s2) {
            Button(action: onCollapse) {
                Image(systemName: "chevron.left")
                    .font(Quiet.Font.ui)
                    .foregroundStyle(Quiet.inkMuted)
                    .padding(Quiet.Space.s2)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Fewer settings")
            .accessibilityLabel("Fewer settings")
            ForEach(Array(SettingsPanelModel.tabs.enumerated()), id: \.offset) { index, tab in
                Button {
                    model.tab = index
                    onExpand(index)
                } label: {
                    Label(tab.label, systemImage: tab.symbol)
                        .font(Quiet.Font.ui)
                        .foregroundStyle(model.tab == index ? Quiet.ink : Quiet.inkMuted)
                        .padding(.horizontal, Quiet.Space.s3)
                        .padding(.vertical, Quiet.Space.s1)
                        .background(
                            RoundedRectangle(cornerRadius: Quiet.Radius.sm, style: .continuous)
                                .fill(model.tab == index ? Quiet.selection : Color.clear)
                        )
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityAddTraits(model.tab == index ? .isSelected : [])
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, Quiet.Space.s4)
        .padding(.vertical, Quiet.Space.s3)
        .frame(width: SettingsPage<EmptyView>.width)
    }
}

/// The everyday settings (compact panels, decision 4): theme, clipboard history, the
/// open-clipboard shortcut, how saving works, open at login; "All settings" for the rest.
struct CompactSettingsView: View {
    @ObservedObject private var themeController = ThemeController.shared
    @ObservedObject private var history = ClipboardHistoryController.shared
    @ObservedObject private var hotkeyService = HotkeyService.shared
    @ObservedObject private var launchAtLoginService = LaunchAtLoginService.shared
    let onExpand: (Int) -> Void
    /// Back to the tab last open.
    let onAllSettings: () -> Void
    let onClose: () -> Void

    var body: some View {
        SettingsPage(width: SettingsPanelLayout.compactWidth) {
            SettingsGroup(title: "Appearance") {
                HStack(spacing: Quiet.Space.s4) {
                    ForEach(ColorTheme.allCases) { theme in
                        CompactThemeButton(theme: theme, isSelected: themeController.theme == theme) {
                            themeController.select(theme)
                        }
                    }
                }
                .padding(Quiet.Space.s4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            SettingsGroup(title: "Clipboard") {
                SettingsToggleRow(
                    title: "Keep clipboard history",
                    isOn: Binding(get: { history.isEnabled }, set: { history.setEnabled($0) })
                )
                if history.isEnabled {
                    SettingsDivider()
                    SettingsToggleRow(
                        title: "Pause recording",
                        isOn: Binding(get: { history.isPaused }, set: { history.setPaused($0) })
                    )
                }
                SettingsDivider()
                SettingsRow(title: "Open history") {
                    KeyHint(keys: hotkeyService.binding(for: .openWindow).shortcutDisplay)
                    Button("Change…") { onExpand(3) }
                }
            }
            SettingsGroup(title: "Saving and startup") {
                SettingsRow(title: "When you save", detail: saveSummary) {
                    Button("Change…") { onExpand(0) }
                }
                SettingsDivider()
                SettingsToggleRow(
                    title: "Open at login",
                    detail: launchAtLoginService.errorMessage,
                    detailIsError: launchAtLoginService.errorMessage != nil,
                    isOn: Binding(get: { launchAtLoginService.isEnabled }, set: { launchAtLoginService.setEnabled($0) })
                )
            }
            HStack {
                Button(action: onAllSettings) {
                    Label("All settings", systemImage: "slider.horizontal.3")
                }
                Spacer()
                Button(action: onClose) {
                    HStack(spacing: Quiet.Space.s1) {
                        KeyHint(keys: "esc")
                        Text("Close").font(Quiet.Font.caption).foregroundStyle(Quiet.inkFaint)
                    }
                }
                .buttonStyle(.plain)
                .help("Close (esc)")
                .accessibilityLabel("Close")
            }
        }
        .onAppear { launchAtLoginService.refresh() }
    }

    private var saveSummary: String {
        switch OutputFolderService.shared.currentMode {
        case .askWhereToSave: return "Asks where each time"
        case .useDefaultFolder:
            let path = OutputFolderService.shared.displayPath ?? ""
            return path.isEmpty ? "Uses a folder" : "Into " + (path as NSString).lastPathComponent
        }
    }
}

/// A theme as a coloured dot with its name, for the compact panel.
private struct CompactThemeButton: View {
    let theme: ColorTheme
    let isSelected: Bool
    let action: () -> Void
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let accent = Color(nsColor: NSColor(themeRGB: theme.surfaces(isDark: colorScheme == .dark).accent))
        Button(action: action) {
            VStack(spacing: Quiet.Space.s1) {
                Circle()
                    .fill(accent)
                    .frame(width: 24, height: 24)
                    // The selected ring sits one space-1 outside the dot.
                    .padding(Quiet.Space.s1)
                    .overlay(Circle().strokeBorder(isSelected ? Quiet.ink : Color.clear, lineWidth: 2))
                Text(theme.displayName)
                    .font(Quiet.Font.caption.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(Quiet.ink)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(theme.displayName): \(theme.summary)")
        .accessibilityLabel(theme.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

/// SwiftUI content placed by frame, not constraints, so it never forces the panel's size; it
/// reports when its ideal size changes so the panel can ease to it.
final class SettingsHostingView: NSHostingView<AnyView> {
    var onIdealSizeChange: (() -> Void)?

    init<Content: View>(_ content: Content) {
        super.init(rootView: AnyView(content))
        sizingOptions = [.intrinsicContentSize]
        translatesAutoresizingMaskIntoConstraints = true
    }

    @MainActor required init(rootView: AnyView) {
        super.init(rootView: rootView)
    }

    @MainActor required init?(coder: NSCoder) { nil }

    override func invalidateIntrinsicContentSize() {
        super.invalidateIntrinsicContentSize()
        DispatchQueue.main.async { [weak self] in self?.onIdealSizeChange?() }
    }
}

// MARK: - General

struct GeneralSettingsView: View {
    @ObservedObject private var themeController = ThemeController.shared
    @ObservedObject private var launchAtLoginService = LaunchAtLoginService.shared
    @State private var hasPermission: Bool = PermissionService.shared.hasScreenCaptureAccess()

    var body: some View {
        SettingsPage {
            SettingsGroup(
                title: "Appearance",
                note: "Changes DocShot's own windows only. Captures, exports and annotation colours stay the same, and light or dark follows macOS."
            ) {
                HStack(spacing: Quiet.Space.s3) {
                    ForEach(ColorTheme.allCases) { theme in
                        ThemeSwatchButton(theme: theme, isSelected: themeController.theme == theme) {
                            themeController.select(theme)
                        }
                    }
                }
                .padding(Quiet.Space.s4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            SettingsGroup(title: "Startup") {
                SettingsToggleRow(
                    title: "Open at login",
                    detail: launchAtLoginService.errorMessage ?? "DocShot waits in the menu bar from when you log in.",
                    detailIsError: launchAtLoginService.errorMessage != nil,
                    isOn: Binding(
                        get: { launchAtLoginService.isEnabled },
                        set: { launchAtLoginService.setEnabled($0) }
                    )
                )
            }

            SavingSettingsGroup()

            SettingsGroup(title: "Permissions") {
                SettingsRow(
                    title: "Screen recording",
                    detail: hasPermission
                        ? "Allowed. DocShot can see windows and capture the screen."
                        : "Not allowed. DocShot needs it to find windows and take screenshots.",
                    detailIsError: !hasPermission
                ) {
                    Button("Open System Settings") {
                        SettingsWindowController.shared.stayOpenWhileAway()
                        PermissionService.shared.openSystemSettingsScreenRecording()
                    }
                }
            }

            SettingsGroup(
                title: "Help",
                note: "DocShot works only on this Mac. It never saves on its own, keeps no analytics and talks to no server; nothing leaves your Mac unless you copy or save it."
            ) {
                SettingsRow(title: "Guide", detail: "The short tour from the first launch.") {
                    Button("Open guide") {
                        OnboardingWindowController.shared.showOnboarding()
                    }
                }
            }
        }
        .onAppear {
            launchAtLoginService.refresh()
            hasPermission = PermissionService.shared.hasScreenCaptureAccess()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            hasPermission = PermissionService.shared.hasScreenCaptureAccess()
        }
    }

}

/// How saving works: ask each time or use a folder, with the folder's controls. Shared by the
/// General tab and the guide's last page, so both behave the same and write the same place.
struct SavingSettingsGroup: View {
    @State private var outputFolderMode: OutputFolderMode = OutputFolderService.shared.currentMode
    @State private var folderPathDisplay: String = OutputFolderService.shared.displayPath ?? "No folder selected"
    @State private var folderMessage: String?
    @State private var isMessageError = false

    var body: some View {
        SettingsGroup(title: "Saving") {
            SettingsRow(title: "When you save", detail: saveDetail) {
                Picker("When you save", selection: Binding(
                    get: { outputFolderMode },
                    set: { choose($0) }
                )) {
                    Text("Ask each time").tag(OutputFolderMode.askWhereToSave)
                    Text("Use a folder").tag(OutputFolderMode.useDefaultFolder)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                .fixedSize()
                // Quiet SegmentedControl: a neutral thumb, never the system blue or the accent.
                .tint(Quiet.inkMuted)
            }
            if outputFolderMode == .useDefaultFolder {
                SettingsDivider()
                SettingsRow(title: "Folder", detail: folderPathDisplay, detailIsPath: true) {
                    Menu("Change") {
                        Button("Choose folder…") { chooseFolder() }
                        Button("Create a DocShot folder…") { createFolder() }
                    }
                    .fixedSize()
                    Button("Show in Finder") { revealFolder() }
                }
            }
            if let folderMessage {
                SettingsDivider()
                Text(folderMessage)
                    .font(Quiet.Font.caption)
                    .foregroundStyle(isMessageError ? Quiet.danger : Quiet.inkMuted)
                    .padding(.horizontal, Quiet.Space.s4)
                    .padding(.vertical, Quiet.Space.s3)
            }
        }
        .onAppear {
            outputFolderMode = OutputFolderService.shared.currentMode
            folderPathDisplay = OutputFolderService.shared.displayPath ?? "No folder selected"
            validateFolder()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            validateFolder()
        }
    }

    private var saveDetail: String {
        outputFolderMode == .askWhereToSave
            ? "DocShot asks where to save every time."
            : "Saves go straight to the folder below."
    }

    /// The two save choices, with the same effects as the radio buttons they replace.
    private func choose(_ mode: OutputFolderMode) {
        switch mode {
        case .askWhereToSave:
            outputFolderMode = .askWhereToSave
            OutputFolderService.shared.setModeAskWhereToSave()
            folderMessage = nil
        case .useDefaultFolder:
            let (url, _) = OutputFolderService.shared.resolveDefaultFolderURL()
            if let url {
                folderPathDisplay = url.path
                outputFolderMode = .useDefaultFolder
                OutputFolderService.shared.currentMode = .useDefaultFolder
                folderMessage = nil
                isMessageError = false
            } else {
                Task {
                    let res = await OutputFolderService.shared.selectDefaultFolder()
                    if let selectedURL = res.url {
                        folderPathDisplay = selectedURL.path
                        outputFolderMode = .useDefaultFolder
                        folderMessage = "Default folder updated."
                        isMessageError = false
                    } else {
                        outputFolderMode = .askWhereToSave
                        OutputFolderService.shared.setModeAskWhereToSave()
                        if let err = res.errorMessage {
                            folderMessage = err
                            isMessageError = true
                        }
                    }
                }
            }
        }
    }

    private func chooseFolder() {
        Task {
            let res = await OutputFolderService.shared.selectDefaultFolder()
            if let url = res.url {
                folderPathDisplay = url.path
                outputFolderMode = .useDefaultFolder
                folderMessage = "Default folder updated."
                isMessageError = false
            } else if let err = res.errorMessage {
                folderMessage = err
                isMessageError = true
            }
        }
    }

    private func createFolder() {
        Task {
            let res = await OutputFolderService.shared.createDocShotFolder()
            if let url = res.url {
                folderPathDisplay = url.path
                outputFolderMode = .useDefaultFolder
                folderMessage = "DocShot folder created and set as default."
                isMessageError = false
            } else if let err = res.errorMessage {
                folderMessage = err
                isMessageError = true
            }
        }
    }

    private func revealFolder() {
        if let err = OutputFolderService.shared.revealInFinder() {
            folderMessage = err
            isMessageError = true
            outputFolderMode = OutputFolderService.shared.currentMode
            folderPathDisplay = OutputFolderService.shared.displayPath ?? "No folder selected"
        } else {
            folderMessage = nil
        }
    }

    private func validateFolder() {
        // The guide and the General tab can both be open: start from what is saved.
        outputFolderMode = OutputFolderService.shared.currentMode
        folderPathDisplay = OutputFolderService.shared.displayPath ?? "No folder selected"
        if outputFolderMode == .useDefaultFolder {
            let (url, staleReason) = OutputFolderService.shared.resolveDefaultFolderURL()
            if let url {
                folderPathDisplay = url.path
                folderMessage = nil
                isMessageError = false
            } else if let staleReason {
                folderMessage = staleReason
                isMessageError = true
                outputFolderMode = .askWhereToSave
                folderPathDisplay = "No folder selected"
            }
        }
    }
}

// MARK: - Capture

struct CaptureSettingsView: View {
    @ObservedObject private var themeController = ThemeController.shared
    @State private var includeCursor: Bool = UserDefaults.standard.bool(forKey: "DocShotIncludeCursor")
    @State private var recordSystemAudio: Bool = UserDefaults.standard.bool(forKey: "DocShotRecordSystemAudio")
    @State private var recordCursor: Bool = UserDefaults.standard.bool(forKey: "DocShotRecordIncludeCursor")
    @State private var recordFrameRate: Int = {
        let saved = UserDefaults.standard.integer(forKey: "DocShotRecordingFrameRate")
        return saved == 0 ? 30 : saved
    }()

    var body: some View {
        SettingsPage {
            SettingsGroup(title: "Screenshots") {
                SettingsToggleRow(
                    title: "Include the pointer",
                    detail: "Screenshots show the mouse pointer. Off by default.",
                    accessibilityName: "Include the pointer in screenshots",
                    isOn: $includeCursor
                )
            }
            SettingsGroup(title: "Recordings") {
                SettingsToggleRow(
                    title: "Include system audio",
                    detail: "Captured only after you choose Record. Microphone audio is not available yet.",
                    isOn: $recordSystemAudio
                )
                SettingsDivider()
                SettingsToggleRow(
                    title: "Include the pointer",
                    accessibilityName: "Include the pointer in recordings",
                    isOn: $recordCursor
                )
                SettingsDivider()
                SettingsPickerRow(title: "Frame rate", detail: "The most frames a second.", selection: $recordFrameRate) {
                    Text("30 fps").tag(30)
                }
            }
        }
        .onChange(of: includeCursor) { _, value in UserDefaults.standard.set(value, forKey: "DocShotIncludeCursor") }
        .onChange(of: recordSystemAudio) { _, value in UserDefaults.standard.set(value, forKey: "DocShotRecordSystemAudio") }
        .onChange(of: recordCursor) { _, value in UserDefaults.standard.set(value, forKey: "DocShotRecordIncludeCursor") }
        .onChange(of: recordFrameRate) { _, value in UserDefaults.standard.set(value, forKey: "DocShotRecordingFrameRate") }
        .onAppear {
            includeCursor = UserDefaults.standard.bool(forKey: "DocShotIncludeCursor")
            recordSystemAudio = UserDefaults.standard.bool(forKey: "DocShotRecordSystemAudio")
            recordCursor = UserDefaults.standard.bool(forKey: "DocShotRecordIncludeCursor")
            let saved = UserDefaults.standard.integer(forKey: "DocShotRecordingFrameRate")
            recordFrameRate = saved == 0 ? 30 : saved
        }
    }
}

// MARK: - Shortcuts

struct ShortcutsSettingsView: View {
    /// The clipboard window's own keys (C3 plan, decision 4; restyle plan, decision 2), shown
    /// so they can be found without opening the window.
    static let windowKeys: [(action: String, keys: String)] = [
        ("Paste into the app you were in", "↵"),
        ("Paste one of the first nine", "⌘1–⌘9"),
        ("Copy without pasting", "⌘C"),
        ("Pin or unpin", "⌘P"),
        ("Delete", "⌘⌫"),
        ("Show or hide the preview", "⌘Y"),
        ("Move through the list", "↑ ↓"),
        ("Clear the search, then close", "esc"),
    ]

    @ObservedObject private var themeController = ThemeController.shared
    @ObservedObject private var hotkeyService = HotkeyService.shared
    @State private var registrationError: String? = HotkeyService.shared.lastError
    @State private var recorderAction: ShortcutAction?

    var body: some View {
        SettingsPage {
            SettingsGroup(
                title: "Shortcuts",
                note: registrationError == nil ? "Saved at once and active everywhere." : nil
            ) {
                let actions = ShortcutAction.allCases.filter(\.isRegistrable)
                ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                    if index > 0 { SettingsDivider() }
                    SettingsRow(title: action.title) {
                        KeyHint(keys: hotkeyService.binding(for: action).shortcutDisplay)
                        Button("Change…") { recorderAction = action }
                        Button("Reset") {
                            let success = hotkeyService.resetToDefault(action)
                            registrationError = success ? nil : hotkeyService.lastError
                        }
                        .disabled(hotkeyService.isUsingDefault(action))
                        .help("Reset to \(action.defaultBinding.shortcutDisplay)")
                    }
                }
            }
            if let registrationError {
                Label(registrationError, systemImage: "exclamationmark.triangle")
                    .font(Quiet.Font.caption)
                    .foregroundStyle(Quiet.danger)
            }
            SettingsGroup(
                title: "In the DocShot window",
                note: "These work while the DocShot window is open, and cannot be changed. Typing goes straight into the search."
            ) {
                ForEach(Array(Self.windowKeys.enumerated()), id: \.offset) { index, key in
                    if index > 0 { SettingsDivider() }
                    SettingsRow(title: key.action) {
                        KeyHint(keys: key.keys)
                    }
                }
            }
        }
        .onAppear { registrationError = HotkeyService.shared.lastError }
        .sheet(item: $recorderAction) { action in
            CustomShortcutRecorder(
                title: "\(action.title) shortcut",
                currentDisplay: hotkeyService.binding(for: action).shortcutDisplay
            ) { keyCode, modifiers, keyDisplay in
                let success = hotkeyService.setBinding(
                    ShortcutBinding(keyCode: keyCode, modifiers: modifiers, keyDisplay: keyDisplay),
                    for: action
                )
                registrationError = success ? nil : hotkeyService.lastError
            }
        }
    }
}

/// One theme in the Appearance section, drawn in the current light or dark mode so it shows
/// what picking it would look like.
private struct ThemeSwatchButton: View {
    let theme: ColorTheme
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        let surfaces = theme.surfaces(isDark: colorScheme == .dark)
        let accent = Color(nsColor: NSColor(themeRGB: surfaces.accent))

        Button(action: action) {
            VStack(spacing: 6) {
                ZStack(alignment: .bottomTrailing) {
                    RoundedRectangle(cornerRadius: Quiet.Radius.sm, style: .continuous)
                        .fill(color(surfaces.windowBackground, fallback: .windowBackgroundColor))
                    RoundedRectangle(cornerRadius: Quiet.Radius.sm - 6, style: .continuous)
                        .fill(color(surfaces.cardBackground, fallback: .controlBackgroundColor))
                        .padding(6)
                    Circle()
                        .fill(accent)
                        .frame(width: 12, height: 12)
                        .padding(11)
                }
                .frame(width: 88, height: 52)
                .overlay(
                    RoundedRectangle(cornerRadius: Quiet.Radius.sm, style: .continuous)
                        .stroke(
                            isSelected ? accent : color(surfaces.border, fallback: .separatorColor),
                            lineWidth: isSelected ? 2 : 1
                        )
                )
                Text(theme.displayName)
                    .font(Quiet.Font.caption.weight(isSelected ? .semibold : .regular))
                    .foregroundStyle(Quiet.ink)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("\(theme.displayName): \(theme.summary)")
        .accessibilityLabel(theme.displayName)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func color(_ rgb: ThemeRGB?, fallback: NSColor) -> Color {
        rgb.map { Color(nsColor: NSColor(themeRGB: $0)) } ?? Color(nsColor: fallback)
    }
}

