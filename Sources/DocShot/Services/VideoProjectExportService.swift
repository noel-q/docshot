import Foundation
import AVFoundation
import CoreImage
import CoreMedia
import CoreGraphics

public enum VideoProjectExportError: Error, Equatable, Sendable, LocalizedError {
    case emptyTimeline
    case sourceUnreadable(String)
    case noVideoTrack
    case compositionFailed(String)
    case exportFailed(String)
    case cancelled

    public var errorDescription: String? {
        switch self {
        case .emptyTimeline:
            return "There is nothing on the timeline to export."
        case .sourceUnreadable(let detail):
            return "The recording could not be read: \(detail)"
        case .noVideoTrack:
            return "The recording contains no video track."
        case .compositionFailed(let detail):
            return "The edit could not be assembled: \(detail)"
        case .exportFailed(let detail):
            return "The export failed: \(detail)"
        case .cancelled:
            return "The export was cancelled."
        }
    }
}

/// Renders a `VideoProject` to a new file.
///
/// Export is the only operation in this feature that writes anything, and it is never automatic:
/// it produces a file in DocShot-owned temporary storage, which the caller then hands to the
/// existing save panel when — and only when — the user chooses Save.
public protocol VideoProjectExporting: Sendable {
    func export(
        _ project: VideoProject,
        progress: (@Sendable (Double) -> Void)?
    ) async throws -> TemporaryRecording
}

/// AVFoundation implementation: one composition, one optional CIFilter overlay pass, one export.
///
/// Guarantees that matter more than speed here:
/// - The source MP4 is opened read-only and is never written, moved, or removed — a failed or
///   cancelled export leaves the original exactly as it was.
/// - The output lands in the temporary store first, so nothing exists in a user-visible location
///   until an explicit Save moves it there.
/// - A failure or cancellation removes the partial export, so no orphan survives the attempt.
public final class AVFoundationVideoProjectExporter: VideoProjectExporting, @unchecked Sendable {

    /// Composition timescale. 600 is the conventional choice: it divides evenly by the common
    /// frame rates (24/25/30/60), so segment boundaries converted from seconds land on exact
    /// ticks rather than drifting.
    public static let timescale: CMTimeScale = 600

    private let store: any TemporaryRecordingStore
    private let overlayRenderer: VideoAnnotationOverlayRenderer
    private let presetName: String

    public init(
        store: any TemporaryRecordingStore,
        overlayRenderer: VideoAnnotationOverlayRenderer = VideoAnnotationOverlayRenderer(),
        presetName: String = AVAssetExportPresetHighestQuality
    ) {
        self.store = store
        self.overlayRenderer = overlayRenderer
        self.presetName = presetName
    }

    public func export(
        _ project: VideoProject,
        progress: (@Sendable (Double) -> Void)? = nil
    ) async throws -> TemporaryRecording {
        guard !project.segments.isEmpty, project.timelineDuration > 0 else {
            throw VideoProjectExportError.emptyTimeline
        }
        if Task.isCancelled { throw VideoProjectExportError.cancelled }

        let asset = AVURLAsset(url: project.sourceURL)
        let sourceVideoTrack: AVAssetTrack
        let sourceAudioTrack: AVAssetTrack?
        do {
            guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
                throw VideoProjectExportError.noVideoTrack
            }
            sourceVideoTrack = videoTrack
            sourceAudioTrack = try await asset.loadTracks(withMediaType: .audio).first
        } catch let error as VideoProjectExportError {
            throw error
        } catch {
            throw VideoProjectExportError.sourceUnreadable(error.localizedDescription)
        }

        let composition = AVMutableComposition()
        try buildComposition(
            composition,
            project: project,
            sourceVideoTrack: sourceVideoTrack,
            sourceAudioTrack: sourceAudioTrack
        )

        let renderSize = try await resolveRenderSize(project: project, sourceVideoTrack: sourceVideoTrack)
        let videoComposition = makeVideoComposition(
            for: composition,
            project: project,
            renderSize: renderSize
        )

        let outputURL: URL
        do {
            outputURL = try store.makeMP4URL()
        } catch {
            throw VideoProjectExportError.exportFailed(error.localizedDescription)
        }

