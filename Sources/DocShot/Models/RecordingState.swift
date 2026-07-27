import Foundation

/// Identifies one recording session.
///
/// Bumped whenever a session ends by any route, so a callback that arrives after the user
/// cancelled, stopped, discarded, or quit can be recognised as stale and dropped.
public struct RecordingSessionID: Equatable, Hashable, Sendable {
    public let rawValue: Int

    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    public static let initial = RecordingSessionID(rawValue: 1)

    public func next() -> RecordingSessionID {
        RecordingSessionID(rawValue: rawValue + 1)
    }
}

/// Every state the recording subsystem can occupy.
///
/// `exportingGIF` belongs to the R4 GIF milestone and is retained here so the state type is the
/// documented one rather than a temporary subset. R1 emits no event that enters it; `RecordingStateReducer`
/// treats it as unreachable and `RecordingStateReducerTests` asserts that.
public enum RecordingState: Equatable, Sendable {
    case idle
    case permissionRequired
    /// Preparing to select: preflighting permission, then discovering windows and presenting
    /// overlays. Overlays exist only after permission has been granted.
    case selecting
    case awaitingConfirmation(RecordingTarget)
    case starting(RecordingTarget)
    case recording(RecordingTarget, startedAt: Date)
    case stopping
    case awaitingOutput(TemporaryRecording)
    case exportingGIF(TemporaryRecording)
    case failed(RecordingFailure)

    /// True while a capture activity owns the screen, so the app can refuse to start a second one.
    public var isActive: Bool {
        self != .idle
    }
}

/// Everything that can happen to a recording. The reducer is the only place that interprets them.
public enum RecordingEvent: Equatable, Sendable {
    case requestRecording
    case permissionResolved(granted: Bool, session: RecordingSessionID)
    case targetSelected(RecordingTarget, session: RecordingSessionID)
    case targetRejected(RecordingTargetRejection, session: RecordingSessionID)
    case selectionCancelled
    case confirmRecord
    case confirmCancel
    case sessionStarted(at: Date, session: RecordingSessionID)
    case sessionStartFailed(RecordingFailure, url: URL?, session: RecordingSessionID)
    case stopRequested
    case sessionStopped(TemporaryRecording, session: RecordingSessionID)
    case sessionStopFailed(RecordingFailure, url: URL?, session: RecordingSessionID)
    case streamFailed(RecordingFailure, url: URL?, session: RecordingSessionID)
    case saveRequested
    case saveCompleted(SaveResult)
    case discardRequested
    case failureAcknowledged
    case appWillTerminate

    /// The session an event belongs to, for events that can arrive late.
    public var session: RecordingSessionID? {
        switch self {
        case .permissionResolved(_, let session),
             .targetSelected(_, let session),
             .targetRejected(_, let session),
             .sessionStarted(_, let session),
             .sessionStartFailed(_, _, let session),
             .sessionStopped(_, let session),
             .sessionStopFailed(_, _, let session),
             .streamFailed(_, _, let session):
            return session
        case .requestRecording, .selectionCancelled, .confirmRecord, .confirmCancel,
             .stopRequested, .saveRequested, .saveCompleted, .discardRequested,
             .failureAcknowledged, .appWillTerminate:
            return nil
        }
    }

    /// Temporary media this event reports, whether or not the event is still current. A late
    /// event is dropped, but anything it created is still deleted.
    public var temporaryURL: URL? {
        switch self {
        case .sessionStopped(let recording, _):
            return recording.url
        case .sessionStartFailed(_, let url, _),
             .sessionStopFailed(_, let url, _),
             .streamFailed(_, let url, _):
            return url
        default:
            return nil
        }
    }
}

/// Work the coordinator performs on the reducer's instruction. Effects are pure data so the whole
/// transition table — including every cleanup path — is assertable without AppKit or a stream.
public enum RecordingEffect: Equatable, Sendable {
    /// Check Screen Recording access. Always precedes `beginSelection`; no overlay exists yet.
    case preflightPermission(session: RecordingSessionID)
    case presentPermissionRequired
    /// Discover eligible windows and present the selection overlays.
    case beginSelection(session: RecordingSessionID)
    case closeOverlays
    case presentTargetRejection(RecordingTargetRejection)
    case startSession(RecordingTarget, session: RecordingSessionID)
    case stopSession(session: RecordingSessionID)
    case cancelSession(session: RecordingSessionID)
    case removeTemporary(URL)
    /// Ask the user to Save or Discard. Never saves anything on its own.
    case presentOutputChoice(TemporaryRecording)
    case presentSavePanel(TemporaryRecording)
    case presentFailure(RecordingFailure)
    /// A capture activity is already running; the request was refused.
    case rejectDuplicateRequest
}
