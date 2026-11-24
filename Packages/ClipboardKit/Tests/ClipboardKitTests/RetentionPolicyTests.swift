import Foundation
import Testing
@testable import ClipboardKit

@Suite("Retention and clear rules (plan 4.2)")
struct RetentionPolicyTests {

    @Test("The defaults are 200 items, 30 days, 500 MB, and 50 MB for one copy")
    func testDefaults() {
        #expect(RetentionLimits.standard.maxItems == 200)
        #expect(RetentionLimits.standard.maxAge == days(30))
        #expect(RetentionLimits.standard.maxBytes == 500 * 1024 * 1024)
        #expect(RetentionLimits.maxItemBytes == 50 * 1024 * 1024)
        #expect(ClearKeep.defaultValue == .pinnedOnly)
    }

    // MARK: Age

    @Test("Unpinned items unused for over 30 days are removed; pinned ones are not")
    func testAge() {
        let fresh = makeItem(usedDaysAgo: 29.9)
        let stale = makeItem(usedDaysAgo: 30.1)
        let stalePinned = makeItem(usedDaysAgo: 400, pinned: true)
        let removed = RetentionPolicy.itemsToRemove(
            from: [fresh, stale, stalePinned], limits: .standard, now: referenceDate
        )
        #expect(removed == [stale.id])
    }

    @Test("An item exactly 30 days old is kept")
    func testAgeBoundary() {
        let item = makeItem(usedDaysAgo: 30)
        #expect(RetentionPolicy.itemsToRemove(from: [item], limits: .standard, now: referenceDate).isEmpty)
    }

    // MARK: Count

    @Test("Beyond 200 unpinned items, the least recently used go")
    func testCount() {
        let items = (0..<203).map { makeItem("item \($0)", usedDaysAgo: Double($0) / 100) }
        let removed = RetentionPolicy.itemsToRemove(from: items, limits: .standard, now: referenceDate)
        #expect(removed == Set(items[200...].map(\.id)))
    }

    @Test("Pinned items do not count towards the 200")
    func testCountIgnoresPins() {
        let pins = (0..<50).map { makeItem("pin \($0)", usedDaysAgo: 1, pinned: true) }
        let unpinned = (0..<200).map { makeItem("item \($0)", usedDaysAgo: 2) }
        #expect(RetentionPolicy.itemsToRemove(from: pins + unpinned, limits: .standard, now: referenceDate).isEmpty)
    }

    // MARK: Storage

    @Test("Over the storage cap, the least recently used unpinned items go until it fits")
    func testStorage() {
        let limits = RetentionLimits(maxItems: 200, maxAge: days(30), maxBytes: 100)
        let newest = makeItem(byteSize: 40, usedDaysAgo: 1)
        let middle = makeItem(byteSize: 40, usedDaysAgo: 2)
        let oldest = makeItem(byteSize: 40, usedDaysAgo: 3)
        let removed = RetentionPolicy.itemsToRemove(from: [oldest, newest, middle], limits: limits, now: referenceDate)
        #expect(removed == [oldest.id])
    }

    @Test("Pinned items count towards the cap but are never removed")
    func testStorageCountsPins() {
        let limits = RetentionLimits(maxItems: 200, maxAge: days(30), maxBytes: 100)
        let pin = makeItem(byteSize: 70, usedDaysAgo: 10, pinned: true)
        let a = makeItem(byteSize: 20, usedDaysAgo: 1)
        let b = makeItem(byteSize: 20, usedDaysAgo: 2)
        let removed = RetentionPolicy.itemsToRemove(from: [pin, a, b], limits: limits, now: referenceDate)
        #expect(removed == [b.id])
    }

    @Test("Pinned items over the cap stay, and every unpinned item goes")
    func testPinsOverCap() {
        let limits = RetentionLimits(maxItems: 200, maxAge: days(30), maxBytes: 100)
        let pins = [makeItem(byteSize: 80, pinned: true), makeItem(byteSize: 80, pinned: true)]
        let unpinned = makeItem(byteSize: 1)
        let removed = RetentionPolicy.itemsToRemove(from: pins + [unpinned], limits: limits, now: referenceDate)
        #expect(removed == [unpinned.id])
    }

    // MARK: Admission

    @Test("A single copy over 50 MB is skipped")
    func testTooLarge() {
        let size = RetentionLimits.maxItemBytes + 1
        #expect(RetentionPolicy.admission(byteSize: size, existing: [], limits: .standard) == .skip(.tooLarge(byteSize: size)))
        #expect(RetentionPolicy.admission(byteSize: RetentionLimits.maxItemBytes, existing: [], limits: .standard) == .record)
    }

    @Test("A copy that cannot fit beside the pinned items is skipped")
    func testStorageFull() {
        let limits = RetentionLimits(maxItems: 200, maxAge: days(30), maxBytes: 100)
        let pins = [makeItem(byteSize: 90, pinned: true)]
        #expect(RetentionPolicy.admission(byteSize: 11, existing: pins, limits: limits) == .skip(.storageFull))
        #expect(RetentionPolicy.admission(byteSize: 10, existing: pins, limits: limits) == .record)
    }

