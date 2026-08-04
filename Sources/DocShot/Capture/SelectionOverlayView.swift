import SwiftUI
import AppKit

public struct SelectionOverlayView: View {
    @ObservedObject var coordinator: CaptureCoordinator
    @ObservedObject var readout: ColorReadoutModel
    public var screenFrame: CGRect
    public var mainScreenHeight: CGFloat
    public var onCancel: () -> Void
    public var onSelectWindow: (WindowInfo) -> Void
    public var onSelectRegion: (CGRect) -> Void

    // Retain local drag state per overlay view so hosting view updates do not reset drag!
    @State private var dragStartPoint: CGPoint?
    @State private var currentDragPoint: CGPoint?

    public init(
        coordinator: CaptureCoordinator,
        readout: ColorReadoutModel,
        screenFrame: CGRect,
        mainScreenHeight: CGFloat,
        onCancel: @escaping () -> Void,
        onSelectWindow: @escaping (WindowInfo) -> Void,
        onSelectRegion: @escaping (CGRect) -> Void
    ) {
        self.coordinator = coordinator
        self.readout = readout
        self.screenFrame = screenFrame
        self.mainScreenHeight = mainScreenHeight
        self.onCancel = onCancel
        self.onSelectWindow = onSelectWindow
        self.onSelectRegion = onSelectRegion
    }
    
    private var activeSelectionLocalRect: CGRect? {
        if let start = dragStartPoint, let current = currentDragPoint {
            let minX = min(start.x, current.x)
            let maxX = max(start.x, current.x)
            let minY = min(start.y, current.y)
            let maxY = max(start.y, current.y)
            return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
        }
        return nil
    }
    
    private func localRect(for cgRect: CGRect) -> CGRect {
        let cocoaGlobal = DisplayGeometry.cgToCocoaRect(cgRect, mainScreenHeight: mainScreenHeight)
        return DisplayGeometry.cocoaToOverlayLocalRect(cocoaGlobal, screenFrame: screenFrame)
    }

    /// Fixed readout of the pixel under the cursor. Values are shown only; nothing is written
    /// to the clipboard, and no sampled colour is retained after selection ends.
    @ViewBuilder
    private var colorReadoutChip: some View {
        HStack(spacing: 10) {
            if readout.isUnavailable {
                Image(systemName: "eyedropper")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(.white.opacity(0.6))
                Text("Sampling unavailable on this display")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(.white.opacity(0.7))
            } else {
                RoundedRectangle(cornerRadius: 3)
                    .fill(readout.swatchColor ?? Color.white.opacity(0.15))
                    .frame(width: 14, height: 14)
                    .overlay(RoundedRectangle(cornerRadius: 3).stroke(Color.white.opacity(0.5), lineWidth: 1))

                Text(readout.hexText)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(.white)
                Text(readout.rgbText)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundColor(.white.opacity(0.75))
                Text(readout.hslText)
                    .font(.system(size: 11, weight: .regular, design: .monospaced))
                    .foregroundColor(.white.opacity(0.75))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(Color.black.opacity(0.8))
                .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
        )
    }

    public var body: some View {
        GeometryReader { geometry in
            ZStack(alignment: .top) {
                Color.black.opacity(0.35)
                    .ignoresSafeArea()
                
                // Smart Window Highlight (using observed coordinator.hoveredWindow)
                if activeSelectionLocalRect == nil, let window = coordinator.hoveredWindow {
                    let winRect = localRect(for: window.boundsInCG)
                    
                    ZStack {
                        Rectangle()
                            .fill(Color.blue.opacity(0.12))
                            .frame(width: winRect.width, height: winRect.height)
                            .overlay(
                                RoundedRectangle(cornerRadius: 4)
                                    .stroke(Color.blue, lineWidth: 2.5)
                            )
                            .position(x: winRect.midX, y: winRect.midY)
                        
                        VStack(spacing: 2) {
                            Text(window.ownerName + (window.title.isEmpty ? "" : ": \(window.title)"))
                                .font(.system(size: 12, weight: .bold, design: .rounded))
                                .foregroundColor(.white)
                                .lineLimit(1)
                            Text("\(Int(window.boundsInCG.width)) × \(Int(window.boundsInCG.height)) px")
                                .font(.system(size: 11, weight: .medium, design: .monospaced))
                                .foregroundColor(.white.opacity(0.8))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(Capsule().fill(Color.black.opacity(0.85)))
                        .overlay(Capsule().stroke(Color.blue.opacity(0.6), lineWidth: 1))
                        .position(x: winRect.midX, y: max(winRect.minY - 24, 30))
                    }
                }
                
                // Drag Region Highlight
                if let dragRect = activeSelectionLocalRect {
                    ZStack {
                        Rectangle()
                            .fill(Color.clear)
                            .frame(width: max(dragRect.width, 1), height: max(dragRect.height, 1))
                            .overlay(
                                Rectangle()
                                    .stroke(Color(nsColor: .controlAccentColor), lineWidth: 2)
                            )
                            .position(x: dragRect.midX, y: dragRect.midY)
                        
                        Text("\(Int(dragRect.width)) × \(Int(dragRect.height)) px")
                            .font(.system(size: 11, weight: .semibold, design: .monospaced))
                            .foregroundColor(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Capsule().fill(Color.black.opacity(0.85)))
                            .position(x: dragRect.midX, y: max(dragRect.minY - 20, 20))
                    }
                }
                
                // Instruction Banner at Top
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        Image(systemName: "viewfinder")
                            .font(.system(size: 13, weight: .bold))
                        Text("Click window or drag region to capture")
                            .font(.system(size: 13, weight: .medium, design: .rounded))
                        Text("•")
                            .foregroundColor(.secondary)
                        Text("Press Esc to cancel")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.white.opacity(0.7))
                        Text("•")
                            .foregroundColor(.secondary)
                        Text("R to refresh colours")
                            .font(.system(size: 12, weight: .regular))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.8))
                            .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
                    )

                    colorReadoutChip
                }
                .padding(.top, 40)

