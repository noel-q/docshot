import Foundation
import CoreGraphics

public enum VideoEditorMath: Sendable {
    /// Clamps a timeline playhead time into `[0, totalDuration]`.
    public static func clampTimelineTime(_ time: TimeInterval, totalDuration: TimeInterval) -> TimeInterval {
        guard time.isFinite else { return 0 }
        let maxTime = max(0, totalDuration)
        return min(max(0, time), maxTime)
    }

    /// Computes the aspect-fit display rectangle of a source video inside a view of `viewSize`.
    public static func aspectFitRect(viewSize: CGSize, sourcePixelSize: CGSize) -> CGRect {
        guard viewSize.width > 0, viewSize.height > 0, sourcePixelSize.width > 0, sourcePixelSize.height > 0 else {
            return CGRect(origin: .zero, size: viewSize)
        }
        let widthRatio = viewSize.width / sourcePixelSize.width
        let heightRatio = viewSize.height / sourcePixelSize.height
        let scale = min(widthRatio, heightRatio)

        let fitWidth = sourcePixelSize.width * scale
        let fitHeight = sourcePixelSize.height * scale
        let originX = (viewSize.width - fitWidth) / 2.0
        let originY = (viewSize.height - fitHeight) / 2.0

        return CGRect(x: originX, y: originY, width: fitWidth, height: fitHeight)
    }

    /// Converts a point in view coordinate space to source video pixel coordinate space.
    public static func viewToSourceCoordinates(
        point: CGPoint,
        viewSize: CGSize,
        sourcePixelSize: CGSize
    ) -> CGPoint {
        let fit = aspectFitRect(viewSize: viewSize, sourcePixelSize: sourcePixelSize)
        guard fit.width > 0, fit.height > 0 else { return .zero }

        let clampedX = min(max(point.x, fit.minX), fit.maxX)
        let clampedY = min(max(point.y, fit.minY), fit.maxY)

        let normalizedX = (clampedX - fit.minX) / fit.width
        let normalizedY = (clampedY - fit.minY) / fit.height

        return CGPoint(
            x: normalizedX * sourcePixelSize.width,
            y: normalizedY * sourcePixelSize.height
        )
    }

    /// Converts a point from source video pixel coordinates to view coordinate space.
    public static func sourceToViewCoordinates(
        point: CGPoint,
        viewSize: CGSize,
        sourcePixelSize: CGSize
    ) -> CGPoint {
        let fit = aspectFitRect(viewSize: viewSize, sourcePixelSize: sourcePixelSize)
        guard sourcePixelSize.width > 0, sourcePixelSize.height > 0 else { return .zero }

        let normalizedX = point.x / sourcePixelSize.width
        let normalizedY = point.y / sourcePixelSize.height

        return CGPoint(
            x: fit.minX + normalizedX * fit.width,
            y: fit.minY + normalizedY * fit.height
        )
    }

    /// Converts a rectangle from view coordinate space to source video pixel space.
    public static func viewToSourceRect(
        rect: CGRect,
        viewSize: CGSize,
        sourcePixelSize: CGSize
    ) -> CGRect {
        let p1 = viewToSourceCoordinates(
            point: rect.origin,
            viewSize: viewSize,
            sourcePixelSize: sourcePixelSize
        )
        let p2 = viewToSourceCoordinates(
            point: CGPoint(x: rect.maxX, y: rect.maxY),
            viewSize: viewSize,
            sourcePixelSize: sourcePixelSize
        )
        return CGRect(
            x: min(p1.x, p2.x),
            y: min(p1.y, p2.y),
            width: abs(p2.x - p1.x),
            height: abs(p2.y - p1.y)
        )
    }

    /// Converts a rectangle from source video pixel space to view coordinate space.
    public static func sourceToViewRect(
        rect: CGRect,
        viewSize: CGSize,
        sourcePixelSize: CGSize
    ) -> CGRect {
        let p1 = sourceToViewCoordinates(
            point: rect.origin,
            viewSize: viewSize,
            sourcePixelSize: sourcePixelSize
        )
        let p2 = sourceToViewCoordinates(
            point: CGPoint(x: rect.maxX, y: rect.maxY),
            viewSize: viewSize,
            sourcePixelSize: sourcePixelSize
        )
        return CGRect(
            x: min(p1.x, p2.x),
            y: min(p1.y, p2.y),
            width: abs(p2.x - p1.x),
            height: abs(p2.y - p1.y)
        )
    }

    /// Calculates initial source time range for a new annotation created at `currentSourceTime`.
    /// Extends from `currentSourceTime` to segment end, or at least `minimumDuration`.
    public static func annotationSourceRange(
        currentSourceTime: TimeInterval,
        segmentSourceRange: VideoTimeRange,
        preferredDuration: TimeInterval = 3.0
    ) -> VideoTimeRange {
        let clampedStart = min(max(currentSourceTime, segmentSourceRange.start), max(segmentSourceRange.start, segmentSourceRange.end - VideoTimeRange.minimumDuration))
        let remainingSegmentDuration = max(VideoTimeRange.minimumDuration, segmentSourceRange.end - clampedStart)
        let duration = min(preferredDuration, remainingSegmentDuration)

        return VideoTimeRange(start: clampedStart, duration: duration)
    }
}
