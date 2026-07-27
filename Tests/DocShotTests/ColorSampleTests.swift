import Testing
import Foundation
@testable import DocShot

@Suite("ColorSample Tests")
struct ColorSampleTests {

    @Test("Hex is uppercase #RRGGBB with no alpha component")
    func testHexFormatting() {
        #expect(ColorSample(red: 255, green: 0, blue: 0).hexString == "#FF0000")
        #expect(ColorSample(red: 0, green: 255, blue: 0).hexString == "#00FF00")
        #expect(ColorSample(red: 0, green: 0, blue: 255).hexString == "#0000FF")
        #expect(ColorSample(red: 0, green: 0, blue: 0).hexString == "#000000")
        #expect(ColorSample(red: 255, green: 255, blue: 255).hexString == "#FFFFFF")
        #expect(ColorSample(red: 26, green: 43, blue: 60).hexString == "#1A2B3C")
        // Single-digit components stay zero-padded.
        #expect(ColorSample(red: 1, green: 2, blue: 3).hexString == "#010203")
    }

    @Test("RGB string lists decimal components")
    func testRGBFormatting() {
        #expect(ColorSample(red: 26, green: 43, blue: 60).rgbString == "rgb(26, 43, 60)")
        #expect(ColorSample(red: 0, green: 0, blue: 0).rgbString == "rgb(0, 0, 0)")
        #expect(ColorSample(red: 255, green: 255, blue: 255).rgbString == "rgb(255, 255, 255)")
    }

    @Test("Primary colours convert to the expected hues")
    func testPrimaryHues() {
        #expect(ColorSample(red: 255, green: 0, blue: 0).hsl == ColorSample.HSL(hue: 0, saturation: 100, lightness: 50))
        #expect(ColorSample(red: 0, green: 255, blue: 0).hsl == ColorSample.HSL(hue: 120, saturation: 100, lightness: 50))
        #expect(ColorSample(red: 0, green: 0, blue: 255).hsl == ColorSample.HSL(hue: 240, saturation: 100, lightness: 50))
        #expect(ColorSample(red: 255, green: 255, blue: 0).hsl == ColorSample.HSL(hue: 60, saturation: 100, lightness: 50))
        #expect(ColorSample(red: 0, green: 255, blue: 255).hsl == ColorSample.HSL(hue: 180, saturation: 100, lightness: 50))
        #expect(ColorSample(red: 255, green: 0, blue: 255).hsl == ColorSample.HSL(hue: 300, saturation: 100, lightness: 50))
    }

    @Test("Achromatic colours report zero hue and zero saturation")
    func testAchromaticColours() {
        #expect(ColorSample(red: 0, green: 0, blue: 0).hsl == ColorSample.HSL(hue: 0, saturation: 0, lightness: 0))
        #expect(ColorSample(red: 255, green: 255, blue: 255).hsl == ColorSample.HSL(hue: 0, saturation: 0, lightness: 100))
        // 128/255 = 0.50196 -> 50%
        #expect(ColorSample(red: 128, green: 128, blue: 128).hsl == ColorSample.HSL(hue: 0, saturation: 0, lightness: 50))
    }

    @Test("A hue that rounds up to 360 wraps back into the 0...359 range")
    func testHueWrapAround() {
        // Just below pure red: hue computes to ~359.8 and must not be reported as 360.
        let nearRed = ColorSample(red: 255, green: 0, blue: 1).hsl
        #expect(nearRed.hue == 0)
        #expect(nearRed.hue >= 0 && nearRed.hue <= 359)
    }

    @Test("A mixed colour converts to the expected HSL triple and string")
    func testMixedColourConversion() {
        let sample = ColorSample(red: 26, green: 43, blue: 60)
        #expect(sample.hsl == ColorSample.HSL(hue: 210, saturation: 40, lightness: 17))
        #expect(sample.hslString == "hsl(210, 40%, 17%)")
    }

    @Test("Every representable component stays inside the documented HSL ranges")
    func testHSLRangesHold() {
        for value in stride(from: 0, through: 255, by: 17) {
            let component = UInt8(value)
            let samples = [
                ColorSample(red: component, green: 0, blue: 0),
                ColorSample(red: 0, green: component, blue: 128),
                ColorSample(red: 200, green: component, blue: component),
                ColorSample(red: component, green: 255 - component, blue: component / 2)
            ]

            for sample in samples {
                let hsl = sample.hsl
                #expect(hsl.hue >= 0 && hsl.hue <= 359, "Hue out of range for \(sample.hexString): \(hsl.hue)")
                #expect(hsl.saturation >= 0 && hsl.saturation <= 100, "Saturation out of range for \(sample.hexString)")
                #expect(hsl.lightness >= 0 && hsl.lightness <= 100, "Lightness out of range for \(sample.hexString)")
            }
        }
    }

    @Test("Conversion is deterministic and samples compare by value")
    func testDeterminismAndEquality() {
        let first = ColorSample(red: 26, green: 43, blue: 60)
        let second = ColorSample(red: 26, green: 43, blue: 60)

        #expect(first == second)
        #expect(first.hsl == second.hsl)
        #expect(first.hexString == second.hexString)
        #expect(first != ColorSample(red: 26, green: 43, blue: 61))
    }
}
