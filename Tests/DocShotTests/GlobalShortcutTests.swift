import Testing
import Foundation
import Carbon
@testable import DocShot

/// A throwaway defaults domain per test, so nothing touches the real preferences.
private func makeDefaults() -> (UserDefaults, String) {
    let name = "DocShotTests.GlobalShortcut.\(UUID().uuidString)"
    return (UserDefaults(suiteName: name)!, name)
}

private let family = UInt32(controlKey | optionKey | cmdKey)

@Suite("Global Shortcut Default Table Tests")
struct GlobalShortcutDefaultTableTests {

    @Test("The table has exactly three actions")
    func testThreeActions() {
        #expect(ShortcutAction.allCases == [.screenshot, .record, .openWindow])
    }

    @Test("Defaults are Control+Option+Command with S, R and V")
    func testDefaults() {
        #expect(ShortcutAction.screenshot.defaultBinding
                == ShortcutBinding(keyCode: UInt32(kVK_ANSI_S), modifiers: family, keyDisplay: "S"))
        #expect(ShortcutAction.record.defaultBinding
                == ShortcutBinding(keyCode: UInt32(kVK_ANSI_R), modifiers: family, keyDisplay: "R"))
        #expect(ShortcutAction.openWindow.defaultBinding
                == ShortcutBinding(keyCode: UInt32(kVK_ANSI_V), modifiers: family, keyDisplay: "V"))
    }

    @Test("Defaults display as one-hand chords")
    func testDisplay() {
        #expect(ShortcutAction.screenshot.defaultBinding.shortcutDisplay == "⌃⌥⌘S")
        #expect(ShortcutAction.record.defaultBinding.shortcutDisplay == "⌃⌥⌘R")
        #expect(ShortcutAction.openWindow.defaultBinding.shortcutDisplay == "⌃⌥⌘V")
    }

    @Test("openWindow is defined but not registered until its window exists")
    func testOpenWindowIsNotRegistrable() {
        #expect(ShortcutAction.screenshot.isRegistrable)
        #expect(ShortcutAction.record.isRegistrable)
        #expect(ShortcutAction.openWindow.isRegistrable == false)
    }

    @Test("Hotkey identifiers are unique and leave 2 for the temporary Escape")
    func testHotKeyIdentifiers() {
        let ids = ShortcutAction.allCases.map(\.hotKeyID)
        #expect(Set(ids).count == ids.count)
        #expect(ids.contains(2) == false)
    }

    @Test("No two defaults share a chord")
    func testDefaultsDoNotCollide() {
        let defaults = ShortcutAction.allCases.map(\.defaultBinding)
        for (index, binding) in defaults.enumerated() {
            for other in defaults.dropFirst(index + 1) {
                #expect(binding.isSameChord(as: other) == false)
            }
        }
    }
}

@Suite("Global Shortcut Override Persistence Tests")
struct GlobalShortcutOverridePersistenceTests {

    @Test("With nothing saved every action uses its default")
    func testDefaultsWhenEmpty() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = ShortcutStore(defaults: defaults)

        for action in ShortcutAction.allCases {
            #expect(store.override(for: action) == nil)
            #expect(store.binding(for: action) == action.defaultBinding)
        }
    }

    @Test("A saved override is read back by a new store")
    func testOverrideRoundTrip() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let custom = ShortcutBinding(keyCode: UInt32(kVK_ANSI_G), modifiers: UInt32(cmdKey | optionKey), keyDisplay: "G")

        ShortcutStore(defaults: defaults).setOverride(custom, for: .record)

        let reloaded = ShortcutStore(defaults: defaults)
        #expect(reloaded.override(for: .record) == custom)
        #expect(reloaded.binding(for: .record) == custom)
    }

    @Test("An override on one action leaves the others on their defaults")
    func testOverridesAreIndependent() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = ShortcutStore(defaults: defaults)
        let custom = ShortcutBinding(keyCode: UInt32(kVK_ANSI_G), modifiers: UInt32(cmdKey | optionKey), keyDisplay: "G")

        store.setOverride(custom, for: .screenshot)

        #expect(store.binding(for: .screenshot) == custom)
        #expect(store.binding(for: .record) == ShortcutAction.record.defaultBinding)
        #expect(store.binding(for: .openWindow) == ShortcutAction.openWindow.defaultBinding)
    }

    @Test("A key with key code 0 (A) persists as an override, not as 'unset'")
    func testKeyCodeZeroPersists() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = ShortcutStore(defaults: defaults)
        let custom = ShortcutBinding(keyCode: UInt32(kVK_ANSI_A), modifiers: family, keyDisplay: "A")

        store.setOverride(custom, for: .screenshot)

        #expect(store.override(for: .screenshot) == custom)
    }

    @Test("Clearing an override returns the action to its default")
    func testClearOverride() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = ShortcutStore(defaults: defaults)
        store.setOverride(
            ShortcutBinding(keyCode: UInt32(kVK_ANSI_G), modifiers: UInt32(cmdKey | optionKey), keyDisplay: "G"),
            for: .screenshot
        )

        store.clearOverride(for: .screenshot)

        #expect(store.override(for: .screenshot) == nil)
        #expect(store.binding(for: .screenshot) == ShortcutAction.screenshot.defaultBinding)
    }
}

