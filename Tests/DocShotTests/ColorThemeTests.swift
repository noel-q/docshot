import Testing
import Foundation
@testable import DocShot

@Suite("Color Theme Tests", .serialized)
struct ColorThemeTests {

    // MARK: - Palette

    @Test("Four themes, Graphite first and the default")
    func testThemeList() {
        #expect(ColorTheme.allCases == [.graphite, .slate, .moss, .ember])
        #expect(ColorTheme.defaultTheme == .graphite)
        #expect(ColorTheme.allCases.map(\.displayName) == ["Graphite", "Slate", "Moss", "Ember"])
    }

    @Test("Graphite is exactly the pre-C0.7 look")
    func testGraphiteUnchanged() {
        let dark = ColorTheme.graphite.dark
        #expect(dark.windowBackground == ThemeRGB(0x1A1D20))
        #expect(dark.cardBackground == ThemeRGB(0x24272B))
        #expect(dark.border == ThemeRGB(0x3D4045))
        #expect(dark.accent == ThemeRGB(0x4FB89F))
        #expect(dark.secondaryText == ThemeRGB(0x8A8F98))

        // Light mode used the standard macOS surfaces with the same accent and text.
        let light = ColorTheme.graphite.light
        #expect(light.windowBackground == nil)
        #expect(light.cardBackground == nil)
        #expect(light.border == nil)
        #expect(light.accent == ThemeRGB(0x4FB89F))
        #expect(light.secondaryText == ThemeRGB(0x8A8F98))
    }

    @Test("Every theme has its own accent in each mode")
    func testDistinctAccents() {
        for isDark in [true, false] {
            let accents = ColorTheme.allCases.map { $0.surfaces(isDark: isDark).accent.hex }
            #expect(Set(accents).count == accents.count)
        }
    }

    @Test("The new themes tint every light-mode surface", arguments: [ColorTheme.slate, .moss, .ember])
    func testNewThemesHaveLightSurfaces(theme: ColorTheme) {
        #expect(theme.light.windowBackground != nil)
        #expect(theme.light.cardBackground != nil)
        #expect(theme.light.border != nil)
    }

    @Test("The new themes stay readable in both modes",
          arguments: [ColorTheme.slate, .moss, .ember], [true, false])
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
          arguments: [ColorTheme.slate, .moss, .ember])
    func testLightAccentDarker(theme: ColorTheme) {
        #expect(theme.light.accent.relativeLuminance < theme.dark.accent.relativeLuminance)
    }

    @Test("Text on the fixed graphite tiles stays readable in every theme")
    func testFixedTileText() {
        // The tile and its text are fixed, so this holds whatever the theme or mode.
        #expect(ThemeRGB.fixedDarkTileText.contrast(with: ThemeRGB.fixedDarkTile) >= 4.5)
        #expect(ThemeRGB.fixedDarkTile == ColorTheme.graphite.dark.windowBackground)
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
        #expect(ColorThemeStore(defaults: defaults).load() == .graphite)
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
        #expect(ColorThemeStore(defaults: defaults).load() == .graphite)
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
        #expect(controller.theme == .graphite)

        controller.select(.ember)
        #expect(controller.theme == .ember)
        #expect(ThemeController.active.theme == .ember)
        #expect(ColorThemeStore(defaults: defaults).load() == .ember)
    }
}
