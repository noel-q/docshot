import Foundation
import CoreGraphics
import AppKit
import ScreenCaptureKit
import os

public final class PermissionService: @unchecked Sendable {
    public static let shared = PermissionService()
    private let logger = Logger(subsystem: "com.docshot.app", category: "PermissionService")

    private init() {}
    
    /// Returns true if screen capture access is currently granted by macOS TCC.
    public func hasScreenCaptureAccess() -> Bool {
        return CGPreflightScreenCaptureAccess()
    }

    /// Verifies capture with the API DocShot actually uses. On recent macOS
    /// versions, the legacy Core Graphics preflight can disagree with an
    /// already-authorized ScreenCaptureKit app.
    @MainActor
    public func canCaptureWithScreenCaptureKit() async -> Bool {
        guard #available(macOS 14.0, *) else {
            return hasScreenCaptureAccess()
        }

        do {
            let content = try await SCShareableContent.excludingDesktopWindows(
                false,
                onScreenWindowsOnly: true
            )
            guard let display = content.displays.first else { return false }

            let configuration = SCStreamConfiguration()
            configuration.sourceRect = CGRect(x: 0, y: 0, width: 1, height: 1)
            configuration.width = 1
            configuration.height = 1
            configuration.showsCursor = false

            let filter = SCContentFilter(
                display: display,
                excludingApplications: [],
                exceptingWindows: []
            )
            _ = try await SCScreenshotManager.captureImage(
                contentFilter: filter,
                configuration: configuration
            )
            return true
        } catch {
            logger.error("SCScreenshotManager.captureImage probe failed: \(error as NSError, privacy: .public)")
            return false
        }
    }
    
    /// Requests screen capture access natively from macOS TCC.
    @discardableResult
    public func requestScreenCaptureAccess() -> Bool {
        return CGRequestScreenCaptureAccess()
    }
    
    /// Opens the macOS System Settings app directly to Privacy & Security -> Screen Recording.
    public func openSystemSettingsScreenRecording() {
        if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") {
            NSWorkspace.shared.open(url)
        } else if let fallbackUrl = URL(string: "x-apple.systempreferences:com.apple.preference.security") {
            NSWorkspace.shared.open(fallbackUrl)
        }
    }
}
