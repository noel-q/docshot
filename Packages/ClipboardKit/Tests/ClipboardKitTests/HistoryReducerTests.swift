import Foundation
import Testing
@testable import ClipboardKit

@Suite("History reducer")
struct HistoryReducerTests {
    let limits = RetentionLimits.standard

    func add(_ text: String, to state: HistoryState, at date: Date = referenceDate, app: String? = nil) -> HistoryResult {
        HistoryReducer.reduce(state, .add(content: .text(text), sourceApp: app, id: UUID()), limits: limits, now: date)
    }

    @Test("A new copy is added at the top")
    func testAddNew() {
        let first = add("one", to: HistoryState())
        let second = add("two", to: first.state, at: referenceDate.addingTimeInterval(1))
        #expect(second.state.items.map(\.preview) == ["two", "one"])
        guard case .added(let item) = second.outcome else {
            Issue.record("expected .added, got \(second.outcome)")
            return
        }
        #expect(second.effects == [.insert(item)])
    }

    @Test("Copying the same thing again moves it to the top instead of adding it twice")
    func testDuplicate() {
        var state = add("one", to: HistoryState(), app: "com.apple.TextEdit").state
        state = add("two", to: state, at: referenceDate.addingTimeInterval(1)).state
        let later = referenceDate.addingTimeInterval(60)
        let result = add("one", to: state, at: later, app: "com.apple.Safari")

        #expect(result.state.items.count == 2)
        #expect(result.state.items.map(\.preview) == ["one", "two"])
        guard case .movedToTop(let item) = result.outcome else {
            Issue.record("expected .movedToTop, got \(result.outcome)")
            return
        }
        #expect(item.lastUsedAt == later)
        #expect(item.createdAt == referenceDate)
        #expect(item.sourceApp == "com.apple.Safari")
        #expect(result.effects == [.update(item)])
    }

    @Test("A re-copy with no known app keeps the original app")
    func testDuplicateKeepsApp() {
        let state = add("one", to: HistoryState(), app: "com.apple.TextEdit").state
        let result = add("one", to: state, at: referenceDate.addingTimeInterval(5), app: nil)
        #expect(result.state.items.first?.sourceApp == "com.apple.TextEdit")
    }

    @Test("Adding past the item limit removes the oldest in the same step")
    func testAddAppliesRetention() {
        let small = RetentionLimits(maxItems: 2, maxAge: days(30), maxBytes: 1_000_000)
        var state = HistoryState()
        var ids: [UUID] = []
        for (index, text) in ["a", "b", "c"].enumerated() {
            let id = UUID()
            ids.append(id)
            state = HistoryReducer.reduce(
                state, .add(content: .text(text), sourceApp: nil, id: id),
                limits: small, now: referenceDate.addingTimeInterval(Double(index))
            ).state
        }
        #expect(state.items.map(\.preview) == ["c", "b"])

        let result = HistoryReducer.reduce(
            HistoryState(items: state.items), .add(content: .text("d"), sourceApp: nil, id: UUID()),
            limits: small, now: referenceDate.addingTimeInterval(10)
        )
        #expect(result.effects.contains(.remove(ids[1])))
    }

    @Test("A copy over 50 MB is skipped and changes nothing")
    func testAddTooLarge() {
        let huge = ClipContent.image(data: Data(count: RetentionLimits.maxItemBytes + 1), typeIdentifier: "public.png")
        let result = HistoryReducer.reduce(HistoryState(), .add(content: huge, sourceApp: nil, id: UUID()), limits: limits, now: referenceDate)
        #expect(result.outcome == .skipped(.tooLarge(byteSize: RetentionLimits.maxItemBytes + 1)))
        #expect(result.effects.isEmpty)
        #expect(result.state.items.isEmpty)
    }

    @Test("Using an item from history moves it to the top")
    func testMarkUsed() {
        var state = add("one", to: HistoryState()).state
        state = add("two", to: state, at: referenceDate.addingTimeInterval(1)).state
        let one = state.items.last!
        let result = HistoryReducer.reduce(state, .markUsed(one.id), limits: limits, now: referenceDate.addingTimeInterval(9))
        #expect(result.state.items.first?.id == one.id)
        #expect(HistoryReducer.reduce(state, .markUsed(UUID()), limits: limits, now: referenceDate).outcome == .notFound)
    }

    @Test("Pin and unpin flip the flag; a pin over the cap is refused")
    func testPinning() {
        let tight = RetentionLimits(maxItems: 200, maxAge: days(30), maxBytes: 5)
        let state = HistoryState(items: [makeItem("a", byteSize: 3), makeItem("b", byteSize: 3)])
        let first = state.items[0]
        let second = state.items[1]

        let pinned = HistoryReducer.reduce(state, .pin(first.id), limits: tight, now: referenceDate)
        #expect(pinned.state.item(first.id)?.pinned == true)

        let refused = HistoryReducer.reduce(pinned.state, .pin(second.id), limits: tight, now: referenceDate)
        #expect(refused.outcome == .pinRefused)
        #expect(refused.effects.isEmpty)

        let unpinned = HistoryReducer.reduce(pinned.state, .unpin(first.id), limits: tight, now: referenceDate)
        #expect(unpinned.state.item(first.id)?.pinned == false)
    }

    @Test("Unpinning an old item lets the age limit remove it at once")
    func testUnpinAppliesRetention() {
        let old = makeItem("old", usedDaysAgo: 90, pinned: true)
        let result = HistoryReducer.reduce(HistoryState(items: [old]), .unpin(old.id), limits: limits, now: referenceDate)
        #expect(result.state.items.isEmpty)
        #expect(result.effects.last == .remove(old.id))
    }

    @Test("Delete removes one item")
    func testDelete() {
        let item = makeItem("a")
        let result = HistoryReducer.reduce(HistoryState(items: [item]), .delete(item.id), limits: limits, now: referenceDate)
        #expect(result.state.items.isEmpty)
        #expect(result.effects == [.remove(item.id)])
        #expect(result.outcome == .removed(count: 1))
    }

    @Test("Clear follows the chosen keep option")
    func testClear() {
        let pin = makeItem("pin", usedDaysAgo: 5, pinned: true)
        let other = makeItem("other", usedDaysAgo: 1)
        let result = HistoryReducer.reduce(HistoryState(items: [pin, other]), .clear(.pinnedOnly), limits: limits, now: referenceDate)
        #expect(result.state.items == [pin])
        #expect(result.outcome == .removed(count: 1))
    }

    @Test("Retention on its own removes stale items")
    func testApplyRetention() {
        let stale = makeItem("stale", usedDaysAgo: 31)
        let fresh = makeItem("fresh", usedDaysAgo: 1)
        let result = HistoryReducer.reduce(HistoryState(items: [stale, fresh]), .applyRetention, limits: limits, now: referenceDate)
        #expect(result.state.items == [fresh])
        #expect(result.effects == [.remove(stale.id)])
    }
}
