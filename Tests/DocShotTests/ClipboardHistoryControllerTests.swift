import AppKit
import Foundation
import Testing
import ClipboardKit
@testable import DocShot

/// The watcher end to end, on a private pasteboard, scratch preferences and a temporary store
/// folder (testing rule 1). Polls are driven by hand; no timer, no general pasteboard.
@Suite("Clipboard history controller", .serialized)
@MainActor
struct ClipboardHistoryControllerTests {

    final class Fixture {
        let pasteboard = NSPasteboard(name: NSPasteboard.Name("DocShotTests.\(UUID().uuidString)"))
        let suite = "DocShotClipboardControllerTests.\(UUID().uuidString)"
        let defaults: UserDefaults
        let folder: URL
        var frontApp = "com.apple.TextEdit"
        var accessibilityAllowed = false

        init() {
            defaults = UserDefaults(suiteName: suite)!
            folder = FileManager.default.temporaryDirectory
                .appendingPathComponent("DocShotClipboardControllerTests-\(UUID().uuidString)")
        }

        @MainActor
        func makeController() -> ClipboardHistoryController {
            ClipboardHistoryController(
                settings: ClipboardSettings(defaults: defaults),
                pasteboard: pasteboard,
                storeDirectory: folder,
                frontmostApp: { [unowned self] in self.frontApp },
                accessibilityAllowed: { [unowned self] in self.accessibilityAllowed }
            )
        }

        func copy(_ text: String, extraTypes: [String] = []) {
            pasteboard.clearContents()
            pasteboard.setString(text, forType: .string)
            for type in extraTypes {
                pasteboard.setData(Data(), forType: NSPasteboard.PasteboardType(type))
            }
        }

