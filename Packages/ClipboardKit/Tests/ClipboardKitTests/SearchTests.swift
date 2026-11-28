import Foundation
import Testing
@testable import ClipboardKit

@Suite("Search")
struct SearchTests {

    @Test("Case, accents and width are ignored")
    func testFolding() {
        let text = SearchText.fold("Café Crème ＡＢＣ")
        #expect(SearchText.matches(text, terms: SearchText.terms("cafe")))
        #expect(SearchText.matches(text, terms: SearchText.terms("CRÈME")))
        #expect(SearchText.matches(text, terms: SearchText.terms("abc")))
    }

    @Test("Every word must match, in any order")
    func testAllWords() {
        let text = SearchText.fold("quarterly report for the board")
        #expect(SearchText.matches(text, terms: SearchText.terms("board  report")))
        #expect(!SearchText.matches(text, terms: SearchText.terms("board budget")))
        #expect(SearchText.terms("   ").isEmpty)
    }

    @Test("Files by path, colours by code, images by nothing")
    func testSearchableContent() {
        let files = SearchText.searchable(.fileURLs([URL(fileURLWithPath: "/tmp/Annual Report.pdf")]))
        #expect(files.contains("Annual Report.pdf"))
        #expect(SearchText.searchable(.colour(ClipColour(red: 1, green: 0, blue: 0))).lowercased().contains("ff0000"))
        #expect(SearchText.searchable(.image(data: Data([1]), typeIdentifier: "public.png")).isEmpty)
        #expect(SearchText.searchable(.richText(rtf: Data(), plainText: "Bold words")) == "Bold words")
    }

    @Test("The store finds items by full text, newest first, and keeps up after changes")
    func testStoreSearch() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let store = try ClipboardStore(directory: folder.url)
        let long = String(repeating: "padding ", count: 100) + "needle at the end"
        try await store.add(.text(long), sourceApp: nil, now: referenceDate)
        try await store.add(.fileURLs([URL(fileURLWithPath: "/tmp/Needle Notes.txt")]), sourceApp: nil,
                            now: referenceDate.addingTimeInterval(1))
        try await store.add(.text("unrelated"), sourceApp: nil, now: referenceDate.addingTimeInterval(2))

        let items = await store.items
        // Beyond the 200-character preview, so only the full text can match.
        #expect(try await store.search("NEEDLE") == [items[1].id, items[2].id])
        #expect(try await store.search("") == items.map(\.id))

        // The index built by that search follows later adds and deletes.
        try await store.add(.text("a needle too"), sourceApp: nil, now: referenceDate.addingTimeInterval(3))
        try await store.delete(items[1].id, now: referenceDate)
        let after = await store.items
        #expect(try await store.search("needle") == [after[0].id, items[2].id])
    }

    @Test("Search works the same on a reopened store")
    func testSearchAfterReopen() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        do {
            let store = try ClipboardStore(directory: folder.url)
            try await store.add(.richText(rtf: Data("{\\rtf1 x}".utf8), plainText: "Résumé draft"), sourceApp: nil, now: referenceDate)
            try await store.add(.colour(ClipColour(red: 0.2, green: 0.6, blue: 0.4)), sourceApp: nil, now: referenceDate)
        }
        let reopened = try ClipboardStore(directory: folder.url)
        #expect(try await reopened.search("resume").count == 1)
        #expect(try await reopened.search("339966").count == 1)
    }

    @Test("Search stays right after Clear, retention by new limits, and a released index")
    func testSearchAfterRemovals() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let store = try ClipboardStore(directory: folder.url)
        for index in 0..<5 {
            try await store.add(.text("word \(index)"), sourceApp: nil, now: referenceDate.addingTimeInterval(Double(index)))
        }
        #expect(try await store.search("word").count == 5)

        try await store.setLimits(RetentionLimits(maxItems: 3, maxAge: days(30), maxBytes: 1_000_000), now: referenceDate)
        #expect(try await store.search("word").count == 3)
        #expect(try await store.search("word 0").isEmpty)

        let newest = try #require(await store.items.first)
        try await store.pin(newest.id, now: referenceDate)
        try await store.clear(keeping: .pinnedOnly, now: referenceDate)
        #expect(try await store.search("word") == [newest.id])

        await store.releaseSearchIndex()
        try await store.add(.text("word again"), sourceApp: nil, now: referenceDate.addingTimeInterval(10))
        #expect(try await store.search("word").count == 2)
    }
}
