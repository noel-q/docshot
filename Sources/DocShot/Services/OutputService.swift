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

/// Copy GIF (26 November 2026): puts a short recording on the clipboard as an animated GIF.
/// The GIF goes on the clipboard twice over: as a file, which Messages, Slack, Mail and Finder
/// paste with its animation, and as GIF data for apps that read images directly. The file lives
/// in DocShot's caches and only the last copied GIF is kept.
public enum GIFClipboard {
    public static let fileName = "DocShot Recording.gif"
    public static let gifType = NSPasteboard.PasteboardType("com.compuserve.gif")

    /// `~/Library/Caches/DocShot/Copied GIF`.
    public static func defaultFolder() throws -> URL {
        let caches = try FileManager.default.url(
            for: .cachesDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        return caches.appendingPathComponent("DocShot/Copied GIF", isDirectory: true)
    }

    /// Moves `gifURL` into `folder`, replacing the last copied GIF, and writes it to
    /// `pasteboard`. Returns where the GIF now is.
    @discardableResult
    public static func copy(gifAt gifURL: URL, into folder: URL, pasteboard: NSPasteboard = .general) throws -> URL {
        let fileManager = FileManager.default
        try fileManager.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let destination = folder.appendingPathComponent(fileName)
        let data = try Data(contentsOf: gifURL)
        if fileManager.fileExists(atPath: destination.path) {
            try fileManager.removeItem(at: destination)
        }
        try fileManager.moveItem(at: gifURL, to: destination)

        let item = NSPasteboardItem()
        item.setString(destination.absoluteString, forType: .fileURL)
        item.setData(data, forType: gifType)
        pasteboard.clearContents()
        guard pasteboard.writeObjects([item]) else {
            throw GIFClipboardError.refused
        }
        return destination
    }
}

public enum GIFClipboardError: LocalizedError {
    case refused

    public var errorDescription: String? {
        "The clipboard did not take the GIF."
    }
}