@Suite("Global Shortcut Migration Tests")
struct GlobalShortcutMigrationTests {

    private static let legacyKeys = [
        "DocShotHotkeyPresetID",
        "DocShotCustomHotkeyEnabled",
        "DocShotCustomHotkeyKeyCode",
        "DocShotCustomHotkeyModifiers",
        "DocShotCustomHotkeyKeyDisplay"
    ]

    @Test("A saved custom screenshot shortcut is kept")
    func testMigrationFromCustom() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(0, forKey: "DocShotHotkeyPresetID")
        defaults.set(true, forKey: "DocShotCustomHotkeyEnabled")
        defaults.set(Int(kVK_ANSI_D), forKey: "DocShotCustomHotkeyKeyCode")
        defaults.set(Int(cmdKey | controlKey), forKey: "DocShotCustomHotkeyModifiers")
        defaults.set("D", forKey: "DocShotCustomHotkeyKeyDisplay")
        let store = ShortcutStore(defaults: defaults)

        store.migrateLegacyIfNeeded()

        #expect(store.binding(for: .screenshot)
                == ShortcutBinding(keyCode: UInt32(kVK_ANSI_D), modifiers: UInt32(cmdKey | controlKey), keyDisplay: "D"))
        #expect(store.binding(for: .record) == ShortcutAction.record.defaultBinding)
    }

    @Test("A saved preset becomes a custom binding",
          arguments: [
            (1, UInt32(kVK_ANSI_5), UInt32(cmdKey | shiftKey), "⇧⌘5"),
            (2, UInt32(kVK_ANSI_7), UInt32(cmdKey | shiftKey), "⇧⌘7"),
            (3, UInt32(kVK_ANSI_S), UInt32(optionKey | shiftKey), "⌥⇧S")
          ])
    func testMigrationFromPreset(presetID: Int, keyCode: UInt32, modifiers: UInt32, display: String) {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(presetID, forKey: "DocShotHotkeyPresetID")
        defaults.set(false, forKey: "DocShotCustomHotkeyEnabled")
        let store = ShortcutStore(defaults: defaults)

        store.migrateLegacyIfNeeded()

        let migrated = store.override(for: .screenshot)
        #expect(migrated?.keyCode == keyCode)
        #expect(migrated?.modifiers == modifiers)
        #expect(migrated?.shortcutDisplay == display)
    }

    @Test("The old default preset (Cmd+Shift+6) moves to the new default")
    func testOldDefaultPresetMovesToNewDefault() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(0, forKey: "DocShotHotkeyPresetID")
        defaults.set(false, forKey: "DocShotCustomHotkeyEnabled")
        let store = ShortcutStore(defaults: defaults)

        store.migrateLegacyIfNeeded()

        #expect(store.override(for: .screenshot) == nil)
        #expect(store.binding(for: .screenshot) == ShortcutAction.screenshot.defaultBinding)
    }

    @Test("Recording always moves to the new default")
    func testRecordingMovesToNewDefault() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(3, forKey: "DocShotHotkeyPresetID")
        let store = ShortcutStore(defaults: defaults)

        store.migrateLegacyIfNeeded()

        #expect(store.override(for: .record) == nil)
        #expect(store.binding(for: .record).shortcutDisplay == "⌃⌥⌘R")
    }

    @Test("A fresh install migrates to the defaults")
    func testFreshInstall() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        let store = ShortcutStore(defaults: defaults)

        store.migrateLegacyIfNeeded()

        for action in ShortcutAction.allCases {
            #expect(store.override(for: action) == nil)
        }
    }

    @Test("Migration removes the legacy keys and runs only once")
    func testMigrationRunsOnce() {
        let (defaults, name) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: name) }
        defaults.set(2, forKey: "DocShotHotkeyPresetID")
        let store = ShortcutStore(defaults: defaults)

        store.migrateLegacyIfNeeded()
        for key in Self.legacyKeys {
            #expect(defaults.object(forKey: key) == nil)
        }

        // The user then resets to default. A stale legacy value reappearing must not win.
        store.clearOverride(for: .screenshot)
        defaults.set(2, forKey: "DocShotHotkeyPresetID")
        store.migrateLegacyIfNeeded()

        #expect(store.override(for: .screenshot) == nil)
    }
}
