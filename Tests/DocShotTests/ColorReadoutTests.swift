import Testing
import Foundation
import CoreGraphics
@testable import DocShot

@Suite("ColorReadout Tests")
struct ColorReadoutTests {

    private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    /// Left half red, right half blue, so moving horizontally changes the sampled pixel.
    private func makeSplitImage(width: Int, height: Int) -> CGImage {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: Self.sRGB,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!

        context.setFillColor(CGColor(colorSpace: Self.sRGB, components: [1, 0, 0, 1])!)
        context.fill(CGRect(x: 0, y: 0, width: CGFloat(width) / 2, height: CGFloat(height)))
        context.setFillColor(CGColor(colorSpace: Self.sRGB, components: [0, 0, 1, 1])!)
        context.fill(CGRect(x: CGFloat(width) / 2, y: 0, width: CGFloat(width) / 2, height: CGFloat(height)))

        return context.makeImage()!
    }

    private func makeSnapshot(
        id: CGDirectDisplayID = 1,
        origin: CGPoint = .zero,
        scale: CGFloat = 2
    ) -> DisplaySnapshot {
        let descriptor = DisplayDescriptor(
            displayID: id,
            frameInCG: CGRect(origin: origin, size: CGSize(width: 100, height: 100)),
            scale: scale
        )
        return DisplaySnapshot(
            descriptor: descriptor,
            image: makeSplitImage(width: descriptor.pixelWidth, height: descriptor.pixelHeight)
        )
    }

    @Test("The readout starts empty and shows placeholders")
    @MainActor
    func testInitialState() {
        let readout = ColorReadoutModel()

        #expect(readout.sample == nil)
        #expect(readout.isUnavailable == false)
        #expect(readout.hexText == "—")
        #expect(readout.rgbText == "—")
        #expect(readout.hslText == "—")
        #expect(readout.swatchColor == nil)
    }

    @Test("A point on a snapshot publishes the sampled colour in all three formats")
    @MainActor
    func testSamplesUnderCursor() {
        let readout = ColorReadoutModel()
        let snapshot = makeSnapshot()

        readout.update(globalPoint: CGPoint(x: 10, y: 50), snapshots: [snapshot], unavailableDescriptors: [])

        #expect(readout.sample == ColorSample(red: 255, green: 0, blue: 0))
        #expect(readout.hexText == "#FF0000")
        #expect(readout.rgbText == "rgb(255, 0, 0)")
        #expect(readout.hslText == "hsl(0, 100%, 50%)")
        #expect(readout.isUnavailable == false)
        #expect(readout.swatchColor != nil)
    }

    @Test("Repeated events on the same pixel publish only once")
    @MainActor
    func testNoChurnOnSamePixel() {
        let readout = ColorReadoutModel()
        let snapshot = makeSnapshot()

        readout.update(globalPoint: CGPoint(x: 10.0, y: 50.0), snapshots: [snapshot], unavailableDescriptors: [])
        let afterFirst = readout.publishedUpdateCount

        // Sub-pixel jitter inside the same pixel: at 2x, a 0.1pt move stays in the same pixel.
        readout.update(globalPoint: CGPoint(x: 10.1, y: 50.1), snapshots: [snapshot], unavailableDescriptors: [])
        readout.update(globalPoint: CGPoint(x: 10.2, y: 50.0), snapshots: [snapshot], unavailableDescriptors: [])

        #expect(readout.publishedUpdateCount == afterFirst)
        #expect(readout.sample == ColorSample(red: 255, green: 0, blue: 0))
    }

    @Test("Moving to a different pixel publishes a new value")
    @MainActor
    func testPublishesOnPixelChange() {
        let readout = ColorReadoutModel()
        let snapshot = makeSnapshot()

        readout.update(globalPoint: CGPoint(x: 10, y: 50), snapshots: [snapshot], unavailableDescriptors: [])
        let afterFirst = readout.publishedUpdateCount

        // Cross into the blue half of the display.
        readout.update(globalPoint: CGPoint(x: 80, y: 50), snapshots: [snapshot], unavailableDescriptors: [])

        #expect(readout.publishedUpdateCount == afterFirst + 1)
        #expect(readout.sample == ColorSample(red: 0, green: 0, blue: 255))
        #expect(readout.hexText == "#0000FF")
    }

