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

/// One appearance (dark or light) of a theme. A nil surface means "use the standard macOS
/// colour", which is how Graphite has always looked in light mode.
public struct ThemeSurfaces: Equatable, Sendable {
    public let windowBackground: ThemeRGB?
    public let cardBackground: ThemeRGB?
    public let border: ThemeRGB?
    public let accent: ThemeRGB
    public let secondaryText: ThemeRGB
}

/// DocShot's interface colour themes (plan section 7, C0.7). A theme changes only DocShot's own
/// interface; annotation colours, captures, exports, the DocShot mark and media backdrops never
/// change.
public enum ColorTheme: String, CaseIterable, Sendable, Identifiable {
    case graphite
    case slate
    case moss
    case ember

    public static let defaultTheme: ColorTheme = .graphite

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .graphite: return "Graphite"
        case .slate: return "Slate"
        case .moss: return "Moss"
        case .ember: return "Ember"
        }
    }

    public var summary: String {
        switch self {
        case .graphite: return "Default, teal accent"
        case .slate: return "Cool grey, blue accent"
        case .moss: return "Green-grey, green accent"
        case .ember: return "Warm charcoal, amber accent"
        }
    }

    public var dark: ThemeSurfaces {
        switch self {
        case .graphite:
            // Today's look, unchanged.
            return ThemeSurfaces(
                windowBackground: ThemeRGB(0x1A1D20), cardBackground: ThemeRGB(0x24272B),
                border: ThemeRGB(0x3D4045), accent: ThemeRGB(0x4FB89F), secondaryText: ThemeRGB(0x8A8F98)
            )
        case .slate:
            return ThemeSurfaces(
                windowBackground: ThemeRGB(0x181C22), cardBackground: ThemeRGB(0x222831),
                border: ThemeRGB(0x3A4350), accent: ThemeRGB(0x6EA8FE), secondaryText: ThemeRGB(0x8B95A3)
            )
        case .moss:
            return ThemeSurfaces(
                windowBackground: ThemeRGB(0x171C18), cardBackground: ThemeRGB(0x212823),
                border: ThemeRGB(0x39443B), accent: ThemeRGB(0x7BC47F), secondaryText: ThemeRGB(0x8C968D)
            )
        case .ember:
            return ThemeSurfaces(
                windowBackground: ThemeRGB(0x1E1A17), cardBackground: ThemeRGB(0x29231F),
                border: ThemeRGB(0x453B33), accent: ThemeRGB(0xE3A84C), secondaryText: ThemeRGB(0x9A9088)
            )
        }
    }

    public var light: ThemeSurfaces {
        switch self {
        case .graphite:
            // Today's look, unchanged: standard macOS surfaces with the same accent and text.
            return ThemeSurfaces(
                windowBackground: nil, cardBackground: nil, border: nil,
                accent: ThemeRGB(0x4FB89F), secondaryText: ThemeRGB(0x8A8F98)
            )
        case .slate:
            return ThemeSurfaces(
                windowBackground: ThemeRGB(0xEEF1F5), cardBackground: ThemeRGB(0xFFFFFF),
                border: ThemeRGB(0xD3DAE3), accent: ThemeRGB(0x2F6FD6), secondaryText: ThemeRGB(0x5F6B7A)
            )
        case .moss:
            return ThemeSurfaces(
                windowBackground: ThemeRGB(0xEEF2EC), cardBackground: ThemeRGB(0xFFFFFF),
                border: ThemeRGB(0xD2DCCF), accent: ThemeRGB(0x2E8540), secondaryText: ThemeRGB(0x5E6B5F)
            )
        case .ember:
            return ThemeSurfaces(
                windowBackground: ThemeRGB(0xF5F1EA), cardBackground: ThemeRGB(0xFFFFFF),
                border: ThemeRGB(0xE2D8CA), accent: ThemeRGB(0xA86A12), secondaryText: ThemeRGB(0x6F6458)
            )
        }
    }

    public func surfaces(isDark: Bool) -> ThemeSurfaces {
        isDark ? dark : light
    }
}

/// Saves the chosen theme in preferences. The defaults are injectable so tests use a scratch
/// suite, never `com.docshot.app`.
public struct ColorThemeStore: @unchecked Sendable {
    public static let key = "DocShotColorTheme"

    private let defaults: UserDefaults

    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }

    /// The saved theme, or the default when nothing is saved or the value is unknown.
    public func load() -> ColorTheme {
        guard let raw = defaults.string(forKey: Self.key),
              let theme = ColorTheme(rawValue: raw) else {
            return .defaultTheme
        }
        return theme
    }

    public func save(_ theme: ColorTheme) {
        defaults.set(theme.rawValue, forKey: Self.key)
    }
}
