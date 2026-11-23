import Foundation
import SQLite3
import Testing
@testable import ClipboardKit

/// Every test uses its own temporary folder, never Application Support.
@Suite("Clipboard store")
struct ClipboardStoreTests {

    func imageFiles(in directory: URL) -> [String] {
        let images = directory.appendingPathComponent(ClipboardStore.imagesFolderName)
        return ((try? FileManager.default.contentsOfDirectory(atPath: images.path)) ?? []).sorted()
    }

    @Test("History survives closing and reopening the store")
    func testSurvivesReopen() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }

        do {
            let store = try ClipboardStore(directory: folder.url)
            try await store.add(.text("first"), sourceApp: "com.apple.TextEdit", now: referenceDate)
            try await store.add(.text("second"), sourceApp: nil, now: referenceDate.addingTimeInterval(1))
            let first = try #require(await store.items.last)
            try await store.pin(first.id, now: referenceDate)
        }

        let reopened = try ClipboardStore(directory: folder.url)
        let items = await reopened.items
        #expect(items.map(\.preview) == ["second", "first"])
        #expect(items.last?.pinned == true)
        #expect(items.last?.sourceApp == "com.apple.TextEdit")
        #expect(items.last?.createdAt == referenceDate)
    }

    @Test("Every kind of content reads back exactly")
    func testPayloadRoundTrip() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let contents: [ClipContent] = [
            .text("plain ✓\nwith lines"),
            .richText(rtf: Data("{\\rtf1 bold}".utf8), plainText: "bold"),
            .image(data: samplePNG, typeIdentifier: "public.png"),
            .fileURLs([URL(fileURLWithPath: "/Users/x/a b.txt"), URL(fileURLWithPath: "/tmp/c.pdf")]),
            .colour(ClipColour(red: 0.25, green: 0.5, blue: 0.75, alpha: 1)),
        ]

        let store = try ClipboardStore(directory: folder.url)
        for (index, content) in contents.enumerated() {
            try await store.add(content, sourceApp: nil, now: referenceDate.addingTimeInterval(Double(index)))
        }

        let reopened = try ClipboardStore(directory: folder.url)
        for item in await reopened.items {
            let content = try await reopened.content(for: item.id)
            #expect(contents.contains(content))
            #expect(content.kind == item.kind)
        }
        #expect(await reopened.items.count == contents.count)
    }

    @Test("A duplicate copy moves the stored item to the top and stays one row")
    func testDuplicateStored() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let store = try ClipboardStore(directory: folder.url)
        try await store.add(.text("same"), sourceApp: nil, now: referenceDate)
        try await store.add(.text("other"), sourceApp: nil, now: referenceDate.addingTimeInterval(1))
        let outcome = try await store.add(.text("same"), sourceApp: nil, now: referenceDate.addingTimeInterval(2))
        guard case .movedToTop = outcome else {
            Issue.record("expected .movedToTop, got \(outcome)")
            return
        }

        let reopened = try ClipboardStore(directory: folder.url)
        #expect(await reopened.items.map(\.preview) == ["same", "other"])
    }

    @Test("Images are saved as files beside the database and removed with their item")
    func testImageFiles() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let store = try ClipboardStore(directory: folder.url)
        try await store.add(.image(data: samplePNG, typeIdentifier: "public.png"), sourceApp: nil, now: referenceDate)
        let item = try #require(await store.items.first)
        #expect(imageFiles(in: folder.url) == [item.contentHash + ".png"])

        try await store.delete(item.id)
        #expect(imageFiles(in: folder.url).isEmpty)
        #expect(await store.items.isEmpty)
    }

    @Test("Clear removes images from disk and keeps pinned items")
    func testClearRemovesFiles() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let store = try ClipboardStore(directory: folder.url)
        try await store.add(.image(data: samplePNG, typeIdentifier: "public.png"), sourceApp: nil, now: referenceDate)
        try await store.add(.text("keep me"), sourceApp: nil, now: referenceDate.addingTimeInterval(1))
        let keep = try #require(await store.items.first)
        try await store.pin(keep.id)

        let outcome = try await store.clear(keeping: .pinnedOnly)
        #expect(outcome == .removed(count: 1))
        #expect(imageFiles(in: folder.url).isEmpty)
        let reopened = try ClipboardStore(directory: folder.url)
        #expect(await reopened.items.map(\.preview) == ["keep me"])
    }

    @Test("Retention removes stale items and their files from disk")
    func testRetentionOnDisk() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let store = try ClipboardStore(directory: folder.url)
        try await store.add(.image(data: samplePNG, typeIdentifier: "public.png"), sourceApp: nil, now: referenceDate)
        try await store.add(.text("new"), sourceApp: nil, now: referenceDate.addingTimeInterval(days(29)))

        let outcome = try await store.applyRetention(now: referenceDate.addingTimeInterval(days(31)))
        #expect(outcome == .removed(count: 1))
        #expect(imageFiles(in: folder.url).isEmpty)
        let reopened = try ClipboardStore(directory: folder.url)
        #expect(await reopened.items.map(\.preview) == ["new"])
    }

    @Test("Tighter limits apply at once")
    func testSetLimits() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let store = try ClipboardStore(directory: folder.url)
        for index in 0..<5 {
            try await store.add(.text("item \(index)"), sourceApp: nil, now: referenceDate.addingTimeInterval(Double(index)))
        }
        try await store.setLimits(RetentionLimits(maxItems: 2, maxAge: days(30), maxBytes: 1_000_000), now: referenceDate.addingTimeInterval(10))
        #expect(await store.items.map(\.preview) == ["item 4", "item 3"])
    }

    @Test("A skipped copy writes nothing")
    func testSkippedWritesNothing() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let tiny = RetentionLimits(maxItems: 200, maxAge: days(30), maxBytes: 4)
        let store = try ClipboardStore(directory: folder.url, limits: tiny)
        try await store.add(.text("abcd"), sourceApp: nil, now: referenceDate)
        let first = try #require(await store.items.first)
        try await store.pin(first.id)

        let outcome = try await store.add(.image(data: samplePNG, typeIdentifier: "public.png"), sourceApp: nil, now: referenceDate)
        #expect(outcome == .skipped(.storageFull))
        #expect(imageFiles(in: folder.url).isEmpty)
        #expect(await store.items.count == 1)
    }

    @Test("Image files no item refers to are removed on open")
    func testOrphanCleanup() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        do {
            let store = try ClipboardStore(directory: folder.url)
            try await store.add(.image(data: samplePNG, typeIdentifier: "public.png"), sourceApp: nil, now: referenceDate)
        }
        let orphan = folder.url.appendingPathComponent(ClipboardStore.imagesFolderName).appendingPathComponent("orphan.png")
        try samplePNG.write(to: orphan)

        let reopened = try ClipboardStore(directory: folder.url)
        let item = try #require(await reopened.items.first)
        #expect(imageFiles(in: folder.url) == [item.contentHash + ".png"])
    }

    @Test("A missing image file is reported, not crashed on")
    func testMissingImage() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let store = try ClipboardStore(directory: folder.url)
        try await store.add(.image(data: samplePNG, typeIdentifier: "public.png"), sourceApp: nil, now: referenceDate)
        let item = try #require(await store.items.first)
        let file = folder.url.appendingPathComponent(ClipboardStore.imagesFolderName).appendingPathComponent(item.contentHash + ".png")
        try FileManager.default.removeItem(at: file)

        await #expect(throws: ClipboardStoreError.payloadMissing(item.id)) {
            try await store.content(for: item.id)
        }
        await #expect(throws: ClipboardStoreError.notFound(UUID(uuidString: "00000000-0000-0000-0000-000000000000")!)) {
            try await store.content(for: UUID(uuidString: "00000000-0000-0000-0000-000000000000")!)
        }
    }

    @Test("A database from a newer version is refused and left untouched")
    func testNewerSchema() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let path = folder.url.appendingPathComponent(ClipboardStore.databaseName).path
        var db: OpaquePointer?
        #expect(sqlite3_open(path, &db) == SQLITE_OK)
        #expect(sqlite3_exec(db, "PRAGMA user_version = 99", nil, nil, nil) == SQLITE_OK)
        sqlite3_close(db)

        #expect(throws: ClipboardStoreError.unsupportedSchema(found: 99)) {
            _ = try ClipboardStore(directory: folder.url)
        }
    }

    @Test("A new store is at schema version 1 and its folders are private")
    func testSchemaAndPermissions() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let storeFolder = folder.url.appendingPathComponent("Clipboard", isDirectory: true)
        _ = try ClipboardStore(directory: storeFolder)

        var db: OpaquePointer?
        #expect(sqlite3_open(storeFolder.appendingPathComponent(ClipboardStore.databaseName).path, &db) == SQLITE_OK)
        var statement: OpaquePointer?
        sqlite3_prepare_v2(db, "PRAGMA user_version", -1, &statement, nil)
        #expect(sqlite3_step(statement) == SQLITE_ROW)
        #expect(sqlite3_column_int(statement, 0) == ClipboardStore.schemaVersion)
        sqlite3_finalize(statement)
        sqlite3_close(db)

        let attributes = try FileManager.default.attributesOfItem(atPath: storeFolder.path)
        #expect((attributes[.posixPermissions] as? NSNumber)?.intValue == 0o700)
    }

    @Test("The default folder is Application Support/DocShot/Clipboard")
    func testDefaultDirectory() throws {
        // Reads the path only; nothing is created inside it.
        let url = try ClipboardStore.defaultDirectory()
        #expect(url.path.hasSuffix("Application Support/DocShot/Clipboard"))
    }
}
