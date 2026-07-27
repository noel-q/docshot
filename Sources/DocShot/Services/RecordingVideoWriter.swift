import Foundation
import AVFoundation
import CoreGraphics
import CoreMedia
import os

/// What a finished writer produced, before the file itself has been validated.
struct RecordingWriterOutcome: Sendable {
    let outputURL: URL
    let requestedPixelSize: CGSize
    let appendedFrameCount: Int
    let droppedFrameCount: Int
}

/// Writes screen samples to one H.264 MP4.
///
/// Every method must be called on the owning session's serial sample queue; the class is
/// `@unchecked Sendable` on that basis alone. Nothing here touches the main actor.
///
/// The writer session starts at the first valid ScreenCaptureKit sample's presentation timestamp,
/// never at wall clock time. In video-only R1 that is necessarily a video sample; with R3 system
/// audio it may be audio. Keeping the earliest stream timestamp avoids dropping initial audio and
/// preserves the capture pipeline's shared media clock.
final class RecordingVideoWriter: @unchecked Sendable {
    /// Initial encoder policy, to be validated during device QA rather than assumed correct:
    /// 0.15 bits per pixel per frame, clamped to 2–40 Mbps, with a two-second keyframe interval.
    static let bitsPerPixelPerFrame = 0.15
    static let minimumBitRate = 2_000_000
    static let maximumBitRate = 40_000_000

    static func averageBitRate(pixelSize: CGSize, frameRate: Int) -> Int {
        let raw = Double(pixelSize.width) * Double(pixelSize.height)
            * Double(max(frameRate, 1)) * bitsPerPixelPerFrame
        guard raw.isFinite else { return minimumBitRate }
        return Int(min(max(raw, Double(minimumBitRate)), Double(maximumBitRate)))
    }

    private let logger = Logger(subsystem: "com.docshot.app", category: "RecordingVideoWriter")

    private let writer: AVAssetWriter
    private let input: AVAssetWriterInput
    private let audioInput: AVAssetWriterInput?
    private let outputURL: URL
    private let requestedPixelSize: CGSize

    private var hasStartedSession = false
    private var isTerminal = false
    private(set) var appendedFrameCount = 0
    private(set) var droppedFrameCount = 0

