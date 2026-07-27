import Testing
import Foundation
import AppKit
import UniformTypeIdentifiers
@testable import DocShot

/// Saving an MP4 is explicit on every path: a cancelled panel and a failed move both leave the
/// temporary recording intact, and neither writes anything to disk.
@Suite("Recording Output Service Tests")
struct RecordingOutputServiceTests {

    private func makeStore() -> (FileManagerTemporaryRecordingStore, URL) {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("DocShotSaverTest_\(UUID().uuidString)", isDirectory: true)
        return (FileManagerTemporaryRecordingStore(rootDirectory: root), root)
    }

    private func makeRecording(in store: FileManagerTemporaryRecordingStore) throws -> TemporaryRecording {
        let url = try store.makeMP4URL()
        try Data("clip".utf8).write(to: url)
        return TemporaryRecording(
            url: url,
            duration: 4.5,
            pixelSize: CGSize(width: 400, height: 300),
            hasAudio: false,
            createdAt: Date()
        )
    }

    private func makeIsolatedFolderService() -> (OutputFolderService, UserDefaults) {
        let suiteName = "DocShotRecordingTest_\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        return (OutputFolderService(defaults: defaults), defaults)
    }

    @Test("A confirmed save moves the recording to the chosen destination")
    @MainActor
    func testConfirmedSaveMovesRecording() async throws {
        let (store, root) = makeStore()
        let destinationDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("DocShotSaved_\(UUID().uuidString)", isDirectory: true)
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: destinationDirectory)
        }
        try FileManager.default.createDirectory(at: destinationDirectory, withIntermediateDirectories: true)

        let recording = try makeRecording(in: store)
        let destination = destinationDirectory.appendingPathComponent("Recording.mp4")
        let (folderService, _) = makeIsolatedFolderService()

        let saver = SavePanelMovieSaver(
            store: store,
            folderService: folderService,
            panelRunner: { _, _ in (.OK, destination) }
        )

        let result = await saver.save(recording, parent: nil)

        #expect(result == .saved(destination))
        #expect(FileManager.default.fileExists(atPath: destination.path))
        #expect(FileManager.default.fileExists(atPath: recording.url.path) == false)
    }

    @Test("A cancelled panel writes nothing and keeps the recording")
    @MainActor
    func testCancelledPanelKeepsRecording() async throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let recording = try makeRecording(in: store)
        let (folderService, _) = makeIsolatedFolderService()

        let saver = SavePanelMovieSaver(
            store: store,
            folderService: folderService,
            panelRunner: { _, _ in (.cancel, nil) }
        )

        let result = await saver.save(recording, parent: nil)

        #expect(result == .cancelled)
        #expect(
            FileManager.default.fileExists(atPath: recording.url.path),
            "Cancelling the panel must not discard the recording"
        )
    }

    @Test("A failed move reports the failure and keeps the recording for a retry")
    @MainActor
    func testFailedMoveKeepsRecording() async throws {
        let (store, root) = makeStore()
        defer { try? FileManager.default.removeItem(at: root) }

        let recording = try makeRecording(in: store)
        let (folderService, _) = makeIsolatedFolderService()

        // A destination inside a directory that does not exist.
        let impossibleDestination = FileManager.default.temporaryDirectory
            .appendingPathComponent("DocShotMissing_\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("Recording.mp4")

        let saver = SavePanelMovieSaver(
            store: store,
            folderService: folderService,
            panelRunner: { _, _ in (.OK, impossibleDestination) }
        )

        let result = await saver.save(recording, parent: nil)

        switch result {
        case .failed(let message):
            #expect(message.isEmpty == false)
        case .saved, .cancelled:
            Issue.record("Expected a failed save, got \(result)")
        }
        #expect(FileManager.default.fileExists(atPath: recording.url.path))
    }

    @Test("The panel offers MP4 and starts in the configured default folder")
    @MainActor
    func testPanelConfiguration() async throws {
        let (store, root) = makeStore()
        let defaultFolder = FileManager.default.temporaryDirectory
            .appendingPathComponent("DocShotDefault_\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: defaultFolder)
        }
        try FileManager.default.createDirectory(at: defaultFolder, withIntermediateDirectories: true)

        let recording = try makeRecording(in: store)
        let (folderService, _) = makeIsolatedFolderService()
        try folderService.saveFolderURL(defaultFolder)

        var capturedTypes: [UTType] = []
        var capturedDirectory: URL?
        var capturedName = ""

        let saver = SavePanelMovieSaver(
            store: store,
            folderService: folderService,
            panelRunner: { panel, _ in
                capturedTypes = panel.allowedContentTypes
                capturedDirectory = panel.directoryURL
                capturedName = panel.nameFieldStringValue
                return (.cancel, nil)
            }
        )

        _ = await saver.save(recording, parent: nil)

        #expect(capturedTypes == [.mpeg4Movie])
        #expect(capturedDirectory?.resolvingSymlinksInPath().path == defaultFolder.path)
        #expect(capturedName.hasSuffix(".mp4"))
    }

    @Test("The suggested file name is a dated MP4 name")
    func testSuggestedFileName() {
        let name = SavePanelMovieSaver.suggestedFileName(at: Date(timeIntervalSince1970: 0))

        #expect(name.hasPrefix("DocShot Recording "))
        #expect(name.hasSuffix(".mp4"))
    }
}
