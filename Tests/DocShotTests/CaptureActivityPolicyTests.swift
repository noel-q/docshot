import Testing
import Foundation
import CoreGraphics
@testable import DocShot

/// Only one DocShot capture activity at a time, decided without either coordinator knowing about
/// the other.
@Suite("CaptureActivityPolicy Tests")
struct CaptureActivityPolicyTests {

    private static let target = RecordingTarget.window(
        id: 1,
        boundsInCG: CGRect(x: 0, y: 0, width: 100, height: 100)
    )

    private static func recording() -> TemporaryRecording {
        TemporaryRecording(
            url: URL(fileURLWithPath: "/tmp/DocShot-Recordings/clip.mp4"),
            duration: 1,
            pixelSize: CGSize(width: 100, height: 100),
            hasAudio: false,
            createdAt: Date()
        )
    }

    @Test("With both subsystems idle, both capture actions are available")
    func testBothIdle() {
        let policy = CaptureActivityPolicy.evaluate(captureState: .idle, recordingState: .idle)

        #expect(policy.allowsScreenshotCapture)
        #expect(policy.allowsRecordingCapture)
        #expect(policy.allowsStopRecording == false)
    }

    @Test("Every non-idle recording state blocks screenshot capture")
    func testRecordingBlocksScreenshots() {
        let busyStates: [RecordingState] = [
            .permissionRequired,
            .selecting,
            .awaitingConfirmation(Self.target),
            .starting(Self.target),
            .recording(Self.target, startedAt: Date()),
            .stopping,
            .awaitingOutput(Self.recording()),
            .exportingGIF(Self.recording()),
            .failed(.streamStart("x"))
        ]

        for state in busyStates {
            let policy = CaptureActivityPolicy.evaluate(captureState: .idle, recordingState: state)
            #expect(policy.allowsScreenshotCapture == false, "Screenshot allowed during \(state)")
            #expect(policy.allowsRecordingCapture == false, "Second recording allowed during \(state)")
        }
    }

    @Test("An in-progress screenshot blocks a new recording")
    func testScreenshotBlocksRecording() {
        let busyStates: [CaptureState] = [.permissionRequired, .selecting, .capturing, .editing]

        for state in busyStates {
            let policy = CaptureActivityPolicy.evaluate(captureState: state, recordingState: .idle)
            #expect(policy.allowsRecordingCapture == false, "Recording allowed during \(state)")
        }
    }

    @Test("A cancelled screenshot leaves recording available")
    func testCancelledScreenshotAllowsRecording() {
        let policy = CaptureActivityPolicy.evaluate(captureState: .cancelled, recordingState: .idle)

        #expect(policy.allowsRecordingCapture)
    }

    @Test("Stop is offered only while a recording is opening or running")
    func testStopAvailability() {
        let stoppable: [RecordingState] = [
            .starting(Self.target),
            .recording(Self.target, startedAt: Date())
        ]
        for state in stoppable {
            #expect(CaptureActivityPolicy.evaluate(captureState: .idle, recordingState: state).allowsStopRecording)
        }

        let notStoppable: [RecordingState] = [
            .idle,
            .permissionRequired,
            .selecting,
            .awaitingConfirmation(Self.target),
            .stopping,
            .awaitingOutput(Self.recording()),
            .failed(.stopFailed("x"))
        ]
        for state in notStoppable {
            #expect(
                CaptureActivityPolicy.evaluate(captureState: .idle, recordingState: state).allowsStopRecording == false,
                "Stop offered during \(state)"
            )
        }
    }
}
