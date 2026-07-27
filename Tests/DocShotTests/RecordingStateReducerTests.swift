import Testing
import Foundation
import CoreGraphics
@testable import DocShot

/// The recording transition table, including every cancel, failure, and late-callback cleanup
/// path. These run in both toolchains: no stream, no permission, no window server.
@Suite("RecordingStateReducer Tests")
struct RecordingStateReducerTests {

    // MARK: - Fixtures

    private static let windowTarget = RecordingTarget.window(
        id: 42,
        boundsInCG: CGRect(x: 10, y: 20, width: 400, height: 300)
    )

    private static let regionTarget = RecordingTarget.region(
        displayID: 1,
        rectInDisplay: CGRect(x: 0, y: 0, width: 200, height: 150),
        outputSize: CGSize(width: 400, height: 300)
    )

    private static func recording(
        _ name: String = "clip",
        duration: TimeInterval = 3
    ) -> TemporaryRecording {
        TemporaryRecording(
            url: URL(fileURLWithPath: "/tmp/DocShot-Recordings/\(name).mp4"),
            duration: duration,
            pixelSize: CGSize(width: 400, height: 300),
            hasAudio: false,
            createdAt: Date(timeIntervalSince1970: 0)
        )
    }

    /// Drives a reducer to `.recording`, returning the live session.
    @discardableResult
    private func advanceToRecording(
        _ reducer: inout RecordingStateReducer,
        target: RecordingTarget = RecordingStateReducerTests.windowTarget
    ) -> RecordingSessionID {
        _ = reducer.apply(.requestRecording)
        let session = reducer.generation
        _ = reducer.apply(.permissionResolved(granted: true, session: session))
        _ = reducer.apply(.targetSelected(target, session: session))
        _ = reducer.apply(.confirmRecord)
        _ = reducer.apply(.sessionStarted(at: Date(timeIntervalSince1970: 100), session: session))
        return session
    }

    // MARK: - Start and permission

    @Test("A recording request preflights permission and creates no selection UI yet")
    func testRequestPreflightsPermissionFirst() {
        var reducer = RecordingStateReducer()

        let effects = reducer.apply(.requestRecording)

        #expect(reducer.state == .selecting)
        #expect(effects == [.preflightPermission(session: reducer.generation)])
        #expect(effects.hasBeginSelection == false, "Overlays must not exist before permission is resolved")
    }

    @Test("Selection overlays are created only after permission is granted")
    func testOverlaysFollowGrantedPermission() {
        var reducer = RecordingStateReducer()
        _ = reducer.apply(.requestRecording)
        let session = reducer.generation

        let effects = reducer.apply(.permissionResolved(granted: true, session: session))

        #expect(effects == [.beginSelection(session: session)])
        #expect(reducer.state == .selecting)
    }

    @Test("Denied permission never begins a selection")
    func testDeniedPermissionNeverBeginsSelection() {
        var reducer = RecordingStateReducer()
        _ = reducer.apply(.requestRecording)
        let session = reducer.generation

        let effects = reducer.apply(.permissionResolved(granted: false, session: session))

        #expect(reducer.state == .permissionRequired)
        #expect(effects == [.presentPermissionRequired])
        #expect(effects.hasBeginSelection == false)
    }

    @Test("A second recording request while busy is refused")
    func testDuplicateRequestRejected() {
        var reducer = RecordingStateReducer()
        _ = reducer.apply(.requestRecording)
        let stateAfterFirst = reducer.state
        let generationAfterFirst = reducer.generation

        let effects = reducer.apply(.requestRecording)

        #expect(effects == [.rejectDuplicateRequest])
        #expect(reducer.state == stateAfterFirst)
        #expect(reducer.generation == generationAfterFirst)
    }

    // MARK: - Selection and confirmation

