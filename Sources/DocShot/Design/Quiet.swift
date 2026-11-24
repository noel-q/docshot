import AppKit
import SwiftUI

/// Quiet, Noel's design system, for SwiftUI (skill `quiet-design`, `platforms.md`). Colours
/// resolve per appearance each time AppKit draws them; values come from the generated
/// `QuietTokens`. The clipboard window is the first screen on Quiet (DocShot pilot).
enum Quiet {

    // MARK: Colours

    static let canvas = color(QuietTokens.canvas)
    static let surface = color(QuietTokens.surface)
    static let surfaceRaised = color(QuietTokens.surfaceRaised)
    static let controlSurface = color(QuietTokens.controlSurface)
    static let hover = color(QuietTokens.hover)
    static let selection = color(QuietTokens.selection)
    static let line = color(QuietTokens.line)
    static let ink = color(QuietTokens.ink)
    static let inkMuted = color(QuietTokens.inkMuted)
    /// Only on `canvas` and `surface`: under 4.5:1 on the selection and raised surfaces.
    static let inkFaint = color(QuietTokens.inkFaint)
    static let onAccent = color(QuietTokens.onAccent)
    static let danger = color(QuietTokens.danger)
    static let controlRing = color(QuietTokens.controlRing)
    static let controlEdge = color(QuietTokens.controlEdge)
    static let controlDrop = color(QuietTokens.controlDrop)
    static let warning = color(QuietTokens.warning)

    /// The skin: follows the Settings colour theme (restyle plan, decision 1).
    static var accent: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let pair = ThemeController.active.theme.quietAccent
            return NSColor(quietRGBA: pair.value(isDark: isDark(appearance)))
        })
    }

    static var accentSoft: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let pair = ThemeController.active.theme.quietAccentSoft
            return NSColor(quietRGBA: pair.value(isDark: isDark(appearance)))
        })
    }

    private static func color(_ pair: QuietPair) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            NSColor(quietRGBA: pair.value(isDark: isDark(appearance)))
        })
    }

    private static func isDark(_ appearance: NSAppearance) -> Bool {
        appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
    }

    // MARK: Space and radius

    enum Space {
        static let s1 = QuietTokens.space1
        static let s2 = QuietTokens.space2
        static let s3 = QuietTokens.space3
        static let s4 = QuietTokens.space4
        static let s6 = QuietTokens.space6
        static let s8 = QuietTokens.space8
        static let s12 = QuietTokens.space12
    }

    enum Radius {
        static let xs = QuietTokens.radiusXs
        static let sm = QuietTokens.radiusSm
        static let md = QuietTokens.radiusMd
        static let lg = QuietTokens.radiusLg
    }

    // MARK: Type (system font only; platforms.md)

    enum Font {
        /// title-3 / native-title.
        static let title3 = SwiftUI.Font.system(size: 22, weight: .semibold)
        /// headline, 17 pt.
        static let headline = SwiftUI.Font.system(size: 17, weight: .semibold)
        /// body, 15 pt: reading text in previews and empty states.
        static let body = SwiftUI.Font.system(size: 15)
        /// ui, 13 pt medium: row titles and controls.
        static let ui = SwiftUI.Font.system(size: 13, weight: .medium)
        /// native-body, 13 pt.
        static let nativeBody = SwiftUI.Font.system(size: 13)
        /// caption, 12 pt: metadata. Never smaller.
        static let caption = SwiftUI.Font.system(size: 12)
        /// native-label, 12 pt medium: group headings.
        static let label = SwiftUI.Font.system(size: 12, weight: .medium)
        static let code = SwiftUI.Font.system(size: 13, design: .monospaced)
        static let codeLarge = SwiftUI.Font.system(size: 15, design: .monospaced)
    }

    // MARK: Motion (platforms.md); callers swap movement for a fade under Reduce Motion

    enum Motion {
        static let instant = Animation.easeOut(duration: QuietTokens.durInstant)
        static let fast = Animation.snappy(duration: QuietTokens.durFast)
        static let base = Animation.spring(response: 0.28, dampingFraction: 0.86)
        static let fade = Animation.easeOut(duration: QuietTokens.durFast)
    }
}

extension NSColor {
    convenience init(quietRGBA value: UInt32) {
        self.init(
            srgbRed: CGFloat((value >> 24) & 0xFF) / 255,
            green: CGFloat((value >> 16) & 0xFF) / 255,
            blue: CGFloat((value >> 8) & 0xFF) / 255,
            alpha: CGFloat(value & 0xFF) / 255
        )
    }
}
