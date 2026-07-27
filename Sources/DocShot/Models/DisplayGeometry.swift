import Foundation
import CoreGraphics
import AppKit

/// A pixel position inside a captured image, with the origin at the image's top-left pixel.
public struct PixelCoordinate: Equatable, Sendable {
    public let x: Int
    public let y: Int

    public init(x: Int, y: Int) {
        self.x = x
        self.y = y
    }
}

/// Pure helper functions for coordinate conversions between AppKit (Cocoa) screen space,
/// Core Graphics screen space, and pixel buffers.
public enum DisplayGeometry {
    
    /// Converts a point from AppKit Cocoa coordinates (origin at bottom-left of main screen, Y-up)
    /// to Core Graphics coordinates (origin at top-left of main screen, Y-down).
    public static func cocoaToCGPoint(_ point: CGPoint, mainScreenHeight: CGFloat) -> CGPoint {
        return CGPoint(x: point.x, y: mainScreenHeight - point.y)
    }
    
    /// Converts a point from Core Graphics coordinates to AppKit Cocoa coordinates.
    public static func cgToCocoaPoint(_ point: CGPoint, mainScreenHeight: CGFloat) -> CGPoint {
        return CGPoint(x: point.x, y: mainScreenHeight - point.y)
    }
    
    /// Converts a rectangle from AppKit Cocoa coordinates to Core Graphics coordinates.
    public static func cocoaToCGRect(_ rect: CGRect, mainScreenHeight: CGFloat) -> CGRect {
        let cgY = mainScreenHeight - (rect.origin.y + rect.size.height)
        return CGRect(x: rect.origin.x, y: cgY, width: rect.size.width, height: rect.size.height)
    }
    
    /// Converts a rectangle from Core Graphics coordinates to AppKit Cocoa coordinates.
    public static func cgToCocoaRect(_ rect: CGRect, mainScreenHeight: CGFloat) -> CGRect {
        let cocoaY = mainScreenHeight - (rect.origin.y + rect.size.height)
        return CGRect(x: rect.origin.x, y: cocoaY, width: rect.size.width, height: rect.size.height)
    }
    
    /// Scales a rectangle by a scale factor (e.g. Retina backing scale factor).
    public static func scaleRect(_ rect: CGRect, scale: CGFloat) -> CGRect {
        return CGRect(
            x: rect.origin.x * scale,
            y: rect.origin.y * scale,
            width: rect.size.width * scale,
            height: rect.size.height * scale
        )
    }
    
    /// Normalizes a rectangle so width and height are non-negative.
    public static func normalizeRect(_ rect: CGRect) -> CGRect {
        var x = rect.origin.x
        var y = rect.origin.y
        var w = rect.size.width
        var h = rect.size.height
        
        if w < 0 {
            x += w
            w = abs(w)
        }
        if h < 0 {
            y += h
            h = abs(h)
        }
        return CGRect(x: x, y: y, width: w, height: h)
    }
    
    /// Converts a point in global Core Graphics screen space to a pixel coordinate inside a
    /// single display's captured image.
    ///
    /// The conversion is `pixel = floor((globalPoint - displayOrigin) * imageScale)`. Subtracting
    /// the display origin before scaling is what keeps displays with negative origins correct:
    /// a display placed left of or above the main display has a negative origin in global CG
    /// space, and the intermediate offset must stay signed.
    ///
    /// No Y flip is applied. Global CG space measures Y downwards from the main display's
    /// top-left, and `CGImage` row 0 is the top row, so both already agree.
    ///
    /// `imageScale` is the scale of the *image being sampled*, not necessarily the display's
    /// backing scale factor. Passing the wrong scale silently returns the wrong pixel, so callers
    /// must pass the scale the image was actually captured at.
    ///
    /// Returns `nil` when the point falls outside the display, or when the inputs are not finite.
    public static func pixelCoordinate(
        forGlobalCGPoint point: CGPoint,
        displayFrameInCG frame: CGRect,
        imageScale: CGFloat
    ) -> PixelCoordinate? {
        guard point.x.isFinite, point.y.isFinite,
              frame.origin.x.isFinite, frame.origin.y.isFinite,
              frame.width.isFinite, frame.height.isFinite,
              imageScale.isFinite, imageScale > 0,
              frame.width > 0, frame.height > 0 else {
            return nil
        }

        let relativeX = point.x - frame.origin.x
        let relativeY = point.y - frame.origin.y

        guard relativeX >= 0, relativeY >= 0,
              relativeX < frame.width, relativeY < frame.height else {
            return nil
        }

        return PixelCoordinate(
            x: Int((relativeX * imageScale).rounded(.down)),
            y: Int((relativeY * imageScale).rounded(.down))
        )
    }

    /// Crops a CGImage to a sub-rectangle in pixels.
    public static func cropImage(_ cgImage: CGImage, to cropRectInPixels: CGRect) -> CGImage? {
        let normalized = normalizeRect(cropRectInPixels)
        let imageWidth = CGFloat(cgImage.width)
        let imageHeight = CGFloat(cgImage.height)
        
        let intersection = normalized.intersection(CGRect(x: 0, y: 0, width: imageWidth, height: imageHeight))
        guard !intersection.isNull, intersection.width > 0, intersection.height > 0 else {
            return nil
        }
        
        return cgImage.cropping(to: intersection)
    }
}
