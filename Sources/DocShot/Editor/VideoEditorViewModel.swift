import Foundation
import Combine
import AppKit

@MainActor
public final class VideoEditorViewModel: ObservableObject {
    @Published public private(set) var history: VideoProjectHistory
    @Published public var currentTimelineTime: TimeInterval = 0
    @Published public var isPlaying: Bool = false
    @Published public var selectedSegmentID: UUID?

    @Published public var activeTool: AnnotationTool = .rectangle
    @Published public var selectedColor: CodableColor = .red
    @Published public var selectedStrokeWidth: CGFloat = 4.0
    @Published public var selectedAnnotationID: UUID?

    @Published public private(set) var isExporting: Bool = false
    @Published public private(set) var exportError: String?
    @Published public private(set) var statusMessage: String?
    @Published public private(set) var isClosed: Bool = false
    @Published public private(set) var saveCompletedURL: URL?

    public let exporter: any VideoProjectExporting
    public let movieSaver: any MovieSaving
    public let store: any TemporaryRecordingStore

    public init(
        project: VideoProject,
        exporter: any VideoProjectExporting = AVFoundationVideoProjectExporter(store: FileManagerTemporaryRecordingStore()),
        movieSaver: any MovieSaving = SavePanelMovieSaver(store: FileManagerTemporaryRecordingStore()),
        store: any TemporaryRecordingStore = FileManagerTemporaryRecordingStore()
    ) {
        self.history = VideoProjectHistory(project)
        self.exporter = exporter
        self.movieSaver = movieSaver
        self.store = store
        self.selectedSegmentID = project.segments.first?.id
    }

    public convenience init(
        recording: TemporaryRecording,
        exporter: any VideoProjectExporting = AVFoundationVideoProjectExporter(store: FileManagerTemporaryRecordingStore()),
        movieSaver: any MovieSaving = SavePanelMovieSaver(store: FileManagerTemporaryRecordingStore()),
        store: any TemporaryRecordingStore = FileManagerTemporaryRecordingStore()
    ) {
        let project = VideoProject(recording: recording)
        self.init(project: project, exporter: exporter, movieSaver: movieSaver, store: store)
    }

    // MARK: - Computed Properties

    public var project: VideoProject {
        history.current
    }

    public var canUndo: Bool { history.canUndo }
    public var canRedo: Bool { history.canRedo }
    public var isUnedited: Bool { project.isUnedited }
    public var hasUnsavedChanges: Bool { !isUnedited }

    public var timelineDuration: TimeInterval {
        project.timelineDuration
    }

    public var selectedSegment: VideoSegment? {
        guard let id = selectedSegmentID else { return nil }
        return project.segment(id: id)
    }

    public var currentSegmentAndLocalTime: (segment: VideoSegment, localTime: TimeInterval)? {
        project.segment(atTimelineTime: currentTimelineTime)
    }

    public var activeAnnotationsAtPlayhead: [VideoAnnotation] {
        guard let (segment, localTime) = currentSegmentAndLocalTime else { return [] }
        let sourceTime = segment.sourceRange.start + localTime
        return project.annotations.filter {
            $0.segmentID == segment.id && $0.sourceRange.contains(sourceTime)
        }
    }

    // MARK: - Playhead & Navigation

    public func seek(to timelineTime: TimeInterval) {
        let clamped = VideoEditorMath.clampTimelineTime(timelineTime, totalDuration: project.timelineDuration)
        currentTimelineTime = clamped
        if let (segment, _) = project.segment(atTimelineTime: clamped) {
            selectedSegmentID = segment.id
        }
    }

    public func togglePlayPause() {
        isPlaying.toggle()
    }

    public func stepFrame(by seconds: TimeInterval) {
        seek(to: currentTimelineTime + seconds)
    }

    // MARK: - Undo / Redo

    public func undo() {
        history.undo()
        clampSelectionAndPlayhead()
    }

    public func redo() {
        history.redo()
        clampSelectionAndPlayhead()
    }

    private func clampSelectionAndPlayhead() {
        seek(to: currentTimelineTime)
        if selectedSegmentID == nil || project.segment(id: selectedSegmentID!) == nil {
            selectedSegmentID = project.segments.first?.id
        }
    }

    // MARK: - Segment Mutations

    public func splitAtPlayhead() {
        do {
            try history.perform { proj in
                try proj.split(atTimelineTime: currentTimelineTime)
            }
            if selectedSegmentID == nil || project.segment(id: selectedSegmentID!) == nil {
                selectedSegmentID = project.segment(atTimelineTime: currentTimelineTime)?.segment.id
            }
            statusMessage = "Segment split at \(String(format: "%.1fs", currentTimelineTime))"
        } catch {
            exportError = (error as? VideoProjectError)?.localizedDescription ?? error.localizedDescription
        }
    }

