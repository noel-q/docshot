import SwiftUI
import AppKit

public struct OnboardingView: View {
    @State private var currentStep: Int = 0
    @State private var selectedPresetID: Int = HotkeyService.shared.currentPreset.id
    @State private var includeCursor: Bool = UserDefaults.standard.bool(forKey: "DocShotIncludeCursor")
    @State private var outputFolderMode: OutputFolderMode = OutputFolderService.shared.currentMode
    @State private var folderPathDisplay: String = OutputFolderService.shared.displayPath ?? "No folder selected"
    @State private var folderErrorMessage: String? = nil
    
    public var onFinish: () -> Void
    
    public init(onFinish: @escaping () -> Void) {
        self.onFinish = onFinish
    }
    
    public var body: some View {
        VStack(spacing: 0) {
            // Header Progress / Steps Bar
            HStack(spacing: 8) {
                ForEach(0..<4) { index in
                    Capsule()
                        .fill(index == currentStep ? DesignTokens.primaryAccent : DesignTokens.borderSubtle)
                        .frame(height: 4)
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 20)
            
            Spacer()
            
            // Step Content
            VStack(spacing: 16) {
                switch currentStep {
                case 0:
                    stepView(
                        showMarkTile: true,
                        icon: "viewfinder",
                        title: "Welcome to DocShot",
                        subtitle: "Fast, local-first macOS screenshot capture & annotation utility.",
                        details: "DocShot runs in your macOS menu bar and triggers instantly via the global hotkey (⌘⇧6 by default). Output is strictly explicit: no auto-saves, cloud uploads, or accounts."
                    )
                case 1:
                    stepView(
                        showMarkTile: false,
                        icon: "macwindow.on.rectangle",
                        title: "Smart Selection & Custom Region",
                        subtitle: "Hover application windows or drag a custom region.",
                        details: "Hovering over any external application window highlights its exact boundaries for single-click capture. Click-dragging across screens selects a custom pixel-precise region."
                    )
                case 2:
                    stepView(
                        showMarkTile: false,
                        icon: "pencil.and.outline",
                        title: "Annotation & Redaction Editor",
                        subtitle: "Annotate before committing any file or clipboard output.",
                        details: "Use Arrow, Rectangle, Ellipse, Text, Highlighter, Blur/Pixelate Redaction, and Crop. Full Undo/Redo (⌘Z / ⇧⌘Z) lets you adjust annotations freely. Output only occurs when clicking Copy PNG or Save."
                    )
                case 3:
                    VStack(spacing: 14) {
                        HStack(spacing: 10) {
                            MarkTileView(size: 32, cornerRadius: 8)
                            Text("Output & Preferences Setup")
                                .font(.system(size: 16, weight: .bold))
                                .foregroundColor(.primary)
                        }
                        
                        VStack(alignment: .leading, spacing: 12) {
                            // Output Folder Setup
                            VStack(alignment: .leading, spacing: 6) {
                                Text("Save Panel Default Folder:")
                                    .font(.system(size: 12, weight: .semibold))
                                
                                HStack(spacing: 16) {
                                    Button(action: {
                                        outputFolderMode = .askWhereToSave
                                        OutputFolderService.shared.setModeAskWhereToSave()
                                    }) {
                                        HStack(spacing: 6) {
                                            Image(systemName: outputFolderMode == .askWhereToSave ? "largecircle.fill.circle" : "circle")
                                                .foregroundColor(outputFolderMode == .askWhereToSave ? DesignTokens.primaryAccent : DesignTokens.secondaryText)
                                            Text("Ask where to save")
                                                .font(.system(size: 12))
                                        }
                                    }
                                    .buttonStyle(.plain)
                                    
                                    Button(action: {
                                        let (url, _) = OutputFolderService.shared.resolveDefaultFolderURL()
                                        if let url {
                                            folderPathDisplay = url.path
                                            outputFolderMode = .useDefaultFolder
                                            OutputFolderService.shared.currentMode = .useDefaultFolder
                                        } else {
                                            Task {
                                                let res = await OutputFolderService.shared.selectDefaultFolder()
                                                if let selectedURL = res.url {
                                                    folderPathDisplay = selectedURL.path
                                                    outputFolderMode = .useDefaultFolder
                                                    folderErrorMessage = nil
                                                } else {
                                                    outputFolderMode = .askWhereToSave
                                                    OutputFolderService.shared.setModeAskWhereToSave()
                                                    if let err = res.errorMessage {
                                                        folderErrorMessage = err
                                                    }
                                                }
                                            }
                                        }
                                    }) {
                                        HStack(spacing: 6) {
                                            Image(systemName: outputFolderMode == .useDefaultFolder ? "largecircle.fill.circle" : "circle")
                                                .foregroundColor(outputFolderMode == .useDefaultFolder ? DesignTokens.primaryAccent : DesignTokens.secondaryText)
                                            Text("Use a default folder")
                                                .font(.system(size: 12))
                                        }
                                    }
                                    .buttonStyle(.plain)
                                }
                                
                                if outputFolderMode == .useDefaultFolder {
                                    VStack(alignment: .leading, spacing: 6) {
                                        Text(folderPathDisplay)
                                            .font(.system(size: 11, design: .monospaced))
                                            .foregroundColor(DesignTokens.secondaryText)
                                            .lineLimit(1)
                                            .truncationMode(.middle)
                                            .padding(6)
                                            .background(RoundedRectangle(cornerRadius: 6).fill(DesignTokens.graphiteBase))
                                        
                                        HStack(spacing: 8) {
                                            Button("Choose Folder...") {
                                                Task {
                                                    let res = await OutputFolderService.shared.selectDefaultFolder()
                                                    if let url = res.url {
                                                        folderPathDisplay = url.path
                                                        outputFolderMode = .useDefaultFolder
                                                        folderErrorMessage = nil
                                                    } else if let err = res.errorMessage {
                                                        folderErrorMessage = err
                                                    }
                                                }
                                            }
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)
                                            
                                            Button("Create DocShot Folder...") {
                                                Task {
                                                    let res = await OutputFolderService.shared.createDocShotFolder()
                                                    if let url = res.url {
                                                        folderPathDisplay = url.path
                                                        outputFolderMode = .useDefaultFolder
                                                        folderErrorMessage = nil
                                                    } else if let err = res.errorMessage {
                                                        folderErrorMessage = err
                                                    }
                                                }
                                            }
                                            .buttonStyle(.bordered)
                                            .controlSize(.small)
                                        }
                                    }
                                    .padding(.top, 2)
                                }
                                
                                if let err = folderErrorMessage {
                                    Text(err)
                                        .font(.system(size: 11))
                                        .foregroundColor(.red)
                                }
                            }
                            
                            Divider()
                            
                            // Global Shortcut & Cursor
                            HStack {
                                Text("Global Shortcut:")
                                    .font(.system(size: 12, weight: .semibold))
                                Spacer()
                                Picker("", selection: $selectedPresetID) {
                                    ForEach(HotkeyPreset.presets) { preset in
                                        Text(preset.label).tag(preset.id)
                                    }
                                }
                                .pickerStyle(.menu)
                                .frame(width: 180)
                                .onChange(of: selectedPresetID) { _, newID in
                                    if let preset = HotkeyPreset.presets.first(where: { $0.id == newID }) {
                                        HotkeyService.shared.registerPreset(preset) {
                                            CaptureCoordinator.shared.startCapture()
                                        }
                                    }
                                }
                            }
                            
                            Toggle(isOn: $includeCursor) {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text("Include cursor in screenshots")
                                        .font(.system(size: 12, weight: .medium))
                                    Text("When enabled, ScreenCaptureKit captures include the mouse pointer (default: off).")
                                        .font(.system(size: 11))
                                        .foregroundColor(DesignTokens.secondaryText)
                                }
                            }
                            .onChange(of: includeCursor) { _, newValue in
                                UserDefaults.standard.set(newValue, forKey: "DocShotIncludeCursor")
                            }
                        }
                        .padding(14)
                        .background(RoundedRectangle(cornerRadius: 8).fill(DesignTokens.cardBackground))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(DesignTokens.borderAdaptive, lineWidth: 1))
                    }
                default:
                    EmptyView()
                }
            }
            .padding(.horizontal, 32)
            
