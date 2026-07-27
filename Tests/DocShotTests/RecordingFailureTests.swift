import Testing
import Foundation
import CoreGraphics
@testable import DocShot

/// Failures have to be distinguishable — the UI says something actionable, and cleanup decides
/// whether media survives — so each case carries its own message and disposal rule.
@Suite("RecordingFailure Tests")
struct RecordingFailureTests {

    private static let allFailures: [RecordingFailure] = [
        .permissionDenied,
        .invalidTarget(.spansMultipleDisplays),
        .streamStart("stream refused"),
        .streamInterrupted("display disconnected"),
        .stopFailed("writer refused to finish"),
        .writer("no frames were recorded"),
        .outputSave("disk full")
    ]

    @Test("Every failure has a distinct, non-empty description")
    func testDescriptionsAreDistinctAndPresent() {
        let descriptions = Self.allFailures.map { $0.errorDescription ?? "" }

        for description in descriptions {
            #expect(description.isEmpty == false)
        }
        #expect(Set(descriptions).count == descriptions.count)
    }

    @Test("Only a save failure keeps the temporary recording")
    func testOnlySaveFailureKeepsMedia() {
        for failure in Self.allFailures {
            if case .outputSave = failure {
                #expect(failure.discardsTemporaryMedia == false)
            } else {
                #expect(failure.discardsTemporaryMedia, "\(failure) should discard its media")
            }
        }
    }

    @Test("An invalid target reports the selection's own explanation")
    func testInvalidTargetUsesRejectionMessage() {
        let rejections: [RecordingTargetRejection] = [
            .spansMultipleDisplays,
            .noContainingDisplay,
            .tooSmall,
            .invalidGeometry,
            .windowUnavailable
        ]

        for rejection in rejections {
            #expect(RecordingFailure.invalidTarget(rejection).errorDescription == rejection.message)
            #expect(rejection.message.isEmpty == false)
        }
    }

    @Test("A recording is only offered to the user when it describes real media")
    func testPlayabilityGuard() {
        let good = TemporaryRecording(
            url: URL(fileURLWithPath: "/tmp/DocShot-Recordings/a.mp4"),
            duration: 2,
            pixelSize: CGSize(width: 640, height: 480),
            hasAudio: false,
            createdAt: Date()
        )
        #expect(good.isPlayable)

        let empty = TemporaryRecording(
            url: good.url,
            duration: 0,
            pixelSize: good.pixelSize,
            hasAudio: false,
            createdAt: Date()
        )
        #expect(empty.isPlayable == false)

        let infinite = TemporaryRecording(
            url: good.url,
            duration: .infinity,
            pixelSize: good.pixelSize,
            hasAudio: false,
            createdAt: Date()
        )
        #expect(infinite.isPlayable == false)

        let sizeless = TemporaryRecording(
            url: good.url,
            duration: 2,
            pixelSize: .zero,
            hasAudio: false,
            createdAt: Date()
        )
        #expect(sizeless.isPlayable == false)
    }

    @Test("R1 recording options are video-only")
    func testVideoOnlyOptions() {
        let options = RecordingOptions.videoOnly(showsCursor: false)

        #expect(options.audio == RecordingAudioMode.none)
        #expect(options.isVideoOnly)
        #expect(options.maximumFrameRate == 30)
        #expect(RecordingOptions(audio: .system, showsCursor: false, maximumFrameRate: 30).isVideoOnly == false)
    }
}