        do {
            try await runExport(
                composition: composition,
                videoComposition: videoComposition,
                outputURL: outputURL,
                progress: progress
            )
        } catch {
            // The partial export goes; the user's recording stays exactly where it was.
            store.removeIfPresent(outputURL)
            throw error
        }

        do {
            return try await describe(outputURL: outputURL)
        } catch {
            store.removeIfPresent(outputURL)
            throw error
        }
    }

    // MARK: - Composition

    private func buildComposition(
        _ composition: AVMutableComposition,
        project: VideoProject,
        sourceVideoTrack: AVAssetTrack,
        sourceAudioTrack: AVAssetTrack?
    ) throws {
        guard let videoTrack = composition.addMutableTrack(
            withMediaType: .video,
            preferredTrackID: kCMPersistentTrackID_Invalid
        ) else {
            throw VideoProjectExportError.compositionFailed("Could not create a video track.")
        }

        // Audio is carried across only when the source actually has it; an absent audio track is
        // not an error, and a silent track is never invented.
        var audioTrack: AVMutableCompositionTrack?
        if sourceAudioTrack != nil {
            audioTrack = composition.addMutableTrack(
                withMediaType: .audio,
                preferredTrackID: kCMPersistentTrackID_Invalid
            )
        }

        var cursor = CMTime.zero
        for segment in project.segments {
            let range = CMTimeRange(
                start: CMTime(seconds: segment.sourceRange.start, preferredTimescale: Self.timescale),
                duration: CMTime(seconds: segment.sourceRange.duration, preferredTimescale: Self.timescale)
            )

            do {
                try videoTrack.insertTimeRange(range, of: sourceVideoTrack, at: cursor)
                if let audioTrack, let sourceAudioTrack {
                    try audioTrack.insertTimeRange(range, of: sourceAudioTrack, at: cursor)
                }
            } catch {
                throw VideoProjectExportError.compositionFailed(error.localizedDescription)
            }

            cursor = CMTimeAdd(cursor, range.duration)
        }
    }

    private func resolveRenderSize(
        project: VideoProject,
        sourceVideoTrack: AVAssetTrack
    ) async throws -> CGSize {
        if project.sourcePixelSize.width >= 1, project.sourcePixelSize.height >= 1 {
            return project.sourcePixelSize
        }
        do {
            return try await sourceVideoTrack.load(.naturalSize)
        } catch {
            throw VideoProjectExportError.sourceUnreadable(error.localizedDescription)
        }
    }

    /// Per-frame overlay compositing.
    ///
    /// Annotations are looked up by the frame's own composition time, which is timeline time —
    /// the project maps that back to source time internally, so reordered or split segments show
    /// the overlays that belong to the frames actually on screen.
    private func makeVideoComposition(
        for composition: AVMutableComposition,
        project: VideoProject,
        renderSize: CGSize
    ) -> AVMutableVideoComposition {
        let renderer = overlayRenderer

        let videoComposition = AVMutableVideoComposition(
            asset: composition,
            applyingCIFiltersWithHandler: { request in
                let timelineTime = CMTimeGetSeconds(request.compositionTime)
                let active = project.activeAnnotations(atTimelineTime: timelineTime)

                guard !active.isEmpty else {
                    request.finish(with: request.sourceImage, context: nil)
                    return
                }

                var output = renderer.applyRedactions(
                    to: request.sourceImage,
                    annotations: active,
                    pixelSize: renderSize
                )

                if let overlay = renderer.makeOverlayImage(annotations: active, pixelSize: renderSize) {
                    output = CIImage(cgImage: overlay).composited(over: output)
                }

                request.finish(with: output, context: nil)
            }
        )
        videoComposition.renderSize = renderSize
        return videoComposition
    }

    // MARK: - Export

    private func runExport(
        composition: AVMutableComposition,
        videoComposition: AVMutableVideoComposition,
        outputURL: URL,
        progress: (@Sendable (Double) -> Void)?
    ) async throws {
        guard let session = AVAssetExportSession(asset: composition, presetName: presetName) else {
            throw VideoProjectExportError.exportFailed("No export session is available for this preset.")
        }
        session.outputURL = outputURL
        session.outputFileType = .mp4
        session.videoComposition = videoComposition
        session.shouldOptimizeForNetworkUse = false

        // `AVAssetExportSession` is not `Sendable`, but `cancelExport()` and `progress` are both
        // designed to be reached from another thread while the export runs. The box carries that
        // guarantee explicitly rather than leaving it implicit at each capture site.
        let box = ExportSessionBox(session)

        let progressTask = progress.map { report in
            Task.detached(priority: .utility) {
                while !Task.isCancelled {
                    let value = Double(box.session.progress)
                    report(value)
                    if value >= 1 { break }
                    try? await Task.sleep(nanoseconds: 100_000_000)
                }
            }
        }
        defer { progressTask?.cancel() }

        try await withTaskCancellationHandler {
            try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
                let didStart = box.startIfNotCancelled { session in
                    session.exportAsynchronously {
                        switch session.status {
                        case .completed:
                            continuation.resume()
                        case .cancelled:
                            continuation.resume(throwing: VideoProjectExportError.cancelled)
                        default:
                            continuation.resume(
                                throwing: VideoProjectExportError.exportFailed(
                                    session.error?.localizedDescription ?? "The export did not complete."
                                )
                            )
                        }
                    }
                }

                // Cancelled before AVFoundation was ever asked to start: report it here, since no
                // completion handler will run.
                if !didStart {
                    continuation.resume(throwing: VideoProjectExportError.cancelled)
                }
            }
        } onCancel: {
            box.cancel()
        }
    }

    /// Carries the export session across concurrency boundaries for the two operations AVFoundation
    /// supports from another thread: reading `progress` and calling `cancelExport()`.
    ///
    /// It also sequences start against cancel. `cancelExport()` on a session that has not started
    /// leaves it in a terminal state, and `exportAsynchronously` on a terminal session raises
    /// `NSInternalInconsistencyException` — an uncatchable crash rather than a thrown error. A task
    /// cancelled before the export begins hits exactly that ordering, so the two are interlocked
    /// here: cancel only reaches AVFoundation once the export has actually started, and a start
    /// after cancellation never happens at all.
    private final class ExportSessionBox: @unchecked Sendable {
        let session: AVAssetExportSession

        private let lock = NSLock()
        private var hasStarted = false
        private var isCancelled = false

        init(_ session: AVAssetExportSession) {
            self.session = session
        }

        /// Starts the export, unless cancellation already happened.
        /// - Returns: `false` when the caller should report cancellation instead.
        func startIfNotCancelled(_ start: (AVAssetExportSession) -> Void) -> Bool {
            lock.lock()
            guard !isCancelled, !hasStarted else {
                lock.unlock()
                return false
            }
            hasStarted = true
            lock.unlock()

            start(session)
            return true
        }

        func cancel() {
            lock.lock()
            let shouldForward = hasStarted && !isCancelled
            isCancelled = true
            lock.unlock()

            if shouldForward {
                session.cancelExport()
            }
        }
    }

    /// Reads back what was actually written, so the caller is handed measured values rather than
    /// the ones the edit intended.
    private func describe(outputURL: URL) async throws -> TemporaryRecording {
        let asset = AVURLAsset(url: outputURL)
        do {
            let duration = try await asset.load(.duration)
            let seconds = CMTimeGetSeconds(duration)
            guard seconds.isFinite, seconds > 0 else {
                throw VideoProjectExportError.exportFailed("The exported file has no playable duration.")
            }

            guard let videoTrack = try await asset.loadTracks(withMediaType: .video).first else {
                throw VideoProjectExportError.exportFailed("The exported file has no video track.")
            }
            let size = try await videoTrack.load(.naturalSize)
            let audioTracks = try await asset.loadTracks(withMediaType: .audio)

            return TemporaryRecording(
                url: outputURL,
                duration: seconds,
                pixelSize: size,
                hasAudio: !audioTracks.isEmpty,
                createdAt: Date()
            )
        } catch let error as VideoProjectExportError {
            throw error
        } catch {
            throw VideoProjectExportError.exportFailed(error.localizedDescription)
        }
    }
}
