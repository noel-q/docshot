import Foundation
import SQLite3
import Testing
@testable import ClipboardKit

/// Failure paths and privacy guarantees of the store (from the C1 review).
@Suite("Clipboard store hardening")
struct ClipboardStoreHardeningTests {

    func permissions(_ url: URL) throws -> Int? {
        (try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? NSNumber)?.intValue
    }

    func rawSQL(_ path: String, _ sql: String) {
        var db: OpaquePointer?
        sqlite3_open(path, &db)
        sqlite3_exec(db, sql, nil, nil, nil)
        sqlite3_close(db)
    }

    @Test("Text containing NUL or nothing at all is stored whole")
    func testUnusualText() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let texts = ["before\u{0}after", "", "emoji 🙂 and ünïcödé"]
        do {
            let store = try ClipboardStore(directory: folder.url)
            for (index, text) in texts.enumerated() {
                try await store.add(.text(text), sourceApp: nil, now: referenceDate.addingTimeInterval(Double(index)))
            }
        }
        let reopened = try ClipboardStore(directory: folder.url)
        var readBack: [String] = []
        for item in await reopened.items {
            if case .text(let text) = try await reopened.content(for: item.id) { readBack.append(text) }
        }
        #expect(Set(readBack) == Set(texts))
    }

    @Test("A newer database is refused without being changed")
    func testNewerSchemaUntouched() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let path = folder.url.appendingPathComponent(ClipboardStore.databaseName).path
        rawSQL(path, "CREATE TABLE future (x); PRAGMA user_version = 7;")
        let before = try Data(contentsOf: URL(fileURLWithPath: path))

        #expect(throws: ClipboardStoreError.unsupportedSchema(found: 7)) {
            _ = try ClipboardStore(directory: folder.url)
        }
        #expect(try Data(contentsOf: URL(fileURLWithPath: path)) == before)
        #expect(!FileManager.default.fileExists(atPath: path + "-wal"))
    }

    @Test("Existing folders with wider permissions are tightened to owner-only")
    func testTightensExistingFolders() throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let images = folder.url.appendingPathComponent(ClipboardStore.imagesFolderName)
        try FileManager.default.createDirectory(at: images, withIntermediateDirectories: true)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: folder.url.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: images.path)

        _ = try ClipboardStore(directory: folder.url)
        #expect(try permissions(folder.url) == 0o700)
        #expect(try permissions(images) == 0o700)
    }

    @Test("An unreadable row is removed on open, so its content can be recorded again")
    func testUnreadableRow() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let content = ClipContent.image(data: samplePNG, typeIdentifier: "public.png")
        do {
            _ = try ClipboardStore(directory: folder.url)
        }
        // A row with an unknown kind holding this content's fingerprint and image file.
        let fileName = content.contentHash + ".png"
        let images = folder.url.appendingPathComponent(ClipboardStore.imagesFolderName)
        try samplePNG.write(to: images.appendingPathComponent(fileName))
        rawSQL(folder.url.appendingPathComponent(ClipboardStore.databaseName).path, """
            INSERT INTO items (id, created_at, last_used_at, kind, content_hash, pinned, byte_size, preview, payload_file)
            VALUES ('\(UUID().uuidString)', 0, 0, 'hologram', '\(content.contentHash)', 0, 1, '', '\(fileName)');
            """)

        let store = try ClipboardStore(directory: folder.url)
        #expect(await store.items.isEmpty)
        let outcome = try await store.add(content, sourceApp: nil, now: referenceDate)
        guard case .added = outcome else {
            Issue.record("expected .added, got \(outcome)")
            return
        }
        let item = try #require(await store.items.first)
        #expect(try await store.content(for: item.id) == content)
    }

    @Test("A failed write leaves history and disk as they were, and the store keeps working")
    func testFailedWriteRollsBack() async throws {
        let folder = try TemporaryDirectory()
        let images = folder.url.appendingPathComponent(ClipboardStore.imagesFolderName)
        defer {
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: images.path)
            folder.remove()
        }
        let store = try ClipboardStore(directory: folder.url)
        try await store.add(.text("kept"), sourceApp: nil, now: referenceDate)

        // The image cannot be written, so the insert fails part-way through the transaction.
        try FileManager.default.setAttributes([.posixPermissions: 0o500], ofItemAtPath: images.path)
        await #expect(throws: (any Error).self) {
            try await store.add(.image(data: samplePNG, typeIdentifier: "public.png"), sourceApp: nil, now: referenceDate.addingTimeInterval(1))
        }
        #expect(await store.items.map(\.preview) == ["kept"])

        // No transaction was left open: later writes still work and persist.
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: images.path)
        try await store.add(.text("after"), sourceApp: nil, now: referenceDate.addingTimeInterval(2))
        let reopened = try ClipboardStore(directory: folder.url)
        #expect(await reopened.items.map(\.preview) == ["after", "kept"])
    }

    @Test("Deleted text leaves no trace in the database or its log")
    func testDeletedTextGone() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let secret = "DOCSHOT-TEST-MARKER-7f3a9c"
        let store = try ClipboardStore(directory: folder.url)
        try await store.add(.text(secret), sourceApp: nil, now: referenceDate)
        try await store.add(.text("ordinary"), sourceApp: nil, now: referenceDate.addingTimeInterval(1))
        let secretItem = try #require(await store.items.first { $0.preview == secret })
        try await store.delete(secretItem.id)

        let marker = Data(secret.utf8)
        for name in [ClipboardStore.databaseName, ClipboardStore.databaseName + "-wal"] {
            let url = folder.url.appendingPathComponent(name)
            guard let bytes = try? Data(contentsOf: url) else { continue }
            #expect(bytes.range(of: marker) == nil, "found deleted text in \(name)")
        }
    }

    @Test("New limits are kept once applied")
    func testSetLimitsKept() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let store = try ClipboardStore(directory: folder.url)
        let tighter = RetentionLimits(maxItems: 3, maxAge: days(7), maxBytes: 1000)
        try await store.setLimits(tighter, now: referenceDate)
        #expect(await store.limits == tighter)
    }
}
