import Foundation

/// What the Captures section keeps (C4 plan, 25 November 2026).
public enum CaptureKind: String, Sendable, Codable {
    /// A screenshot: its image as a file, and the app's annotation state as opaque JSON.
    case screenshot
    /// A saved recording: only its path. The movie itself is never copied into storage.
    case recording
}

/// One entry in Captures. Screenshots carry an image file; recordings carry a path.
public struct CaptureItem: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let createdAt: Date
    public let kind: CaptureKind
    public let pixelWidth: Int
    public let pixelHeight: Int
    /// Bytes on disk counted towards the storage cap: the image file for a screenshot, zero for
    /// a recording reference.
    public let byteSize: Int
    /// Screenshot only: the image file's name in the Captures folder.
    public let imageFile: String?
    /// Recording only: where the user saved it.
    public let filePath: String?

    public init(
        id: UUID, createdAt: Date, kind: CaptureKind, pixelWidth: Int, pixelHeight: Int,
        byteSize: Int, imageFile: String?, filePath: String?
    ) {
        self.id = id
        self.createdAt = createdAt
        self.kind = kind
        self.pixelWidth = pixelWidth
        self.pixelHeight = pixelHeight
        self.byteSize = byteSize
        self.imageFile = imageFile
        self.filePath = filePath
    }
}

/// The pure rules for what Captures keeps (C4 plan, decision 3). Nothing here touches storage.
public enum CaptureRetention {
    /// Fixed caps, not settings (plan 4.5; decided 17 November 2026 for screenshots).
    public static let maxScreenshots = 20
    public static let maxRecordings = 20

    /// Captures the limits remove, in no particular order:
    /// 1. anything older than the history age limit;
    /// 2. screenshots beyond the 20 newest, and recording references beyond the 20 newest;
    /// 3. while history and screenshots together are over the storage cap, the oldest screenshot.
    public static func toRemove(
        _ captures: [CaptureItem], limits: RetentionLimits, historyBytes: Int, now: Date
    ) -> Set<UUID> {
        var removed = Set<UUID>()
        let newestFirst = captures.sorted { $0.createdAt > $1.createdAt }

        for capture in newestFirst where now.timeIntervalSince(capture.createdAt) > limits.maxAge {
            removed.insert(capture.id)
        }
        for (kind, cap) in [(CaptureKind.screenshot, maxScreenshots), (.recording, maxRecordings)] {
            let kept = newestFirst.filter { $0.kind == kind && !removed.contains($0.id) }
            for capture in kept.dropFirst(cap) {
                removed.insert(capture.id)
            }
        }

        var total = historyBytes + newestFirst.filter { !removed.contains($0.id) }.reduce(0) { $0 + $1.byteSize }
        for capture in newestFirst.reversed() where total > limits.maxBytes {
            guard capture.kind == .screenshot, !removed.contains(capture.id) else { continue }
            removed.insert(capture.id)
            total -= capture.byteSize
        }
        return removed
    }

    /// Captures a Clear removes. Captures have no pins, so "pinned only" and "nothing" remove
    /// them all; "last 5" and "last 10" keep that many of each kind.
    public static func toRemoveOnClear(_ captures: [CaptureItem], keep: ClearKeep) -> Set<UUID> {
        let keepCount: Int
        switch keep {
        case .lastFive: keepCount = 5
        case .lastTen: keepCount = 10
        case .pinnedOnly, .nothing: keepCount = 0
        }
        var removed = Set<UUID>()
        for kind in [CaptureKind.screenshot, .recording] {
            let newestFirst = captures.filter { $0.kind == kind }.sorted { $0.createdAt > $1.createdAt }
            for capture in newestFirst.dropFirst(keepCount) {
                removed.insert(capture.id)
            }
        }
        return removed
    }
}
