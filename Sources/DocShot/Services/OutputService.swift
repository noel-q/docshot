import Foundation
import AppKit

public protocol PasteboardWriter: Sendable {
    @discardableResult
    func writePNG(data: Data) -> Bool
}

public protocol FileWriter: Sendable {
    func write(data: Data, to url: URL) throws
}

public struct StandardPasteboardWriter: PasteboardWriter {
    public init() {}
    public func writePNG(data: Data) -> Bool {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        // Publish one canonical representation. Writing an NSImage after the
        // PNG can replace the raw PNG payload with an AppKit representation,
        // causing consumers to receive an unexpected thumbnail or blank image.
        return pasteboard.setData(data, forType: .png)
    }
}

public struct StandardFileWriter: FileWriter {
    public init() {}
    public func write(data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
    }
}

public enum SaveResult: Equatable, Sendable {
    case saved(URL)
    case cancelled
    case failed(String)
}

public final class OutputService: @unchecked Sendable {
    public static let shared = OutputService()
    
    private let pasteboardWriter: PasteboardWriter
    private let fileWriter: FileWriter
    
    public typealias SavePanelRunner = @MainActor (NSSavePanel, NSWindow?) async -> (response: NSApplication.ModalResponse, targetURL: URL?)
    
    @MainActor
    public static let defaultSavePanelRunner: SavePanelRunner = { panel, parentWindow in
        let response: NSApplication.ModalResponse
        if let parent = parentWindow, parent.isVisible {
            response = await panel.beginSheetModal(for: parent)
        } else {
            response = panel.runModal()
        }
        return (response, panel.url)
    }
    
    public init(pasteboardWriter: PasteboardWriter = StandardPasteboardWriter(), fileWriter: FileWriter = StandardFileWriter()) {
        self.pasteboardWriter = pasteboardWriter
        self.fileWriter = fileWriter
    }
    
    @discardableResult
    public func copyToClipboard(pngData: Data) -> Bool {
        return pasteboardWriter.writePNG(data: pngData)
    }

    /// Result of applying the configured default folder to a save panel's starting directory.
    public struct DirectoryConfigurationResult: Equatable, Sendable {
        public let dirURL: URL?
        public let isAccessing: Bool
        public let staleReason: String?
    }

    /// Applies the configured default folder (if any) to `panel.directoryURL`, or -- when the
    /// saved bookmark is stale/unavailable -- explains why via `panel.message` and leaves the
    /// panel's directory unset so it falls back to the system's normal recent-location default.
    @MainActor
    @discardableResult
    public static func configureDefaultDirectory(
        on panel: NSSavePanel,
        folderService: OutputFolderService
    ) -> DirectoryConfigurationResult {
        let (dirURL, staleReason) = folderService.resolveDefaultFolderURL()
        var isAccessing = false

        if let dirURL {
            isAccessing = dirURL.startAccessingSecurityScopedResource()
            panel.directoryURL = dirURL
        } else if let staleReason {
            panel.message = staleReason
        }

        return DirectoryConfigurationResult(dirURL: dirURL, isAccessing: isAccessing, staleReason: staleReason)
    }

    @MainActor
    public func saveWithPanel(
        pngData: Data,
        parentWindow: NSWindow?,
        suggestedFileName: String? = nil,
        folderService: OutputFolderService = .shared,
        panelRunner: SavePanelRunner = OutputService.defaultSavePanelRunner
    ) async -> SaveResult {
        let savePanel = NSSavePanel()
        savePanel.allowedContentTypes = [.png]
        savePanel.canCreateDirectories = true
        savePanel.isExtensionHidden = false

        let directoryConfig = OutputService.configureDefaultDirectory(on: savePanel, folderService: folderService)

        defer {
            if directoryConfig.isAccessing, let dirURL = directoryConfig.dirURL {
                dirURL.stopAccessingSecurityScopedResource()
            }
        }

        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let timestamp = formatter.string(from: Date())
        savePanel.nameFieldStringValue = suggestedFileName ?? "DocShot \(timestamp).png"
        
        let (response, targetURL) = await panelRunner(savePanel, parentWindow)
        
        if response == .OK, let targetURL {
            do {
                try fileWriter.write(data: pngData, to: targetURL)
                return .saved(targetURL)
            } catch {
                return .failed("Failed to save image: \(error.localizedDescription)")
            }
        }

        // A deliberate cancel is always .cancelled, even after a stale-bookmark fallback
        return .cancelled
    }
}
