import Foundation
import CoreGraphics

/// Reads individual pixels out of an already-captured image and reports them as sRGB samples.
///
/// This type performs no screen capture of its own, holds no state, retains nothing, and never
/// touches the pasteboard. It answers exactly one question: what colour is the pixel under this
/// point, given an image and the display geometry that image belongs to.
public enum PixelSampler {

    /// Samples a pixel by its position within the image, with the origin at the top-left pixel.
    ///
    /// The pixel is drawn through a 1x1 sRGB context, so the returned components are normalised
    /// to sRGB regardless of the source image's colour space (Display P3 captures included).
    /// Interpolation is disabled so the value is the pixel itself, never a blend of neighbours.
    public static func sample(image: CGImage, at coordinate: PixelCoordinate) -> ColorSample? {
        guard coordinate.x >= 0, coordinate.y >= 0,
              coordinate.x < image.width, coordinate.y < image.height else {
            return nil
        }

        guard let colorSpace = CGColorSpace(name: CGColorSpace.sRGB) else { return nil }

        var pixel: [UInt8] = [0, 0, 0, 0]
        let sampled: Bool = pixel.withUnsafeMutableBytes { buffer -> Bool in
            guard let context = CGContext(
                data: buffer.baseAddress,
                width: 1,
                height: 1,
                bitsPerComponent: 8,
                bytesPerRow: 4,
                space: colorSpace,
                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            ) else {
                return false
            }

            context.interpolationQuality = .none

            // CGContext draws Y-up while image row 0 is the top row, so the vertical offset is
            // measured from the bottom: translate the wanted pixel onto the 1x1 context origin.
            context.draw(image, in: CGRect(
                x: -CGFloat(coordinate.x),
                y: -CGFloat(image.height - 1 - coordinate.y),
                width: CGFloat(image.width),
                height: CGFloat(image.height)
            ))
            return true
        }

        guard sampled else { return nil }
        return ColorSample(red: pixel[0], green: pixel[1], blue: pixel[2])
    }

    /// Samples the pixel under a point in global Core Graphics screen space.
    ///
    /// - Parameters:
    ///   - image: A capture of a single display. Passing a multi-display composite is incorrect:
    ///     `ScreenCaptureService` normalises composites to the highest scale present, so their
    ///     pixels no longer map 1:1 to any one display.
    ///   - imageScale: The scale `image` was captured at, not assumed from the display.
    ///   - displayFrameInCG: The display's frame in global CG space, origin allowed to be negative.
    ///   - globalPoint: The point to sample, in global CG space.
    /// - Returns: The sample, or `nil` if the point is outside the display or the image.
    public static func sample(
        image: CGImage,
        imageScale: CGFloat,
        displayFrameInCG: CGRect,
        globalPoint: CGPoint
    ) -> ColorSample? {
        guard let coordinate = DisplayGeometry.pixelCoordinate(
            forGlobalCGPoint: globalPoint,
            displayFrameInCG: displayFrameInCG,
            imageScale: imageScale
        ) else {
            return nil
        }

        return sample(image: image, at: coordinate)
    }

    /// Samples an 11x11 grid of pixels centered at `centerCoordinate`, preserving a fixed 11x11 matrix.
    ///
    /// Out-of-bounds cells return `nil` so the caller can render empty/checkerboard edge padding.
    public static func sampleGrid(
        image: CGImage,
        at centerCoordinate: PixelCoordinate,
        radius: Int = MagnifierGrid.radius
    ) -> MagnifierGrid {
        let dimension = radius * 2 + 1
        var gridRows: [[ColorSample?]] = []
        gridRows.reserveCapacity(dimension)

        for r in -radius...radius {
            var row: [ColorSample?] = []
            row.reserveCapacity(dimension)
            for c in -radius...radius {
                let coord = PixelCoordinate(x: centerCoordinate.x + c, y: centerCoordinate.y + r)
                row.append(sample(image: image, at: coord))
            }
            gridRows.append(row)
        }

        return MagnifierGrid(pixels: gridRows, centerCoordinate: centerCoordinate)
    }
}
