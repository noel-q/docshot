import Testing
import Foundation
import AVFoundation
import CoreMedia
import CoreVideo
import CoreGraphics
@testable import DocShot

/// End-to-end export against a real, synthesised source movie.
///
/// The source is built one second per colour — red, then green, then blue — so a test can assert
/// *which* footage came out, not merely that something did. That is what makes trim, reorder, and
/// delete verifiable rather than plausible.
/// Serialized deliberately: each test drives a real `AVAssetWriter` and `AVAssetExportSession`, and
/// running a dozen hardware encode pipelines concurrently starves the encoder and hangs the run.
@Suite("VideoProject Export Tests", .serialized)
struct VideoProjectExportTests {

    private static let frameRate: Int32 = 30
    private static let size = CGSize(width: 320, height: 240)

    private struct RGB {
        let red: Double
        let green: Double
        let blue: Double

        static let red = RGB(red: 1, green: 0, blue: 0)
        static let green = RGB(red: 0, green: 1, blue: 0)
        static let blue = RGB(red: 0, green: 0, blue: 1)
        static let yellow = RGB(red: 1, green: 1, blue: 0)

        func isClose(to other: RGB, tolerance: Double = 0.3) -> Bool {
            abs(red - other.red) < tolerance
                && abs(green - other.green) < tolerance
                && abs(blue - other.blue) < tolerance
        }

        var description: String {
            String(format: "(%.2f, %.2f, %.2f)", red, green, blue)
        }
    }

    // MARK: - Fixtures

    private func makeStore() -> (FileManagerTemporaryRecordingStore, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DocShotVideoExportTest_\(UUID().uuidString)", isDirectory: true)
        return (FileManagerTemporaryRecordingStore(rootDirectory: root), root)
    }

    /// Writes a movie of solid one-second colour blocks, optionally with a silent audio track.
    private func makeSourceMovie(
        colours: [RGB] = [.red, .green, .blue],
        withAudio: Bool = false
    ) async throws -> (url: URL, duration: TimeInterval) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("DocShotVideoSource_\(UUID().uuidString)")
            .appendingPathExtension("mp4")

        let writer = try AVAssetWriter(outputURL: url, fileType: .mp4)