    @Test("Selecting a target waits for confirmation and starts nothing")
    func testTargetSelectionAwaitsConfirmation() {
        var reducer = RecordingStateReducer()
        _ = reducer.apply(.requestRecording)
        let session = reducer.generation
        _ = reducer.apply(.permissionResolved(granted: true, session: session))

        let effects = reducer.apply(.targetSelected(Self.regionTarget, session: session))

        #expect(reducer.state == .awaitingConfirmation(Self.regionTarget))
        #expect(effects.isEmpty)
        #expect(effects.hasStartSession == false, "No stream may begin before Record")
    }

    @Test("A rejected region keeps the selection open and explains why")
    func testRejectedTargetKeepsSelectionOpen() {
        var reducer = RecordingStateReducer()
        _ = reducer.apply(.requestRecording)
        let session = reducer.generation
        _ = reducer.apply(.permissionResolved(granted: true, session: session))

        let effects = reducer.apply(.targetRejected(.spansMultipleDisplays, session: session))

        #expect(reducer.state == .selecting)
        #expect(effects == [.presentTargetRejection(.spansMultipleDisplays)])
    }

    @Test("Escape during selection creates no temporary file and no session")
    func testCancelDuringSelectionCreatesNothing() {
        var reducer = RecordingStateReducer()
        _ = reducer.apply(.requestRecording)
        let session = reducer.generation
        _ = reducer.apply(.permissionResolved(granted: true, session: session))

        let effects = reducer.apply(.selectionCancelled)

        #expect(reducer.state == .idle)
        #expect(effects == [.closeOverlays])
        #expect(effects.hasStartSession == false)
        #expect(effects.removedURLs.isEmpty)
        #expect(reducer.generation != session, "Cancelling must invalidate the session")
    }

    @Test("Cancel at the confirmation step never starts a stream")
    func testCancelAtConfirmationNeverStarts() {
        var reducer = RecordingStateReducer()
        _ = reducer.apply(.requestRecording)
        let session = reducer.generation
        _ = reducer.apply(.permissionResolved(granted: true, session: session))
        _ = reducer.apply(.targetSelected(Self.windowTarget, session: session))

        let effects = reducer.apply(.confirmCancel)

        #expect(reducer.state == .idle)
        #expect(effects == [.closeOverlays])
        #expect(effects.hasStartSession == false)
        #expect(effects.removedURLs.isEmpty)
    }

    @Test("Record closes the overlays before the stream opens")
    func testConfirmRecordClosesOverlaysFirst() {
        var reducer = RecordingStateReducer()
        _ = reducer.apply(.requestRecording)
        let session = reducer.generation
        _ = reducer.apply(.permissionResolved(granted: true, session: session))
        _ = reducer.apply(.targetSelected(Self.windowTarget, session: session))

        let effects = reducer.apply(.confirmRecord)

        #expect(reducer.state == .starting(Self.windowTarget))
        #expect(effects == [.closeOverlays, .startSession(Self.windowTarget, session: session)])
    }

    // MARK: - Running

    @Test("A started stream moves to recording with the reported start time")
    func testSessionStartedRecords() {
        var reducer = RecordingStateReducer()
        _ = reducer.apply(.requestRecording)
        let session = reducer.generation
        _ = reducer.apply(.permissionResolved(granted: true, session: session))
        _ = reducer.apply(.targetSelected(Self.windowTarget, session: session))
        _ = reducer.apply(.confirmRecord)

        let startedAt = Date(timeIntervalSince1970: 1_000)
        let effects = reducer.apply(.sessionStarted(at: startedAt, session: session))

        #expect(reducer.state == .recording(Self.windowTarget, startedAt: startedAt))
        #expect(effects.isEmpty)
    }

    @Test("Stop pressed while the stream is still opening is honoured once it opens")
    func testStopWhileStartingIsQueued() {
        var reducer = RecordingStateReducer()
        _ = reducer.apply(.requestRecording)
        let session = reducer.generation
        _ = reducer.apply(.permissionResolved(granted: true, session: session))
        _ = reducer.apply(.targetSelected(Self.windowTarget, session: session))
        _ = reducer.apply(.confirmRecord)

        let queued = reducer.apply(.stopRequested)
        #expect(queued.isEmpty, "A half-open session must not be torn down mid-start")
        #expect(reducer.state == .starting(Self.windowTarget))

        let effects = reducer.apply(.sessionStarted(at: Date(), session: session))

        #expect(reducer.state == .stopping)
        #expect(effects == [.stopSession(session: session)])
    }

