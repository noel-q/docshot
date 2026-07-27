import Foundation

/// The whole recording transition table, as a deterministic value.
///
/// Every rule that matters for correctness lives here rather than in the coordinator: duplicate
/// start and stop requests are refused, late callbacks from an ended session are dropped, and
/// each terminal path emits the cleanup effects that remove temporary media. That keeps those
/// guarantees testable in both toolchains, with no stream, no permission, and no window server.
public struct RecordingStateReducer {
    public private(set) var state: RecordingState
    /// The session events must belong to in order to be acted on.
    public private(set) var generation: RecordingSessionID

    /// Set when Stop arrives while the stream is still opening. Tearing down a half-open session
    /// races the start; instead the stop is honoured the moment the stream reports it started.
    private var stopRequestedWhileStarting = false

    /// Guards against a second save panel while one is already open.
    private var isSavePanelOpen = false

    public init(
        state: RecordingState = .idle,
        generation: RecordingSessionID = .initial
    ) {
        self.state = state
        self.generation = generation
    }

    public mutating func apply(_ event: RecordingEvent) -> [RecordingEffect] {
        // A callback from a session the user already ended. It must not move the state machine —
        // but anything it produced is still deleted, which is what keeps a late stop from
        // stranding a temporary file.
        if let eventSession = event.session, eventSession != generation {
            return event.temporaryURL.map { [.removeTemporary($0)] } ?? []
        }

        switch event {
        case .requestRecording:
            guard state == .idle else { return [.rejectDuplicateRequest] }
            generation = generation.next()
            state = .selecting
            return [.preflightPermission(session: generation)]

        case .permissionResolved(let granted, _):
            guard state == .selecting else { return [] }
            guard granted else {
                state = .permissionRequired
                return [.presentPermissionRequired]
            }
            // Overlays are created here and nowhere else, so no selection UI can precede a
            // granted permission.
            return [.beginSelection(session: generation)]

        case .targetSelected(let target, _):
            guard state == .selecting else { return [] }
            state = .awaitingConfirmation(target)
            return []

        case .targetRejected(let rejection, _):
            guard state == .selecting else { return [] }
            // Selection stays open: the user retries rather than losing the session.
            return [.presentTargetRejection(rejection)]

        case .selectionCancelled:
            switch state {
            case .selecting, .awaitingConfirmation, .permissionRequired:
                generation = generation.next()
                state = .idle
                return [.closeOverlays]
            case .idle, .starting, .recording, .stopping, .awaitingOutput, .exportingGIF, .failed:
                return []
            }

        case .confirmRecord:
            guard case .awaitingConfirmation(let target) = state else { return [] }
            state = .starting(target)
            // Overlays close before the stream opens, so DocShot's own selection UI cannot appear
            // in the recorded pixels.
            return [.closeOverlays, .startSession(target, session: generation)]

        case .confirmCancel:
            guard case .awaitingConfirmation = state else { return [] }
            generation = generation.next()
            state = .idle
            // No stream was started and no temporary file was minted: nothing to clean up.
            return [.closeOverlays]

        case .sessionStarted(let startedAt, _):
            guard case .starting(let target) = state else { return [] }
            if stopRequestedWhileStarting {
                stopRequestedWhileStarting = false
                state = .stopping
                return [.stopSession(session: generation)]
            }
            state = .recording(target, startedAt: startedAt)
            return []

        case .sessionStartFailed(let failure, let url, _):
            guard case .starting = state else { return [] }
            return endSession(failure: failure, temporaryURL: url)

        case .stopRequested:
            switch state {
            case .starting:
                stopRequestedWhileStarting = true
                return []
            case .recording:
                state = .stopping
                return [.stopSession(session: generation)]
            case .idle, .permissionRequired, .selecting, .awaitingConfirmation, .stopping,
                 .awaitingOutput, .exportingGIF, .failed:
                // Includes the repeated-Stop case: stopping is single-flight.
                return []
            }

        case .sessionStopped(let recording, _):
            guard state == .stopping else { return [] }
            state = .awaitingOutput(recording)
            // Nothing is written outside temporary storage until the user chooses.
            return [.presentOutputChoice(recording)]

        case .sessionStopFailed(let failure, let url, _):
            guard state == .stopping else { return [] }
            return endSession(failure: failure, temporaryURL: url)

        case .streamFailed(let failure, let url, _):
            switch state {
            case .starting, .recording, .stopping:
                return endSession(failure: failure, temporaryURL: url)
            case .idle, .permissionRequired, .selecting, .awaitingConfirmation, .awaitingOutput,
                 .exportingGIF, .failed:
                // The session is already over; only its media still matters.
                return url.map { [.removeTemporary($0)] } ?? []
            }

        case .saveRequested:
            guard case .awaitingOutput(let recording) = state, !isSavePanelOpen else { return [] }
            isSavePanelOpen = true
            return [.presentSavePanel(recording)]

        case .saveCompleted(let result):
            isSavePanelOpen = false
            guard case .awaitingOutput(let recording) = state else { return [] }
            switch result {
            case .saved:
                generation = generation.next()
                state = .idle
                // The move already consumed the temporary file; removal is a no-op that keeps the
                // "every session ends with a removal" invariant true on every path.
                return [.removeTemporary(recording.url)]
            case .cancelled:
                // A cancelled panel is not a discard: the recording is still the user's to keep.
                return [.presentOutputChoice(recording)]
            case .failed(let message):
                return [.presentFailure(.outputSave(message)), .presentOutputChoice(recording)]
            }

        case .discardRequested:
            guard case .awaitingOutput(let recording) = state else { return [] }
            generation = generation.next()
            state = .idle
            return [.removeTemporary(recording.url)]

        case .failureAcknowledged:
            guard case .failed = state else { return [] }
            state = .idle
            return [.closeOverlays]

        case .appWillTerminate:
            let ended = generation
            generation = generation.next()
            stopRequestedWhileStarting = false
            isSavePanelOpen = false

            var effects: [RecordingEffect] = []
            switch state {
            case .starting, .recording, .stopping:
                // The live session owns its file; cancelling it removes the media. The coordinator
                // also sweeps its temporary directory, so a session that never reported its URL
                // cannot leave an orphan behind.
                effects.append(.cancelSession(session: ended))
            case .awaitingOutput(let recording), .exportingGIF(let recording):
                effects.append(.removeTemporary(recording.url))
            case .idle, .permissionRequired, .selecting, .awaitingConfirmation, .failed:
                break
            }
            effects.append(.closeOverlays)
            state = .idle
            return effects
        }
    }

    /// Ends the live session on a failure path: invalidate the generation so nothing it emits
    /// later is honoured, cancel it, delete its media, and report the failure.
    private mutating func endSession(
        failure: RecordingFailure,
        temporaryURL: URL?
    ) -> [RecordingEffect] {
        let ended = generation
        generation = generation.next()
        stopRequestedWhileStarting = false
        state = .failed(failure)

        var effects: [RecordingEffect] = [.cancelSession(session: ended)]
        if let temporaryURL {
            effects.append(.removeTemporary(temporaryURL))
        }
        effects.append(.presentFailure(failure))
        return effects
    }
}
