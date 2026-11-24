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
                frontmostApp: { [unowned self] in self.frontApp }
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
}