    init(outputURL: URL, pixelSize: CGSize, frameRate: Int, capturesSystemAudio: Bool) throws {
        guard pixelSize.width >= 1, pixelSize.height >= 1,
              pixelSize.width.isFinite, pixelSize.height.isFinite else {
            throw RecordingFailure.writer("The selected size (\(Int(pixelSize.width)) × \(Int(pixelSize.height)) px) cannot be encoded.")
        }

        self.outputURL = outputURL
        self.requestedPixelSize = pixelSize

        do {
            writer = try AVAssetWriter(outputURL: outputURL, fileType: .mp4)
        } catch {
            throw RecordingFailure.writer(error.localizedDescription)
        }

        // The selected pixel size is preserved exactly, odd dimensions included.
        let compression: [String: Any] = [
            AVVideoAverageBitRateKey: RecordingVideoWriter.averageBitRate(
                pixelSize: pixelSize,
                frameRate: frameRate
            ),
            AVVideoMaxKeyFrameIntervalKey: max(frameRate, 1) * 2,
            AVVideoProfileLevelKey: AVVideoProfileLevelH264HighAutoLevel,
            AVVideoAllowFrameReorderingKey: false
        ]

        input = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: Int(pixelSize.width),
                AVVideoHeightKey: Int(pixelSize.height),
                AVVideoCompressionPropertiesKey: compression
            ]
        )
        input.expectsMediaDataInRealTime = true

        guard writer.canAdd(input) else {
            throw RecordingFailure.writer("The video input could not be added to the MP4 writer.")
        }
        writer.add(input)

        if capturesSystemAudio {
            let input = AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: 48_000,
                    AVNumberOfChannelsKey: 2,
                    AVEncoderBitRateKey: 192_000
                ]
            )
            input.expectsMediaDataInRealTime = true
            guard writer.canAdd(input) else {
                throw RecordingFailure.writer("The system-audio input could not be added to the MP4 writer.")
            }
            writer.add(input)
            audioInput = input
        } else {
            audioInput = nil
        }

        guard writer.startWriting() else {
            throw RecordingFailure.writer(
                writer.error?.localizedDescription ?? "The MP4 writer could not be started."
            )
        }
    }

    /// Records a frame the stream reported as incomplete or unusable.
    func noteDroppedFrame() {
        guard !isTerminal else { return }
        droppedFrameCount += 1
    }

    func appendVideo(_ sampleBuffer: CMSampleBuffer) {
        guard !isTerminal else { return }
        guard CMSampleBufferIsValid(sampleBuffer), CMSampleBufferGetNumSamples(sampleBuffer) > 0 else {
            droppedFrameCount += 1
            return
        }

        guard beginSessionIfNeeded(for: sampleBuffer) else {
            droppedFrameCount += 1
            return
        }

        // Back-pressure: an input that is not ready must never be appended to. Dropping here is
        // counted for diagnostics only and is never reported as user analytics.
        guard input.isReadyForMoreMediaData else {
            droppedFrameCount += 1
            return
        }

        if input.append(sampleBuffer) {
            appendedFrameCount += 1
        } else {
            droppedFrameCount += 1
            logger.error("Sample append failed: \(self.writer.error?.localizedDescription ?? "unknown", privacy: .public)")
        }
    }

    /// Audio and video are supplied by ScreenCaptureKit on the same serialized stream queue. The
    /// first valid buffer, of either type, anchors the writer so no leading audio is discarded.
    func appendAudio(_ sampleBuffer: CMSampleBuffer) {
        guard !isTerminal, let audioInput else { return }
        guard beginSessionIfNeeded(for: sampleBuffer), audioInput.isReadyForMoreMediaData else { return }
        _ = audioInput.append(sampleBuffer)
    }

    private func beginSessionIfNeeded(for sampleBuffer: CMSampleBuffer) -> Bool {
        guard CMSampleBufferIsValid(sampleBuffer), CMSampleBufferGetNumSamples(sampleBuffer) > 0 else {
            return false
        }
        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard presentationTime.isValid, !presentationTime.isIndefinite else { return false }
        if !hasStartedSession {
            writer.startSession(atSourceTime: presentationTime)
            hasStartedSession = true
        }
        return true
    }

    /// Finishes the file. Calls back on an arbitrary queue exactly once.
    func finish(completion: @escaping @Sendable (Result<RecordingWriterOutcome, RecordingFailure>) -> Void) {
        guard !isTerminal else {
            completion(.failure(.stopFailed("The recording was already finished.")))
            return
        }
        isTerminal = true

        guard hasStartedSession, appendedFrameCount > 0 else {
            writer.cancelWriting()
            completion(.failure(.writer("No frames were recorded.")))
            return
        }

        let outcome = RecordingWriterOutcome(
            outputURL: outputURL,
            requestedPixelSize: requestedPixelSize,
            appendedFrameCount: appendedFrameCount,
            droppedFrameCount: droppedFrameCount
        )

        input.markAsFinished()
        audioInput?.markAsFinished()
        // `self` carries the queue invariant; capturing the writer itself would move a
        // non-Sendable value into the completion handler.
        writer.finishWriting { [weak self] in
            guard let self else {
                completion(.failure(.writer("The writer was released before the file was finished.")))
                return
            }
            guard self.writer.status == .completed else {
                completion(.failure(.writer(
                    self.writer.error?.localizedDescription ?? "The MP4 file could not be finished."
                )))
                return
            }
            completion(.success(outcome))
        }
    }

    /// Abandons the file. `cancelWriting` removes the partial output; the temporary store removes
    /// it again on the coordinator's cleanup path, and both are idempotent.
    func cancel() {
        guard !isTerminal else { return }
        isTerminal = true
        writer.cancelWriting()
    }
}

/// Confirms that a finished file is real, finite media before it is ever offered to the user.
enum RecordingAssetValidator {
    static func validate(outcome: RecordingWriterOutcome, now: Date = Date()) async throws -> TemporaryRecording {
        let asset = AVURLAsset(url: outcome.outputURL)

        let duration: CMTime
        let videoTracks: [AVAssetTrack]
        do {
            duration = try await asset.load(.duration)
            videoTracks = try await asset.loadTracks(withMediaType: .video)
        } catch {
            throw RecordingFailure.writer("The recording could not be read back: \(error.localizedDescription)")
        }

        guard duration.isValid, duration.isNumeric else {
            throw RecordingFailure.writer("The recording has no finite duration.")
        }
        let seconds = CMTimeGetSeconds(duration)
        guard seconds.isFinite, seconds > 0 else {
            throw RecordingFailure.writer("The recording is empty.")
        }
        guard let track = videoTracks.first else {
            throw RecordingFailure.writer("The recording contains no video track.")
        }

        let naturalSize: CGSize
        do {
            naturalSize = try await track.load(.naturalSize)
        } catch {
            throw RecordingFailure.writer("The recording's dimensions could not be read: \(error.localizedDescription)")
        }

        if naturalSize != outcome.requestedPixelSize {
            // Kept rather than rejected: the recording is still the user's. Device QA covers the
            // odd-dimension case specifically.
            Logger(subsystem: "com.docshot.app", category: "RecordingVideoWriter").warning(
                "Encoded size \(Int(naturalSize.width))×\(Int(naturalSize.height)) differs from the selected \(Int(outcome.requestedPixelSize.width))×\(Int(outcome.requestedPixelSize.height))"
            )
        }

        let audioTracks = (try? await asset.loadTracks(withMediaType: .audio)) ?? []

        return TemporaryRecording(
            url: outcome.outputURL,
            duration: seconds,
            pixelSize: naturalSize,
            hasAudio: !audioTracks.isEmpty,
            createdAt: now
        )
    }
}
