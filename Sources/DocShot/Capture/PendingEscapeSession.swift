import AppKit
import Foundation

/// Owns the temporary global Escape registration that covers the interval between starting a
/// capture and the selection overlay appearing.
///
/// It exists as its own type for two reasons: the register/release rules are worth stating
/// once rather than repeating at every call site, and it can be compiled into the Xcode test
/// target, which does not link the app binary.
///
/// Guarantees:
/// - **Idempotent release.** Ending a session that is already over does nothing.
/// - **Cancellation safe.** Each `begin` returns a token, and `end(token:)` releases only that
///   session. A deferred release from a superseded session can never tear down a newer one.
/// - **Single registration.** Beginning while another session is active releases the old one
///   first, so at most one Escape registration exists at a time.
@MainActor
public final class PendingEscapeSession {

    /// Identifies one pending window. Stale tokens are ignored by `end(token:)`.
    public struct Token: Equatable, Sendable {
        fileprivate let value: Int
    }

    private let handler: TemporaryEscapeHandling
    private var activeToken: Token?
    private var nextTokenValue = 0

    public init(handler: TemporaryEscapeHandling) {
        self.handler = handler
    }

    public var isActive: Bool {
        activeToken != nil
    }

    /// Starts intercepting Escape system-wide until the matching `end(token:)` or `endAll()`.
    @discardableResult
    public func begin(onEscape: @escaping @MainActor @Sendable () -> Void) -> Token {
        endAll()

        nextTokenValue += 1
        let token = Token(value: nextTokenValue)
        guard handler.registerTemporaryEscape(action: onEscape) else {
            // A failed Carbon registration must not leave the session looking active: callers
            // will still safely end this token through their normal deferred teardown.
            activeToken = nil
            return token
        }

        activeToken = token
        return token
    }

    /// Releases the registration if `token` owns the active session. Stale tokens are ignored.
    public func end(token: Token) {
        guard activeToken == token else { return }
        endAll()
    }

    /// Releases any active registration. Safe on paths where nothing was ever begun.
    public func endAll() {
        guard activeToken != nil else { return }
        activeToken = nil
        handler.unregisterTemporaryEscape()
    }
}

/// Tells an open selector that the user moved to another Space (a desktop or a full-screen
/// app), for example with a three-finger swipe. The selector's frozen picture and window list
/// belong to the Space it opened on, so it must re-read both or it captures the Space the user
/// left.
@MainActor
public final class SpaceChangeObserver {
    private let center: NotificationCenter
    private var token: NSObjectProtocol?

    public init(center: NotificationCenter = NSWorkspace.shared.notificationCenter) {
        self.center = center
    }

    public func start(_ onChange: @escaping @MainActor @Sendable () -> Void) {
        stop()
        token = center.addObserver(
            forName: NSWorkspace.activeSpaceDidChangeNotification, object: nil, queue: .main
        ) { _ in
            MainActor.assumeIsolated { onChange() }
        }
    }

    public func stop() {
        if let token { center.removeObserver(token) }
        token = nil
    }
}