    @Test("A display without a snapshot reports unavailable instead of a colour")
    @MainActor
    func testUnavailableDisplay() {
        let readout = ColorReadoutModel()
        let snapshot = makeSnapshot(id: 1)
        let skipped = DisplayDescriptor(
            displayID: 2,
            frameInCG: CGRect(x: 100, y: 0, width: 100, height: 100),
            scale: 2
        )

        readout.update(globalPoint: CGPoint(x: 150, y: 50), snapshots: [snapshot], unavailableDescriptors: [skipped])

        #expect(readout.isUnavailable)
        #expect(readout.sample == nil)
        #expect(readout.hexText == "—")
    }

    @Test("Moving from an unavailable display back onto a snapshot restores sampling")
    @MainActor
    func testRecoveryFromUnavailableDisplay() {
        let readout = ColorReadoutModel()
        let snapshot = makeSnapshot(id: 1)
        let skipped = DisplayDescriptor(
            displayID: 2,
            frameInCG: CGRect(x: 100, y: 0, width: 100, height: 100),
            scale: 2
        )

        readout.update(globalPoint: CGPoint(x: 150, y: 50), snapshots: [snapshot], unavailableDescriptors: [skipped])
        #expect(readout.isUnavailable)

        readout.update(globalPoint: CGPoint(x: 10, y: 50), snapshots: [snapshot], unavailableDescriptors: [skipped])

        #expect(readout.isUnavailable == false)
        #expect(readout.sample == ColorSample(red: 255, green: 0, blue: 0))
    }

    @Test("A point on no known display clears the readout")
    @MainActor
    func testPointOutsideEveryDisplay() {
        let readout = ColorReadoutModel()
        let snapshot = makeSnapshot()

        readout.update(globalPoint: CGPoint(x: 10, y: 50), snapshots: [snapshot], unavailableDescriptors: [])
        #expect(readout.sample != nil)

        readout.update(globalPoint: CGPoint(x: 5000, y: 5000), snapshots: [snapshot], unavailableDescriptors: [])

        #expect(readout.sample == nil)
        #expect(readout.isUnavailable == false)
    }

    @Test("Sampling with no snapshots at all yields nothing")
    @MainActor
    func testNoSnapshotsYieldsNothing() {
        let readout = ColorReadoutModel()

        readout.update(globalPoint: CGPoint(x: 10, y: 50), snapshots: [], unavailableDescriptors: [])

        #expect(readout.sample == nil)
        #expect(readout.isUnavailable == false)
    }

    @Test("Clearing resets the readout and retains no sampled colour")
    @MainActor
    func testClearRetainsNothing() {
        let readout = ColorReadoutModel()
        let snapshot = makeSnapshot()

        readout.update(globalPoint: CGPoint(x: 10, y: 50), snapshots: [snapshot], unavailableDescriptors: [])
        #expect(readout.sample != nil)

        readout.clear()

        #expect(readout.sample == nil)
        #expect(readout.isUnavailable == false)
        #expect(readout.hexText == "—")

        // Clearing twice does not churn the UI.
        let afterClear = readout.publishedUpdateCount
        readout.clear()
        #expect(readout.publishedUpdateCount == afterClear)
    }

    @Test("Each display is sampled at its own scale on a mixed-scale layout")
    @MainActor
    func testMixedScaleReadout() {
        let readout = ColorReadoutModel()
        let retina = makeSnapshot(id: 1, origin: CGPoint(x: -100, y: -50), scale: 2)
        let oneX = makeSnapshot(id: 2, origin: CGPoint(x: 0, y: 0), scale: 1)

        // Left edge of the negative-origin Retina display: red half.
        readout.update(globalPoint: CGPoint(x: -90, y: 0), snapshots: [retina, oneX], unavailableDescriptors: [])
        #expect(readout.sample == ColorSample(red: 255, green: 0, blue: 0))

        // Right half of the 1x display: blue half.
        readout.update(globalPoint: CGPoint(x: 80, y: 50), snapshots: [retina, oneX], unavailableDescriptors: [])
        #expect(readout.sample == ColorSample(red: 0, green: 0, blue: 255))
    }
}
