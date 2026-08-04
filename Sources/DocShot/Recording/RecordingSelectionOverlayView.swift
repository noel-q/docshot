import SwiftUI
import AppKit

/// The recording selection overlay: hover a window or drag a region, then confirm.
///
/// It mirrors the screenshot overlay's interaction and coordinate handling, but is a separate
/// view owned by `RecordingCoordinator`. It draws no colour readout and takes no display
/// snapshots — recording has no use for either, and skipping them keeps the selection cheap.
struct RecordingSelectionOverlayView: View {
    @ObservedObject var coordinator: RecordingCoordinator
    let screenFrame: CGRect
    let mainScreenHeight: CGFloat

    @State private var dragStartPoint: CGPoint?
    @State private var currentDragPoint: CGPoint?

    private var isAwaitingConfirmation: Bool {
        if case .awaitingConfirmation = coordinator.state { return true }
        return false
    }

    private var activeSelectionLocalRect: CGRect? {
        guard let start = dragStartPoint, let current = currentDragPoint else { return nil }
        return CGRect(
            x: min(start.x, current.x),
            y: min(start.y, current.y),
            width: abs(current.x - start.x),
            height: abs(current.y - start.y)
        )
    }

    private func localRect(forCG cgRect: CGRect) -> CGRect {
        let cocoaGlobal = DisplayGeometry.cgToCocoaRect(cgRect, mainScreenHeight: mainScreenHeight)
        return localRect(forCocoa: cocoaGlobal)
    }

    private func localRect(forCocoa cocoaRect: CGRect) -> CGRect {
        DisplayGeometry.cocoaToOverlayLocalRect(cocoaRect, screenFrame: screenFrame)
    }

    var body: some View {
        ZStack(alignment: .top) {
            Color.black.opacity(0.35)
                .ignoresSafeArea()

            if let pendingRect = coordinator.pendingSelectionCocoaRect, isAwaitingConfirmation {
                confirmationLayer(localRect(forCocoa: pendingRect))
            } else {
                selectionLayer
            }

            banner
        }
        .contentShape(Rectangle())
        .modifier(SelectionDragModifier(isEnabled: !isAwaitingConfirmation) { phase in
            switch phase {
            case .changed(let start, let location):
                if dragStartPoint == nil { dragStartPoint = start }
                currentDragPoint = location
            case .ended(let start, let end):
                dragStartPoint = nil
                currentDragPoint = nil
                finishDrag(from: start, to: end)
            }
        })
    }

    // MARK: - Layers

    @ViewBuilder
    private var selectionLayer: some View {
        if activeSelectionLocalRect == nil, let window = coordinator.hoveredWindow {
            let windowRect = localRect(forCG: window.boundsInCG)
            ZStack {
                Rectangle()
                    .fill(Color.red.opacity(0.10))
                    .frame(width: windowRect.width, height: windowRect.height)
                    .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.red, lineWidth: 2.5))
                    .position(x: windowRect.midX, y: windowRect.midY)

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
                .overlay(Capsule().stroke(Color.red.opacity(0.5), lineWidth: 1))
                .position(x: windowRect.midX, y: max(windowRect.minY - 24, 30))
            }
        }

        if let dragRect = activeSelectionLocalRect {
            ZStack {
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: max(dragRect.width, 1), height: max(dragRect.height, 1))
                    .overlay(Rectangle().stroke(Color.red, lineWidth: 2))
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
    }

    @ViewBuilder
    private func confirmationLayer(_ rect: CGRect) -> some View {
        // Only the overlay covering the selection shows the control; the others just dim.
        let intersectsThisScreen = rect.maxX > 0 && rect.maxY > 0
            && rect.minX < screenFrame.width && rect.minY < screenFrame.height

        if intersectsThisScreen {
            ZStack {
                Rectangle()
                    .fill(Color.clear)
                    .frame(width: max(rect.width, 1), height: max(rect.height, 1))
                    .overlay(Rectangle().stroke(Color.red, lineWidth: 2.5))
                    .position(x: rect.midX, y: rect.midY)

                RecordingConfirmationView(
                    sizeText: "\(Int(rect.width)) × \(Int(rect.height)) px",
                    audioText: coordinator.selectedAudioDescription,
                    onRecord: { coordinator.confirmRecord() },
                    onCancel: { coordinator.confirmCancel() }
                )
                .position(x: rect.midX, y: max(rect.minY - 30, 34))
            }
        }
    }

    @ViewBuilder
    private var banner: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                Image(systemName: "record.circle")
                    .font(.system(size: 13, weight: .bold))
                Text(isAwaitingConfirmation
                     ? "Press Record to start, or Cancel"
                     : "Click a window or drag a region to record")
                    .font(.system(size: 13, weight: .medium, design: .rounded))
                Text("•")
                    .foregroundColor(.secondary)
                Text("Esc to cancel")
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.7))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)
            .background(
                Capsule()
                    .fill(Color.black.opacity(0.8))
                    .shadow(color: .black.opacity(0.3), radius: 8, x: 0, y: 4)
            )

            if !isAwaitingConfirmation {
                Text("Regions must stay within a single display. \(coordinator.selectedAudioDescription).")
                    .font(.system(size: 11))
                    .foregroundColor(.white.opacity(0.65))
            }

            if let notice = coordinator.noticeMessage {
                Text(notice)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Capsule().fill(Color.red.opacity(0.85)))
            }
        }
        .padding(.top, 40)
    }

    // MARK: - Selection

    private func finishDrag(from start: CGPoint, to end: CGPoint) {
        let width = abs(end.x - start.x)
        let height = abs(end.y - start.y)

        if width < 5 && height < 5 {
            if let window = coordinator.hoveredWindow {
                coordinator.selectWindow(window)
            }
            return
        }

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
        coordinator.selectRegion(cocoaRegion)
    }
}

/// Attaches the selection drag gesture only while selection is live, so the confirmation
/// control's own buttons stay clickable.
private struct SelectionDragModifier: ViewModifier {
    enum Phase {
        case changed(start: CGPoint, location: CGPoint)
        case ended(start: CGPoint, end: CGPoint)
    }

    let isEnabled: Bool
    let onPhase: (Phase) -> Void

    func body(content: Content) -> some View {
        if isEnabled {
            content.gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        onPhase(.changed(start: value.startLocation, location: value.location))
                    }
                    .onEnded { value in
                        onPhase(.ended(start: value.startLocation, end: value.location))
                    }
            )
        } else {
            content
        }
    }
}