                // Drag-Only 11x11 Magnifier Lens (rendered only on the overlay with active drag)
                if currentDragPoint != nil, let grid = readout.magnifierGrid, let dragPt = currentDragPoint {
                    let lensPos = magnifierPosition(currentPoint: dragPt, viewSize: geometry.size)
                    MagnifierView(grid: grid)
                        .position(lensPos)
                }
            }
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        if dragStartPoint == nil {
                            dragStartPoint = value.startLocation
                        }
                        currentDragPoint = value.location
                    }
                    .onEnded { value in
                        defer {
                            dragStartPoint = nil
                            currentDragPoint = nil
                            readout.clear()
                        }
                        
                        let start = value.startLocation
                        let end = value.location
                        let width = abs(end.x - start.x)
                        let height = abs(end.y - start.y)
                        
                        if width < 5 && height < 5 {
                            if let window = coordinator.hoveredWindow {
                                onSelectWindow(window)
                            }
                        } else {
                            let localRegion = CGRect(
                                x: min(start.x, end.x),
                                y: min(start.y, end.y),
                                width: width,
                                height: height
                            )
                            let cocoaRegion = DisplayGeometry.overlayLocalToCocoaRect(
                                localRegion,
                                screenFrame: screenFrame
                            )
                            onSelectRegion(cocoaRegion)
                        }
                    }
            )
        }
    }

    private func magnifierPosition(currentPoint: CGPoint, viewSize: CGSize) -> CGPoint {
        let lensWidth = MagnifierView.renderedSize
        let lensHeight = MagnifierView.renderedSize
        let halfW = lensWidth / 2.0
        let halfH = lensHeight / 2.0
        let offset: CGFloat = 24.0

        var posX = currentPoint.x + offset + halfW
        if posX + halfW > viewSize.width {
            posX = currentPoint.x - offset - halfW
        }
        posX = max(halfW, min(viewSize.width - halfW, posX))

        var posY = currentPoint.y - offset - halfH
        if posY - halfH < 0 {
            posY = currentPoint.y + offset + halfH
        }
        posY = max(halfH, min(viewSize.height - halfH, posY))

        return CGPoint(x: posX, y: posY)
    }
}
