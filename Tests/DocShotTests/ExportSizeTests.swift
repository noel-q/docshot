import Testing
import Foundation
import CoreGraphics
import AppKit
@testable import DocShot

@Suite("ExportSize Tests")
struct ExportSizeTests {

    private let source = CGSize(width: 1000, height: 800)

    // MARK: - Resolution

    @Test("Native export resolves to the source pixel dimensions")
    func testNativeResolvesToSource() throws {
        let size = try ExportSize.native.resolve(sourceSize: source).get()
        #expect(size == CGSize(width: 1000, height: 800))
    }

    @Test("Percent export scales both dimensions, downscale and upscale")
    func testPercentScaling() throws {
        let half = try ExportSize.percent(50).resolve(sourceSize: source).get()
        #expect(half == CGSize(width: 500, height: 400))

        let double = try ExportSize.percent(200).resolve(sourceSize: source).get()
        #expect(double == CGSize(width: 2000, height: 1600))
    }

    @Test("Explicit pixel export resolves to the requested dimensions")
    func testExplicitPixels() throws {
        let size = try ExportSize.pixels(width: 640, height: 512).resolve(sourceSize: source).get()
        #expect(size == CGSize(width: 640, height: 512))
    }

    // MARK: - Rounding

    @Test("Fractional results round half-up and never fall below one pixel")
    func testRoundingRules() throws {
        // 300 * 0.505 = 151.5 -> 152 (half-up, away from zero)
        let halfUp = try ExportSize.percent(50.5).resolve(sourceSize: CGSize(width: 300, height: 300)).get()
        #expect(halfUp == CGSize(width: 152, height: 152))

        // 300 * 0.33333 = 99.999 -> 100
        let roundedUp = try ExportSize.percent(33.333).resolve(sourceSize: CGSize(width: 300, height: 300)).get()
        #expect(roundedUp == CGSize(width: 100, height: 100))

        // 100 * 0.001 = 0.1 -> clamped to 1, never zero
        let clamped = try ExportSize.percent(0.1).resolve(sourceSize: CGSize(width: 100, height: 100)).get()
        #expect(clamped == CGSize(width: 1, height: 1))

        let subPixel = try ExportSize.pixels(width: 0.4, height: 0.6).resolve(sourceSize: source).get()
        #expect(subPixel == CGSize(width: 1, height: 1))
    }

    // MARK: - Validation

    @Test("Zero, negative and non-finite requests are rejected")
    func testInvalidRequestsRejected() {
        let invalidRequests: [ExportSize] = [
            .percent(0),
            .percent(-25),
            .percent(.nan),
            .percent(.infinity),
            .pixels(width: 0, height: 100),
            .pixels(width: 100, height: 0),
            .pixels(width: -100, height: 100),
            .pixels(width: .nan, height: 100),
            .pixels(width: 100, height: .infinity)
        ]

        for request in invalidRequests {
            let result = request.resolve(sourceSize: source)
            #expect(result == .failure(.invalidRequestedSize), "Expected rejection for \(request)")
        }
    }

    @Test("A source image with no usable dimensions is rejected")
    func testInvalidSourceRejected() {
        #expect(ExportSize.percent(50).resolve(sourceSize: CGSize(width: 0, height: 100)) == .failure(.invalidSourceSize))
        #expect(ExportSize.native.resolve(sourceSize: CGSize(width: 100, height: -5)) == .failure(.invalidSourceSize))
        #expect(ExportSize.pixels(width: 10, height: 10).resolve(sourceSize: CGSize(width: CGFloat.nan, height: 100)) == .failure(.invalidSourceSize))
    }

    // MARK: - Memory budget

    @Test("The 512 MB decoded-pixel budget is 134,217,728 pixels")
    func testBudgetConstant() {
        #expect(ExportSize.memoryBudgetBytes == 512 * 1024 * 1024)
        #expect(ExportSize.bytesPerPixel == 4)
        #expect(ExportSize.maximumPixelCount == 134_217_728)
    }

