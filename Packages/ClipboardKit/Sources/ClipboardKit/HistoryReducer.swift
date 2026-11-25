import Foundation

/// History as a list of items, most recently used first.
public struct HistoryState: Sendable, Equatable {
    public private(set) var items: [ClipItem]

    public init(items: [ClipItem] = []) {
        self.items = items.sorted(by: RetentionPolicy.mostRecentFirst)
    }

    public func item(_ id: UUID) -> ClipItem? {
        items.first { $0.id == id }
    }

    public var totalBytes: Int {
        items.reduce(0) { $0 + $1.byteSize }
    }

    fileprivate mutating func upsert(_ item: ClipItem) {
        items.removeAll { $0.id == item.id }
        items.append(item)
        items.sort(by: RetentionPolicy.mostRecentFirst)
    }

    /// Swaps in a changed item with the same id (its recognised text changed its size, C4a).
    mutating func replace(_ item: ClipItem) {
        guard let index = items.firstIndex(where: { $0.id == item.id }) else { return }
        items[index] = item
    }

    fileprivate mutating func remove(_ ids: Set<UUID>) {
        items.removeAll { ids.contains($0.id) }
    }
}

public enum HistoryAction: Sendable, Equatable {
    /// A new copy. `id` is used only when the content is not already in history.
    case add(content: ClipContent, sourceApp: String?, id: UUID)
    /// The item was copied back or pasted from history: it moves to the top.
    case markUsed(UUID)
    case pin(UUID)
    case unpin(UUID)
    case delete(UUID)
    case clear(ClearKeep)
    case applyRetention
}

/// A change the store must make to match the new state.
public enum HistoryEffect: Sendable, Equatable {
    case insert(ClipItem)
    case update(ClipItem)
    case remove(UUID)
}

public enum HistoryOutcome: Sendable, Equatable {
    case added(ClipItem)
    /// The content was already in history; that item moved to the top.
    case movedToTop(ClipItem)
    case skipped(SkipReason)
    case updated(ClipItem)
    /// Pinned items alone would exceed the storage cap.
    case pinRefused
    case removed(count: Int)
    case notFound
}

public struct HistoryResult: Sendable, Equatable {
    public let state: HistoryState
    public let effects: [HistoryEffect]
    public let outcome: HistoryOutcome
}

/// The pure decision layer for history (plan section 4.1). The store runs it, then applies the
/// effects to the database in one transaction.
public enum HistoryReducer {

    public static func reduce(
        _ state: HistoryState, _ action: HistoryAction, limits: RetentionLimits, now: Date
    ) -> HistoryResult {
        var next = state
        var effects: [HistoryEffect] = []
        let outcome: HistoryOutcome

        switch action {
        case .add(let content, let sourceApp, let id):
            let hash = content.contentHash
            if var existing = state.items.first(where: { $0.contentHash == hash }) {
                existing.lastUsedAt = max(now, existing.lastUsedAt)
                existing.sourceApp = sourceApp ?? existing.sourceApp
                next.upsert(existing)
                effects.append(.update(existing))
                outcome = .movedToTop(existing)
            } else {
                let admission = RetentionPolicy.admission(
                    byteSize: content.byteSize, existing: state.items, limits: limits
                )
                if case .skip(let reason) = admission {
                    return HistoryResult(state: state, effects: [], outcome: .skipped(reason))
                }
                let item = ClipItem(content: content, sourceApp: sourceApp, now: now, id: id)
                next.upsert(item)
                effects.append(.insert(item))
                outcome = .added(item)
            }
            effects += retention(&next, limits: limits, now: now)

        case .markUsed(let id):
            guard var item = state.item(id) else { return unchanged(state, .notFound) }
            item.lastUsedAt = max(now, item.lastUsedAt)
            next.upsert(item)
            effects.append(.update(item))
            outcome = .updated(item)

        case .pin(let id):
            guard var item = state.item(id) else { return unchanged(state, .notFound) }
            guard !item.pinned else { return unchanged(state, .updated(item)) }
            guard RetentionPolicy.canPin(id, in: state.items, limits: limits) else {
                return unchanged(state, .pinRefused)
            }
            item.pinned = true
            next.upsert(item)
            effects.append(.update(item))
            outcome = .updated(item)

        case .unpin(let id):
            guard var item = state.item(id) else { return unchanged(state, .notFound) }
            guard item.pinned else { return unchanged(state, .updated(item)) }
            item.pinned = false
            next.upsert(item)
            effects.append(.update(item))
            // An unpinned item counts again, so the limits apply to it at once.
            effects += retention(&next, limits: limits, now: now)
            outcome = .updated(item)

        case .delete(let id):
            guard state.item(id) != nil else { return unchanged(state, .notFound) }
            next.remove([id])
            effects.append(.remove(id))
            outcome = .removed(count: 1)

        case .clear(let keep):
            let ids = RetentionPolicy.itemsToRemoveOnClear(from: state.items, keep: keep)
            next.remove(ids)
            effects += sortedRemovals(ids)
            outcome = .removed(count: ids.count)

        case .applyRetention:
            let removals = retention(&next, limits: limits, now: now)
            effects += removals
            outcome = .removed(count: removals.count)
        }

        return HistoryResult(state: next, effects: effects, outcome: outcome)
    }

    private static func retention(
        _ state: inout HistoryState, limits: RetentionLimits, now: Date
    ) -> [HistoryEffect] {
        let ids = RetentionPolicy.itemsToRemove(from: state.items, limits: limits, now: now)
        state.remove(ids)
        return sortedRemovals(ids)
    }

    /// Removals in a stable order, so effects are deterministic.
    private static func sortedRemovals(_ ids: Set<UUID>) -> [HistoryEffect] {
        ids.sorted { $0.uuidString < $1.uuidString }.map(HistoryEffect.remove)
    }

    private static func unchanged(_ state: HistoryState, _ outcome: HistoryOutcome) -> HistoryResult {
        HistoryResult(state: state, effects: [], outcome: outcome)
    }
}
