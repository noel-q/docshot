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

    @Test("Limits default to 200 items, 30 days and 500 MB; no limit is saved and read back")
    func testLimits() {
        let (settings, defaults, suite) = scratch()
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(settings.maxItems == 200)
        #expect(settings.limits == .standard)

        settings.maxItems = nil
        settings.maxAgeDays = 7
        settings.maxMegabytes = 1024
        let reread = ClipboardSettings(defaults: defaults)
        #expect(reread.maxItems == nil)
        #expect(reread.limits == RetentionLimits(maxItems: RetentionLimits.noItemLimit,
                                                 maxAge: 7 * 86_400, maxBytes: 1024 * 1024 * 1024))
    }

    @Test("A stored limit that is not one of the choices reads as the default")
    func testUnknownLimits() {
        let (settings, defaults, suite) = scratch()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(-5, forKey: ClipboardSettings.maxItemsKey)
        defaults.set(3, forKey: ClipboardSettings.maxAgeDaysKey)
        defaults.set(7, forKey: ClipboardSettings.maxMegabytesKey)
        #expect(settings.limits == .standard)
    }

    @Test("Excluded apps start as the defaults; an edit is kept; Restore Defaults undoes it")
    func testExcludedApps() {
        let (settings, defaults, suite) = scratch()
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(Set(settings.excludedApps) == RecordingRules.defaultExcludedBundleIDs)
        settings.excludedApps = ["com.example.a"]
        #expect(ClipboardSettings(defaults: defaults).excludedApps == ["com.example.a"])
        settings.restoreDefaultExcludedApps()
        #expect(Set(settings.excludedApps) == RecordingRules.defaultExcludedBundleIDs)
    }

    @Test("Paste into the previous app is on by default; the request has not been shown")
    func testPasteDefaults() {
        let (settings, defaults, suite) = scratch()
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(settings.pasteDirectly)
        #expect(!settings.accessRequested)
        settings.pasteDirectly = false
        #expect(!ClipboardSettings(defaults: defaults).pasteDirectly)
    }
}
