import AppKit
import SwiftUI

/// The theme in use, readable from `NSColor` dynamic providers, which AppKit may call off the
/// main thread while drawing.
final class ActiveThemeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var value: ColorTheme

    init(_ value: ColorTheme) {
        self.value = value
    }

    var theme: ColorTheme {
        get {
            lock.lock()
            defer { lock.unlock() }
            return value
        }
        set {
            lock.lock()
            value = newValue
            lock.unlock()
        }
    }
}

/// Owns the chosen colour theme (C0.7). Views that use `DesignTokens` observe it, so a change
/// in Settings redraws every open window at once without rebuilding any view state.
@MainActor
public final class ThemeController: ObservableObject {
    public static let shared = ThemeController()

    /// Read by the dynamic colours in `DesignTokens`.
    nonisolated static let active = ActiveThemeBox(ColorThemeStore().load())

    @Published public private(set) var theme: ColorTheme

    private let store: ColorThemeStore

    init(store: ColorThemeStore = ColorThemeStore()) {
        self.store = store
        let saved = store.load()
        Self.active.theme = saved
        self.theme = saved
    }

    public func select(_ theme: ColorTheme) {
        guard theme != self.theme else { return }
        store.save(theme)
        Self.active.theme = theme
        self.theme = theme
    }
}

extension NSColor {
    convenience init(themeRGB rgb: ThemeRGB) {
        self.init(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1.0)
    }
}
