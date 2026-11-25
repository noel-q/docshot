import Foundation
import SQLite3

public enum ClipboardStoreError: Error, Equatable, Sendable {
    case openFailed(String)
    case sqlite(String)
    /// The database was written by a newer DocShot. It is left untouched.
    case unsupportedSchema(found: Int)
    case notFound(UUID)
    case payloadMissing(UUID)
}

/// Clipboard history on disk (plan section 4.2): one SQLite database, with image payloads saved
/// as files beside it. Every change runs through `HistoryReducer`, and its effects are applied in
/// one transaction, so the database and the in-memory list never disagree.
public actor ClipboardStore {
    /// 1: clipboard items (C1). 2: captures (C4).
    public static let schemaVersion: Int32 = 2
    public static let databaseName = "history.sqlite"
    public static let imagesFolderName = "Images"
    public static let capturesFolderName = "Captures"

    /// `~/Library/Application Support/DocShot/Clipboard`.
    public static func defaultDirectory() throws -> URL {
        let support = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        return support.appendingPathComponent("DocShot/Clipboard", isDirectory: true)
    }

    public nonisolated let directory: URL
    private let imagesDirectory: URL
    private let capturesDirectory: URL
    private let db: SQLiteConnection
    private var state: HistoryState
    /// Captures, newest first (C4).
    private var captureList: [CaptureItem]
    public private(set) var limits: RetentionLimits
    /// Folded searchable text by item, built on the first search and kept up to date after.
    private var searchIndex: [UUID: String]?

    /// Opens or creates the store in `directory`. On open it removes only rows this version
    /// cannot read (with their image) and image files no row refers to (left behind by a crash
    /// between writing a file and committing). A database from a newer version is refused
    /// without being changed.
    public init(directory: URL, limits: RetentionLimits = .standard) throws {
        let fileManager = FileManager.default
        let images = directory.appendingPathComponent(Self.imagesFolderName, isDirectory: true)
        let captures = directory.appendingPathComponent(Self.capturesFolderName, isDirectory: true)
        // History is private: owner-only folders, tightened even if they already existed.
        for folder in [directory, images, captures] {
            try fileManager.createDirectory(
                at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
            )
            try fileManager.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
        }

        let connection = try SQLiteConnection(path: directory.appendingPathComponent(Self.databaseName).path)
        // Refuses a newer database before anything below changes it.
        try Self.migrate(connection)
        try connection.execute("PRAGMA journal_mode = WAL")
        // Freed pages are zeroed, so deleted clips do not linger in the file.
        try connection.execute("PRAGMA secure_delete = ON")
        try Self.removeUnreadableRows(connection, imagesDirectory: images)
        let items = try Self.loadItems(connection)
        try Self.removeOrphanImages(connection, imagesDirectory: images)
        let captureItems = try Self.loadCaptures(connection, capturesDirectory: captures)
        Self.removeOrphanCaptureFiles(captureItems, capturesDirectory: captures)

        self.directory = directory
        self.imagesDirectory = images
        self.capturesDirectory = captures
        self.db = connection
        self.limits = limits
        self.state = HistoryState(items: items)
        self.captureList = captureItems
    }

    // MARK: - Reading

    /// Every item, most recently used first.
    public var items: [ClipItem] { state.items }

    public var totalBytes: Int { state.totalBytes }

    public func content(for id: UUID) throws -> ClipContent {
        guard let item = state.item(id) else { throw ClipboardStoreError.notFound(id) }
        let statement = try db.prepare(
            "SELECT payload_text, payload_blob, payload_type, payload_file FROM items WHERE id = ?"
        )
        try statement.bind(1, id.uuidString)
        guard try statement.step() else { throw ClipboardStoreError.notFound(id) }
        let text = statement.text(0)
        let blob = statement.blob(1)
        let type = statement.text(2)
        let file = statement.text(3)

        switch item.kind {
        case .text:
            guard let text else { throw ClipboardStoreError.payloadMissing(id) }
            return .text(text)
        case .richText:
            guard let blob, let text else { throw ClipboardStoreError.payloadMissing(id) }
            return .richText(rtf: blob, plainText: text)
        case .image:
            guard let file, let type,
                  let data = try? Data(contentsOf: imagesDirectory.appendingPathComponent(file)) else {
                throw ClipboardStoreError.payloadMissing(id)
            }
            return .image(data: data, typeIdentifier: type)
        case .fileURLs:
            guard let text else { throw ClipboardStoreError.payloadMissing(id) }
            return .fileURLs(text.split(separator: "\n").compactMap { URL(string: String($0)) })
        case .colour:
            guard let text, let colour = ClipColour(storageString: text) else {
                throw ClipboardStoreError.payloadMissing(id)
            }
            return .colour(colour)
        }
    }

    /// The saved file of an image item, for thumbnails; nil for other kinds or a missing file.
    public func imageFileURL(for id: UUID) throws -> URL? {
        guard state.item(id)?.kind == .image else { return nil }
        let statement = try db.prepare("SELECT payload_file FROM items WHERE id = ?")
        try statement.bind(1, id.uuidString)
        guard try statement.step(), let name = statement.text(0) else { return nil }
        let url = imagesDirectory.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    // MARK: - Search

    /// Ids of the items matching every word of `query`, most recently used first; every item
    /// for a blank query. Rules in `SearchText`.
    public func search(_ query: String) throws -> [UUID] {
        let terms = SearchText.terms(query)
        guard !terms.isEmpty else { return state.items.map(\.id) }
        let index = try loadSearchIndex()
        return state.items.compactMap { item in
            guard let text = index[item.id], SearchText.matches(text, terms: terms) else { return nil }
            return item.id
        }
    }

    /// Frees the search index; the next search rebuilds it. The app calls this when the window
    /// closes, so a large history's text is not held in memory twice between searches.
    public func releaseSearchIndex() {
        searchIndex = nil
    }

    private func loadSearchIndex() throws -> [UUID: String] {
        if let searchIndex { return searchIndex }
        var index: [UUID: String] = [:]
        let statement = try db.prepare("SELECT id, payload_text FROM items")
        while try statement.step() {
            guard let id = statement.text(0).flatMap(UUID.init(uuidString:)),
                  let item = state.item(id) else { continue }
            index[id] = SearchText.fold(
                SearchText.searchable(kind: item.kind, payloadText: statement.text(1), preview: item.preview)
            )
        }
        searchIndex = index
        return index
    }

    // MARK: - Changes

    /// Records a copy. Skipping by marker, app or pause happens before this, in `RecordingRules`.
    @discardableResult
    public func add(_ content: ClipContent, sourceApp: String?, now: Date = Date()) throws -> HistoryOutcome {
        try run(.add(content: content, sourceApp: sourceApp, id: UUID()), now: now, newContent: content)
    }

    @discardableResult
    public func markUsed(_ id: UUID, now: Date = Date()) throws -> HistoryOutcome {
        try run(.markUsed(id), now: now)
    }

    @discardableResult
    public func pin(_ id: UUID, now: Date = Date()) throws -> HistoryOutcome {
        try run(.pin(id), now: now)
    }

    @discardableResult
    public func unpin(_ id: UUID, now: Date = Date()) throws -> HistoryOutcome {
        try run(.unpin(id), now: now)
    }

    @discardableResult
    public func delete(_ id: UUID, now: Date = Date()) throws -> HistoryOutcome {
        try run(.delete(id), now: now)
    }

    /// One Clear removes history and captures together, keeping what `keep` says (C4 plan,
    /// decision 3).
    @discardableResult
    public func clear(keeping keep: ClearKeep, now: Date = Date()) throws -> HistoryOutcome {
        let outcome = try run(.clear(keep), now: now)
        try removeCaptures(CaptureRetention.toRemoveOnClear(captureList, keep: keep))
        return outcome
    }

    @discardableResult
    public func applyRetention(now: Date = Date()) throws -> HistoryOutcome {
        let outcome = try run(.applyRetention, now: now)
        try applyCaptureRetention(limits: limits, now: now)
        return outcome
    }

    /// New limits take effect at once.
    @discardableResult
    public func setLimits(_ newLimits: RetentionLimits, now: Date = Date()) throws -> HistoryOutcome {
        let outcome = try run(.applyRetention, now: now, limits: newLimits)
        limits = newLimits
        try applyCaptureRetention(limits: newLimits, now: now)
        return outcome
    }

    // MARK: - Captures (C4)

    /// Screenshots and recording references, newest first.
    public var captures: [CaptureItem] { captureList }

    /// Bytes the kept screenshots take on disk.
    public var captureBytes: Int { captureList.reduce(0) { $0 + $1.byteSize } }

    /// Keeps a screenshot: its PNG as a file, and the app's annotation state, if any.
    @discardableResult
    public func addScreenshot(
        png: Data, pixelWidth: Int, pixelHeight: Int, annotations: Data? = nil, now: Date = Date()
    ) throws -> UUID {
        let id = UUID()
        let name = id.uuidString + ".png"
        let url = capturesDirectory.appendingPathComponent(name)
        try png.write(to: url, options: .atomic)
        let item = CaptureItem(
            id: id, createdAt: now, kind: .screenshot, pixelWidth: pixelWidth, pixelHeight: pixelHeight,
            byteSize: png.count, imageFile: name, filePath: nil
        )
        do {
            try insertCapture(item, annotations: annotations)
        } catch {
            try? FileManager.default.removeItem(at: url)
            throw error
        }
        captureList.insert(item, at: 0)
        try applyCaptureRetention(limits: limits, now: now)
        return id
    }

    /// Keeps a saved recording by its path. Saving to the same path again moves it to the top.
    @discardableResult
    public func addRecordingReference(
        path: String, pixelWidth: Int = 0, pixelHeight: Int = 0, now: Date = Date()
    ) throws -> UUID {
        try removeCaptures(Set(captureList.filter { $0.kind == .recording && $0.filePath == path }.map(\.id)))
        let item = CaptureItem(
            id: UUID(), createdAt: now, kind: .recording, pixelWidth: pixelWidth, pixelHeight: pixelHeight,
            byteSize: 0, imageFile: nil, filePath: path
        )
        try insertCapture(item, annotations: nil)
        captureList.insert(item, at: 0)
        try applyCaptureRetention(limits: limits, now: now)
        return item.id
    }

    /// Replaces a screenshot's annotation state (the editor closed). A capture removed in the
    /// meantime is ignored.
    public func updateCaptureAnnotations(_ id: UUID, _ annotations: Data?) throws {
        guard captureList.contains(where: { $0.id == id }) else { return }
        let statement = try db.prepare("UPDATE captures SET annotations = ? WHERE id = ?")
        try statement.bind(1, annotations)
        try statement.bind(2, id.uuidString)
        try statement.run()
    }

    public func captureAnnotations(_ id: UUID) throws -> Data? {
        let statement = try db.prepare("SELECT annotations FROM captures WHERE id = ?")
        try statement.bind(1, id.uuidString)
        guard try statement.step() else { throw ClipboardStoreError.notFound(id) }
        return statement.blob(0)
    }

    /// A screenshot's image file; nil for a recording or a missing file.
    public func captureImageURL(_ id: UUID) -> URL? {
        guard let name = captureList.first(where: { $0.id == id })?.imageFile else { return nil }
        let url = capturesDirectory.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    public func deleteCapture(_ id: UUID) throws {
        try removeCaptures([id])
    }

    private func applyCaptureRetention(limits: RetentionLimits, now: Date) throws {
        try removeCaptures(CaptureRetention.toRemove(captureList, limits: limits, historyBytes: state.totalBytes, now: now))
    }

    private func insertCapture(_ item: CaptureItem, annotations: Data?) throws {
        let statement = try db.prepare("""
            INSERT INTO captures (id, created_at, kind, pixel_width, pixel_height, byte_size, image_file,
                                  file_path, annotations)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
            """)
        try statement.bind(1, item.id.uuidString)
        try statement.bind(2, item.createdAt.timeIntervalSince1970)
        try statement.bind(3, item.kind.rawValue)
        try statement.bind(4, item.pixelWidth)
        try statement.bind(5, item.pixelHeight)
        try statement.bind(6, item.byteSize)
        try statement.bind(7, item.imageFile)
        try statement.bind(8, item.filePath)
        try statement.bind(9, annotations)
        try statement.run()
    }

    /// Removes captures and their image files in one transaction; files go once it commits.
    private func removeCaptures(_ ids: Set<UUID>) throws {
        guard !ids.isEmpty else { return }
        var files: [URL] = []
        try db.execute("BEGIN IMMEDIATE")
        do {
            for id in ids {
                if let name = captureList.first(where: { $0.id == id })?.imageFile {
                    files.append(capturesDirectory.appendingPathComponent(name))
                }
                let statement = try db.prepare("DELETE FROM captures WHERE id = ?")
                try statement.bind(1, id.uuidString)
                try statement.run()
            }
            try db.execute("COMMIT")
        } catch {
            try? db.execute("ROLLBACK")
            throw error
        }
        captureList.removeAll { ids.contains($0.id) }
        files.forEach { try? FileManager.default.removeItem(at: $0) }
        try? db.execute("PRAGMA wal_checkpoint(TRUNCATE)")
    }

    // MARK: - Applying effects

    private func run(
        _ action: HistoryAction, now: Date, newContent: ClipContent? = nil, limits overrideLimits: RetentionLimits? = nil
    ) throws -> HistoryOutcome {
        let result = HistoryReducer.reduce(state, action, limits: overrideLimits ?? limits, now: now)
        guard !result.effects.isEmpty else {
            state = result.state
            return result.outcome
        }

        var writtenFiles: [URL] = []
        var filesToDelete: [URL] = []
        do {
            try db.execute("BEGIN IMMEDIATE")
            for effect in result.effects {
                switch effect {
                case .insert(let item):
                    guard let content = newContent else { throw ClipboardStoreError.payloadMissing(item.id) }
                    if let file = try insert(item, content: content) {
                        writtenFiles.append(file)
                    }
                case .update(let item):
                    try update(item)
                case .remove(let id):
                    if let file = try remove(id) {
                        filesToDelete.append(file)
                    }
                }
            }
            try db.execute("COMMIT")
        } catch {
            try? db.execute("ROLLBACK")
            writtenFiles.forEach { try? FileManager.default.removeItem(at: $0) }
            throw error
        }

        state = result.state
        filesToDelete.forEach { try? FileManager.default.removeItem(at: $0) }
        if searchIndex != nil {
            for effect in result.effects {
                switch effect {
                case .insert(let item):
                    searchIndex?[item.id] = newContent.map { SearchText.fold(SearchText.searchable($0)) }
                case .remove(let id):
                    searchIndex?[id] = nil
                case .update:
                    break
                }
            }
        }
        if result.effects.contains(where: { if case .remove = $0 { return true } else { return false } }) {
            // Fold the write-ahead log back into the database and empty it, so removed clips
            // do not linger there. Best effort: a busy reader only delays it.
            try? db.execute("PRAGMA wal_checkpoint(TRUNCATE)")
        }
        return result.outcome
    }

    /// Returns the image file written, if any.
    private func insert(_ item: ClipItem, content: ClipContent) throws -> URL? {
        var text: String?
        var blob: Data?
        var type: String?
        var fileName: String?
        var fileURL: URL?

        switch content {
        case .text(let string):
            text = string
        case .richText(let rtf, let plainText):
            text = plainText
            blob = rtf
        case .image(let data, let typeIdentifier):
            type = typeIdentifier
            let name = item.contentHash + "." + Self.fileExtension(for: typeIdentifier)
            let url = imagesDirectory.appendingPathComponent(name)
            // Only a file this insert created is removed on failure; one already there belongs
            // to another row.
            let existed = FileManager.default.fileExists(atPath: url.path)
            try data.write(to: url, options: .atomic)
            fileName = name
            fileURL = existed ? nil : url
        case .fileURLs(let urls):
            text = ClipContent.joinedURLs(urls)
        case .colour(let colour):
            text = colour.storageString
        }

        let statement = try db.prepare("""
            INSERT INTO items (id, created_at, last_used_at, kind, content_hash, source_app, pinned,
                               byte_size, preview, payload_text, payload_blob, payload_type, payload_file)
            VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """)
        do {
            try statement.bind(1, item.id.uuidString)
            try statement.bind(2, item.createdAt.timeIntervalSince1970)
            try statement.bind(3, item.lastUsedAt.timeIntervalSince1970)
            try statement.bind(4, item.kind.rawValue)
            try statement.bind(5, item.contentHash)
            try statement.bind(6, item.sourceApp)
            try statement.bind(7, item.pinned ? 1 : 0)
            try statement.bind(8, item.byteSize)
            try statement.bind(9, item.preview)
            try statement.bind(10, text)
            try statement.bind(11, blob)
            try statement.bind(12, type)
            try statement.bind(13, fileName)
            try statement.run()
        } catch {
            if let fileURL { try? FileManager.default.removeItem(at: fileURL) }
            throw error
        }
        return fileURL
    }

    private func update(_ item: ClipItem) throws {
        let statement = try db.prepare(
            "UPDATE items SET last_used_at = ?, source_app = ?, pinned = ? WHERE id = ?"
        )
        try statement.bind(1, item.lastUsedAt.timeIntervalSince1970)
        try statement.bind(2, item.sourceApp)
        try statement.bind(3, item.pinned ? 1 : 0)
        try statement.bind(4, item.id.uuidString)
        try statement.run()
    }

    /// Returns the image file to delete once the transaction commits, if any.
    private func remove(_ id: UUID) throws -> URL? {
        let select = try db.prepare("SELECT payload_file FROM items WHERE id = ?")
        try select.bind(1, id.uuidString)
        let file = try select.step() ? select.text(0) : nil

        let delete = try db.prepare("DELETE FROM items WHERE id = ?")
        try delete.bind(1, id.uuidString)
        try delete.run()
        return file.map { imagesDirectory.appendingPathComponent($0) }
    }

    static func fileExtension(for typeIdentifier: String) -> String {
        switch typeIdentifier {
        case "public.png": return "png"
        case "public.tiff": return "tiff"
        case "public.jpeg": return "jpg"
        default: return "bin"
        }
    }

    // MARK: - Opening

    private static func migrate(_ db: SQLiteConnection) throws {
        let version = try db.userVersion()
        if version > schemaVersion {
            throw ClipboardStoreError.unsupportedSchema(found: Int(version))
        }
        guard version < schemaVersion else { return }

        try db.execute("BEGIN IMMEDIATE")
        do {
            if version < 1 {
                try db.execute("""
                    CREATE TABLE items (
                        id TEXT PRIMARY KEY NOT NULL,
                        created_at REAL NOT NULL,
                        last_used_at REAL NOT NULL,
                        kind TEXT NOT NULL,
                        content_hash TEXT NOT NULL UNIQUE,
                        source_app TEXT,
                        pinned INTEGER NOT NULL DEFAULT 0,
                        byte_size INTEGER NOT NULL,
                        preview TEXT NOT NULL,
                        payload_text TEXT,
                        payload_blob BLOB,
                        payload_type TEXT,
                        payload_file TEXT
                    )
                    """)
            }
            if version < 2 {
                try db.execute("""
                    CREATE TABLE captures (
                        id TEXT PRIMARY KEY NOT NULL,
                        created_at REAL NOT NULL,
                        kind TEXT NOT NULL,
                        pixel_width INTEGER NOT NULL DEFAULT 0,
                        pixel_height INTEGER NOT NULL DEFAULT 0,
                        byte_size INTEGER NOT NULL DEFAULT 0,
                        image_file TEXT,
                        file_path TEXT,
                        annotations BLOB
                    )
                    """)
            }
            // Later migrations (OCR text in C4a) go here, one `if version < n` block each.
            try db.execute("PRAGMA user_version = \(schemaVersion)")
            try db.execute("COMMIT")
        } catch {
            try? db.execute("ROLLBACK")
            throw error
        }
    }

    /// Rows this version cannot read (a corrupt id or an unknown kind) are removed with their
    /// image, so they cannot block the same content from being recorded again.
    private static func removeUnreadableRows(_ db: SQLiteConnection, imagesDirectory: URL) throws {
        let statement = try db.prepare("SELECT rowid, id, kind, content_hash, payload_file FROM items")
        var bad: [(rowid: Int, file: String?)] = []
        while try statement.step() {
            let readable = statement.text(1).flatMap(UUID.init(uuidString:)) != nil
                && statement.text(2).flatMap(ClipKind.init(rawValue:)) != nil
                && statement.text(3) != nil
            if !readable { bad.append((statement.int(0), statement.text(4))) }
        }
        guard !bad.isEmpty else { return }
        for row in bad {
            let delete = try db.prepare("DELETE FROM items WHERE rowid = ?")
            try delete.bind(1, row.rowid)
            try delete.run()
            if let file = row.file {
                try? FileManager.default.removeItem(at: imagesDirectory.appendingPathComponent(file))
            }
        }
    }

    private static func loadItems(_ db: SQLiteConnection) throws -> [ClipItem] {
        let statement = try db.prepare("""
            SELECT id, created_at, last_used_at, kind, content_hash, source_app, pinned, byte_size, preview
            FROM items
            """)
        var items: [ClipItem] = []
        while try statement.step() {
            // Unreadable rows were removed on open; this guard only keeps a bad row from
            // crashing the load.
            guard let idString = statement.text(0), let id = UUID(uuidString: idString),
                  let kindString = statement.text(3), let kind = ClipKind(rawValue: kindString),
                  let hash = statement.text(4) else { continue }
            items.append(ClipItem(
                id: id,
                createdAt: Date(timeIntervalSince1970: statement.double(1)),
                lastUsedAt: Date(timeIntervalSince1970: statement.double(2)),
                kind: kind,
                contentHash: hash,
                sourceApp: statement.text(5),
                pinned: statement.int(6) != 0,
                byteSize: statement.int(7),
                preview: statement.text(8) ?? ""
            ))
        }
        return items
    }

    /// Captures, newest first. Rows this version cannot read, and screenshots whose image file
    /// is gone, are removed.
    private static func loadCaptures(_ db: SQLiteConnection, capturesDirectory: URL) throws -> [CaptureItem] {
        let statement = try db.prepare("""
            SELECT rowid, id, created_at, kind, pixel_width, pixel_height, byte_size, image_file, file_path
            FROM captures ORDER BY created_at DESC
            """)
        var captures: [CaptureItem] = []
        var bad: [Int] = []
        while try statement.step() {
            guard let id = statement.text(1).flatMap(UUID.init(uuidString:)),
                  let kind = statement.text(3).flatMap(CaptureKind.init(rawValue:)) else {
                bad.append(statement.int(0))
                continue
            }
            let imageFile = statement.text(7)
            if kind == .screenshot {
                guard let imageFile,
                      FileManager.default.fileExists(atPath: capturesDirectory.appendingPathComponent(imageFile).path) else {
                    bad.append(statement.int(0))
                    continue
                }
            }
            captures.append(CaptureItem(
                id: id,
                createdAt: Date(timeIntervalSince1970: statement.double(2)),
                kind: kind,
                pixelWidth: statement.int(4),
                pixelHeight: statement.int(5),
                byteSize: statement.int(6),
                imageFile: imageFile,
                filePath: statement.text(8)
            ))
        }
        for rowid in bad {
            let delete = try db.prepare("DELETE FROM captures WHERE rowid = ?")
            try delete.bind(1, rowid)
            try delete.run()
        }
        return captures
    }

    /// Capture files no row refers to (a crash between writing the file and committing).
    private static func removeOrphanCaptureFiles(_ captures: [CaptureItem], capturesDirectory: URL) {
        let referenced = Set(captures.compactMap(\.imageFile))
        let onDisk = (try? FileManager.default.contentsOfDirectory(atPath: capturesDirectory.path)) ?? []
        for name in onDisk where !referenced.contains(name) {
            try? FileManager.default.removeItem(at: capturesDirectory.appendingPathComponent(name))
        }
    }

    private static func removeOrphanImages(_ db: SQLiteConnection, imagesDirectory: URL) throws {
        let statement = try db.prepare("SELECT payload_file FROM items WHERE payload_file IS NOT NULL")
        var referenced = Set<String>()
        while try statement.step() {
            if let name = statement.text(0) { referenced.insert(name) }
        }
        let onDisk = (try? FileManager.default.contentsOfDirectory(atPath: imagesDirectory.path)) ?? []
        for name in onDisk where !referenced.contains(name) {
            try? FileManager.default.removeItem(at: imagesDirectory.appendingPathComponent(name))
        }
    }
}
