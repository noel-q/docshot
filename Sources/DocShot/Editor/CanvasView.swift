import SwiftUI
import AppKit

public struct CanvasView: View {
    @ObservedObject var viewModel: EditorViewModel
    
    @State private var activeDragStart: CGPoint?
    @State private var lastDragLocation: CGPoint?
    @State private var preMoveItemState: AnnotationItem?
    @State private var freehandPoints: [CGPoint] = []
    @State private var editingTextID: UUID?
    @State private var textInputBuffer: String = ""
    @FocusState private var isTextFieldFocused: Bool
    
    public init(viewModel: EditorViewModel) {
        self.viewModel = viewModel
    }
    
    private var imageWidth: CGFloat { CGFloat(viewModel.baseImage.width) }
    private var imageHeight: CGFloat { CGFloat(viewModel.baseImage.height) }
    
    public var body: some View {
        GeometryReader { geometry in
            let canvasScale = min(geometry.size.width / imageWidth, geometry.size.height / imageHeight, 1.0)
            let displayedWidth = imageWidth * canvasScale
            let displayedHeight = imageHeight * canvasScale
            
            ZStack {
                Color(nsColor: .windowBackgroundColor)
                    .ignoresSafeArea()
                
                // Base Image
                ZStack(alignment: .topLeading) {
                    Image(nsImage: NSImage(cgImage: viewModel.baseImage, size: NSSize(width: imageWidth, height: imageHeight)))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(width: displayedWidth, height: displayedHeight)
                        .shadow(color: .black.opacity(0.2), radius: 10, x: 0, y: 4)
                    
                    // Render Redactions
                    ForEach(viewModel.annotations) { item in
                        if case .redaction(let rect, let style) = item.type {
                            let norm = DisplayGeometry.normalizeRect(rect)
                            Rectangle()
                                .fill(style == .blur ? Color.gray.opacity(0.85) : Color.black.opacity(0.9))
                                .overlay(
                                    Text(style == .blur ? "BLURRED" : "REDACTED")
                                        .font(.system(size: 10, weight: .bold, design: .monospaced))
                                        .foregroundColor(.white.opacity(0.7))
                                )
                                .frame(width: norm.width * canvasScale, height: norm.height * canvasScale)
                                .position(
                                    x: (norm.origin.x + norm.width / 2) * canvasScale,
                                    y: (norm.origin.y + norm.height / 2) * canvasScale
                                )
                        }
                    }
                    
                    // Render Vector Annotations
                    ForEach(viewModel.annotations) { item in
                        renderAnnotationItem(item, canvasScale: canvasScale)
                    }
                    
                    // Active drawing preview shape
                    if let start = activeDragStart, let current = lastDragLocation {
                        renderActiveDrawingShape(start: start, current: current, canvasScale: canvasScale)
                    }
                    
                    // Inline Text Editor Overlay
                    if let textID = editingTextID,
                       let item = viewModel.annotations.first(where: { $0.id == textID }),
                       case .text(let rect, _, let fontSize) = item.type {
                        let norm = DisplayGeometry.normalizeRect(rect)
                        TextField("Type text...", text: $textInputBuffer, onCommit: {
                            commitTextEdit(id: textID, text: textInputBuffer)
                        })
                        .textFieldStyle(.plain)
                        .focused($isTextFieldFocused)
                        .font(.system(size: fontSize * canvasScale, weight: .bold))
                        .foregroundColor(item.color.swiftUIColor)
                        .padding(4)
                        .background(Color.white.opacity(0.9))
                        .cornerRadius(4)
                        .frame(width: max(norm.width * canvasScale, 100), height: max(norm.height * canvasScale, 30))
                        .position(
                            x: (norm.origin.x + norm.width / 2) * canvasScale,
                            y: (norm.origin.y + norm.height / 2) * canvasScale
                        )
                        .onAppear {
                            // A text annotation is immediately editable; requiring
                            // a second click made typing appear to do nothing.
                            DispatchQueue.main.async {
                                isTextFieldFocused = true
                            }
                        }
                    }
                    
                    // Crop Box Overlay
                    if let crop = viewModel.cropRect {
                        let norm = DisplayGeometry.normalizeRect(crop)
                        Rectangle()
                            .stroke(Color.yellow, style: StrokeStyle(lineWidth: 2, dash: [6]))
                            .frame(width: norm.width * canvasScale, height: norm.height * canvasScale)
                            .position(
                                x: (norm.origin.x + norm.width / 2) * canvasScale,
                                y: (norm.origin.y + norm.height / 2) * canvasScale
                            )
                    }
                }
                .frame(width: displayedWidth, height: displayedHeight)
                .contentShape(Rectangle())
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            guard editingTextID == nil else { return }
                            let locInImage = CGPoint(
                                x: value.location.x / canvasScale,
                                y: value.location.y / canvasScale
                            )
                            let startInImage = CGPoint(
                                x: value.startLocation.x / canvasScale,
                                y: value.startLocation.y / canvasScale
                            )
                            
                            if activeDragStart == nil {
                                activeDragStart = startInImage
                                lastDragLocation = startInImage
                                
                                if viewModel.activeTool == .select {
                                    // Hit test to select annotation and capture initial state
                                    let hitItem = viewModel.annotations.last(where: { $0.boundingBox.contains(startInImage) })
                                    viewModel.selectedAnnotationID = hitItem?.id
                                    preMoveItemState = hitItem
                                } else if viewModel.activeTool == .highlighter {
                                    freehandPoints = [startInImage]
                                }
                            }
                            
                            let prev = lastDragLocation ?? startInImage
                            let stepDelta = CGSize(width: locInImage.x - prev.x, height: locInImage.y - prev.y)
                            lastDragLocation = locInImage
                            
                            if viewModel.activeTool == .highlighter {
                                freehandPoints.append(locInImage)
                            } else if viewModel.activeTool == .select, let selectedID = viewModel.selectedAnnotationID {
                                viewModel.translateAnnotationLive(id: selectedID, delta: stepDelta)
                            }
                        }
                        .onEnded { value in
                            defer {
                                activeDragStart = nil
                                lastDragLocation = nil
                                preMoveItemState = nil
                                freehandPoints.removeAll()
                            }
                            
                            guard let start = activeDragStart, let current = lastDragLocation else { return }
                            let minX = min(start.x, current.x)
                            let minY = min(start.y, current.y)
                            let width = abs(current.x - start.x)
                            let height = abs(current.y - start.y)
                            let shapeRect = CGRect(x: minX, y: minY, width: width, height: height)
                            
                            switch viewModel.activeTool {
                            case .select:
                                if let selectedID = viewModel.selectedAnnotationID,
                                   let initial = preMoveItemState,
                                   let currentItem = viewModel.annotations.first(where: { $0.id == selectedID }) {
                                    viewModel.commitMoveAnnotation(id: selectedID, from: initial, to: currentItem)
                                }
                                
                            case .arrow:
                                if width > 5 || height > 5 {
                                    let item = AnnotationItem(
                                        type: .arrow(start: start, end: current),
                                        color: viewModel.selectedColor,
                                        strokeWidth: viewModel.selectedStrokeWidth
                                    )
                                    viewModel.addAnnotation(item)
                                }
                                
                            case .rectangle:
                                if width > 5 && height > 5 {
                                    let item = AnnotationItem(
                                        type: .rectangle(rect: shapeRect, isFilled: false),
                                        color: viewModel.selectedColor,
                                        strokeWidth: viewModel.selectedStrokeWidth
                                    )
                                    viewModel.addAnnotation(item)
                                }
                                
                            case .ellipse:
                                if width > 5 && height > 5 {
                                    let item = AnnotationItem(
                                        type: .ellipse(rect: shapeRect, isFilled: false),
                                        color: viewModel.selectedColor,
                                        strokeWidth: viewModel.selectedStrokeWidth
                                    )
                                    viewModel.addAnnotation(item)
                                }
                                
                            case .text:
                                let initialRect = CGRect(x: start.x, y: start.y, width: max(width, 120), height: max(height, 40))
                                let item = AnnotationItem(
                                    type: .text(rect: initialRect, text: "", fontSize: 24.0),
                                    color: viewModel.selectedColor,
                                    strokeWidth: viewModel.selectedStrokeWidth
                                )
                                viewModel.addAnnotation(item)
                                editingTextID = item.id
                                textInputBuffer = ""
                                
                            case .highlighter:
                                if freehandPoints.count > 1 {
                                    let item = AnnotationItem(
                                        type: .highlighter(points: freehandPoints),
                                        color: viewModel.selectedColor,
                                        strokeWidth: viewModel.selectedStrokeWidth
                                    )
                                    viewModel.addAnnotation(item)
                                }
                                
                            case .redaction:
                                if width > 5 && height > 5 {
                                    let item = AnnotationItem(
                                        type: .redaction(rect: shapeRect, style: viewModel.redactionStyle),
                                        color: .black,
                                        strokeWidth: 0
                                    )
                                    viewModel.addAnnotation(item)
                                }
                                
                            case .crop:
                                if width > 20 && height > 20 {
                                    viewModel.setCropRect(shapeRect)
                                }
                            }
                        }
                )
            }
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
    }
    
    private func commitTextEdit(id: UUID, text: String) {
        if let index = viewModel.annotations.firstIndex(where: { $0.id == id }),
           case .text(let rect, _, let fontSize) = viewModel.annotations[index].type {
            var item = viewModel.annotations[index]
            item.type = .text(rect: rect, text: text, fontSize: fontSize)
            viewModel.updateAnnotation(item)
        }
        editingTextID = nil
    }
    
    @ViewBuilder
    private func renderAnnotationItem(_ item: AnnotationItem, canvasScale: CGFloat) -> some View {
        let isSelected = (item.id == viewModel.selectedAnnotationID)
        
        Group {
            switch item.type {
            case .arrow(let start, let end):
                ZStack {
                    arrowShaft(start: start, end: end, canvasScale: canvasScale)
                        .stroke(item.color.swiftUIColor, style: StrokeStyle(lineWidth: item.strokeWidth * canvasScale, lineCap: .round))
                    arrowHead(start: start, end: end, strokeWidth: item.strokeWidth, canvasScale: canvasScale)
                        .fill(item.color.swiftUIColor)
                }
                
            case .rectangle(let rect, let isFilled):
                let norm = DisplayGeometry.normalizeRect(rect)
                Rectangle()
                    .fill(isFilled ? item.color.swiftUIColor : Color.clear)
                    .overlay(Rectangle().stroke(item.color.swiftUIColor, lineWidth: item.strokeWidth * canvasScale))
                    .frame(width: norm.width * canvasScale, height: norm.height * canvasScale)
                    .position(
                        x: (norm.origin.x + norm.width / 2) * canvasScale,
                        y: (norm.origin.y + norm.height / 2) * canvasScale
                    )
                
            case .ellipse(let rect, let isFilled):
                let norm = DisplayGeometry.normalizeRect(rect)
                Ellipse()
                    .fill(isFilled ? item.color.swiftUIColor : Color.clear)
                    .overlay(Ellipse().stroke(item.color.swiftUIColor, lineWidth: item.strokeWidth * canvasScale))
                    .frame(width: norm.width * canvasScale, height: norm.height * canvasScale)
                    .position(
                        x: (norm.origin.x + norm.width / 2) * canvasScale,
                        y: (norm.origin.y + norm.height / 2) * canvasScale
                    )
                
            case .text(let rect, let text, let fontSize):
                let norm = DisplayGeometry.normalizeRect(rect)
                Text(text)
                    .font(.system(size: fontSize * canvasScale, weight: .bold))
                    .foregroundColor(item.color.swiftUIColor)
                    .frame(width: norm.width * canvasScale, height: norm.height * canvasScale, alignment: .topLeading)
                    .position(
                        x: (norm.origin.x + norm.width / 2) * canvasScale,
                        y: (norm.origin.y + norm.height / 2) * canvasScale
                    )
                
            case .highlighter(let points):
                if points.count > 1 {
                    Path { path in
                        path.move(to: CGPoint(x: points[0].x * canvasScale, y: points[0].y * canvasScale))
                        for p in points.dropFirst() {
                            path.addLine(to: CGPoint(x: p.x * canvasScale, y: p.y * canvasScale))
                        }
                    }
                    .stroke(item.color.swiftUIColor.opacity(0.4), style: StrokeStyle(lineWidth: item.strokeWidth * 2.5 * canvasScale, lineCap: .round, lineJoin: .round))
                }
                
            case .redaction:
                EmptyView()
            }
        }
        .overlay(
            isSelected ?
                Rectangle()
                    .stroke(Color.blue, style: StrokeStyle(lineWidth: 1.5, dash: [4]))
                    .frame(width: item.boundingBox.width * canvasScale + 6, height: item.boundingBox.height * canvasScale + 6)
                    .position(
                        x: (item.boundingBox.origin.x + item.boundingBox.width / 2) * canvasScale,
                        y: (item.boundingBox.origin.y + item.boundingBox.height / 2) * canvasScale
                    )
                : nil
        )
    }
    
    @ViewBuilder
    private func renderActiveDrawingShape(start: CGPoint, current: CGPoint, canvasScale: CGFloat) -> some View {
        let minX = min(start.x, current.x)
        let minY = min(start.y, current.y)
        let width = abs(current.x - start.x)
        let height = abs(current.y - start.y)
        
        switch viewModel.activeTool {
        case .arrow:
            ZStack {
                arrowShaft(start: start, end: current, canvasScale: canvasScale)
                    .stroke(viewModel.selectedColor.swiftUIColor, style: StrokeStyle(lineWidth: viewModel.selectedStrokeWidth * canvasScale, lineCap: .round))
                arrowHead(start: start, end: current, strokeWidth: viewModel.selectedStrokeWidth, canvasScale: canvasScale)
                    .fill(viewModel.selectedColor.swiftUIColor)
            }
            
        case .rectangle:
            Rectangle()
                .stroke(viewModel.selectedColor.swiftUIColor, lineWidth: viewModel.selectedStrokeWidth * canvasScale)
                .frame(width: width * canvasScale, height: height * canvasScale)
                .position(x: (minX + width / 2) * canvasScale, y: (minY + height / 2) * canvasScale)
            
        case .ellipse:
            Ellipse()
                .stroke(viewModel.selectedColor.swiftUIColor, lineWidth: viewModel.selectedStrokeWidth * canvasScale)
                .frame(width: width * canvasScale, height: height * canvasScale)
                .position(x: (minX + width / 2) * canvasScale, y: (minY + height / 2) * canvasScale)
            
        case .redaction:
            Rectangle()
                .fill(Color.gray.opacity(0.5))
                .overlay(Rectangle().stroke(Color.red, lineWidth: 1.5))
                .frame(width: width * canvasScale, height: height * canvasScale)
                .position(x: (minX + width / 2) * canvasScale, y: (minY + height / 2) * canvasScale)
            
        case .highlighter:
            if freehandPoints.count > 1 {
                Path { path in
                    path.move(to: CGPoint(x: freehandPoints[0].x * canvasScale, y: freehandPoints[0].y * canvasScale))
                    for p in freehandPoints.dropFirst() {
                        path.addLine(to: CGPoint(x: p.x * canvasScale, y: p.y * canvasScale))
                    }
                }
                .stroke(viewModel.selectedColor.swiftUIColor.opacity(0.4), style: StrokeStyle(lineWidth: viewModel.selectedStrokeWidth * 2.5 * canvasScale, lineCap: .round, lineJoin: .round))
            }
            
        default:
            EmptyView()
        }
    }

    private func arrowShaft(start: CGPoint, end: CGPoint, canvasScale: CGFloat) -> Path {
        Path { path in
            path.move(to: CGPoint(x: start.x * canvasScale, y: start.y * canvasScale))
            path.addLine(to: CGPoint(x: end.x * canvasScale, y: end.y * canvasScale))
        }
    }

    private func arrowHead(start: CGPoint, end: CGPoint, strokeWidth: CGFloat, canvasScale: CGFloat) -> Path {
        let tip = CGPoint(x: end.x * canvasScale, y: end.y * canvasScale)
        let tail = CGPoint(x: start.x * canvasScale, y: start.y * canvasScale)
        let angle = atan2(tip.y - tail.y, tip.x - tail.x)
        let headLength = max(strokeWidth * 4, 14) * canvasScale
        let headAngle = CGFloat.pi / 6
        let left = CGPoint(
            x: tip.x - headLength * cos(angle - headAngle),
            y: tip.y - headLength * sin(angle - headAngle)
        )
        let right = CGPoint(
            x: tip.x - headLength * cos(angle + headAngle),
            y: tip.y - headLength * sin(angle + headAngle)
        )

        return Path { path in
            path.move(to: tip)
            path.addLine(to: left)
            path.addLine(to: right)
            path.closeSubpath()
        }
    }
}
