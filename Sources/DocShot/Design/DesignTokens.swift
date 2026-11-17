import SwiftUI
import AppKit

public enum DesignTokens {
    // MARK: - Color Palette
    
    /// Graphite Base Surface (#1A1D20) - Primary dark surface and mark background tile
    public static let graphiteBaseHex = "#1A1D20"
    public static let graphiteBase = Color(red: 0x1A / 255.0, green: 0x1D / 255.0, blue: 0x20 / 255.0)
    public static let nsGraphiteBase = NSColor(red: 0x1A / 255.0, green: 0x1D / 255.0, blue: 0x20 / 255.0, alpha: 1.0)
    
    /// Graphite Elevated Surface (#24272B) - Cards, containers, toolbars
    public static let graphiteElevatedHex = "#24272B"
    public static let graphiteElevated = Color(red: 0x24 / 255.0, green: 0x27 / 255.0, blue: 0x2B / 255.0)
    public static let nsGraphiteElevated = NSColor(red: 0x24 / 255.0, green: 0x27 / 255.0, blue: 0x2B / 255.0, alpha: 1.0)
    
    /// Border Subtle (#3D4045) - Dividers, card strokes
    public static let borderSubtle = Color(red: 0x3D / 255.0, green: 0x40 / 255.0, blue: 0x45 / 255.0)
    public static let nsBorderSubtle = NSColor(red: 0x3D / 255.0, green: 0x40 / 255.0, blue: 0x45 / 255.0, alpha: 1.0)
    
    /// Border Strong (#5A5F68) - Hover states, active borders
    public static let borderStrong = Color(red: 0x5A / 255.0, green: 0x5F / 255.0, blue: 0x68 / 255.0)
    public static let nsBorderStrong = NSColor(red: 0x5A / 255.0, green: 0x5F / 255.0, blue: 0x68 / 255.0, alpha: 1.0)
    
    /// Product accent for controls, primary buttons and status. Follows the colour theme
    /// (C0.7); Graphite keeps today's teal (#4FB89F) in both modes.
    public static var primaryAccent: Color {
        themed { $0.accent }
    }
    public static let nsPrimaryAccent = NSColor(red: 0x4F / 255.0, green: 0xB8 / 255.0, blue: 0x9F / 255.0, alpha: 1.0)
    
    /// Identity Accent Amber (#E3A84C) - Brand identity details and mark asset
    public static let identityAccent = Color(red: 0xE3 / 255.0, green: 0xA8 / 255.0, blue: 0x4C / 255.0)
    public static let nsIdentityAccent = NSColor(red: 0xE3 / 255.0, green: 0xA8 / 255.0, blue: 0x4C / 255.0, alpha: 1.0)
    
    /// Secondary text for subtitles, captions and status labels. Follows the colour theme;
    /// Graphite keeps today's #8A8F98 in both modes.
    public static var secondaryText: Color {
        themed { $0.secondaryText }
    }
    public static let nsSecondaryText = NSColor(red: 0x8A / 255.0, green: 0x8F / 255.0, blue: 0x98 / 255.0, alpha: 1.0)
    
    // MARK: - Adaptive Surfaces for Light/Dark Appearance
    
    /// Window and container background. Follows the colour theme; Graphite is graphite in dark
    /// mode and the standard window background in light mode, as before C0.7.
    public static var windowBackground: Color {
        themed(fallback: { .windowBackgroundColor }) { $0.windowBackground }
    }

    /// Card and panel background. Graphite: graphite elevated in dark mode, the standard
    /// control background in light mode.
    public static var cardBackground: Color {
        themed(fallback: { .controlBackgroundColor }) { $0.cardBackground }
    }

    /// Border stroke. Graphite: the subtle graphite border in dark mode, the standard
    /// separator in light mode.
    public static var borderAdaptive: Color {
        themed(fallback: { .separatorColor }) { $0.border }
    }

    /// Text on the fixed graphite tiles (`graphiteBase` backgrounds), the same in every theme
    /// and mode so it stays readable there.
    public static let textOnDarkTile = Color(nsColor: NSColor(themeRGB: .fixedDarkTileText))

    // MARK: - Theme resolution

    /// A colour that follows both the macOS appearance and the chosen theme, resolved each time
    /// AppKit draws it. Brand and media colours above (the mark, `graphiteBase`, `borderSubtle`,
    /// `identityAccent`) stay fixed by decision.
    private static func themed(
        fallback: @escaping @Sendable () -> NSColor = { .labelColor },
        _ pick: @escaping @Sendable (ThemeSurfaces) -> ThemeRGB?
    ) -> Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            let surfaces = ThemeController.active.theme.surfaces(isDark: isDark)
            guard let rgb = pick(surfaces) else { return fallback() }
            return NSColor(themeRGB: rgb)
        })
    }
}
