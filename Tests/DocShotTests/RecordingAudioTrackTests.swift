import Testing
import Foundation
import AVFoundation
import CoreMedia
import CoreVideo
import CoreGraphics
@testable import DocShot

/// Drives `RecordingVideoWriter` with synthesised samples and inspects the MP4 it produces.
///
/// This is the part of the audio contract that does not need a device: whether an audio track
/// exists at all, what format it is in, and whether audio and video share the writer's session
/// clock. It cannot prove that a real audible source was captured, or that playback is perceptually
/// in sync — those stay in `docs/DEVICE_VERIFICATION.md`.
@Suite("Recording Audio Track Tests")
struct RecordingAudioTrackTests {

    private static let pixelSize = CGSize(width: 320, height: 240)
    private static let frameRate = 30
    private static let sampleRate: Float64 = 48_000
    private static let channels: UInt32 = 2
    private static let audioFramesPerChunk = 1024

    // MARK: - Harness

    private func makeOutputURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("DocShotAudioTest_\(UUID().uuidString)")
            .appendingPathExtension("mp4")
    }

    /// Writes a short clip and returns the finished file.
    ///
    /// - Parameter audioLeadsVideo: when true the first audio buffer is appended before any video
    ///   frame, which is what anchors the writer session on an audio timestamp.
    private func writeClip(
        capturesSystemAudio: Bool,
        audioLeadsVideo: Bool = false,
        videoFrames: Int = 20
    ) async throws -> (url: URL, outcome: RecordingWriterOutcome) {
        let url = makeOutputURL()
        let writer = try RecordingVideoWriter(
            outputURL: url,
            pixelSize: Self.pixelSize,
            frameRate: Self.frameRate,
            capturesSystemAudio: capturesSystemAudio
        )

        let start = CMTime(value: 1_000, timescale: 600)
        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(Self.frameRate))

        if capturesSystemAudio && audioLeadsVideo {
            // One chunk earlier than the first video frame.
            let leadTime = CMTimeSubtract(start, CMTime(value: 20, timescale: 600))
            writer.appendAudio(try makeAudioSample(at: leadTime))
        }

        // Audio is fed to cover the same span as the video, so a duration comparison measures the
        // writer rather than the harness.
        let chunkDuration = CMTime(
            value: CMTimeValue(Self.audioFramesPerChunk),
            timescale: CMTimeScale(Self.sampleRate)
        )
        let videoEnd = CMTimeAdd(start, CMTimeMultiply(frameDuration, multiplier: Int32(videoFrames)))

        var audioTime = start
        for index in 0..<videoFrames {
            let presentationTime = CMTimeAdd(start, CMTimeMultiply(frameDuration, multiplier: Int32(index)))
            writer.appendVideo(try makeVideoSample(at: presentationTime, duration: frameDuration))

            if capturesSystemAudio {
                while CMTimeCompare(audioTime, CMTimeAdd(presentationTime, frameDuration)) < 0,
                      CMTimeCompare(audioTime, videoEnd) < 0 {
                    writer.appendAudio(try makeAudioSample(at: audioTime))
                    audioTime = CMTimeAdd(audioTime, chunkDuration)
                }
            }

            // The writer inputs are configured for real-time media. Bursting frames at the encoder
            // as fast as the loop can build them makes it shed most of them — which is the
            // back-pressure behaviour working, not a writer defect. Pacing to the frame rate is
            // what ScreenCaptureKit actually does, and is what makes the timeline measurable.
            try await Task.sleep(nanoseconds: UInt64(1_000_000_000 / Double(Self.frameRate)))
        }

        let outcome = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<RecordingWriterOutcome, Error>) in
            writer.finish { result in
                continuation.resume(with: result.mapError { $0 as Error })
            }
        }
        return (url, outcome)
    }

    fileprivate func makeVideoSample(at time: CMTime, duration: CMTime) throws -> CMSampleBuffer {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(Self.pixelSize.width),
            Int(Self.pixelSize.height),
            kCVPixelFormatType_32BGRA,
            nil,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer else {
            throw HarnessError.pixelBuffer(status)
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        if let base = CVPixelBufferGetBaseAddress(pixelBuffer) {
            memset(base, 0x60, CVPixelBufferGetBytesPerRow(pixelBuffer) * Int(Self.pixelSize.height))
        }
        CVPixelBufferUnlockBaseAddress(pixelBuffer, [])

        var formatDescription: CMVideoFormatDescription?
        let formatStatus = CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDescription
        )
        guard formatStatus == noErr, let formatDescription else {
            throw HarnessError.formatDescription(formatStatus)
        }

        var timing = CMSampleTimingInfo(
            duration: duration,
            presentationTimeStamp: time,
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        let sampleStatus = CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: formatDescription,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        )
        guard sampleStatus == noErr, let sampleBuffer else {
            throw HarnessError.sampleBuffer(sampleStatus)
        }
        return sampleBuffer
    }

    /// One chunk of stereo float32 PCM, shaped like what ScreenCaptureKit delivers.
    private func makeAudioSample(at time: CMTime) throws -> CMSampleBuffer {
        var asbd = AudioStreamBasicDescription(
            mSampleRate: Self.sampleRate,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 4 * Self.channels,
            mFramesPerPacket: 1,
            mBytesPerFrame: 4 * Self.channels,
            mChannelsPerFrame: Self.channels,
            mBitsPerChannel: 32,
            mReserved: 0
        )

        var formatDescription: CMAudioFormatDescription?
        let formatStatus = CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &asbd,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDescription
        )
        guard formatStatus == noErr, let formatDescription else {
            throw HarnessError.formatDescription(formatStatus)
        }

        // An audible tone rather than silence, so the encoder has real content to work with.
        var samples = [Float](repeating: 0, count: Self.audioFramesPerChunk * Int(Self.channels))
        for frame in 0..<Self.audioFramesPerChunk {
            let value = Float(sin(Double(frame) * 2.0 * .pi * 440.0 / Self.sampleRate)) * 0.25
            samples[frame * Int(Self.channels)] = value
            samples[frame * Int(Self.channels) + 1] = value
        }
        let byteCount = samples.count * MemoryLayout<Float>.size

        var blockBuffer: CMBlockBuffer?
        let blockStatus = CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: byteCount,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: byteCount,
            flags: 0,
            blockBufferOut: &blockBuffer
        )
        guard blockStatus == kCMBlockBufferNoErr, let blockBuffer else {
            throw HarnessError.blockBuffer(blockStatus)
        }

        let fillStatus = samples.withUnsafeBytes { raw in
            CMBlockBufferReplaceDataBytes(
                with: raw.baseAddress!,
                blockBuffer: blockBuffer,
                offsetIntoDestination: 0,
                dataLength: byteCount
            )
        }
        guard fillStatus == kCMBlockBufferNoErr else {
            throw HarnessError.blockBuffer(fillStatus)
        }

        var sampleBuffer: CMSampleBuffer?
        let sampleStatus = CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: formatDescription,
            sampleCount: CMItemCount(Self.audioFramesPerChunk),
            presentationTimeStamp: time,
            packetDescriptions: nil,
            sampleBufferOut: &sampleBuffer
        )
        guard sampleStatus == noErr, let sampleBuffer else {
            throw HarnessError.sampleBuffer(sampleStatus)
        }
        return sampleBuffer
    }

    fileprivate enum HarnessError: Error {
        case pixelBuffer(CVReturn)
        case formatDescription(OSStatus)
        case sampleBuffer(OSStatus)
        case blockBuffer(OSStatus)
    }

    // MARK: - Audio off

    @Test("With audio off, the finished MP4 has no audio track at all")
    func testAudioOffProducesNoAudioTrack() async throws {
        let (url, outcome) = try await writeClip(capturesSystemAudio: false)
        defer { try? FileManager.default.removeItem(at: url) }

        let asset = AVURLAsset(url: url)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        let videoTracks = try await asset.loadTracks(withMediaType: .video)

        #expect(audioTracks.isEmpty, "Audio off must not produce an audio track")
        #expect(videoTracks.count == 1)
        #expect(outcome.appendedFrameCount > 0)

        // The value handed to the coordinator must agree with the file.
        let recording = try await RecordingAssetValidator.validate(outcome: outcome)
        #expect(recording.hasAudio == false)
        #expect(recording.isPlayable)
    }

    @Test("With audio off, audio buffers that arrive anyway are ignored")
    func testAudioOffIgnoresStrayAudioBuffers() async throws {
        let url = makeOutputURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let writer = try RecordingVideoWriter(
            outputURL: url,
            pixelSize: Self.pixelSize,
            frameRate: Self.frameRate,
            capturesSystemAudio: false
        )

        let start = CMTime(value: 1_000, timescale: 600)
        let frameDuration = CMTime(value: 1, timescale: CMTimeScale(Self.frameRate))
        for index in 0..<10 {
            let time = CMTimeAdd(start, CMTimeMultiply(frameDuration, multiplier: Int32(index)))
            writer.appendVideo(try makeVideoSample(at: time, duration: frameDuration))
            writer.appendAudio(try makeAudioSample(at: time))
        }

        let outcome = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<RecordingWriterOutcome, Error>) in
            writer.finish { result in
                continuation.resume(with: result.mapError { $0 as Error })
            }
        }

        let asset = AVURLAsset(url: outcome.outputURL)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)
        #expect(audioTracks.isEmpty, "No audio input exists, so stray audio must be dropped, not written")
    }

    // MARK: - System audio

    @Test("System audio produces exactly one AAC track at the configured rate and channel count")
    func testSystemAudioProducesAACTrack() async throws {
        let (url, outcome) = try await writeClip(capturesSystemAudio: true)
        defer { try? FileManager.default.removeItem(at: url) }

        let asset = AVURLAsset(url: url)
        let audioTracks = try await asset.loadTracks(withMediaType: .audio)

        #expect(audioTracks.count == 1)
        let audioTrack = try #require(audioTracks.first)

        let formats = try await audioTrack.load(.formatDescriptions)
        let format = try #require(formats.first)
        #expect(CMFormatDescriptionGetMediaSubType(format) == kAudioFormatMPEG4AAC)

        let asbd = try #require(CMAudioFormatDescriptionGetStreamBasicDescription(format)?.pointee)
        #expect(asbd.mSampleRate == Self.sampleRate)
        #expect(asbd.mChannelsPerFrame == Self.channels)

        let recording = try await RecordingAssetValidator.validate(outcome: outcome)
        #expect(recording.hasAudio)
        #expect(recording.isPlayable)
    }

    @Test("Audio and video are written against the same session clock")
    func testAudioAndVideoShareTheSessionClock() async throws {
        let (url, _) = try await writeClip(capturesSystemAudio: true)
        defer { try? FileManager.default.removeItem(at: url) }

        let asset = AVURLAsset(url: url)
        let audioTrack = try #require(try await asset.loadTracks(withMediaType: .audio).first)
        let videoTrack = try #require(try await asset.loadTracks(withMediaType: .video).first)

        let audioRange = try await audioTrack.load(.timeRange)
        let videoRange = try await videoTrack.load(.timeRange)

        let startSkew = abs(CMTimeGetSeconds(CMTimeSubtract(audioRange.start, videoRange.start)))
        #expect(
            startSkew < 1.0 / Double(Self.frameRate),
            "Audio and video must start within one frame of each other; skew was \(startSkew)s"
        )

        let audioSeconds = CMTimeGetSeconds(audioRange.duration)
        let videoSeconds = CMTimeGetSeconds(videoRange.duration)
        #expect(audioSeconds > 0)
        #expect(
            abs(audioSeconds - videoSeconds) < 0.15,
            "Tracks should cover comparable spans; audio \(audioSeconds)s vs video \(videoSeconds)s"
        )
    }

    @Test("Audio arriving before the first video frame anchors the session instead of being dropped")
    func testLeadingAudioIsNotDiscarded() async throws {
        let (url, _) = try await writeClip(capturesSystemAudio: true, audioLeadsVideo: true)
        defer { try? FileManager.default.removeItem(at: url) }

        let asset = AVURLAsset(url: url)
        let audioTrack = try #require(try await asset.loadTracks(withMediaType: .audio).first)
        let videoTrack = try #require(try await asset.loadTracks(withMediaType: .video).first)

        let audioRange = try await audioTrack.load(.timeRange)
        let videoRange = try await videoTrack.load(.timeRange)

        // The writer anchors on the earliest valid buffer of either type, so leading audio is
        // kept rather than landing before the session start and being discarded.
        #expect(CMTimeGetSeconds(audioRange.start) <= CMTimeGetSeconds(videoRange.start) + 0.001)
        #expect(CMTimeGetSeconds(audioRange.duration) > 0)
    }
}