    @Test("Repeated Stop requests produce exactly one stop")
    func testRepeatedStopIsSingleFlight() {
        var reducer = RecordingStateReducer()
        let session = advanceToRecording(&reducer)

        let first = reducer.apply(.stopRequested)
        let second = reducer.apply(.stopRequested)
        let third = reducer.apply(.stopRequested)

        #expect(first == [.stopSession(session: session)])
        #expect(second.isEmpty)
        #expect(third.isEmpty)
        #expect(reducer.state == .stopping)
    }

    @Test("Stopping produces an output choice and never a save")
    func testStopProducesOutputChoiceOnly() {
        var reducer = RecordingStateReducer()
        let session = advanceToRecording(&reducer)
        _ = reducer.apply(.stopRequested)

        let clip = Self.recording()
        let effects = reducer.apply(.sessionStopped(clip, session: session))

        #expect(reducer.state == .awaitingOutput(clip))
        #expect(effects == [.presentOutputChoice(clip)])
        #expect(effects.hasSavePanel == false, "Stop must never open a save panel on its own")
        #expect(effects.removedURLs.isEmpty)
    }

    // MARK: - Failure paths

    @Test("A start failure cancels the session and deletes its temporary file")
    func testStartFailureCleansUp() {
        var reducer = RecordingStateReducer()
        _ = reducer.apply(.requestRecording)
        let session = reducer.generation
        _ = reducer.apply(.permissionResolved(granted: true, session: session))
        _ = reducer.apply(.targetSelected(Self.windowTarget, session: session))
        _ = reducer.apply(.confirmRecord)

        let url = URL(fileURLWithPath: "/tmp/DocShot-Recordings/partial.mp4")
        let failure = RecordingFailure.streamStart("stream refused")
        let effects = reducer.apply(.sessionStartFailed(failure, url: url, session: session))

        #expect(reducer.state == .failed(failure))
        #expect(effects == [
            .cancelSession(session: session),
            .removeTemporary(url),
            .presentFailure(failure)
        ])
        #expect(reducer.generation != session)
    }

    @Test("A stop failure deletes the untrustworthy file")
    func testStopFailureCleansUp() {
        var reducer = RecordingStateReducer()
        let session = advanceToRecording(&reducer)
        _ = reducer.apply(.stopRequested)

        let url = URL(fileURLWithPath: "/tmp/DocShot-Recordings/half.mp4")
        let failure = RecordingFailure.stopFailed("writer refused to finish")
        let effects = reducer.apply(.sessionStopFailed(failure, url: url, session: session))

        #expect(reducer.state == .failed(failure))
        #expect(effects.removedURLs == [url])
        #expect(effects.contains(.cancelSession(session: session)))
    }

    @Test("A stream that stops on its own is cleaned up from every live state")
    func testStreamFailureFromEveryLiveState() {
        let url = URL(fileURLWithPath: "/tmp/DocShot-Recordings/interrupted.mp4")
        let failure = RecordingFailure.streamInterrupted("display disconnected")

        // While starting.
        var starting = RecordingStateReducer()
        _ = starting.apply(.requestRecording)
        let startingSession = starting.generation
        _ = starting.apply(.permissionResolved(granted: true, session: startingSession))
        _ = starting.apply(.targetSelected(Self.windowTarget, session: startingSession))
        _ = starting.apply(.confirmRecord)
        let startingEffects = starting.apply(.streamFailed(failure, url: url, session: startingSession))
        #expect(starting.state == .failed(failure))
        #expect(startingEffects.removedURLs == [url])

        // While recording.
        var recording = RecordingStateReducer()
        let recordingSession = advanceToRecording(&recording)
        let recordingEffects = recording.apply(.streamFailed(failure, url: url, session: recordingSession))
        #expect(recording.state == .failed(failure))
        #expect(recordingEffects.removedURLs == [url])

        // While stopping.
        var stopping = RecordingStateReducer()
        let stoppingSession = advanceToRecording(&stopping)
        _ = stopping.apply(.stopRequested)
        let stoppingEffects = stopping.apply(.streamFailed(failure, url: url, session: stoppingSession))
        #expect(stopping.state == .failed(failure))
        #expect(stoppingEffects.removedURLs == [url])
    }

    @Test("Acknowledging a failure returns to idle")
    func testFailureAcknowledgementReturnsToIdle() {
        var reducer = RecordingStateReducer()
        let session = advanceToRecording(&reducer)
        _ = reducer.apply(.streamFailed(.streamInterrupted("gone"), url: nil, session: session))

        let effects = reducer.apply(.failureAcknowledged)

        #expect(reducer.state == .idle)
        #expect(effects == [.closeOverlays])
    }

    // MARK: - Late callbacks

    @Test("A late stop result changes nothing but still deletes its file")
    func testLateStopResultIsDroppedAndCleanedUp() {
        var reducer = RecordingStateReducer()
        let session = advanceToRecording(&reducer)
        _ = reducer.apply(.stopRequested)
        _ = reducer.apply(.sessionStopped(Self.recording("first"), session: session))
        _ = reducer.apply(.discardRequested)

        let stateBefore = reducer.state
        let late = Self.recording("late")
        let effects = reducer.apply(.sessionStopped(late, session: session))

        #expect(reducer.state == stateBefore)
        #expect(reducer.state == .idle)
        #expect(effects == [.removeTemporary(late.url)], "A late clip must never be stranded on disk")
    }

    @Test("A late stream failure deletes its file without reporting an error")
    func testLateStreamFailureIsDroppedAndCleanedUp() {
        var reducer = RecordingStateReducer()
        let session = advanceToRecording(&reducer)
        _ = reducer.apply(.selectionCancelled) // no-op while recording
        _ = reducer.apply(.stopRequested)
        _ = reducer.apply(.sessionStopped(Self.recording(), session: session))
        _ = reducer.apply(.discardRequested)

        let url = URL(fileURLWithPath: "/tmp/DocShot-Recordings/orphan.mp4")
        let effects = reducer.apply(.streamFailed(.streamInterrupted("late"), url: url, session: session))

        #expect(reducer.state == .idle)
        #expect(effects == [.removeTemporary(url)])
    }

    @Test("A late start result cannot resurrect a cancelled session")
    func testLateStartResultCannotResurrectSession() {
        var reducer = RecordingStateReducer()
        _ = reducer.apply(.requestRecording)
        let session = reducer.generation
        _ = reducer.apply(.permissionResolved(granted: true, session: session))
        _ = reducer.apply(.selectionCancelled)

        let effects = reducer.apply(.sessionStarted(at: Date(), session: session))

        #expect(reducer.state == .idle)
        #expect(effects.isEmpty)
    }

    @Test("A late permission result cannot reopen a dismissed selection")
    func testLatePermissionResultIsIgnored() {
        var reducer = RecordingStateReducer()
        _ = reducer.apply(.requestRecording)
        let session = reducer.generation
        _ = reducer.apply(.selectionCancelled)

        let effects = reducer.apply(.permissionResolved(granted: true, session: session))

        #expect(reducer.state == .idle)
        #expect(effects.isEmpty)
        #expect(effects.hasBeginSelection == false)
    }

    // MARK: - Output

    @Test("The save panel opens only on an explicit save request, and only once")
    func testSavePanelRequiresExplicitRequest() {
        var reducer = RecordingStateReducer()
        let session = advanceToRecording(&reducer)
        _ = reducer.apply(.stopRequested)
        let clip = Self.recording()
        _ = reducer.apply(.sessionStopped(clip, session: session))

        let first = reducer.apply(.saveRequested)
        let second = reducer.apply(.saveRequested)

        #expect(first == [.presentSavePanel(clip)])
        #expect(second.isEmpty, "A second panel must not open over the first")
        #expect(reducer.state == .awaitingOutput(clip))
    }

    @Test("A saved recording ends the session")
    func testSaveCompletesSession() {
        var reducer = RecordingStateReducer()
        let session = advanceToRecording(&reducer)
        _ = reducer.apply(.stopRequested)
        let clip = Self.recording()
        _ = reducer.apply(.sessionStopped(clip, session: session))
        _ = reducer.apply(.saveRequested)

        let destination = URL(fileURLWithPath: "/Users/someone/Movies/clip.mp4")
        let effects = reducer.apply(.saveCompleted(.saved(destination)))

        #expect(reducer.state == .idle)
        #expect(effects == [.removeTemporary(clip.url)])
    }

    @Test("A cancelled save panel keeps the recording available and deletes nothing")
    func testCancelledSaveKeepsRecording() {
        var reducer = RecordingStateReducer()
        let session = advanceToRecording(&reducer)
        _ = reducer.apply(.stopRequested)
        let clip = Self.recording()
        _ = reducer.apply(.sessionStopped(clip, session: session))
        _ = reducer.apply(.saveRequested)

        let effects = reducer.apply(.saveCompleted(.cancelled))

        #expect(reducer.state == .awaitingOutput(clip))
        #expect(effects == [.presentOutputChoice(clip)])
        #expect(effects.removedURLs.isEmpty, "Cancelling the panel is not a discard")
    }

    @Test("A failed save reports the error and keeps the recording for a retry")
    func testFailedSaveKeepsRecording() {
        var reducer = RecordingStateReducer()
        let session = advanceToRecording(&reducer)
        _ = reducer.apply(.stopRequested)
        let clip = Self.recording()
        _ = reducer.apply(.sessionStopped(clip, session: session))
        _ = reducer.apply(.saveRequested)

        let effects = reducer.apply(.saveCompleted(.failed("disk full")))

        #expect(reducer.state == .awaitingOutput(clip))
        #expect(effects == [
            .presentFailure(.outputSave("disk full")),
            .presentOutputChoice(clip)
        ])
        #expect(effects.removedURLs.isEmpty)

        // The panel can be reopened after a failure.
        #expect(reducer.apply(.saveRequested) == [.presentSavePanel(clip)])
    }

    @Test("Discard deletes the temporary recording and touches nothing else")
    func testDiscardDeletesTemporaryRecording() {
        var reducer = RecordingStateReducer()
        let session = advanceToRecording(&reducer)
        _ = reducer.apply(.stopRequested)
        let clip = Self.recording()
        _ = reducer.apply(.sessionStopped(clip, session: session))

        let effects = reducer.apply(.discardRequested)

        #expect(reducer.state == .idle)
        #expect(effects == [.removeTemporary(clip.url)])
    }

    // MARK: - Termination

    @Test("Quitting while recording cancels the live session")
    func testTerminateWhileRecordingCancelsSession() {
        var reducer = RecordingStateReducer()
        let session = advanceToRecording(&reducer)

        let effects = reducer.apply(.appWillTerminate)

        #expect(reducer.state == .idle)
        #expect(effects == [.cancelSession(session: session), .closeOverlays])
    }

    @Test("Quitting while a recording awaits output deletes it")
    func testTerminateWhileAwaitingOutputDeletesRecording() {
        var reducer = RecordingStateReducer()
        let session = advanceToRecording(&reducer)
        _ = reducer.apply(.stopRequested)
        let clip = Self.recording()
        _ = reducer.apply(.sessionStopped(clip, session: session))

        let effects = reducer.apply(.appWillTerminate)

        #expect(reducer.state == .idle)
        #expect(effects == [.removeTemporary(clip.url), .closeOverlays])
    }

    @Test("Quitting from idle does nothing destructive")
    func testTerminateFromIdleIsHarmless() {
        var reducer = RecordingStateReducer()

        let effects = reducer.apply(.appWillTerminate)

        #expect(reducer.state == .idle)
        #expect(effects == [.closeOverlays])
    }

    // MARK: - R1 scope

    @Test("No R1 event can reach the GIF export state")
    func testGIFExportIsUnreachableInR1() {
        let events: [RecordingEvent] = [
            .requestRecording,
            .permissionResolved(granted: true, session: .initial),
            .permissionResolved(granted: false, session: .initial),
            .targetSelected(Self.windowTarget, session: .initial),
            .targetRejected(.tooSmall, session: .initial),
            .selectionCancelled,
            .confirmRecord,
            .confirmCancel,
            .sessionStarted(at: Date(), session: .initial),
            .sessionStartFailed(.streamStart("x"), url: nil, session: .initial),
            .stopRequested,
            .sessionStopped(Self.recording(), session: .initial),
            .sessionStopFailed(.stopFailed("x"), url: nil, session: .initial),
            .streamFailed(.streamInterrupted("x"), url: nil, session: .initial),
            .saveRequested,
            .saveCompleted(.cancelled),
            .discardRequested,
            .failureAcknowledged,
            .appWillTerminate
        ]

        // Replay every event against a fresh reducer and against a live recording session.
        for event in events {
            var fresh = RecordingStateReducer()
            _ = fresh.apply(event)
            #expect(fresh.state != .exportingGIF(Self.recording()))

            var live = RecordingStateReducer()
            advanceToRecording(&live)
            _ = live.apply(event)
            if case .exportingGIF = live.state {
                Issue.record("Event \(event) reached the R4 GIF state")
            }
        }
    }

    @Test("Every terminal path removes the temporary recording exactly once")
    func testEveryTerminalPathRemovesTemporaryMediaOnce() {
        let clip = Self.recording()

        // Discard.
        var discard = RecordingStateReducer()
        let discardSession = advanceToRecording(&discard)
        _ = discard.apply(.stopRequested)
        _ = discard.apply(.sessionStopped(clip, session: discardSession))
        #expect(discard.apply(.discardRequested).removedURLs == [clip.url])

        // Save.
        var save = RecordingStateReducer()
        let saveSession = advanceToRecording(&save)
        _ = save.apply(.stopRequested)
        _ = save.apply(.sessionStopped(clip, session: saveSession))
        _ = save.apply(.saveRequested)
        let saved = save.apply(.saveCompleted(.saved(URL(fileURLWithPath: "/tmp/out.mp4"))))
        #expect(saved.removedURLs == [clip.url])

        // Terminate.
        var terminate = RecordingStateReducer()
        let terminateSession = advanceToRecording(&terminate)
        _ = terminate.apply(.stopRequested)
        _ = terminate.apply(.sessionStopped(clip, session: terminateSession))
        #expect(terminate.apply(.appWillTerminate).removedURLs == [clip.url])

        // Failure.
        var failure = RecordingStateReducer()
        let failureSession = advanceToRecording(&failure)
        let failed = failure.apply(.streamFailed(.streamInterrupted("x"), url: clip.url, session: failureSession))
        #expect(failed.removedURLs == [clip.url])
    }
}

// MARK: - Effect helpers

private extension Array where Element == RecordingEffect {
    var hasStartSession: Bool {
        contains { if case .startSession = $0 { return true } else { return false } }
    }

    var hasBeginSelection: Bool {
        contains { if case .beginSelection = $0 { return true } else { return false } }
    }

    var hasSavePanel: Bool {
        contains { if case .presentSavePanel = $0 { return true } else { return false } }
    }

    var removedURLs: [URL] {
        compactMap { if case .removeTemporary(let url) = $0 { return url } else { return nil } }
    }
}