        func tearDown() {
            pasteboard.releaseGlobally()
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: folder)
        }
    }

    func copyAndPoll(_ fixture: Fixture, _ controller: ClipboardHistoryController, _ text: String, extraTypes: [String] = []) async {
        fixture.copy(text, extraTypes: extraTypes)
        controller.poll()
        await controller.waitUntilIdle()
    }

    @Test("With history off nothing is read, stored or created on disk")
    func testOffDoesNothing() async {
        let fixture = Fixture()
        defer { fixture.tearDown() }
        let controller = fixture.makeController()
        controller.start()

        await copyAndPoll(fixture, controller, "not recorded")
        #expect(controller.isEnabled == false)
        #expect(controller.items.isEmpty)
        #expect(FileManager.default.fileExists(atPath: fixture.folder.path) == false)
    }

    @Test("Copies made after switching on are recorded, newest first; earlier ones are not")
    func testRecordsCopies() async {
        let fixture = Fixture()
        defer { fixture.tearDown() }
        fixture.copy("already there")
        let controller = fixture.makeController()
        controller.setEnabled(true)
        await controller.waitUntilIdle()

        controller.poll()
        await copyAndPoll(fixture, controller, "first")
        await copyAndPoll(fixture, controller, "second")
        #expect(controller.items.map(\.preview) == ["second", "first"])
        #expect(controller.items.first?.sourceApp == "com.apple.TextEdit")
    }

    @Test("Concealed copies and copies from excluded apps never appear")
    func testSkips() async {
        let fixture = Fixture()
        defer { fixture.tearDown() }
        let controller = fixture.makeController()
        controller.setEnabled(true)
        await controller.waitUntilIdle()

        await copyAndPoll(fixture, controller, "password", extraTypes: ["org.nspasteboard.ConcealedType"])
        fixture.frontApp = "com.apple.Passwords"
        await copyAndPoll(fixture, controller, "from Passwords")
        fixture.frontApp = "com.apple.TextEdit"
        await copyAndPoll(fixture, controller, "ordinary")
        #expect(controller.items.map(\.preview) == ["ordinary"])
    }

    @Test("Nothing is recorded while paused, nor what was copied during the pause")
    func testPause() async {
        let fixture = Fixture()
        defer { fixture.tearDown() }
        let controller = fixture.makeController()
        controller.setEnabled(true)
        await controller.waitUntilIdle()

        controller.setPaused(true)
        await copyAndPoll(fixture, controller, "during pause")
        controller.setPaused(false)
        controller.poll()
        await controller.waitUntilIdle()
        #expect(controller.items.isEmpty)

        await copyAndPoll(fixture, controller, "after pause")
        #expect(controller.items.map(\.preview) == ["after pause"])
    }

    @Test("Copying back from history moves the item to the top without a duplicate")
    func testCopyBack() async throws {
        let fixture = Fixture()
        defer { fixture.tearDown() }
        let controller = fixture.makeController()
        controller.setEnabled(true)
        await controller.waitUntilIdle()
        await copyAndPoll(fixture, controller, "older")
        await copyAndPoll(fixture, controller, "newer")

        let older = try #require(controller.items.last)
        #expect(await controller.copyBack(older))
        #expect(fixture.pasteboard.string(forType: .string) == "older")
        // Were DocShot's own write recorded as a copy, the item would take this app as its
        // source; ignored, it keeps the app it was first copied in.
        fixture.frontApp = "com.example.elsewhere"
        controller.poll()
        await controller.waitUntilIdle()
        #expect(controller.items.map(\.preview) == ["older", "newer"])
        #expect(controller.items.first?.sourceApp == "com.apple.TextEdit")
    }

    @Test("Switching off and on while a copy is still saving keeps one store and loses nothing")
    func testOffOnWhileSaving() async {
        let fixture = Fixture()
        defer { fixture.tearDown() }
        let controller = fixture.makeController()
        controller.setEnabled(true)
        await controller.waitUntilIdle()

        fixture.copy("racing")
        controller.poll()
        controller.setEnabled(false)
        controller.setEnabled(true)
        await controller.waitUntilIdle()
        #expect(controller.items.map(\.preview) == ["racing"])

        await copyAndPoll(fixture, controller, "racing")
        #expect(controller.items.map(\.preview) == ["racing"])
        #expect(controller.problem == nil)
    }

    @Test("History survives a relaunch; switching off keeps it, Clear removes it")
    func testRelaunchAndClear() async throws {
        let fixture = Fixture()
        defer { fixture.tearDown() }
        do {
            let controller = fixture.makeController()
            controller.setEnabled(true)
            await controller.waitUntilIdle()
            await copyAndPoll(fixture, controller, "kept")
        }

        let relaunched = fixture.makeController()
        relaunched.start()
        await relaunched.waitUntilIdle()
        #expect(relaunched.isEnabled)
        #expect(relaunched.items.map(\.preview) == ["kept"])

        relaunched.setEnabled(false)
        await relaunched.waitUntilIdle()
        relaunched.setEnabled(true)
        await relaunched.waitUntilIdle()
        #expect(relaunched.items.map(\.preview) == ["kept"])

        relaunched.clear()
        await relaunched.waitUntilIdle()
        #expect(relaunched.items.isEmpty)
    }

    @Test("With history off, Clear still removes what was kept; the count survives a relaunch")
    func testClearWhileOff() async {
        let fixture = Fixture()
        defer { fixture.tearDown() }
        let controller = fixture.makeController()
        controller.setEnabled(true)
        await controller.waitUntilIdle()
        for index in 1...7 {
            await copyAndPoll(fixture, controller, "kept \(index)")
        }
        controller.setEnabled(false)
        await controller.waitUntilIdle()
        #expect(controller.items.isEmpty)
        #expect(controller.storedItems.count == 7)
        #expect(controller.hasStoredWhileOff)
        controller.setClearKeep(.lastFive)
        #expect(controller.clearCount == 2)

        let relaunched = fixture.makeController()
        relaunched.start()
        await relaunched.waitUntilIdle()
        #expect(relaunched.isEnabled == false)
        #expect(relaunched.storedItems.count == 7)

        relaunched.setClearKeep(.nothing)
        #expect(relaunched.clearCount == 7)
        relaunched.clear()
        await relaunched.waitUntilIdle()
        #expect(relaunched.storedItems.isEmpty)
        #expect(relaunched.hasStoredWhileOff == false)
        #expect(relaunched.isEnabled == false)
        #expect(relaunched.problem == nil)

        // Gone from disk, not just from the list: switching on shows nothing.
        relaunched.setEnabled(true)
        await relaunched.waitUntilIdle()
        #expect(relaunched.items.isEmpty)
    }

    @Test("Switching on while a Clear with history off is still running uses one store and clears")
    func testClearWhileOffThenOn() async {
        let fixture = Fixture()
        defer { fixture.tearDown() }
        let controller = fixture.makeController()
        controller.setEnabled(true)
        await controller.waitUntilIdle()
        await copyAndPoll(fixture, controller, "old")
        controller.setEnabled(false)
        controller.setClearKeep(.nothing)
        controller.clear()
        controller.setEnabled(true)
        await controller.waitUntilIdle()
        #expect(controller.isEnabled)
        #expect(controller.items.isEmpty)
        #expect(controller.problem == nil)

        await copyAndPoll(fixture, controller, "new")
        #expect(controller.items.map(\.preview) == ["new"])
    }

    @Test("With history never kept, Clear while off opens and creates nothing")
    func testClearWhileOffNeverKept() async {
        let fixture = Fixture()
        defer { fixture.tearDown() }
        let controller = fixture.makeController()
        controller.start()
        controller.clear()
        await controller.waitUntilIdle()
        #expect(controller.hasStoredWhileOff == false)
        #expect(controller.clearCount == 0)
        #expect(FileManager.default.fileExists(atPath: fixture.folder.path) == false)
    }

    @Test("An app added to the excluded list stops being recorded; Restore Defaults brings back the defaults")
    func testExcludedAppsEdit() async {
        let fixture = Fixture()
        defer { fixture.tearDown() }
        let controller = fixture.makeController()
        controller.setEnabled(true)
        await controller.waitUntilIdle()

        controller.addExcludedApp("com.apple.TextEdit")
        await copyAndPoll(fixture, controller, "from TextEdit")
        #expect(controller.items.isEmpty)

        controller.removeExcludedApp("com.apple.Passwords")
        fixture.frontApp = "com.apple.Passwords"
        await copyAndPoll(fixture, controller, "from Passwords")
        #expect(controller.items.map(\.preview) == ["from Passwords"])

        controller.restoreDefaultExcludedApps()
        #expect(Set(controller.excludedApps) == RecordingRules.defaultExcludedBundleIDs)
        await copyAndPoll(fixture, controller, "Passwords again")
        fixture.frontApp = "com.apple.TextEdit"
        await copyAndPoll(fixture, controller, "TextEdit again")
        #expect(controller.items.map(\.preview) == ["TextEdit again", "from Passwords"])

        // The edited list is saved.
        controller.addExcludedApp("com.example.secret")
        #expect(fixture.makeController().excludedApps.contains("com.example.secret"))
    }

    @Test("Lowering the item limit removes the oldest unpinned items at once; no limit keeps them")
    func testLimits() async throws {
        let fixture = Fixture()
        defer { fixture.tearDown() }
        let controller = fixture.makeController()
        controller.setEnabled(true)
        await controller.waitUntilIdle()
        for index in 0..<52 {
            await copyAndPoll(fixture, controller, "copy \(index)")
        }
        let oldest = try #require(controller.items.last)
        controller.togglePin(oldest)
        await controller.waitUntilIdle()

        let fifty = controller.limits(maxItems: 50, maxAgeDays: 30, maxMegabytes: 500)
        #expect(controller.removalCount(for: fifty) == 1)
        controller.setLimits(maxItems: 50, maxAgeDays: 30, maxMegabytes: 500)
        await controller.waitUntilIdle()
        #expect(controller.items.count == 51) // 50 unpinned plus the pin
        #expect(controller.items.contains { $0.id == oldest.id })
        #expect(!controller.items.contains { $0.preview == "copy 1" })

        controller.setLimits(maxItems: nil, maxAgeDays: 30, maxMegabytes: 500)
        await copyAndPoll(fixture, controller, "one more")
        #expect(controller.items.count == 52)

        // Saved, and used by the store when history opens again.
        let relaunched = fixture.makeController()
        #expect(relaunched.maxItems == nil)
        #expect(relaunched.limits.maxItems == RetentionLimits.noItemLimit)
    }

    @Test("Choosing pastes only with the setting and Accessibility; the request is shown once")
    func testPasteOutcome() async {
        let fixture = Fixture()
        defer { fixture.tearDown() }
        let controller = fixture.makeController()
        #expect(controller.pasteOutcome(hasPreviousApp: true) == .copyOnly(askForAccess: true))
        controller.markAccessRequested()
        #expect(controller.pasteOutcome(hasPreviousApp: true) == .copyOnly(askForAccess: false))

        fixture.accessibilityAllowed = true
        #expect(controller.pasteOutcome(hasPreviousApp: true) == .pasteIntoPreviousApp)
        #expect(controller.pasteAllowed)

        controller.setPasteDirectly(false)
        #expect(controller.pasteOutcome(hasPreviousApp: true) == .copyOnly(askForAccess: false))
        #expect(fixture.makeController().pasteDirectly == false)
    }

    @Test("Search finds text beyond the preview; with history off it finds nothing")
    func testSearch() async {
        let fixture = Fixture()
        defer { fixture.tearDown() }
        let controller = fixture.makeController()
        controller.setEnabled(true)
        await controller.waitUntilIdle()
        await copyAndPoll(fixture, controller, String(repeating: "x ", count: 150) + "Zürich")
        await copyAndPoll(fixture, controller, "other")
        #expect(await controller.search("zurich").count == 1)

        controller.setEnabled(false)
        await controller.waitUntilIdle()
        #expect(await controller.search("zurich").isEmpty)
    }
}
