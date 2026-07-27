import Foundation
import CoreGraphics

/// One piece of the source recording, placed on the timeline.
///
/// A segment never owns media of its own: it is a range into the single source MP4. Trimming and
/// splitting only move those ranges around, which is what makes the whole editor non-destructive —
/// the original file is never rewritten, and nothing is exported until the user asks.
public struct VideoSegment: Identifiable, Equatable, Sendable {
    public let id: UUID
    /// The portion of the source asset this segment plays, in source time.
    public var sourceRange: VideoTimeRange

    public init(id: UUID = UUID(), sourceRange: VideoTimeRange) {
        self.id = id
        self.sourceRange = sourceRange
    }

    public var duration: TimeInterval {
        sourceRange.duration
    }
}

/// An annotation overlay, visible for part of the recording.
///
/// The visible window is stored in **source** time, not timeline time. That is the decision that
/// makes editing behave the way people expect: an arrow points at something on screen, so when a
/// segment is trimmed, split, or reordered, the annotation stays attached to the frames it was
/// drawn over instead of sliding onto unrelated content.
///
/// `segmentID` scopes the annotation to one segment, so deleting a clip deletes its annotations and
/// the same source frames appearing twice on the timeline do not silently share overlays.
public struct VideoAnnotation: Identifiable, Equatable, Sendable {
    public let id: UUID
    public var segmentID: UUID
    public var sourceRange: VideoTimeRange
    /// Reuses the screenshot editor's annotation model unchanged: same shapes, colours, and
    /// coordinate convention (top-left origin, in source pixels).
    public var item: AnnotationItem

    public init(
        id: UUID = UUID(),
        segmentID: UUID,
        sourceRange: VideoTimeRange,
        item: AnnotationItem
    ) {
        self.id = id
        self.segmentID = segmentID
        self.sourceRange = sourceRange
        self.item = item
    }
}

/// A non-destructive edit of one completed temporary recording.
///
/// Pure value semantics throughout: every mutation is a `mutating func` on a `Equatable` struct, so
/// undo/redo is a matter of keeping snapshots (see `VideoProjectHistory`) rather than journalling
/// inverse operations. The project holds no file handles, writes nothing, and knows nothing about
/// AVFoundation; export is a separate service that reads it.
public struct VideoProject: Equatable, Sendable {
    public let sourceURL: URL
    public let sourceDuration: TimeInterval
    public let sourcePixelSize: CGSize
    public let hasSourceAudio: Bool

    public private(set) var segments: [VideoSegment]
    public private(set) var annotations: [VideoAnnotation]

    // MARK: - Creation

    public init(
        sourceURL: URL,
        sourceDuration: TimeInterval,
        sourcePixelSize: CGSize,
        hasSourceAudio: Bool,
        segments: [VideoSegment]? = nil,
        annotations: [VideoAnnotation] = []
    ) {
        self.sourceURL = sourceURL
        self.sourceDuration = sourceDuration
        self.sourcePixelSize = sourcePixelSize
        self.hasSourceAudio = hasSourceAudio
        self.segments = segments ?? [
            VideoSegment(sourceRange: VideoTimeRange(start: 0, duration: max(sourceDuration, 0)))
        ]
        self.annotations = annotations
    }

    /// Opens a finished recording for editing. The initial timeline is the whole clip, untouched.
    public init(recording: TemporaryRecording) {
        self.init(
            sourceURL: recording.url,
            sourceDuration: recording.duration,
            sourcePixelSize: recording.pixelSize,
            hasSourceAudio: recording.hasAudio
        )
    }

    // MARK: - Timeline queries

    public var timelineDuration: TimeInterval {
        segments.reduce(0) { $0 + $1.duration }
    }

    /// True when the project would export exactly the source, byte-for-byte identical in content.
    public var isUnedited: Bool {
        annotations.isEmpty
            && segments.count == 1
            && segments[0].sourceRange.start == 0
            && abs(segments[0].sourceRange.duration - sourceDuration) < 0.000_1
    }

    public func segment(id: UUID) -> VideoSegment? {
        segments.first { $0.id == id }
    }

    /// Where a segment begins on the timeline, or `nil` if it is not in this project.
    public func timelineStart(ofSegmentID id: UUID) -> TimeInterval? {
        var offset: TimeInterval = 0
        for segment in segments {
            if segment.id == id { return offset }
            offset += segment.duration
        }
        return nil
    }

    /// Which segment is playing at a timeline position, and how far into it that is.
    public func segment(atTimelineTime time: TimeInterval) -> (segment: VideoSegment, localTime: TimeInterval)? {
        guard time >= 0 else { return nil }
        var offset: TimeInterval = 0
        for segment in segments {
            if time < offset + segment.duration {
                return (segment, time - offset)
            }
            offset += segment.duration
        }
        return nil
    }

