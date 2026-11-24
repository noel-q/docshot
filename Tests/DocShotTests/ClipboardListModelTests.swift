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
        #expect(all.today.map(\.preview) == ["a", "c"])
        let some = ClipboardList.arrange([a, b, c], matching: [c.id])
        #expect(some.pinned.isEmpty)
        #expect(some.rows.map(\.preview) == ["c"])
    }

    static func item(_ label: String, kind: ClipKind, usedAt: Date, pinned: Bool = false) -> ClipItem {
        ClipItem(createdAt: usedAt, lastUsedAt: usedAt, kind: kind,
                 contentHash: ClipContent.text(label).contentHash, sourceApp: nil,
                 pinned: pinned, byteSize: 1, preview: label)
    }

    @Test("Unpinned items split into today and earlier by last use; pins stay on top whatever their age")
    func testGroups() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try #require(TimeZone(identifier: "Europe/London"))
        let now = try #require(calendar.date(from: DateComponents(year: 2026, month: 11, day: 24, hour: 10)))
        let morning = now.addingTimeInterval(-9 * 3600) // 01:00 today
        let yesterday = now.addingTimeInterval(-11 * 3600) // 23:00 yesterday
        let items = [
            Self.item("today", kind: .text, usedAt: morning),
            Self.item("yesterday", kind: .text, usedAt: yesterday),
            Self.item("old pin", kind: .text, usedAt: yesterday, pinned: true),
        ]
        let groups = ClipboardList.arrange(items, matching: nil, now: now, calendar: calendar)
        #expect(groups.pinned.map(\.preview) == ["old pin"])
        #expect(groups.today.map(\.preview) == ["today"])
        #expect(groups.earlier.map(\.preview) == ["yesterday"])
        #expect(groups.rows.map(\.preview) == ["old pin", "today", "yesterday"])
    }

    @Test("The type filter keeps one kind; Text includes rich text; it combines with search")
    func testFilter() {
        let now = Date()
        let items: [ClipItem] = [
            Self.item("plain", kind: .text, usedAt: now),
            Self.item("rich", kind: .richText, usedAt: now),
            Self.item("picture", kind: .image, usedAt: now),
            Self.item("doc", kind: .fileURLs, usedAt: now),
            Self.item("swatch", kind: .colour, usedAt: now),
        ]
        func shown(_ filter: ClipboardFilter, _ matching: Set<UUID>? = nil) -> [String] {
            ClipboardList.arrange(items, matching: matching, filter: filter, now: now).rows.map(\.preview)
        }
        #expect(shown(.all).count == 5)
        #expect(shown(.text) == ["plain", "rich"])
        #expect(shown(.images) == ["picture"])
        #expect(shown(.files) == ["doc"])
        #expect(shown(.colours) == ["swatch"])
        #expect(shown(.text, [items[1].id, items[2].id]) == ["rich"])
        #expect(ClipboardFilter.allCases.map(\.title) == ["All", "Text", "Images", "Files", "Colours"])
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

    @Test("Cmd+1 to Cmd+9 pick a row; on AZERTY the digit-row position decides; Cmd+0 does nothing")
    func testPick() {
        #expect(action(18, .command, chars: "1") == .pick(1))
        #expect(action(25, .command, chars: "9") == .pick(9))
        #expect(action(18, .command, chars: "&") == .pick(1)) // AZERTY 1 key
        #expect(action(19, .command, chars: "é") == .pick(2)) // AZERTY 2 key
        #expect(action(29, .command, chars: "0") == .passThrough)
        #expect(action(18, [], chars: "1") == .passThrough) // plain 1 types in the search
        #expect(action(18, .command, chars: "c") == .copy) // a letter is never a digit
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

    @Test("The filter narrows the list and selects its first row; opening again shows All")
    func testFilterInModel() async {
        let fixture = ClipboardHistoryControllerTests.Fixture()
        defer { fixture.tearDown() }
        let controller = fixture.makeController()
        controller.setEnabled(true)
        await controller.waitUntilIdle()
        for text in ["first", "second"] {
            fixture.copy(text)
            controller.poll()
            await controller.waitUntilIdle()
        }
        let model = ClipboardWindowModel(controller: controller, searchDelay: .zero)
        model.reset()
        model.filter = .images
        #expect(model.rows.isEmpty)
        #expect(model.selectedItem == nil)
        model.filter = .text
        #expect(model.selectedItem?.preview == "second")
        #expect(await model.settledRow(2)?.preview == "first")
        #expect(await model.settledRow(3) == nil)
        model.reset()
        #expect(model.filter == .all)
    }
}

@Suite("Clip preview text")
struct ClipPreviewTextTests {
    @Test("Colours read as hex, RGB and HSL")
    func testColour() {
        let colour = ClipColour(red: 233 / 255, green: 114 / 255, blue: 76 / 255)
        #expect(colour.hexString == "#E9724C")
        #expect(ClipPreviewText.rgb(colour) == "rgb(233 114 76)")
        #expect(ClipPreviewText.hsl(colour) == "hsl(15 78% 61%)") // standard maths; the Quiet preview shows 79%
        #expect(ClipPreviewText.hsl(ClipColour(red: 0.5, green: 0.5, blue: 0.5)) == "hsl(0 0% 50%)")
        #expect(ClipPreviewText.hsl(ClipColour(red: 0, green: 0, blue: 1)) == "hsl(240 100% 50%)")
    }

    @Test("A lone web link shows its site from the address; other text does not")
    func testLinkHost() {
        #expect(ClipPreviewText.linkHost("https://www.apple.com/design") == "apple.com")
        #expect(ClipPreviewText.linkHost("  http://example.org/a?b=c \n") == "example.org")
        #expect(ClipPreviewText.linkHost("file:///tmp/a.txt") == nil)
        #expect(ClipPreviewText.linkHost("see https://apple.com") == nil)
    }

    @Test("Text from terminals and code editors counts as code")
    func testCodeSource() {
        #expect(ClipPreviewText.isCodeSource("com.apple.Terminal"))
        #expect(ClipPreviewText.isCodeSource("com.jetbrains.intellij"))
        #expect(!ClipPreviewText.isCodeSource("com.apple.TextEdit"))
        #expect(!ClipPreviewText.isCodeSource(nil))
    }

    @Test("Size reads as characters, pixels and bytes, or a file count")
    func testSize() {
        #expect(ClipPreviewText.size(of: .text("hello"), pixelSize: nil, byteSize: 5) == "5 characters")
        #expect(ClipPreviewText.size(of: .text("a"), pixelSize: nil, byteSize: 1) == "1 character")
        #expect(ClipPreviewText.size(of: .fileURLs([URL(fileURLWithPath: "/a"), URL(fileURLWithPath: "/b")]),
                                     pixelSize: nil, byteSize: 0) == "2 files")
        #expect(ClipPreviewText.size(of: .image(data: Data(), typeIdentifier: "public.png"),
                                     pixelSize: CGSize(width: 480, height: 360), byteSize: 2048)
                .hasPrefix("480 × 360 pixels, "))
    }
}
