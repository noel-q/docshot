import Testing
import Foundation
import CoreGraphics
@testable import DocShot

@Suite("PixelSampler Coordinate Tests")
struct PixelSamplerCoordinateTests {

    private let fullHD = CGRect(x: 0, y: 0, width: 1920, height: 1080)

    @Test("At 1x, a global point maps to the matching pixel on the main display")
    func testUnitScaleMapping() {
        let coordinate = DisplayGeometry.pixelCoordinate(
            forGlobalCGPoint: CGPoint(x: 100, y: 250),
            displayFrameInCG: fullHD,
            imageScale: 1
        )
        #expect(coordinate == PixelCoordinate(x: 100, y: 250))
    }

    @Test("Backing scale multiplies the offset, not the global coordinate")
    func testRetinaAndThreeTimesScale() {
        #expect(DisplayGeometry.pixelCoordinate(
            forGlobalCGPoint: CGPoint(x: 100, y: 250),
            displayFrameInCG: fullHD,
            imageScale: 2
        ) == PixelCoordinate(x: 200, y: 500))

        #expect(DisplayGeometry.pixelCoordinate(
            forGlobalCGPoint: CGPoint(x: 100, y: 250),
            displayFrameInCG: fullHD,
            imageScale: 3
        ) == PixelCoordinate(x: 300, y: 750))
    }

    @Test("A display left of main has a negative origin and still maps correctly")
    func testNegativeOriginDisplay() {
        // External display placed to the left of, and above, the main display.
        let leftDisplay = CGRect(x: -1920, y: -300, width: 1920, height: 1080)

        #expect(DisplayGeometry.pixelCoordinate(
            forGlobalCGPoint: CGPoint(x: -1910, y: -280),
            displayFrameInCG: leftDisplay,
            imageScale: 2
        ) == PixelCoordinate(x: 20, y: 40))

        // The display's own top-left corner is pixel (0, 0), not a negative pixel.
        #expect(DisplayGeometry.pixelCoordinate(
            forGlobalCGPoint: CGPoint(x: -1920, y: -300),
            displayFrameInCG: leftDisplay,
            imageScale: 2
        ) == PixelCoordinate(x: 0, y: 0))

        // A point still negative in both axes but inside the display resolves normally.
        #expect(DisplayGeometry.pixelCoordinate(
            forGlobalCGPoint: CGPoint(x: -1000, y: -100),
            displayFrameInCG: leftDisplay,
            imageScale: 1
        ) == PixelCoordinate(x: 920, y: 200))
    }

    @Test("The same global point resolves per-image on a mixed-scale pair of displays")
    func testMixedScaleDisplays() {
        // Retina main display and a 1x display to its right, sharing a top edge.
        let retinaMain = CGRect(x: 0, y: 0, width: 1440, height: 900)
        let externalOneX = CGRect(x: 1440, y: 0, width: 1920, height: 1080)

        let pointOnMain = CGPoint(x: 720, y: 450)
        #expect(DisplayGeometry.pixelCoordinate(
            forGlobalCGPoint: pointOnMain,
            displayFrameInCG: retinaMain,
            imageScale: 2
        ) == PixelCoordinate(x: 1440, y: 900))

        // Same point is outside the external display entirely.
        #expect(DisplayGeometry.pixelCoordinate(
            forGlobalCGPoint: pointOnMain,
            displayFrameInCG: externalOneX,
            imageScale: 1
        ) == nil)

        let pointOnExternal = CGPoint(x: 1540, y: 450)
        #expect(DisplayGeometry.pixelCoordinate(
            forGlobalCGPoint: pointOnExternal,
            displayFrameInCG: externalOneX,
            imageScale: 1
        ) == PixelCoordinate(x: 100, y: 450))
        #expect(DisplayGeometry.pixelCoordinate(
            forGlobalCGPoint: pointOnExternal,
            displayFrameInCG: retinaMain,
            imageScale: 2
        ) == nil)
    }

    @Test("Points on and beyond the display edges resolve deterministically")
    func testEdgeAndOutOfBoundsPoints() {
        let display = CGRect(x: 0, y: 0, width: 100, height: 100)

        // Inside the last pixel column/row.
        #expect(DisplayGeometry.pixelCoordinate(
            forGlobalCGPoint: CGPoint(x: 99.99, y: 99.99),
            displayFrameInCG: display,
            imageScale: 1
        ) == PixelCoordinate(x: 99, y: 99))

        // Exactly maxX/maxY belongs to the next display, not this one.
        #expect(DisplayGeometry.pixelCoordinate(
            forGlobalCGPoint: CGPoint(x: 100, y: 50),
            displayFrameInCG: display,
            imageScale: 1
        ) == nil)
        #expect(DisplayGeometry.pixelCoordinate(
            forGlobalCGPoint: CGPoint(x: 50, y: 100),
            displayFrameInCG: display,
            imageScale: 1
        ) == nil)

        // Just outside the top-left corner.
        #expect(DisplayGeometry.pixelCoordinate(
            forGlobalCGPoint: CGPoint(x: -0.01, y: 50),
            displayFrameInCG: display,
            imageScale: 1
        ) == nil)
        #expect(DisplayGeometry.pixelCoordinate(
            forGlobalCGPoint: CGPoint(x: 50, y: -0.01),
            displayFrameInCG: display,
            imageScale: 1
        ) == nil)
    }

    @Test("Pixel boundaries round down so a coordinate never lands on the neighbouring pixel")
    func testBoundaryRoundingIsFloor() {
        let display = CGRect(x: 0, y: 0, width: 100, height: 100)

        #expect(DisplayGeometry.pixelCoordinate(
            forGlobalCGPoint: CGPoint(x: 10.0, y: 10.0),
            displayFrameInCG: display,
            imageScale: 1
        ) == PixelCoordinate(x: 10, y: 10))

        #expect(DisplayGeometry.pixelCoordinate(
            forGlobalCGPoint: CGPoint(x: 10.999, y: 10.5),
            displayFrameInCG: display,
            imageScale: 1
        ) == PixelCoordinate(x: 10, y: 10))

        // At 2x, half a point is a whole pixel.
        #expect(DisplayGeometry.pixelCoordinate(
            forGlobalCGPoint: CGPoint(x: 10.5, y: 10.5),
            displayFrameInCG: display,
            imageScale: 2
        ) == PixelCoordinate(x: 21, y: 21))
    }

    @Test("Non-finite and degenerate inputs are rejected rather than guessed at")
    func testInvalidInputsRejected() {
        let display = CGRect(x: 0, y: 0, width: 100, height: 100)

        #expect(DisplayGeometry.pixelCoordinate(
            forGlobalCGPoint: CGPoint(x: CGFloat.nan, y: 10),
            displayFrameInCG: display,
            imageScale: 1
        ) == nil)
        #expect(DisplayGeometry.pixelCoordinate(
            forGlobalCGPoint: CGPoint(x: 10, y: CGFloat.infinity),
            displayFrameInCG: display,
            imageScale: 1
        ) == nil)
        #expect(DisplayGeometry.pixelCoordinate(
            forGlobalCGPoint: CGPoint(x: 10, y: 10),
            displayFrameInCG: display,
            imageScale: 0
        ) == nil)
        #expect(DisplayGeometry.pixelCoordinate(
            forGlobalCGPoint: CGPoint(x: 10, y: 10),
            displayFrameInCG: display,
            imageScale: -2
        ) == nil)
        #expect(DisplayGeometry.pixelCoordinate(
            forGlobalCGPoint: CGPoint(x: 10, y: 10),
            displayFrameInCG: CGRect(x: 0, y: 0, width: 0, height: 100),
            imageScale: 1
        ) == nil)
    }
}