/// What an interrupted session leaves on disk.
///
/// A revoked permission or a stream that stops on its own reaches the writer as a cancellation,
/// with or without audio configured. The state machine's cleanup effects are asserted in
/// `RecordingStateReducerTests`; this checks the other half — that the file itself is actually
/// gone once the writer is torn down.
@Suite("Recording Writer Cleanup Tests")
struct RecordingWriterCleanupTests {

    private let harness = RecordingAudioTrackTests()

    private func makeOutputURL() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("DocShotCleanupTest_\(UUID().uuidString)")
            .appendingPathExtension("mp4")
    }

    private func writeFrames(_ count: Int, to writer: RecordingVideoWriter) throws {
        let start = CMTime(value: 1_000, timescale: 600)
        let frameDuration = CMTime(value: 1, timescale: 30)
        for index in 0..<count {
            let time = CMTimeAdd(start, CMTimeMultiply(frameDuration, multiplier: Int32(index)))
            writer.appendVideo(try harness.makeVideoSample(at: time, duration: frameDuration))
        }
    }

    @Test("Cancelling a video-only writer leaves no partial file behind")
    func testCancelRemovesPartialFile() throws {
        let url = makeOutputURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let writer = try RecordingVideoWriter(
            outputURL: url,
            pixelSize: CGSize(width: 320, height: 240),
            frameRate: 30,
            capturesSystemAudio: false
        )
        try writeFrames(3, to: writer)

        writer.cancel()

        #expect(
            FileManager.default.fileExists(atPath: url.path) == false,
            "An interrupted recording must not leave media on disk"
        )
    }

    @Test("Cancelling a system-audio writer leaves no partial file behind")
    func testCancelWithAudioRemovesPartialFile() throws {
        let url = makeOutputURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let writer = try RecordingVideoWriter(
            outputURL: url,
            pixelSize: CGSize(width: 320, height: 240),
            frameRate: 30,
            capturesSystemAudio: true
        )
        try writeFrames(3, to: writer)

        writer.cancel()

        #expect(FileManager.default.fileExists(atPath: url.path) == false)
    }

    @Test("Cancelling is idempotent, as every terminal path may reach it")
    func testCancelIsIdempotent() throws {
        let url = makeOutputURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let writer = try RecordingVideoWriter(
            outputURL: url,
            pixelSize: CGSize(width: 320, height: 240),
            frameRate: 30,
            capturesSystemAudio: true
        )
        try writeFrames(2, to: writer)

        writer.cancel()
        writer.cancel()

        #expect(FileManager.default.fileExists(atPath: url.path) == false)
    }

    @Test("A session interrupted before any frame arrived fails and leaves no file")
    func testNoFramesLeavesNoFile() async throws {
        let url = makeOutputURL()
        defer { try? FileManager.default.removeItem(at: url) }

        let writer = try RecordingVideoWriter(
            outputURL: url,
            pixelSize: CGSize(width: 320, height: 240),
            frameRate: 30,
            capturesSystemAudio: true
        )

        let result = await withCheckedContinuation { (continuation: CheckedContinuation<Result<RecordingWriterOutcome, RecordingFailure>, Never>) in
            writer.finish { continuation.resume(returning: $0) }
        }

        switch result {
        case .success:
            Issue.record("A recording with no frames must not be offered to the user")
        case .failure(let failure):
            #expect(failure.discardsTemporaryMedia)
        }
        #expect(FileManager.default.fileExists(atPath: url.path) == false)
    }
}

