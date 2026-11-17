import Testing
import AppKit
import SwiftUI
@testable import DocShot

// SettingsView is app-only, so this runs under `swift test` (see Tests/target-parity.json).
#if SWIFT_PACKAGE
@Suite("Settings Layout Tests")
struct SettingsLayoutTests {

    /// The Settings content scrolls inside a fixed window. A fixed height without scrolling
    /// once clipped the header and the privacy notice. This keeps the window small enough
    /// for a 13-inch display (about 800 points of usable height).
    @Test("The Settings window has a fixed size that fits a small display")
    @MainActor
    func testSettingsFitsItsWindow() {
        let hosting = NSHostingView(rootView: SettingsView())
        let size = hosting.fittingSize

        #expect(size.width == 520)
        #expect(size.height >= 500, "Too short to show the shortcut rows without scrolling")
        #expect(size.height <= 760, "Settings window is taller than a small display")
    }
}
#endif
