import Testing
import Foundation
import AppKit
@testable import DocShot

/// Records the temporary-escape lifecycle without touching Carbon or the real system hotkey.
@MainActor
private final class SpyEscapeHandler: TemporaryEscapeHandling {
    var shouldRegister = true
    private(set) var registerCount = 0
    private(set) var unregisterCount = 0
    private(set) var isTemporaryEscapeRegistered = false
    private var action: (@MainActor @Sendable () -> Void)?

    @discardableResult
    func registerTemporaryEscape(action: @escaping @MainActor @Sendable () -> Void) -> Bool {
        registerCount += 1
        guard shouldRegister else { return false }
        self.action = action
        isTemporaryEscapeRegistered = true
        return true
    }

    func unregisterTemporaryEscape() {
        unregisterCount += 1
        action = nil
        isTemporaryEscapeRegistered = false
    }

    /// Simulates the user pressing Escape while a snapshot is still pending.
    func fire() {
        action?()
    }
}

@Suite("PendingEscapeSession Tests")
struct PendingEscapeSessionTests {

    @Test("Nothing is intercepted until a capture begins a session")
    @MainActor
    func testInactiveUntilBegun() {
        let spy = SpyEscapeHandler()
        let session = PendingEscapeSession(handler: spy)

        #expect(session.isActive == false)
        #expect(spy.registerCount == 0)
        #expect(spy.isTemporaryEscapeRegistered == false)
    }

    @Test("Beginning registers exactly once and ending releases exactly once")
    @MainActor
    func testBeginAndEnd() {
        let spy = SpyEscapeHandler()
        let session = PendingEscapeSession(handler: spy)

        let token = session.begin { }
        #expect(session.isActive)
        #expect(spy.registerCount == 1)
        #expect(spy.isTemporaryEscapeRegistered)

        session.end(token: token)
        #expect(session.isActive == false)
        #expect(spy.unregisterCount == 1)
        #expect(spy.isTemporaryEscapeRegistered == false)
    }

    @Test("A failed registration leaves no active session or Escape action")
    @MainActor
    func testFailedRegistrationStaysInactive() {
        let spy = SpyEscapeHandler()
        spy.shouldRegister = false
        let session = PendingEscapeSession(handler: spy)
        var cancelCount = 0

        let token = session.begin { cancelCount += 1 }

        #expect(spy.registerCount == 1)
        #expect(session.isActive == false)
        #expect(spy.isTemporaryEscapeRegistered == false)

        spy.fire()
        session.end(token: token)
        session.endAll()
        #expect(cancelCount == 0)
        #expect(spy.unregisterCount == 0)
    }

    @Test("Ending is idempotent on paths where the session is already over")
    @MainActor
    func testEndIsIdempotent() {
        let spy = SpyEscapeHandler()
        let session = PendingEscapeSession(handler: spy)

        let token = session.begin { }
        session.end(token: token)
        session.end(token: token)
        session.endAll()
        session.endAll()

        #expect(session.isActive == false)
        #expect(spy.unregisterCount == 1, "Repeated releases must not churn the handler")
    }

    @Test("Ending a session that never began does nothing")
    @MainActor
    func testEndWithoutBeginDoesNothing() {
        let spy = SpyEscapeHandler()
        let session = PendingEscapeSession(handler: spy)

        session.endAll()

        #expect(spy.unregisterCount == 0)
        #expect(spy.registerCount == 0)
        #expect(session.isActive == false)
    }

    @Test("A stale token cannot release a newer session")
    @MainActor
    func testStaleTokenCannotReleaseNewerSession() {
        let spy = SpyEscapeHandler()
        let session = PendingEscapeSession(handler: spy)

        // First pending window, then a cancel-and-restart before its deferred release runs.
        let firstToken = session.begin { }
        let secondToken = session.begin { }

        // The superseded session's deferred release must not disarm the live one.
        session.end(token: firstToken)

        #expect(session.isActive, "A stale token released a newer session's registration")
        #expect(spy.isTemporaryEscapeRegistered)

        session.end(token: secondToken)
        #expect(session.isActive == false)
        #expect(spy.isTemporaryEscapeRegistered == false)
    }

    @Test("Beginning while active replaces the registration rather than stacking it")
    @MainActor
    func testBeginReplacesActiveRegistration() {
        let spy = SpyEscapeHandler()
        let session = PendingEscapeSession(handler: spy)

        session.begin { }
        session.begin { }

        // Two begins: the first was released before the second registered.
        #expect(spy.registerCount == 2)
        #expect(spy.unregisterCount == 1)
        #expect(session.isActive)

        session.endAll()
        #expect(spy.unregisterCount == 2)
        #expect(session.isActive == false)
    }

    @Test("A failed replacement registration leaves no active registration behind")
    @MainActor
    func testFailedReplacementLeavesNothingRegistered() {
        let spy = SpyEscapeHandler()
        let session = PendingEscapeSession(handler: spy)
        var firstFired = 0
        var secondFired = 0

        let firstToken = session.begin { firstFired += 1 }
        #expect(session.isActive)

        // Beginning releases the live registration before registering the replacement, so a
        // failure here must leave the session inactive rather than still holding the old one.
        spy.shouldRegister = false
        let secondToken = session.begin { secondFired += 1 }

        #expect(spy.registerCount == 2)
        #expect(spy.unregisterCount == 1, "The superseded registration must be released once")
        #expect(session.isActive == false)
        #expect(spy.isTemporaryEscapeRegistered == false)

        // Neither action may survive: Escape belongs to the frontmost app again.
        spy.fire()
        #expect(firstFired == 0)
        #expect(secondFired == 0)

        // Both callers still run their deferred teardown; neither may churn the handler.
        session.end(token: firstToken)
        session.end(token: secondToken)
        session.endAll()
        #expect(spy.unregisterCount == 1)
        #expect(session.isActive == false)
    }

