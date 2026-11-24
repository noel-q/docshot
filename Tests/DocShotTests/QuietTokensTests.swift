import Foundation
import Testing
@testable import DocShot

/// Contrast for the Quiet pairs the clipboard window uses (quiet-design skill, checklist 3):
/// text 4.5:1, marks 3:1, in dark and light.
@Suite("Quiet tokens")
struct QuietTokensTests {

    /// Opaque colour of `value` (RRGGBBAA) laid over the opaque `base`.
    static func composite(_ value: UInt32, over base: UInt32) -> ThemeRGB {
        let alpha = Double(value & 0xFF) / 255
        func channel(_ shift: UInt32) -> UInt32 {
            let top = Double((value >> (shift + 8)) & 0xFF)
            let bottom = Double((base >> (shift + 8)) & 0xFF)
            return UInt32((top * alpha + bottom * (1 - alpha)).rounded())
        }
        return ThemeRGB((channel(16) << 16) | (channel(8) << 8) | channel(0))
    }

    static func rgb(_ value: UInt32) -> ThemeRGB { ThemeRGB(value >> 8) }

    static let modes = [true, false]

    @Test("Text tokens read at 4.5:1 on every surface the window uses", arguments: modes)
    func testText(isDark: Bool) {
        let canvas = QuietTokens.canvas.value(isDark: isDark)
        let backgrounds: [(String, ThemeRGB)] = [
            ("canvas", Self.rgb(canvas)),
            ("surface", Self.rgb(QuietTokens.surface.value(isDark: isDark))),
            ("surfaceRaised", Self.rgb(QuietTokens.surfaceRaised.value(isDark: isDark))),
            ("selection on canvas", Self.composite(QuietTokens.selection.value(isDark: isDark), over: canvas)),
            ("hover on canvas", Self.composite(QuietTokens.hover.value(isDark: isDark), over: canvas)),
        ]
        for (textName, text) in [("ink", QuietTokens.ink), ("inkMuted", QuietTokens.inkMuted)] {
            for (backgroundName, background) in backgrounds {
                let ratio = Self.rgb(text.value(isDark: isDark)).contrast(with: background)
                #expect(ratio >= 4.5, "\(textName) on \(backgroundName), dark \(isDark): \(ratio)")
            }
        }
        // inkFaint is used only on canvas and surface (footer and detail labels); it falls just
        // under 4.5:1 on the selection and on raised surfaces, so it is never used there.
        for (backgroundName, background) in backgrounds.prefix(2) {
            let ratio = Self.rgb(QuietTokens.inkFaint.value(isDark: isDark)).contrast(with: background)
            #expect(ratio >= 4.5, "inkFaint on \(backgroundName), dark \(isDark): \(ratio)")
        }
    }

    @Test("Every theme's accent shows at 3:1 as a mark, and text on it reads at 4.5:1",
          arguments: ColorTheme.allCases)
    func testAccent(theme: ColorTheme) {
        for isDark in Self.modes {
            let accent = Self.rgb(theme.quietAccent.value(isDark: isDark))
            for surface in [QuietTokens.canvas, QuietTokens.surface] {
                let ratio = accent.contrast(with: Self.rgb(surface.value(isDark: isDark)))
                #expect(ratio >= 3, "\(theme) accent, dark \(isDark): \(ratio)")
            }
            let onAccent = Self.rgb(QuietTokens.onAccent.value(isDark: isDark)).contrast(with: accent)
            #expect(onAccent >= 4.5, "on-accent on \(theme), dark \(isDark): \(onAccent)")
        }
    }

    @Test("Themes map to the agreed Quiet accents")
    func testMapping() {
        #expect(ColorTheme.tide.quietAccent == QuietTokens.tide)
        #expect(ColorTheme.slate.quietAccent == QuietTokens.sky)
        #expect(ColorTheme.moss.quietAccent == QuietTokens.moss)
        #expect(ColorTheme.ember.quietAccent == QuietTokens.ember)
    }

    @Test("The accent reads at 4.5:1 as text on canvas (the Resume link), for every theme",
          arguments: ColorTheme.allCases)
    func testAccentAsText(theme: ColorTheme) {
        for isDark in Self.modes {
            let ratio = Self.rgb(theme.quietAccent.value(isDark: isDark))
                .contrast(with: Self.rgb(QuietTokens.canvas.value(isDark: isDark)))
            #expect(ratio >= 4.5, "\(theme) accent text, dark \(isDark): \(ratio)")
        }
    }

    @Test("Key caps, warnings and errors read at 4.5:1", arguments: modes)
    func testControlAndStatus(isDark: Bool) {
        let keyCap = Self.rgb(QuietTokens.inkMuted.value(isDark: isDark))
            .contrast(with: Self.rgb(QuietTokens.controlSurface.value(isDark: isDark)))
        #expect(keyCap >= 4.5, "key cap, dark \(isDark): \(keyCap)")
        for (name, pair) in [("warning", QuietTokens.warning), ("danger", QuietTokens.danger)] {
            let ratio = Self.rgb(pair.value(isDark: isDark)).contrast(with: Self.rgb(QuietTokens.canvas.value(isDark: isDark)))
            #expect(ratio >= 4.5, "\(name) on canvas, dark \(isDark): \(ratio)")
        }
    }
}