    @Test("Requests are accepted at the budget boundary and rejected just past it")
    func testBudgetBoundary() throws {
        // 11,585^2 = 134,212,225 pixels, just inside the budget.
        let atLimit = try ExportSize.pixels(width: 11_585, height: 11_585).resolve(sourceSize: source).get()
        #expect(atLimit == CGSize(width: 11_585, height: 11_585))

        // 11,586^2 = 134,235,396 pixels, just past it.
        let pastLimit = ExportSize.pixels(width: 11_586, height: 11_586).resolve(sourceSize: source)
        #expect(pastLimit == .failure(.exceedsMemoryBudget(
            requestedPixelCount: 134_235_396,
            budgetPixelCount: ExportSize.maximumPixelCount
        )))
    }

    @Test("An absurd percentage is rejected by the budget rather than attempted")
    func testAbsurdPercentRejected() {
        let result = ExportSize.percent(100_000).resolve(sourceSize: source)
        guard case .failure(.exceedsMemoryBudget) = result else {
            Issue.record("Expected memory budget rejection, got \(result)")
            return
        }
    }

    @Test("Native export is never blocked by the export budget")
    func testNativeBypassesBudget() throws {
        // A capture this large already exists in memory; refusing to export it would be wrong.
        let huge = CGSize(width: 20_000, height: 20_000)
        let size = try ExportSize.native.resolve(sourceSize: huge).get()
        #expect(size == huge)
    }

    // MARK: - Aspect lock

    @Test("Aspect-locked dimensions preserve the source ratio and reject bad input")
    func testAspectLock() {
        #expect(ExportSize.aspectLockedHeight(forWidth: 500, sourceSize: source) == 400)
        #expect(ExportSize.aspectLockedWidth(forHeight: 400, sourceSize: source) == 500)

        // 333 * (800/1000) = 266.4 -> 266
        #expect(ExportSize.aspectLockedHeight(forWidth: 333, sourceSize: source) == 266)

        #expect(ExportSize.aspectLockedHeight(forWidth: 0, sourceSize: source) == nil)
        #expect(ExportSize.aspectLockedWidth(forHeight: .nan, sourceSize: source) == nil)
        #expect(ExportSize.aspectLockedHeight(forWidth: 100, sourceSize: CGSize(width: 0, height: 100)) == nil)
    }
}

@Suite("Export Resizing Pipeline Tests")
struct ExportResizingPipelineTests {

    private func makeWhiteImage(width: Int, height: Int) -> CGImage {
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    private func pixelColor(_ cgImage: CGImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8)? {
        guard x >= 0, x < cgImage.width, y >= 0, y < cgImage.height else { return nil }
        var pixel: [UInt8] = [0, 0, 0, 0]
        guard let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }

        // CGContext is Y-up: flip y coordinate
        context.draw(cgImage, in: CGRect(
            x: -CGFloat(x),
            y: -CGFloat(cgImage.height - 1 - y),
            width: CGFloat(cgImage.width),
            height: CGFloat(cgImage.height)
        ))
        return (pixel[0], pixel[1], pixel[2], pixel[3])
    }

    private func decode(_ data: Data) -> CGImage? {
        NSImage(data: data)?.cgImage(forProposedRect: nil, context: nil, hints: nil)
    }

    private var redRectAnnotation: AnnotationItem {
        AnnotationItem(
            type: .rectangle(rect: CGRect(x: 40, y: 40, width: 80, height: 80), isFilled: true),
            color: .red,
            strokeWidth: 0
        )
    }

    @Test("Exporting at 50% halves the output and scales annotation placement with it")
    func testHalfSizeExportScalesAnnotations() async throws {
        let baseImage = makeWhiteImage(width: 200, height: 200)

        let data = try await ExportService.shared.exportPNGResult(
            baseImage: baseImage,
            annotations: [redRectAnnotation],
            cropRect: nil,
            exportSize: .percent(50)
        ).get()

        let exported = try #require(decode(data))
        #expect(exported.width == 100)
        #expect(exported.height == 100)

        // Source (60, 60) is inside the red rect (40...120); at 50% that is output (30, 30).
        let inside = try #require(pixelColor(exported, x: 30, y: 30))
        #expect(inside.r > 200, "Expected red inside the scaled annotation, got r=\(inside.r)")
        #expect(inside.g <= 60, "Expected low green inside the scaled annotation, got g=\(inside.g)")

        // Source (180, 180) is outside the red rect; at 50% that is output (90, 90).
        let outside = try #require(pixelColor(exported, x: 90, y: 90))
        #expect(outside.r > 200 && outside.g > 200 && outside.b > 200, "Expected white background outside the annotation")
    }

