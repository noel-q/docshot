import Foundation
import Testing
@testable import ClipboardKit

/// Text recognised in images (C4a).
@Suite("Recognised text")
struct RecognisedTextTests {
    @Test("Images wait to be read once; their text is searchable, counts towards storage, and goes with the item")
    func recognisedText() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let store = try ClipboardStore(directory: folder.url)
        try await store.add(.image(data: Data(repeating: 1, count: 100), typeIdentifier: "public.png"), sourceApp: nil)
        try await store.add(.text("unrelated note"), sourceApp: nil)
        let image = try #require(await store.items.first { $0.kind == .image })
        #expect(try await store.imagesAwaitingText() == [image.id])
        #expect(try await store.search("invoice").isEmpty)

        try await store.setRecognisedText(image.id, "Invoice 42 from Café Noir")
        #expect(try await store.imagesAwaitingText().isEmpty)
        #expect(try await store.search("cafe invoice") == [image.id], "accents and case ignored, every word must match")
        #expect(try await store.recognisedText(image.id) == "Invoice 42 from Café Noir")
        #expect(await store.items.first { $0.id == image.id }?.byteSize == 100 + "Invoice 42 from Café Noir".utf8.count)

        // Read once: a second result is ignored.
        try await store.setRecognisedText(image.id, "other")
        #expect(try await store.recognisedText(image.id) == "Invoice 42 from Café Noir")

        try await store.delete(image.id)
        #expect(try await store.recognisedText(image.id) == nil)
    }

    @Test("An image with no text is read once and not again; text items are never queued")
    func emptyText() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        do {
            let store = try ClipboardStore(directory: folder.url)
            try await store.add(.image(data: Data(repeating: 2, count: 50), typeIdentifier: "public.png"), sourceApp: nil)
            let id = try #require(await store.items.first?.id)
            try await store.setRecognisedText(id, "")
        }
        let reopened = try ClipboardStore(directory: folder.url)
        #expect(try await reopened.imagesAwaitingText().isEmpty)
    }
}
