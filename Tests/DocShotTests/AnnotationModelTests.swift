import Testing
import CoreGraphics
@testable import DocShot

@Suite("AnnotationModel Tests")
struct AnnotationModelTests {
    
    @Test("Rectangle annotation bounding box and translation")
    func testRectangleAnnotation() {
        var item = AnnotationItem(
            type: .rectangle(rect: CGRect(x: 10, y: 20, width: 100, height: 50), isFilled: false),
            color: .red,
            strokeWidth: 2.0
        )
        
        #expect(item.boundingBox.origin.x == 10)
        #expect(item.boundingBox.origin.y == 20)
        #expect(item.boundingBox.width == 100)
        #expect(item.boundingBox.height == 50)
        
        item.translate(by: CGSize(width: 15, height: -5))
        
        #expect(item.boundingBox.origin.x == 25)
        #expect(item.boundingBox.origin.y == 15)
    }
    
    @Test("Arrow annotation bounding box and translation")
    func testArrowAnnotation() {
        var item = AnnotationItem(
            type: .arrow(start: CGPoint(x: 0, y: 0), end: CGPoint(x: 100, y: 50)),
            color: .blue,
            strokeWidth: 4.0
        )
        
        #expect(item.boundingBox.origin.x == 0)
        #expect(item.boundingBox.origin.y == 0)
        #expect(item.boundingBox.width == 100)
        #expect(item.boundingBox.height == 50)
        
        item.translate(by: CGSize(width: 20, height: 30))
        
        if case .arrow(let start, let end) = item.type {
            #expect(start == CGPoint(x: 20, y: 30))
            #expect(end == CGPoint(x: 120, y: 80))
        } else {
            Issue.record("Expected arrow type")
        }
    }
}
