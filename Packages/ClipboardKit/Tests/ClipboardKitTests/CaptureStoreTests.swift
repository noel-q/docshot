import Foundation
import SQLite3
import Testing
@testable import ClipboardKit

/// Captures in the history store (C4 plan, 25 November 2026).
@Suite("Captures")
struct CaptureStoreTests {
    let png = Data(repeating: 7, count: 1_000)

    func screenshot(_ daysAgo: Double, bytes: Int = 10) -> CaptureItem {
        CaptureItem(
            id: UUID(), createdAt: referenceDate.addingTimeInterval(-days(daysAgo)), kind: .screenshot,
            pixelWidth: 10, pixelHeight: 10, byteSize: bytes, imageFile: "x.png", filePath: nil
        )
    }

    func recording(_ daysAgo: Double) -> CaptureItem {
        CaptureItem(
            id: UUID(), createdAt: referenceDate.addingTimeInterval(-days(daysAgo)), kind: .recording,
            pixelWidth: 0, pixelHeight: 0, byteSize: 0, imageFile: nil, filePath: "/tmp/r\(daysAgo).mp4"
        )
    }

    @Test("Limits keep the 20 newest of each kind, drop old ones, and shed the oldest screenshots over the cap")
    func limits() {
        let shots = (0..<25).map { screenshot(Double($0) / 10) }
        let movies = (0..<22).map { recording(Double($0) / 10) }
        let removed = CaptureRetention.toRemove(shots + movies, limits: .standard, historyBytes: 0, now: referenceDate)
        #expect(removed == Set(shots.suffix(5).map(\.id) + movies.suffix(2).map(\.id)))

        let old = screenshot(31)
        #expect(CaptureRetention.toRemove([old], limits: .standard, historyBytes: 0, now: referenceDate) == [old.id])

        let limits = RetentionLimits(maxItems: 200, maxAge: days(30), maxBytes: 100)
        let newer = screenshot(1, bytes: 40), older = screenshot(2, bytes: 40)
        let movie = recording(3)
        // History takes 50 of 100: only the newer screenshot fits; recordings take no space.
        #expect(CaptureRetention.toRemove([newer, older, movie], limits: limits, historyBytes: 50, now: referenceDate) == [older.id])
    }

    @Test("Clear keeps 5 or 10 of each kind, and none for pinned only or nothing")
    func clearRules() {
        let shots = (0..<12).map { screenshot(Double($0)) }
        let movies = (0..<3).map { recording(Double($0)) }
        let all = shots + movies
        #expect(CaptureRetention.toRemoveOnClear(all, keep: .lastFive) == Set(shots.dropFirst(5).map(\.id)))
        #expect(CaptureRetention.toRemoveOnClear(all, keep: .lastTen) == Set(shots.dropFirst(10).map(\.id)))
        #expect(CaptureRetention.toRemoveOnClear(all, keep: .pinnedOnly) == Set(all.map(\.id)))
        #expect(CaptureRetention.toRemoveOnClear(all, keep: .nothing) == Set(all.map(\.id)))
    }

    @Test("A screenshot keeps its image and annotations, survives reopening, and its file goes with it")
    func screenshotRoundTrip() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        var id = UUID()
        do {
            let store = try ClipboardStore(directory: folder.url)
            id = try await store.addScreenshot(png: png, pixelWidth: 40, pixelHeight: 30, annotations: Data("[]".utf8))
            try await store.updateCaptureAnnotations(id, Data("[1]".utf8))
            try await store.addRecordingReference(path: "/tmp/a.mp4")
            try await store.addRecordingReference(path: "/tmp/a.mp4")
        }
        let store = try ClipboardStore(directory: folder.url)
        let captures = await store.captures
        #expect(captures.count == 2)
        #expect(captures.filter { $0.kind == .recording }.count == 1, "saving to the same path again does not add a second row")
        #expect(try await store.captureAnnotations(id) == Data("[1]".utf8))
        let file = try #require(await store.captureImageURL(id))
        #expect(try Data(contentsOf: file) == png)
        #expect(await store.captureBytes == png.count)

        try await store.deleteCapture(id)
        #expect(!FileManager.default.fileExists(atPath: file.path))
        #expect(await store.captures.count == 1)
    }

    @Test("Clear removes captures with history, files included; keep nothing leaves no capture file")
    func clearRemovesFiles() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let store = try ClipboardStore(directory: folder.url)
        for _ in 0..<3 {
            try await store.addScreenshot(png: png, pixelWidth: 1, pixelHeight: 1)
        }
        try await store.add(.text("hello"), sourceApp: nil)
        try await store.clear(keeping: .nothing)
        #expect(await store.captures.isEmpty)
        #expect(await store.items.isEmpty)
        let files = try FileManager.default.contentsOfDirectory(
            atPath: folder.url.appendingPathComponent(ClipboardStore.capturesFolderName).path
        )
        #expect(files.isEmpty)
    }

    @Test("A schema 1 database gains captures and keeps its items; stray capture files are removed on open")
    func migrationFromOne() async throws {
        let folder = try TemporaryDirectory()
        defer { folder.remove() }
        let path = folder.url.appendingPathComponent(ClipboardStore.databaseName).path
        var db: OpaquePointer?
        sqlite3_open(path, &db)
        sqlite3_exec(db, """
            CREATE TABLE items (id TEXT PRIMARY KEY NOT NULL, created_at REAL NOT NULL, last_used_at REAL NOT NULL,
              kind TEXT NOT NULL, content_hash TEXT NOT NULL UNIQUE, source_app TEXT, pinned INTEGER NOT NULL DEFAULT 0,
              byte_size INTEGER NOT NULL, preview TEXT NOT NULL, payload_text TEXT, payload_blob BLOB,
              payload_type TEXT, payload_file TEXT);
            INSERT INTO items VALUES ('\(UUID().uuidString)', 1, 1, 'text', 'h', NULL, 0, 5, 'hello', 'hello', NULL, NULL, NULL);
            PRAGMA user_version = 1;
            """, nil, nil, nil)
        sqlite3_close(db)
        let captures = folder.url.appendingPathComponent(ClipboardStore.capturesFolderName)
        try FileManager.default.createDirectory(at: captures, withIntermediateDirectories: true)
        try png.write(to: captures.appendingPathComponent("stray.png"))

        let store = try ClipboardStore(directory: folder.url)
        #expect(await store.items.count == 1)
        #expect(await store.captures.isEmpty)
        #expect(try FileManager.default.contentsOfDirectory(atPath: captures.path).isEmpty)
        try await store.addScreenshot(png: png, pixelWidth: 1, pixelHeight: 1)
        #expect(await store.captures.count == 1)
    }
}