    /// The source-asset time a timeline position reads from.
    public func sourceTime(atTimelineTime time: TimeInterval) -> TimeInterval? {
        guard let (segment, localTime) = segment(atTimelineTime: time) else { return nil }
        return segment.sourceRange.start + localTime
    }

    public func annotations(forSegmentID id: UUID) -> [VideoAnnotation] {
        annotations.filter { $0.segmentID == id }
    }

    /// The overlays visible at a timeline position, in insertion order.
    ///
    /// This is the one query the exporter needs per frame, and the reason annotations are anchored
    /// in source time: the mapping is a lookup, never a re-derivation of edit history.
    public func activeAnnotations(atTimelineTime time: TimeInterval) -> [AnnotationItem] {
        guard let (segment, localTime) = segment(atTimelineTime: time) else { return [] }
        let sourceTime = segment.sourceRange.start + localTime
        return annotations
            .filter { $0.segmentID == segment.id && $0.sourceRange.contains(sourceTime) }
            .map(\.item)
    }

    // MARK: - Segment mutations

    /// Replaces a segment's source range — the trim operation.
    public mutating func trim(segmentID: UUID, to range: VideoTimeRange) throws {
        guard let index = segments.firstIndex(where: { $0.id == segmentID }) else {
            throw VideoProjectError.unknownSegment(segmentID)
        }
        guard range.isValid else { throw VideoProjectError.invalidTimeRange }
        guard range.start >= 0, range.end <= sourceDuration + Self.epsilon else {
            throw VideoProjectError.rangeOutsideSource(sourceDuration: sourceDuration)
        }

        segments[index].sourceRange = range
        // Annotations follow the content, so any part of them left outside the new range goes with
        // the frames it described. One that no longer overlaps at all is dropped.
        clipAnnotations(toSegmentAt: index)
    }

    /// Splits the segment under a timeline position in two.
    ///
    /// The leading half keeps the original segment's identity so existing selections and undo
    /// snapshots stay meaningful; the trailing half is new. Annotations are reassigned to whichever
    /// half contains the frame they start on, and clipped to it.
    @discardableResult
    public mutating func split(atTimelineTime time: TimeInterval) throws -> (leading: UUID, trailing: UUID) {
        guard let (segment, localTime) = segment(atTimelineTime: time),
              let index = segments.firstIndex(where: { $0.id == segment.id }) else {
            throw VideoProjectError.timeOutsideTimeline(timelineDuration: timelineDuration)
        }
        guard localTime >= VideoTimeRange.minimumDuration,
              segment.duration - localTime >= VideoTimeRange.minimumDuration else {
            throw VideoProjectError.splitAtSegmentBoundary
        }

        let splitSourceTime = segment.sourceRange.start + localTime
        let leadingRange = VideoTimeRange(start: segment.sourceRange.start, duration: localTime)
        let trailingRange = VideoTimeRange(
            start: splitSourceTime,
            duration: segment.sourceRange.duration - localTime
        )

        let trailing = VideoSegment(sourceRange: trailingRange)
        segments[index].sourceRange = leadingRange
        segments.insert(trailing, at: index + 1)

        for annotationIndex in annotations.indices where annotations[annotationIndex].segmentID == segment.id {
            if annotations[annotationIndex].sourceRange.start >= splitSourceTime {
                annotations[annotationIndex].segmentID = trailing.id
            }
        }
        clipAnnotations(toSegmentAt: index)
        clipAnnotations(toSegmentAt: index + 1)

        return (leading: segment.id, trailing: trailing.id)
    }

    /// Removes a segment and every annotation attached to it.
    public mutating func removeSegment(id: UUID) throws {
        guard let index = segments.firstIndex(where: { $0.id == id }) else {
            throw VideoProjectError.unknownSegment(id)
        }
        guard segments.count > 1 else { throw VideoProjectError.cannotRemoveLastSegment }

        segments.remove(at: index)
        annotations.removeAll { $0.segmentID == id }
    }

    /// Reorders a segment. Annotations are keyed by segment, so they move with it.
    public mutating func moveSegment(id: UUID, toIndex destination: Int) throws {
        guard let index = segments.firstIndex(where: { $0.id == id }) else {
            throw VideoProjectError.unknownSegment(id)
        }
        guard destination >= 0, destination < segments.count else {
            throw VideoProjectError.invalidSegmentPosition
        }
        guard destination != index else { return }

        let segment = segments.remove(at: index)
        segments.insert(segment, at: destination)
    }

