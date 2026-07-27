import Testing
import CoreGraphics
import AppKit
@testable import DocShot

@Suite("CropRendering Tests")
struct CropRenderingTests {
    
    private func createWhiteTestImage(width: Int = 200, height: Int = 200) -> CGImage {
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        )!
        context.setFillColor(CGColor(red: 1.0, green: 1.0, blue: 1.0, alpha: 1.0))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }
    
    private func getPixelColor(cgImage: CGImage, x: Int, y: Int) -> (r: UInt8, g: UInt8, b: UInt8, a: UInt8)? {
        let width = cgImage.width
        let height = cgImage.height
        guard x >= 0, x < width, y >= 0, y < height else { return nil }
        
        var pixel: [UInt8] = [0, 0, 0, 0]
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: &pixel,
            width: 1,
            height: 1,
            bitsPerComponent: 8,
            bytesPerRow: 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return nil }
        
        // CGContext is Y-up: flip y coordinate
        context.draw(cgImage, in: CGRect(x: -CGFloat(x), y: -CGFloat(height - 1 - y), width: CGFloat(width), height: CGFloat(height)))
        return (pixel[0], pixel[1], pixel[2], pixel[3])
    }
    
    @Test("Crop rendering clamps crop rect, shifts annotations, and clips pixels deterministically")
    func testCropRenderingPixelShiftAndClipping() {
        let baseImage = createWhiteTestImage(width: 200, height: 200)
        
        // Solid red rectangle at un-cropped coordinates (40, 40) with size (80, 80)
        let redRectItem = AnnotationItem(
            type: .rectangle(rect: CGRect(x: 40, y: 40, width: 80, height: 80), isFilled: true),
            color: .red,
            strokeWidth: 0
        )
        
        // Crop region (50, 50, 100, 100)
        let cropRect = CGRect(x: 50, y: 50, width: 100, height: 100)
        
        guard let pngData = ImageRenderer.shared.renderFlattenedPNG(
            baseImage: baseImage,
            annotations: [redRectItem],
            cropRect: cropRect
        ) else {
            Issue.record("Failed to render cropped PNG")
            return
        }
        
        guard let nsImage = NSImage(data: pngData),
              let cgImage = nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil) else {
            Issue.record("Failed to create CGImage from exported PNG data")
            return
        }
        
        // Assert dimensions
        #expect(cgImage.width == 100)
        #expect(cgImage.height == 100)
        
        // Pixel at (10, 10) in cropped space corresponds to (60, 60) in original image.
        // It is inside the shifted red rectangle bounds (-10, -10) to (70, 70).
        if let pixelInside = getPixelColor(cgImage: cgImage, x: 10, y: 10) {
            #expect(pixelInside.r > 200, "Expected red channel > 200 inside shifted annotation, got \(pixelInside.r)")
            #expect(pixelInside.g <= 60, "Expected green channel <= 60 inside shifted annotation, got \(pixelInside.g)")
        } else {
            Issue.record("Failed to read pixel at (10, 10)")
        }
        
        // Pixel at (90, 90) in cropped space corresponds to (140, 140) in original image.
        // It is outside the shifted red rectangle bounds.
        if let pixelOutside = getPixelColor(cgImage: cgImage, x: 90, y: 90) {
            #expect(pixelOutside.r > 200, "Expected white background red channel > 200 outside annotation, got \(pixelOutside.r)")
            #expect(pixelOutside.g > 200, "Expected white background green channel > 200 outside annotation, got \(pixelOutside.g)")
            #expect(pixelOutside.b > 200, "Expected white background blue channel > 200 outside annotation, got \(pixelOutside.b)")
        } else {
            Issue.record("Failed to read pixel at (90, 90)")
        }
    }
}
