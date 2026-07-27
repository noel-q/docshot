import SwiftUI
import AppKit
import Carbon

@main
struct DocShotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject private var hotkeyService = HotkeyService.shared
    @ObservedObject private var captureCoordinator = CaptureCoordinator.shared
    @ObservedObject private var recordingCoordinator = RecordingCoordinator.shared

    /// Only one DocShot capture activity may run at a time. The policy is evaluated here rather
    /// than inside either coordinator, so screenshot capture keeps its existing behaviour.
    private var activityPolicy: CaptureActivityPolicy {
        CaptureActivityPolicy.evaluate(
            captureState: captureCoordinator.state,
            recordingState: recordingCoordinator.state
        )
    }

    var body: some Scene {
        MenuBarExtra("DocShot", systemImage: "viewfinder") {
            Button("Capture Screenshot (\(hotkeyService.currentPreset.shortcutDisplay))") {
                CaptureCoordinator.shared.startCapture()
            }
            .disabled(!activityPolicy.allowsScreenshotCapture)

            Button("Record Screen...") {
                RecordingCoordinator.shared.startRecording()
            }
            .disabled(!activityPolicy.allowsRecordingCapture)

            if activityPolicy.allowsStopRecording {
                Button("Stop Recording") {
                    RecordingCoordinator.shared.stopRecording()
                }
            }

            Divider()

            Button("Settings...") {
                appDelegate.openSettingsWindow()
            }

            Button("Onboarding Guide...") {
                OnboardingWindowController.shared.showOnboarding()
            }

            Divider()

            Button("Quit DocShot") {
                NSApp.terminate(nil)
            }
        }
    }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var settingsWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Register Carbon Global Hotkey from saved preset
        HotkeyService.shared.registerPreset(HotkeyService.shared.currentPreset) {
            AppDelegate.startScreenshotCaptureIfAllowed()
        }
        HotkeyService.shared.registerRecordingHotkey {
            let policy = CaptureActivityPolicy.evaluate(captureState: CaptureCoordinator.shared.state, recordingState: RecordingCoordinator.shared.state)
            guard policy.allowsRecordingCapture else { NSSound.beep(); return }
            RecordingCoordinator.shared.startRecording()
        }

        // Show onboarding guide on first launch
        Task { @MainActor in
            OnboardingWindowController.shared.showOnboardingIfNeeded()

            // A previous run that ended abnormally can leave a partial recording behind. Only
            // DocShot's own temporary recordings directory is swept.
            RecordingCoordinator.shared.purgeOrphanTemporaries()
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        MainActor.assumeIsolated {
            RecordingCoordinator.shared.terminateCleanup()
        }
    }

    /// The capture shortcut must not start a screenshot while a recording activity owns the
    /// screen. This is the only other entry point to `startCapture()` besides the menu item.
    @MainActor
    private static func startScreenshotCaptureIfAllowed() {
        let policy = CaptureActivityPolicy.evaluate(
            captureState: CaptureCoordinator.shared.state,
            recordingState: RecordingCoordinator.shared.state
        )
        guard policy.allowsScreenshotCapture else {
            NSSound.beep()
            return
        }
        CaptureCoordinator.shared.startCapture()
    }

    @MainActor
    func openSettingsWindow() {
        if let window = settingsWindow {
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }

        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 500),
            styleMask: [.titled, .closable],
            backing: .buffered,
            defer: false
        )
        window.title = "DocShot Settings"
        window.center()
        window.contentView = NSHostingView(rootView: SettingsView())
        window.isReleasedWhenClosed = false

        self.settingsWindow = window
        window.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
}
