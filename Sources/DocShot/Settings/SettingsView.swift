import AppKit
import SwiftUI

/// Settings in Quiet (pilot step 3, agreed 24 November 2026): its own window with toolbar tabs
/// (General, Clipboard, Capture, Shortcuts), groups of rows in `surface` panels, and switches.
/// Every setting behaves as before; only where it sits and how it looks changed.
@MainActor
enum SettingsWindowFactory {
    static let identifier = NSUserInterfaceItemIdentifier("DocShotSettings")

    static func make() -> NSWindow {
        SettingsWindowController.shared.window!
    }

    /// The window's tabs, for the debug hook.
    static var controller: SettingsWindowController { .shared }
}

/// Settings tabs the way Mac Settings windows switch: a preferences toolbar, the new tab's
/// content at once, and the window easing to its height over Quiet's `dur-base` with the top
/// edge kept in place (a plain change under Reduce Motion). Drives the switch itself, because
/// `NSTabViewController` cross-faded and then jumped (Noel, 24 November 2026: "like a
/// PowerPoint"). A tab whose own height changes eases the same way.
@MainActor
final class SettingsWindowController: NSWindowController, NSToolbarDelegate {
    static let shared = SettingsWindowController()

    private struct Tab {
        let id: NSToolbarItem.Identifier
        let label: String
        let symbol: String
        let view: SettingsHostingView
    }

    private var tabs: [Tab] = []
    private let container = NSView()
    private(set) var selectedIndex = 0

    private init() {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: SettingsPage<EmptyView>.width, height: 400),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.identifier = SettingsWindowFactory.identifier
        window.isReleasedWhenClosed = false
        window.toolbarStyle = .preference
        super.init(window: window)

        tabs = [
            Tab(id: .init("general"), label: "General", symbol: "gearshape", view: SettingsHostingView(GeneralSettingsView())),
            Tab(id: .init("clipboard"), label: "Clipboard", symbol: "doc.on.clipboard", view: SettingsHostingView(ClipboardSettingsSection())),
            Tab(id: .init("capture"), label: "Capture", symbol: "camera.viewfinder", view: SettingsHostingView(CaptureSettingsView())),
            Tab(id: .init("shortcuts"), label: "Shortcuts", symbol: "command", view: SettingsHostingView(ShortcutsSettingsView())),
        ]
        for tab in tabs {
            tab.view.onIdealSizeChange = { [weak self, weak view = tab.view] in
                guard let self, let view, self.tabs[self.selectedIndex].view === view else { return }
                self.resize(animated: true)
            }
        }

        container.autoresizingMask = [.width, .height]
        window.contentView = container
        let toolbar = NSToolbar(identifier: "DocShotSettingsToolbar")
        toolbar.delegate = self
        toolbar.displayMode = .iconAndLabel
        toolbar.allowsUserCustomization = false
        window.toolbar = toolbar
        select(0, animated: false)
        window.center()
    }

    required init?(coder: NSCoder) { nil }

    func select(_ index: Int, animated: Bool = true) {
        guard tabs.indices.contains(index) else { return }
        selectedIndex = index
        let tab = tabs[index]
        window?.toolbar?.selectedItemIdentifier = tab.id
        window?.title = tab.label
        container.subviews.forEach { $0.removeFromSuperview() }
        tab.view.frame = container.bounds
        tab.view.autoresizingMask = [.width, .height]
        container.addSubview(tab.view)
        resize(animated: animated)
    }

    private func resize(animated: Bool) {
        guard let window else { return }
        let view = tabs[selectedIndex].view
        // Lay a tab out before measuring it: a tab not shown before otherwise measures a few
        // points off, and the correction a moment later restarts the animation with a jump.
        view.layoutSubtreeIfNeeded()
        let size = view.fittingSize
        guard size.height > 0 else { return }
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: size))
        frame.origin.x = window.frame.minX
        frame.origin.y = window.frame.maxY - frame.height
        guard frame.size != window.frame.size else { return }
        if !animated || !window.isVisible || NSWorkspace.shared.accessibilityDisplayShouldReduceMotion {
            window.setFrame(frame, display: true)
        } else {
            NSAnimationContext.runAnimationGroup { context in
                context.duration = QuietTokens.durBase
                context.timingFunction = CAMediaTimingFunction(controlPoints: 0.22, 1, 0.36, 1) // ease-out
                window.animator().setFrame(frame, display: true)
            }
        }
    }

    @objc private func toolbarItemClicked(_ sender: NSToolbarItem) {
        guard let index = tabs.firstIndex(where: { $0.id == sender.itemIdentifier }) else { return }
        select(index)
    }

    // MARK: NSToolbarDelegate

    func toolbarAllowedItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { tabs.map(\.id) }
    func toolbarDefaultItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { tabs.map(\.id) }
    func toolbarSelectableItemIdentifiers(_ toolbar: NSToolbar) -> [NSToolbarItem.Identifier] { tabs.map(\.id) }

    func toolbar(_ toolbar: NSToolbar, itemForItemIdentifier id: NSToolbarItem.Identifier,
                 willBeInsertedIntoToolbar flag: Bool) -> NSToolbarItem? {
        guard let tab = tabs.first(where: { $0.id == id }) else { return nil }
        let item = NSToolbarItem(itemIdentifier: id)
        item.label = tab.label
        item.image = NSImage(systemSymbolName: tab.symbol, accessibilityDescription: tab.label)
        item.target = self
        item.action = #selector(toolbarItemClicked(_:))
        return item
    }
}

/// A tab's SwiftUI content. It is placed by frame, not constraints, so it never forces the
/// window's size; it reports when its ideal size changes so the window can ease to it.
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
    @State private var outputFolderMode: OutputFolderMode = OutputFolderService.shared.currentMode
    @State private var folderPathDisplay: String = OutputFolderService.shared.displayPath ?? "No folder selected"
    @State private var folderMessage: String?
    @State private var isMessageError = false

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

            SettingsGroup(title: "Permissions") {
                SettingsRow(
                    title: "Screen recording",
                    detail: hasPermission
                        ? "Allowed. DocShot can see windows and capture the screen."
                        : "Not allowed. DocShot needs it to find windows and take screenshots.",
                    detailIsError: !hasPermission
                ) {
                    Button("Open System Settings") {
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
            outputFolderMode = OutputFolderService.shared.currentMode
            folderPathDisplay = OutputFolderService.shared.displayPath ?? "No folder selected"
            validateFolder()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            hasPermission = PermissionService.shared.hasScreenCaptureAccess()
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

