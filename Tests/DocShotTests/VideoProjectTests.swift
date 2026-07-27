import Testing
import Foundation
import CoreGraphics
@testable import DocShot

/// The non-destructive edit model: what the timeline is, what each mutation is allowed to do, and
/// where annotations end up afterwards. Pure values throughout — no asset, no file, no export.
@Suite("VideoProject Tests")
struct VideoProjectTests {

    // MARK: - Fixtures

    private static let sourceURL = URL(fileURLWithPath: "/tmp/DocShot-Recordings/source.mp4")

    private func makeProject(duration: TimeInterval = 10, hasAudio: Bool = true) -> VideoProject {
        VideoProject(
            sourceURL: Self.sourceURL,
            sourceDuration: duration,
            sourcePixelSize: CGSize(width: 640, height: 480),
            hasSourceAudio: hasAudio
        )
    }

    private func makeAnnotationItem(_ color: CodableColor = .red) -> AnnotationItem {
        AnnotationItem(
            type: .rectangle(rect: CGRect(x: 10, y: 10, width: 100, height: 80), isFilled: true),
            color: color
        )
    }

    /// `#expect(throws:)` takes its closure as immutable, which rules it out for `mutating`
    /// edits on a local project. This keeps the same intent while letting the edit be attempted.
    private func expectRejected(
        _ expected: VideoProjectError,
        sourceLocation: SourceLocation = #_sourceLocation,
        _ edit: () throws -> Void
    ) {
        do {
            try edit()
            Issue.record("Expected \(expected), but the edit was accepted", sourceLocation: sourceLocation)
        } catch let error as VideoProjectError {
            #expect(error == expected, sourceLocation: sourceLocation)
        } catch {
            Issue.record("Expected \(expected), got \(error)", sourceLocation: sourceLocation)
        }
    }

    private func expectRejected(
        sourceLocation: SourceLocation = #_sourceLocation,
        _ edit: () throws -> Void
    ) {
        do {
            try edit()
            Issue.record("Expected the edit to be rejected", sourceLocation: sourceLocation)
        } catch is VideoProjectError {
            // Expected.
        } catch {
            Issue.record("Expected a VideoProjectError, got \(error)", sourceLocation: sourceLocation)
        }
    }

    // MARK: - Creation

    @Test("A new project is the whole recording, untouched")
    func testNewProjectIsWholeRecording() {
        let project = makeProject(duration: 10)

        #expect(project.segments.count == 1)
        #expect(project.segments[0].sourceRange == VideoTimeRange(start: 0, duration: 10))
        #expect(project.timelineDuration == 10)
        #expect(project.annotations.isEmpty)
        #expect(project.isUnedited)
    }

    @Test("A project opened from a finished recording carries its measured values")
    func testProjectFromRecording() {
        let recording = TemporaryRecording(
            url: Self.sourceURL,
            duration: 7.5,
            pixelSize: CGSize(width: 1280, height: 720),
            hasAudio: true,
            createdAt: Date()
        )

        let project = VideoProject(recording: recording)

        #expect(project.sourceURL == recording.url)
        #expect(project.sourceDuration == 7.5)
        #expect(project.sourcePixelSize == CGSize(width: 1280, height: 720))
        #expect(project.hasSourceAudio)
        #expect(project.isUnedited)
    }

    // MARK: - Trim

    @Test("Trimming narrows a segment and shortens the timeline")
    func testTrim() throws {
        var project = makeProject(duration: 10)
        let segmentID = project.segments[0].id

        try project.trim(segmentID: segmentID, to: VideoTimeRange(start: 2, duration: 5))

        #expect(project.segments.count == 1)
        #expect(project.segments[0].sourceRange == VideoTimeRange(start: 2, duration: 5))
        #expect(project.timelineDuration == 5)
        #expect(project.isUnedited == false)
    }

