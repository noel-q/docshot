import Foundation

/// A colour as 0xRRGGBB, with the maths the theme tests need. No AppKit, so it runs in both
/// test targets.
public struct ThemeRGB: Equatable, Sendable {
    public let hex: UInt32

    public init(_ hex: UInt32) {
        self.hex = hex
    }

    public var red: Double { Double((hex >> 16) & 0xFF) / 255.0 }
    public var green: Double { Double((hex >> 8) & 0xFF) / 255.0 }
    public var blue: Double { Double(hex & 0xFF) / 255.0 }

    /// WCAG relative luminance.
    public var relativeLuminance: Double {
        func linear(_ channel: Double) -> Double {
            channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(red) + 0.7152 * linear(green) + 0.0722 * linear(blue)
    }

    /// The graphite tile some views draw in every theme (folder path, timeline segments).
    public static let fixedDarkTile = ThemeRGB(0x1A1D20)
    /// Text on that tile. Fixed, because themed secondary text darkens in light mode and would
    /// lose contrast on a tile that stays dark.
    public static let fixedDarkTileText = ThemeRGB(0x8A8F98)

    /// WCAG contrast ratio between two colours, from 1 to 21.
    public func contrast(with other: ThemeRGB) -> Double {
        let a = relativeLuminance
        let b = other.relativeLuminance
        return (max(a, b) + 0.05) / (min(a, b) + 0.05)
    }
}

/// One appearance (dark or light) of a theme. Since Quiet pilot step 2 every surface is set;
/// a nil surface would still mean "use the standard macOS colour".
public struct ThemeSurfaces: Equatable, Sendable {
    public let windowBackground: ThemeRGB?
    public let cardBackground: ThemeRGB?
    public let border: ThemeRGB?
    public let accent: ThemeRGB
    public let secondaryText: ThemeRGB
}

/// DocShot's interface colour themes (plan section 7, C0.7; Quiet pilot step 2, 24 November
/// 2026). Every theme uses Quiet's neutrals; a theme is only an accent. A theme changes only
/// DocShot's own interface; annotation colours, captures, exports, the DocShot mark and media
/// backdrops never change.
public enum ColorTheme: String, CaseIterable, Sendable, Identifiable {
    case ember
    /// Was "Graphite" until 24 November 2026; a saved "graphite" loads as Tide.
    case tide
    case slate
    case moss
    /// Hidden until the "in bloom" easter egg (27 November 2026). Quiet's rose.
    case rose
    /// Hidden until the "in bloom" easter egg. Quiet's lavender.
    case lavender

    public static let defaultTheme: ColorTheme = .ember

    public var id: String { rawValue }

    /// Rose and Lavender are shown only once the easter egg has unlocked them.
    public var isHidden: Bool { self == .rose || self == .lavender }

    /// The themes Settings offers.
    public static func choices(includingHidden: Bool) -> [ColorTheme] {
        allCases.filter { includingHidden || !$0.isHidden }
    }

    public var displayName: String {
        switch self {
        case .ember: return "Ember"
        case .tide: return "Tide"
        case .slate: return "Slate"
        case .moss: return "Moss"
        case .rose: return "Rose"
        case .lavender: return "Lavender"
        }
    }

    public var summary: String {
        switch self {
        case .ember: return "Default, orange accent"
        case .tide: return "Teal accent"
        case .slate: return "Blue accent"
        case .moss: return "Green accent"
        case .rose: return "Pink accent"
        case .lavender: return "Soft violet accent"
        }
    }

    /// The theme's Quiet accent (the skin).
    public var quietAccent: QuietPair {
        switch self {
        case .ember: return QuietTokens.ember
        case .tide: return QuietTokens.tide
        case .slate: return QuietTokens.sky
        case .moss: return QuietTokens.moss
        case .rose: return QuietTokens.rose
        case .lavender: return QuietTokens.lavender
        }
    }

    public var quietAccentSoft: QuietPair {
        switch self {
        case .ember: return QuietTokens.emberSoft
        case .tide: return QuietTokens.tideSoft
        case .slate: return QuietTokens.skySoft
        case .moss: return QuietTokens.mossSoft
        case .rose: return QuietTokens.roseSoft
        case .lavender: return QuietTokens.lavenderSoft
        }
    }

    public var dark: ThemeSurfaces { surfaces(isDark: true) }
    public var light: ThemeSurfaces { surfaces(isDark: false) }

    /// Quiet's neutrals with this theme's accent. Borders are `line-strong` laid over the canvas,
    /// so they stay opaque like the old theme borders.
    public func surfaces(isDark: Bool) -> ThemeSurfaces {
        let canvas = QuietTokens.canvas.value(isDark: isDark)
        return ThemeSurfaces(
            windowBackground: ThemeRGB(quietRGBA: canvas),
            cardBackground: ThemeRGB(quietRGBA: QuietTokens.surface.value(isDark: isDark)),
            border: ThemeRGB(quietRGBA: QuietTokens.lineStrong.value(isDark: isDark), over: canvas),
            accent: ThemeRGB(quietRGBA: quietAccent.value(isDark: isDark)),
            secondaryText: ThemeRGB(quietRGBA: QuietTokens.inkMuted.value(isDark: isDark))
        )
    }
}

extension ThemeRGB {
    /// An opaque Quiet colour (0xRRGGBBAA).
    public init(quietRGBA value: UInt32) {
        self.init(value >> 8)
    }

    /// A Quiet colour with alpha (0xRRGGBBAA) laid over an opaque one.
    public init(quietRGBA value: UInt32, over base: UInt32) {
        let alpha = Double(value & 0xFF) / 255
        func channel(_ shift: UInt32) -> UInt32 {
            let top = Double((value >> (shift + 8)) & 0xFF)
            let bottom = Double((base >> (shift + 8)) & 0xFF)
            return UInt32((top * alpha + bottom * (1 - alpha)).rounded())
        }
        self.init((channel(16) << 16) | (channel(8) << 8) | channel(0))
    }
}

/// Saves the chosen theme in preferences. The defaults are injectable so tests use a scratch
/// suite, never `com.docshot.app`.
public struct ColorThemeStore: @unchecked Sendable {
    public static let key = "DocShotColorTheme"
    /// Set once the "in bloom" easter egg has unlocked Rose and Lavender.
    public static let hiddenThemesKey = "DocShotHiddenThemesUnlocked"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The saved theme, or the default when nothing is saved or the value is unknown. A saved
    /// "graphite" (the name until 24 November 2026) is Tide.
    public func load() -> ColorTheme {
        guard let raw = defaults.string(forKey: Self.key) else { return .defaultTheme }
        if raw == "graphite" { return .tide }
        return ColorTheme(rawValue: raw) ?? .defaultTheme
    }

    public func save(_ theme: ColorTheme) {
        defaults.set(theme.rawValue, forKey: Self.key)
    }

    /// True once the hidden themes are unlocked, or when one of them is the saved theme.
    public func hiddenThemesUnlocked() -> Bool {
        defaults.bool(forKey: Self.hiddenThemesKey) || load().isHidden
    }

    public func unlockHiddenThemes() {
        defaults.set(true, forKey: Self.hiddenThemesKey)
    }
}
