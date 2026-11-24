import AppKit
import Carbon.HIToolbox
import Testing
@testable import DocShot

@Suite("Paste action")
@MainActor
struct PasteActionTests {

    @Test("Paste needs the setting, Accessibility and an app to paste into; the request shows once")
    func testPlanner() {
        #expect(PastePlanner.outcome(pasteDirectly: true, accessAllowed: true, hasPreviousApp: true,
                                     accessRequestedBefore: false) == .pasteIntoPreviousApp)
        #expect(PastePlanner.outcome(pasteDirectly: true, accessAllowed: false, hasPreviousApp: true,
                                     accessRequestedBefore: false) == .copyOnly(askForAccess: true))
        #expect(PastePlanner.outcome(pasteDirectly: true, accessAllowed: false, hasPreviousApp: true,
                                     accessRequestedBefore: true) == .copyOnly(askForAccess: false))
        #expect(PastePlanner.outcome(pasteDirectly: false, accessAllowed: false, hasPreviousApp: true,
                                     accessRequestedBefore: false) == .copyOnly(askForAccess: false))
        #expect(PastePlanner.outcome(pasteDirectly: true, accessAllowed: true, hasPreviousApp: false,
                                     accessRequestedBefore: false) == .copyOnly(askForAccess: false))
    }

    static func layoutData(_ id: String) -> Data? {
        let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource],
              let source = list.first else { return nil }
        return PasteKeystroke.layoutData(of: source)
    }

    @Test("Cmd+V uses the key that gives V with Command held in the layout", arguments: [
        ("com.apple.keylayout.US", CGKeyCode(kVK_ANSI_V)),
        ("com.apple.keylayout.British", CGKeyCode(kVK_ANSI_V)),
        ("com.apple.keylayout.Dvorak", CGKeyCode(kVK_ANSI_Period)),
        ("com.apple.keylayout.DVORAK-QWERTYCMD", CGKeyCode(kVK_ANSI_V)),
    ])
    func testKeyCode(layout: String, expected: CGKeyCode) throws {
        let data = try #require(Self.layoutData(layout), "layout \(layout) not found")
        #expect(PasteKeystroke.keyCode(for: "v", layoutData: data) == expected)
    }

    @Test("The current layout always gives a key")
    func testCurrentLayout() {
        #expect(PasteKeystroke.keyCodeForV() < 128)
    }
}
