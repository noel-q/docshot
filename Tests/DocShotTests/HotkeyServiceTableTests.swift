import Testing
import Foundation
import Carbon
@testable import DocShot

/// Drives `HotkeyService` against the real Carbon hotkey table, over a scratch preferences
/// domain. These replace manual "rebind, relaunch, reset" checks. The chords are F-keys with
/// four modifiers so they cannot collide with anything a person has bound.
@Suite("HotkeyService Table Tests", .serialized)
struct HotkeyServiceTableTests {

    private static let allModifiers = UInt32(controlKey | optionKey | cmdKey | shiftKey)
    private static let chordA = ShortcutBinding(keyCode: UInt32(kVK_F13), modifiers: allModifiers, keyDisplay: "F13")
    private static let chordB = ShortcutBinding(keyCode: UInt32(kVK_F14), modifiers: allModifiers, keyDisplay: "F14")
    private static let chordC = ShortcutBinding(keyCode: UInt32(kVK_F15), modifiers: allModifiers, keyDisplay: "F15")

    /// A service over throwaway preferences, with both actions parked on test chords so the
    /// real defaults are never registered by the test process.
    private func makeService() -> (HotkeyService, ShortcutStore, UserDefaults, String) {
        let name = "DocShotTests.HotkeyServiceTable.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: name)!
        let store = ShortcutStore(defaults: defaults)
        store.setOverride(Self.chordA, for: .screenshot)
        store.setOverride(Self.chordB, for: .record)
        return (HotkeyService(store: store), store, defaults, name)
    }

    @Test("A new service loads saved overrides and defaults")
    func testLoadsBindings() {
        let (service, _, defaults, name) = makeService()
        defer { defaults.removePersistentDomain(forName: name) }

        #expect(service.binding(for: .screenshot) == Self.chordA)
        #expect(service.binding(for: .record) == Self.chordB)
        #expect(service.binding(for: .openWindow) == ShortcutAction.openWindow.defaultBinding)
        #expect(service.currentPreset == Self.chordA)
        #expect(service.isUsingDefault(.screenshot) == false)
        #expect(service.isUsingDefault(.openWindow))
    }

    @Test("openWindow is never registered with the system")
    func testOpenWindowIsNotRegistered() {
        let (service, _, defaults, name) = makeService()
        defer { defaults.removePersistentDomain(forName: name) }

        #expect(service.register(.openWindow) { } == false)
        #expect(service.lastError == nil, "Declining to register openWindow is not a failure")
    }

    @Test("Rebinding registers the new chord, saves it and survives a relaunch")
    func testRebindPersists() throws {
        let (service, store, defaults, name) = makeService()
        defer {
            service.unregister(.screenshot)
            defaults.removePersistentDomain(forName: name)
        }
        try #require(service.register(.screenshot) { }, "This process could not register a system hotkey")

        #expect(service.setBinding(Self.chordC, for: .screenshot))
        #expect(service.binding(for: .screenshot) == Self.chordC)
        #expect(service.lastError == nil)
        #expect(store.override(for: .screenshot) == Self.chordC)

        // "Relaunch": a fresh service over the same preferences.
        service.unregister(.screenshot)
        #expect(HotkeyService(store: store).binding(for: .screenshot) == Self.chordC)
    }

    @Test("Rebinding to the other action's chord is refused and changes nothing")
    func testDuplicateChordIsRefused() {
        let (service, store, defaults, name) = makeService()
        defer { defaults.removePersistentDomain(forName: name) }

        #expect(service.setBinding(Self.chordB, for: .screenshot) == false)
        #expect(service.binding(for: .screenshot) == Self.chordA)
        #expect(store.override(for: .screenshot) == Self.chordA)
        #expect(service.lastError?.contains("already used") == true)
    }

    @Test("A chord the system refuses leaves the previous chord registered and saved")
    func testFailedRebindRollsBack() throws {
        let (service, store, defaults, name) = makeService()
        // A second owner already holds chord C system-wide.
        let (blocker, _, blockerDefaults, blockerName) = makeService()
        defer {
            service.unregister(.screenshot)
            blocker.unregister(.record)
            defaults.removePersistentDomain(forName: name)
            blockerDefaults.removePersistentDomain(forName: blockerName)
        }
        try #require(blocker.register(.record) { }, "This process could not register a system hotkey")
        try #require(blocker.setBinding(Self.chordC, for: .record))
        try #require(service.register(.screenshot) { })

        #expect(service.setBinding(Self.chordC, for: .screenshot) == false)

        #expect(service.binding(for: .screenshot) == Self.chordA)
        #expect(store.override(for: .screenshot) == Self.chordA)
        #expect(service.lastError?.contains("failed to register") == true)
        // The old chord is live again: taking it from a third owner must now fail.
        let (third, _, thirdDefaults, thirdName) = makeService()
        defer {
            third.unregister(.record)
            thirdDefaults.removePersistentDomain(forName: thirdName)
        }
        #expect(third.register(.screenshot) { } == false, "Chord A should still be held by the first service")
        third.unregister(.screenshot)
    }

    @Test("Reset returns to the default and clears the saved override")
    func testResetToDefault() {
        let (service, store, defaults, name) = makeService()
        defer { defaults.removePersistentDomain(forName: name) }

        // No handler is registered, so this exercises the table without claiming the real
        // default chord system-wide.
        #expect(service.resetToDefault(.screenshot))

        #expect(service.binding(for: .screenshot) == ShortcutAction.screenshot.defaultBinding)
        #expect(service.isUsingDefault(.screenshot))
        #expect(store.override(for: .screenshot) == nil)
    }

    @Test("Table shortcuts and the temporary Escape do not disturb each other")
    @MainActor
    func testEscapeIsIndependent() throws {
        let (service, _, defaults, name) = makeService()
        defer {
            service.unregisterTemporaryEscape()
            service.unregister(.screenshot)
            defaults.removePersistentDomain(forName: name)
        }
        try #require(service.register(.screenshot) { }, "This process could not register a system hotkey")

        let escapeRegistered = service.registerTemporaryEscape { }
        #expect(service.binding(for: .screenshot) == Self.chordA)

        service.unregisterTemporaryEscape()
        #expect(service.isTemporaryEscapeRegistered == false)
        // The screenshot chord is still held after Escape is released.
        #expect(service.setBinding(Self.chordC, for: .screenshot))
        _ = escapeRegistered
    }
}
