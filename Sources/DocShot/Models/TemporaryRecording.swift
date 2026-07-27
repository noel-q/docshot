import Foundation
import CoreGraphics

/// A finished recording that exists only in DocShot's private temporary directory.
///
/// This is not a history item and is never presented as a library entry. It exists between Stop
/// and the user's explicit Save or Discard, and every terminal path removes it. Deliberately free
/// of AVFoundation types so it compiles into the hostless Xcode test bundle.
public struct TemporaryRecording: Equatable, Sendable {
    /// A unique file inside DocShot's own temporary recordings directory.
    public let url: URL
    public let duration: TimeInterval
    /// The encoded pixel dimensions, as verified from the finished asset.
    public let pixelSize: CGSize
    /// Always `false` in R1: video-only recording writes no audio track.
    public let hasAudio: Bool
    public let createdAt: Date

    public init(
        url: URL,
        duration: TimeInterval,
        pixelSize: CGSize,
        hasAudio: Bool,
        createdAt: Date
    ) {
        self.url = url
        self.duration = duration
        self.pixelSize = pixelSize
        self.hasAudio = hasAudio
        self.createdAt = createdAt
    }

    /// A recording is only offered to the user when it describes real, finite media.
    public var isPlayable: Bool {
        duration.isFinite && duration > 0
            && pixelSize.width >= 1 && pixelSize.height >= 1
            && pixelSize.width.isFinite && pixelSize.height.isFinite
    }
}
