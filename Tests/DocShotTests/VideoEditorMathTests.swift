import Testing
import Foundation
import CoreGraphics
@testable import DocShot

@Suite("VideoEditorMath Tests")
struct VideoEditorMathTests {

    @Test("Timeline playhead clamping bounds time into [0, totalDuration]")
    func testPlayheadClamping() {
        #expect(VideoEditorMath.clampTimelineTime(-5, totalDuration: 10) == 0)
        #expect(VideoEditorMath.clampTimelineTime(5, totalDuration: 10) == 5)
        #expect(VideoEditorMath.clampTimelineTime(15, totalDuration: 10) == 10)
        #expect(VideoEditorMath.clampTimelineTime(Double.nan, totalDuration: 10) == 0)
        #expect(VideoEditorMath.clampTimelineTime(5, totalDuration: 0) == 0)
    }

    @Test("Aspect fit rectangle centers video within container view")
    func testAspectFitRect() {
        let viewSize = CGSize(width: 800, height: 600)
        let sourcePixelSize = CGSize(width: 1920, height: 1080)

        let fit = VideoEditorMath.aspectFitRect(viewSize: viewSize, sourcePixelSize: sourcePixelSize)

        #expect(fit.width == 800)
        #expect(abs(fit.height - 450) < 0.001)
        #expect(fit.minX == 0)
        #expect(fit.minY == 75)
    }

    @Test("View to source coordinate mapping scales view points to video pixels")
    func testViewToSourceCoordinates() {
        let viewSize = CGSize(width: 800, height: 600)
        let sourcePixelSize = CGSize(width: 1920, height: 1080)

        // Center of view
        let centerView = CGPoint(x: 400, y: 300)
        let centerSource = VideoEditorMath.viewToSourceCoordinates(
            point: centerView,
            viewSize: viewSize,
            sourcePixelSize: sourcePixelSize
        )

        #expect(abs(centerSource.x - 960) < 0.001)
        #expect(abs(centerSource.y - 540) < 0.001)

        // Top-left of active video region (y = 75 in view space)
        let topLeftView = CGPoint(x: 0, y: 75)
        let topLeftSource = VideoEditorMath.viewToSourceCoordinates(
            point: topLeftView,
            viewSize: viewSize,
            sourcePixelSize: sourcePixelSize
        )

        #expect(abs(topLeftSource.x - 0) < 0.001)
        #expect(abs(topLeftSource.y - 0) < 0.001)
    }

    @Test("Source to view coordinate mapping scales video pixels back to view space")
    func testSourceToViewCoordinates() {
        let viewSize = CGSize(width: 800, height: 600)
        let sourcePixelSize = CGSize(width: 1920, height: 1080)

        let sourcePoint = CGPoint(x: 960, y: 540)
        let viewPoint = VideoEditorMath.sourceToViewCoordinates(
            point: sourcePoint,
            viewSize: viewSize,
            sourcePixelSize: sourcePixelSize
        )

        #expect(abs(viewPoint.x - 400) < 0.001)
        #expect(abs(viewPoint.y - 300) < 0.001)
    }

    @Test("Annotation default source range calculation caps at segment end")
    func testAnnotationSourceRange() {
        let segmentRange = VideoTimeRange(start: 10, duration: 5) // [10 .. 15]

        let range1 = VideoEditorMath.annotationSourceRange(
            currentSourceTime: 11,
            segmentSourceRange: segmentRange,
            preferredDuration: 3.0
        )
        #expect(range1.start == 11)
        #expect(range1.duration == 3.0)

        // Near segment end
        let range2 = VideoEditorMath.annotationSourceRange(
            currentSourceTime: 14,
            segmentSourceRange: segmentRange,
            preferredDuration: 3.0
        )
        #expect(range2.start == 14)
        #expect(range2.duration == 1.0)
    }
}
