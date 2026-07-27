import Foundation

public enum TemporaryRecordingStoreError: Error, Equatable, LocalizedError {
    case cannotCreateDirectory(String)
    case moveFailed(String)

    public var errorDescription: String? {
        switch self {
        case .cannotCreateDirectory(let detail):
            return "Could not prepare the temporary recordings folder: \(detail)"
        case .moveFailed(let detail):
            return "Could not move the recording: \(detail)"
        }
    }
}

/// Where a recording lives between Stop and the user's explicit Save or Discard.
public protocol TemporaryRecordingStore: Sendable {
    /// A unique, not-yet-existing MP4 URL inside DocShot's own temporary directory.
    func makeMP4URL() throws -> URL
    func makeGIFURL() throws -> URL

    /// Deletes a temporary recording. Idempotent, and refuses any URL DocShot does not own.
    func removeIfPresent(_ url: URL)

    /// Moves a temporary recording to the destination the user chose in the save panel.
    func move(_ source: URL, to destination: URL) throws

    /// Removes every temporary recording DocShot owns, and nothing else.
    func purgeOwnedTemporaries()
}

/// The production store: one private directory under the system temporary directory.
///
/// `removeIfPresent` and `purgeOwnedTemporaries` only ever touch `.mp4` files sitting directly
/// inside that directory. A URL outside it — most importantly the destination the user just chose
/// in the save panel — cannot be deleted through this type at all.
public final class FileManagerTemporaryRecordingStore: TemporaryRecordingStore, @unchecked Sendable {
    public static let directoryName = "DocShot-Recordings"
    public static let fileExtension = "mp4"
    public static let gifExtension = "gif"

    public let rootDirectory: URL
    private let fileManager: FileManager

    /// - Parameter rootDirectory: overridden in tests; production uses the system temporary
    ///   directory so nothing is ever written inside the user's own folders.
    public init(rootDirectory: URL? = nil, fileManager: FileManager = .default) {
        self.fileManager = fileManager
        self.rootDirectory = rootDirectory ?? fileManager.temporaryDirectory
            .appendingPathComponent(FileManagerTemporaryRecordingStore.directoryName, isDirectory: true)
    }

    public func makeMP4URL() throws -> URL {
        try makeURL(withExtension: Self.fileExtension)
    }

    public func makeGIFURL() throws -> URL {
        try makeURL(withExtension: Self.gifExtension)
    }

    private func makeURL(withExtension extension: String) throws -> URL {
        try createRootIfNeeded()

        var candidate = url(forName: UUID().uuidString, extension: `extension`)
        while fileManager.fileExists(atPath: candidate.path) {
            candidate = url(forName: UUID().uuidString, extension: `extension`)
        }
        return candidate
    }

    public func removeIfPresent(_ url: URL) {
        guard owns(url) else { return }
        try? fileManager.removeItem(at: url)
    }

    public func move(_ source: URL, to destination: URL) throws {
        guard fileManager.fileExists(atPath: source.path) else {
            throw TemporaryRecordingStoreError.moveFailed("The temporary recording no longer exists.")
        }

        do {
            if fileManager.fileExists(atPath: destination.path) {
                // The save panel already obtained the user's overwrite confirmation.
                _ = try fileManager.replaceItemAt(destination, withItemAt: source)
            } else {
                try fileManager.moveItem(at: source, to: destination)
            }
        } catch {
            throw TemporaryRecordingStoreError.moveFailed(error.localizedDescription)
        }
    }

    public func purgeOwnedTemporaries() {
        guard let contents = try? fileManager.contentsOfDirectory(
            at: rootDirectory,
            includingPropertiesForKeys: nil,
            options: [.skipsSubdirectoryDescendants, .skipsHiddenFiles]
        ) else {
            return
        }

        for url in contents where owns(url) {
            try? fileManager.removeItem(at: url)
        }
    }

    // MARK: - Ownership

    /// True only for `.mp4` files sitting directly inside this store's own directory.
    private func owns(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        guard [FileManagerTemporaryRecordingStore.fileExtension, FileManagerTemporaryRecordingStore.gifExtension]
            .contains(url.pathExtension.lowercased()) else {
            return false
        }
        let parent = url.standardizedFileURL.deletingLastPathComponent().standardizedFileURL
        return parent.path == rootDirectory.standardizedFileURL.path
    }

    private func url(forName name: String, extension: String) -> URL {
        rootDirectory
            .appendingPathComponent(name)
            .appendingPathExtension(`extension`)
    }

    private func createRootIfNeeded() throws {
        var isDirectory: ObjCBool = false
        if fileManager.fileExists(atPath: rootDirectory.path, isDirectory: &isDirectory) {
            guard isDirectory.boolValue else {
                throw TemporaryRecordingStoreError.cannotCreateDirectory(
                    "A file already exists at \(rootDirectory.path)."
                )
            }
            return
        }

        do {
            try fileManager.createDirectory(
                at: rootDirectory,
                withIntermediateDirectories: true,
                attributes: [.posixPermissions: 0o700]
            )
        } catch {
            throw TemporaryRecordingStoreError.cannotCreateDirectory(error.localizedDescription)
        }
    }
}
