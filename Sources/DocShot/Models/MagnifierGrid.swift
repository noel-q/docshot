import Foundation
import CoreGraphics

/// A fixed 11x11 grid of sampled pixels surrounding a target pixel coordinate.
///
/// Out-of-bounds pixels (e.g. near the edges of a display) are represented as `nil`
/// elements within the 11x11 matrix, preserving the 11x11 structure with checkerboard padding
/// rather than clipping or altering grid dimensions.
public struct MagnifierGrid: Equatable, Sendable {
    public static let dimension = 11
    public static let radius = 5
    public static let centerIndex = 5 // Index 5 in 0...10 is the center

    /// 11 rows by 11 columns of pixel samples, indexed `[row][column]`.
    /// Row 0 is top (y - 5), Column 0 is left (x - 5). Center pixel is at `[5][5]`.
    public let pixels: [[ColorSample?]]
    public let centerCoordinate: PixelCoordinate

    public init(pixels: [[ColorSample?]], centerCoordinate: PixelCoordinate) {
        self.pixels = pixels
        self.centerCoordinate = centerCoordinate
    }

    public var centerSample: ColorSample? {
        guard pixels.indices.contains(Self.centerIndex),
              pixels[Self.centerIndex].indices.contains(Self.centerIndex) else {
            return nil
        }
        return pixels[Self.centerIndex][Self.centerIndex]
    }
}
