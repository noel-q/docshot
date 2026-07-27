import Foundation
import CoreGraphics
import CoreImage
import AppKit

/// Draws annotation overlays into a transparent bitmap the size of a video frame.
///
/// Annotation coordinates use the screenshot editor's convention — top-left origin, in source
/// pixels — so the same `AnnotationItem` values drawn over a still are drawn over a frame here,
/// with the same y-flip applied once at the drawing boundary.
///
/// Redactions are deliberately not drawn here: blurring and pixelating have to sample the frame
/// underneath, so the exporter applies them as Core Image filters before this overlay is
/// composited on top.
public final class VideoAnnotationOverlayRenderer: @unchecked Sendable {

    public init() {}

    /// The vector overlay for one frame, or `nil` when there is nothing to draw.
    public func makeOverlayImage(
        annotations: [AnnotationItem],
        pixelSize: CGSize
    ) -> CGImage? {
        let drawable = annotations.filter { annotation in
            if case .redaction = annotation.type { return false }
            return true
        }
        guard !drawable.isEmpty else { return nil }

        let width = Int(pixelSize.width.rounded())
        let height = Int(pixelSize.height.rounded())
        guard width > 0, height > 0 else { return nil }

        guard let context = CGContext(
            data: nil,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else {
            return nil
        }

        context.clear(CGRect(x: 0, y: 0, width: CGFloat(width), height: CGFloat(height)))

        // Text drawing goes through AppKit, which needs a current graphics context to draw into.
        let previousContext = NSGraphicsContext.current
        NSGraphicsContext.current = NSGraphicsContext(cgContext: context, flipped: false)
        defer { NSGraphicsContext.current = previousContext }

        let frameHeight = CGFloat(height)
        for annotation in drawable {
            switch annotation.type {
            case .arrow(let start, let end):
                drawArrow(
                    context: context,
                    start: start,
                    end: end,
                    color: annotation.color.nsColor,
                    strokeWidth: annotation.strokeWidth,
                    height: frameHeight
                )
            case .rectangle(let rect, let isFilled):
                drawRectangle(
                    context: context,
                    rect: rect,
                    color: annotation.color.nsColor,
                    strokeWidth: annotation.strokeWidth,
                    isFilled: isFilled,
                    height: frameHeight
                )
            case .ellipse(let rect, let isFilled):
                drawEllipse(
                    context: context,
                    rect: rect,
                    color: annotation.color.nsColor,
                    strokeWidth: annotation.strokeWidth,
                    isFilled: isFilled,
                    height: frameHeight
                )
            case .text(let rect, let text, let fontSize):
                drawText(
                    context: context,
                    rect: rect,
                    text: text,
                    color: annotation.color.nsColor,
                    fontSize: fontSize,
                    height: frameHeight
                )
            case .highlighter(let points):
                drawHighlighter(
                    context: context,
                    points: points,
                    color: annotation.color.nsColor,
                    strokeWidth: annotation.strokeWidth,
                    height: frameHeight
                )
            case .redaction:
                continue
            }
        }

        return context.makeImage()
    }

    /// Applies redaction annotations to a frame. Returns the input unchanged when there are none.
    public func applyRedactions(
        to image: CIImage,
        annotations: [AnnotationItem],
        pixelSize: CGSize
    ) -> CIImage {
        let redactions = annotations.compactMap { annotation -> (CGRect, RedactionStyle)? in
            if case .redaction(let rect, let style) = annotation.type { return (rect, style) }
            return nil
        }
        guard !redactions.isEmpty else { return image }

        let bounds = CGRect(origin: .zero, size: pixelSize)
        var result = image

        for (rect, style) in redactions {
            let normalized = DisplayGeometry.normalizeRect(rect).intersection(bounds)
            guard !normalized.isNull, normalized.width > 0, normalized.height > 0 else { continue }

            // Annotation rects are top-left origin; Core Image is bottom-left.
            let ciRect = CGRect(
                x: normalized.origin.x,
                y: bounds.height - normalized.origin.y - normalized.height,
                width: normalized.width,
                height: normalized.height
            )

            let region = result.cropped(to: ciRect)
            let filtered: CIImage?
            switch style {
            case .blur:
                let filter = CIFilter(name: "CIGaussianBlur")
                filter?.setValue(region.clampedToExtent(), forKey: kCIInputImageKey)
                filter?.setValue(15.0, forKey: kCIInputRadiusKey)
                filtered = filter?.outputImage?.cropped(to: ciRect)
            case .pixelate:
                let filter = CIFilter(name: "CIPixellate")
                filter?.setValue(region.clampedToExtent(), forKey: kCIInputImageKey)
                filter?.setValue(16.0, forKey: kCIInputScaleKey)
                filtered = filter?.outputImage?.cropped(to: ciRect)
            }

            if let filtered {
                result = filtered.composited(over: result)
            }
        }

        return result
    }

    // MARK: - Drawing
    //
    // These mirror the still-image renderer's conventions so an annotation looks the same over a
    // frame as it does over a screenshot. They are kept here rather than shared with
    // `ImageRenderer` so that this feature cannot change the screenshot export path; extracting a
    // common drawing type is a follow-up, not a prerequisite.

    private func drawArrow(
        context: CGContext,
        start: CGPoint,
        end: CGPoint,
        color: NSColor,
        strokeWidth: CGFloat,
        height: CGFloat
    ) {
        context.saveGState()
        context.setStrokeColor(color.cgColor)
        context.setFillColor(color.cgColor)
        context.setLineWidth(strokeWidth)
        context.setLineCap(.round)

        let from = CGPoint(x: start.x, y: height - start.y)
        let to = CGPoint(x: end.x, y: height - end.y)

        context.move(to: from)
        context.addLine(to: to)
        context.strokePath()

        let angle = atan2(to.y - from.y, to.x - from.x)
        let headLength = max(strokeWidth * 4.0, 14.0)
        let spread = CGFloat.pi / 6.0

        context.move(to: to)
        context.addLine(to: CGPoint(
            x: to.x - headLength * cos(angle - spread),
            y: to.y - headLength * sin(angle - spread)
        ))
        context.addLine(to: CGPoint(
            x: to.x - headLength * cos(angle + spread),
            y: to.y - headLength * sin(angle + spread)
        ))
        context.closePath()
        context.fillPath()

        context.restoreGState()
    }

    private func flipped(_ rect: CGRect, height: CGFloat) -> CGRect {
        let normalized = DisplayGeometry.normalizeRect(rect)
        return CGRect(
            x: normalized.origin.x,
            y: height - normalized.origin.y - normalized.height,
            width: normalized.width,
            height: normalized.height
        )
    }

    private func drawRectangle(
        context: CGContext,
        rect: CGRect,
        color: NSColor,
        strokeWidth: CGFloat,
        isFilled: Bool,
        height: CGFloat
    ) {
        context.saveGState()
        let target = flipped(rect, height: height)
        if isFilled {
            context.setFillColor(color.cgColor)
            context.fill(target)
        } else {
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(strokeWidth)
            context.stroke(target)
        }
        context.restoreGState()
    }

    private func drawEllipse(
        context: CGContext,
        rect: CGRect,
        color: NSColor,
        strokeWidth: CGFloat,
        isFilled: Bool,
        height: CGFloat
    ) {
        context.saveGState()
        let target = flipped(rect, height: height)
        if isFilled {
            context.setFillColor(color.cgColor)
            context.fillEllipse(in: target)
        } else {
            context.setStrokeColor(color.cgColor)
            context.setLineWidth(strokeWidth)
            context.strokeEllipse(in: target)
        }
        context.restoreGState()
    }

    private func drawText(
        context: CGContext,
        rect: CGRect,
        text: String,
        color: NSColor,
        fontSize: CGFloat,
        height: CGFloat
    ) {
        guard !text.isEmpty else { return }
        context.saveGState()

        let target = flipped(rect, height: height)
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: fontSize, weight: .bold),
            .foregroundColor: color
        ]
        (text as NSString).draw(in: target, withAttributes: attributes)

        context.restoreGState()
    }

    private func drawHighlighter(
        context: CGContext,
        points: [CGPoint],
        color: NSColor,
        strokeWidth: CGFloat,
        height: CGFloat
    ) {
        guard points.count > 1 else { return }
        context.saveGState()

        context.setStrokeColor(color.withAlphaComponent(0.4).cgColor)
        context.setLineWidth(strokeWidth * 2.5)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        context.move(to: CGPoint(x: points[0].x, y: height - points[0].y))
        for point in points.dropFirst() {
            context.addLine(to: CGPoint(x: point.x, y: height - point.y))
        }
        context.strokePath()

        context.restoreGState()
    }
}
