import Foundation

/// Why a recording could not start, continue, finish, or be saved.
///
/// The cases are distinguished so the UI can say something actionable, and so cleanup can tell
/// "no stream ever existed" from "a stream produced a file that must now be deleted".
public enum RecordingFailure: Error, Equatable, Sendable, LocalizedError {
    /// Screen Recording permission is not granted.
    case permissionDenied
    /// The selection could not become a valid target.
    case invalidTarget(RecordingTargetRejection)
    /// The stream could not be constructed or started. No usable media exists.
    case streamStart(String)
    /// A running stream stopped on its own: a delegate error, display change, or revoked access.
    case streamInterrupted(String)
    /// Stopping failed, so the file cannot be trusted.
    case stopFailed(String)
    /// The writer failed, produced no frames, or produced an asset that does not validate.
    case writer(String)
    /// The finished recording could not be written to the user's chosen destination.
    /// The temporary file is retained so the user can retry or discard.
    case outputSave(String)

    public var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "DocShot needs Screen Recording permission to record. Grant access in System Settings, then try again."
        case .invalidTarget(let rejection):
            return rejection.message
        case .streamStart(let detail):
            return "Recording could not start: \(detail)"
        case .streamInterrupted(let detail):
            return "Recording stopped unexpectedly: \(detail)"
        case .stopFailed(let detail):
            return "Recording could not be finished: \(detail)"
        case .writer(let detail):
            return "The recording could not be written: \(detail)"
        case .outputSave(let detail):
            return "The recording could not be saved: \(detail)"
        }
    }

    /// True when the failure left no media worth keeping, so cleanup is unconditional.
    public var discardsTemporaryMedia: Bool {
        switch self {
        case .outputSave:
            return false
        case .permissionDenied, .invalidTarget, .streamStart, .streamInterrupted, .stopFailed, .writer:
            return true
        }
    }
}
