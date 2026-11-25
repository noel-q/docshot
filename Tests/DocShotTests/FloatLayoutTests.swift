import CoreGraphics
import Testing
@testable import DocShot

@Suite("Float layout")
struct FloatLayoutTests {
    let screen = CGRect(x: 0, y: 0, width: 1440, height: 875)

    @Test("A large image is fitted to 480 points on its long side; a small one is not enlarged")
    func size() {
        #expect(FloatLayout.size(pixelSize: CGSize(width: 3000, height: 1500), backingScale: 2, visible: screen) == CGSize(width: 480, height: 240))
        #expect(FloatLayout.size(pixelSize: CGSize(width: 200, height: 100), backingScale: 2, visible: screen) == CGSize(width: 100, height: 50))
        #expect(FloatLayout.size(pixelSize: .zero, backingScale: 0, visible: screen).width >= 1)
    }

    @Test("Floats open centred and cascade down and right, always on screen")
    func cascade() {
        let size = CGSize(width: 400, height: 300)
        let first = FloatLayout.frame(size: size, visible: screen, index: 0)
        let second = FloatLayout.frame(size: size, visible: screen, index: 1)
        #expect(abs(first.midX - screen.midX) <= 1 && abs(first.midY - screen.midY) <= 1)
        #expect(second.minX == first.minX + FloatLayout.cascade && second.minY == first.minY - FloatLayout.cascade)
        #expect(screen.contains(FloatLayout.frame(size: CGSize(width: 1400, height: 860), visible: screen, index: 9)))
    }
}
