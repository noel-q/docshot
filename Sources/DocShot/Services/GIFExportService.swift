import AVFoundation
import ImageIO
import UniformTypeIdentifiers

/// Converts a completed temporary MP4 into a bounded, silent GIF. It is intentionally app-only:
/// AVFoundation/ImageIO work never belongs in the hostless model-test subset.
final class GIFExportService: @unchecked Sendable {
    func export(source: TemporaryRecording, destination: URL, profile: GIFProfile) async throws -> URL {
        guard profile.supports(source) else {
            throw RecordingFailure.outputSave("GIF is available only for recordings of 15 seconds or less.")
        }
        return try await Task.detached(priority: .userInitiated) {
            let asset = AVURLAsset(url: source.url)
            let track = try await asset.loadTracks(withMediaType: .video).first
            guard let track else { throw RecordingFailure.writer("The MP4 has no video track for GIF export.") }
            let size = try await track.load(.naturalSize)
            let longEdge = max(size.width, size.height)
            let scale = longEdge > CGFloat(profile.maximumLongEdge) ? CGFloat(profile.maximumLongEdge) / longEdge : 1
            let outputSize = CGSize(width: max(1, (size.width * scale).rounded()), height: max(1, (size.height * scale).rounded()))

            guard let destinationRef = CGImageDestinationCreateWithURL(destination as CFURL, UTType.gif.identifier as CFString, 0, nil) else {
                throw RecordingFailure.writer("Could not create the temporary GIF.")
            }
            let generator = AVAssetImageGenerator(asset: asset)
            generator.appliesPreferredTrackTransform = true
            generator.maximumSize = outputSize
            let frameCount = max(1, Int(ceil(source.duration * Double(profile.framesPerSecond))))
            let frameDelay = 1.0 / Double(profile.framesPerSecond)
            CGImageDestinationSetProperties(destinationRef, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFLoopCount: 0]] as CFDictionary)
            for index in 0..<frameCount {
                let time = CMTime(seconds: Double(index) * frameDelay, preferredTimescale: 600)
                let image = try generator.copyCGImage(at: time, actualTime: nil)
                CGImageDestinationAddImage(destinationRef, image, [kCGImagePropertyGIFDictionary: [kCGImagePropertyGIFDelayTime: frameDelay]] as CFDictionary)
            }
            guard CGImageDestinationFinalize(destinationRef) else {
                throw RecordingFailure.writer("The GIF could not be finalized.")
            }
            let bytes = (try FileManager.default.attributesOfItem(atPath: destination.path)[.size] as? NSNumber)?.intValue ?? 0
            guard bytes <= profile.maximumEncodedBytes else {
                try? FileManager.default.removeItem(at: destination)
                throw RecordingFailure.outputSave("The GIF is larger than the 10 MB limit. Save the MP4 instead.")
            }
            return destination
        }.value
    }
}
