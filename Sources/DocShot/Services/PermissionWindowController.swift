import SwiftUI
import AppKit

@MainActor
public final class PermissionAlertModel: ObservableObject {
    @Published public var statusMessage: String?
}

public struct PermissionAlertView: View {
    @ObservedObject public var model: PermissionAlertModel
    public var onOpenSettings: () -> Void
    public var onRestart: () -> Void
    public var onCancel: () -> Void
    
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
        VStack(spacing: 20) {
            // Full mark for brand identity; the permission concept itself is a status
            // indicator, not an identity detail, so it stays in the product's teal accent
            // rather than amber. Keeps amber reserved for the mark, per the brand system.
            MarkTileView(size: 64, cornerRadius: 14)

            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "lock.shield")
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(DesignTokens.primaryAccent)

                    Text("Screen Recording Permission Required")
                        .font(.system(size: 16, weight: .bold))
                }

                Text("DocShot requires Screen Recording permission to select application windows and capture screen regions.\n\nPlease grant permission in System Settings.")
                    .font(.system(size: 13))
                    .foregroundColor(DesignTokens.secondaryText)
                    .multilineTextAlignment(.center)
            }

            if let statusMessage = model.statusMessage {
                Text(statusMessage)
                    .font(.system(size: 11))
                    .foregroundColor(DesignTokens.secondaryText)
                    .multilineTextAlignment(.center)
            }
            
            HStack(spacing: 12) {
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.borderless)
                
                Button("Open System Settings") {
                    onOpenSettings()
                }
                .buttonStyle(.borderedProminent)
                .tint(DesignTokens.primaryAccent)

                Button("Restart DocShot") {
                    onRestart()
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(24)
        .frame(width: 440, height: 280)
        .background(DesignTokens.windowBackground)
    }
}

@MainActor
public final class PermissionWindowController: NSObject, NSWindowDelegate {
    public static let shared = PermissionWindowController()
    
    public var onDismiss: (@MainActor () -> Void)?
    private var window: NSWindow?
    private var model: PermissionAlertModel?
    
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
            onOpenSettings: { [weak self] in
                PermissionService.shared.openSystemSettingsScreenRecording()
                self?.model?.statusMessage = "After enabling permission in System Settings, return here and choose Restart DocShot."
            },
            onRestart: { [weak self] in
                self?.restartIfPermissionGranted()
            },
            onCancel: { [weak self] in
                self?.closePermissionAlert()
            }
        )
        
        let hostingView = NSHostingView(rootView: alertView)
        let newWindow = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 440, height: 280),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        
        newWindow.title = "Permission Required: DocShot"
        newWindow.center()
        newWindow.contentView = hostingView
        newWindow.delegate = self
        newWindow.isReleasedWhenClosed = false
        
        NSApp.activate(ignoringOtherApps: true)
        newWindow.makeKeyAndOrderFront(nil)
        
        self.window = newWindow
    }

    private func restartIfPermissionGranted() {
        guard PermissionService.shared.hasScreenCaptureAccess() else {
            model?.statusMessage = "macOS has not made Screen Recording permission available to DocShot yet. Enable it, then return and try again."
            return
        }

        let appURL = Bundle.main.bundleURL
        guard appURL.pathExtension == "app" else {
            model?.statusMessage = "Permission is enabled. Please quit and relaunch DocShot from Xcode so it runs as a macOS app."
            return
        }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        NSWorkspace.shared.openApplication(at: appURL, configuration: configuration) { [weak self] _, error in
            Task { @MainActor [weak self] in
                if let error {
                    self?.model?.statusMessage = "DocShot could not restart: \(error.localizedDescription)"
                } else {
                    NSApp.terminate(nil)
                }
            }
        }
    }
    
    public func closePermissionAlert() {
        if let win = window {
            win.delegate = nil
            win.orderOut(nil)
            win.close()
            window = nil
        }
        model = nil
        let callback = onDismiss
        onDismiss = nil
        callback?()
    }
    
    public func windowWillClose(_ notification: Notification) {
        window = nil
        model = nil
        let callback = onDismiss
        onDismiss = nil
        callback?()
    }
}
