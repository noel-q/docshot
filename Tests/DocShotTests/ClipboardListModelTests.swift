import AppKit
import Foundation
import Testing
import ClipboardKit
@testable import DocShot

@Suite("Clipboard list")
struct ClipboardListTests {

    static func item(_ label: String, pinned: Bool = false) -> ClipItem {
        ClipItem(createdAt: Date(), lastUsedAt: Date(), kind: .text,
                 contentHash: ClipContent.text(label).contentHash, sourceApp: nil,
                 pinned: pinned, byteSize: 1, preview: label)
    }

    @Test("Pinned items come first, each group keeps its order, and a search filters both")
    func testArrange() {
        let a = Self.item("a"), b = Self.item("b", pinned: true), c = Self.item("c")
        let all = ClipboardList.arrange([a, b, c], matching: nil)
        #expect(all.pinned.map(\.preview) == ["b"])
        #expect(all.others.map(\.preview) == ["a", "c"])
        let some = ClipboardList.arrange([a, b, c], matching: [c.id])
        #expect(some.pinned.isEmpty)
        #expect(some.others.map(\.preview) == ["c"])
    }

    @Test("Up and Down stop at the ends; with nothing selected the first row is chosen")
    func testMove() {
        let rows = ["a", "b", "c"].map { Self.item($0) }
        #expect(ClipboardList.move(nil, by: 1, in: rows) == rows[0].id)
        #expect(ClipboardList.move(rows[0].id, by: -1, in: rows) == rows[0].id)
        #expect(ClipboardList.move(rows[1].id, by: 1, in: rows) == rows[2].id)
        #expect(ClipboardList.move(rows[2].id, by: 1, in: rows) == rows[2].id)
        #expect(ClipboardList.move(nil, by: 1, in: []) == nil)
    }

    @Test("After a delete the row now in its place is selected")
    func testKeepSelection() {
        let rows = ["a", "b", "c"].map { Self.item($0) }
        #expect(ClipboardList.keepSelection(rows[1].id, old: rows, new: rows) == rows[1].id)
        #expect(ClipboardList.keepSelection(rows[1].id, old: rows, new: [rows[0], rows[2]]) == rows[2].id)
        #expect(ClipboardList.keepSelection(rows[2].id, old: rows, new: [rows[0], rows[1]]) == rows[1].id)
        #expect(ClipboardList.keepSelection(rows[0].id, old: rows, new: []) == nil)
    }
}

@Suite("Clipboard window keys")
struct ClipboardKeysTests {
    func action(_ keyCode: UInt16, _ flags: NSEvent.ModifierFlags = [], chars: String? = nil,
                marked: Bool = false, selection: Bool = false, query: String = "") -> ClipboardKeyAction {
        ClipboardKeys.action(keyCode: keyCode, modifiers: flags, characters: chars,
                             charactersIgnoringModifiers: chars, hasMarkedText: marked,
                             hasTextSelection: selection, queryIsEmpty: query.isEmpty)
    }

    @Test("Escape clears the search first, then closes")
    func testEscape() {
        #expect(action(53, query: "abc") == .clearSearch)
        #expect(action(53) == .close)
    }

    @Test("Return, Enter, arrows, Cmd+Delete, Cmd+C and Cmd+P map to their actions")
    func testKeys() {
        #expect(action(36) == .choose)
        #expect(action(76) == .choose)
        #expect(action(126) == .up)
        #expect(action(125) == .down)
        #expect(action(51, .command) == .delete)
        #expect(action(8, .command, chars: "c") == .copy)
        #expect(action(35, .command, chars: "p") == .togglePin)
        #expect(action(36, .shift) == .passThrough)
        #expect(action(51) == .passThrough) // plain Delete edits the search
        #expect(action(0, .command, chars: "a") == .passThrough) // Cmd+A selects the search text
    }

    @Test("Cmd+C with text selected in the field copies that text, not an item")
    func testCopySelection() {
        #expect(action(8, .command, chars: "c", selection: true) == .passThrough)
    }

    @Test("While an input method is composing, every key belongs to it")
    func testMarkedText() {
        for key: UInt16 in [36, 53, 125, 126] {
            #expect(action(key, marked: true) == .passThrough)
        }
    }

