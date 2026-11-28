import Testing
import Foundation
@testable import DocShot

@Suite("Color Theme Tests", .serialized)
struct ColorThemeTests {

    // MARK: - Palette

    @Test("Four themes plus two hidden ones, Ember first and the default; Graphite is now Tide")
    func testThemeList() {
        #expect(ColorTheme.allCases == [.ember, .tide, .slate, .moss, .rose, .lavender])
        #expect(ColorTheme.defaultTheme == .ember)
        #expect(ColorTheme.allCases.map(\.displayName) == ["Ember", "Tide", "Slate", "Moss", "Rose", "Lavender"])
    }

    @Test("Every theme uses Quiet's neutrals; only the accent differs", arguments: [true, false])
    func testQuietNeutrals(isDark: Bool) {
        let all = ColorTheme.allCases.map { $0.surfaces(isDark: isDark) }
        #expect(Set(all.compactMap { $0.windowBackground?.hex }).count == 1)
        #expect(all[0].windowBackground == ThemeRGB(quietRGBA: QuietTokens.canvas.value(isDark: isDark)))
        #expect(all[0].secondaryText == ThemeRGB(quietRGBA: QuietTokens.inkMuted.value(isDark: isDark)))
    }

    @Test("Every theme has its own accent in each mode")
    func testDistinctAccents() {
        for isDark in [true, false] {
            let accents = ColorTheme.allCases.map { $0.surfaces(isDark: isDark).accent.hex }
            #expect(Set(accents).count == accents.count)
        }
    }

    @Test("The new themes tint every light-mode surface", arguments: ColorTheme.allCases)
    func testNewThemesHaveLightSurfaces(theme: ColorTheme) {
        #expect(theme.light.windowBackground != nil)
        #expect(theme.light.cardBackground != nil)
        #expect(theme.light.border != nil)
    }

    @Test("The new themes stay readable in both modes",
          arguments: ColorTheme.allCases, [true, false])
    func testNewThemesContrast(theme: ColorTheme, isDark: Bool) throws {
        let surfaces = theme.surfaces(isDark: isDark)
        let window = try #require(surfaces.windowBackground)
        let card = try #require(surfaces.cardBackground)

        // WCAG AA: 4.5:1 for small text, 3:1 for interface components such as the accent.
        #expect(surfaces.secondaryText.contrast(with: card) >= 4.5)
        #expect(surfaces.secondaryText.contrast(with: window) >= 4.5)
        #expect(surfaces.accent.contrast(with: card) >= 3.0)
        #expect(surfaces.accent.contrast(with: window) >= 3.0)
    }

    @Test("Light-mode accents are darker than dark-mode ones for the new themes",
          arguments: ColorTheme.allCases)
    func testLightAccentDarker(theme: ColorTheme) {
        #expect(theme.light.accent.relativeLuminance < theme.dark.accent.relativeLuminance)
    }

    @Test("Text on the fixed graphite tiles stays readable in every theme")
    func testFixedTileText() {
        // The tile and its text are fixed, so this holds whatever the theme or mode.
        #expect(ThemeRGB.fixedDarkTileText.contrast(with: ThemeRGB.fixedDarkTile) >= 4.5)
    }

    @Test("Contrast maths matches known values")
    func testContrastMaths() {
        #expect(abs(ThemeRGB(0x000000).contrast(with: ThemeRGB(0xFFFFFF)) - 21) < 0.01)
        #expect(abs(ThemeRGB(0x777777).contrast(with: ThemeRGB(0x777777)) - 1) < 0.0001)
    }

    // MARK: - Store

    private func scratchDefaults() -> (UserDefaults, String) {
        let suite = "DocShotColorThemeTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suite)!, suite)
    }

    @Test("Nothing saved means the default theme")
    func testStoreDefault() {
        let (defaults, suite) = scratchDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        #expect(ColorThemeStore(defaults: defaults).load() == .ember)
    }

    @Test("A saved theme is read back", arguments: ColorTheme.allCases)
    func testStoreRoundTrip(theme: ColorTheme) {
        let (defaults, suite) = scratchDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ColorThemeStore(defaults: defaults)
        store.save(theme)
        #expect(ColorThemeStore(defaults: defaults).load() == theme)
    }

    @Test("An unknown saved value falls back to the default")
    func testStoreUnknownValue() {
        let (defaults, suite) = scratchDefaults()
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("neon", forKey: ColorThemeStore.key)
        #expect(ColorThemeStore(defaults: defaults).load() == .ember)
    }

    // MARK: - Controller

    @Test("Selecting a theme saves it and updates what the colours read")
    @MainActor
    func testControllerSelect() {
        let (defaults, suite) = scratchDefaults()
        let previous = ThemeController.active.theme
        defer {
            ThemeController.active.theme = previous
            defaults.removePersistentDomain(forName: suite)
        }

        let controller = ThemeController(store: ColorThemeStore(defaults: defaults))
        #expect(controller.theme == .ember)

        controller.select(.ember)
        #expect(controller.theme == .ember)
        #expect(ThemeController.active.theme == .ember)
        #expect(ColorThemeStore(defaults: defaults).load() == .ember)
    }

    @Test("A saved Graphite choice loads as Tide")
    func testGraphiteMigrates() {
        let suite = "DocShotThemeMigration.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set("graphite", forKey: ColorThemeStore.key)
        #expect(ColorThemeStore(defaults: defaults).load() == .tide)
    }

    @Test("Every theme: Quiet canvas, surface, ink-muted, and line-strong over canvas as its border",
          arguments: ColorTheme.allCases)
    func testQuietSurfacesPerTheme(theme: ColorTheme) {
        for isDark in [true, false] {
            let surfaces = theme.surfaces(isDark: isDark)
            #expect(surfaces.windowBackground == ThemeRGB(quietRGBA: QuietTokens.canvas.value(isDark: isDark)))
            #expect(surfaces.cardBackground == ThemeRGB(quietRGBA: QuietTokens.surface.value(isDark: isDark)))
            #expect(surfaces.secondaryText == ThemeRGB(quietRGBA: QuietTokens.inkMuted.value(isDark: isDark)))
            #expect(surfaces.accent == ThemeRGB(quietRGBA: theme.quietAccent.value(isDark: isDark)))
        }
        // line-strong composited over canvas, worked out by hand.
        #expect(theme.dark.border == ThemeRGB(0x333332))
        #expect(theme.light.border == ThemeRGB(0xDAD9D7))
    }
}