            Spacer()
            
            // Bottom Action Controls
            HStack {
                if currentStep > 0 {
                    Button("Back") {
                        withAnimation { currentStep -= 1 }
                    }
                    .buttonStyle(.borderless)
                }
                
                Spacer()
                
                Button("Skip") {
                    finishOnboarding()
                }
                .buttonStyle(.plain)
                .foregroundColor(DesignTokens.secondaryText)
                .padding(.trailing, 12)
                
                if currentStep < 3 {
                    Button("Next") {
                        withAnimation { currentStep += 1 }
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DesignTokens.primaryAccent)
                } else {
                    Button("Get Started") {
                        finishOnboarding()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(DesignTokens.primaryAccent)
                }
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 20)
        }
        .frame(width: 520, height: 420)
        .background(DesignTokens.windowBackground)
        .onAppear {
            outputFolderMode = OutputFolderService.shared.currentMode
            folderPathDisplay = OutputFolderService.shared.displayPath ?? "No folder selected"
        }
    }
    
    private func finishOnboarding() {
        UserDefaults.standard.set(true, forKey: "hasCompletedOnboarding")
        onFinish()
    }
    
    @ViewBuilder
    private func stepView(showMarkTile: Bool, icon: String, title: String, subtitle: String, details: String) -> some View {
        VStack(spacing: 12) {
            if showMarkTile {
                MarkTileView(size: 64, cornerRadius: 14)
            } else {
                Image(systemName: icon)
                    .font(.system(size: 44, weight: .semibold))
                    .foregroundColor(DesignTokens.primaryAccent)
            }
            
            Text(title)
                .font(.system(size: 20, weight: .bold))
            
            Text(subtitle)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(.primary)
            
            Text(details)
                .font(.system(size: 12))
                .foregroundColor(DesignTokens.secondaryText)
                .multilineTextAlignment(.center)
                .lineSpacing(3)
        }
    }
}

@MainActor
public final class OnboardingWindowController: NSObject {
    public static let shared = OnboardingWindowController()
    
    private var window: NSWindow?
    
    private override init() {
        super.init()
    }
    
    public func showOnboardingIfNeeded() {
        let completed = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
        if !completed {
            showOnboarding()
        }
    }
    
    public func showOnboarding() {
        closeOnboarding()
        
        let onboardingView = OnboardingView(onFinish: { [weak self] in
            self?.closeOnboarding()
        })
        
        let hostingView = NSHostingView(rootView: onboardingView)
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        
        newWindow.title = "Welcome to DocShot"
        newWindow.center()
        newWindow.contentView = hostingView
        newWindow.isReleasedWhenClosed = false
        
        NSApp.activate(ignoringOtherApps: true)
        newWindow.makeKeyAndOrderFront(nil)
        
        self.window = newWindow
    }
    
    public func closeOnboarding() {
        if let win = window {
            win.orderOut(nil)
            win.close()
            window = nil
        }
    }
}
