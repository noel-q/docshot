import Testing
import AppKit
import SwiftUI
@testable import DocShot

// The Settings tabs are app-only, so this runs under `swift test` (see Tests/target-parity.json).
#if SWIFT_PACKAGE
@Suite("Settings Layout Tests", .serialized)
@MainActor
struct SettingsLayoutTests {

    /// A tab takes its content's height up to a cap that, with the title bar and toolbar,
    /// fits a 13-inch display (about 800 points usable); beyond it the tab scrolls.
    @Test("Every Settings tab is 560 points wide and no taller than the cap, even the longest")
    func testTabsFit() async {
        // The longest case: clipboard history on, so every clipboard group shows.
        let fixture = ClipboardHistoryControllerTests.Fixture()
        defer { fixture.tearDown() }
        let controller = fixture.makeController()
        controller.setEnabled(true)
        await controller.waitUntilIdle()
        #expect(controller.excludedApps.count == 5)

        let tabs: [(String, NSView)] = [
            ("General", NSHostingView(rootView: GeneralSettingsView())),
            ("Clipboard", NSHostingView(rootView: ClipboardSettingsSection(controller: controller))),
            ("Capture", NSHostingView(rootView: CaptureSettingsView())),
            ("Shortcuts", NSHostingView(rootView: ShortcutsSettingsView())),
        ]
        for (name, view) in tabs {
            view.layoutSubtreeIfNeeded()
            let size = view.fittingSize
            #expect(size.width == SettingsPage<EmptyView>.width, "\(name) width \(size.width)")
            #expect(size.height >= 120, "\(name) is empty")
            #expect(size.height <= SettingsPage<EmptyView>.maxHeight, "\(name) is taller than the cap: \(size.height)")
        }
    }

    @Test("Every key the Shortcuts tab lists for the DocShot window does what it says")
    func testWindowKeysAreTrue() {
        func action(_ keyCode: UInt16, _ flags: NSEvent.ModifierFlags = [], _ chars: String? = nil,
                    query: String = "") -> ClipboardKeyAction {
            ClipboardKeys.action(keyCode: keyCode, modifiers: flags, characters: chars,
                                 charactersIgnoringModifiers: chars, hasMarkedText: false,
                                 hasTextSelection: false, queryIsEmpty: query.isEmpty)
        }
        let listed = Dictionary(uniqueKeysWithValues: ShortcutsSettingsView.windowKeys.map { ($0.keys, $0.action) })
        #expect(listed.count == 8)
        #expect(listed["↵"] != nil && action(36) == .choose)
        #expect(listed["⌘1–⌘9"] != nil && action(18, .command, "1") == .pick(1) && action(25, .command, "9") == .pick(9))
        #expect(listed["⌘C"] != nil && action(8, .command, "c") == .copy)
        #expect(listed["⌘P"] != nil && action(35, .command, "p") == .togglePin)
        #expect(listed["⌘⌫"] != nil && action(51, .command) == .delete)
        #expect(listed["⌘Y"] != nil && action(16, .command, "y") == .togglePreview)
        #expect(listed["↑ ↓"] != nil && action(126) == .up && action(125) == .down)
        #expect(listed["esc"] != nil && action(53, query: "x") == .clearSearch && action(53) == .close)
    }
}
#endif