    @Test("Shortcuts follow the layout's letter, and the key position only on non-Latin layouts")
    func testLayouts() {
        // Dvorak: the key at ANSI J (38) types "c".
        #expect(action(38, .command, chars: "c") == .copy)
        // Dvorak: the ANSI C position (8) types "j" and must not copy.
        #expect(action(8, .command, chars: "j") == .passThrough)
        // Russian: the ANSI C position types a Cyrillic letter; the position decides.
        #expect(action(8, .command, chars: "с") == .copy)
        #expect(action(35, .command, chars: "з") == .togglePin)
    }

    @Test("The letter typed with Command wins over the plain letter (Dvorak with QWERTY Command)")
    func testCharactersFirst() {
        // Dvorak - QWERTY Command: the ANSI C key types "j" alone but "c" with Command.
        #expect(ClipboardKeys.action(keyCode: 8, modifiers: .command, characters: "c",
                                     charactersIgnoringModifiers: "j", hasMarkedText: false,
                                     hasTextSelection: false, queryIsEmpty: true) == .copy)
        #expect(ClipboardKeys.commandLetter(keyCode: 38, characters: "j", charactersIgnoringModifiers: "c") == "j")
    }
}

/// The window model against a real controller on a private pasteboard and temporary store.
@Suite("Clipboard window model", .serialized)
@MainActor
struct ClipboardWindowModelTests {

    @Test("Typing searches, selects the best match, and a blank search shows everything again")
    func testSearch() async throws {
        let fixture = ClipboardHistoryControllerTests.Fixture()
        defer { fixture.tearDown() }
        let controller = fixture.makeController()
        controller.setEnabled(true)
        await controller.waitUntilIdle()
        for text in ["apple pie", "banana bread", "Apple crumble"] {
            fixture.copy(text)
            controller.poll()
            await controller.waitUntilIdle()
        }
        let model = ClipboardWindowModel(controller: controller, searchDelay: .zero)
        model.reset()
        #expect(model.rows.map(\.preview) == ["Apple crumble", "banana bread", "apple pie"])

        model.query = "APPLE"
        await model.waitForSearch()
        #expect(model.rows.map(\.preview) == ["Apple crumble", "apple pie"])
        #expect(model.selectedItem?.preview == "Apple crumble")

        // A new matching copy shows up while the search stays.
        fixture.copy("apple tart")
        controller.poll()
        await controller.waitUntilIdle()
        await model.waitForSearch()
        #expect(model.rows.map(\.preview) == ["apple tart", "Apple crumble", "apple pie"])

        model.query = ""
        #expect(model.rows.count == 4)
    }

    @Test("Pins move to the top group; deleting keeps a selection in place")
    func testPinAndDelete() async throws {
        let fixture = ClipboardHistoryControllerTests.Fixture()
        defer { fixture.tearDown() }
        let controller = fixture.makeController()
        controller.setEnabled(true)
        await controller.waitUntilIdle()
        for text in ["one", "two", "three"] {
            fixture.copy(text)
            controller.poll()
            await controller.waitUntilIdle()
        }
        let model = ClipboardWindowModel(controller: controller, searchDelay: .zero)
        model.reset()

        let one = try #require(model.rows.last)
        controller.togglePin(one)
        await controller.waitUntilIdle()
        #expect(model.pinned.map(\.preview) == ["one"])
        #expect(model.others.map(\.preview) == ["three", "two"])

        // The selection follows the item, not the row, when a pin reorders the list.
        let three = try #require(model.selectedItem)
        #expect(three.preview == "three")
        controller.delete(three)
        await controller.waitUntilIdle()
        #expect(model.selectedItem?.preview == "two")
        #expect(controller.notice == nil)
    }

    @Test("A key pressed straight after typing acts on the searched list, not the old one")
    func testSettledSelection() async {
        let fixture = ClipboardHistoryControllerTests.Fixture()
        defer { fixture.tearDown() }
        let controller = fixture.makeController()
        controller.setEnabled(true)
        await controller.waitUntilIdle()
        for text in ["target", "newest"] {
            fixture.copy(text)
            controller.poll()
            await controller.waitUntilIdle()
        }
        let model = ClipboardWindowModel(controller: controller, searchDelay: .milliseconds(200))
        model.reset()
        #expect(model.selectedItem?.preview == "newest")
        model.query = "targ"
        #expect(await model.settledSelection()?.preview == "target")
    }
}
