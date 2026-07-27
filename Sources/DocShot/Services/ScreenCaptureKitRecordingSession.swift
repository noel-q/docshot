import Foundation
import CoreMedia
import ScreenCaptureKit
import os

/// One `SCStream`, one serialized writer queue, and one temporary MP4.
///
/// Phase is guarded by a lock so that Stop is single-flight and a delegate error arriving during
/// teardown cannot report a failure for a session the user already ended. Sample handling and
/// encoding happen on the stream's own queue; nothing here touches the main actor.
final class ScreenCaptureKitRecordingSession: NSObject, RecordingSession, @unchecked Sendable {
    private enum Phase {
        case idle
        case starting
        case running
        case stopping
        case terminal
    }

    private let logger = Logger(subsystem: "com.docshot.app", category: "RecordingSession")

    /// The stream's sample handler queue. The writer is only ever touched here.
    private let sampleQueue = DispatchQueue(label: "com.docshot.app.recording.samples")
    private let lock = NSLock()

    private var phase: Phase = .idle
    private var stream: SCStream?
    private var writer: RecordingVideoWriter?
    private var outputURL: URL?

    private let onFailure: @Sendable (RecordingFailure) -> Void

    init(onFailure: @escaping @Sendable (RecordingFailure) -> Void) {
        self.onFailure = onFailure
        super.init()
    }

    // MARK: - RecordingSession

    func start(target: RecordingTarget, options: RecordingOptions, outputURL: URL) async throws {
        guard options.supportsCurrentAudioPipeline else {
            throw RecordingFailure.streamStart("Microphone and combined audio are not available yet.")
        }

        try withLock {
            guard phase == .idle else {
                throw RecordingFailure.streamStart("A recording session is already in progress.")
            }
            phase = .starting
            self.outputURL = outputURL
        }

        do {
            let resolved = try await RecordingFilterFactory.resolve(target: target, options: options)
            let writer = try RecordingVideoWriter(
                outputURL: outputURL,
                pixelSize: resolved.pixelSize,
                frameRate: options.maximumFrameRate,
                capturesSystemAudio: options.capturesSystemAudio
            )
            let stream = SCStream(
                filter: resolved.filter,
                configuration: resolved.configuration,
                delegate: self
            )
            try stream.addStreamOutput(self, type: .screen, sampleHandlerQueue: sampleQueue)
            if options.capturesSystemAudio {
                try stream.addStreamOutput(self, type: .audio, sampleHandlerQueue: sampleQueue)
            }

            // Both are in place before capture opens, so no sample can arrive with nowhere to go.
            withLock {
                self.writer = writer
                self.stream = stream
            }

            try await stream.startCapture()

            try withLock {
                // Cancelled while the stream was opening: unwind instead of going live.
                guard phase == .starting else {
                    throw RecordingFailure.streamStart("The recording was cancelled before it started.")
                }
                phase = .running
            }
        } catch {
            await teardownAfterStartFailure()
            throw Self.failure(from: error, fallback: .streamStart(error.localizedDescription))
        }
    }

    func stop() async throws -> TemporaryRecording {
        try withLock {
            guard phase == .running else {
                throw RecordingFailure.stopFailed("There is no recording to stop.")
            }
            phase = .stopping
        }

        let stream = withLock { self.stream }
        do {
            try await stream?.stopCapture()
        } catch {
            // A stream that already stopped is not a reason to lose the file; finishing the
            // writer is what decides whether there is usable media.
            logger.error("stopCapture reported: \(error as NSError, privacy: .public)")
        }

        do {
            let outcome = try await finishWriter()
            let recording = try await RecordingAssetValidator.validate(outcome: outcome)

            if outcome.droppedFrameCount > 0 {
                logger.info("Recording finished with \(outcome.appendedFrameCount) frames written, \(outcome.droppedFrameCount) dropped")
            }

            withLock {
                phase = .terminal
                self.stream = nil
                self.writer = nil
            }
            return recording
        } catch {
            await cancel()
            throw Self.failure(from: error, fallback: .stopFailed(error.localizedDescription))
        }
    }