    @Test("Upscaling above 100% is permitted up to the budget")
    func testUpscaleExport() async throws {
        let baseImage = makeWhiteImage(width: 200, height: 200)

        let data = try await ExportService.shared.exportPNGResult(
            baseImage: baseImage,
            annotations: [redRectAnnotation],
            cropRect: nil,
            exportSize: .percent(250)
        ).get()

        let exported = try #require(decode(data))
        #expect(exported.width == 500)
        #expect(exported.height == 500)
    }

    @Test("Resizing applies to the cropped image, not the original capture")
    func testResizeAppliesAfterCrop() async throws {
        let baseImage = makeWhiteImage(width: 200, height: 200)

        let data = try await ExportService.shared.exportPNGResult(
            baseImage: baseImage,
            annotations: [redRectAnnotation],
            cropRect: CGRect(x: 50, y: 50, width: 100, height: 100),
            exportSize: .percent(50)
        ).get()

        let exported = try #require(decode(data))
        #expect(exported.width == 50)
        #expect(exported.height == 50)
    }

    @Test("Predicted flattened size matches the exported pixels, including fractional crops")
    func testFlattenedPixelSizePrediction() async throws {
        let baseImage = makeWhiteImage(width: 200, height: 200)
        let fractionalCrop = CGRect(x: 50.5, y: 40.25, width: 100.2, height: 80.75)

        let predicted = ImageRenderer.flattenedPixelSize(
            baseWidth: baseImage.width,
            baseHeight: baseImage.height,
            cropRect: fractionalCrop
        )

        let data = try await ExportService.shared.exportPNGResult(
            baseImage: baseImage,
            annotations: [],
            cropRect: fractionalCrop,
            exportSize: .native
        ).get()

        let exported = try #require(decode(data))
        #expect(CGFloat(exported.width) == predicted.width)
        #expect(CGFloat(exported.height) == predicted.height)
    }

    @Test("A crop below the 10 px minimum is ignored and the full image is exported")
    func testUndersizedCropIgnored() {
        let size = ImageRenderer.flattenedPixelSize(
            baseWidth: 200,
            baseHeight: 200,
            cropRect: CGRect(x: 10, y: 10, width: 4, height: 4)
        )
        #expect(size == CGSize(width: 200, height: 200))
        #expect(ImageRenderer.effectiveCropRect(baseWidth: 200, baseHeight: 200, cropRect: nil) == nil)
    }

    @Test("Native export is unchanged: dimensions match the flatten and no resampling occurs")
    func testNativeExportRegression() async throws {
        let baseImage = makeWhiteImage(width: 200, height: 200)
        let crop = CGRect(x: 50, y: 50, width: 100, height: 100)

        let nativeData = try await ExportService.shared.exportPNGResult(
            baseImage: baseImage,
            annotations: [redRectAnnotation],
            cropRect: crop,
            exportSize: .native
        ).get()

        let legacyData = try #require(ImageRenderer.shared.renderFlattenedPNG(
            baseImage: baseImage,
            annotations: [redRectAnnotation],
            cropRect: crop
        ))

        #expect(nativeData == legacyData, "Native export must stay byte-identical to the V1 render path")

        let exported = try #require(decode(nativeData))
        #expect(exported.width == 100)
        #expect(exported.height == 100)
    }

    @Test("An over-budget export fails with a typed sizing error and no PNG data")
    func testOverBudgetExportFails() async {
        let baseImage = makeWhiteImage(width: 200, height: 200)

        let result = await ExportService.shared.exportPNGResult(
            baseImage: baseImage,
            annotations: [],
            cropRect: nil,
            exportSize: .pixels(width: 30_000, height: 30_000)
        )

        guard case .failure(.sizing(.exceedsMemoryBudget)) = result else {
            Issue.record("Expected a memory budget failure, got \(result)")
            return
        }

        let optionalData = await ExportService.shared.exportPNG(
            baseImage: baseImage,
            annotations: [],
            cropRect: nil,
            exportSize: .pixels(width: 30_000, height: 30_000)
        )
        #expect(optionalData == nil)
    }
}
