import Testing
import Foundation
import CoreGraphics
@testable import DocShot

@Suite("SnapshotPlan Budget Tests")
struct SnapshotPlanTests {

    /// Real display geometries, expressed in points with their backing scale.
    private func builtInRetina(id: CGDirectDisplayID = 1, origin: CGPoint = .zero) -> DisplayDescriptor {
        DisplayDescriptor(
            displayID: id,
            frameInCG: CGRect(origin: origin, size: CGSize(width: 1728, height: 1117)),
            scale: 2
        )
    }

    private func studioDisplay5K(id: CGDirectDisplayID = 2, origin: CGPoint = .zero) -> DisplayDescriptor {
        DisplayDescriptor(
            displayID: id,
            frameInCG: CGRect(origin: origin, size: CGSize(width: 2560, height: 1440)),
            scale: 2
        )
    }

    private func proDisplayXDR6K(id: CGDirectDisplayID = 3, origin: CGPoint = .zero) -> DisplayDescriptor {
        DisplayDescriptor(
            displayID: id,
            frameInCG: CGRect(origin: origin, size: CGSize(width: 3008, height: 1692)),
            scale: 2
        )
    }

    @Test("The budget is 512 MB of decoded pixels")
    func testBudgetConstants() {
        #expect(SnapshotPlan.memoryBudgetBytes == 512 * 1024 * 1024)
        #expect(SnapshotPlan.bytesPerPixel == 4)
        #expect(SnapshotPlan.maximumPixelCount == 134_217_728)
    }

    @Test("A single display is planned and its cost reported")
    func testSingleDisplay() {
        let plan = SnapshotPlan.make(for: [builtInRetina()])

        #expect(plan.included.count == 1)
        #expect(plan.excluded.isEmpty)
        #expect(plan.includes(1))
        // 3456 x 2234 = 7,720,704 px -> ~30.9 MB
        #expect(plan.totalPixelCount == 3456 * 2234)
        #expect(plan.estimatedBytes == 3456 * 2234 * 4)
        #expect(plan.estimatedBytes < SnapshotPlan.memoryBudgetBytes)
    }

    @Test("A realistic three-display desk fits inside the budget")
    func testThreeLargeDisplaysAllFit() {
        let displays = [
            builtInRetina(id: 1),
            studioDisplay5K(id: 2, origin: CGPoint(x: 1728, y: 0)),
            proDisplayXDR6K(id: 3, origin: CGPoint(x: -3008, y: 0))
        ]

        let plan = SnapshotPlan.make(for: displays)

        #expect(plan.included.count == 3)
        #expect(plan.excluded.isEmpty)
        #expect(plan.estimatedBytes <= SnapshotPlan.memoryBudgetBytes)
    }

    @Test("Beyond the budget, largest displays are kept and the rest are skipped")
    func testOverBudgetSkipsRatherThanDownscales() {
        // Ten 6K displays: 20.4M px each, so only six fit inside 134.2M px.
        let displays = (1...10).map { index in
            proDisplayXDR6K(id: CGDirectDisplayID(index), origin: CGPoint(x: CGFloat(index) * 3008, y: 0))
        }

        let plan = SnapshotPlan.make(for: displays)

        #expect(plan.included.count + plan.excluded.count == 10)
        #expect(!plan.included.isEmpty)
        #expect(!plan.excluded.isEmpty)
        #expect(plan.totalPixelCount <= SnapshotPlan.maximumPixelCount)

        // Adding any excluded display would breach the budget: nothing was downscaled to fit.
        let excludedCost = plan.excluded.first?.pixelCount ?? 0
        #expect(plan.totalPixelCount + excludedCost > SnapshotPlan.maximumPixelCount)
    }

    @Test("Largest-first means a big display is not starved by smaller ones listed before it")
    func testLargestFirstOrdering() {
        // Enough 5K displays to fill the budget, with one 6K display enumerated last.
        var displays = (1...20).map { index in
            studioDisplay5K(id: CGDirectDisplayID(index), origin: CGPoint(x: CGFloat(index) * 2560, y: 0))
        }
        let large = proDisplayXDR6K(id: 99, origin: CGPoint(x: -3008, y: 0))
        displays.append(large)

        let plan = SnapshotPlan.make(for: displays)

        #expect(plan.includes(99), "The largest display must be considered before smaller ones")
        #expect(plan.totalPixelCount <= SnapshotPlan.maximumPixelCount)
    }

    @Test("A display larger than the whole budget is excluded without invalidating the plan")
    func testOversizedSingleDisplayExcluded() {
        let absurd = DisplayDescriptor(
            displayID: 7,
            frameInCG: CGRect(x: 0, y: 0, width: 20_000, height: 20_000),
            scale: 2
        )
        let normal = builtInRetina(id: 1)

        let plan = SnapshotPlan.make(for: [absurd, normal])

        #expect(!plan.includes(7))
        #expect(plan.includes(1), "Other displays must still be snapshotted")
        #expect(plan.excluded.map(\.displayID) == [7])
    }

    @Test("Invalid display geometry is excluded rather than guessed at")
    func testInvalidDescriptorsExcluded() {
        let zeroSize = DisplayDescriptor(displayID: 10, frameInCG: CGRect(x: 0, y: 0, width: 0, height: 1080), scale: 2)
        let negativeScale = DisplayDescriptor(displayID: 11, frameInCG: CGRect(x: 0, y: 0, width: 1920, height: 1080), scale: -1)
        let notFinite = DisplayDescriptor(displayID: 12, frameInCG: CGRect(x: CGFloat.nan, y: 0, width: 1920, height: 1080), scale: 2)
        let valid = builtInRetina(id: 13)

        let plan = SnapshotPlan.make(for: [zeroSize, negativeScale, notFinite, valid])

        let includedIDs: [CGDirectDisplayID] = plan.included.map(\.displayID)
        let excludedIDs: Set<CGDirectDisplayID> = Set(plan.excluded.map(\.displayID))
        #expect(includedIDs == [13])
        #expect(excludedIDs == Set([10, 11, 12] as [CGDirectDisplayID]))
        #expect(zeroSize.pixelCount == 0)
        #expect(negativeScale.isValid == false)
        #expect(notFinite.isValid == false)
    }

    @Test("No displays produces an empty plan rather than a failure")
    func testEmptyInput() {
        let plan = SnapshotPlan.make(for: [])

        #expect(plan.included.isEmpty)
        #expect(plan.excluded.isEmpty)
        #expect(plan.totalPixelCount == 0)
        #expect(plan.estimatedBytes == 0)
    }

    @Test("Results are reported in the caller's display order")
    func testOutputPreservesInputOrder() {
        let displays = [
            studioDisplay5K(id: 5),
            builtInRetina(id: 2),
            proDisplayXDR6K(id: 9)
        ]

        let plan = SnapshotPlan.make(for: displays)
        #expect(plan.included.map(\.displayID) == [5, 2, 9])
    }

    @Test("Negative-origin displays are planned like any other")
    func testNegativeOriginDisplaysPlanned() {
        let left = builtInRetina(id: 1, origin: CGPoint(x: -1728, y: -300))
        let plan = SnapshotPlan.make(for: [left])

        #expect(plan.includes(1))
        #expect(left.contains(globalPoint: CGPoint(x: -1000, y: 0)))
        #expect(!left.contains(globalPoint: CGPoint(x: 10, y: 10)))
    }
}