@Suite("PixelSampler Sampling Tests")
struct PixelSamplerSamplingTests {

    private struct RGB {
        let r: Double, g: Double, b: Double
    }

    private static let sRGB = CGColorSpace(name: CGColorSpace.sRGB)!

    /// Builds a colour in sRGB explicitly. `CGColor(red:green:blue:alpha:)` produces a Generic RGB
    /// colour, which the sampler would faithfully convert to different sRGB components -- correct
    /// behaviour, but it would make these fixtures test the conversion instead of the sampling.
    private static func sRGBColor(_ rgb: RGB) -> CGColor {
        CGColor(colorSpace: sRGB, components: [rgb.r, rgb.g, rgb.b, 1.0])!
    }

    /// Builds an image whose four quadrants are solid known colours:
    /// top-left red, top-right green, bottom-left blue, bottom-right white.
    private func makeQuadrantImage(width: Int, height: Int) -> CGImage {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!

        let halfWidth = CGFloat(width) / 2
        let halfHeight = CGFloat(height) / 2

        // CGContext is Y-up, so the "top" quadrants are drawn in the upper half.
        let quadrants: [(CGRect, RGB)] = [
            (CGRect(x: 0, y: halfHeight, width: halfWidth, height: halfHeight), RGB(r: 1, g: 0, b: 0)),
            (CGRect(x: halfWidth, y: halfHeight, width: halfWidth, height: halfHeight), RGB(r: 0, g: 1, b: 0)),
            (CGRect(x: 0, y: 0, width: halfWidth, height: halfHeight), RGB(r: 0, g: 0, b: 1)),
            (CGRect(x: halfWidth, y: 0, width: halfWidth, height: halfHeight), RGB(r: 1, g: 1, b: 1))
        ]

        for (rect, colour) in quadrants {
            context.setFillColor(Self.sRGBColor(colour))
            context.fill(rect)
        }

        return context.makeImage()!
    }

