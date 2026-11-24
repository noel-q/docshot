import AppKit
import ClipboardKit
import SwiftUI
import UniformTypeIdentifiers

/// The "Clipboard history" section in Settings (plan section 5; C3: editable limits, excluded
/// apps and paste access).
struct ClipboardSettingsSection: View {
    @ObservedObject var themeController = ThemeController.shared
    @ObservedObject var controller = ClipboardHistoryController.shared

    @State private var confirmingClear = false
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
        VStack(alignment: .leading, spacing: 8) {
            Text("Clipboard History")
                .font(.system(size: 13, weight: .semibold))

            Toggle(isOn: Binding(
                get: { controller.isEnabled },
                set: { controller.setEnabled($0) }
            )) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Keep clipboard history")
                        .font(.system(size: 13, weight: .medium))
                    note("Off by default. Stored on this Mac only. Turning it off stops recording; what is kept stays until you clear it.")
                }
            }

            if controller.isEnabled {
                Toggle("Pause history", isOn: Binding(
                    get: { controller.isPaused },
                    set: { controller.setPaused($0) }
                ))

                HStack {
                    Picker("Clear keeps", selection: Binding(
                        get: { controller.clearKeep },
                        set: { controller.setClearKeep($0) }
                    )) {
                        ForEach(ClearKeep.allCases, id: \.self) { keep in
                            Text(keep.title).tag(keep)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(maxWidth: 260)
                    Button("Clear Now…") { confirmingClear = true }
                        .disabled(controller.items.isEmpty)
                }

                limits
                pasteAccess
                excludedApps

                if controller.accessBlocked {
                    Text("macOS is set to ask before, or refuse, DocShot reading the clipboard, so history may miss copies. You can change it for DocShot in System Settings > Privacy & Security.")
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            if let problem = controller.problem {
                Text(problem)
                    .font(.system(size: 11))
                    .foregroundColor(.red)
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
        .confirmationDialog("Clear clipboard history?", isPresented: $confirmingClear) {
            Button("Clear", role: .destructive) { controller.clear() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Keeps: \(controller.clearKeep.title.lowercased()). This cannot be undone.")
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
            Text("The new limit removes the oldest unpinned items. Pinned items stay. This cannot be undone.")
        }
    }

    // MARK: - Limits (C3 plan, decision 6)

    private var limits: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 12) {
                Picker("Keep for", selection: Binding(
                    get: { controller.maxAgeDays },
                    set: { change(maxAgeDays: $0) }
                )) {
                    ForEach(ClipboardSettings.ageChoices, id: \.self) { Text("\($0) days").tag($0) }
                }
                .frame(maxWidth: 170)

                Picker("Items", selection: Binding(
                    get: { controller.maxItems ?? 0 },
                    set: { change(maxItems: .some($0 == 0 ? nil : $0)) } // .some: "no limit" is a choice, not "unchanged"
                )) {
                    ForEach(ClipboardSettings.itemChoices, id: \.self) { choice in
                        Text(choice.map(String.init) ?? "No limit").tag(choice ?? 0)
                    }
                }
                .frame(maxWidth: 150)

                Picker("Storage", selection: Binding(
                    get: { controller.maxMegabytes },
                    set: { change(maxMegabytes: $0) }
                )) {
                    ForEach(ClipboardSettings.megabyteChoices, id: \.self) { megabytes in
                        Text(megabytes >= 1024 ? "\(megabytes / 1024) GB" : "\(megabytes) MB").tag(megabytes)
                    }
                }
                .frame(maxWidth: 160)
            }
            .pickerStyle(.menu)
            note("Pinned items are kept whatever the limits, and do not count towards the item limit. With no item limit, the storage limit still applies. A single copy over \(RetentionLimits.maxItemBytes / (1024 * 1024)) MB is skipped.")
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

    // MARK: - Paste (C3 plan, decisions 1 and 2)

    private var pasteAccess: some View {
        VStack(alignment: .leading, spacing: 4) {
            Toggle("Paste into the app you were in", isOn: Binding(
                get: { controller.pasteDirectly },
                set: { controller.setPasteDirectly($0) }
            ))
            if controller.pasteDirectly {
                HStack(spacing: 8) {
                    if controller.pasteAllowed {
                        note("Allowed. Return or a click in the DocShot window pastes.")
                    } else {
                        note("Needs Accessibility permission. Until then, Return copies and you press ⌘V.")
                        Button("Allow…") {
                            controller.markAccessRequested()
                            AccessibilityAccess.request()
                            AccessibilityAccess.openSettings()
                        }
                    }
                }
            }
        }
    }

    // MARK: - Excluded apps (C3 plan, decision 7)

    private var excludedApps: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Never record copies from")
                .font(.system(size: 12, weight: .medium))
            VStack(alignment: .leading, spacing: 2) {
                ForEach(controller.excludedApps, id: \.self) { bundleID in
                    HStack(spacing: 6) {
                        if let icon = Self.icon(for: bundleID) {
                            Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                        }
                        Text(Self.name(for: bundleID))
                            .font(.system(size: 12))
                        Spacer()
                        Button {
                            controller.removeExcludedApp(bundleID)
                        } label: {
                            Image(systemName: "minus.circle")
                        }
                        .buttonStyle(.plain)
                        .foregroundColor(DesignTokens.secondaryText)
                        .help("Remove")
                        .accessibilityLabel("Remove \(Self.name(for: bundleID))")
                    }
                }
            }
            .frame(maxWidth: 360)
            HStack {
                Button("Add App…") { chooseApp() }
                Button("Restore Defaults") { controller.restoreDefaultExcludedApps() }
            }
            note("Copies marked secret by password managers are never recorded, whatever this list says.")
        }
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

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundColor(DesignTokens.secondaryText)
            .fixedSize(horizontal: false, vertical: true)
    }
}
