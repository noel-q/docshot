import Foundation
import AppKit
import UniformTypeIdentifiers

/// Writes a finished recording to a destination the user explicitly chose.
public protocol MovieSaving: Sendable {
    @MainActor
    func save(_ recording: TemporaryRecording, parent: NSWindow?) async -> SaveResult
}

/// Saves an MP4 through a native save panel, reusing the screenshot pipeline's default-folder
/// behaviour so both outputs start in the same place.
///
/// Nothing here writes a file until the panel returns `.OK` with a URL. A cancelled panel and a
/// failed move both leave the temporary recording intact, so the user can retry or discard it —
/// neither is treated as a discard.
public final class SavePanelMovieSaver: MovieSaving, @unchecked Sendable {
    private let store: any TemporaryRecordingStore
    private let folderService: OutputFolderService
    private let panelRunner: OutputService.SavePanelRunner?
    private let clock: @Sendable () -> Date

    /// - Parameter panelRunner: injected in tests. `nil` uses the app's real save panel.
    public init(
        store: any TemporaryRecordingStore,
        folderService: OutputFolderService = .shared,
        panelRunner: OutputService.SavePanelRunner? = nil,
        clock: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.store = store
        self.folderService = folderService
        self.panelRunner = panelRunner
        self.clock = clock
    }

    public static func suggestedFileName(at date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        return "DocShot Recording \(formatter.string(from: date)).mp4"
    }

    @MainActor
    public func save(_ recording: TemporaryRecording, parent: NSWindow?) async -> SaveResult {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.mpeg4Movie]
        panel.canCreateDirectories = true
        panel.isExtensionHidden = false
        panel.nameFieldStringValue = SavePanelMovieSaver.suggestedFileName(at: clock())

        let directoryConfig = OutputService.configureDefaultDirectory(
            on: panel,
            folderService: folderService
        )
        defer {
            if directoryConfig.isAccessing, let dirURL = directoryConfig.dirURL {
                dirURL.stopAccessingSecurityScopedResource()
            }
        }

        let runner = panelRunner ?? OutputService.defaultSavePanelRunner
        let (response, targetURL) = await runner(panel, parent)

        guard response == .OK, let targetURL else {
            return .cancelled
        }

        do {
            try store.move(recording.url, to: targetURL)
            return .saved(targetURL)
        } catch {
            return .failed(error.localizedDescription)
        }
    }
}
