import SwiftUI
import AppKit

public struct SettingsView: View {
    /// Redraws this view when the colour theme changes (C0.7).
    @ObservedObject private var themeController = ThemeController.shared
    @State private var hasPermission: Bool = PermissionService.shared.hasScreenCaptureAccess()
    @ObservedObject private var hotkeyService = HotkeyService.shared
    @State private var registrationError: String? = HotkeyService.shared.lastError
    @State private var recorderAction: ShortcutAction?
    @ObservedObject private var launchAtLoginService = LaunchAtLoginService.shared
    @State private var includeCursor: Bool = UserDefaults.standard.bool(forKey: "DocShotIncludeCursor")
    @State private var recordSystemAudio: Bool = UserDefaults.standard.bool(forKey: "DocShotRecordSystemAudio")
    @State private var recordCursor: Bool = UserDefaults.standard.bool(forKey: "DocShotRecordIncludeCursor")
    @State private var recordFrameRate: Int = {
        let saved = UserDefaults.standard.integer(forKey: "DocShotRecordingFrameRate")
        return saved == 0 ? 30 : saved
    }()
    
    @State private var outputFolderMode: OutputFolderMode = OutputFolderService.shared.currentMode
    @State private var folderPathDisplay: String = OutputFolderService.shared.displayPath ?? "No folder selected"
    @State private var folderMessage: String? = nil
    @State private var isMessageError: Bool = false
    
    public init() {}
    
    public var body: some View {
        // The sections are taller than a small display, and their height changes with
        // permission and folder state, so the content scrolls inside a fixed window. A
        // plain fixed height used to clip the header and the privacy notice.
        ScrollView {
        VStack(alignment: .leading, spacing: 16) {
            // Header
            HStack(spacing: 12) {
                MarkTileView(size: 44, cornerRadius: 10)
                
                VStack(alignment: .leading, spacing: 2) {
                    Text("DocShot Settings")
                        .font(.system(size: 16, weight: .bold))
                    Text("Local-first screenshot capture & annotation utility")
                        .font(.system(size: 12))
                        .foregroundColor(DesignTokens.secondaryText)
                }
                Spacer()
                Button("Guide...") {
                    OnboardingWindowController.shared.showOnboarding()
                }
                .buttonStyle(.bordered)
                .help("Re-open first-launch onboarding guide")
            }
            
            Divider()

            // Appearance (C0.7)
            VStack(alignment: .leading, spacing: 8) {
                Text("Appearance")
                    .font(.system(size: 13, weight: .semibold))
                HStack(spacing: 12) {
                    ForEach(ColorTheme.allCases) { theme in
                        ThemeSwatchButton(theme: theme, isSelected: themeController.theme == theme) {
                            themeController.select(theme)
                        }
                    }
                }
                Text("Changes DocShot's own windows only. Captures, exports and annotation colours stay the same, and light or dark follows macOS.")
                    .font(.system(size: 11))
                    .foregroundColor(DesignTokens.secondaryText)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Divider()

            // Clipboard history (C2)
            ClipboardSettingsSection()

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("App Launch")
                    .font(.system(size: 13, weight: .semibold))
                Toggle(isOn: Binding(
                    get: { launchAtLoginService.isEnabled },
                    set: { launchAtLoginService.setEnabled($0) }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Launch DocShot at login")
                            .font(.system(size: 13, weight: .medium))
                        Text("Off by default. Turning this off removes DocShot from Login Items.")
                            .font(.system(size: 11))
                            .foregroundColor(DesignTokens.secondaryText)
                    }
                }
                if let errorMessage = launchAtLoginService.errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                }
            }

            Divider()

            VStack(alignment: .leading, spacing: 8) {
                Text("Recording")
                    .font(.system(size: 13, weight: .semibold))
                Toggle(isOn: $recordSystemAudio) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Include system audio in recordings")
                            .font(.system(size: 13, weight: .medium))
                        Text("Off by default. Audio is captured only after you select Record; microphone and mixed audio are not available yet.")
                            .font(.system(size: 11))
                            .foregroundColor(DesignTokens.secondaryText)
                    }
                }
                .onChange(of: recordSystemAudio) { _, newValue in
                    UserDefaults.standard.set(newValue, forKey: "DocShotRecordSystemAudio")
                }
                Toggle("Include cursor in recordings", isOn: $recordCursor)
                    .onChange(of: recordCursor) { _, newValue in
                        UserDefaults.standard.set(newValue, forKey: "DocShotRecordIncludeCursor")
                    }
                Picker("Maximum frame rate", selection: $recordFrameRate) {
                    Text("30 fps").tag(30)
                }
                .pickerStyle(.menu)
                .onChange(of: recordFrameRate) { _, newValue in
                    UserDefaults.standard.set(newValue, forKey: "DocShotRecordingFrameRate")
                }
            }

