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
    
    /// Primary Product Accent Teal (#4FB89F) - DocShot controls, primary buttons, status
    public static let primaryAccent = Color(red: 0x4F / 255.0, green: 0xB8 / 255.0, blue: 0x9F / 255.0)
    public static let nsPrimaryAccent = NSColor(red: 0x4F / 255.0, green: 0xB8 / 255.0, blue: 0x9F / 255.0, alpha: 1.0)
    
    /// Identity Accent Amber (#E3A84C) - Brand identity details and mark asset
    public static let identityAccent = Color(red: 0xE3 / 255.0, green: 0xA8 / 255.0, blue: 0x4C / 255.0)
    public static let nsIdentityAccent = NSColor(red: 0xE3 / 255.0, green: 0xA8 / 255.0, blue: 0x4C / 255.0, alpha: 1.0)
    
    /// Secondary Text (#8A8F98) - Subtitles, captions, export status labels
    public static let secondaryText = Color(red: 0x8A / 255.0, green: 0x8F / 255.0, blue: 0x98 / 255.0)
    public static let nsSecondaryText = NSColor(red: 0x8A / 255.0, green: 0x8F / 255.0, blue: 0x98 / 255.0, alpha: 1.0)
    
    // MARK: - Adaptive Surfaces for Light/Dark Appearance
    
    /// Adaptive background for windows/containers: Uses graphite in dark mode, clean control background in light mode.
    public static var windowBackground: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return nsGraphiteBase
            } else {
                return .windowBackgroundColor
            }
        })
    }
    
    /// Adaptive surface background for cards/panels: Uses graphite elevated in dark mode, control background in light mode.
    public static var cardBackground: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return nsGraphiteElevated
            } else {
                return .controlBackgroundColor
            }
        })
    }
    
    /// Adaptive border stroke color
    public static var borderAdaptive: Color {
        Color(nsColor: NSColor(name: nil) { appearance in
            if appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua {
                return nsBorderSubtle
            } else {
                return NSColor.separatorColor
            }
        })
    }
}
