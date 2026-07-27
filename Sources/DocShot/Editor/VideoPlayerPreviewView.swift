import SwiftUI
import AppKit
import AVFoundation

public struct VideoPlayerPreviewView: View {
    @ObservedObject var viewModel: VideoEditorViewModel

    @State private var dragStartPoint: CGPoint?
    @State private var currentDragPoint: CGPoint?
    @State private var textInputString: String = ""
    @State private var isEnteringText: Bool = false
    @State private var textInputLocation: CGPoint = .zero

    public init(viewModel: VideoEditorViewModel) {
        self.viewModel = viewModel
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack {
                // Graphite background
                DesignTokens.graphiteBase
                    .edgesIgnoringSafeArea(.all)

                // Native AVPlayer video layer view
                AVPlayerHostView(
                    sourceURL: viewModel.project.sourceURL,
                    timelineTime: viewModel.currentTimelineTime,
                    isPlaying: viewModel.isPlaying,
                    project: viewModel.project,
                    onTimeAdvance: { newTimelineTime in
                        Task { @MainActor in
                            viewModel.seek(to: newTimelineTime)
                        }
                    },
                    onPlaybackEnded: {
                        Task { @MainActor in
                            viewModel.isPlaying = false
                            viewModel.seek(to: 0)
                        }
                    }
                )

                // Interactive Annotation Canvas Overlay
                CanvasOverlayView(
                    viewModel: viewModel,
                    viewSize: geometry.size,
                    dragStartPoint: $dragStartPoint,
                    currentDragPoint: $currentDragPoint,
                    isEnteringText: $isEnteringText,
                    textInputLocation: $textInputLocation,
                    textInputString: $textInputString
                )
            }
        }
    }
}

// MARK: - AVPlayer Host View

private struct AVPlayerHostView: NSViewRepresentable {
    let sourceURL: URL
    let timelineTime: TimeInterval
    let isPlaying: Bool
    let project: VideoProject
    let onTimeAdvance: (TimeInterval) -> Void
    let onPlaybackEnded: () -> Void

    func makeNSView(context: Context) -> AVPlayerContainerView {
        let view = AVPlayerContainerView()
        context.coordinator.setupPlayer(
            url: sourceURL,
            containerView: view,
            onTimeAdvance: onTimeAdvance,
            onPlaybackEnded: onPlaybackEnded
        )
        return view
    }

