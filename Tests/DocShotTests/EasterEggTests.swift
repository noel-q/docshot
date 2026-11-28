import Testing
import Foundation
@testable import DocShot

@Suite("Easter Egg Tests")
struct EasterEggTests {

    // MARK: - Search phrases

    @Test("Each phrase is found when it is the whole search, in any case and spacing")
    func testPhrases() {
        #expect(SearchEgg.egg(forQuery: "hello docshot") == .hello)
        #expect(SearchEgg.egg(forQuery: "  Hello   DocShot ") == .hello)
        #expect(SearchEgg.egg(forQuery: "IN BLOOM") == .bloom)
        #expect(SearchEgg.egg(forQuery: "made by noel") == .signature)
    }

    @Test("Ordinary searches never show an egg",
          arguments: ["", "noel", "hello", "docshot", "bloom", "made by", "made by noel's team",
                      "hello docshot!", "say hello docshot", "in-bloom", "madebynoel"])
    func testNoAccidents(query: String) {
        #expect(SearchEgg.egg(forQuery: query) == nil)
    }

    @Test("Egg words are plain: no exclamation marks or emoji")
    func testWording() {
        for egg in SearchEgg.allCases {
            #expect(!egg.title.contains("!"))
            #expect(!egg.detail.contains("!"))
            #expect(!(egg.title + egg.detail).unicodeScalars.contains { $0.properties.isEmojiPresentation })
        }
        #expect(SearchEgg.signature.title == "Made quietly by Noel.")
        #expect(!(KonamiEgg.title + KonamiEgg.detail).contains("!"))
    }

    // MARK: - Konami code

    private func run(_ keys: [KonamiKey?], gap: TimeInterval = 0.2, from start: TimeInterval = 100,
                     tracker: inout KonamiTracker) -> [Bool] {
        keys.enumerated().map { index, key in tracker.record(key, at: start + Double(index) * gap) }
    }

    @Test("The full code fires once, on the final A")
    func testFullCode() {
        var tracker = KonamiTracker()
        let results = run(KonamiTracker.sequence, tracker: &tracker)
        #expect(results == Array(repeating: false, count: 9) + [true])
    }

    @Test("Another key in between starts it again")
    func testInterrupted() {
        var tracker = KonamiTracker()
        var keys: [KonamiKey?] = KonamiTracker.sequence
        keys.insert(nil, at: 5)
        #expect(!run(keys, tracker: &tracker).contains(true))
    }

    @Test("Too slow between two keys starts it again")
    func testTooSlow() {
        var tracker = KonamiTracker()
        #expect(!run(KonamiTracker.sequence, gap: 1.6, tracker: &tracker).contains(true))
        var quick = KonamiTracker()
        #expect(run(KonamiTracker.sequence, gap: 1.4, tracker: &quick).last == true)
    }

    @Test("Extra ups before the code still count")
    func testExtraUps() {
        var tracker = KonamiTracker()
        #expect(run([.up, .up, .up] + KonamiTracker.sequence.dropFirst(2), tracker: &tracker).last == true)
    }

    @Test("It must be typed in full again to fire again")
    func testFiresOnce() {
        var tracker = KonamiTracker()
        _ = run(KonamiTracker.sequence, tracker: &tracker)
        #expect(tracker.record(.a, at: 200) == false)
        #expect(run(KonamiTracker.sequence, from: 300, tracker: &tracker).last == true)
    }

    @Test("Only plain keys count")
    func testKeyMapping() {
        #expect(KonamiKey.from(keyCode: 126, characters: "", hasModifiers: false) == .up)
        #expect(KonamiKey.from(keyCode: 0, characters: "a", hasModifiers: false) == .a)
        #expect(KonamiKey.from(keyCode: 0, characters: "a", hasModifiers: true) == nil)
        #expect(KonamiKey.from(keyCode: 126, characters: "", hasModifiers: true) == nil)
        #expect(KonamiKey.from(keyCode: 8, characters: "c", hasModifiers: false) == nil)
    }

    // MARK: - Hidden themes

    @Test("Rose and Lavender are hidden until unlocked")
    func testHiddenChoices() {
        #expect(ColorTheme.choices(includingHidden: false) == [.ember, .tide, .slate, .moss])
        #expect(ColorTheme.choices(includingHidden: true) == [.ember, .tide, .slate, .moss, .rose, .lavender])
    }

    @Test("Unlocking is saved, and a saved hidden theme counts as unlocked")
    func testUnlockStore() throws {
        let suite = "DocShotEggTests-\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = ColorThemeStore(defaults: defaults)
        #expect(!store.hiddenThemesUnlocked())
        store.unlockHiddenThemes()
        #expect(store.hiddenThemesUnlocked())

        let other = "DocShotEggTests-\(UUID().uuidString)"
        let otherDefaults = try #require(UserDefaults(suiteName: other))
        defer { otherDefaults.removePersistentDomain(forName: other) }
        ColorThemeStore(defaults: otherDefaults).save(.rose)
        #expect(ColorThemeStore(defaults: otherDefaults).hiddenThemesUnlocked())
    }
}