    /// An image whose single top row is red and whose remaining rows are white.
    private func makeTopRowImage(width: Int, height: Int) -> CGImage {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpace(name: CGColorSpace.sRGB)!,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!

        context.setFillColor(Self.sRGBColor(RGB(r: 1, g: 1, b: 1)))
        context.fill(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        // Y-up: the image's top row is the highest row in context space.
        context.setFillColor(Self.sRGBColor(RGB(r: 1, g: 0, b: 0)))
        context.fill(CGRect(x: 0, y: CGFloat(height - 1), width: CGFloat(width), height: 1))

        return context.makeImage()!
    }

    private let red = ColorSample(red: 255, green: 0, blue: 0)
    private let green = ColorSample(red: 0, green: 255, blue: 0)
    private let blue = ColorSample(red: 0, green: 0, blue: 255)
    private let white = ColorSample(red: 255, green: 255, blue: 255)

    @Test("Sampling by pixel coordinate reads the expected quadrant colours")
    func testSampleByPixelCoordinate() {
        let image = makeQuadrantImage(width: 200, height: 200)

        #expect(PixelSampler.sample(image: image, at: PixelCoordinate(x: 50, y: 50)) == red)
        #expect(PixelSampler.sample(image: image, at: PixelCoordinate(x: 150, y: 50)) == green)
        #expect(PixelSampler.sample(image: image, at: PixelCoordinate(x: 50, y: 150)) == blue)
        #expect(PixelSampler.sample(image: image, at: PixelCoordinate(x: 150, y: 150)) == white)
    }

    @Test("Corner pixels are readable and coordinates outside the image return nil")
    func testPixelBoundsHandling() {
        let image = makeQuadrantImage(width: 200, height: 200)

        #expect(PixelSampler.sample(image: image, at: PixelCoordinate(x: 0, y: 0)) == red)
        #expect(PixelSampler.sample(image: image, at: PixelCoordinate(x: 199, y: 199)) == white)

        #expect(PixelSampler.sample(image: image, at: PixelCoordinate(x: 200, y: 100)) == nil)
        #expect(PixelSampler.sample(image: image, at: PixelCoordinate(x: 100, y: 200)) == nil)
        #expect(PixelSampler.sample(image: image, at: PixelCoordinate(x: -1, y: 100)) == nil)
        #expect(PixelSampler.sample(image: image, at: PixelCoordinate(x: 100, y: -1)) == nil)
    }

    @Test("No Y flip: a point near the display's top edge reads the image's top row")
    func testTopEdgeMapsToTopRow() {
        let image = makeTopRowImage(width: 100, height: 100)
        let display = CGRect(x: 0, y: 0, width: 100, height: 100)

        // Global CG Y grows downwards from the display's top-left, so y=0 is the top row.
        #expect(PixelSampler.sample(
            image: image,
            imageScale: 1,
            displayFrameInCG: display,
            globalPoint: CGPoint(x: 50, y: 0)
        ) == red)