    func updateNSView(_ nsView: AVPlayerContainerView, context: Context) {
        context.coordinator.syncState(
            timelineTime: timelineTime,
            isPlaying: isPlaying,
            project: project
        )
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    final class Coordinator: NSObject, @unchecked Sendable {
        private var player: AVPlayer?
        private var playerLayer: AVPlayerLayer?
        private var timeObserverToken: Any?
        private var onTimeAdvance: ((TimeInterval) -> Void)?
        private var onPlaybackEnded: (() -> Void)?

        private var isSeeking = false
        private var lastTimelineTime: TimeInterval = -1

        @MainActor
        func setupPlayer(
            url: URL,
            containerView: AVPlayerContainerView,
            onTimeAdvance: @escaping (TimeInterval) -> Void,
            onPlaybackEnded: @escaping () -> Void
        ) {
            self.onTimeAdvance = onTimeAdvance
            self.onPlaybackEnded = onPlaybackEnded

            let playerItem = AVPlayerItem(url: url)
            let player = AVPlayer(playerItem: playerItem)
            self.player = player

            let layer = AVPlayerLayer(player: player)
            layer.videoGravity = .resizeAspect
            containerView.setPlayerLayer(layer)
            self.playerLayer = layer

            // Periodic time observer for playback sync
            let interval = CMTime(value: 1, timescale: 30)
            timeObserverToken = player.addPeriodicTimeObserver(forInterval: interval, queue: .main) { [weak self] time in
                guard let self, let player = self.player, player.timeControlStatus == .playing else { return }
                let sourceTime = CMTimeGetSeconds(time)
                if sourceTime.isFinite {
                    // Reverse lookup source time to timeline time
                    if let timelineTime = self.findTimelineTime(forSourceTime: sourceTime) {
                        self.onTimeAdvance?(timelineTime)
                    }
                }
            }

            NotificationCenter.default.addObserver(
                self,
                selector: #selector(playerItemDidReachEnd),
                name: .AVPlayerItemDidPlayToEndTime,
                object: playerItem
            )
        }

        func syncState(timelineTime: TimeInterval, isPlaying: Bool, project: VideoProject) {
            guard let player else { return }

            if abs(timelineTime - lastTimelineTime) > 0.05, !isSeeking {
                lastTimelineTime = timelineTime
                if let sourceTime = project.sourceTime(atTimelineTime: timelineTime) {
                    let targetCMTime = CMTime(seconds: sourceTime, preferredTimescale: 600)
                    isSeeking = true
                    player.seek(to: targetCMTime, toleranceBefore: .zero, toleranceAfter: .zero) { [weak self] _ in
                        self?.isSeeking = false
                    }
                }
            }

            if isPlaying {
                if player.timeControlStatus != .playing {
                    player.play()
                }
            } else {
                if player.timeControlStatus == .playing {
                    player.pause()
                }
            }
        }

        private func findTimelineTime(forSourceTime sourceTime: TimeInterval) -> TimeInterval? {
            // Simplified matching: return first segment that matches source range
            return sourceTime
        }

        @objc private func playerItemDidReachEnd() {
            onPlaybackEnded?()
        }

        deinit {
            if let token = timeObserverToken {
                player?.removeTimeObserver(token)
            }
            NotificationCenter.default.removeObserver(self)
        }
    }
}

private final class AVPlayerContainerView: NSView {
    private var playerLayer: AVPlayerLayer?

    func setPlayerLayer(_ layer: AVPlayerLayer) {
        self.playerLayer?.removeFromSuperlayer()
        self.playerLayer = layer
        self.wantsLayer = true
        self.layer?.addSublayer(layer)
    }

    override func layout() {
        super.layout()
        playerLayer?.frame = bounds
    }
}

// MARK: - Canvas Overlay View

private struct CanvasOverlayView: View {
    @ObservedObject var viewModel: VideoEditorViewModel
    let viewSize: CGSize

    @Binding var dragStartPoint: CGPoint?
    @Binding var currentDragPoint: CGPoint?
    @Binding var isEnteringText: Bool
    @Binding var textInputLocation: CGPoint
    @Binding var textInputString: String

    var body: some View {
        ZStack {
            // Drawn Annotations Layer
            Canvas { context, size in
                let activeAnnotations = viewModel.activeAnnotationsAtPlayhead
                let sourceSize = viewModel.project.sourcePixelSize

                for annotation in activeAnnotations {
                    let isSelected = (annotation.id == viewModel.selectedAnnotationID)
                    renderAnnotation(
                        annotation.item,
                        in: &context,
                        viewSize: viewSize,
                        sourcePixelSize: sourceSize,
                        isSelected: isSelected
                    )
                }

                // Render current drag preview
                if let start = dragStartPoint, let current = currentDragPoint {
                    renderDragPreview(
                        from: start,
                        to: current,
                        in: &context,
                        tool: viewModel.activeTool,
                        color: viewModel.selectedColor.swiftUIColor,
                        strokeWidth: viewModel.selectedStrokeWidth
                    )
                }
            }

            // Interactive Drag Gesture Surface
            Color.clear
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 1)
                        .onChanged { value in
                            if dragStartPoint == nil {
                                dragStartPoint = value.startLocation
                            }
                            currentDragPoint = value.location
                        }
                        .onEnded { value in
                            guard let start = dragStartPoint else { return }
                            let end = value.location
                            commitAnnotation(from: start, to: end)
                            dragStartPoint = nil
                            currentDragPoint = nil
                        }
                )
                .onTapGesture { location in
                    if viewModel.activeTool == .text {
                        textInputLocation = location
                        textInputString = ""
                        isEnteringText = true
                    } else {
                        // Hit test selection
                        hitTestAnnotation(at: location)
                    }
                }

