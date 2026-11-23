import Foundation

/// History limits (plan section 4.2): whichever is hit first.
public struct RetentionLimits: Sendable, Equatable {
    /// Unpinned items kept. Pinned items do not count.
    public var maxItems: Int
    /// How long an unpinned item is kept after its last use.
    public var maxAge: TimeInterval
    /// Total storage, pinned items included.
    public var maxBytes: Int

    public static let defaultMaxItems = 200
    public static let defaultMaxAge: TimeInterval = 30 * 24 * 60 * 60
    public static let defaultMaxBytes = 500 * 1024 * 1024
    /// Any single copy above this is skipped. Fixed, not a setting (decided 23 November 2026).
    public static let maxItemBytes = 50 * 1024 * 1024

    public static let standard = RetentionLimits(
        maxItems: defaultMaxItems, maxAge: defaultMaxAge, maxBytes: defaultMaxBytes
    )

    public init(maxItems: Int, maxAge: TimeInterval, maxBytes: Int) {
        self.maxItems = maxItems
        self.maxAge = maxAge
        self.maxBytes = maxBytes
    }
}

/// What a Clear leaves behind (plan section 4.2). The default is pinned only.
public enum ClearKeep: String, Sendable, CaseIterable, Codable {
    case lastFive
    case lastTen
    case pinnedOnly
    case nothing

    public static let defaultValue: ClearKeep = .pinnedOnly
}

/// The pure rules for what history keeps. Every function takes the item list and returns a
/// decision; nothing here touches storage.
public enum RetentionPolicy {

    /// Items the limits remove, in no particular order. Pinned items are never removed.
    ///
    /// 1. Unpinned items unused for longer than `maxAge`.
    /// 2. Unpinned items beyond the `maxItems` most recently used.
    /// 3. While total storage (pinned included) is over `maxBytes`, the least recently used
    ///    unpinned item.
    public static func itemsToRemove(
        from items: [ClipItem], limits: RetentionLimits, now: Date
    ) -> Set<UUID> {
        var removed = Set<UUID>()
        var keptUnpinned = items
            .filter { !$0.pinned }
            .sorted(by: mostRecentFirst)

        // 1. Age.
        keptUnpinned.removeAll { item in
            let expired = now.timeIntervalSince(item.lastUsedAt) > limits.maxAge
            if expired { removed.insert(item.id) }
            return expired
        }

        // 2. Count.
        if keptUnpinned.count > limits.maxItems {
            let surplus = keptUnpinned[max(limits.maxItems, 0)...]
            surplus.forEach { removed.insert($0.id) }
            keptUnpinned.removeLast(surplus.count)
        }

        // 3. Storage.
        let pinnedBytes = items.filter(\.pinned).reduce(0) { $0 + $1.byteSize }
        var total = pinnedBytes + keptUnpinned.reduce(0) { $0 + $1.byteSize }
        while total > limits.maxBytes, let oldest = keptUnpinned.popLast() {
            removed.insert(oldest.id)
            total -= oldest.byteSize
        }
        return removed
    }

    /// Whether a new copy of `byteSize` can be admitted at all. Unpinned items make room as
    /// needed, so only the per-item limit and the pinned total can refuse it.
    public static func admission(
        byteSize: Int, existing items: [ClipItem], limits: RetentionLimits
    ) -> RecordDecision {
        if byteSize > RetentionLimits.maxItemBytes {
            return .skip(.tooLarge(byteSize: byteSize))
        }
        let pinnedBytes = items.filter(\.pinned).reduce(0) { $0 + $1.byteSize }
        if pinnedBytes + byteSize > limits.maxBytes {
            return .skip(.storageFull)
        }
        return .record
    }

    /// A pin is refused when pinned items alone would exceed the storage cap.
    public static func canPin(_ id: UUID, in items: [ClipItem], limits: RetentionLimits) -> Bool {
        guard let item = items.first(where: { $0.id == id }) else { return false }
        if item.pinned { return true }
        let pinnedBytes = items.filter(\.pinned).reduce(0) { $0 + $1.byteSize }
        return pinnedBytes + item.byteSize <= limits.maxBytes
    }

    /// Items a Clear removes. "Last 5 / last 10" keep that many most recently used items plus
    /// every pinned item; "pinned only" keeps the pins; "nothing" removes everything.
    public static func itemsToRemoveOnClear(from items: [ClipItem], keep: ClearKeep) -> Set<UUID> {
        let recentCount: Int
        switch keep {
        case .nothing:
            return Set(items.map(\.id))
        case .pinnedOnly:
            recentCount = 0
        case .lastFive:
            recentCount = 5
        case .lastTen:
            recentCount = 10
        }
        let recent = Set(items.sorted(by: mostRecentFirst).prefix(recentCount).map(\.id))
        return Set(items.filter { !$0.pinned && !recent.contains($0.id) }.map(\.id))
    }

    /// Most recently used first; ties broken by newest creation, then by id, so the order is
    /// stable.
    public static func mostRecentFirst(_ a: ClipItem, _ b: ClipItem) -> Bool {
        if a.lastUsedAt != b.lastUsedAt { return a.lastUsedAt > b.lastUsedAt }
        if a.createdAt != b.createdAt { return a.createdAt > b.createdAt }
        return a.id.uuidString < b.id.uuidString
    }
}