    func cancel() async {
        let shouldTearDown: Bool = withLock {
            guard phase != .terminal else { return false }
            phase = .terminal
            return true
        }
        guard shouldTearDown else { return }

        let stream = withLock { self.stream }
        try? await stream?.stopCapture()

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            sampleQueue.async { [weak self] in
                self?.writer?.cancel()
                continuation.resume()
            }
        }

        withLock {
            self.stream = nil
            self.writer = nil
        }
    }

    // MARK: - Teardown helpers

    private func teardownAfterStartFailure() async {
        let stream = withLock {
            phase = .terminal
            return self.stream
        }
        try? await stream?.stopCapture()

        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            sampleQueue.async { [weak self] in
                self?.writer?.cancel()
                continuation.resume()
            }
        }

        withLock {
            self.stream = nil
            self.writer = nil
        }
    }

    private func finishWriter() async throws -> RecordingWriterOutcome {
        let writer = withLock { self.writer }
        guard let writer else {
            throw RecordingFailure.writer("The recording was already finished.")
        }

        return try await withCheckedThrowingContinuation { continuation in
            sampleQueue.async {
                writer.finish { result in
                    continuation.resume(with: result)
                }
            }
        }
    }

    private static func failure(from error: Error, fallback: RecordingFailure) -> RecordingFailure {
        (error as? RecordingFailure) ?? fallback
    }

    // MARK: - Locking

    private func withLock<T>(_ body: () throws -> T) rethrows -> T {
        lock.lock()
        defer { lock.unlock() }
        return try body()
    }
}

// MARK: - SCStreamOutput

extension ScreenCaptureKitRecordingSession: SCStreamOutput {
    func stream(
        _ stream: SCStream,
        didOutputSampleBuffer sampleBuffer: CMSampleBuffer,
        of type: SCStreamOutputType
    ) {
        // Already on `sampleQueue`, which is the only queue that touches the writer.
        let (writer, isRunning) = withLock { (self.writer, phase == .running || phase == .starting) }
        guard let writer, isRunning else { return }

        switch type {
        case .screen:
            guard frameStatus(of: sampleBuffer) == .complete else {
                writer.noteDroppedFrame()
                return
            }
            writer.appendVideo(sampleBuffer)
        case .audio:
            writer.appendAudio(sampleBuffer)
        default:
            return
        }
    }

    private func frameStatus(of sampleBuffer: CMSampleBuffer) -> SCFrameStatus? {
        guard let attachments = CMSampleBufferGetSampleAttachmentsArray(
            sampleBuffer,
            createIfNecessary: false
        ) as? [[SCStreamFrameInfo: Any]],
            let rawStatus = attachments.first?[.status] as? Int else {
            return nil
        }
        return SCFrameStatus(rawValue: rawStatus)
    }
}

// MARK: - SCStreamDelegate

extension ScreenCaptureKitRecordingSession: SCStreamDelegate {
    func stream(_ stream: SCStream, didStopWithError error: Error) {
        // Only an unsolicited stop is a failure. A stop the user asked for, or a cancellation,
        // has already moved the phase on, so the handler fires at most once per session.
        let shouldReport: Bool = withLock {
            guard phase == .running || phase == .starting else { return false }
            phase = .terminal
            return true
        }
        guard shouldReport else { return }

        logger.error("Stream stopped unexpectedly: \(error as NSError, privacy: .public)")
        onFailure(.streamInterrupted(error.localizedDescription))
    }
}

/// Builds the production session.
struct ScreenCaptureKitRecordingSessionFactory: RecordingSessionFactory {
    func makeSession(
        onFailure: @escaping @Sendable (RecordingFailure) -> Void
    ) -> any RecordingSession {
        ScreenCaptureKitRecordingSession(onFailure: onFailure)
    }
}
