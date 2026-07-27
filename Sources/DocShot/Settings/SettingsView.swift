import SwiftUI
import AppKit

public struct SettingsView: View {
    @State private var hasPermission: Bool = PermissionService.shared.hasScreenCaptureAccess()
    @State private var selectedPresetID: Int = HotkeyService.shared.currentPreset.id
    @State private var registrationError: String? = HotkeyService.shared.lastError
    @State private var isShowingCustomShortcutRecorder = false
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

            VStack(alignment: .leading, spacing: 8) {
                Text("Recording")
                    .font(.system(size: 13, weight: .semibold))
                HStack {
                    Text("Global shortcut")
                    Spacer()
                    Text(HotkeyService.shared.recordingPreset.shortcutDisplay)
                        .font(.system(size: 13, design: .monospaced))
                    Text("Records screen")
                        .font(.system(size: 11))
                        .foregroundColor(DesignTokens.secondaryText)
                }
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
                                .foregroundColor(DesignTokens.secondaryText)
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
                Text("Global Capture Shortcut")
                    .font(.system(size: 13, weight: .semibold))
                
                HStack(spacing: 12) {
                    Text("Shortcut:")
                        .font(.system(size: 13))
                    
                    Picker("", selection: $selectedPresetID) {
                        ForEach(HotkeyPreset.presets) { preset in
                            Text(preset.label).tag(preset.id)
                        }
                        Divider()
                        Text("Custom…").tag(HotkeyPreset.customID)
                    }
                    .pickerStyle(.menu)
                    .frame(width: 220)
                    .onChange(of: selectedPresetID) { _, newID in
                        if newID == HotkeyPreset.customID {
                            isShowingCustomShortcutRecorder = true
                            return
                        }
                        if let preset = HotkeyPreset.presets.first(where: { $0.id == newID }) {
                            let success = HotkeyService.shared.registerPreset(preset) {
                                CaptureCoordinator.shared.startCapture()
                            }
                            registrationError = success ? nil : HotkeyService.shared.lastError
                        }
                    }
                }

                if HotkeyService.shared.currentPreset.id == HotkeyPreset.customID {
                    Text("Using custom shortcut: \(HotkeyService.shared.currentPreset.shortcutDisplay)")
                        .font(.system(size: 11))
                        .foregroundColor(DesignTokens.secondaryText)
                }
                
                if let error = registrationError {
                    Text("⚠️ \(error)")
                        .font(.system(size: 11))
                        .foregroundColor(.red)
                } else {
                    Text("Shortcut selection is automatically saved and active globally.")
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
            
            Spacer()
        }
        .padding(24)
        .frame(width: 520, height: 570)
        .background(DesignTokens.windowBackground)
        .onAppear {
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
        .sheet(isPresented: $isShowingCustomShortcutRecorder, onDismiss: {
            selectedPresetID = HotkeyService.shared.currentPreset.id
        }) {
            CustomShortcutRecorder(currentShortcut: HotkeyService.shared.currentPreset) { keyCode, modifiers, keyDisplay in
                let success = HotkeyService.shared.registerCustomShortcut(
                    keyCode: keyCode,
                    modifiers: modifiers,
                    keyDisplay: keyDisplay
                ) {
                    CaptureCoordinator.shared.startCapture()
                }
                registrationError = success ? nil : HotkeyService.shared.lastError
                selectedPresetID = HotkeyService.shared.currentPreset.id
            }
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
