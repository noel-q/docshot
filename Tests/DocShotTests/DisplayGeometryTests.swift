import Testing
import CoreGraphics
import AppKit
@testable import DocShot

@Suite("DisplayGeometry Tests")
struct DisplayGeometryTests {
    
    @Test("Cocoa to CoreGraphics point conversion")
    func testPointConversion() {
        let mainHeight: CGFloat = 1080
        let cocoaPoint = CGPoint(x: 100, y: 800)
        let cgPoint = DisplayGeometry.cocoaToCGPoint(cocoaPoint, mainScreenHeight: mainHeight)
        
        #expect(cgPoint.x == 100)
        #expect(cgPoint.y == 280) // 1080 - 800
        
        let backToCocoa = DisplayGeometry.cgToCocoaPoint(cgPoint, mainScreenHeight: mainHeight)
        #expect(backToCocoa == cocoaPoint)
    }
    
    @Test("Cocoa to CoreGraphics rect conversion")
    func testRectConversion() {
        let mainHeight: CGFloat = 1080
        let cocoaRect = CGRect(x: 50, y: 600, width: 400, height: 300)
        let cgRect = DisplayGeometry.cocoaToCGRect(cocoaRect, mainScreenHeight: mainHeight)
        
        #expect(cgRect.origin.x == 50)
        #expect(cgRect.origin.y == 180)
        #expect(cgRect.width == 400)
        #expect(cgRect.height == 300)
        
        let backToCocoa = DisplayGeometry.cgToCocoaRect(cgRect, mainScreenHeight: mainHeight)
        #expect(backToCocoa == cocoaRect)
    }
    
    @Test("Multi-display with negative origin and mixed scale factors")
    func testMultiDisplayNegativeOrigin() {
        let mainHeight: CGFloat = 1080
        
        // Secondary screen positioned to the left of main screen (origin x: -1920, y: 0)
        let secondaryCocoaFrame = CGRect(x: -1920, y: 0, width: 1920, height: 1080)
        let secondaryCGRect = DisplayGeometry.cocoaToCGRect(secondaryCocoaFrame, mainScreenHeight: mainHeight)
        
        #expect(secondaryCGRect.origin.x == -1920)
        #expect(secondaryCGRect.origin.y == 0) // 1080 - (0 + 1080)
        #expect(secondaryCGRect.width == 1920)
        #expect(secondaryCGRect.height == 1080)
        
        // Test scale conversion across 1x and 2x Retina backing scale factors
        let rect1x = CGRect(x: 100, y: 100, width: 400, height: 300)
        let scaled1x = DisplayGeometry.scaleRect(rect1x, scale: 1.0)
        #expect(scaled1x == rect1x)
        
        let scaled2x = DisplayGeometry.scaleRect(rect1x, scale: 2.0)
        #expect(scaled2x == CGRect(x: 200, y: 200, width: 800, height: 600))
    }
    
    @Test("Rect normalization and scaling")
    func testRectNormalizeAndScale() {
        let invertedRect = CGRect(x: 200, y: 300, width: -100, height: -50)
        let normalized = DisplayGeometry.normalizeRect(invertedRect)
        
        #expect(normalized.origin.x == 100)
        #expect(normalized.origin.y == 250)
        #expect(normalized.width == 100)
        #expect(normalized.height == 50)
        
        let scaled = DisplayGeometry.scaleRect(normalized, scale: 2.0)
        #expect(scaled.origin.x == 200)
        #expect(scaled.origin.y == 500)
        #expect(scaled.width == 200)
        #expect(scaled.height == 100)
    }
}
