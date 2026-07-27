import Testing
import Foundation
import CoreGraphics
@testable import DocShot

#if SWIFT_PACKAGE
@Suite("VideoEditorViewModel Tests")
@MainActor
struct VideoEditorViewModelTests {

    private static let sourceURL = URL(fileURLWithPath: "/tmp/DocShot-Recordings/test_video.mp4")

    private func makeViewModel(duration: TimeInterval = 10.0) -> VideoEditorViewModel {
        let recording = TemporaryRecording(
            url: Self.sourceURL,
            duration: duration,
            pixelSize: CGSize(width: 1280, height: 720),
            hasAudio: true,
            createdAt: Date()
        )
        return VideoEditorViewModel(recording: recording)
    }

    @Test("Initialization from TemporaryRecording creates single segment project")
    func testInitialization() {
        let vm = makeViewModel(duration: 10.0)
        #expect(vm.project.sourceDuration == 10.0)
        #expect(vm.project.segments.count == 1)
        #expect(vm.currentTimelineTime == 0)
        #expect(!vm.isExporting)
        #expect(!vm.isClosed)
        #expect(vm.isUnedited)
    }

    @Test("Seeking clamps playhead time to valid timeline duration")
    func testPlayheadSeeking() {
        let vm = makeViewModel(duration: 10.0)

        vm.seek(to: 5.0)
        #expect(vm.currentTimelineTime == 5.0)

        vm.seek(to: -2.0)
        #expect(vm.currentTimelineTime == 0.0)

        vm.seek(to: 25.0)
        #expect(vm.currentTimelineTime == 10.0)
    }

    @Test("Split at playhead divides segment into leading and trailing halves")
    func testSplitAtPlayhead() {
        let vm = makeViewModel(duration: 10.0)
        vm.seek(to: 4.0)

        vm.splitAtPlayhead()

        #expect(vm.project.segments.count == 2)
        #expect(vm.project.segments[0].sourceRange == VideoTimeRange(start: 0, duration: 4.0))
        #expect(vm.project.segments[1].sourceRange == VideoTimeRange(start: 4.0, duration: 6.0))
        #expect(vm.hasUnsavedChanges)
    }

    @Test("Trimming segment updates source range")
    func testTrimSegment() {
        let vm = makeViewModel(duration: 10.0)
        guard let segmentID = vm.project.segments.first?.id else { return }

        vm.trimSegment(id: segmentID, startInSource: 2.0, endInSource: 8.0)

        #expect(vm.project.segments[0].sourceRange == VideoTimeRange(start: 2.0, duration: 6.0))
        #expect(vm.timelineDuration == 6.0)
    }

    @Test("Removing segment deletes it from timeline")
    func testRemoveSegment() {
        let vm = makeViewModel(duration: 10.0)
        vm.seek(to: 4.0)
        vm.splitAtPlayhead()

        let secondSegmentID = vm.project.segments[1].id
        vm.removeSegment(id: secondSegmentID)

        #expect(vm.project.segments.count == 1)
        #expect(vm.timelineDuration == 4.0)
    }

    @Test("Adding annotation attaches it to current segment at playhead source time")
    func testAddAnnotationAtPlayhead() {
        let vm = makeViewModel(duration: 10.0)
        vm.seek(to: 3.0)

        let item = AnnotationItem(
            type: .rectangle(rect: CGRect(x: 100, y: 100, width: 200, height: 150), isFilled: false),
            color: .red,
            strokeWidth: 4.0
        )
        vm.addAnnotation(item: item)

        #expect(vm.project.annotations.count == 1)
        let annotation = vm.project.annotations[0]
        #expect(annotation.segmentID == vm.project.segments[0].id)
        #expect(annotation.sourceRange.start == 3.0)
        #expect(annotation.sourceRange.duration > 0)
        #expect(vm.activeAnnotationsAtPlayhead.count == 1)
    }

    @Test("Undo and Redo restore project states")
    func testUndoRedo() {
        let vm = makeViewModel(duration: 10.0)
        #expect(!vm.canUndo)

        vm.seek(to: 5.0)
        vm.splitAtPlayhead()
        #expect(vm.project.segments.count == 2)
        #expect(vm.canUndo)

        vm.undo()
        #expect(vm.project.segments.count == 1)
        #expect(vm.canRedo)

        vm.redo()
        #expect(vm.project.segments.count == 2)
    }

    @Test("Discard and Cancel mark view model as closed without saving")
    func testDiscardAndCancel() {
        let vm = makeViewModel(duration: 10.0)
        vm.discard()

        #expect(vm.isClosed)
        #expect(vm.saveCompletedURL == nil)
    }
}
#endif