    public func trimSegment(id: UUID, startInSource: TimeInterval, endInSource: TimeInterval) {
        do {
            let range = VideoTimeRange.between(start: startInSource, end: endInSource)
            try history.perform { proj in
                try proj.trim(segmentID: id, to: range)
            }
            seek(to: currentTimelineTime)
            statusMessage = "Trimmed segment"
        } catch {
            exportError = (error as? VideoProjectError)?.localizedDescription ?? error.localizedDescription
        }
    }

    public func removeSegment(id: UUID) {
        do {
            try history.perform { proj in
                try proj.removeSegment(id: id)
            }
            clampSelectionAndPlayhead()
            statusMessage = "Segment removed"
        } catch {
            exportError = (error as? VideoProjectError)?.localizedDescription ?? error.localizedDescription
        }
    }

    public func moveSegment(id: UUID, toIndex destination: Int) {
        do {
            try history.perform { proj in
                try proj.moveSegment(id: id, toIndex: destination)
            }
            seek(to: currentTimelineTime)
            statusMessage = "Segment reordered"
        } catch {
            exportError = (error as? VideoProjectError)?.localizedDescription ?? error.localizedDescription
        }
    }

    // MARK: - Annotation Mutations

    public func addAnnotation(item: AnnotationItem, customTimeRange: VideoTimeRange? = nil) {
        guard let (segment, localTime) = currentSegmentAndLocalTime else { return }
        let currentSourceTime = segment.sourceRange.start + localTime

        let sourceRange: VideoTimeRange
        if let customTimeRange {
            sourceRange = customTimeRange
        } else {
            sourceRange = VideoEditorMath.annotationSourceRange(
                currentSourceTime: currentSourceTime,
                segmentSourceRange: segment.sourceRange
            )
        }

        let videoAnnotation = VideoAnnotation(
            segmentID: segment.id,
            sourceRange: sourceRange,
            item: item
        )

        do {
            try history.perform { proj in
                try proj.addAnnotation(videoAnnotation)
            }
            selectedAnnotationID = videoAnnotation.id
            statusMessage = "Added \(item.typeDescription) annotation"
        } catch {
            exportError = (error as? VideoProjectError)?.localizedDescription ?? error.localizedDescription
        }
    }

    public func removeAnnotation(id: UUID) {
        do {
            try history.perform { proj in
                try proj.removeAnnotation(id: id)
            }
            if selectedAnnotationID == id {
                selectedAnnotationID = nil
            }
            statusMessage = "Removed annotation"
        } catch {
            exportError = (error as? VideoProjectError)?.localizedDescription ?? error.localizedDescription
        }
    }

    public func moveAnnotationRange(id: UUID, newRange: VideoTimeRange) {
        do {
            try history.perform { proj in
                try proj.moveAnnotation(id: id, to: newRange)
            }
            statusMessage = "Updated annotation timing"
        } catch {
            exportError = (error as? VideoProjectError)?.localizedDescription ?? error.localizedDescription
        }
    }

    // MARK: - Export & Actions

    public func saveEditedMP4(parentWindow: NSWindow?) {
        guard !isExporting else { return }
        isExporting = true
        exportError = nil
        statusMessage = "Exporting edited MP4..."

        let projectToExport = project

        Task {
            do {
                // Perform rendering/export off main thread via VideoProjectExporting
                let temporaryExport = try await exporter.export(projectToExport, progress: nil)

                let saveResult = await movieSaver.save(temporaryExport, parent: parentWindow)

                // Remove temporary exported file after save handling
                store.removeIfPresent(temporaryExport.url)

                await MainActor.run {
                    self.isExporting = false
                    switch saveResult {
                    case .saved(let destinationURL):
                        self.saveCompletedURL = destinationURL
                        self.statusMessage = "Saved \(destinationURL.lastPathComponent)"
                        self.isClosed = true
                    case .cancelled:
                        self.statusMessage = nil
                    case .failed(let message):
                        self.exportError = message
                    }
                }
            } catch {
                await MainActor.run {
                    self.isExporting = false
                    self.exportError = error.localizedDescription
                }
            }
        }
    }

    public func discard() {
        isPlaying = false
        isClosed = true
    }

    public func cancel() {
        isPlaying = false
        isClosed = true
    }
}

extension AnnotationItem {
    public var typeDescription: String {
        switch type {
        case .arrow: return "Arrow"
        case .rectangle: return "Rectangle"
        case .ellipse: return "Ellipse"
        case .text: return "Text"
        case .highlighter: return "Highlighter"
        case .redaction: return "Redaction"
        }
    }
}