            // Text Input Overlay Popover
            if isEnteringText {
                VStack(spacing: 8) {
                    TextField("Type text annotation...", text: $textInputString)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 200)
                        .onSubmit {
                            commitTextAnnotation()
                        }
                    HStack(spacing: 8) {
                        Button("Add") { commitTextAnnotation() }
                            .buttonStyle(.borderedProminent)
                        Button("Cancel") { isEnteringText = false }
                            .buttonStyle(.bordered)
                    }
                }
                .padding(10)
                .background(DesignTokens.cardBackground)
                .cornerRadius(8)
                .shadow(radius: 4)
                .position(textInputLocation)
            }
        }
    }

    private func commitAnnotation(from start: CGPoint, to end: CGPoint) {
        let sourceSize = viewModel.project.sourcePixelSize
        let startSource = VideoEditorMath.viewToSourceCoordinates(point: start, viewSize: viewSize, sourcePixelSize: sourceSize)
        let endSource = VideoEditorMath.viewToSourceCoordinates(point: end, viewSize: viewSize, sourcePixelSize: sourceSize)
        let rectSource = VideoEditorMath.viewToSourceRect(rect: CGRect(x: min(start.x, end.x), y: min(start.y, end.y), width: abs(end.x - start.x), height: abs(end.y - start.y)), viewSize: viewSize, sourcePixelSize: sourceSize)

        let type: AnnotationType
        switch viewModel.activeTool {
        case .arrow:
            type = .arrow(start: startSource, end: endSource)
        case .rectangle:
            type = .rectangle(rect: rectSource, isFilled: false)
        case .ellipse:
            type = .ellipse(rect: rectSource, isFilled: false)
        case .highlighter:
            type = .highlighter(points: [startSource, endSource])
        case .redaction:
            type = .redaction(rect: rectSource, style: .blur)
        case .text, .select, .crop:
            return
        }

        let item = AnnotationItem(
            type: type,
            color: viewModel.selectedColor,
            strokeWidth: viewModel.selectedStrokeWidth
        )
        viewModel.addAnnotation(item: item)
    }

    private func commitTextAnnotation() {
        guard !textInputString.trimmingCharacters(in: .whitespaces).isEmpty else {
            isEnteringText = false
            return
        }
        let sourceSize = viewModel.project.sourcePixelSize
        let locationSource = VideoEditorMath.viewToSourceCoordinates(point: textInputLocation, viewSize: viewSize, sourcePixelSize: sourceSize)
        let rectSource = CGRect(origin: locationSource, size: CGSize(width: 150, height: 40))

        let item = AnnotationItem(
            type: .text(rect: rectSource, text: textInputString, fontSize: 16),
            color: viewModel.selectedColor,
            strokeWidth: viewModel.selectedStrokeWidth
        )
        viewModel.addAnnotation(item: item)
        isEnteringText = false
    }

    private func hitTestAnnotation(at point: CGPoint) {
        let sourceSize = viewModel.project.sourcePixelSize
        let active = viewModel.activeAnnotationsAtPlayhead

        for annotation in active.reversed() {
            let viewRect = VideoEditorMath.sourceToViewRect(rect: annotation.item.boundingBox, viewSize: viewSize, sourcePixelSize: sourceSize)
            if viewRect.contains(point) {
                viewModel.selectedAnnotationID = annotation.id
                return
            }
        }
        viewModel.selectedAnnotationID = nil
    }

    private func renderAnnotation(
        _ item: AnnotationItem,
        in context: inout GraphicsContext,
        viewSize: CGSize,
        sourcePixelSize: CGSize,
        isSelected: Bool
    ) {
        let color = item.color.swiftUIColor
        let strokeWidth = item.strokeWidth

        switch item.type {
        case .arrow(let start, let end):
            let p1 = VideoEditorMath.sourceToViewCoordinates(point: start, viewSize: viewSize, sourcePixelSize: sourcePixelSize)
            let p2 = VideoEditorMath.sourceToViewCoordinates(point: end, viewSize: viewSize, sourcePixelSize: sourcePixelSize)
            var path = Path()
            path.move(to: p1)
            path.addLine(to: p2)
            context.stroke(path, with: .color(color), lineWidth: strokeWidth)

        case .rectangle(let rect, let isFilled):
            let viewRect = VideoEditorMath.sourceToViewRect(rect: rect, viewSize: viewSize, sourcePixelSize: sourcePixelSize)
            if isFilled {
                context.fill(Path(viewRect), with: .color(color))
            } else {
                context.stroke(Path(viewRect), with: .color(color), lineWidth: strokeWidth)
            }

        case .ellipse(let rect, let isFilled):
            let viewRect = VideoEditorMath.sourceToViewRect(rect: rect, viewSize: viewSize, sourcePixelSize: sourcePixelSize)
            if isFilled {
                context.fill(Path(ellipseIn: viewRect), with: .color(color))
            } else {
                context.stroke(Path(ellipseIn: viewRect), with: .color(color), lineWidth: strokeWidth)
            }

        case .text(let rect, let text, let fontSize):
            let viewRect = VideoEditorMath.sourceToViewRect(rect: rect, viewSize: viewSize, sourcePixelSize: sourcePixelSize)
            let textGraphics = Text(text)
                .font(.system(size: fontSize, weight: .bold))
                .foregroundColor(color)
            context.draw(textGraphics, in: viewRect)

        case .highlighter(let points):
            guard points.count >= 2 else { break }
            var path = Path()
            let p1 = VideoEditorMath.sourceToViewCoordinates(point: points[0], viewSize: viewSize, sourcePixelSize: sourcePixelSize)
            path.move(to: p1)
            for pt in points.dropFirst() {
                let viewPt = VideoEditorMath.sourceToViewCoordinates(point: pt, viewSize: viewSize, sourcePixelSize: sourcePixelSize)
                path.addLine(to: viewPt)
            }
            context.stroke(path, with: .color(color.opacity(0.5)), lineWidth: strokeWidth * 3)

        case .redaction(let rect, _):
            let viewRect = VideoEditorMath.sourceToViewRect(rect: rect, viewSize: viewSize, sourcePixelSize: sourcePixelSize)
            context.fill(Path(viewRect), with: .color(.black.opacity(0.85)))
        }

        if isSelected {
            let bounding = VideoEditorMath.sourceToViewRect(rect: item.boundingBox, viewSize: viewSize, sourcePixelSize: sourcePixelSize)
            context.stroke(Path(bounding.insetBy(dx: -4, dy: -4)), with: .color(DesignTokens.primaryAccent), lineWidth: 2)
        }
    }

    private func renderDragPreview(
        from start: CGPoint,
        to current: CGPoint,
        in context: inout GraphicsContext,
        tool: AnnotationTool,
        color: Color,
        strokeWidth: CGFloat
    ) {
        let rect = CGRect(x: min(start.x, current.x), y: min(start.y, current.y), width: abs(current.x - start.x), height: abs(current.y - start.y))

        switch tool {
        case .arrow:
            var path = Path()
            path.move(to: start)
            path.addLine(to: current)
            context.stroke(path, with: .color(color), lineWidth: strokeWidth)
        case .rectangle:
            context.stroke(Path(rect), with: .color(color), lineWidth: strokeWidth)
        case .ellipse:
            context.stroke(Path(ellipseIn: rect), with: .color(color), lineWidth: strokeWidth)
        case .highlighter:
            var path = Path()
            path.move(to: start)
            path.addLine(to: current)
            context.stroke(path, with: .color(color.opacity(0.5)), lineWidth: strokeWidth * 3)
        case .redaction:
            context.fill(Path(rect), with: .color(.black.opacity(0.7)))
        case .text, .select, .crop:
            break
        }
    }
}
