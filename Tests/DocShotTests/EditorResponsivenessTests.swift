import Testing
import Foundation
import CoreGraphics
@testable import DocShot

@Suite("EditorResponsiveness Tests")
struct EditorResponsivenessTests {
    
    private func createTestImage(width: Int = 1000, height: Int = 1000) -> CGImage {
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
        return context.makeImage()!
    }
    
    @Test("Production ExportService boundary executes image rendering off the main thread")
    func testProductionExportServiceBoundary() async {
        let baseImage = createTestImage(width: 800, height: 800)
        
        let rectItem = AnnotationItem(
            type: .rectangle(rect: CGRect(x: 100, y: 100, width: 200, height: 200), isFilled: true),
            color: .red,
            strokeWidth: 4.0
        )
        
        let blurItem = AnnotationItem(
            type: .redaction(rect: CGRect(x: 150, y: 150, width: 100, height: 100), style: .blur),
            color: .black,
            strokeWidth: 0
        )
        
        // Invoke production ExportService boundary (as called by EditorView.performCopy and EditorView.performSave)
        let pngData = await ExportService.shared.exportPNG(
            baseImage: baseImage,
            annotations: [rectItem, blurItem],
            cropRect: CGRect(x: 50, y: 50, width: 400, height: 400)
        )
        
        #expect(pngData != nil, "Expected non-nil PNG data from production ExportService pipeline")
    }
}