    // MARK: - Annotation mutations

    public mutating func addAnnotation(_ annotation: VideoAnnotation) throws {
        guard let segment = segment(id: annotation.segmentID) else {
            throw VideoProjectError.unknownSegment(annotation.segmentID)
        }
        guard annotation.sourceRange.isValid else { throw VideoProjectError.invalidTimeRange }
        guard annotation.sourceRange.intersects(segment.sourceRange) else {
            throw VideoProjectError.annotationOutsideSegment
        }

        annotations.append(annotation)
    }

    public mutating func removeAnnotation(id: UUID) throws {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else {
            throw VideoProjectError.unknownAnnotation(id)
        }
        annotations.remove(at: index)
    }

    /// Retimes an annotation within its current segment.
    public mutating func moveAnnotation(id: UUID, to range: VideoTimeRange) throws {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else {
            throw VideoProjectError.unknownAnnotation(id)
        }
        guard let segment = segment(id: annotations[index].segmentID) else {
            throw VideoProjectError.unknownSegment(annotations[index].segmentID)
        }
        guard range.isValid else { throw VideoProjectError.invalidTimeRange }
        guard range.intersects(segment.sourceRange) else {
            throw VideoProjectError.annotationOutsideSegment
        }

        annotations[index].sourceRange = range
    }

    /// Moves an annotation to another segment, retiming it at the same time.
    public mutating func moveAnnotation(id: UUID, toSegmentID segmentID: UUID, range: VideoTimeRange) throws {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else {
            throw VideoProjectError.unknownAnnotation(id)
        }
        guard let segment = segment(id: segmentID) else {
            throw VideoProjectError.unknownSegment(segmentID)
        }
        guard range.isValid else { throw VideoProjectError.invalidTimeRange }
        guard range.intersects(segment.sourceRange) else {
            throw VideoProjectError.annotationOutsideSegment
        }

        annotations[index].segmentID = segmentID
        annotations[index].sourceRange = range
    }

    /// Repositions an annotation's drawing without touching its timing.
    public mutating func translateAnnotation(id: UUID, by delta: CGSize) throws {
        guard let index = annotations.firstIndex(where: { $0.id == id }) else {
            throw VideoProjectError.unknownAnnotation(id)
        }
        annotations[index].item.translate(by: delta)
    }

    // MARK: - Internals

    private static let epsilon: TimeInterval = 0.000_1

    /// Clips every annotation on a segment to that segment's source range, dropping any that no
    /// longer overlap it. Derived clipping is allowed to produce ranges below the authoring
    /// minimum: the alternative is deleting an overlay the user never asked to remove.
    private mutating func clipAnnotations(toSegmentAt index: Int) {
        let segment = segments[index]
        annotations = annotations.compactMap { annotation in
            guard annotation.segmentID == segment.id else { return annotation }
            guard let clipped = annotation.sourceRange.intersection(segment.sourceRange) else {
                return nil
            }
            var updated = annotation
            updated.sourceRange = clipped
            return updated
        }
    }
}

/// Snapshot-based undo/redo.
///
/// `VideoProject` is a value, so the cheapest correct history is a stack of whole projects: there
/// are no inverse operations to get wrong, and a rejected mutation never enters the history at all.
public struct VideoProjectHistory: Equatable, Sendable {
    public private(set) var current: VideoProject
    private var undoStack: [VideoProject] = []
    private var redoStack: [VideoProject] = []

    /// How many snapshots to keep. A recording editor holds far fewer edits than a document editor.
    public let limit: Int

    public init(_ project: VideoProject, limit: Int = 50) {
        self.current = project
        self.limit = limit
    }

    public var canUndo: Bool { !undoStack.isEmpty }
    public var canRedo: Bool { !redoStack.isEmpty }

    /// Applies a mutation, recording an undo step only if it succeeded and actually changed
    /// something. A throwing mutation leaves both the project and the history untouched.
    public mutating func perform(_ mutation: (inout VideoProject) throws -> Void) rethrows {
        var candidate = current
        try mutation(&candidate)
        guard candidate != current else { return }

        undoStack.append(current)
        if undoStack.count > limit {
            undoStack.removeFirst(undoStack.count - limit)
        }
        redoStack.removeAll()
        current = candidate
    }

    @discardableResult
    public mutating func undo() -> Bool {
        guard let previous = undoStack.popLast() else { return false }
        redoStack.append(current)
        current = previous
        return true
    }

    @discardableResult
    public mutating func redo() -> Bool {
        guard let next = redoStack.popLast() else { return false }
        undoStack.append(current)
        current = next
        return true
    }
}
