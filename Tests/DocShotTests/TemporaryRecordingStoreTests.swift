import Testing
import Foundation
@testable import DocShot

/// Temporary media lifecycle: unique files, idempotent deletion, an ownership boundary that
/// makes deleting a user's own file impossible, and a purge that touches nothing else.
@Suite("TemporaryRecordingStore Tests")
struct TemporaryRecordingStoreTests {

    private func makeStore() -> (FileManagerTemporaryRecordingStore, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DocShotStoreTest_\(UUID().uuidString)", isDirectory: true)
        return (FileManagerTemporaryRecordingStore(rootDirectory: root), root)
    }

    private func write(_ contents: String, to url: URL) throws {
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data(contents.utf8).write(to: url)
    }

    @Test("A new URL is unique, ends in .mp4, and does not create the file")
    func testMakeMP4URL() throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let first = try store.makeMP4URL()
        let second = try store.makeMP4URL()

        #expect(first != second)
        #expect(first.pathExtension == "mp4")
        #expect(first.deletingLastPathComponent().standardizedFileURL == root.standardizedFileURL)
        #expect(FileManager.default.fileExists(atPath: first.path) == false)

        var isDirectory: ObjCBool = false
        #expect(FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory))
        #expect(isDirectory.boolValue)
    }

    @Test("Removing an owned recording is idempotent")
    func testRemoveIsIdempotent() throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let url = try store.makeMP4URL()
        try write("clip", to: url)
        #expect(FileManager.default.fileExists(atPath: url.path))

        store.removeIfPresent(url)
        store.removeIfPresent(url)

        #expect(FileManager.default.fileExists(atPath: url.path) == false)
    }

    @Test("A file outside the store cannot be deleted through it")
    func testRemoveRefusesForeignFiles() throws {
        let (store, root) = makeStore()
        let elsewhere = FileManager.default.temporaryDirectory
            .appendingPathComponent("DocShotForeign_\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("user-movie.mp4")
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: elsewhere.deletingLastPathComponent())
        }

        try write("the user's own file", to: elsewhere)

        store.removeIfPresent(elsewhere)

        #expect(
            FileManager.default.fileExists(atPath: elsewhere.path),
            "A saved destination must never be deletable through the temporary store"
        )
    }

    @Test("A non-MP4 file inside the store is not treated as ours")
    func testRemoveRefusesNonMP4() throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        _ = try store.makeMP4URL()
        let notes = root.appendingPathComponent("notes.txt")
        try write("not a recording", to: notes)

        store.removeIfPresent(notes)

        #expect(FileManager.default.fileExists(atPath: notes.path))
    }

    @Test("Moving a recording consumes the temporary file")
    func testMoveConsumesTemporary() throws {
        let (store, root) = makeStore()
        let destinationDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DocShotDest_\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: destinationDirectory)
        }
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        let source = try store.makeMP4URL()
        try write("clip", to: source)
        let destination = destinationDirectory.appendingPathComponent("Saved.mp4")

        try store.move(source, to: destination)

        #expect(FileManager.default.fileExists(atPath: source.path) == false)
        #expect(try String(contentsOf: destination, encoding: .utf8) == "clip")
    }

    @Test("Moving over an existing file replaces it")
    func testMoveReplacesExistingDestination() throws {
        let (store, root) = makeStore()
        let destinationDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DocShotDest_\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: destinationDirectory)
        }
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        let destination = destinationDirectory.appendingPathComponent("Saved.mp4")
        try write("older", to: destination)

        let source = try store.makeMP4URL()
        try write("newer", to: source)

        try store.move(source, to: destination)

        #expect(try String(contentsOf: destination, encoding: .utf8) == "newer")
        #expect(FileManager.default.fileExists(atPath: source.path) == false)
    }

    @Test("Moving a recording that no longer exists reports a move failure")
    func testMoveMissingSourceThrows() throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let source = try store.makeMP4URL()
        let destination = root.appendingPathComponent("Saved.mp4")

        #expect(throws: TemporaryRecordingStoreError.self) {
            try store.move(source, to: destination)
        }
    }

    @Test("Purging removes DocShot's own recordings and nothing else")
    func testPurgeRemovesOnlyOwnedRecordings() throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let first = try store.makeMP4URL()
        let second = try store.makeMP4URL()
        try write("a", to: first)
        try write("b", to: second)

        let foreignFile = root.appendingPathComponent("readme.txt")
        try write("keep me", to: foreignFile)
        let subdirectory = root.appendingPathComponent("nested", isDirectory: true)
        try write("nested clip", to: subdirectory.appendingPathComponent("inner.mp4"))

        store.purgeOwnedTemporaries()

        #expect(FileManager.default.fileExists(atPath: first.path) == false)
        #expect(FileManager.default.fileExists(atPath: second.path) == false)
        #expect(FileManager.default.fileExists(atPath: foreignFile.path))
        #expect(FileManager.default.fileExists(atPath: subdirectory.appendingPathComponent("inner.mp4").path))
    }

    @Test("Purging when nothing was ever recorded is harmless")
    func testPurgeWithoutDirectoryIsHarmless() {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        store.purgeOwnedTemporaries()

        #expect(FileManager.default.fileExists(atPath: root.path) == false)
    }
}
