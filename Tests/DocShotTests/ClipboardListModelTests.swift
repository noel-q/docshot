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

    @Test("Cmd+Y shows or hides the preview, on Latin and non-Latin layouts; plain Y types")
    func testTogglePreview() {
        #expect(action(16, .command, chars: "y") == .togglePreview)
        #expect(action(16, .command, chars: "н") == .togglePreview) // Russian: the Y position
        #expect(action(16, [], chars: "y") == .passThrough)
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

    @Test("The preview choice is kept in the controller's preferences, never the app's own")
    func testPreviewPreference() {
        let fixture = ClipboardHistoryControllerTests.Fixture()
        defer { fixture.tearDown() }
        let controller = fixture.makeController()
        let model = ClipboardWindowModel(controller: controller, searchDelay: .zero)
        #expect(model.showPreview == false)
        model.showPreview = true
        #expect(fixture.defaults.bool(forKey: ClipboardSettings.showPreviewKey))
        #expect(ClipboardWindowModel(controller: fixture.makeController(), searchDelay: .zero).showPreview)
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

@Suite("Clipboard panel layout")
struct ClipboardPanelLayoutTests {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 900)

    @Test("Compact is 420 wide; with the preview, 780")
    func testWidths() {
        #expect(ClipboardPanelLayout.width(showingPreview: false) == 420)
        #expect(ClipboardPanelLayout.width(showingPreview: true) == 780)
    }

    @Test("First open: centred across, top a fifth of the way down")
    func testFirstOpen() {
        let frame = ClipboardPanelLayout.frame(visible: screen, savedOrigin: nil, showingPreview: false)
        #expect(frame.midX == screen.midX)
        #expect(frame.maxY == screen.maxY - screen.height / 5)
        #expect(screen.contains(frame))
    }

    @Test("A remembered place is used if the whole panel fits there, otherwise the default")
    func testRemembered() {
        let kept = ClipboardPanelLayout.frame(visible: screen, savedOrigin: CGPoint(x: 100, y: 200), showingPreview: false)
        #expect(kept.origin == CGPoint(x: 100, y: 200))
        // On another, smaller screen the old place is off the edge: back to the default.
        let small = CGRect(x: 0, y: 0, width: 800, height: 600)
        let moved = ClipboardPanelLayout.frame(visible: small, savedOrigin: CGPoint(x: 900, y: 200), showingPreview: false)
        #expect(small.contains(moved))
        #expect(moved.midX == small.midX)
    }

    @Test("A place left partly off screen is nudged back on, not forgotten")
    func testNudgedBack() {
        let partly = ClipboardPanelLayout.frame(visible: screen, savedOrigin: CGPoint(x: 1300, y: 50), showingPreview: false)
        #expect(screen.contains(partly))
        #expect(partly.maxX == screen.maxX)
    }

    @Test("Resizing only ever moves the panel sideways")
    func testSidewaysOnly() {
        let low = CGRect(x: 1000, y: -100, width: 420, height: 480) // partly below the screen
        #expect(ClipboardPanelLayout.resized(low, toWidth: 780, within: screen).minY == -100)
    }

    @Test("Widening keeps the left edge, unless that would run off the right of the screen")
    func testWidening() {
        let left = CGRect(x: 100, y: 200, width: 420, height: 480)
        #expect(ClipboardPanelLayout.resized(left, toWidth: 780, within: screen).minX == 100)
        let right = CGRect(x: 1000, y: 200, width: 420, height: 480)
        let widened = ClipboardPanelLayout.resized(right, toWidth: 780, within: screen)
        #expect(widened.maxX == screen.maxX)
        #expect(widened.width == 780)
        #expect(ClipboardPanelLayout.resized(widened, toWidth: 420, within: screen).minX == widened.minX)
    }
}

@Suite("Settings panel layout")
struct SettingsPanelLayoutTests {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)
    let icon = CGRect(x: 1200, y: 875, width: 30, height: 24) // in the menu bar, above `screen`

    @Test("The panel drops down under the menu bar icon, right edges lined up")
    func testUnderIcon() {
        let frame = SettingsPanelLayout.frame(size: CGSize(width: 380, height: 400), anchor: icon, visible: screen)
        #expect(frame.maxX == icon.maxX)
        #expect(frame.maxY == icon.minY - SettingsPanelLayout.gapBelowAnchor)
    }

    @Test("Near the left of the screen it is nudged on screen; with no icon it takes the top right")
    func testEdges() {
        let leftIcon = CGRect(x: 40, y: 875, width: 30, height: 24)
        #expect(SettingsPanelLayout.frame(size: CGSize(width: 380, height: 400), anchor: leftIcon, visible: screen).minX == 0)
        let none = SettingsPanelLayout.frame(size: CGSize(width: 380, height: 400), anchor: nil, visible: screen)
        #expect(screen.contains(none))
        #expect(none.maxX == screen.maxX - SettingsPanelLayout.gapBelowAnchor)
    }

    @Test("Expanding keeps the top-right corner, growing left and down, and stays on screen")
    func testGrow() {
        let compact = SettingsPanelLayout.frame(size: CGSize(width: 380, height: 400), anchor: icon, visible: screen)
        let full = SettingsPanelLayout.resized(compact, to: CGSize(width: 560, height: 700), within: screen)
        #expect(full.maxX == compact.maxX)
        #expect(full.maxY == compact.maxY)
        let tall = SettingsPanelLayout.resized(compact, to: CGSize(width: 560, height: 2000), within: screen)
        #expect(tall.minY == screen.minY)
        #expect(screen.contains(tall), "never taller than the screen, so the tab strip stays on it")
    }

    @Test("On a short screen the page cap drops so the expanded panel fits")
    func pageCapFitsTheScreen() {
        #expect(SettingsPanelLayout.pageMaxHeight(within: screen, cap: 640) == 640)
        let short = CGRect(x: 0, y: 0, width: 1280, height: 660)
        let cap = SettingsPanelLayout.pageMaxHeight(within: short, cap: 640)
        #expect(cap + SettingsPanelLayout.tabStripAllowance + SettingsPanelLayout.gapBelowAnchor <= short.height)
        #expect(SettingsPanelLayout.pageMaxHeight(within: CGRect(x: 0, y: 0, width: 800, height: 100), cap: 640) == 200)
    }
}