    @Test("Trimming refuses ranges outside the recording, too-short ranges, and unknown clips")
    func testTrimValidation() {
        var project = makeProject(duration: 10)
        let segmentID = project.segments[0].id

        expectRejected(VideoProjectError.rangeOutsideSource(sourceDuration: 10)) {
            try project.trim(segmentID: segmentID, to: VideoTimeRange(start: 8, duration: 5))
        }
        expectRejected(VideoProjectError.invalidTimeRange) {
            try project.trim(segmentID: segmentID, to: VideoTimeRange(start: 1, duration: 0.001))
        }
        expectRejected(VideoProjectError.invalidTimeRange) {
            try project.trim(segmentID: segmentID, to: VideoTimeRange(start: -1, duration: 2))
        }
        let unknown = UUID()
        expectRejected(VideoProjectError.unknownSegment(unknown)) {
            try project.trim(segmentID: unknown, to: VideoTimeRange(start: 0, duration: 2))
        }

        // A rejected edit changes nothing at all.
        #expect(project.segments[0].sourceRange == VideoTimeRange(start: 0, duration: 10))
        #expect(project.isUnedited)
    }

    @Test("Trimming clips the annotations that survive and drops the ones trimmed away")
    func testTrimClipsAnnotations() throws {
        var project = makeProject(duration: 10)
        let segmentID = project.segments[0].id

        let surviving = VideoAnnotation(
            segmentID: segmentID,
            sourceRange: VideoTimeRange(start: 1, duration: 4),
            item: makeAnnotationItem()
        )
        let trimmedAway = VideoAnnotation(
            segmentID: segmentID,
            sourceRange: VideoTimeRange(start: 8, duration: 1),
            item: makeAnnotationItem(.blue)
        )
        try project.addAnnotation(surviving)
        try project.addAnnotation(trimmedAway)

        try project.trim(segmentID: segmentID, to: VideoTimeRange(start: 2, duration: 4))

        #expect(project.annotations.count == 1)
        let kept = try #require(project.annotations.first)
        #expect(kept.id == surviving.id)
        #expect(kept.sourceRange == VideoTimeRange(start: 2, duration: 3), "The overlay follows the frames it was drawn over")
    }

    // MARK: - Split

    @Test("Splitting divides one clip into two that still cover the same footage")
    func testSplit() throws {
        var project = makeProject(duration: 10)
        let originalID = project.segments[0].id

        let result = try project.split(atTimelineTime: 4)

        #expect(project.segments.count == 2)
        #expect(result.leading == originalID, "The leading half keeps the original identity")
        #expect(project.segments[0].sourceRange == VideoTimeRange(start: 0, duration: 4))
        #expect(project.segments[1].sourceRange == VideoTimeRange(start: 4, duration: 6))
        #expect(project.segments[1].id == result.trailing)
        #expect(project.timelineDuration == 10, "A split changes nothing about what plays")
    }

    @Test("Splitting refuses edges and times off the timeline")
    func testSplitValidation() {
        var project = makeProject(duration: 10)

        expectRejected(VideoProjectError.splitAtSegmentBoundary) {
            try project.split(atTimelineTime: 0)
        }
        expectRejected(VideoProjectError.splitAtSegmentBoundary) {
            try project.split(atTimelineTime: 9.99)
        }
        expectRejected(VideoProjectError.timeOutsideTimeline(timelineDuration: 10)) {
            try project.split(atTimelineTime: 12)
        }
        expectRejected(VideoProjectError.timeOutsideTimeline(timelineDuration: 10)) {
            try project.split(atTimelineTime: -1)
        }
        #expect(project.segments.count == 1)
    }

    @Test("A split sends each annotation to the half holding the frame it starts on")
    func testSplitReassignsAnnotations() throws {
        var project = makeProject(duration: 10)
        let segmentID = project.segments[0].id

        let early = VideoAnnotation(
            segmentID: segmentID,
            sourceRange: VideoTimeRange(start: 1, duration: 2),
            item: makeAnnotationItem()
        )
        let late = VideoAnnotation(
            segmentID: segmentID,
            sourceRange: VideoTimeRange(start: 6, duration: 2),
            item: makeAnnotationItem(.blue)
        )
        let straddling = VideoAnnotation(
            segmentID: segmentID,
            sourceRange: VideoTimeRange(start: 3, duration: 3),
            item: makeAnnotationItem(.green)
        )
        try project.addAnnotation(early)
        try project.addAnnotation(late)
        try project.addAnnotation(straddling)

        let result = try project.split(atTimelineTime: 4)

        let leading = project.annotations(forSegmentID: result.leading)
        let trailing = project.annotations(forSegmentID: result.trailing)

        let leadingIDs: Set<UUID> = Set(leading.map(\.id))
        let trailingIDs: Set<UUID> = Set(trailing.map(\.id))
        #expect(leadingIDs == Set([early.id, straddling.id]))
        #expect(trailingIDs == Set([late.id]))

        // The straddling overlay is clipped to the half that owns its first frame.
        let clipped = try #require(leading.first { $0.id == straddling.id })
        #expect(clipped.sourceRange == VideoTimeRange(start: 3, duration: 1))
    }

