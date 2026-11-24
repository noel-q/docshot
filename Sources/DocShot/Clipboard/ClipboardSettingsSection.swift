import ClipboardKit
import SwiftUI

/// The "Clipboard history" section in Settings (plan section 5, C2). Limits and excluded apps
/// are shown read-only; editing them arrives in C3.
struct ClipboardSettingsSection: View {
    @ObservedObject var themeController = ThemeController.shared
    @ObservedObject var controller = ClipboardHistoryController.shared

    @State private var confirmingClear = false

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
                    Text("Off by default. Stored on this Mac only. Turning it off stops recording; what is kept stays until you clear it.")
                        .font(.system(size: 11))
                        .foregroundColor(DesignTokens.secondaryText)
                        .fixedSize(horizontal: false, vertical: true)
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

                Text("Keeps up to \(RetentionLimits.defaultMaxItems) items for \(Int(RetentionLimits.defaultMaxAge / 86_400)) days, at most \(RetentionLimits.defaultMaxBytes / (1024 * 1024)) MB; a single copy over \(RetentionLimits.maxItemBytes / (1024 * 1024)) MB is skipped. Never recorded: copies marked secret by password managers, and copies made in \(excludedAppNames).")
                    .font(.system(size: 11))
                    .foregroundColor(DesignTokens.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)

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
        .onAppear { controller.refreshAccessState() }
        .confirmationDialog("Clear clipboard history?", isPresented: $confirmingClear) {
            Button("Clear", role: .destructive) { controller.clear() }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("Keeps: \(controller.clearKeep.title.lowercased()). This cannot be undone.")
        }
    }

    private var excludedAppNames: String {
        "Passwords, Keychain Access, Bitwarden and 1Password"
    }
}
