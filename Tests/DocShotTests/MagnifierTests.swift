import Testing
import Foundation
import CoreGraphics
@testable import DocShot

@Suite("Magnifier Tests")
struct MagnifierTests {

    private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    /// Creates a 20x20 test image where pixel (x, y) has red = x*10, green = y*10, blue = 100.
    private func makePatternImage(width: Int = 20, height: Int = 20) -> CGImage {
        let bytesPerRow = width * 4
        var rawData = [UInt8](repeating: 0, count: height * bytesPerRow)

        for y in 0..<height {
            for x in 0..<width {
                let offset = (y * width + x) * 4
                rawData[offset] = UInt8(min(255, x * 10))      // R
                rawData[offset + 1] = UInt8(min(255, y * 10))  // G
                rawData[offset + 2] = 100                      // B
                rawData[offset + 3] = 255                      // A
            }
        }

        let context = CGContext(
            data: &rawData,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: bytesPerRow,
            space: Self.sRGB,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!

        return context.makeImage()!
    }

    private func makeSnapshot(
        id: CGDirectDisplayID = 1,
        origin: CGPoint = .zero,
        scale: CGFloat = 1
    ) -> DisplaySnapshot {
        let descriptor = DisplayDescriptor(
            displayID: id,
            frameInCG: CGRect(origin: origin, size: CGSize(width: 20, height: 20)),
            scale: scale
        )
        return DisplaySnapshot(
            descriptor: descriptor,
            image: makePatternImage(width: descriptor.pixelWidth, height: descriptor.pixelHeight)
        )
    }

    @Test("MagnifierGrid preserves a fixed 11x11 matrix and center index (5,5)")
    func testGridGeometry() {
        let coord = PixelCoordinate(x: 10, y: 10)
        let image = makePatternImage()
        let grid = PixelSampler.sampleGrid(image: image, at: coord)

        #expect(grid.pixels.count == 11)
        for row in grid.pixels {
            #expect(row.count == 11)
        }
        #expect(grid.centerCoordinate == coord)
        #expect(grid.centerSample == grid.pixels[5][5])
    }

    @Test("Nearest-neighbour pixel sampling extracts exact 1:1 samples for surrounding cells")
    func testNearestNeighbourSampling() {
        let coord = PixelCoordinate(x: 10, y: 10)
        let image = makePatternImage()
        let grid = PixelSampler.sampleGrid(image: image, at: coord)

        // Center pixel at (10, 10): R = 100, G = 100, B = 100
        let center = grid.centerSample
        #expect(center != nil)
        #expect(center?.red == 100)
        #expect(center?.green == 100)
        #expect(center?.blue == 100)

        // Cell at (-1, -1) from center corresponds to pixel (9, 9): R = 90, G = 90, B = 100
        let topLeftOffset = grid.pixels[4][4]
        #expect(topLeftOffset != nil)
        #expect(topLeftOffset?.red == 90)
        #expect(topLeftOffset?.green == 90)

        // Cell at (+2, 0) from center corresponds to pixel (12, 10): R = 120, G = 100, B = 100
        let rightTwo = grid.pixels[5][7]
        #expect(rightTwo != nil)
        #expect(rightTwo?.red == 120)
        #expect(rightTwo?.green == 100)
    }

    @Test("Edge out-of-bounds sampling populates nil cells while preserving the 11x11 structure")
    func testEdgePaddingNils() {
        // Sample near top-left corner (1, 1) of a 20x20 image.
        // x - 5 = -4, y - 5 = -4 (several cells will be out of bounds < 0).
        let coord = PixelCoordinate(x: 1, y: 1)
        let image = makePatternImage()
        let grid = PixelSampler.sampleGrid(image: image, at: coord)

        #expect(grid.pixels.count == 11)
        for row in grid.pixels {
            #expect(row.count == 11)
        }

        // Top-leftmost cell [0][0] corresponds to (1-5, 1-5) = (-4, -4) -> out of bounds (nil)
        #expect(grid.pixels[0][0] == nil)
        #expect(grid.pixels[0][4] == nil)

        // Center cell [5][5] corresponds to (1, 1) -> in bounds
        #expect(grid.pixels[5][5] != nil)
        #expect(grid.pixels[5][5]?.red == 10)
        #expect(grid.pixels[5][5]?.green == 10)
    }

    @Test("ColorReadoutModel updates magnifierGrid and skips churn on sub-pixel jitter")
    @MainActor
    func testReadoutModelMagnifierLifecycle() {
        let readout = ColorReadoutModel()
        let snapshot = makeSnapshot()

        // 1. Initial state
        #expect(readout.magnifierGrid == nil)

        // 2. Update on snapshot
        readout.update(globalPoint: CGPoint(x: 10, y: 10), snapshots: [snapshot], unavailableDescriptors: [])
        #expect(readout.magnifierGrid != nil)
        #expect(readout.magnifierGrid?.centerCoordinate == PixelCoordinate(x: 10, y: 10))

        let updateCountAfterFirst = readout.publishedUpdateCount

        // 3. Sub-pixel jitter on same target pixel
        readout.update(globalPoint: CGPoint(x: 10.1, y: 10.1), snapshots: [snapshot], unavailableDescriptors: [])
        #expect(readout.publishedUpdateCount == updateCountAfterFirst)

        // 4. Clearing resets grid to nil
        readout.clear()
        #expect(readout.magnifierGrid == nil)
    }

    @Test("Moving onto an unavailable display clears the magnifier grid")
    @MainActor
    func testUnavailableDisplayClearsMagnifier() {
        let readout = ColorReadoutModel()
        let snapshot = makeSnapshot(id: 1)
        let skipped = DisplayDescriptor(
            displayID: 2,
            frameInCG: CGRect(x: 20, y: 0, width: 20, height: 20),
            scale: 1
        )

        readout.update(globalPoint: CGPoint(x: 10, y: 10), snapshots: [snapshot], unavailableDescriptors: [skipped])
        #expect(readout.magnifierGrid != nil)

        readout.update(globalPoint: CGPoint(x: 25, y: 10), snapshots: [snapshot], unavailableDescriptors: [skipped])
        #expect(readout.magnifierGrid == nil)
        #expect(readout.isUnavailable)
    }
}