    // MARK: - Remove and reorder

    @Test("Removing a clip takes its annotations with it")
    func testRemoveSegment() throws {
        var project = makeProject(duration: 10)
        let result = try project.split(atTimelineTime: 4)
        try project.addAnnotation(VideoAnnotation(
            segmentID: result.trailing,
            sourceRange: VideoTimeRange(start: 5, duration: 1),
            item: makeAnnotationItem()
        ))

        try project.removeSegment(id: result.trailing)

        #expect(project.segments.count == 1)
        #expect(project.segments[0].id == result.leading)
        #expect(project.timelineDuration == 4)
        #expect(project.annotations.isEmpty)
    }

    @Test("The last clip cannot be removed")
    func testCannotRemoveLastSegment() {
        var project = makeProject(duration: 10)
        let segmentID = project.segments[0].id

        expectRejected(VideoProjectError.cannotRemoveLastSegment) {
            try project.removeSegment(id: segmentID)
        }
        #expect(project.segments.count == 1)
    }

    @Test("Reordering clips moves their annotations with them")
    func testMoveSegment() throws {
        var project = makeProject(duration: 10)
        let result = try project.split(atTimelineTime: 4)
        try project.addAnnotation(VideoAnnotation(
            segmentID: result.trailing,
            sourceRange: VideoTimeRange(start: 5, duration: 1),
            item: makeAnnotationItem()
        ))

        try project.moveSegment(id: result.trailing, toIndex: 0)

        #expect(project.segments.map(\.id) == [result.trailing, result.leading])
        #expect(project.timelineDuration == 10)
        // The trailing clip now starts the timeline, so its overlay shows near the start.
        #expect(project.activeAnnotations(atTimelineTime: 1.5).count == 1)
        #expect(project.activeAnnotations(atTimelineTime: 7).isEmpty)
    }

    @Test("Reordering refuses positions outside the timeline")
    func testMoveSegmentValidation() throws {
        var project = makeProject(duration: 10)
        let result = try project.split(atTimelineTime: 4)

        expectRejected(VideoProjectError.invalidSegmentPosition) {
            try project.moveSegment(id: result.leading, toIndex: 5)
        }
        expectRejected(VideoProjectError.invalidSegmentPosition) {
            try project.moveSegment(id: result.leading, toIndex: -1)
        }
        #expect(project.segments.map(\.id) == [result.leading, result.trailing])
    }

    // MARK: - Annotations

    @Test("An annotation has to overlap the clip it belongs to")
    func testAddAnnotationValidation() throws {
        var project = makeProject(duration: 10)
        let segmentID = project.segments[0].id
        try project.trim(segmentID: segmentID, to: VideoTimeRange(start: 0, duration: 5))

        expectRejected(VideoProjectError.annotationOutsideSegment) {
            try project.addAnnotation(VideoAnnotation(
                segmentID: segmentID,
                sourceRange: VideoTimeRange(start: 6, duration: 1),
                item: makeAnnotationItem()
            ))
        }
        expectRejected(VideoProjectError.invalidTimeRange) {
            try project.addAnnotation(VideoAnnotation(
                segmentID: segmentID,
                sourceRange: VideoTimeRange(start: 1, duration: 0.001),
                item: makeAnnotationItem()
            ))
        }
        let unknown = UUID()
        expectRejected(VideoProjectError.unknownSegment(unknown)) {
            try project.addAnnotation(VideoAnnotation(
                segmentID: unknown,
                sourceRange: VideoTimeRange(start: 1, duration: 1),
                item: makeAnnotationItem()
            ))
        }
        #expect(project.annotations.isEmpty)
    }