            Divider()
            
            // Output Folder Section
            VStack(alignment: .leading, spacing: 8) {
                Text("Default Save Folder")
                    .font(.system(size: 13, weight: .semibold))
                
                VStack(alignment: .leading, spacing: 8) {
                    HStack(spacing: 16) {
                        Button(action: {
                            outputFolderMode = .askWhereToSave
                            OutputFolderService.shared.setModeAskWhereToSave()
                            folderMessage = nil
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: outputFolderMode == .askWhereToSave ? "largecircle.fill.circle" : "circle")
                                    .foregroundColor(outputFolderMode == .askWhereToSave ? DesignTokens.primaryAccent : DesignTokens.secondaryText)
                                Text("Ask where to save")
                                    .font(.system(size: 13))
                            }
                        }
                        .buttonStyle(.plain)
                        
                        Button(action: {
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
                        }) {
                            HStack(spacing: 6) {
                                Image(systemName: outputFolderMode == .useDefaultFolder ? "largecircle.fill.circle" : "circle")
                                    .foregroundColor(outputFolderMode == .useDefaultFolder ? DesignTokens.primaryAccent : DesignTokens.secondaryText)
                                Text("Use a default folder")
                                    .font(.system(size: 13))
                            }
                        }
                        .buttonStyle(.plain)
                    }
                    
                    if outputFolderMode == .useDefaultFolder {
                        VStack(alignment: .leading, spacing: 8) {
                            Text(folderPathDisplay)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundColor(DesignTokens.textOnDarkTile)
                                .lineLimit(1)
                                .truncationMode(.middle)
                                .padding(6)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .background(RoundedRectangle(cornerRadius: 6).fill(DesignTokens.graphiteBase))
                            
                            HStack(spacing: 8) {
                                Button("Choose Folder...") {
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
                                .buttonStyle(.bordered)
                                
                                Button("Create DocShot Folder...") {
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
                                .buttonStyle(.bordered)
                                
                                Button("Reveal in Finder") {
                                    if let err = OutputFolderService.shared.revealInFinder() {
                                        folderMessage = err
                                        isMessageError = true
                                        outputFolderMode = OutputFolderService.shared.currentMode
                                        folderPathDisplay = OutputFolderService.shared.displayPath ?? "No folder selected"
                                    } else {
                                        folderMessage = nil
                                    }
                                }
                                .buttonStyle(.bordered)
                            }
                        }
                    }
                    
                    if let msg = folderMessage {
                        Text(msg)
                            .font(.system(size: 11))
                            .foregroundColor(isMessageError ? .red : DesignTokens.primaryAccent)
                    }
                }
            }
            
            Divider()
            
            // Global Hotkey Section
            VStack(alignment: .leading, spacing: 8) {
                Text("Global Shortcuts")
                    .font(.system(size: 13, weight: .semibold))

                ForEach(ShortcutAction.allCases.filter(\.isRegistrable)) { action in
                    shortcutRow(for: action)
                }

                if let error = registrationError {
                    Text("⚠️ \(error)")
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                } else {
                    Text("Shortcuts are saved automatically and active globally.")
                        .font(.system(size: 11))
                        .foregroundColor(DesignTokens.secondaryText)
                }
            }
            
            Divider()
            
            // Cursor Settings Section
            VStack(alignment: .leading, spacing: 6) {
                Text("Capture Preferences")
                    .font(.system(size: 13, weight: .semibold))
                
                Toggle(isOn: $includeCursor) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Include cursor in screenshots")
                            .font(.system(size: 13, weight: .medium))
                        Text("When enabled, ScreenCaptureKit captures include the mouse pointer (default: off).")
                            .font(.system(size: 11))
                            .foregroundColor(DesignTokens.secondaryText)
                    }
                }
                .onChange(of: includeCursor) { _, newValue in
                    UserDefaults.standard.set(newValue, forKey: "DocShotIncludeCursor")
                }
            }
            
            Divider()
            
            // Screen Recording Permission Section
            VStack(alignment: .leading, spacing: 8) {
                Text("Screen Recording Permission")
                    .font(.system(size: 13, weight: .semibold))
                
                HStack(spacing: 10) {
                    Circle()
                        .fill(hasPermission ? DesignTokens.primaryAccent : Color.red)
                        .frame(width: 10, height: 10)
                    
                    Text(hasPermission ? "Screen Capture Permission Granted" : "Permission Not Granted")
                        .font(.system(size: 13, weight: .medium))
                    
                    Spacer()
                    
                    Button("Open System Settings") {
                        PermissionService.shared.openSystemSettingsScreenRecording()
                    }
                    .buttonStyle(.bordered)
                }
                
                if !hasPermission {
                    Text("DocShot requires Screen Recording permission to detect window bounds and capture screenshots.")
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                }
            }
            
            Divider()
            
            // Local-first Commitment
            VStack(alignment: .leading, spacing: 4) {
                Text("Local-First & Privacy Notice")
                    .font(.system(size: 12, weight: .semibold))
                Text("DocShot operates entirely on your local Mac. It never auto-saves images, writes to history libraries, tracks analytics, or connects to external servers. All output is strictly driven by your explicit Copy or Save actions.")
                    .font(.system(size: 11))
                    .foregroundColor(DesignTokens.secondaryText)
            }
        }
        .padding(24)
        }
        .frame(width: 520, height: 620)
        .background(DesignTokens.windowBackground)
        .onAppear {
            launchAtLoginService.refresh()
            hasPermission = PermissionService.shared.hasScreenCaptureAccess()
            registrationError = HotkeyService.shared.lastError
            includeCursor = UserDefaults.standard.bool(forKey: "DocShotIncludeCursor")
            recordSystemAudio = UserDefaults.standard.bool(forKey: "DocShotRecordSystemAudio")
            recordCursor = UserDefaults.standard.bool(forKey: "DocShotRecordIncludeCursor")
            let savedFrameRate = UserDefaults.standard.integer(forKey: "DocShotRecordingFrameRate")
            recordFrameRate = savedFrameRate == 0 ? 30 : savedFrameRate
            outputFolderMode = OutputFolderService.shared.currentMode
            folderPathDisplay = OutputFolderService.shared.displayPath ?? "No folder selected"
            validateFolder()
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            hasPermission = PermissionService.shared.hasScreenCaptureAccess()
            validateFolder()
        }
        .sheet(item: $recorderAction) { action in
            CustomShortcutRecorder(
                title: "Set \(action.title) Shortcut",
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

    /// One row per global shortcut: the current chord, the recorder, and reset to default.
    private func shortcutRow(for action: ShortcutAction) -> some View {
        HStack(spacing: 12) {
            Text(action.title)
                .font(.system(size: 13))
            Spacer()
            Text(hotkeyService.binding(for: action).shortcutDisplay)
                .font(.system(size: 13, design: .monospaced))
            Button("Change…") {
                recorderAction = action
            }
            .controlSize(.small)
            Button("Reset") {
                let success = hotkeyService.resetToDefault(action)
                registrationError = success ? nil : hotkeyService.lastError
            }
            .controlSize(.small)
            .disabled(hotkeyService.isUsingDefault(action))
            .help("Reset to \(action.defaultBinding.shortcutDisplay)")
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
                    RoundedRectangle(cornerRadius: 8)
                        .fill(color(surfaces.windowBackground, fallback: .windowBackgroundColor))
                    RoundedRectangle(cornerRadius: 5)
                        .fill(color(surfaces.cardBackground, fallback: .controlBackgroundColor))
                        .padding(6)
                    Circle()
                        .fill(accent)
                        .frame(width: 12, height: 12)
                        .padding(11)
                }
                .frame(width: 88, height: 52)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            isSelected ? accent : color(surfaces.border, fallback: .separatorColor),
                            lineWidth: isSelected ? 2 : 1
                        )
                )
                Text(theme.displayName)
                    .font(.system(size: 11, weight: isSelected ? .semibold : .regular))
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
