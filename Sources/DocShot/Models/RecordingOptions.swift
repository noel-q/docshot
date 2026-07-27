import Foundation

/// Which audio sources a recording captures.
///
/// R1 is video-only and constructs `.none` exclusively; the remaining cases exist so the R3 audio
/// milestone extends this type rather than replacing it. `ScreenCaptureKitRecordingSession`
/// rejects any non-`.none` value rather than silently ignoring it.
public enum RecordingAudioMode: Equatable, Sendable {
    case none
    case system
    case microphone(deviceID: String?)
    case systemAndMicrophone(deviceID: String?)
}

/// How a recording is configured, decided before the stream starts.
public struct RecordingOptions: Equatable, Sendable {
    public var audio: RecordingAudioMode
    public var showsCursor: Bool
    /// Frames per second the stream may not exceed. R1 fixes this at 30 with no user control.
    public var maximumFrameRate: Int

    public static let defaultMaximumFrameRate = 30

    public init(audio: RecordingAudioMode, showsCursor: Bool, maximumFrameRate: Int) {
        self.audio = audio
        self.showsCursor = showsCursor
        self.maximumFrameRate = maximumFrameRate
    }

    /// The only configuration R1 produces.
    public static func videoOnly(
        showsCursor: Bool,
        maximumFrameRate: Int = RecordingOptions.defaultMaximumFrameRate
    ) -> RecordingOptions {
        RecordingOptions(audio: .none, showsCursor: showsCursor, maximumFrameRate: maximumFrameRate)
    }

    public var isVideoOnly: Bool {
        audio == .none
    }

    /// R3's first audio slice supports ScreenCaptureKit system audio only. Microphone and mixed
    /// recording require their own capability and timestamp-validation work.
    public var supportsCurrentAudioPipeline: Bool {
        audio == .none || audio == .system
    }

    /// Whether the stream captures system audio at all. With audio off, no audio is requested
    /// from ScreenCaptureKit, no audio writer input is created, and the file has no audio track.
    public var capturesSystemAudio: Bool {
        audio == .system
    }

    /// Whether DocShot's own process audio must be kept out of the system-audio track.
    ///
    /// The video filter excludes DocShot's windows, but that says nothing about audio: system
    /// audio is captured globally, for a window target as much as a display one. Without this,
    /// DocShot's own alert sounds and error beeps would be recorded into the user's clip.
    public var excludesOwnProcessAudio: Bool {
        capturesSystemAudio
    }
}

/// The deliberately fixed R4 GIF profile. GIF is a post-stop conversion of a completed MP4;
/// these limits are checked before presenting any user-facing Save panel.
public struct GIFProfile: Equatable, Sendable {
    public let maximumDuration: TimeInterval
    public let framesPerSecond: Int
    public let maximumLongEdge: Int
    public let maximumEncodedBytes: Int

    public init(
        maximumDuration: TimeInterval,
        framesPerSecond: Int,
        maximumLongEdge: Int,
        maximumEncodedBytes: Int
    ) {
        self.maximumDuration = maximumDuration
        self.framesPerSecond = framesPerSecond
        self.maximumLongEdge = maximumLongEdge
        self.maximumEncodedBytes = maximumEncodedBytes
    }

    /// Owner-approved R4 export policy: 15 seconds, 10 fps, 960 px, 10 MB.
    public static let docShotR4 = GIFProfile(
        maximumDuration: 15,
        framesPerSecond: 10,
        maximumLongEdge: 960,
        maximumEncodedBytes: 10 * 1_000_000
    )

    public func supports(_ recording: TemporaryRecording) -> Bool {
        recording.isPlayable && recording.duration <= maximumDuration
    }
}
