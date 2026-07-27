import Foundation

/// A single sampled screen pixel, held as 8-bit sRGB components.
///
/// Samples are always normalised to sRGB when read, so hex values match what macOS's
/// Digital Color Meter reports in its sRGB mode and what design tools expect. This type is
/// pure data: it performs no capture, writes nothing to the clipboard, and stores no history.
public struct ColorSample: Equatable, Sendable {
    public let red: UInt8
    public let green: UInt8
    public let blue: UInt8

    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    /// Hue in 0...359 degrees, saturation and lightness as whole percentages.
    public struct HSL: Equatable, Sendable {
        public let hue: Int
        public let saturation: Int
        public let lightness: Int

        public init(hue: Int, saturation: Int, lightness: Int) {
            self.hue = hue
            self.saturation = saturation
            self.lightness = lightness
        }
    }

    /// Uppercase `#RRGGBB`. Screen captures are opaque, so no alpha component is reported.
    public var hexString: String {
        String(format: "#%02X%02X%02X", Int(red), Int(green), Int(blue))
    }

    public var rgbString: String {
        "rgb(\(Int(red)), \(Int(green)), \(Int(blue)))"
    }

    public var hslString: String {
        let hsl = self.hsl
        return "hsl(\(hsl.hue), \(hsl.saturation)%, \(hsl.lightness)%)"
    }

    /// Converts the stored sRGB components to HSL, rounded to integers.
    ///
    /// Hue is undefined for achromatic colours and is reported as 0. A hue that rounds up to
    /// 360 wraps back to 0 so the reported range is always 0...359.
    public var hsl: HSL {
        let r = Double(red) / 255.0
        let g = Double(green) / 255.0
        let b = Double(blue) / 255.0

        let maxComponent = max(r, g, b)
        let minComponent = min(r, g, b)
        let delta = maxComponent - minComponent
        let lightness = (maxComponent + minComponent) / 2.0

        guard delta > 0 else {
            return HSL(hue: 0, saturation: 0, lightness: Int((lightness * 100).rounded()))
        }

        let saturation = lightness > 0.5
            ? delta / (2.0 - maxComponent - minComponent)
            : delta / (maxComponent + minComponent)

        var hue: Double
        switch maxComponent {
        case r:
            hue = (g - b) / delta
        case g:
            hue = 2.0 + (b - r) / delta
        default:
            hue = 4.0 + (r - g) / delta
        }

        hue *= 60.0
        if hue < 0 { hue += 360.0 }

        var roundedHue = Int(hue.rounded())
        if roundedHue >= 360 { roundedHue -= 360 }

        return HSL(
            hue: roundedHue,
            saturation: Int((saturation * 100).rounded()),
            lightness: Int((lightness * 100).rounded())
        )
    }
}