        #expect(PixelSampler.sample(
            image: image,
            imageScale: 1,
            displayFrameInCG: display,
            globalPoint: CGPoint(x: 50, y: 1)
        ) == white)
    }

    @Test("Sampling through global screen space honours scale and negative display origins")
    func testGlobalPointSampling() {
        // 100x100 point display captured at 2x, so a 200x200 pixel image.
        let image = makeQuadrantImage(width: 200, height: 200)
        let display = CGRect(x: -100, y: -100, width: 100, height: 100)

        // 25 points in = pixel 50: top-left quadrant.
        #expect(PixelSampler.sample(
            image: image,
            imageScale: 2,
            displayFrameInCG: display,
            globalPoint: CGPoint(x: -75, y: -75)
        ) == red)

        // 75 points in = pixel 150: bottom-right quadrant.
        #expect(PixelSampler.sample(
            image: image,
            imageScale: 2,
            displayFrameInCG: display,
            globalPoint: CGPoint(x: -25, y: -25)
        ) == white)

        // Top-right and bottom-left quadrants.
        #expect(PixelSampler.sample(
            image: image,
            imageScale: 2,
            displayFrameInCG: display,
            globalPoint: CGPoint(x: -25, y: -75)
        ) == green)
        #expect(PixelSampler.sample(
            image: image,
            imageScale: 2,
            displayFrameInCG: display,
            globalPoint: CGPoint(x: -75, y: -25)
        ) == blue)
    }

    @Test("A point outside the display, or beyond the image, yields no sample")
    func testGlobalPointOutsideYieldsNil() {
        let image = makeQuadrantImage(width: 200, height: 200)
        let display = CGRect(x: 0, y: 0, width: 100, height: 100)

        #expect(PixelSampler.sample(
            image: image,
            imageScale: 2,
            displayFrameInCG: display,
            globalPoint: CGPoint(x: 100, y: 50)
        ) == nil)

        // An image smaller than the display implies the wrong scale was supplied: the
        // coordinate resolves but falls outside the image, and no colour is invented.
        let smallImage = makeQuadrantImage(width: 50, height: 50)
        #expect(PixelSampler.sample(
            image: smallImage,
            imageScale: 2,
            displayFrameInCG: display,
            globalPoint: CGPoint(x: 90, y: 90)
        ) == nil)
    }

    @Test("Sampling the same point twice returns identical values")
    func testSamplingIsDeterministic() {
        let image = makeQuadrantImage(width: 200, height: 200)
        let display = CGRect(x: 0, y: 0, width: 100, height: 100)
        let point = CGPoint(x: 30, y: 70)

        let first = PixelSampler.sample(image: image, imageScale: 2, displayFrameInCG: display, globalPoint: point)
        let second = PixelSampler.sample(image: image, imageScale: 2, displayFrameInCG: display, globalPoint: point)

        #expect(first == second)
        #expect(first == blue)
        #expect(first?.hexString == "#0000FF")
    }

    @Test("Samples expose hex, RGB and HSL for the same pixel")
    func testSampleFormatsFromRealPixel() throws {
        let image = makeQuadrantImage(width: 200, height: 200)
        let sample = try #require(PixelSampler.sample(image: image, at: PixelCoordinate(x: 150, y: 50)))

        #expect(sample.hexString == "#00FF00")
        #expect(sample.rgbString == "rgb(0, 255, 0)")
        #expect(sample.hslString == "hsl(120, 100%, 50%)")
    }
}