/// The configuration half of the audio contract: what the stream is asked to capture, and whose
/// audio is excluded from it.
@Suite("Recording Audio Policy Tests")
struct RecordingAudioPolicyTests {

    @Test("Audio off requests no system audio")
    func testAudioOffRequestsNothing() {
        let options = RecordingOptions.videoOnly(showsCursor: false)

        #expect(options.capturesSystemAudio == false)
        #expect(options.isVideoOnly)
        #expect(options.supportsCurrentAudioPipeline)
    }

    @Test("System audio always excludes DocShot's own process audio")
    func testSystemAudioExcludesOwnProcess() {
        let options = RecordingOptions(audio: .system, showsCursor: false, maximumFrameRate: 30)

        #expect(options.capturesSystemAudio)
        #expect(
            options.excludesOwnProcessAudio,
            "DocShot's alert sounds and error beeps must never land in the user's recording"
        )
        #expect(options.isVideoOnly == false)
    }

    @Test("With audio off there is no process-audio exclusion to apply")
    func testAudioOffNeedsNoExclusion() {
        #expect(RecordingOptions.videoOnly(showsCursor: true).excludesOwnProcessAudio == false)
    }

    @Test("Microphone and combined modes are still refused by the current pipeline")
    func testUnsupportedAudioModesAreRefused() {
        let microphone = RecordingOptions(audio: .microphone(deviceID: nil), showsCursor: false, maximumFrameRate: 30)
        let combined = RecordingOptions(audio: .systemAndMicrophone(deviceID: nil), showsCursor: false, maximumFrameRate: 30)

        #expect(microphone.supportsCurrentAudioPipeline == false)
        #expect(combined.supportsCurrentAudioPipeline == false)
        #expect(microphone.capturesSystemAudio == false)
        #expect(combined.capturesSystemAudio == false)
    }
}
