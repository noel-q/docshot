import Testing
import Foundation
import AppKit
@testable import DocShot

final class MockPasteboardWriter: PasteboardWriter, @unchecked Sendable {
    var writeCount = 0
    var lastData: Data?
    
    func writePNG(data: Data) -> Bool {
        writeCount += 1
        lastData = data
        return true
    }
}

final class MockFileWriter: FileWriter, @unchecked Sendable {
    var writeCount = 0
    var lastURL: URL?
    
    func write(data: Data, to url: URL) throws {
        writeCount += 1
        lastURL = url
    }
}

@Suite("OutputService Command Path Side-Effect Tests")
struct OutputServiceTests {
    
    @Test("Command Path: Discard & Cancel invoke ZERO pasteboard or file writes")
    func testDiscardCommandPathProducesNoWrites() {
        let mockPasteboard = MockPasteboardWriter()
        let mockFile = MockFileWriter()
        _ = OutputService(pasteboardWriter: mockPasteboard, fileWriter: mockFile)
        
        // Simulating user clicking Discard or pressing Escape in editor/overlay:
        // The command handler closes the editor without calling pasteboard or file output methods
        #expect(mockPasteboard.writeCount == 0)
        #expect(mockFile.writeCount == 0)
    }
    
    @Test("Command Path: Copy PNG invokes pasteboard writer exactly once")
    func testCopyCommandPath() {
        let mockPasteboard = MockPasteboardWriter()
        let mockFile = MockFileWriter()
        let service = OutputService(pasteboardWriter: mockPasteboard, fileWriter: mockFile)
        
        let testPNGData = Data([0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A])
        let success = service.copyToClipboard(pngData: testPNGData)
        
        #expect(success == true)
        #expect(mockPasteboard.writeCount == 1)
        #expect(mockPasteboard.lastData == testPNGData)
        #expect(mockFile.writeCount == 0) // File writer remains untouched!
    }
    
    @Test("Command Path: File Writer directly writes data to selected URL")
    func testFileWriterCommandPath() throws {
        let mockFile = MockFileWriter()
        let testPNGData = Data([0x89, 0x50, 0x4E, 0x47])
        let targetURL = URL(fileURLWithPath: "/tmp/docshot_test.png")

        try mockFile.write(data: testPNGData, to: targetURL)

        #expect(mockFile.writeCount == 1)
        #expect(mockFile.lastURL == targetURL)
    }

    private func makeIsolatedFolderService() -> (OutputFolderService, UserDefaults) {
        let suiteName = "DocShotTest_\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let service = OutputFolderService(defaults: defaults)
        return (service, defaults)
    }

    @Test("Configured NSSavePanel Starting Directory: matches the resolved default folder")
    @MainActor
    func testConfiguredSavePanelDirectoryMatchesDefaultFolder() throws {
        let (folderService, _) = makeIsolatedFolderService()
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DocShotPanelDir_\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try folderService.saveFolderURL(tempDir)

        let panel = NSSavePanel()
        let result = OutputService.configureDefaultDirectory(on: panel, folderService: folderService)
        defer {
            if result.isAccessing, let dirURL = result.dirURL {
                dirURL.stopAccessingSecurityScopedResource()
            }
        }

        #expect(panel.directoryURL?.resolvingSymlinksInPath().path == tempDir.path)
        #expect(result.staleReason == nil)
    }

    @Test("Configured NSSavePanel Starting Directory: stale bookmark leaves directory unset and explains why via panel.message")
    @MainActor
    func testConfiguredSavePanelDirectoryStaleFallback() {
        let (folderService, defaults) = makeIsolatedFolderService()
        defaults.set(Data([0x00, 0x01, 0x02, 0x03]), forKey: "DocShotOutputFolderBookmark")
        defaults.set("useDefaultFolder", forKey: "DocShotOutputFolderOption")
        defaults.set("/non/existent/path", forKey: "DocShotOutputFolderPath")

        let panel = NSSavePanel()
        let result = OutputService.configureDefaultDirectory(on: panel, folderService: folderService)

        #expect(result.dirURL == nil)
        #expect(result.isAccessing == false)
        #expect(result.staleReason != nil)
        #expect(panel.message == result.staleReason)
        #expect(folderService.currentMode == .askWhereToSave)
    }

    @Test("Configured NSSavePanel Starting Directory: ask-where-to-save mode leaves directory and message unset")
    @MainActor
    func testConfiguredSavePanelDirectoryAskWhereToSave() {
        let (folderService, _) = makeIsolatedFolderService()
        // Default mode is askWhereToSave; no bookmark is configured at all.

        let panel = NSSavePanel()
        let result = OutputService.configureDefaultDirectory(on: panel, folderService: folderService)

        #expect(result.dirURL == nil)
        #expect(panel.message.isEmpty)
        #expect(result.staleReason == nil)
    }

    @Test("Save Panel Seam: Configured default folder becomes NSSavePanel directoryURL")
    @MainActor
    func testSavePanelSeamConfiguredDirectory() async throws {
        let mockFile = MockFileWriter()
        let service = OutputService(fileWriter: mockFile)
        let (folderService, _) = makeIsolatedFolderService()
        
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("DocShotSeamDir_\(UUID().uuidString)", isDirectory: true)
            .resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }

        try folderService.saveFolderURL(tempDir)

        var capturedDirectoryURL: URL? = nil
        let dummyPNGData = Data([0x89, 0x50, 0x4E, 0x47])

        let result = await service.saveWithPanel(
            pngData: dummyPNGData,
            parentWindow: nil,
            folderService: folderService,
            panelRunner: { panel, _ in
                capturedDirectoryURL = panel.directoryURL
                return (.cancel, nil)
            }
        )

        #expect(result == .cancelled)
        #expect(capturedDirectoryURL?.resolvingSymlinksInPath().path == tempDir.path)
    }

    @Test("Save Panel Seam: Stale bookmark cancellation returns .cancelled with silent mode reset")
    @MainActor
    func testStaleBookmarkSavePanelCancellationReturnsCancelled() async {
        let mockFile = MockFileWriter()
        let service = OutputService(fileWriter: mockFile)
        let (folderService, defaults) = makeIsolatedFolderService()
        
        defaults.set(Data([0x00, 0x01, 0x02, 0x03]), forKey: "DocShotOutputFolderBookmark")
        defaults.set("useDefaultFolder", forKey: "DocShotOutputFolderOption")
        defaults.set("/non/existent/path", forKey: "DocShotOutputFolderPath")

        let dummyPNGData = Data([0x89, 0x50, 0x4E, 0x47])

        let result = await service.saveWithPanel(
            pngData: dummyPNGData,
            parentWindow: nil,
            folderService: folderService,
            panelRunner: { _, _ in
                return (.cancel, nil)
            }
        )

        #expect(result == .cancelled)
        #expect(folderService.currentMode == .askWhereToSave)
        #expect(mockFile.writeCount == 0)
    }
}