@Suite("Captures keys and grid")
struct CaptureKeysTests {
    func action(_ code: UInt16, _ flags: NSEvent.ModifierFlags = [], chars: String? = nil) -> CaptureKeyAction {
        CaptureKeys.action(keyCode: code, modifiers: flags, characters: chars, charactersIgnoringModifiers: chars)
    }

    @Test("Tab switches; Return chooses; Cmd+C, E and S copy, edit and save; Cmd+Delete deletes")
    func keys() {
        #expect(action(48) == .switchSection)
        #expect(action(53) == .close)
        #expect(action(36) == .choose && action(76) == .choose)
        #expect(action(8, .command, chars: "c") == .copy)
        #expect(action(14, .command, chars: "e") == .edit)
        #expect(action(1, .command, chars: "s") == .save)
        #expect(action(14, .command, chars: "у") == .edit, "Cyrillic layout: E by position")
        #expect(action(51, .command) == .delete)
        #expect(action(51) == .passThrough)
        #expect(action(123) == .left && action(124) == .right && action(126) == .up && action(125) == .down)
        #expect(ClipboardKeys.action(keyCode: 48, modifiers: [], characters: "\t", charactersIgnoringModifiers: "\t",
                                     hasMarkedText: false, hasTextSelection: false, queryIsEmpty: true) == .switchSection)
    }

    @Test("Arrows move through the grid of screenshots, then down into the recordings and back")
    func grid() {
        // 6 screenshots (rows of 4 and 2), then 2 recordings: indexes 6 and 7.
        func move(_ index: Int?, _ action: CaptureKeyAction) -> Int? {
            CaptureGrid.move(index, action, screenshots: 6, total: 8)
        }
        #expect(move(nil, .down) == 0)
        #expect(move(0, .right) == 1 && move(0, .left) == 0)
        #expect(move(1, .down) == 5)
        #expect(move(3, .down) == 6, "no screenshot below: to the first recording")
        #expect(move(5, .down) == 6)
        #expect(move(6, .up) == 5)
        #expect(move(6, .down) == 7 && move(7, .down) == 7)
        #expect(move(4, .up) == 0)
        #expect(CaptureGrid.move(0, .down, screenshots: 0, total: 0) == nil)
    }
}

@Suite("Capture editor state")
struct CaptureEditorStateTests {
    @Test("Marks and crop survive the trip to storage and back; bad data reads as nothing")
    func roundTrip() throws {
        let state = CaptureEditorState(
            annotations: [
                AnnotationItem(type: .arrow(start: CGPoint(x: 1, y: 2), end: CGPoint(x: 30, y: 40)), color: .blue, strokeWidth: 6),
                AnnotationItem(type: .redaction(rect: CGRect(x: 5, y: 5, width: 50, height: 20))),
            ],
            cropRect: CGRect(x: 10, y: 10, width: 200, height: 100)
        )
        let data = try #require(state.encoded())
        #expect(CaptureEditorState.decoded(data) == state)
        #expect(CaptureEditorState.decoded(Data("not json".utf8)) == nil)
        #expect(CaptureEditorState.decoded(nil) == nil)
    }
}

@Suite("Copy text key")
struct CopyTextKeyTests {
    @Test("Shift+Cmd+C copies the text in an image; Cmd+C alone still copies the item")
    func key() {
        func action(_ flags: NSEvent.ModifierFlags, _ chars: String) -> ClipboardKeyAction {
            ClipboardKeys.action(keyCode: 8, modifiers: flags, characters: chars, charactersIgnoringModifiers: chars,
                                 hasMarkedText: false, hasTextSelection: false, queryIsEmpty: true)
        }
        #expect(action([.command, .shift], "C") == .copyText)
        #expect(action([.command], "c") == .copy)
        #expect(ClipboardKeys.action(keyCode: 3, modifiers: [.command], characters: "f", charactersIgnoringModifiers: "f",
                                     hasMarkedText: false, hasTextSelection: false, queryIsEmpty: true) == .float)
        #expect(CaptureKeys.action(keyCode: 3, modifiers: [.command], characters: "f", charactersIgnoringModifiers: "f") == .float)
        #expect(CaptureKeys.action(keyCode: 3, modifiers: [.command], characters: "а", charactersIgnoringModifiers: "а") == .float)
    }
}