    @Test("Escape fires the pending session's action, and never after release")
    @MainActor
    func testEscapeActionFiresOnlyWhileActive() {
        let spy = SpyEscapeHandler()
        let session = PendingEscapeSession(handler: spy)
        var cancelCount = 0

        let token = session.begin { cancelCount += 1 }
        spy.fire()
        #expect(cancelCount == 1)

        session.end(token: token)
        spy.fire()
        #expect(cancelCount == 1, "A released registration must not still fire")
    }

    @Test("Only the newest session's action fires after a restart")
    @MainActor
    func testNewestActionWins() {
        let spy = SpyEscapeHandler()
        let session = PendingEscapeSession(handler: spy)
        var firstFired = 0
        var secondFired = 0

        session.begin { firstFired += 1 }
        session.begin { secondFired += 1 }
        spy.fire()

        #expect(firstFired == 0)
        #expect(secondFired == 1)

        session.endAll()
    }
}

@Suite("Temporary Escape Hotkey Registration Tests", .serialized)
struct TemporaryEscapeHotkeyTests {

    @Test("Nothing is registered until a capture asks for it")
    @MainActor
    func testInitiallyUnregistered() {
        let service = HotkeyService.shared
        service.unregisterTemporaryEscape()

        #expect(service.isTemporaryEscapeRegistered == false)
    }

    @Test("Registering then releasing leaves no system-wide Escape interception")
    @MainActor
    func testRegisterThenUnregisterLeavesNothingBehind() {
        let service = HotkeyService.shared

        let didRegister = service.registerTemporaryEscape { }
        if didRegister {
            // Only assert the positive case when the environment allowed registration; a
            // headless test process may legitimately refuse it.
            #expect(service.isTemporaryEscapeRegistered)
        }

        service.unregisterTemporaryEscape()

        #expect(service.isTemporaryEscapeRegistered == false,
                "Escape must never stay intercepted after the pending window closes")
    }

    @Test("Releasing is safe on paths where nothing was ever registered")
    @MainActor
    func testUnregisterIsIdempotent() {
        let service = HotkeyService.shared

        service.unregisterTemporaryEscape()
        service.unregisterTemporaryEscape()
        service.unregisterTemporaryEscape()

        #expect(service.isTemporaryEscapeRegistered == false)
    }

    @Test("Registering twice still releases completely with one call")
    @MainActor
    func testDoubleRegistrationReleasesCleanly() {
        let service = HotkeyService.shared

        service.registerTemporaryEscape { }
        service.registerTemporaryEscape { }
        service.unregisterTemporaryEscape()

        #expect(service.isTemporaryEscapeRegistered == false)
    }

    @Test("The temporary registration never disturbs the user's capture shortcut")
    @MainActor
    func testCaptureShortcutIsUntouched() {
        let service = HotkeyService.shared
        let presetBefore = service.currentPreset

        service.registerTemporaryEscape { }
        #expect(service.currentPreset == presetBefore)

        service.unregisterTemporaryEscape()
        #expect(service.currentPreset == presetBefore)
        #expect(service.isTemporaryEscapeRegistered == false)
    }
}

// The Xcode test target compiles a subset of app sources and does not link the app binary
// (no TEST_HOST/BUNDLE_LOADER), so `CaptureCoordinator` has no symbols to link against there.
// These coordinator-level paths therefore run under `swift test`, where the whole module is
// available. The same guarantees are covered in both toolchains by PendingEscapeSessionTests.
#if SWIFT_PACKAGE
@Suite("CaptureCoordinator Escape Lifecycle Tests", .serialized)
struct CaptureCoordinatorEscapeLifecycleTests {

    @Test("Cancelling a capture releases the temporary Escape registration")
    @MainActor
    func testCancelCaptureReleasesRegistration() {
        let coordinator = CaptureCoordinator.shared
        let originalSession = coordinator.escapeSession
        let spy = SpyEscapeHandler()
        coordinator.escapeSession = PendingEscapeSession(handler: spy)
        defer { coordinator.escapeSession = originalSession }

        coordinator.escapeSession.begin { }
        #expect(spy.isTemporaryEscapeRegistered)

        coordinator.cancelCapture()

        #expect(spy.isTemporaryEscapeRegistered == false)
        #expect(spy.unregisterCount >= 1)
        #expect(coordinator.escapeSession.isActive == false)
        #expect(coordinator.state == .idle)
    }

    @Test("Closing overlays also releases the registration")
    @MainActor
    func testCloseOverlaysReleasesRegistration() {
        let coordinator = CaptureCoordinator.shared
        let originalSession = coordinator.escapeSession
        let spy = SpyEscapeHandler()
        coordinator.escapeSession = PendingEscapeSession(handler: spy)
        defer { coordinator.escapeSession = originalSession }

        coordinator.escapeSession.begin { }
        coordinator.closeOverlays()

        #expect(spy.isTemporaryEscapeRegistered == false)
        #expect(coordinator.escapeSession.isActive == false)
    }

    @Test("Cancelling twice is safe and leaves nothing registered")
    @MainActor
    func testRepeatedCancellationIsSafe() {
        let coordinator = CaptureCoordinator.shared
        let originalSession = coordinator.escapeSession
        let spy = SpyEscapeHandler()
        coordinator.escapeSession = PendingEscapeSession(handler: spy)
        defer { coordinator.escapeSession = originalSession }

        coordinator.escapeSession.begin { }
        coordinator.cancelCapture()
        coordinator.cancelCapture()

        #expect(spy.isTemporaryEscapeRegistered == false)
        #expect(spy.unregisterCount == 1)
        #expect(coordinator.state == .idle)
    }
}
#endif
