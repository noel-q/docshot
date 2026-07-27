import Foundation
import CoreGraphics

/// Identity and geometry of one connected display, as needed to capture and sample it.
public struct DisplayDescriptor: Equatable, Sendable {
    public let displayID: CGDirectDisplayID
    /// The display's frame in global Core Graphics space. The origin may be negative.
    public let frameInCG: CGRect
    /// The scale the display's snapshot is captured at.
    public let scale: CGFloat

    public init(displayID: CGDirectDisplayID, frameInCG: CGRect, scale: CGFloat) {
        self.displayID = displayID
        self.frameInCG = frameInCG
        self.scale = scale
    }

    /// A display can only be snapshotted if its geometry is finite and positive.
    public var isValid: Bool {
        frameInCG.origin.x.isFinite && frameInCG.origin.y.isFinite &&
        frameInCG.width.isFinite && frameInCG.height.isFinite &&
        frameInCG.width > 0 && frameInCG.height > 0 &&
        scale.isFinite && scale > 0
    }

    public var pixelWidth: Int {
        guard isValid else { return 0 }
        return Int((frameInCG.width * scale).rounded())
    }

    public var pixelHeight: Int {
        guard isValid else { return 0 }
        return Int((frameInCG.height * scale).rounded())
    }

    /// Decoded pixels a snapshot of this display would occupy. Zero when the display is invalid.
    public var pixelCount: Int {
        pixelWidth * pixelHeight
    }

    public func contains(globalPoint point: CGPoint) -> Bool {
        guard isValid, point.x.isFinite, point.y.isFinite else { return false }
        let relativeX = point.x - frameInCG.origin.x
        let relativeY = point.y - frameInCG.origin.y
        return relativeX >= 0 && relativeY >= 0
            && relativeX < frameInCG.width && relativeY < frameInCG.height
    }
}

/// A frozen image of one display, captured before any DocShot overlay exists.
///
/// Snapshots live only for the duration of a selection session. They are released when the
/// overlays close, so DocShot never accumulates a capture history or image library.
public struct DisplaySnapshot: @unchecked Sendable {
    public let descriptor: DisplayDescriptor
    public let image: CGImage

    public init(descriptor: DisplayDescriptor, image: CGImage) {
        self.descriptor = descriptor
        self.image = image
    }

    public func contains(globalPoint point: CGPoint) -> Bool {
        descriptor.contains(globalPoint: point)
    }

    /// Samples the pixel under a global Core Graphics point, normalised to sRGB.
    /// The snapshot's own captured scale is used, never an assumed backing scale factor.
    public func sample(atGlobalPoint point: CGPoint) -> ColorSample? {
        PixelSampler.sample(
            image: image,
            imageScale: descriptor.scale,
            displayFrameInCG: descriptor.frameInCG,
            globalPoint: point
        )
    }
}
