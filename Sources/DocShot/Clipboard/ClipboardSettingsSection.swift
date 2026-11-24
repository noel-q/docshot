import AppKit
import ClipboardKit
import SwiftUI
import UniformTypeIdentifiers

/// The Clipboard tab of Settings (plan section 5; C3: editable limits, excluded apps and
/// paste access; Quiet pilot step 3: groups of rows in panels, switches).
struct ClipboardSettingsSection: View {
    @ObservedObject var themeController = ThemeController.shared
    @ObservedObject var controller = ClipboardHistoryController.shared
    @ObservedObject private var hotkeyService = HotkeyService.shared

    @State private var confirmingClear = false
    /// The open-history shortcut, changeable here too (Noel, 24 November 2026).
    @State private var editingShortcut = false
    @State private var shortcutError: String?
    /// A limit change that would remove items, waiting for a yes.
    @State private var pendingLimits: PendingLimits?

    struct PendingLimits: Identifiable {
        let id = UUID()
        let maxItems: Int?
        let maxAgeDays: Int
        let maxMegabytes: Int
        let removals: Int
    }

    var body: some View {
        SettingsPage {
            SettingsGroup(title: "Clipboard history") {
                SettingsRow(
                    title: "Open clipboard history",
                    detail: shortcutError ?? "Works from any app. Also in the DocShot menu in the menu bar.",
                    detailIsError: shortcutError != nil
                ) {
                    KeyHint(keys: hotkeyService.binding(for: .openWindow).shortcutDisplay)
                    Button("Change…") { editingShortcut = true }
                    Button("Reset") {
                        shortcutError = hotkeyService.resetToDefault(.openWindow) ? nil : hotkeyService.lastError
                    }
                    .disabled(hotkeyService.isUsingDefault(.openWindow))
                    .help("Reset to \(ShortcutAction.openWindow.defaultBinding.shortcutDisplay)")
                }
                SettingsDivider()
                SettingsToggleRow(
                    title: "Keep clipboard history",
                    detail: "Stored on this Mac only. Off by default. Turning it off keeps what is stored until you clear it.",
                    isOn: Binding(get: { controller.isEnabled }, set: { controller.setEnabled($0) })
                )
                if controller.isEnabled {
                    SettingsDivider()
                    SettingsToggleRow(
                        title: "Pause recording",
                        detail: "Copies are not recorded until you resume.",
                        isOn: Binding(get: { controller.isPaused }, set: { controller.setPaused($0) })
                    )
                }
                if controller.isEnabled && controller.accessBlocked {
                    SettingsDivider()
                    SettingsRow(
                        title: "Clipboard access",
                        detail: "macOS asks before, or refuses, DocShot reading the clipboard, so history may miss copies. Change it in System Settings > Privacy & Security.",
                        detailIsError: true
                    ) { EmptyView() }
                }
            }

            if controller.isEnabled {
                limits
                pasting
                excludedApps
                clearing
            }

            if let problem = controller.problem {
                Label(problem, systemImage: "exclamationmark.triangle")
                    .font(Quiet.Font.caption)
                    .foregroundStyle(Quiet.danger)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .onAppear {
            controller.refreshAccessState()
            controller.refreshPasteAccess()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            // Back from System Settings: show whether Accessibility is now allowed.
            controller.refreshPasteAccess()
        }
        .sheet(isPresented: $editingShortcut) {
            CustomShortcutRecorder(
                title: "\(ShortcutAction.openWindow.title) shortcut",
                currentDisplay: hotkeyService.binding(for: .openWindow).shortcutDisplay
            ) { keyCode, modifiers, keyDisplay in
                let success = hotkeyService.setBinding(
                    ShortcutBinding(keyCode: keyCode, modifiers: modifiers, keyDisplay: keyDisplay),
                    for: .openWindow
                )
                shortcutError = success ? nil : hotkeyService.lastError
            }
        }
        .confirmationDialog(ClipboardSettings.clearQuestion(controller.clearCount), isPresented: $confirmingClear) {
            Button("Clear", role: .destructive) { controller.clear() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Keeps \(controller.clearKeep.title.lowercased()). \(ClipboardSettings.clearWarning)")
        }
        .confirmationDialog(
            "Remove \(pendingLimits?.removals ?? 0) item\(pendingLimits?.removals == 1 ? "" : "s") now?",
            isPresented: Binding(get: { pendingLimits != nil }, set: { if !$0 { pendingLimits = nil } }),
            presenting: pendingLimits
        ) { pending in
            Button("Remove", role: .destructive) {
                controller.setLimits(
                    maxItems: pending.maxItems, maxAgeDays: pending.maxAgeDays, maxMegabytes: pending.maxMegabytes
                )
            }
            Button("Cancel", role: .cancel) {}
        } message: { _ in
            Text("The new limit removes the oldest unpinned items. Pinned items stay. \(ClipboardSettings.clearWarning)")
        }
    }

    // MARK: - Limits (C3 plan, decision 6)

    private var limits: some View {
        SettingsGroup(
            title: "Limits",
            note: "Pinned items are always kept and do not count towards the item limit. With no item limit, the storage limit still applies. A single copy over \(RetentionLimits.maxItemBytes / (1024 * 1024)) MB is skipped."
        ) {
            SettingsPickerRow(title: "Keep items for", selection: Binding(
                get: { controller.maxAgeDays }, set: { change(maxAgeDays: $0) }
            )) {
                ForEach(ClipboardSettings.ageChoices, id: \.self) { Text("\($0) days").tag($0) }
            }
            SettingsDivider()
            SettingsPickerRow(title: "Most items", selection: Binding(
                get: { controller.maxItems ?? 0 },
                set: { change(maxItems: .some($0 == 0 ? nil : $0)) } // .some: "no limit" is a choice
            )) {
                ForEach(ClipboardSettings.itemChoices, id: \.self) { choice in
                    Text(choice.map(String.init) ?? "No limit").tag(choice ?? 0)
                }
            }
            SettingsDivider()
            SettingsPickerRow(title: "Most storage", selection: Binding(
                get: { controller.maxMegabytes }, set: { change(maxMegabytes: $0) }
            )) {
                ForEach(ClipboardSettings.megabyteChoices, id: \.self) { megabytes in
                    Text(megabytes >= 1024 ? "\(megabytes / 1024) GB" : "\(megabytes) MB").tag(megabytes)
                }
            }
        }
    }

    private func change(maxItems: Int?? = nil, maxAgeDays: Int? = nil, maxMegabytes: Int? = nil) {
        let items = maxItems ?? controller.maxItems
        let days = maxAgeDays ?? controller.maxAgeDays
        let megabytes = maxMegabytes ?? controller.maxMegabytes
        let removals = controller.removalCount(
            for: controller.limits(maxItems: items, maxAgeDays: days, maxMegabytes: megabytes)
        )
        if removals > 0 {
            pendingLimits = PendingLimits(
                maxItems: items, maxAgeDays: days, maxMegabytes: megabytes, removals: removals
            )
        } else {
            controller.setLimits(maxItems: items, maxAgeDays: days, maxMegabytes: megabytes)
        }
    }

    // MARK: - Pasting (C3 plan, decisions 1 and 2)

    private var pasting: some View {
        SettingsGroup(title: "Pasting") {
            SettingsToggleRow(
                title: "Paste into the app you were in",
                detail: pasteDetail,
                isOn: Binding(get: { controller.pasteDirectly }, set: { controller.setPasteDirectly($0) })
            )
            if controller.pasteDirectly && !controller.pasteAllowed {
                SettingsDivider()
                SettingsRow(title: "Accessibility", detail: "Not allowed yet. Until then, Return copies and you press ⌘V.") {
                    Button("Allow…") {
                        controller.markAccessRequested()
                        AccessibilityAccess.request()
                        AccessibilityAccess.openSettings()
                    }
                }
            }
        }
    }

    private var pasteDetail: String {
        guard controller.pasteDirectly else { return "Off: Return and a click copy, and you paste." }
        return controller.pasteAllowed
            ? "Return or a click in the DocShot window pastes."
            : "Needs Accessibility permission."
    }

    // MARK: - Excluded apps (C3 plan, decision 7)

    private var excludedApps: some View {
        SettingsGroup(
            title: "Never record copies from",
            note: "Copies marked secret by password managers are never recorded, whatever this list says."
        ) {
            ForEach(controller.excludedApps, id: \.self) { bundleID in
                HStack(spacing: Quiet.Space.s3) {
                    if let icon = Self.icon(for: bundleID) {
                        Image(nsImage: icon).resizable().frame(width: 20, height: 20)
                            .accessibilityHidden(true)
                    }
                    Text(Self.name(for: bundleID))
                        .font(Quiet.Font.ui)
                        .foregroundStyle(Quiet.ink)
                    Spacer()
                    Button {
                        controller.removeExcludedApp(bundleID)
                    } label: {
                        Image(systemName: "minus.circle")
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(Quiet.inkMuted)
                    .help("Remove")
                    .accessibilityLabel("Remove \(Self.name(for: bundleID))")
                }
                .padding(.horizontal, Quiet.Space.s4)
                .padding(.vertical, Quiet.Space.s2)
                SettingsDivider()
            }
            HStack(spacing: Quiet.Space.s2) {
                Button("Add app…") { chooseApp() }
                Button("Restore defaults") { controller.restoreDefaultExcludedApps() }
                Spacer()
            }
            .padding(.horizontal, Quiet.Space.s4)
            .padding(.vertical, Quiet.Space.s3)
        }
    }

    // MARK: - Clear

    private var clearing: some View {
        SettingsGroup(title: "Clear") {
            SettingsPickerRow(title: "Clear keeps", selection: Binding(
                get: { controller.clearKeep }, set: { controller.setClearKeep($0) }
            )) {
                ForEach(ClearKeep.allCases, id: \.self) { keep in
                    Text(keep.title).tag(keep)
                }
            }
            SettingsDivider()
            SettingsRow(title: "Clear history", detail: clearDetail) {
                Button("Clear history…", role: .destructive) { confirmingClear = true }
                    .disabled(controller.clearCount == 0)
            }
        }
    }

    private var clearDetail: String {
        let count = controller.clearCount
        return count == 0 ? "Nothing to clear." : "Removes \(ClipPreviewText.count(count, "item")) now."
    }

    private func chooseApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowsMultipleSelection = false
        panel.prompt = "Add"
        guard panel.runModal() == .OK, let url = panel.url,
              let bundleID = Bundle(url: url)?.bundleIdentifier else { return }
        controller.addExcludedApp(bundleID)
    }

    private static func name(for bundleID: String) -> String {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            return "\(bundleID) (not installed)"
        }
        return FileManager.default.displayName(atPath: url.path).replacingOccurrences(of: ".app", with: "")
    }

    private static func icon(for bundleID: String) -> NSImage? {
        NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)
            .map { NSWorkspace.shared.icon(forFile: $0.path) }
    }

}
