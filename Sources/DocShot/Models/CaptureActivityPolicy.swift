import Foundation

/// Which capture actions the app offers, given what the two coordinators are currently doing.
///
/// Only one DocShot capture activity may exist at a time. Rather than teaching either coordinator
/// about the other, the app-level menu and the global hotkey consult this pure policy, so
/// screenshot capture keeps working exactly as it did.
public struct CaptureActivityPolicy: Equatable, Sendable {
    public let allowsScreenshotCapture: Bool
    public let allowsRecordingCapture: Bool
    public let allowsStopRecording: Bool

    public init(
        allowsScreenshotCapture: Bool,
        allowsRecordingCapture: Bool,
        allowsStopRecording: Bool
    ) {
        self.allowsScreenshotCapture = allowsScreenshotCapture
        self.allowsRecordingCapture = allowsRecordingCapture
        self.allowsStopRecording = allowsStopRecording
    }

    public static func evaluate(
        captureState: CaptureState,
        recordingState: RecordingState
    ) -> CaptureActivityPolicy {
        // Screenshot capture owns its own state guards (including the editor discard prompt); the
        // only new rule is that it may not begin while a recording activity is live.
        let screenshotAllowed = !recordingState.isActive

        let screenshotIdle: Bool
        switch captureState {
        case .idle, .cancelled:
            screenshotIdle = true
        case .permissionRequired, .selecting, .capturing, .editing:
            screenshotIdle = false
        }

        let stopAllowed: Bool
        switch recordingState {
        case .starting, .recording:
            stopAllowed = true
        case .idle, .permissionRequired, .selecting, .awaitingConfirmation, .stopping,
             .awaitingOutput, .exportingGIF, .failed:
            stopAllowed = false
        }

        return CaptureActivityPolicy(
            allowsScreenshotCapture: screenshotAllowed,
            allowsRecordingCapture: screenshotIdle && recordingState == .idle,
            allowsStopRecording: stopAllowed
        )
    }
}
