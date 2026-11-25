import SwiftUI
import AppKit
import Carbon
import ServiceManagement

@main
struct DocShotApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @ObservedObject private var hotkeyService = HotkeyService.shared
    @ObservedObject private var captureCoordinator = CaptureCoordinator.shared
    @ObservedObject private var recordingCoordinator = RecordingCoordinator.shared
    @ObservedObject private var clipboardHistory = ClipboardHistoryController.shared

    /// Only one DocShot capture activity may run at a time. The policy is evaluated here rather
    /// than inside either coordinator, so screenshot capture keeps its existing behaviour.
    private var activityPolicy: CaptureActivityPolicy {
        CaptureActivityPolicy.evaluate(
            captureState: captureCoordinator.state,
            recordingState: recordingCoordinator.state
        )
    }

    var body: some Scene {
        // The Viewfinder mark (Quiet icon bake-off, chosen 24 November 2026), a template image
        // so macOS tints it for the menu bar.
        MenuBarExtra("DocShot", image: "MenuBarIcon") {
            Button("Capture Screenshot (\(hotkeyService.binding(for: .screenshot).shortcutDisplay))") {
                CaptureCoordinator.shared.startCapture()
            }
            .disabled(!activityPolicy.allowsScreenshotCapture)

            Button("Record Screen... (\(hotkeyService.binding(for: .record).shortcutDisplay))") {
                RecordingCoordinator.shared.startRecording()
            }
            .disabled(!activityPolicy.allowsRecordingCapture)

            if activityPolicy.allowsStopRecording {
                Button("Stop Recording") {
                    RecordingCoordinator.shared.stopRecording()
                }
            }

            Divider()

            Button("Open Clipboard History (\(hotkeyService.binding(for: .openWindow).shortcutDisplay))") {
                ClipboardWindowController.shared.show()
            }

            if clipboardHistory.isEnabled {
                Button(clipboardHistory.isPaused ? "Resume Clipboard History" : "Pause Clipboard History") {
                    clipboardHistory.setPaused(!clipboardHistory.isPaused)
                }
            }
            // With history off, Clear stays while anything is still stored.
            if clipboardHistory.isEnabled || clipboardHistory.hasStoredWhileOff {
                Button("Clear Clipboard History...") {
                    AppDelegate.confirmClearClipboardHistory()
                }
                .disabled(clipboardHistory.clearCount == 0)
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
#if DEBUG
    /// For the debug hook: SwiftUI's `NSApp.delegate` is not this object.
    @MainActor static weak var debugInstance: AppDelegate?
#endif

    func applicationDidFinishLaunching(_ notification: Notification) {
#if DEBUG
        AppDelegate.debugInstance = self
#endif
        registerForLaunchAtLogin()

        // Register the global shortcuts from the table. `openWindow` is defined there but
        // stays unregistered until the window it opens exists.
        HotkeyService.shared.register(.screenshot) {
            AppDelegate.startScreenshotCaptureIfAllowed()
        }
        HotkeyService.shared.register(.record) {
            let policy = CaptureActivityPolicy.evaluate(captureState: CaptureCoordinator.shared.state, recordingState: RecordingCoordinator.shared.state)
            switch policy.recordShortcutAction {
            case .start: RecordingCoordinator.shared.startRecording()
            case .stop: RecordingCoordinator.shared.stopRecording()
            case .refuse: NSSound.beep()
            }
        }
        HotkeyService.shared.register(.openWindow) {
            ClipboardWindowController.shared.toggle()
        }

        // Clipboard history does nothing unless the user switched it on (plan section 2.3).
        MainActor.assumeIsolated {
            ClipboardHistoryController.shared.start()
#if DEBUG
            ClipboardDebugHooks.install()
#endif
        }

        // Show onboarding guide on first launch
        Task { @MainActor in
            OnboardingWindowController.shared.showOnboardingIfNeeded()

            // A previous run that ended abnormally can leave a partial recording behind. Only
            // DocShot's own temporary recordings directory is swept.
            RecordingCoordinator.shared.purgeOrphanTemporaries()
        }
    }

    /// Clearing from the menu bar asks first, like the window and Settings.
    @MainActor
    static func confirmClearClipboardHistory() {
        let controller = ClipboardHistoryController.shared
        NSApp.activate()
        let alert = NSAlert()
        alert.messageText = ClipboardSettings.clearQuestion(controller.clearCount)
        alert.informativeText = "Keeps \(controller.clearKeep.title.lowercased()). \(ClipboardSettings.clearWarning)"
        alert.addButton(withTitle: "Clear")
        alert.addButton(withTitle: "Cancel")
        alert.buttons.first?.hasDestructiveAction = true
        if alert.runModal() == .alertFirstButtonReturn {
            controller.clear()
        }
    }

    /// Keep the menu-bar utility available after the user signs in to macOS.
    private func registerForLaunchAtLogin() {
        let loginItem = SMAppService.mainApp
        guard loginItem.status == .notRegistered else { return }

        do {
            try loginItem.register()
        } catch {
            NSLog("DocShot could not register for launch at login: %@", error.localizedDescription)
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
        // The compact Settings panel under the menu bar icon (compact panels, decision 4).
        SettingsWindowController.shared.toggle()
    }

}
