import Foundation
import CoreGraphics
import CoreImage
import AppKit
import SwiftUI

public final class ImageRenderer: @unchecked Sendable {
    public static let shared = ImageRenderer()
    
    private init() {}

    /// The crop actually applied by the render pipeline, in base-image pixel coordinates, or
    /// `nil` when the whole image is exported. Crops are normalised, clamped to the image,
    /// rejected below 10 px on either edge, then made integral so the resulting pixel
    /// dimensions are exactly predictable before rendering.
    public static func effectiveCropRect(baseWidth: Int, baseHeight: Int, cropRect: CGRect?) -> CGRect? {
        let fullImageBounds = CGRect(x: 0, y: 0, width: CGFloat(baseWidth), height: CGFloat(baseHeight))
        guard let crop = cropRect else { return nil }

        let clampedCrop = DisplayGeometry.normalizeRect(crop).intersection(fullImageBounds)
        guard !clampedCrop.isNull, clampedCrop.width >= 10, clampedCrop.height >= 10 else { return nil }

        let integralCrop = clampedCrop.integral.intersection(fullImageBounds)
        guard !integralCrop.isNull, integralCrop.width >= 1, integralCrop.height >= 1 else { return nil }

        return integralCrop
    }

    /// The pixel dimensions a flatten produces before any export resizing is applied.
    public static func flattenedPixelSize(baseWidth: Int, baseHeight: Int, cropRect: CGRect?) -> CGSize {
        if let crop = effectiveCropRect(baseWidth: baseWidth, baseHeight: baseHeight, cropRect: cropRect) {
            return CGSize(width: crop.width, height: crop.height)
        }
        return CGSize(width: CGFloat(baseWidth), height: CGFloat(baseHeight))
    }

