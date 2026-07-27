import Foundation
import AppKit

public enum OutputFolderMode: String, Codable, Sendable {
    case askWhereToSave = "askWhereToSave"
    case useDefaultFolder = "useDefaultFolder"
}

public final class OutputFolderService: @unchecked Sendable {
    public static let shared = OutputFolderService()
    
    private let defaults: UserDefaults
    private let optionKey = "DocShotOutputFolderOption"
    private let bookmarkKey = "DocShotOutputFolderBookmark"
    private let pathKey = "DocShotOutputFolderPath"
    
    public init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
    }
    
    public var currentMode: OutputFolderMode {
        get {
            guard let raw = defaults.string(forKey: optionKey),
                  let mode = OutputFolderMode(rawValue: raw) else {
                return .askWhereToSave
            }
            return mode
        }
        set {
            defaults.set(newValue.rawValue, forKey: optionKey)
        }
    }
    
    public var displayPath: String? {
        return defaults.string(forKey: pathKey)
    }
    
    public func setModeAskWhereToSave() {
        currentMode = .askWhereToSave
    }
    
    public func saveFolderURL(_ url: URL) throws {
        let normalizedURL = url.standardizedFileURL.resolvingSymlinksInPath()
        let bookmarkData = try normalizedURL.bookmarkData(
            options: .withSecurityScope,
            includingResourceValuesForKeys: nil,
            relativeTo: nil
        )
        defaults.set(bookmarkData, forKey: bookmarkKey)
        defaults.set(normalizedURL.path, forKey: pathKey)
        currentMode = .useDefaultFolder
    }
    
    public func clearSavedFolder() {
        defaults.removeObject(forKey: bookmarkKey)
        defaults.removeObject(forKey: pathKey)
        currentMode = .askWhereToSave
    }
    
    public func resolveDefaultFolderURL() -> (url: URL?, staleReason: String?) {
        guard currentMode == .useDefaultFolder else {
            return (nil, nil)
        }
        
        guard let bookmarkData = defaults.data(forKey: bookmarkKey) else {
            clearSavedFolder()
            return (nil, "No folder bookmark was saved. Default reset to 'Ask where to save'.")
        }
        
        var isStale = false
        do {
            let url = try URL(
                resolvingBookmarkData: bookmarkData,
                options: .withSecurityScope,
                relativeTo: nil,
                bookmarkDataIsStale: &isStale
            )
            
            if isStale {
                clearSavedFolder()
                return (nil, "The selected default folder bookmark is stale. Default reset to 'Ask where to save'.")
            }
            
            var isDir: ObjCBool = false
            guard FileManager.default.fileExists(atPath: url.path, isDirectory: &isDir), isDir.boolValue else {
                clearSavedFolder()
                return (nil, "The default folder no longer exists on disk. Default reset to 'Ask where to save'.")
            }
            
            return (url, nil)
        } catch {
            clearSavedFolder()
            return (nil, "Could not access default folder (\(error.localizedDescription)). Default reset to 'Ask where to save'.")
        }
    }
    
    @MainActor
    public func selectDefaultFolder(parentWindow: NSWindow? = nil) async -> (url: URL?, errorMessage: String?) {
        let panel = NSOpenPanel()
        panel.title = "Select Default Save Folder"
        panel.message = "Choose a default folder where DocShot will open save panels."
        panel.prompt = "Select Folder"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        
        let response: NSApplication.ModalResponse
        if let parentWindow, parentWindow.isVisible {
            response = await panel.beginSheetModal(for: parentWindow)
        } else {
            response = panel.runModal()
        }
        
        guard response == .OK, let selectedURL = panel.url else {
            return (nil, nil)
        }
        
        do {
            try saveFolderURL(selectedURL)
            return (selectedURL, nil)
        } catch {
            return (nil, "Could not save folder bookmark: \(error.localizedDescription)")
        }
    }
    
    @MainActor
    public func createDocShotFolder(parentWindow: NSWindow? = nil) async -> (url: URL?, errorMessage: String?) {
        let panel = NSOpenPanel()
        panel.title = "Select Parent Location for DocShot Folder"
        panel.message = "Choose a parent location to explicitly create the DocShot folder."
        panel.prompt = "Choose Parent Location"
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        
        let response: NSApplication.ModalResponse
        if let parentWindow, parentWindow.isVisible {
            response = await panel.beginSheetModal(for: parentWindow)
        } else {
            response = panel.runModal()
        }
        
        guard response == .OK, let parentURL = panel.url else {
            return (nil, nil)
        }
        
        let targetURL = parentURL.appendingPathComponent("DocShot", isDirectory: true)

        // Check what's already there before asking for confirmation, so the alert says
        // something true: creating a new folder and reusing an existing one are different
        // actions, and a file occupying that name isn't something we can safely proceed with.
        var isDir: ObjCBool = false
        let alreadyExists = FileManager.default.fileExists(atPath: targetURL.path, isDirectory: &isDir)

        if alreadyExists && !isDir.boolValue {
            return (nil, "A file named 'DocShot' already exists at \(parentURL.path) and isn't a folder. Choose a different location or rename that file.")
        }

        // Ask for explicit confirmation before creating (or reusing) the folder
        let alert = NSAlert()
        if alreadyExists {
            alert.messageText = "Use Existing DocShot Folder?"
            alert.informativeText = "A 'DocShot' folder already exists inside:\n\(parentURL.path)\n\nUse it as your default save folder."
            alert.addButton(withTitle: "Use Folder")
        } else {
            alert.messageText = "Create DocShot Folder?"
            alert.informativeText = "Create a dedicated 'DocShot' folder inside:\n\(parentURL.path)"
            alert.addButton(withTitle: "Create Folder")
        }
        alert.addButton(withTitle: "Cancel")
        alert.alertStyle = .informational

        let alertResponse: NSApplication.ModalResponse
        if let parentWindow, parentWindow.isVisible {
            alertResponse = await alert.beginSheetModal(for: parentWindow)
        } else {
            alertResponse = alert.runModal()
        }

        guard alertResponse == .alertFirstButtonReturn else {
            return (nil, nil)
        }

        let parentAccessing = parentURL.startAccessingSecurityScopedResource()
        defer {
            if parentAccessing {
                parentURL.stopAccessingSecurityScopedResource()
            }
        }

        do {
            if !alreadyExists {
                try FileManager.default.createDirectory(at: targetURL, withIntermediateDirectories: true)
            }
            try saveFolderURL(targetURL)
            return (targetURL, nil)
        } catch {
            return (nil, "Could not create DocShot folder: \(error.localizedDescription)")
        }
    }
    
    public func revealInFinder() -> String? {
        let (url, staleReason) = resolveDefaultFolderURL()
        guard let url else {
            return staleReason ?? "No default folder set."
        }
        
        let accessing = url.startAccessingSecurityScopedResource()
        defer {
            if accessing {
                url.stopAccessingSecurityScopedResource()
            }
        }
        
        NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path)
        return nil
    }
}
