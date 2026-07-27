import Testing
import Foundation
import AppKit
@testable import DocShot

@Suite("OutputFolderService Tests")
struct OutputFolderServiceTests {
    
    private func makeIsolatedService() -> (OutputFolderService, UserDefaults) {
        let suiteName = "DocShotTest_\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let service = OutputFolderService(defaults: defaults)
        return (service, defaults)
    }
    
    @Test("Folder Preference Persistence: Default mode is askWhereToSave")
    func testDefaultModeIsAskWhereToSave() {
        let (service, _) = makeIsolatedService()
        #expect(service.currentMode == .askWhereToSave)
        #expect(service.displayPath == nil)
    }
    
    @Test("Folder Preference Persistence: Saving folder sets mode to useDefaultFolder")
    func testSavingFolderURL() throws {
        let (service, _) = makeIsolatedService()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("DocShotTestFolder_\(UUID().uuidString)", isDirectory: true).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        try service.saveFolderURL(tempDir)
        
        #expect(service.currentMode == .useDefaultFolder)
        #expect(service.displayPath == tempDir.path)
        
        let (resolvedURL, staleReason) = service.resolveDefaultFolderURL()
        #expect(resolvedURL?.resolvingSymlinksInPath().path == tempDir.path)
        #expect(staleReason == nil)
    }
    
    @Test("Stale-Bookmark Fallback: Deleted folder falls back to askWhereToSave with explanation")
    func testDeletedFolderFallback() throws {
        let (service, _) = makeIsolatedService()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("DocShotDeleteMe_\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        
        try service.saveFolderURL(tempDir)
        #expect(service.currentMode == .useDefaultFolder)
        
        // Remove directory from disk to simulate missing/stale folder
        try FileManager.default.removeItem(at: tempDir)
        
        let (resolvedURL, staleReason) = service.resolveDefaultFolderURL()
        #expect(resolvedURL == nil)
        #expect(staleReason != nil)
        #expect(service.currentMode == .askWhereToSave)
    }
    
    @Test("Stale-Bookmark Fallback: Corrupted bookmark data falls back cleanly")
    func testCorruptedBookmarkFallback() {
        let (service, defaults) = makeIsolatedService()
        defaults.set(Data([0x00, 0x01, 0x02, 0x03]), forKey: "DocShotOutputFolderBookmark")
        defaults.set("useDefaultFolder", forKey: "DocShotOutputFolderOption")
        defaults.set("/non/existent/path", forKey: "DocShotOutputFolderPath")
        
        let (resolvedURL, staleReason) = service.resolveDefaultFolderURL()
        #expect(resolvedURL == nil)
        #expect(staleReason != nil)
        #expect(service.currentMode == .askWhereToSave)
    }
    
    @Test("Configured Directory URL Resolution: Resolved directory matches configured default folder")
    func testOutputServiceDirectoryResolution() throws {
        let (service, _) = makeIsolatedService()
        let tempDir = FileManager.default.temporaryDirectory.appendingPathComponent("DocShotTarget_\(UUID().uuidString)", isDirectory: true).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: tempDir) }
        
        try service.saveFolderURL(tempDir)
        
        let (dirURL, staleReason) = service.resolveDefaultFolderURL()
        #expect(dirURL?.resolvingSymlinksInPath().path == tempDir.path)
        #expect(staleReason == nil)
    }
}
