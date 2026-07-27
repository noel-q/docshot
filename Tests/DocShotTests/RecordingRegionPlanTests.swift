import Testing
import Foundation
import CoreGraphics
@testable import DocShot

/// Region → ScreenCaptureKit mapping. R1 records a region only when it lies wholly within one
/// display, and preserves the selected pixel size exactly.
@Suite("RecordingRegionPlan Tests")
struct RecordingRegionPlanTests {

    // Retina main display at the origin.
    private static let retinaMain = DisplayDescriptor(
        displayID: 1,
        frameInCG: CGRect(x: 0, y: 0, width: 1440, height: 900),
        scale: 2
    )

    // 1x display to the right of the main one.
    private static let external1x = DisplayDescriptor(
        displayID: 2,
        frameInCG: CGRect(x: 1440, y: 0, width: 1920, height: 1080),
        scale: 1
    )

    // A display placed left of and above the main display: negative origin in global CG space.
    private static let negativeOrigin = DisplayDescriptor(
        displayID: 3,
        frameInCG: CGRect(x: -1920, y: -120, width: 1920, height: 1080),
        scale: 1
    )

    private static let allDisplays = [retinaMain, external1x, negativeOrigin]

    @Test("A Retina region maps to display-relative points and doubled pixels")
    func testRetinaRegion() {
        let plan = RecordingRegionPlan.make(
            globalRectInCG: CGRect(x: 100, y: 120, width: 200, height: 150),
            displays: [Self.retinaMain]
        )

        #expect(plan == .ok(
            displayID: 1,
            sourceRectInPoints: CGRect(x: 100, y: 120, width: 200, height: 150),
            outputPixelSize: CGSize(width: 400, height: 300)
        ))
    }

    @Test("A region on a 1x external display subtracts that display's origin")
    func testExternalDisplayRegion() {
        let plan = RecordingRegionPlan.make(
            globalRectInCG: CGRect(x: 1500, y: 50, width: 300, height: 200),
            displays: Self.allDisplays
        )

        #expect(plan == .ok(
            displayID: 2,
            sourceRectInPoints: CGRect(x: 60, y: 50, width: 300, height: 200),
            outputPixelSize: CGSize(width: 300, height: 200)
        ))
    }

    @Test("A display with a negative origin keeps the offset signed")
    func testNegativeOriginDisplay() {
        let plan = RecordingRegionPlan.make(
            globalRectInCG: CGRect(x: -1800, y: -100, width: 400, height: 300),
            displays: Self.allDisplays
        )

        #expect(plan == .ok(
            displayID: 3,
            sourceRectInPoints: CGRect(x: 120, y: 20, width: 400, height: 300),
            outputPixelSize: CGSize(width: 400, height: 300)
        ))
    }

    @Test("Odd pixel dimensions are preserved, not rounded to convenient values")
    func testOddDimensionsArePreserved() {
        let onePointScale = RecordingRegionPlan.make(
            globalRectInCG: CGRect(x: 1500, y: 60, width: 101, height: 77),
            displays: Self.allDisplays
        )
        #expect(onePointScale.outputPixelSize == CGSize(width: 101, height: 77))

        let retina = RecordingRegionPlan.make(
            globalRectInCG: CGRect(x: 20, y: 20, width: 101.5, height: 77.5),
            displays: [Self.retinaMain]
        )
        #expect(retina.outputPixelSize == CGSize(width: 203, height: 155))
    }

    @Test("Fractional point sizes round to the nearest whole pixel")
    func testFractionalSizesRound() {
        let plan = RecordingRegionPlan.make(
            globalRectInCG: CGRect(x: 10, y: 10, width: 100.4, height: 50.6),
            displays: [Self.retinaMain]
        )

        #expect(plan.outputPixelSize == CGSize(width: 201, height: 101))
    }

    @Test("A region overlapping two displays is refused rather than cropped")
    func testSpanningTwoDisplaysIsRefused() {
        let plan = RecordingRegionPlan.make(
            globalRectInCG: CGRect(x: 1340, y: 100, width: 400, height: 300),
            displays: Self.allDisplays
        )

        #expect(plan.rejection == .spansMultipleDisplays)
        #expect(plan.target == nil)
    }

    @Test("A region on no display at all is refused")
    func testRegionOutsideEveryDisplayIsRefused() {
        let plan = RecordingRegionPlan.make(
            globalRectInCG: CGRect(x: 9000, y: 9000, width: 200, height: 200),
            displays: Self.allDisplays
        )

        #expect(plan.rejection == .noContainingDisplay)
    }

    @Test("A region running off the edge of its only display is refused")
    func testRegionOverflowingItsDisplayIsRefused() {
        let plan = RecordingRegionPlan.make(
            globalRectInCG: CGRect(x: 1300, y: 700, width: 400, height: 400),
            displays: [Self.retinaMain]
        )

        #expect(plan.rejection == .noContainingDisplay)
    }

    @Test("A region smaller than the minimum side is refused")
    func testTooSmallRegionIsRefused() {
        let plan = RecordingRegionPlan.make(
            globalRectInCG: CGRect(x: 10, y: 10, width: 10, height: 40),
            displays: [Self.retinaMain]
        )

        #expect(plan.rejection == .tooSmall)
    }

    @Test("Zero-area and non-finite selections are refused")
    func testInvalidGeometryIsRefused() {
        let zero = RecordingRegionPlan.make(
            globalRectInCG: CGRect(x: 10, y: 10, width: 0, height: 0),
            displays: [Self.retinaMain]
        )
        #expect(zero.rejection == .invalidGeometry)

        let infinite = RecordingRegionPlan.make(
            globalRectInCG: CGRect(x: 10, y: 10, width: CGFloat.infinity, height: 100),
            displays: [Self.retinaMain]
        )
        #expect(infinite.rejection == .invalidGeometry)

        let notANumber = RecordingRegionPlan.make(
            globalRectInCG: CGRect(x: CGFloat.nan, y: 10, width: 100, height: 100),
            displays: [Self.retinaMain]
        )
        #expect(notANumber.rejection == .invalidGeometry)
    }

    @Test("A right-to-left drag is normalised before it is evaluated")
    func testReversedDragIsNormalised() {
        let plan = RecordingRegionPlan.make(
            globalRectInCG: CGRect(x: 300, y: 270, width: -200, height: -150),
            displays: [Self.retinaMain]
        )

        #expect(plan == .ok(
            displayID: 1,
            sourceRectInPoints: CGRect(x: 100, y: 120, width: 200, height: 150),
            outputPixelSize: CGSize(width: 400, height: 300)
        ))
    }

    @Test("Mirrored displays resolve deterministically to the lowest display ID")
    func testMirroredDisplaysAreDeterministic() {
        let frame = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let mirrorA = DisplayDescriptor(displayID: 7, frameInCG: frame, scale: 2)
        let mirrorB = DisplayDescriptor(displayID: 4, frameInCG: frame, scale: 2)

        let plan = RecordingRegionPlan.make(
            globalRectInCG: CGRect(x: 40, y: 40, width: 200, height: 200),
            displays: [mirrorA, mirrorB]
        )

        #expect(plan.displayID == 4)
    }

    @Test("Invalid display descriptors are never selected as the target display")
    func testInvalidDescriptorsAreIgnored() {
        let broken = DisplayDescriptor(
            displayID: 9,
            frameInCG: CGRect(x: 0, y: 0, width: CGFloat.nan, height: 900),
            scale: 2
        )

        let plan = RecordingRegionPlan.make(
            globalRectInCG: CGRect(x: 100, y: 100, width: 200, height: 200),
            displays: [broken, Self.retinaMain]
        )

        #expect(plan.displayID == 1)
    }

    @Test("An accepted plan converts to the matching region target")
    func testAcceptedPlanBecomesRegionTarget() {
        let plan = RecordingRegionPlan.make(
            globalRectInCG: CGRect(x: 100, y: 120, width: 200, height: 150),
            displays: [Self.retinaMain]
        )

        #expect(plan.target == .region(
            displayID: 1,
            rectInDisplay: CGRect(x: 100, y: 120, width: 200, height: 150),
            outputSize: CGSize(width: 400, height: 300)
        ))
        #expect(plan.rejection == nil)
    }
}

private extension RecordingRegionPlan {
    var outputPixelSize: CGSize? {
        if case .ok(_, _, let size) = self { return size }
        return nil
    }

    var displayID: CGDirectDisplayID? {
        if case .ok(let displayID, _, _) = self { return displayID }
        return nil
    }
}