    @Test("Unpinned items never block a new copy; they make room instead")
    func testUnpinnedMakeRoom() {
        let limits = RetentionLimits(maxItems: 200, maxAge: days(30), maxBytes: 100)
        let unpinned = [makeItem(byteSize: 100)]
        #expect(RetentionPolicy.admission(byteSize: 50, existing: unpinned, limits: limits) == .record)
    }

    // MARK: Pinning

    @Test("A pin is refused when pinned items alone would exceed the cap")
    func testCanPin() {
        let limits = RetentionLimits(maxItems: 200, maxAge: days(30), maxBytes: 100)
        let pinned = makeItem(byteSize: 60, pinned: true)
        let small = makeItem(byteSize: 40)
        let big = makeItem(byteSize: 41)
        let items = [pinned, small, big]
        #expect(RetentionPolicy.canPin(small.id, in: items, limits: limits))
        #expect(!RetentionPolicy.canPin(big.id, in: items, limits: limits))
        #expect(RetentionPolicy.canPin(pinned.id, in: items, limits: limits))
        #expect(!RetentionPolicy.canPin(UUID(), in: items, limits: limits))
    }

    // MARK: Clear

    func clearFixture() -> (items: [ClipItem], pinned: ClipItem, recent: [ClipItem]) {
        let recent = (0..<12).map { makeItem("recent \($0)", usedDaysAgo: Double($0)) }
        let pinned = makeItem("old pin", usedDaysAgo: 20, pinned: true)
        return (recent + [pinned], pinned, recent)
    }

    @Test("Clear keeping pinned only leaves just the pins")
    func testClearPinnedOnly() {
        let (items, pinned, _) = clearFixture()
        let removed = RetentionPolicy.itemsToRemoveOnClear(from: items, keep: .pinnedOnly)
        #expect(removed == Set(items.map(\.id)).subtracting([pinned.id]))
    }

    @Test("Clear keeping the last 5 leaves the 5 most recent plus every pin")
    func testClearLastFive() {
        let (items, pinned, recent) = clearFixture()
        let removed = RetentionPolicy.itemsToRemoveOnClear(from: items, keep: .lastFive)
        let kept = Set(items.map(\.id)).subtracting(removed)
        #expect(kept == Set(recent.prefix(5).map(\.id)).union([pinned.id]))
    }

    @Test("Clear keeping the last 10 leaves the 10 most recent plus every pin")
    func testClearLastTen() {
        let (items, pinned, recent) = clearFixture()
        let removed = RetentionPolicy.itemsToRemoveOnClear(from: items, keep: .lastTen)
        let kept = Set(items.map(\.id)).subtracting(removed)
        #expect(kept == Set(recent.prefix(10).map(\.id)).union([pinned.id]))
    }

    @Test("A recent pin counts as one of the last 5")
    func testClearRecentPin() {
        let pin = makeItem("new pin", usedDaysAgo: 0, pinned: true)
        let others = (1...8).map { makeItem("item \($0)", usedDaysAgo: Double($0)) }
        let removed = RetentionPolicy.itemsToRemoveOnClear(from: [pin] + others, keep: .lastFive)
        let kept = Set(([pin] + others).map(\.id)).subtracting(removed)
        #expect(kept == Set([pin.id] + others.prefix(4).map(\.id)))
    }

    @Test("Clear keeping nothing removes pins too")
    func testClearNothing() {
        let (items, _, _) = clearFixture()
        #expect(RetentionPolicy.itemsToRemoveOnClear(from: items, keep: .nothing) == Set(items.map(\.id)))
    }

    @Test("Order is most recently used first, then newest, then by id")
    func testOrdering() {
        let a = makeItem(usedDaysAgo: 1)
        let b = makeItem(usedDaysAgo: 2)
        #expect(RetentionPolicy.mostRecentFirst(a, b))
        #expect(!RetentionPolicy.mostRecentFirst(b, a))
    }
}

@Suite("Retention without an item limit")
struct NoItemLimitTests {
    @Test("With no item limit, count removes nothing but age and storage still apply")
    func testNoItemLimit() {
        let limits = RetentionLimits(maxItems: RetentionLimits.noItemLimit, maxAge: days(30), maxBytes: 1_000)
        let many = (0..<500).map { makeItem("item \($0)", byteSize: 1, usedDaysAgo: Double($0) / 1000) }
        #expect(RetentionPolicy.itemsToRemove(from: many, limits: limits, now: referenceDate).isEmpty)

        let old = makeItem("old", usedDaysAgo: 31)
        let big = makeItem("big", byteSize: 2_000, usedDaysAgo: 1)
        let removed = RetentionPolicy.itemsToRemove(from: many + [old, big], limits: limits, now: referenceDate)
        #expect(removed == [old.id, big.id])
    }
}
