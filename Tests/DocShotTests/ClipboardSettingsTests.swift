import Foundation
import Testing
import ClipboardKit
@testable import DocShot

@Suite("Clipboard settings")
struct ClipboardSettingsTests {

    private func scratch() -> (ClipboardSettings, UserDefaults, String) {
        let suite = "DocShotClipboardSettingsTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        return (ClipboardSettings(defaults: defaults), defaults, suite)
    }

    @Test("History is off, not paused, and Clear keeps pinned only by default")
    func testDefaults() {
        let (settings, defaults, suite) = scratch()
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(settings.historyEnabled == false)
        #expect(settings.paused == false)
        #expect(settings.clearKeep == .pinnedOnly)
    }

    @Test("Choices are saved and read back")
    func testRoundTrip() {
        let (settings, defaults, suite) = scratch()
        defer { defaults.removePersistentDomain(forName: suite) }
        settings.historyEnabled = true
        settings.paused = true
        settings.clearKeep = .lastTen

        let reread = ClipboardSettings(defaults: defaults)
        #expect(reread.historyEnabled)
        #expect(reread.paused)
        #expect(reread.clearKeep == .lastTen)
    }

    @Test("An unknown Clear choice falls back to pinned only")
    func testUnknownClearKeep() {
        let (settings, defaults, suite) = scratch()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("everything", forKey: ClipboardSettings.clearKeepKey)
        #expect(settings.clearKeep == .pinnedOnly)
    }

    @Test("Every Clear choice has a label")
    func testClearKeepTitles() {
        #expect(ClearKeep.allCases.map(\.title) == ["Last 5 and pinned", "Last 10 and pinned", "Pinned only", "Nothing"])
    }
}