    /// Flattens base image + redactions + annotations into PNG Data at native pixel resolution.
    /// When `outputSize` is supplied, the flattened result is resampled once, as the final step,
    /// to those exact pixel dimensions. Safe to call off the main thread.
    public func renderFlattenedPNG(
        baseImage: CGImage,
        annotations: [AnnotationItem],
        cropRect: CGRect? = nil,
        outputSize: CGSize? = nil
    ) -> Data? {
        let fullWidth = CGFloat(baseImage.width)
        let fullHeight = CGFloat(baseImage.height)
        let fullImageBounds = CGRect(x: 0, y: 0, width: fullWidth, height: fullHeight)

        var activeImage = baseImage
        var cropOffset = CGPoint.zero
        var renderBounds = fullImageBounds

        // 1. Clamp cropRect to base image bounds and translate coordinates
        if let clampedCrop = ImageRenderer.effectiveCropRect(
            baseWidth: baseImage.width,
            baseHeight: baseImage.height,
            cropRect: cropRect
        ) {
            if let cropped = DisplayGeometry.cropImage(baseImage, to: clampedCrop) {
                activeImage = cropped
                cropOffset = clampedCrop.origin
                renderBounds = CGRect(x: 0, y: 0, width: clampedCrop.width, height: clampedCrop.height)
            }
        }
        
        // 2. Adjust annotations to cropped space: translate by -cropOffset and filter/clip
        let shiftedAnnotations = annotations.compactMap { item -> AnnotationItem? in
            var shifted = item
            shifted.translate(by: CGSize(width: -cropOffset.x, height: -cropOffset.y))
            
            if shifted.boundingBox.intersects(renderBounds) {
                return shifted
            }
            return nil
        }
        
        let width = activeImage.width
        let height = activeImage.height
        let imageBounds = CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height))
        
        // 3. Apply CIFilter Redactions onto cropped base image
        let imageWithRedactions = applyRedactions(baseImage: activeImage, annotations: shiftedAnnotations, bounds: imageBounds) ?? activeImage
        
        // 4. Draw vector annotations on top using CGContext
        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }
        
        context.clip(to: imageBounds)
        context.draw(imageWithRedactions, in: imageBounds)
        
        for item in shiftedAnnotations {
            switch item.type {
            case .redaction:
                continue // Already applied to pixel buffer
            case .arrow(let start, let end):
                drawArrow(context: context, start: start, end: end, color: item.color.nsColor, strokeWidth: item.strokeWidth, height: CGFloat(height))
            case .rectangle(let rect, let isFilled):
                drawRectangle(context: context, rect: rect, color: item.color.nsColor, strokeWidth: item.strokeWidth, isFilled: isFilled, height: CGFloat(height))
            case .ellipse(let rect, let isFilled):
                drawEllipse(context: context, rect: rect, color: item.color.nsColor, strokeWidth: item.strokeWidth, isFilled: isFilled, height: CGFloat(height))
            case .text(let rect, let text, let fontSize):
                drawText(context: context, rect: rect, text: text, color: item.color.nsColor, fontSize: fontSize, height: CGFloat(height))
            case .highlighter(let points):
                drawHighlighter(context: context, points: points, color: item.color.nsColor, strokeWidth: item.strokeWidth, height: CGFloat(height))
            }
        }
        
        guard let flattenedImage = context.makeImage() else { return nil }

        // 5. Resize once, after flattening, so editing stays at native resolution
        let finalCGImage: CGImage
        if let outputSize {
            guard let resampled = resample(flattenedImage, to: outputSize) else { return nil }
            finalCGImage = resampled
        } else {
            finalCGImage = flattenedImage
        }

        // PNG encoding using CGImageDestination (thread-safe, does not require NSGraphicsContext)
        let mutableData = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(mutableData as CFMutableData, "public.png" as CFString, 1, nil) else {
            return nil
        }
        
        CGImageDestinationAddImage(destination, finalCGImage, nil)
        guard CGImageDestinationFinalize(destination) else {
            return nil
        }
        
        return mutableData as Data
    }
    
    /// Resamples a flattened image to exact pixel dimensions. Returns the input untouched when the
    /// dimensions already match, so a native-size export never pays for an extra copy.
    private func resample(_ image: CGImage, to size: CGSize) -> CGImage? {
        let width = Int(ExportSize.roundedPixels(Double(size.width)))
        let height = Int(ExportSize.roundedPixels(Double(size.height)))

        guard width != image.width || height != image.height else { return image }
        guard width <= ExportSize.maximumPixelCount / max(height, 1) else { return nil }

        let colorSpace = CGColorSpaceCreateDeviceRGB()
        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: colorSpace,
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.interpolationQuality = .high
        context.draw(image, in: CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))
        return context.makeImage()
    }

    private func applyRedactions(baseImage: CGImage, annotations: [AnnotationItem], bounds: CGRect) -> CGImage? {
        let redactions = annotations.compactMap { item -> (CGRect, RedactionStyle)? in
            if case .redaction(let rect, let style) = item.type {
                return (rect, style)
            }
            return nil
        }
        
        guard !redactions.isEmpty else { return baseImage }
        
        let ciImage = CIImage(cgImage: baseImage)
        var resultCI = ciImage
        
        for (rect, style) in redactions {
            let norm = DisplayGeometry.normalizeRect(rect).intersection(bounds)
            if norm.width <= 0 || norm.height <= 0 { continue }
            
            let ciRect = CGRect(x: norm.origin.x, y: bounds.height - norm.origin.y - norm.height, width: norm.width, height: norm.height)
            let croppedCI = resultCI.cropped(to: ciRect)
            var filteredCI: CIImage?
            
            if style == .blur {
                let filter = CIFilter(name: "CIGaussianBlur")
                filter?.setValue(croppedCI, forKey: kCIInputImageKey)
                filter?.setValue(15.0, forKey: kCIInputRadiusKey)
                filteredCI = filter?.outputImage?.cropped(to: ciRect)
            } else {
                let filter = CIFilter(name: "CIPixellate")
                filter?.setValue(croppedCI, forKey: kCIInputImageKey)
                filter?.setValue(16.0, forKey: kCIInputScaleKey)
                filteredCI = filter?.outputImage?.cropped(to: ciRect)
            }
            
            if let filtered = filteredCI {
                resultCI = filtered.composited(over: resultCI)
            }
        }
        
        let ciContext = CIContext()
        return ciContext.createCGImage(resultCI, from: bounds)
    }
    
    private func drawArrow(context: CGContext, start: CGPoint, end: CGPoint, color: NSColor, strokeWidth: CGFloat, height: CGFloat) {
        context.saveGState()
        context.setStrokeColor(color.cgColor)
        context.setFillColor(color.cgColor)
        context.setLineWidth(strokeWidth)
        context.setLineCap(.round)
        
        let p1 = CGPoint(x: start.x, y: height - start.y)
        let p2 = CGPoint(x: end.x, y: height - end.y)
        
        context.move(to: p1)
        context.addLine(to: p2)
        context.strokePath()
        
        let angle = atan2(p2.y - p1.y, p2.x - p1.x)
        let headLength = max(strokeWidth * 4.0, 14.0)
        let arrowAngle = CGFloat.pi / 6.0
        
        let p3 = CGPoint(x: p2.x - headLength * cos(angle - arrowAngle), y: p2.y - headLength * sin(angle - arrowAngle))
        let p4 = CGPoint(x: p2.x - headLength * cos(angle + arrowAngle), y: p2.y - headLength * sin(angle + arrowAngle))
        
        context.move(to: p2)
        context.addLine(to: p3)
        context.addLine(to: p4)
        context.closePath()
        context.fillPath()
        
        context.restoreGState()
    }
    
    private func drawRectangle(context: CGContext, rect: CGRect, color: NSColor, strokeWidth: CGFloat, isFilled: Bool, height: CGFloat) {
        context.saveGState()
        let norm = DisplayGeometry.normalizeRect(rect)
        let cgRect = CGRect(x: norm.origin.x, y: height - norm.origin.y - norm.height, width: norm.width, height: norm.height)
        
        if isFilled {
            context.setFillColor(color.cgColor)
            context.fill(cgRect)
        } else {
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(strokeWidth)
            context.stroke(cgRect)
        }
        context.restoreGState()
    }
    
    private func drawEllipse(context: CGContext, rect: CGRect, color: NSColor, strokeWidth: CGFloat, isFilled: Bool, height: CGFloat) {
        context.saveGState()
        let norm = DisplayGeometry.normalizeRect(rect)
        let cgRect = CGRect(x: norm.origin.x, y: height - norm.origin.y - norm.height, width: norm.width, height: norm.height)
        
        if isFilled {
            context.setFillColor(color.cgColor)
            context.fillEllipse(in: cgRect)
        } else {
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(strokeWidth)
            context.strokeEllipse(in: cgRect)
        }
        context.restoreGState()
    }
    
    private func drawText(context: CGContext, rect: CGRect, text: String, color: NSColor, fontSize: CGFloat, height: CGFloat) {
        context.saveGState()
        let norm = DisplayGeometry.normalizeRect(rect)
        let cgRect = CGRect(x: norm.origin.x, y: height - norm.origin.y - norm.height, width: norm.width, height: norm.height)
        
        let paragraphStyle = NSMutableParagraphStyle()
        paragraphStyle.alignment = .left
        
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: color,
            .paragraphStyle: paragraphStyle
        ]
        
        let nsString = text as NSString
        nsString.draw(in: cgRect, withAttributes: attributes)
        context.restoreGState()
    }
    
    private func drawHighlighter(context: CGContext, points: [CGPoint], color: NSColor, strokeWidth: CGFloat, height: CGFloat) {
        guard points.count > 1 else { return }
        context.saveGState()
        
        let alphaColor = color.withAlphaComponent(0.4)
        context.setStrokeColor(alphaColor.cgColor)
        context.setLineWidth(strokeWidth * 2.5)
        context.setLineCap(.round)
        context.setLineJoin(.round)
        
        let p0 = points[0]
        context.move(to: CGPoint(x: p0.x, y: height - p0.y))
        
        for i in 1..<points.count {
            let p = points[i]
            context.addLine(to: CGPoint(x: p.x, y: height - p.y))
        }
        
        context.strokePath()
        context.restoreGState()
    }
}