    @Test("Annotations can be removed, retimed, moved between clips, and repositioned")
    func testAnnotationMutations() throws {
        var project = makeProject(duration: 10)
        let result = try project.split(atTimelineTime: 5)
        let annotation = VideoAnnotation(
            segmentID: result.leading,
            sourceRange: VideoTimeRange(start: 1, duration: 2),
            item: makeAnnotationItem()
        )
        try project.addAnnotation(annotation)

        try project.moveAnnotation(id: annotation.id, to: VideoTimeRange(start: 2, duration: 1))
        #expect(project.annotations[0].sourceRange == VideoTimeRange(start: 2, duration: 1))

        try project.moveAnnotation(
            id: annotation.id,
            toSegmentID: result.trailing,
            range: VideoTimeRange(start: 6, duration: 1)
        )
        #expect(project.annotations[0].segmentID == result.trailing)
        #expect(project.annotations[0].sourceRange == VideoTimeRange(start: 6, duration: 1))

        try project.translateAnnotation(id: annotation.id, by: CGSize(width: 20, height: 30))
        if case .rectangle(let rect, _) = project.annotations[0].item.type {
            #expect(rect.origin == CGPoint(x: 30, y: 40))
        } else {
            Issue.record("The annotation changed shape")
        }

        try project.removeAnnotation(id: annotation.id)
        #expect(project.annotations.isEmpty)

        expectRejected(VideoProjectError.unknownAnnotation(annotation.id)) {
            try project.removeAnnotation(id: annotation.id)
        }
    }

    // MARK: - Timeline mapping

    @Test("Timeline positions map back to the source frames they play")
    func testTimelineMapping() throws {
        var project = makeProject(duration: 10)
        let result = try project.split(atTimelineTime: 4)
        try project.trim(segmentID: result.trailing, to: VideoTimeRange(start: 7, duration: 2))

        #expect(project.timelineDuration == 6)
        #expect(project.timelineStart(ofSegmentID: result.leading) == 0)
        #expect(project.timelineStart(ofSegmentID: result.trailing) == 4)

        #expect(project.sourceTime(atTimelineTime: 1) == 1)
        #expect(project.sourceTime(atTimelineTime: 4.5) == 7.5)
        #expect(project.sourceTime(atTimelineTime: 6) == nil, "The timeline is half-open")
        #expect(project.segment(atTimelineTime: -1) == nil)
    }

    @Test("Only the overlays belonging to the frames on screen are active")
    func testActiveAnnotations() throws {
        var project = makeProject(duration: 10)
        let result = try project.split(atTimelineTime: 5)

        try project.addAnnotation(VideoAnnotation(
            segmentID: result.leading,
            sourceRange: VideoTimeRange(start: 1, duration: 2),
            item: makeAnnotationItem()
        ))
        try project.addAnnotation(VideoAnnotation(
            segmentID: result.trailing,
            sourceRange: VideoTimeRange(start: 6, duration: 1),
            item: makeAnnotationItem(.blue)
        ))

        #expect(project.activeAnnotations(atTimelineTime: 0.5).isEmpty)
        #expect(project.activeAnnotations(atTimelineTime: 1.5).count == 1)
        #expect(project.activeAnnotations(atTimelineTime: 3.5).isEmpty)
        #expect(project.activeAnnotations(atTimelineTime: 6.5).count == 1)
        #expect(project.activeAnnotations(atTimelineTime: 20).isEmpty)
    }

    @Test("Trimming a clip's head keeps its overlays on the same frames")
    func testAnnotationsStayAttachedToContentAcrossTrim() throws {
        var project = makeProject(duration: 10)
        let segmentID = project.segments[0].id
        try project.addAnnotation(VideoAnnotation(
            segmentID: segmentID,
            sourceRange: VideoTimeRange(start: 4, duration: 2),
            item: makeAnnotationItem()
        ))

        // Before: source second 4 plays at timeline 4.
        #expect(project.activeAnnotations(atTimelineTime: 4.5).count == 1)

        try project.trim(segmentID: segmentID, to: VideoTimeRange(start: 3, duration: 5))

        // After: the same source frames now play three seconds earlier, and the overlay moved
        // with them rather than staying at timeline 4.
        #expect(project.activeAnnotations(atTimelineTime: 1.5).count == 1)
        #expect(project.activeAnnotations(atTimelineTime: 4.5).isEmpty)
    }