        let videoInput = AVAssetWriterInput(
            mediaType: .video,
            outputSettings: [
                AVVideoCodecKey: AVVideoCodecType.h264,
                AVVideoWidthKey: Int(Self.size.width),
                AVVideoHeightKey: Int(Self.size.height)
            ]
        )
        videoInput.expectsMediaDataInRealTime = false
        let adaptor = AVAssetWriterInputPixelBufferAdaptor(
            assetWriterInput: videoInput,
            sourcePixelBufferAttributes: [
                kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32ARGB),
                kCVPixelBufferWidthKey as String: Int(Self.size.width),
                kCVPixelBufferHeightKey as String: Int(Self.size.height)
            ]
        )
        writer.add(videoInput)

        var audioInput: AVAssetWriterInput?
        if withAudio {
            let input = AVAssetWriterInput(
                mediaType: .audio,
                outputSettings: [
                    AVFormatIDKey: kAudioFormatMPEG4AAC,
                    AVSampleRateKey: 48_000,
                    AVNumberOfChannelsKey: 2,
                    AVEncoderBitRateKey: 128_000
                ]
            )
            input.expectsMediaDataInRealTime = false
            writer.add(input)
            audioInput = input
        }

        guard writer.startWriting() else {
            throw HarnessError.sourceWriteFailed(
                writer.error?.localizedDescription ?? "startWriting() was refused"
            )
        }
        writer.startSession(atSourceTime: .zero)

        // Audio and video are interleaved as they are produced. Writing one track to completion
        // before starting the other stalls the writer: it holds the lagging input unready while it
        // waits for the media it expects next.
        let chunkFrames = 1024
        let audioChunkCount = withAudio
            ? Int((Double(colours.count) * 48_000.0 / Double(chunkFrames)).rounded())
            : 0
        var audioChunk = 0

        let totalFrames = Int(Self.frameRate) * colours.count
        for frame in 0..<totalFrames {
            let colourIndex = min(frame / Int(Self.frameRate), colours.count - 1)
            let buffer = try makePixelBuffer(colour: colours[colourIndex])
            try await waitForReadiness(of: videoInput, writer: writer)
            adaptor.append(buffer, withPresentationTime: CMTime(value: CMTimeValue(frame), timescale: Self.frameRate))

            guard let audioInput else { continue }
            let frameEnd = Double(frame + 1) / Double(Self.frameRate)
            while audioChunk < audioChunkCount,
                  Double(audioChunk * chunkFrames) / 48_000.0 < frameEnd {
                let time = CMTime(value: CMTimeValue(audioChunk * chunkFrames), timescale: 48_000)
                let sample = try makeSilentAudioSample(at: time, frames: chunkFrames)
                try await waitForReadiness(of: audioInput, writer: writer)
                audioInput.append(sample)
                audioChunk += 1
            }
        }

        if let audioInput {
            while audioChunk < audioChunkCount {
                let time = CMTime(value: CMTimeValue(audioChunk * chunkFrames), timescale: 48_000)
                let sample = try makeSilentAudioSample(at: time, frames: chunkFrames)
                try await waitForReadiness(of: audioInput, writer: writer)
                audioInput.append(sample)
                audioChunk += 1
            }
            audioInput.markAsFinished()
        }
        videoInput.markAsFinished()

        await writer.finishWriting()
        guard writer.status == .completed else {
            throw HarnessError.sourceWriteFailed(writer.error?.localizedDescription ?? "unknown")
        }

        return (url, TimeInterval(colours.count))
    }

    /// A short source clip *with* an audio track, built through the app's own
    /// `RecordingVideoWriter` — the same path a real recording takes, and one already proven to
    /// produce a valid AAC track by `RecordingAudioTrackTests`.
    ///
    /// The bespoke writer above is used for the colour fixtures because it can run flat out; this
    /// one is paced to the frame rate because the production writer's inputs are real-time and
    /// shed anything arriving faster.
    private func makeSourceMovieWithAudio() async throws -> (url: URL, duration: TimeInterval) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("DocShotVideoSourceAudio_\(UUID().uuidString)")
            .appendingPathExtension("mp4")

        let writer = try RecordingVideoWriter(
            outputURL: url,
            pixelSize: Self.size,
            frameRate: Int(Self.frameRate),
            capturesSystemAudio: true
        )

        let frameDuration = CMTime(value: 1, timescale: Self.frameRate)
        let chunkFrames = 1024
        var audioTime = CMTime.zero
        let totalFrames = 45 // 1.5 seconds

        for frame in 0..<totalFrames {
            let presentationTime = CMTime(value: CMTimeValue(frame), timescale: Self.frameRate)
            writer.appendVideo(try makeVideoSample(colour: .red, at: presentationTime, duration: frameDuration))

            let frameEnd = Double(frame + 1) / Double(Self.frameRate)
            while CMTimeGetSeconds(audioTime) < frameEnd {
                writer.appendAudio(try makeSilentAudioSample(at: audioTime, frames: chunkFrames))
                audioTime = CMTimeAdd(audioTime, CMTime(value: CMTimeValue(chunkFrames), timescale: 48_000))
            }

            try await Task.sleep(nanoseconds: UInt64(1_000_000_000 / Double(Self.frameRate)))
        }

        let outcome = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<RecordingWriterOutcome, Error>) in
            writer.finish { continuation.resume(with: $0.mapError { $0 as Error }) }
        }
        let recording = try await RecordingAssetValidator.validate(outcome: outcome)
        return (recording.url, recording.duration)
    }

    private func makeVideoSample(colour: RGB, at time: CMTime, duration: CMTime) throws -> CMSampleBuffer {
        let pixelBuffer = try makePixelBuffer(colour: colour)

        var formatDescription: CMVideoFormatDescription?
        guard CMVideoFormatDescriptionCreateForImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescriptionOut: &formatDescription
        ) == noErr, let formatDescription else {
            throw HarnessError.context
        }

        var timing = CMSampleTimingInfo(
            duration: duration,
            presentationTimeStamp: time,
            decodeTimeStamp: .invalid
        )
        var sampleBuffer: CMSampleBuffer?
        guard CMSampleBufferCreateReadyWithImageBuffer(
            allocator: kCFAllocatorDefault,
            imageBuffer: pixelBuffer,
            formatDescription: formatDescription,
            sampleTiming: &timing,
            sampleBufferOut: &sampleBuffer
        ) == noErr, let sampleBuffer else {
            throw HarnessError.context
        }
        return sampleBuffer
    }

    /// Waits for an input to accept more data, bounded. An unbounded wait turns any writer failure
    /// into a hung test run rather than a readable failure.
    private func waitForReadiness(of input: AVAssetWriterInput, writer: AVAssetWriter) async throws {
        var attempts = 0
        while !input.isReadyForMoreMediaData {
            if writer.status == .failed {
                throw HarnessError.sourceWriteFailed(
                    writer.error?.localizedDescription ?? "the writer failed mid-run"
                )
            }
            try await Task.sleep(nanoseconds: 2_000_000)
            attempts += 1
            if attempts > 2_500 {
                throw HarnessError.sourceWriteFailed("an input never became ready to accept data")
            }
        }
    }

    private func makePixelBuffer(colour: RGB) throws -> CVPixelBuffer {
        var pixelBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            Int(Self.size.width),
            Int(Self.size.height),
            kCVPixelFormatType_32ARGB,
            nil,
            &pixelBuffer
        )
        guard status == kCVReturnSuccess, let pixelBuffer else {
            throw HarnessError.pixelBuffer(status)
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, [])
        defer { CVPixelBufferUnlockBaseAddress(pixelBuffer, []) }

        guard let base = CVPixelBufferGetBaseAddress(pixelBuffer),
              let context = CGContext(
                data: base,
                width: Int(Self.size.width),
                height: Int(Self.size.height),
                bitsPerComponent: 8,
                bytesPerRow: CVPixelBufferGetBytesPerRow(pixelBuffer),
                space: CGColorSpaceCreateDeviceRGB(),
                bitmapInfo: CGImageAlphaInfo.noneSkipFirst.rawValue
              ) else {
            throw HarnessError.context
        }

        context.setFillColor(red: colour.red, green: colour.green, blue: colour.blue, alpha: 1)
        context.fill(CGRect(origin: .zero, size: Self.size))
        return pixelBuffer
    }

    private func makeSilentAudioSample(at time: CMTime, frames: Int) throws -> CMSampleBuffer {
        var asbd = AudioStreamBasicDescription(
            mSampleRate: 48_000,
            mFormatID: kAudioFormatLinearPCM,
            mFormatFlags: kAudioFormatFlagIsFloat | kAudioFormatFlagIsPacked,
            mBytesPerPacket: 8,
            mFramesPerPacket: 1,
            mBytesPerFrame: 8,
            mChannelsPerFrame: 2,
            mBitsPerChannel: 32,
            mReserved: 0
        )
        var formatDescription: CMAudioFormatDescription?
        guard CMAudioFormatDescriptionCreate(
            allocator: kCFAllocatorDefault,
            asbd: &asbd,
            layoutSize: 0,
            layout: nil,
            magicCookieSize: 0,
            magicCookie: nil,
            extensions: nil,
            formatDescriptionOut: &formatDescription
        ) == noErr, let formatDescription else {
            throw HarnessError.context
        }

        let byteCount = frames * 8
        var blockBuffer: CMBlockBuffer?
        guard CMBlockBufferCreateWithMemoryBlock(
            allocator: kCFAllocatorDefault,
            memoryBlock: nil,
            blockLength: byteCount,
            blockAllocator: kCFAllocatorDefault,
            customBlockSource: nil,
            offsetToData: 0,
            dataLength: byteCount,
            flags: 0,
            blockBufferOut: &blockBuffer
        ) == kCMBlockBufferNoErr, let blockBuffer else {
            throw HarnessError.context
        }
        _ = CMBlockBufferFillDataBytes(with: 0, blockBuffer: blockBuffer, offsetIntoDestination: 0, dataLength: byteCount)

        var sampleBuffer: CMSampleBuffer?
        guard CMAudioSampleBufferCreateReadyWithPacketDescriptions(
            allocator: kCFAllocatorDefault,
            dataBuffer: blockBuffer,
            formatDescription: formatDescription,
            sampleCount: CMItemCount(frames),
            presentationTimeStamp: time,
            packetDescriptions: nil,
            sampleBufferOut: &sampleBuffer
        ) == noErr, let sampleBuffer else {
            throw HarnessError.context
        }
        return sampleBuffer
    }

    /// The average colour of a frame. Frames are solid blocks, so averaging is immune to the
    /// block noise H.264 introduces around edges.
    private func averageColour(of url: URL, atSeconds seconds: TimeInterval) throws -> RGB {
        let generator = AVAssetImageGenerator(asset: AVURLAsset(url: url))
        generator.requestedTimeToleranceBefore = .zero
        generator.requestedTimeToleranceAfter = .zero
        generator.appliesPreferredTrackTransform = true

        let image = try generator.copyCGImage(
            at: CMTime(seconds: seconds, preferredTimescale: 600),
            actualTime: nil
        )

        var pixel = [UInt8](repeating: 0, count: 4)
        guard let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            throw HarnessError.context
        }
        context.interpolationQuality = .medium
        context.draw(image, in: CGRect(x: 0, y: 0, width: 1, height: 1))

        return RGB(
            red: Double(pixel[0]) / 255.0,
            green: Double(pixel[1]) / 255.0,
            blue: Double(pixel[2]) / 255.0
        )
    }

    private enum HarnessError: Error {
        case pixelBuffer(CVReturn)
        case context
        case sourceWriteFailed(String)
    }

    private func expectColour(
        _ url: URL,
        at seconds: TimeInterval,
        isNear expected: RGB,
        sourceLocation: SourceLocation = #_sourceLocation
    ) throws {
        let actual = try averageColour(of: url, atSeconds: seconds)
        #expect(
            actual.isClose(to: expected),
            "At \(seconds)s expected \(expected.description), got \(actual.description)",
            sourceLocation: sourceLocation
        )
    }

    // MARK: - Rendering the timeline

    @Test("An unedited project exports the whole recording, in order")
    func testExportUnedited() async throws {
        let (store, root) = makeStore()
        let source = try await makeSourceMovie(withAudio: false)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: source.url)
        }

        let project = VideoProject(
            sourceURL: source.url,
            sourceDuration: source.duration,
            sourcePixelSize: Self.size,
            hasSourceAudio: false
        )

        let exported = try await AVFoundationVideoProjectExporter(store: store).export(project)

        #expect(abs(exported.duration - 3) < 0.2, "Expected ~3s, got \(exported.duration)")
        try expectColour(exported.url, at: 0.5, isNear: .red)
        try expectColour(exported.url, at: 1.5, isNear: .green)
        try expectColour(exported.url, at: 2.5, isNear: .blue)
    }

    @Test("A trimmed project exports only the footage that was kept")
    func testExportTrimmed() async throws {
        let (store, root) = makeStore()
        let source = try await makeSourceMovie(withAudio: false)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: source.url)
        }

        var project = VideoProject(
            sourceURL: source.url,
            sourceDuration: source.duration,
            sourcePixelSize: Self.size,
            hasSourceAudio: false
        )
        try project.trim(segmentID: project.segments[0].id, to: VideoTimeRange(start: 2, duration: 1))

        let exported = try await AVFoundationVideoProjectExporter(store: store).export(project)

        #expect(abs(exported.duration - 1) < 0.2, "Expected ~1s, got \(exported.duration)")
        try expectColour(exported.url, at: 0.5, isNear: .blue)
    }

    @Test("Reordered clips are rendered in timeline order")
    func testExportReordered() async throws {
        let (store, root) = makeStore()
        let source = try await makeSourceMovie(withAudio: false)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: source.url)
        }

        var project = VideoProject(
            sourceURL: source.url,
            sourceDuration: source.duration,
            sourcePixelSize: Self.size,
            hasSourceAudio: false
        )
        try project.split(atTimelineTime: 1)
        let second = try project.split(atTimelineTime: 2)
        // Timeline is now red | green | blue. Move the blue clip to the front.
        try project.moveSegment(id: second.trailing, toIndex: 0)

        let exported = try await AVFoundationVideoProjectExporter(store: store).export(project)

        #expect(abs(exported.duration - 3) < 0.2)
        try expectColour(exported.url, at: 0.5, isNear: .blue)
        try expectColour(exported.url, at: 1.5, isNear: .red)
        try expectColour(exported.url, at: 2.5, isNear: .green)
    }

    @Test("A removed clip is absent from the export")
    func testExportWithRemovedSegment() async throws {
        let (store, root) = makeStore()
        let source = try await makeSourceMovie(withAudio: false)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: source.url)
        }

        var project = VideoProject(
            sourceURL: source.url,
            sourceDuration: source.duration,
            sourcePixelSize: Self.size,
            hasSourceAudio: false
        )
        try project.split(atTimelineTime: 1)
        let second = try project.split(atTimelineTime: 2)
        try project.removeSegment(id: second.leading) // drop the green middle

        let exported = try await AVFoundationVideoProjectExporter(store: store).export(project)

        #expect(abs(exported.duration - 2) < 0.2, "Expected ~2s, got \(exported.duration)")
        try expectColour(exported.url, at: 0.5, isNear: .red)
        try expectColour(exported.url, at: 1.5, isNear: .blue)
    }

    // MARK: - Annotations

    @Test("Annotations are composited into the frames they cover, and only those")
    func testExportCompositesAnnotations() async throws {
        let (store, root) = makeStore()
        let source = try await makeSourceMovie(withAudio: false)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: source.url)
        }

        var project = VideoProject(
            sourceURL: source.url,
            sourceDuration: source.duration,
            sourcePixelSize: Self.size,
            hasSourceAudio: false
        )
        // A filled rectangle covering the whole frame for the first second only.
        try project.addAnnotation(VideoAnnotation(
            segmentID: project.segments[0].id,
            sourceRange: VideoTimeRange(start: 0, duration: 1),
            item: AnnotationItem(
                type: .rectangle(
                    rect: CGRect(origin: .zero, size: Self.size),
                    isFilled: true
                ),
                color: .yellow
            )
        ))

        let exported = try await AVFoundationVideoProjectExporter(store: store).export(project)

        try expectColour(exported.url, at: 0.5, isNear: .yellow)
        try expectColour(exported.url, at: 1.5, isNear: .green)
        try expectColour(exported.url, at: 2.5, isNear: .blue)
    }

    // MARK: - Audio

    @Test("Source audio is carried into the export")
    func testExportPreservesAudio() async throws {
        let (store, root) = makeStore()
        let source = try await makeSourceMovieWithAudio()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: source.url)
        }

        var project = VideoProject(
            sourceURL: source.url,
            sourceDuration: source.duration,
            sourcePixelSize: Self.size,
            hasSourceAudio: true
        )
        try project.trim(
            segmentID: project.segments[0].id,
            to: VideoTimeRange(start: 0.2, duration: min(0.8, source.duration - 0.3))
        )

        let exported = try await AVFoundationVideoProjectExporter(store: store).export(project)

        #expect(exported.hasAudio, "A recording with sound must keep it through an edit")
        let tracks = try await AVURLAsset(url: exported.url).loadTracks(withMediaType: .audio)
        #expect(tracks.count == 1)
    }

    @Test("A silent recording exports without inventing an audio track")
    func testExportWithoutAudio() async throws {
        let (store, root) = makeStore()
        let source = try await makeSourceMovie(withAudio: false)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: source.url)
        }

        let project = VideoProject(
            sourceURL: source.url,
            sourceDuration: source.duration,
            sourcePixelSize: Self.size,
            hasSourceAudio: false
        )

        let exported = try await AVFoundationVideoProjectExporter(store: store).export(project)

        #expect(exported.hasAudio == false)
    }

    // MARK: - Non-destructiveness

    @Test("Editing writes nothing; only export produces a file")
    func testEditingWritesNothing() async throws {
        let (store, root) = makeStore()
        let source = try await makeSourceMovie(withAudio: false)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: source.url)
        }

        var project = VideoProject(
            sourceURL: source.url,
            sourceDuration: source.duration,
            sourcePixelSize: Self.size,
            hasSourceAudio: false
        )
        try project.split(atTimelineTime: 1)
        try project.trim(segmentID: project.segments[0].id, to: VideoTimeRange(start: 0, duration: 0.5))
        try project.addAnnotation(VideoAnnotation(
            segmentID: project.segments[0].id,
            sourceRange: VideoTimeRange(start: 0, duration: 0.4),
            item: AnnotationItem(type: .ellipse(rect: CGRect(x: 0, y: 0, width: 10, height: 10), isFilled: true))
        ))

        #expect(
            FileManager.default.fileExists(atPath: root.path) == false,
            "Editing must not create so much as a directory"
        )

        let exported = try await AVFoundationVideoProjectExporter(store: store).export(project)
        #expect(FileManager.default.fileExists(atPath: exported.url.path))
    }

    @Test("The export lands in DocShot's temporary storage and leaves the recording untouched")
    func testExportWritesToTemporaryStoreOnly() async throws {
        let (store, root) = makeStore()
        let source = try await makeSourceMovie(withAudio: false)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: source.url)
        }

        let sourceSizeBefore = try FileManager.default.attributesOfItem(atPath: source.url.path)[.size] as? Int

        let project = VideoProject(
            sourceURL: source.url,
            sourceDuration: source.duration,
            sourcePixelSize: Self.size,
            hasSourceAudio: false
        )
        let exported = try await AVFoundationVideoProjectExporter(store: store).export(project)

        let parent = exported.url.deletingLastPathComponent().standardizedFileURL
        #expect(parent.path == root.standardizedFileURL.path)
        #expect(exported.url.pathExtension == "mp4")

        // The original recording is untouched: still there, same size.
        #expect(FileManager.default.fileExists(atPath: source.url.path))
        let sourceSizeAfter = try FileManager.default.attributesOfItem(atPath: source.url.path)[.size] as? Int
        #expect(sourceSizeBefore == sourceSizeAfter)
    }

    @Test("A failed export leaves no partial file and keeps the recording")
    func testFailedExportCleansUpAndKeepsSource() async throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let missingSource = FileManager.default.temporaryDirectory
            .appendingPathComponent("DocShotMissing_\(UUID().uuidString).mp4")

        let project = VideoProject(
            sourceURL: missingSource,
            sourceDuration: 3,
            sourcePixelSize: Self.size,
            hasSourceAudio: false
        )

        do {
            _ = try await AVFoundationVideoProjectExporter(store: store).export(project)
            Issue.record("Exporting a missing recording should fail")
        } catch is VideoProjectExportError {
            // Expected.
        }

        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        #expect(leftovers.isEmpty, "A failed export must not leave a partial file behind: \(leftovers)")
    }

    @Test("An empty timeline is refused before anything is written")
    func testEmptyTimelineIsRefused() async throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let project = VideoProject(
            sourceURL: URL(fileURLWithPath: "/tmp/does-not-matter.mp4"),
            sourceDuration: 3,
            sourcePixelSize: Self.size,
            hasSourceAudio: false,
            segments: []
        )

        do {
            _ = try await AVFoundationVideoProjectExporter(store: store).export(project)
            Issue.record("An empty timeline should be refused")
        } catch let error as VideoProjectExportError {
            #expect(error == .emptyTimeline)
        }

        #expect(FileManager.default.fileExists(atPath: root.path) == false)
    }

    @Test("A cancelled export leaves no orphan in temporary storage")
    func testCancelledExportLeavesNoOrphan() async throws {
        let (store, root) = makeStore()
        let source = try await makeSourceMovie(withAudio: false)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: source.url)
        }

        let project = VideoProject(
            sourceURL: source.url,
            sourceDuration: source.duration,
            sourcePixelSize: Self.size,
            hasSourceAudio: false
        )
        let exporter = AVFoundationVideoProjectExporter(store: store)

        let task = Task { try await exporter.export(project) }
        task.cancel()

        // Either outcome is legitimate — a short export can finish before cancellation lands —
        // but neither may strand a file the user never asked for.
        var completedURL: URL?
        do {
            completedURL = try await task.value.url
        } catch {
            completedURL = nil
        }

        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: root.path)) ?? []
        if let completedURL {
            #expect(leftovers == [completedURL.lastPathComponent])
        } else {
            #expect(leftovers.isEmpty, "A cancelled export must remove its partial file: \(leftovers)")
        }
    }
}
