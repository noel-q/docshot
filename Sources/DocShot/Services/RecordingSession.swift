import Foundation

/// One live capture-and-write session: a single stream, a single writer, and a single temporary
/// file. The coordinator owns at most one at a time and never reuses one after it ends.
///
/// The session is given the output URL rather than minting its own. That way the coordinator
/// always knows which file a session owns, so cleanup after a start failure, a stream error, or
/// a late callback never depends on the session surviving long enough to clean up after itself.
public protocol RecordingSession: Sendable {
    /// Opens the stream and begins writing. Throws `RecordingFailure` if nothing usable started.
    func start(target: RecordingTarget, options: RecordingOptions, outputURL: URL) async throws

    /// Stops the stream, finishes the file, and validates it. Single-flight: a second call while
    /// one is in progress throws rather than tearing the writer down twice.
    func stop() async throws -> TemporaryRecording

    /// Abandons the session and removes its partial media. Safe to call repeatedly and from any
    /// terminal path, including app termination.
    func cancel() async
}

public protocol RecordingSessionFactory: Sendable {
    /// - Parameter onFailure: called when the stream stops on its own — a delegate error, a
    ///   display change, or revoked permission. Never called as a result of `stop()` or `cancel()`.
    func makeSession(
        onFailure: @escaping @Sendable (RecordingFailure) -> Void
    ) -> any RecordingSession
}