    // MARK: - Undo/redo

    @Test("Each accepted edit becomes one undo step")
    func testHistoryUndoRedo() throws {
        let project = makeProject(duration: 10)
        var history = VideoProjectHistory(project)
        let segmentID = project.segments[0].id

        #expect(history.canUndo == false)
        #expect(history.canRedo == false)

        try history.perform { try $0.trim(segmentID: segmentID, to: VideoTimeRange(start: 0, duration: 6)) }
        try history.perform { try $0.split(atTimelineTime: 3) }

        #expect(history.current.segments.count == 2)
        #expect(history.canUndo)

        let didUndoSplit = history.undo()
        #expect(didUndoSplit)
        #expect(history.current.segments.count == 1)
        #expect(history.current.timelineDuration == 6)

        let didUndoTrim = history.undo()
        #expect(didUndoTrim)
        #expect(history.current.timelineDuration == 10)
        #expect(history.canUndo == false)

        let didRedo = history.redo()
        #expect(didRedo)
        #expect(history.current.timelineDuration == 6)
    }

    @Test("A rejected edit changes neither the project nor the history")
    func testHistoryIgnoresRejectedEdits() {
        var history = VideoProjectHistory(makeProject(duration: 10))
        let before = history.current

        expectRejected {
            try history.perform { try $0.split(atTimelineTime: 99) }
        }

        #expect(history.current == before)
        #expect(history.canUndo == false)
    }

    @Test("An edit that changes nothing is not recorded")
    func testHistoryIgnoresNoOpEdits() throws {
        var history = VideoProjectHistory(makeProject(duration: 10))
        let segmentID = history.current.segments[0].id

        try history.perform { try $0.moveSegment(id: segmentID, toIndex: 0) }

        #expect(history.canUndo == false)
    }

    @Test("A new edit after an undo clears the redo stack")
    func testHistoryRedoClearedByNewEdit() throws {
        var history = VideoProjectHistory(makeProject(duration: 10))
        let segmentID = history.current.segments[0].id

        try history.perform { try $0.trim(segmentID: segmentID, to: VideoTimeRange(start: 0, duration: 6)) }
        let didUndo = history.undo()
        #expect(didUndo)
        #expect(history.canRedo)

        try history.perform { try $0.trim(segmentID: segmentID, to: VideoTimeRange(start: 0, duration: 4)) }

        #expect(history.canRedo == false)
        #expect(history.current.timelineDuration == 4)
    }

    @Test("The history keeps a bounded number of snapshots")
    func testHistoryLimit() throws {
        var history = VideoProjectHistory(makeProject(duration: 10), limit: 3)
        let segmentID = history.current.segments[0].id

        for step in 1...6 {
            let duration = TimeInterval(10 - step)
            try history.perform { try $0.trim(segmentID: segmentID, to: VideoTimeRange(start: 0, duration: duration)) }
        }

        var undoCount = 0
        while history.undo() { undoCount += 1 }

        #expect(undoCount == 3, "Only the most recent edits stay undoable")
    }

    // MARK: - Time ranges

    @Test("Time ranges validate, intersect, and clip")
    func testTimeRange() {
        let range = VideoTimeRange(start: 2, duration: 3)

        #expect(range.end == 5)
        #expect(range.isValid)
        #expect(range.contains(2))
        #expect(range.contains(4.99))
        #expect(range.contains(5) == false, "Ranges are half-open")

        #expect(range.intersects(VideoTimeRange(start: 4, duration: 2)))
        #expect(range.intersects(VideoTimeRange(start: 5, duration: 1)) == false)
        #expect(range.intersection(VideoTimeRange(start: 4, duration: 2)) == VideoTimeRange(start: 4, duration: 1))
        #expect(range.intersection(VideoTimeRange(start: 9, duration: 1)) == nil)
        #expect(range.shifted(by: -1) == VideoTimeRange(start: 1, duration: 3))

        #expect(VideoTimeRange(start: 0, duration: 0.001).isValid == false)
        #expect(VideoTimeRange(start: 0, duration: 0.001).isWellFormed)
        #expect(VideoTimeRange(start: -1, duration: 2).isValid == false)
        #expect(VideoTimeRange(start: 0, duration: .infinity).isValid == false)
    }
}
